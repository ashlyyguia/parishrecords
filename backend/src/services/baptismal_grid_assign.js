/**
 * Assigns OCR.space words to the CV-detected grid cells and emits the row
 * shape the baptismal route serializes. Words and cells are in the SAME
 * rectified-page pixel frame (OCR ran on the image the grid came from), so a
 * word belongs to the cell whose rect contains its box centre.
 */

const { applyFillDown } = require('./baptismal_register_layout');

const GRID_KEY_TO_FIELD = {
  child_name: 'nameOfChild',
  place_and_birth_date: 'placeAndBirthDate',
  parents: 'parents',
  residents_of: 'residentsOf',
  baptism_date: 'dateOfBaptism',
  minister: 'minister',
  sponsors: 'sponsors',
  // 'no' drives lineNo (handled separately); 'l_or_ill' and 'observations'
  // are intentionally not captured.
};

function centre(word) {
  const xs = word.vertices.map((v) => v.x);
  const ys = word.vertices.map((v) => v.y);
  return {
    cx: (Math.min(...xs) + Math.max(...xs)) / 2,
    cy: (Math.min(...ys) + Math.max(...ys)) / 2,
    word,
  };
}

function inRect(cx, cy, c) {
  return cx >= c.x && cx < c.x + c.w && cy >= c.y && cy < c.y + c.h;
}

// Join a cell's words in reading order (top line then left-to-right) using a
// coarse y tolerance from the median word height.
function cellValue(words) {
  if (words.length === 0) return { value: '', confidence: 0 };
  const heights = words
    .map((w) => {
      const ys = w.vertices.map((v) => v.y);
      return Math.max(...ys) - Math.min(...ys);
    })
    .sort((a, b) => a - b);
  const tol = (heights[Math.floor(heights.length / 2)] || 20) * 0.7;
  const withC = words.map(centre);
  withC.sort((a, b) => (Math.abs(a.cy - b.cy) > tol ? a.cy - b.cy : a.cx - b.cx));
  const value = withC.map((w) => w.word.text).join(' ').replace(/\s+/g, ' ').trim();
  const confidence =
    withC.reduce((s, w) => s + (w.word.confidence || 0), 0) / withC.length;
  return { value, confidence };
}

/** Collects each page's words into `${row}:${key}` buckets. */
function bucket(page, words) {
  const cells = (page && page.cells) || [];
  const perCell = new Map();
  for (const { cx, cy, word } of (words || []).map(centre)) {
    const hit = cells.find((c) => inRect(cx, cy, c));
    if (!hit) continue;
    const k = `${hit.row}:${hit.key}`;
    if (!perCell.has(k)) perCell.set(k, []);
    perCell.get(k).push(word);
  }
  return perCell;
}

function rowIndices(page) {
  const rows = new Set();
  for (const c of (page && page.cells) || []) rows.add(c.row);
  return [...rows];
}

function gridToRows(leftPage, leftWords, rightPage, rightWords) {
  const left = bucket(leftPage, leftWords || []);
  const right = bucket(rightPage, rightWords || []);
  const indices = [...new Set([...rowIndices(leftPage), ...rowIndices(rightPage)])]
    .sort((a, b) => a - b);

  const rows = indices.map((rowIdx) => {
    const fields = {};
    for (const src of [left, right]) {
      for (const [k, words] of src) {
        const [r, key] = k.split(':');
        if (Number(r) !== rowIdx) continue;
        const fieldKey = GRID_KEY_TO_FIELD[key];
        if (!fieldKey) continue; // 'no', 'l_or_ill', 'observations'
        fields[fieldKey] = { ...cellValue(words), inherited: false };
      }
    }
    for (const fk of Object.values(GRID_KEY_TO_FIELD)) {
      if (!fields[fk]) fields[fk] = { value: '', confidence: 0, inherited: false };
    }
    const noWords = left.get(`${rowIdx}:no`) || [];
    const lineNo = cellValue(noWords).value || String(rowIdx + 1);
    return { index: rowIdx, lineNo, fields };
  });

  const { rows: filled } = applyFillDown(rows);
  return { rows: filled, warnings: [] };
}

module.exports = { GRID_KEY_TO_FIELD, gridToRows };
