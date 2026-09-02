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

/** Each page row's top y-position (min cell y), keyed by that page's own row index. */
function pageRowTops(page) {
  const tops = new Map();
  for (const c of (page && page.cells) || []) {
    if (!tops.has(c.row) || c.y < tops.get(c.row)) tops.set(c.row, c.y);
  }
  return tops;
}

function median(nums) {
  if (nums.length === 0) return 0;
  const s = [...nums].sort((a, b) => a - b);
  return s[Math.floor(s.length / 2)];
}

// The integer index offset `d` for which left row i and right row i+d are the
// same physical row.
//
// The two rectified halves are split from one photo and share a y-axis: the
// same ruled lines cross the gutter, so one physical row sits at ~the same y on
// both pages. But each page detects its own header/title bands independently --
// on a real spread the right page can catch the "Register" title AND the column
// headers as extra top rows the left page didn't, shifting every right-page row
// index down. Joining by raw index then pairs a child's name with a DIFFERENT
// entry's baptism data -- individually plausible, silently wrong. Choosing the
// offset that best lines the two pages up by y fixes that: the columns of the
// spread are joined per physical row, not per raw index. When the pages already
// agree (d = 0) nothing changes.
function rowOffset(leftTops, rightTops) {
  const li = [...leftTops.keys()].sort((a, b) => a - b);
  if (li.length < 2 || rightTops.size < 2) return 0;
  const pitch = median(li.slice(1).map((r, k) => leftTops.get(r) - leftTops.get(li[k])));
  const tol = Math.max(20, pitch * 0.6);
  let best = { d: 0, score: -1 };
  for (let d = -6; d <= 6; d += 1) {
    let score = 0;
    for (const r of li) {
      const ry = rightTops.get(r + d);
      if (ry != null && Math.abs(leftTops.get(r) - ry) <= tol) score += 1;
    }
    if (score > best.score) best = { d, score };
  }
  // Only trust a shift with real corroboration; a lone coincidental match must
  // not move an already-aligned spread.
  return best.score >= 2 ? best.d : 0;
}

// Printed labels of the register's own header band and page titles. A row whose
// text is only these is the header, not an entry.
const HEADER_WORDS = new Set([
  'no', 'name', 'names', 'of', 'child', 'place', 'date', 'birth', 'and',
  'l', 'or', 'ill', 'lor', 'parents', 'parent', 'mother', 'mothers', 'maiden',
  'residents', 'resident', 'baptism', 'minister', 'sponsors', 'sponsor',
  'observations', 'observation', 'register', 'baptismal',
]);

function tokens(s) {
  return String(s || '').toLowerCase().split(/[^a-z0-9]+/).filter(Boolean);
}

// The register number if the No. cell holds a clean small integer, else null.
// Handwritten numbers OCR poorly and the header's "No." lands here too, so this
// is deliberately strict.
function plausibleNo(s) {
  const digits = String(s || '').replace(/\D/g, '');
  if (!digits) return null;
  const n = Number(digits);
  return n >= 1 && n <= 999 ? String(n) : null;
}

// True when the child-name cell carries at least one word that is NOT a printed
// header label -- i.e. a real handwritten name, even if the merged header text
// ("Name of Child JUAN ...") happens to sit in the same cell.
function hasDataText(s) {
  return tokens(s).some((t) => t.length >= 2 && /[a-z]/.test(t) && !HEADER_WORDS.has(t));
}

function isDataRow(row) {
  if (plausibleNo(row.lineNo)) return true;
  return hasDataText(row.fields.nameOfChild && row.fields.nameOfChild.value);
}

function gridToRows(leftPage, leftWords, rightPage, rightWords) {
  const left = bucket(leftPage, leftWords || []);
  const right = bucket(rightPage, rightWords || []);

  const d = rowOffset(pageRowTops(leftPage), pageRowTops(rightPage));

  // Canonical row index = left page's own index; the matching right row is at
  // index (canonical + d).
  const canonical = new Set();
  for (const c of (leftPage && leftPage.cells) || []) canonical.add(c.row);
  for (const c of (rightPage && rightPage.cells) || []) canonical.add(c.row - d);
  const ordered = [...canonical].sort((a, b) => a - b);

  let rows = ordered.map((rowIdx) => {
    const fields = {};
    for (const [src, srcRow] of [[left, rowIdx], [right, rowIdx + d]]) {
      for (const [k, words] of src) {
        const [r, key] = k.split(':');
        if (Number(r) !== srcRow) continue;
        const fieldKey = GRID_KEY_TO_FIELD[key];
        if (!fieldKey) continue; // 'no', 'l_or_ill', 'observations'
        fields[fieldKey] = { ...cellValue(words), inherited: false };
      }
    }
    for (const fk of Object.values(GRID_KEY_TO_FIELD)) {
      if (!fields[fk]) fields[fk] = { value: '', confidence: 0, inherited: false };
    }
    const noWords = left.get(`${rowIdx}:no`) || [];
    return { index: rowIdx, lineNo: cellValue(noWords).value, fields };
  });

  // Drop the printed header/title band. It is geometrically identical to a data
  // row (same ruled height), so it can only be told apart by its text: it sits
  // above the first real entry and reads as column labels. Everything from the
  // first data row down is kept; a spread with no recognizable data row (only
  // possible in tests / a blank scan) is left untouched.
  const firstData = rows.findIndex(isDataRow);
  if (firstData > 0) rows = rows.slice(firstData);

  // Number rows by position, since the No. cell usually holds the misread "No."
  // header or nothing after a handwritten digit fails OCR. A cleanly recognized
  // register number is kept as-is.
  rows = rows.map((r, i) => ({
    ...r,
    index: i,
    lineNo: plausibleNo(r.lineNo) || String(i + 1),
  }));

  const { rows: filled } = applyFillDown(rows);
  return { rows: filled, warnings: [] };
}

module.exports = { GRID_KEY_TO_FIELD, gridToRows };
