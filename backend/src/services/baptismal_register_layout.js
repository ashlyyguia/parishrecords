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

/**
 * Locates the header band's lower boundary.
 *
 * Anchored, two-step gap sweep (same gap-sweep technique `splitSpread` uses
 * on the x-axis for the gutter, but constrained to the region it actually
 * applies to):
 *
 *  1. Find the header row's own bottom edge by matching column-header tokens
 *     directly against page words, unrestricted by position, then taking the
 *     y-level with the most matches clustered together (headers are printed
 *     on one line, so the real header row wins the vote over any lone
 *     stray/decoy word that happens to share text with a header token). This
 *     is the one thing we know for certain regardless of what else is
 *     printed on the page (a title above the headers, a page with no data
 *     rows at all, etc.) — if header tokens matched, real header text is
 *     sitting right there.
 *  2. Sweep forward from that anchor for the FIRST gap between rows of
 *     words (not the widest gap on the page). That first gap is the
 *     header-row/data-row boundary by construction, so it can't be fooled by
 *     an uneven inter-row gap further down a real handwritten register.
 *
 * Two failure modes this replaces:
 *  - A fixed top-of-page ratio (the original bug): a title sitting above the
 *    header row pulls the page's minY up, shrinking the ratio-based band
 *    below the header row itself and excluding every header.
 *  - A "widest gap anywhere" sweep: with no data rows below the header (a
 *    blank page, or one cropped tight to the header) there's no header/data
 *    gap to find, so it fell back to the same broken ratio above. And with
 *    uneven row spacing, a wide inter-row gap further down the page could
 *    beat the real (possibly narrower) header/data gap and pull the
 *    boundary into the data region.
 *
 * If no header token matches anywhere on the page, there is nothing to
 * anchor to and every column will end up unmatched regardless of where the
 * boundary sits — return `maxY` (no restriction at all) rather than guess,
 * since an overly tight guess could only make things worse.
 */
function findHeaderBandBoundary(pageWords, columnDefs, maxY) {
  const boxes = pageWords.map(boxOf);

  const hitY1s = [];
  pageWords.forEach((w, i) => {
    const text = w.text.toLowerCase().replace(/[^a-z]/g, '');
    if (!text) return;
    const isHeaderToken = columnDefs.some(
      (def) => def.header.some((t) => text === t || text.startsWith(t)),
    );
    if (isHeaderToken) hitY1s.push(boxes[i].y1);
  });

  if (hitY1s.length === 0) return maxY;

  // Printed headers all sit on the same line, so the real header row is
  // whichever y-level has the MOST header-token hits clustered together. A
  // single stray word that happens to share text with a header token (e.g.
  // a coincidental OCR misread deeper on the page) is a cluster of size one
  // and loses the vote to the real header row — using the single bottommost
  // (or topmost) hit instead would let exactly that kind of outlier drag the
  // anchor to the wrong place.
  const TOL = 8;
  hitY1s.sort((a, b) => a - b);
  let headerRowBottom = hitY1s[0];
  let bestClusterSize = 1;
  let clusterStart = 0;
  for (let i = 1; i <= hitY1s.length; i += 1) {
    if (i === hitY1s.length || hitY1s[i] - hitY1s[i - 1] > TOL) {
      const size = i - clusterStart;
      if (size > bestClusterSize) {
        bestClusterSize = size;
        headerRowBottom = hitY1s[i - 1];
      }
      clusterStart = i;
    }
  }

  const spans = boxes
    .map((b) => [b.y0, b.y1])
    .filter(([, y1]) => y1 > headerRowBottom - 0.001)
    .sort((a, b) => a[0] - b[0]);

  let cursor = headerRowBottom;
  let bestY = null;
  for (const [y0, y1] of spans) {
    if (y0 > cursor) {
      bestY = (cursor + y0) / 2;
      break; // first gap after the header row IS the header/data boundary
    }
    if (y1 > cursor) cursor = y1;
  }

  // No row found below the headers at all: nothing to exclude, so the
  // boundary can safely sit right at the header row's own bottom edge.
  return bestY !== null ? bestY : headerRowBottom;
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
  const maxY = Math.max(...boxes.map((b) => b.y1));
  const width = maxX - minX;
  const band = { headerMaxY: findHeaderBandBoundary(pageWords, columnDefs, maxY) };

  const centers = columnDefs.map((def) => {
    const found = findHeaderCenter(pageWords, def.header, band);
    return {
      key: def.key,
      center: found === null ? minX + width * def.fallbackRatio : found,
      matched: found !== null,
    };
  });

  if (centers.some((c) => !c.matched)) warnings.push('LAYOUT_UNCERTAIN');

  // Guard against inverted or zero-width bands. `columnDefs` is declared in
  // true left-to-right physical order, so matched centers (real header text)
  // are trustworthy anchors, but an unmatched column's fallback is derived
  // from page width alone — a stray outlier word (e.g. an overflowing note)
  // can inflate that width enough to push a fallback center past a correctly
  // matched neighbour, inverting the band between them. An inverted or
  // zero-width band means words that belong there match no column and
  // vanish silently, which is worse than a merely-imprecise fallback
  // position.
  //
  // The tie-breaking room for an unmatched column is strictly the interval
  // between its surrounding matched anchors (or the page's own edge, for a
  // run that starts/ends the column list) — never past them. So rather than
  // clamping each unmatched center independently and then nudging ties
  // forward (which can walk a nudge straight into the NEXT matched column
  // and corrupt a value that was read directly off the page), every maximal
  // run of adjacent unmatched columns is redistributed evenly across the
  // interval bounded by its neighbouring matched centers. This never writes
  // to a matched column's `center` — only indices inside an unmatched run
  // are ever assigned — so a matched center is always exactly what
  // calibration detected, unmodified.
  //
  // Redistributing (rather than sorting columns by position, or dropping
  // the column) is the deliberate choice here, same as before: sorting
  // could swap which KEY a band gets assigned to, silently mis-labeling a
  // column instead of just mis-sizing it; dropping the column removes its
  // band entirely, which resurrects the exact "words have nowhere to go and
  // vanish" failure this guard exists to prevent. Redistributing keeps every
  // column present with a valid, ordered, non-zero-width band.
  const MIN_GAP = 1;

  let runStart = 0;
  while (runStart < centers.length) {
    if (centers[runStart].matched) {
      runStart += 1;
      continue;
    }
    let runEnd = runStart;
    while (runEnd < centers.length && !centers[runEnd].matched) runEnd += 1;
    // Run of unmatched columns is [runStart, runEnd). Bounded by the nearest
    // matched center on each side, or the page's own bounds at an edge run.
    const runLength = runEnd - runStart;
    const lo = runStart > 0 ? centers[runStart - 1].center : minX;
    const hi = runEnd < centers.length ? centers[runEnd].center : maxX;

    if (hi - lo <= runLength * MIN_GAP) {
      // Degenerate interval (matched anchors too close together, or a
      // page-edge run with little room) — still must produce distinct,
      // strictly ascending values, so just step by MIN_GAP from lo.
      for (let k = 0; k < runLength; k += 1) {
        centers[runStart + k].center = lo + MIN_GAP * (k + 1);
      }
    } else {
      // Evenly space the run's centers across the open interval (lo, hi).
      const step = (hi - lo) / (runLength + 1);
      for (let k = 0; k < runLength; k += 1) {
        centers[runStart + k].center = lo + step * (k + 1);
      }
    }
    runStart = runEnd;
  }

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
