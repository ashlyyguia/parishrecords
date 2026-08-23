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

  // Normalised the same way every other matcher in this file normalises OCR
  // text (see findHeaderBandBoundary/findHeaderCenter's
  // `.toLowerCase().replace(/[^a-z]/g, '')`). Vision routinely attaches
  // punctuation to a word ("Baptismal," / "Register."), and an exact
  // `=== title` match rejects that -- so `confirmed` would be false on every
  // real scan, permanently showing the GUTTER_UNCONFIRMED warning and
  // desensitising the reviewer to the panel that also carries the
  // higher-severity ROW_ALIGNMENT_MISMATCH warning.
  const hasTitle = (list, title) =>
    list.some((w) => w.text.toLowerCase().replace(/[^a-z]/g, '') === title);
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
 * Matches OCR'd header text against a column header token.
 *
 * Exact match always counts. A prefix match (`text.startsWith(token)`) also
 * counts, but only when the leftover suffix is short (`MAX_HEADER_SUFFIX`
 * characters or fewer) — enough slack for real OCR noise (a trailing plural
 * "s", a stray misread character) without accepting a wholly different
 * English word that merely happens to start with a short token. Unbounded
 * `startsWith` let a fabricated non-register document (e.g. a memo
 * containing "CHILDREN", "ILLNESS", "SPONSORSHIP", "NOTICE") rack up
 * several false column-header matches purely by coincidence — 'children'
 * starts with 'child', 'illness' starts with 'ill', 'sponsorship' starts
 * with 'sponsors', 'notice' starts with 'no' — enough to clear
 * `extractBaptismalRows`'s LAYOUT_UNRECOGNIZED guard and produce a
 * fabricated extraction. Every one of those has a leftover suffix of 3+
 * characters; every genuine header token in this file matches the real
 * fixture with a leftover of 0.
 */
const MAX_HEADER_SUFFIX = 2;

function matchesHeaderToken(text, token) {
  if (text === token) return true;
  return text.startsWith(token) && text.length - token.length <= MAX_HEADER_SUFFIX;
}

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
      (def) => def.header.some((t) => matchesHeaderToken(text, t)),
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
    if (tokens.some((t) => matchesHeaderToken(text, t))) hits.push(b.cx);
  }
  if (hits.length === 0) return null;
  return hits.reduce((a, b) => a + b, 0) / hits.length;
}

/**
 * Calibrates column x-bands for one page.
 * @returns {{columns: Array<{key,x0,x1,matched}>, warnings: string[], headerMaxY: number}}
 */
function calibrateColumns(pageWords, columnDefs) {
  const warnings = [];
  if (!pageWords || pageWords.length === 0) {
    return { columns: [], warnings: ['LAYOUT_UNCERTAIN'], headerMaxY: 0 };
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
  // column present with a valid, ordered band whose width is zero only when
  // the interval it was redistributed across is itself zero-width (two
  // matched anchors that landed on the same x, or no room at a page edge) —
  // never negative.

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

    // Evenly space the run's centers across the closed interval [lo, hi].
    // This one formula covers every case, degenerate or not: `step` is never
    // negative (lo <= hi for a valid run) and every generated value is
    // `lo + step*(k+1)` for k in [0, runLength), which is always >= lo and
    // always <= hi (the largest, k = runLength-1, is hi - step <= hi). A
    // narrow interval just yields a small `step` — down to 0 when hi === lo
    // — producing coincident centers rather than distinct ones. Coincident
    // centers (a zero-width band) are an honest, acceptable result for a
    // genuinely too-narrow interval; stepping past `hi` to force distinctness
    // (the previous approach) is not, because it overshoots the next matched
    // anchor and inverts the band between them — the exact failure this
    // guard exists to prevent, just relocated instead of removed.
    const step = (hi - lo) / (runLength + 1);
    for (let k = 0; k < runLength; k += 1) {
      centers[runStart + k].center = lo + step * (k + 1);
    }
    runStart = runEnd;
  }

  // Bands are the midpoints between adjacent column centers. Centers are
  // constructed to be non-decreasing above, which makes x1 >= x0 here by
  // construction — but this is the accuracy-critical path an inverted band
  // silently drops words from, and this is the third round of finding a new
  // way to produce one. Belt and braces: clamp x1 to x0 defensively so an
  // inverted band is structurally impossible here regardless of how the
  // centers upstream were derived, now or after a future change.
  const columns = centers.map((c, i) => {
    const prev = centers[i - 1];
    const next = centers[i + 1];
    const x0 = prev ? (prev.center + c.center) / 2 : minX - 1;
    const x1raw = next ? (c.center + next.center) / 2 : maxX + 1;
    const x1 = Math.max(x1raw, x0);
    return { key: c.key, x0, x1, matched: c.matched };
  });

  return { columns, warnings, headerMaxY: band.headerMaxY };
}

/** Median box height, used to size the y-clustering tolerance. Falls back to
 * a reasonable default when there are no boxes to measure. */
function medianHeight(boxes) {
  if (boxes.length === 0) return 20;
  const hs = boxes.map((b) => b.h).sort((a, b) => a - b);
  return hs[Math.floor(hs.length / 2)] || 20;
}

/** Groups y-centers into clusters no more than `tolerance` apart. */
function clusterByY(items, tolerance) {
  const sorted = [...items].sort((a, b) => a.cy - b.cy);
  const clusters = [];
  for (const it of sorted) {
    const last = clusters[clusters.length - 1];
    if (last && it.cy - last.cy <= tolerance) {
      last.members.push(it);
      last.cy = (last.cy * (last.members.length - 1) + it.cy) / last.members.length;
    } else {
      clusters.push({ cy: it.cy, members: [it] });
    }
  }
  return clusters;
}

/**
 * Detects row y-bands.
 *
 * Primary anchor: the numerals printed in the lineNo ("NO.") column, each
 * one clustered by y-position into a single row anchor. This is trustworthy
 * because it reads the same printed sequence a human would use to find a
 * row, rather than inferring row boundaries from wherever handwritten data
 * happens to sit.
 *
 * Fallback: when no lineNo digit can be matched, clusters every word on the
 * page by y instead. This is noisier — a row with unusually wide handwriting
 * can span more than one visual cluster, or a stray mark can create a
 * spurious one — and it cannot recover a `lineNo` value. Two different
 * reasons land here, and only one of them is worth a warning:
 *  - The page has no lineNo column AT ALL (`columns` carries no `lineNo`
 *    entry — true for the right-hand page of a spread by design, since the
 *    register only prints row numbers on the left page). Falling back here
 *    is the structurally normal, expected path, not a quality problem, so
 *    it does NOT warn `ROW_ANCHOR_FALLBACK`. Warning on every scan for a
 *    page that was never going to have row numbers trains the reviewer to
 *    ignore the warnings list.
 *  - The page HAS a lineNo column but its digits are actually unreadable
 *    (smudged, cropped, or genuinely blank) — this is the case the warning
 *    exists for, and it still fires.
 *
 * Corroboration: one or more lineNo anchors is not automatically trusted at
 * face value. `anchors.length` alone can't distinguish a genuine one-row
 * page from a many-row page whose NO. column is mostly illegible except for
 * one surviving/misread digit — both yield exactly one anchor. So the
 * fallback y-clustering is always computed too (over every data word, not
 * just the NO. column) and compared against the anchor clusters: if it
 * finds MORE row-like bands than the anchors account for, the anchors are
 * treated as a sparse fragment of a bigger page rather than the whole page,
 * and the fallback's row count is used instead (still warning
 * `ROW_ANCHOR_FALLBACK`). This trades away the sparse anchors' partial
 * `lineNo` information, but the alternative — confidently returning far
 * fewer rows than the page evidently contains — silently drops real
 * baptismal records, which is worse.
 *
 * `headerMaxY` must be the boundary `calibrateColumns` already computed for
 * this same page (its returned `headerMaxY`) — recomputing it here from a
 * different signal (e.g. a fixed top-of-page ratio) is exactly the bug Task 4
 * fixed for column calibration; reusing the one true boundary keeps row
 * detection and column calibration looking at the same header/data split.
 *
 * @param {Array} pageWords - words for a single (already split) page.
 * @param {Array} columns - calibrated column bands from `calibrateColumns`.
 * @param {number} headerMaxY - header/data boundary from `calibrateColumns`.
 * @returns {{rows: Array<{index:number,lineNo:string|null,y0:number,y1:number}>, warnings: string[]}}
 */
function detectRows(pageWords, columns, headerMaxY) {
  const warnings = [];
  if (!pageWords || pageWords.length === 0) return { rows: [], warnings };

  // No silent fallback: a caller that forgets to pass calibrateColumns'
  // headerMaxY would otherwise compare every word's y against `undefined`
  // (always false), silently degrading to "every word is a row anchor
  // candidate" instead of failing loudly. That's a wrong header/data split
  // masquerading as a working one, which is worse than an explicit crash.
  if (typeof headerMaxY !== 'number' || Number.isNaN(headerMaxY)) {
    throw new Error(
      "detectRows requires the numeric headerMaxY calibrateColumns returned for this same page — got " +
        String(headerMaxY),
    );
  }

  const lineNoCol = (columns || []).find((c) => c.key === 'lineNo');
  const boxes = pageWords.map((w) => ({ ...boxOf(w), text: w.text }));
  const tolerance = medianHeight(boxes) * 0.9;

  let anchors = [];
  if (lineNoCol) {
    anchors = boxes.filter(
      (b) =>
        b.cx >= lineNoCol.x0 &&
        b.cx < lineNoCol.x1 &&
        b.cy > headerMaxY &&
        /^\d{1,3}$/.test(b.text),
    );
  }

  const dataBoxes = boxes.filter((b) => b.cy > headerMaxY);
  // Fallback y-clustering over EVERY data word, not just the NO. column.
  // This doubles as a corroborating signal for the anchor path below: a
  // register row leaves handwriting in several columns even when its NO.
  // digit is faded past recognition, so the number of row-like y-bands this
  // finds is a reasonable independent estimate of how many rows the page
  // actually has.
  const fallbackClusters = clusterByY(dataBoxes, tolerance);

  // A single legible digit is still a trustworthy anchor for a genuinely
  // one-row page — requiring two would force a page with exactly one data
  // row into the noisier fallback path and silently discard the very lineNo
  // value it correctly read. But `anchors.length` alone can't tell that
  // case apart from a many-row page whose NO. column is mostly illegible
  // except for one surviving (or misread) digit — both produce exactly one
  // anchor. Corroborate: cluster the anchors themselves and compare against
  // `fallbackClusters` computed above. If the page-wide clustering finds
  // MORE row-like bands than the anchors account for, the anchors are a
  // sparse fragment of a bigger register, not the whole page — trusting
  // them alone would silently drop every row they missed, which is exactly
  // the failure this function exists to avoid. In that case, use the
  // fallback's row count instead (lineNo unrecoverable, same as the
  // zero-anchor case) rather than confidently returning too few rows.
  let clusters;
  if (anchors.length >= 1) {
    const anchorClusters = clusterByY(anchors, tolerance);
    if (fallbackClusters.length > anchorClusters.length) {
      warnings.push('ROW_ANCHOR_FALLBACK');
      clusters = fallbackClusters.map((c) => ({ cy: c.cy, lineNo: null }));
    } else {
      clusters = anchorClusters.map((c) => ({
        cy: c.cy,
        lineNo: c.members[0].text,
      }));
    }
  } else {
    // Only warn when there was a lineNo column to expect digits from in the
    // first place. Its absence (e.g. the right page, which never prints row
    // numbers) is structurally normal, not a fallback worth flagging.
    if (lineNoCol) warnings.push('ROW_ANCHOR_FALLBACK');
    clusters = fallbackClusters.map((c) => ({ cy: c.cy, lineNo: null }));
  }

  if (clusters.length === 0) return { rows: [], warnings };

  // Row bands are the midpoints between adjacent anchors; the first and last
  // extend by half the median row pitch. With only one row there is no
  // adjacent anchor to derive a pitch from, so fall back to twice the
  // clustering tolerance as a reasonable single-row band height.
  const pitch =
    clusters.length > 1
      ? (clusters[clusters.length - 1].cy - clusters[0].cy) / (clusters.length - 1)
      : tolerance * 2;

  const rows = clusters.map((c, i) => {
    const prev = clusters[i - 1];
    const next = clusters[i + 1];
    return {
      index: i,
      lineNo: c.lineNo,
      y0: prev ? (prev.cy + c.cy) / 2 : c.cy - pitch / 2,
      y1: next ? (c.cy + next.cy) / 2 : c.cy + pitch / 2,
    };
  });

  return { rows, warnings };
}

/**
 * Assigns every word to exactly one (row, column) cell by box center.
 *
 * A word whose center falls outside every row band or every column band is
 * dropped — that is deliberate. Guessing is worse than an empty field the
 * reviewer can see and fill in. But a silently-dropped word looks identical
 * to a genuinely blank field, and a badly calibrated or badly skewed scan can
 * drop most of a page's words this way — so the count of dropped words is
 * reported back rather than swallowed, letting a caller flag a page whose
 * drop count is suspiciously high instead of trusting an all-blank result at
 * face value.
 *
 * Sub-column note: `nameOfChild`, `parents` and `sponsors` are physically two
 * sub-columns each on the printed register (e.g. `parents` is father then
 * mother), but they are calibrated and assigned here as a single band, and
 * that is NOT a placeholder for a later task -- there is no sub-column
 * split anywhere in this pipeline. Both names land in one field as a plain
 * space-joined blob (e.g. "JUAN DELA CRUZ MARIA SANTOS"), with no ` / `
 * separator and no way to tell where the father's name ends and the
 * mother's begins. `ManualRegisterNotes._parentsValue` can split an
 * already-structured `{father, mother}` map, but nothing upstream of it
 * ever produces one from OCR. Splitting correctly would require tracking
 * each sub-column's own x-range (not just the combined band), which this
 * function does not do -- see the manual verification checklist for the
 * known-limitation note and the follow-up this needs. Do NOT paper over
 * this with a crude x-midpoint split: guessing which token belongs to which
 * parent and getting it wrong (e.g. putting the mother's name in the
 * father's field) is worse than an honest, visibly-unsplit blob the
 * reviewer knows to fix by hand.
 *
 * @param {Array} pageWords - words for a single (already split) page, in the
 *   same normalized/rotated frame as the `columns` and `rows` passed in.
 * @param {Array<{key,x0,x1}>} columns - calibrated column bands from
 *   `calibrateColumns`.
 * @param {Array<{index,y0,y1}>} rows - detected row bands from `detectRows`.
 * @returns {{cells: Array<Record<string, {value: string, confidence: number}>>,
 *   dropped: number, droppedInDataRegion: number, dataWordCount: number}}
 *   `cells` has one entry per row, keyed by column key. `dropped` is the
 *   total count of words whose center fell outside every row band or every
 *   column band (header words above the first row band count here too —
 *   they legitimately have nowhere to go). `droppedInDataRegion` and
 *   `dataWordCount` narrow that same count to words at or below the first
 *   row's own top edge (`rows[0].y0`) — i.e. excluding the header/title
 *   words that are *always* dropped by construction — so a caller can build
 *   a drop ratio that isn't dominated by that fixed baseline. See
 *   `isManyWordsUnplaced` below.
 */
function assignCells(pageWords, columns, rows) {
  const cells = rows.map(() => {
    const row = {};
    for (const col of columns) row[col.key] = { words: [] };
    return row;
  });

  // Words at or below the first row's own top edge are "in the data region"
  // — plausibly real handwriting rather than the printed header/title block
  // above it. When there are no rows at all, there is no data region.
  const firstRowY0 = rows.length > 0 ? rows[0].y0 : Infinity;

  let dropped = 0;
  let droppedInDataRegion = 0;
  let dataWordCount = 0;
  for (const w of pageWords || []) {
    const b = boxOf(w);
    const inDataRegion = b.cy >= firstRowY0;
    if (inDataRegion) dataWordCount += 1;

    const rowIndex = rows.findIndex((r) => b.cy >= r.y0 && b.cy < r.y1);
    if (rowIndex === -1) {
      dropped += 1;
      if (inDataRegion) droppedInDataRegion += 1;
      continue;
    }
    const col = columns.find((c) => b.cx >= c.x0 && b.cx < c.x1);
    if (!col) {
      dropped += 1;
      // rowIndex matched, so this word is in the data region by construction
      // regardless of the `inDataRegion` check above.
      droppedInDataRegion += 1;
      continue;
    }
    cells[rowIndex][col.key].words.push({ text: w.text, confidence: w.confidence, box: b });
  }

  const outCells = cells.map((row) => {
    const out = {};
    for (const key of Object.keys(row)) {
      const items = row[key].words;
      if (items.length === 0) {
        out[key] = { value: '', confidence: 0 };
        continue;
      }
      // Reading order: group into lines by y using the same agglomerative
      // clusterByY primitive detectRows relies on (rather than a pairwise
      // |Δcy| > tolerance test inside Array.sort's comparator, which is not
      // an equivalence relation — A-same-line-as-B and B-same-line-as-C does
      // not imply A-same-line-as-C, so feeding that test straight into
      // Array.sort produces an engine-dependent order). clusterByY clusters
      // against a running cluster mean instead, which is well-defined
      // regardless of visit order. Each cluster is then sorted left-to-right,
      // and clusters are concatenated top-to-bottom by cluster mean y.
      const lineTolerance = medianHeight(items.map((i) => i.box)) * 0.7;
      const lines = clusterByY(
        items.map((it) => ({ ...it, cy: it.box.cy })),
        lineTolerance,
      );
      lines.sort((a, b) => a.cy - b.cy);
      const sorted = lines.flatMap((line) =>
        [...line.members].sort((a, b) => a.box.cx - b.box.cx),
      );
      const value = sorted.map((i) => i.text).join(' ').replace(/\s+/g, ' ').trim();
      const confidence =
        sorted.reduce((sum, i) => sum + (i.confidence || 0), 0) / sorted.length;
      out[key] = { value, confidence };
    }
    return out;
  });

  return { cells: outCells, dropped, droppedInDataRegion, dataWordCount };
}

const ALL_KEYS = [
  ...LEFT_COLUMNS.map((c) => c.key).filter((k) => k !== 'lineNo'),
  ...RIGHT_COLUMNS.map((c) => c.key),
];

const DITTO = /^(-?\s*do\s*-?|["”]|,,|-{2,})$/i;

function isEmptyCell(field) {
  const v = (field && field.value ? field.value : '').trim();
  return v === '' || DITTO.test(v);
}

/**
 * Joins left- and right-page cells into whole register rows by index.
 *
 * Index-pairing alone is not proof the two sides actually correspond to the
 * same physical row: if the left page mis-detects one extra row and the
 * right page misses one, the two row COUNTS can coincide by chance while
 * every row past the divergence point is paired with the wrong person's
 * data — the single highest-consequence failure mode here, since it means a
 * baptism record naming one child with another child's parents, sponsors
 * and date. `ROW_COUNT_MISMATCH` alone cannot catch this, because the counts
 * genuinely match.
 *
 * Both `detectRows` outputs already carry each row's `y0`/`y1` band, so a
 * pairing that's actually wrong is independently checkable: paired rows from
 * a correctly-joined spread describe the same physical strip of the page and
 * their y-bands overlap; a misaligned pairing (rows drifted out of sync)
 * will not. This never re-aligns rows on its own — silently patching the
 * pairing would hide the exact problem a reviewer needs to see — it only
 * raises `ROW_ALIGNMENT_MISMATCH` so the divergence is impossible to miss.
 */
function joinPages(leftCells, rightCells, leftRows, rightRows) {
  const warnings = [];
  const count = Math.max(leftCells.length, rightCells.length);
  if (leftCells.length !== rightCells.length) warnings.push('ROW_COUNT_MISMATCH');

  const lRows = leftRows || [];
  const rRows = rightRows || [];
  const checkable = Math.min(lRows.length, rRows.length);
  let alignmentMismatch = false;
  for (let i = 0; i < checkable; i += 1) {
    const l = lRows[i];
    const r = rRows[i];
    if (!l || !r) continue;
    if (typeof l.y0 !== 'number' || typeof l.y1 !== 'number') continue;
    if (typeof r.y0 !== 'number' || typeof r.y1 !== 'number') continue;

    // A bare intersection test (`max(y0) < min(y1)`) is too weak: row bands
    // are contiguous by construction (each band's y1 is the next band's y0),
    // so a ONE-ROW DRIFT between the two pages still intersects whenever the
    // two pages' band heights differ even slightly -- which they always do
    // in practice, since left bands are sized off small printed `NO.` digits
    // and right bands off full-width handwriting. Worked case: left anchors
    // at cy 100/200/300/400/500 give bands [50,150] [150,250] [250,350]
    // [350,450] [450,550]; a blank right-page row 2 plus a tall row 4 that
    // splits into two visual clusters gives right bands [55,205] [205,342.5]
    // [342.5,405] [405,467.5] [467.5,555]. Every index pair still intersects
    // under bare overlap, so a four-row drift (wrong baptism date, minister,
    // sponsors for four children) would sail through with an empty
    // `warnings` array.
    //
    // Comparing band CENTRES against a fraction of the smaller band's height
    // catches this: a correct join's centres agree closely (the same
    // physical row, measured two different ways), while a drifted join's
    // centres diverge by roughly half a row height or more. On the worked
    // case above, |Δcentre| at i=1 is |200 - 273.75| = 73.75, comfortably
    // past the 0.5 * min(100, 137.5) = 50 threshold.
    const centreL = (l.y0 + l.y1) / 2;
    const centreR = (r.y0 + r.y1) / 2;
    const heightL = l.y1 - l.y0;
    const heightR = r.y1 - r.y0;
    const centreDrift = Math.abs(centreL - centreR);
    const driftThreshold = 0.5 * Math.min(heightL, heightR);
    if (centreDrift > driftThreshold) {
      alignmentMismatch = true;
      break;
    }
  }
  // A row-count mismatch guarantees every row past the divergence point is
  // paired with the wrong counterpart (see the doc comment above), so it is
  // raised unconditionally alongside ROW_COUNT_MISMATCH regardless of what
  // the (necessarily incomplete) centre-drift check over just the OVERLAPPING
  // prefix found.
  if (alignmentMismatch || leftCells.length !== rightCells.length) {
    warnings.push('ROW_ALIGNMENT_MISMATCH');
  }

  const rows = [];
  for (let i = 0; i < count; i += 1) {
    const fields = {};
    for (const key of ALL_KEYS) fields[key] = { value: '', confidence: 0, inherited: false };
    Object.assign(fields, normalizeCells(leftCells[i]), normalizeCells(rightCells[i]));
    rows.push({
      index: i,
      lineNo: (leftRows && leftRows[i] && leftRows[i].lineNo) || String(i + 1),
      fields,
    });
  }
  return { rows, warnings };
}

function normalizeCells(cells) {
  if (!cells) return {};
  const out = {};
  for (const key of Object.keys(cells)) {
    if (key === 'lineNo') continue;
    out[key] = {
      value: cells[key].value,
      confidence: cells[key].confidence,
      inherited: false,
    };
  }
  return out;
}

/**
 * Carries `minister` and `dateOfBaptism` down into empty or ditto cells.
 *
 * Deliberately narrow: these are the only two columns the register repeats
 * down a batch. Every inherited value is tagged so the reviewer can see it
 * was carried, not read.
 */
function applyFillDown(rows) {
  const carried = { minister: null, dateOfBaptism: null };
  let filled = 0;

  const out = rows.map((row) => {
    const fields = { ...row.fields };
    for (const key of ['dateOfBaptism', 'minister']) {
      const field = fields[key] || { value: '', confidence: 0 };
      if (!isEmptyCell(field)) {
        carried[key] = field.value.trim();
        fields[key] = { ...field, inherited: false };
      } else if (carried[key]) {
        fields[key] = { value: carried[key], confidence: 0, inherited: true };
        filled += 1;
      } else {
        fields[key] = { ...field, inherited: false };
      }
    }
    return { ...row, fields };
  });

  return { rows: out, filled };
}

/**
 * Threshold share of a page's DATA-REGION words (see `assignCells`'s
 * `droppedInDataRegion`/`dataWordCount`) that must be dropped before
 * `MANY_WORDS_UNPLACED` is raised.
 *
 * A prior version of this ratio was computed over ALL of a page's words,
 * header/title block included. `assignCells` always counts those header
 * words as dropped (they legitimately have nowhere to go), so that ratio's
 * numerator carried a fixed ~15-word baseline while its denominator grew
 * with row count — on a sparse page (few data rows) the fixed baseline
 * dominated the total, producing false positives on perfectly clean small
 * pages (measured as high as 64% dropped on a clean 1-row fixture, comfortably
 * past any reasonable threshold). A partial/last page of a register with only
 * one or two rows is an entirely ordinary input, not an edge case to special-
 * case away.
 *
 * Restricting both the numerator and denominator to the data region (at or
 * below the first row's own top edge) removes that fixed cost entirely: a
 * cleanly calibrated page — of any row count, including one row — places
 * essentially all of its real data words into some row/column band, so the
 * ratio sits at or near 0. Reaching past 0.5 now genuinely requires half or
 * more of the page's DATA words to land nowhere, which only a real
 * calibration/skew failure produces.
 */
const MANY_WORDS_UNPLACED_RATIO = 0.5;

function isManyWordsUnplaced(dataWordCount, droppedInDataRegion) {
  return dataWordCount > 0 && droppedInDataRegion / dataWordCount > MANY_WORDS_UNPLACED_RATIO;
}

/**
 * Full pipeline: raw Vision words in, register rows out.
 * @throws {Error} with .code = 'LAYOUT_UNRECOGNIZED'
 */
function extractBaptismalRows(words) {
  const oriented = normalizeOrientation(words);
  const spread = splitSpread(oriented.words);

  const leftCal = calibrateColumns(spread.left, LEFT_COLUMNS);
  const rightCal = calibrateColumns(spread.right, RIGHT_COLUMNS);

  const leftMatched = leftCal.columns.filter((c) => c.matched).length;
  const rightMatched = rightCal.columns.filter((c) => c.matched).length;
  // A bare combined total is passable by a non-register document that
  // happens to rack up several coincidental header matches on ONE side (a
  // memo isn't laid out as a two-page register spread, so its words tend to
  // land entirely on one side of splitSpread's arbitrary gutter guess). A
  // genuine register spread always shows print on BOTH halves, so require
  // evidence on each side individually as well as the combined total.
  if (leftMatched + rightMatched < 3 || leftMatched < 1 || rightMatched < 1) {
    const err = new Error(
      'LAYOUT_UNRECOGNIZED: this does not look like a baptismal register page',
    );
    err.code = 'LAYOUT_UNRECOGNIZED';
    throw err;
  }

  const leftRows = detectRows(spread.left, leftCal.columns, leftCal.headerMaxY);
  const rightRows = detectRows(spread.right, rightCal.columns, rightCal.headerMaxY);

  const left = assignCells(spread.left, leftCal.columns, leftRows.rows);
  const right = assignCells(spread.right, rightCal.columns, rightRows.rows);

  const joined = joinPages(left.cells, right.cells, leftRows.rows, rightRows.rows);
  const { rows } = applyFillDown(joined.rows);

  const unplacedWarnings =
    isManyWordsUnplaced(left.dataWordCount, left.droppedInDataRegion) ||
    isManyWordsUnplaced(right.dataWordCount, right.droppedInDataRegion)
      ? ['MANY_WORDS_UNPLACED']
      : [];

  const warnings = [
    ...new Set([
      ...leftCal.warnings,
      ...rightCal.warnings,
      ...leftRows.warnings,
      ...rightRows.warnings,
      ...joined.warnings,
      ...unplacedWarnings,
      ...(spread.confirmed ? [] : ['GUTTER_UNCONFIRMED']),
    ]),
  ];

  return {
    rows,
    rotation: oriented.rotation,
    gutterX: spread.gutterX,
    columns: { left: leftCal.columns, right: rightCal.columns },
    warnings,
  };
}

module.exports = {
  boxOf,
  wordAngle,
  normalizeOrientation,
  splitSpread,
  LEFT_COLUMNS,
  RIGHT_COLUMNS,
  calibrateColumns,
  detectRows,
  assignCells,
  joinPages,
  applyFillDown,
  extractBaptismalRows,
};
