/**
 * Pure layout analysis for baptismal register spreads.
 *
 * Turns Vision's words-with-boxes into register rows by calibrating column
 * x-bands against the PRINTED column headers (the one thing OCR reads
 * reliably) and row y-bands against the printed NO. column.
 *
 * No I/O, no Vision types, no logging. Every function here is unit-tested
 * against synthetic fixtures in test/helpers/register_fixture.js.
 */

/** Axis-aligned bounds + center of a word's quadrilateral. */
function boxOf(word) {
  const xs = word.vertices.map((v) => v.x);
  const ys = word.vertices.map((v) => v.y);
  const x0 = Math.min(...xs);
  const x1 = Math.max(...xs);
  const y0 = Math.min(...ys);
  const y1 = Math.max(...ys);
  return {
    x0, y0, x1, y1,
    cx: (x0 + x1) / 2,
    cy: (y0 + y1) / 2,
    w: x1 - x0,
    h: y1 - y0,
  };
}

/**
 * Angle of a word's baseline, from the top-left to top-right vertex,
 * snapped to the nearest 90 degrees. Vision preserves vertex order relative
 * to the glyph, so this recovers page rotation without touching the image.
 */
function wordAngle(word) {
  const [tl, tr] = word.vertices;
  const dx = tr.x - tl.x;
  const dy = tr.y - tl.y;
  const deg = (Math.atan2(dy, dx) * 180) / Math.PI;
  const snapped = ((Math.round(deg / 90) * 90) % 360 + 360) % 360;
  return snapped;
}

function rotatePointBack(p, rotation, bounds) {
  // Inverse of the clockwise page rotation.
  switch (rotation) {
    case 90: return { x: p.y, y: bounds.maxX - p.x };
    case 180: return { x: bounds.maxX - p.x, y: bounds.maxY - p.y };
    case 270: return { x: bounds.maxY - p.y, y: p.x };
    default: return { x: p.x, y: p.y };
  }
}

/**
 * Detects page rotation from the modal word-baseline angle and rotates all
 * coordinates into an upright reading frame.
 *
 * COORDINATE CONTRACT: the returned `words` are in a normalized
 * CONTENT-RELATIVE frame, not source-image pixel coordinates. For a non-zero
 * rotation, the inverse rotation is computed against the bounding box of the
 * WORD CONTENT itself (there is no captured source page width/height to
 * invert against), so recovered coordinates are shifted from true
 * source-image pixels by the page's content margin (whatever whitespace/
 * border sits outside the outermost OCR'd words). For rotation 0, `words` is
 * returned untouched — i.e. in literal source-image coordinates — so this
 * margin offset is present for rotated pages but absent for upright ones.
 * This is fine for relative-position work (column/row calibration only cares
 * about order and spacing), but any consumer that maps a returned coordinate
 * back onto the original scanned image (e.g. to draw a highlight box) must
 * account for this margin — it is not source-image-accurate as-is.
 * @returns {{rotation: 0|90|180|270, words: Array}}
 */
function normalizeOrientation(words) {
  if (!words || words.length === 0) return { rotation: 0, words: [] };

  const tally = { 0: 0, 90: 0, 180: 0, 270: 0 };
  for (const w of words) tally[wordAngle(w)] += 1;
  const rotation = Number(
    Object.keys(tally).reduce((a, b) => (tally[a] >= tally[b] ? a : b)),
  );

  if (rotation === 0) return { rotation: 0, words };

  let maxX = 0;
  let maxY = 0;
  for (const w of words) {
    for (const v of w.vertices) {
      if (v.x > maxX) maxX = v.x;
      if (v.y > maxY) maxY = v.y;
    }
  }
  const bounds = { maxX, maxY };

  const rotated = words.map((w) => ({
    ...w,
    vertices: w.vertices.map((v) => rotatePointBack(v, rotation, bounds)),
  }));

  return { rotation, words: rotated };
}

/**
 * Splits a two-page spread at the gutter.
 *
 * The gutter is the widest vertical band in the middle third of the page
 * that no word's box crosses. Confirmed by finding the printed page titles
 * ("Baptismal" left, "Register" right).
 */
function splitSpread(words) {
  if (!words || words.length === 0) {
    return { gutterX: 0, left: [], right: [], confirmed: false };
  }

  const boxes = words.map(boxOf);
  const minX = Math.min(...boxes.map((b) => b.x0));
  const maxX = Math.max(...boxes.map((b) => b.x1));
  const searchStart = minX + (maxX - minX) / 3;
  const searchEnd = minX + ((maxX - minX) * 2) / 3;

  // Sort spans by x0 and sweep for the widest uncovered interval in range.
  const spans = boxes
    .map((b) => [b.x0, b.x1])
    .sort((a, b) => a[0] - b[0]);

  let bestGap = 0;
  let bestX = (searchStart + searchEnd) / 2;
  let cursor = spans.length ? spans[0][1] : searchStart;

  for (const [x0, x1] of spans) {
    if (x0 > cursor) {
      const gapStart = cursor;
      const gapEnd = x0;
      const mid = (gapStart + gapEnd) / 2;
      const gap = gapEnd - gapStart;
      if (mid >= searchStart && mid <= searchEnd && gap > bestGap) {
        bestGap = gap;
        bestX = mid;
      }
    }
    if (x1 > cursor) cursor = x1;
  }

  const left = [];
  const right = [];
  words.forEach((w, i) => (boxes[i].cx < bestX ? left : right).push(w));

  const hasTitle = (list, title) =>
    list.some((w) => w.text.toLowerCase() === title);
  const confirmed = hasTitle(left, 'baptismal') && hasTitle(right, 'register');

  return { gutterX: bestX, left, right, confirmed };
}

/**
 * Column descriptors. `header` tokens are matched case-insensitively against
 * PRINTED header words; `fallbackRatio` is the column center as a fraction of
 * page width, used only when the header can't be read.
 */
// Tokens must be DISTINCTIVE, not merely present in the header. 'name' would
// match both "NAME OF CHILD" and "NAME OF PARENTS", averaging the two into a
// center sitting over the birth-date column. Match on the token unique to each
// header instead.
const LEFT_COLUMNS = [
  { key: 'lineNo',            header: ['no'],                          fallbackRatio: 0.03 },
  { key: 'nameOfChild',       header: ['child'],                       fallbackRatio: 0.20 },
  { key: 'placeAndBirthDate', header: ['place', 'birth'],              fallbackRatio: 0.48 },
  { key: 'legitimacy',        header: ['ill'],                         fallbackRatio: 0.72 },
  { key: 'parents',           header: ['parents'],                     fallbackRatio: 0.88 },
];

const RIGHT_COLUMNS = [
  { key: 'residentsOf',   header: ['residents'],   fallbackRatio: 0.10 },
  { key: 'dateOfBaptism', header: ['baptism'],     fallbackRatio: 0.30 },
  { key: 'minister',      header: ['minister'],    fallbackRatio: 0.50 },
  { key: 'sponsors',      header: ['sponsors'],    fallbackRatio: 0.72 },
  { key: 'observations',  header: ['observations'],fallbackRatio: 0.92 },
];

const HEADER_BAND_RATIO = 0.25; // fallback: headers live in the top quarter of the page

/**
 * Locates the header band's lower boundary by finding the widest vertical
 * gap between rows of words on the page (same gap-sweep technique
 * `splitSpread` uses on the x-axis for the gutter).
 *
 * This is more robust than a fixed top-of-page ratio: a printed page title
 * (e.g. "Baptismal"/"Register") sitting above the column headers pulls the
 * page's minY well above the header row, which would otherwise shrink a
 * ratio-based band below the header row itself and cause every header to go
 * unmatched. The gap between the header row and the first handwritten data
 * row is reliably the widest gap near the top of the page, so sweeping for
 * it finds the header/data boundary regardless of what sits above it.
 * Falls back to the fixed ratio when no clear gap exists (e.g. too few
 * words to form distinct rows).
 */
function findHeaderBandBoundary(boxes, minY, maxY) {
  const spans = boxes.map((b) => [b.y0, b.y1]).sort((a, b) => a[0] - b[0]);

  let bestGap = 0;
  let bestY = null;
  let cursor = spans.length ? spans[0][1] : minY;

  for (const [y0, y1] of spans) {
    if (y0 > cursor) {
      const gap = y0 - cursor;
      if (gap > bestGap) {
        bestGap = gap;
        bestY = (cursor + y0) / 2;
      }
    }
    if (y1 > cursor) cursor = y1;
  }

  return bestY !== null ? bestY : minY + (maxY - minY) * HEADER_BAND_RATIO;
}

/**
 * Finds the x-center of a column header by matching its tokens among the
 * words in the page's header band. Returns null when unmatched.
 */
function findHeaderCenter(pageWords, tokens, band) {
  const hits = [];
  for (const w of pageWords) {
    const b = boxOf(w);
    if (b.cy > band.headerMaxY) continue;
    const text = w.text.toLowerCase().replace(/[^a-z]/g, '');
    if (!text) continue;
    if (tokens.some((t) => text === t || text.startsWith(t))) hits.push(b.cx);
  }
  if (hits.length === 0) return null;
  return hits.reduce((a, b) => a + b, 0) / hits.length;
}

/**
 * Calibrates column x-bands for one page.
 * @returns {{columns: Array<{key,x0,x1,matched}>, warnings: string[]}}
 */
function calibrateColumns(pageWords, columnDefs) {
  const warnings = [];
  if (!pageWords || pageWords.length === 0) {
    return { columns: [], warnings: ['LAYOUT_UNCERTAIN'] };
  }

  const boxes = pageWords.map(boxOf);
  const minX = Math.min(...boxes.map((b) => b.x0));
  const maxX = Math.max(...boxes.map((b) => b.x1));
  const minY = Math.min(...boxes.map((b) => b.y0));
  const maxY = Math.max(...boxes.map((b) => b.y1));
  const width = maxX - minX;
  const band = { headerMaxY: findHeaderBandBoundary(boxes, minY, maxY) };

  const centers = columnDefs.map((def) => {
    const found = findHeaderCenter(pageWords, def.header, band);
    return {
      key: def.key,
      center: found === null ? minX + width * def.fallbackRatio : found,
      matched: found !== null,
    };
  });

  if (centers.some((c) => !c.matched)) warnings.push('LAYOUT_UNCERTAIN');

  // Bands are the midpoints between adjacent column centers.
  const columns = centers.map((c, i) => {
    const prev = centers[i - 1];
    const next = centers[i + 1];
    const x0 = prev ? (prev.center + c.center) / 2 : minX - 1;
    const x1 = next ? (c.center + next.center) / 2 : maxX + 1;
    return { key: c.key, x0, x1, matched: c.matched };
  });

  return { columns, warnings };
}

module.exports = {
  boxOf,
  wordAngle,
  normalizeOrientation,
  splitSpread,
  LEFT_COLUMNS,
  RIGHT_COLUMNS,
  calibrateColumns,
};
