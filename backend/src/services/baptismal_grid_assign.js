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

// --- Assigning handwritten lines to entries --------------------------------
//
// A register entry is two handwritten lines in a ruled row only about two
// lines tall, so writers routinely put one of the lines ON a ruled line, or
// squeeze it into the neighbouring row: on the sample register the place of
// birth starts above its own row, and the second sponsor and the minister sit
// on the row's bottom rule. Dropping every word into the cell that contains
// its centre then splits entries, with half of each one's text in the next
// row. So words are grouped into the lines they were written on, and each
// column's lines are assigned to entries as a whole:
//
// * Date columns (place & date of birth, date of baptism): each entry's text
//   ends with a year, so the lines up to and including a year line form one
//   entry, placed in the row where that group sits most squarely.
// * Every other column: an entry holds at most COLUMN_LINE_CAP lines, so the
//   lines are spread over the rows, in order, keeping each one in or right
//   next to the row it was written in (see assignLines).

const COLUMN_LINE_CAP = 2;
const COLUMN_CAPS = { place_and_birth_date: 3, minister: 1 };
const YEAR_ENDS_ENTRY = new Set(['place_and_birth_date', 'baptism_date']);
const YEAR_RE = /\b(1[89]\d\d|20\d\d)\b/;
// How far below the table's bottom border a line may sit and still be the
// last entry's (it was written on the border), in row heights.
const BELOW_TABLE_SLACK = 0.35;
// assignLines costs, in units of "one row height away from where it was
// written"; see assignLines.
const DISTANCE_COST = 3;
const OVERFULL_COST = 1;
const EMPTY_COST = 0.4;

function wordBox(word) {
  const xs = word.vertices.map((v) => v.x);
  const ys = word.vertices.map((v) => v.y);
  return {
    x0: Math.min(...xs), x1: Math.max(...xs), y0: Math.min(...ys), y1: Math.max(...ys),
  };
}

// Words of one column, grouped into the handwritten lines they sit on.
function groupLines(words) {
  const items = words.map((word) => ({ word, box: wordBox(word) }))
    .sort((a, b) => (a.box.y0 + a.box.y1) - (b.box.y0 + b.box.y1));
  const lines = [];
  for (const it of items) {
    const h = it.box.y1 - it.box.y0;
    let joined = null;
    for (const line of lines) {
      // Compare with the line's own core (its median word), not its growing
      // extent, so two close lines never chain into one.
      const overlap = Math.min(line.cy1, it.box.y1) - Math.max(line.cy0, it.box.y0);
      if (overlap >= 0.5 * Math.min(h, line.cy1 - line.cy0)) { joined = line; break; }
    }
    if (joined) {
      joined.words.push(it.word);
      joined.y0 = Math.min(joined.y0, it.box.y0);
      joined.y1 = Math.max(joined.y1, it.box.y1);
    } else {
      lines.push({
        words: [it.word], y0: it.box.y0, y1: it.box.y1, cy0: it.box.y0, cy1: it.box.y1,
      });
    }
  }
  for (const line of lines) {
    line.cy = (line.y0 + line.y1) / 2;
    line.text = line.words.map((w) => w.text).join(' ');
  }
  return lines.sort((a, b) => a.cy - b.cy);
}

// How far (in row heights) a line's centre is outside row `r` (0 when inside).
function outside(line, r) {
  if (line.cy < r.y) return (r.y - line.cy) / r.h;
  if (line.cy > r.y + r.h) return (line.cy - r.y - r.h) / r.h;
  return 0;
}

// How squarely a line sits in a row: 0 on a rule, 0.5 dead centre, negative
// outside it.
function depth(line, r) {
  return Math.min(line.cy - r.y, r.y + r.h - line.cy) / r.h;
}

/**
 * Assign lines (top to bottom) to rows, never out of order: minimise how far
 * each line is moved from where it was written, plus a penalty per line over
 * `cap` in a row and a small one per empty row. A line written on a rule can
 * go to either side for free, so the cap decides: the second sponsor on the
 * bottom rule joins its own entry instead of overfilling the next one.
 * Returns each line's row index into `rows`.
 */
function assignLines(lines, rows, cap, yearEndsEntry = false) {
  const n = lines.length;
  const R = rows.length;
  if (n === 0 || R === 0) return [];
  const maxC = cap + 2;
  // best[i][r][c]: least cost with lines 0..i placed, line i in row r, and
  // c lines (capped at maxC) in row r so far.
  const INF = Infinity;
  const best = [];
  const from = [];
  for (let i = 0; i < n; i += 1) {
    best.push([]); from.push([]);
    for (let r = 0; r < R; r += 1) {
      best[i].push(new Array(maxC + 1).fill(INF));
      from[i].push(new Array(maxC + 1).fill(null));
    }
  }
  const lineCost = (i, r) => DISTANCE_COST * outside(lines[i], rows[r]);
  const overfill = (c) => (c > cap ? OVERFULL_COST : 0);
  for (let r = 0; r < R; r += 1) {
    best[0][r][1] = lineCost(0, r) + EMPTY_COST * r;
  }
  for (let i = 1; i < n; i += 1) {
    for (let r = 0; r < R; r += 1) {
      const lc = lineCost(i, r);
      if (lc > DISTANCE_COST * 1.5) continue;
      for (let pr = 0; pr <= r; pr += 1) {
        for (let pc = 1; pc <= maxC; pc += 1) {
          const prev = best[i - 1][pr][pc];
          if (prev === INF) continue;
          let c;
          let cost;
          if (pr === r) {
            c = Math.min(maxC, pc + 1);
            cost = prev + lc + overfill(pc + 1);
            // In a date column the year is the entry's last line; text below
            // it in the same row is the next entry's, written high.
            if (yearEndsEntry && YEAR_RE.test(lines[i - 1].text)) cost += OVERFULL_COST;
          } else {
            c = 1;
            cost = prev + lc + EMPTY_COST * (r - pr - 1);
          }
          if (cost < best[i][r][c]) {
            best[i][r][c] = cost;
            from[i][r][c] = [pr, pc];
          }
        }
      }
    }
  }
  let end = null;
  let endCost = INF;
  for (let r = 0; r < R; r += 1) {
    for (let c = 1; c <= maxC; c += 1) {
      const cost = best[n - 1][r][c] + EMPTY_COST * (R - 1 - r);
      if (cost < endCost) { endCost = cost; end = [r, c]; }
    }
  }
  const out = new Array(n);
  let cur = end;
  for (let i = n - 1; i >= 0; i -= 1) {
    out[i] = cur[0];
    cur = from[i][cur[0]][cur[1]];
  }
  return out;
}

/** Date columns: group lines up to each year line, place the group as one. */
function assignByYear(lines, rows) {
  const out = new Array(lines.length).fill(null);
  const geometric = (line) => {
    let bestR = null;
    let bestD = -Infinity;
    rows.forEach((r, idx) => {
      const d = depth(line, r);
      if (d > bestD) { bestD = d; bestR = idx; }
    });
    return bestR;
  };
  const taken = new Set();
  let start = 0;
  for (let i = 0; i < lines.length; i += 1) {
    if (!YEAR_RE.test(lines[i].text)) continue;
    const group = lines.slice(start, i + 1);
    const homes = group.map(geometric);
    // The group sits where its most squarely placed line is.
    let bestIdx = 0;
    group.forEach((line, k) => {
      if (depth(line, rows[homes[k]]) > depth(group[bestIdx], rows[homes[bestIdx]])) bestIdx = k;
    });
    const row = homes[bestIdx];
    const spread = Math.max(...homes) - Math.min(...homes);
    if (spread <= 1 && !taken.has(row)) {
      for (let k = start; k <= i; k += 1) out[k] = row;
      taken.add(row);
    } else {
      // A missed year merged two entries: keep each line where it was written.
      for (let k = start; k <= i; k += 1) out[k] = homes[k - start];
    }
    start = i + 1;
  }
  for (let k = start; k < lines.length; k += 1) out[k] = geometric(lines[k]);
  return out;
}

/** Collects each page's words into `${row}:${key}` buckets. */
function bucket(page, words) {
  const cells = (page && page.cells) || [];
  const perCell = new Map();
  const add = (row, key, word) => {
    const k = `${row}:${key}`;
    if (!perCell.has(k)) perCell.set(k, []);
    perCell.get(k).push(word);
  };

  const byKey = new Map();
  for (const c of cells) {
    if (!byKey.has(c.key)) byKey.set(c.key, []);
    byKey.get(c.key).push(c);
  }
  for (const list of byKey.values()) list.sort((a, b) => a.row - b.row);

  // Small grids (tests, partial pages) and the template-free path: plain
  // centre-point assignment.
  const rowCount = byKey.size ? Math.max(...[...byKey.values()].map((l) => l.length)) : 0;
  if (rowCount < 4) {
    for (const { cx, cy, word } of (words || []).map(centre)) {
      const hit = cells.find((c) => inRect(cx, cy, c));
      if (hit) add(hit.row, hit.key, word);
    }
    return perCell;
  }

  // Which column each word is in (by x), keeping only words inside the table
  // or just below its bottom border.
  const columnWords = new Map();
  for (const word of words || []) {
    const { cx, cy } = centre(word);
    for (const [key, list] of byKey) {
      const c0 = list[0];
      if (cx < c0.x || cx >= c0.x + c0.w) continue;
      const last = list[list.length - 1];
      if (cy < c0.y || cy > last.y + last.h * (1 + BELOW_TABLE_SLACK)) break;
      if (!columnWords.has(key)) columnWords.set(key, []);
      columnWords.get(key).push(word);
      break;
    }
  }

  for (const [key, list] of byKey) {
    const lines = groupLines(columnWords.get(key) || []);
    // The first row is the printed column header. Its own label lines stay
    // there (gridToRows drops that row); handwriting that crept up into it is
    // assigned with the entries.
    const headerCell = list[0];
    const entryRows = list.slice(1);
    const entryLines = [];
    for (const line of lines) {
      // Specks the OCR read as punctuation are not a line of writing; left in,
      // they would take an entry's place in the order.
      if (!/[A-Za-z0-9]{2}/.test(line.text)) {
        for (const w of line.words) {
          const { cx, cy } = centre(w);
          const hit = list.find((c) => inRect(cx, cy, c));
          if (hit) add(hit.row, key, w);
        }
        continue;
      }
      const isLabel = line.cy < headerCell.y + headerCell.h
        && !tokens(line.text).some((t) => /[a-z]/.test(t) && t.length >= 2 && !HEADER_WORDS.has(t));
      const deepInHeader = line.y1 < headerCell.y + headerCell.h;
      if (isLabel || deepInHeader) {
        for (const w of line.words) add(headerCell.row, key, w);
      } else {
        entryLines.push(line);
      }
    }
    const rowsOut = assignLines(
      entryLines, entryRows, COLUMN_CAPS[key] || COLUMN_LINE_CAP, YEAR_ENDS_ENTRY.has(key),
    );
    entryLines.forEach((line, i) => {
      const r = rowsOut[i];
      if (r == null) return;
      for (const w of line.words) add(entryRows[r].row, key, w);
    });
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
