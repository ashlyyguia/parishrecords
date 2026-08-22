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

module.exports = { boxOf, wordAngle, normalizeOrientation };
