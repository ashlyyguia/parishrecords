/**
 * Assigns OCR.space words to the CV-detected marriage-register grid cells and
 * emits the row shape the marriage route serializes. Words and cells share the
 * same rectified-page pixel frame, so a word belongs to the cell whose rect
 * contains its box centre.
 *
 * A marriage entry occupies TWO ruled lines within one grid row: the groom on
 * the top line, the bride on the bottom. The register's "paired" columns
 * (contracting parties, legal status, actual address, birth, baptism, parents)
 * carry one value per line, so their cell is split at the row's vertical
 * midpoint -- words above go to the groom, words below to the bride. The
 * "shared" columns (date of marriage, sponsors, minister, license, observations)
 * span both lines and take the whole cell; sponsors, though shared, are stored
 * on the groom.
 *
 * This module is a pure cell->field mapper. Header-band dropping and lineNo
 * renumbering are the route's job (see marriage_ocr_firestore.js), exactly as
 * for the baptismal pipeline.
 */

const { groupLines, assignLines } = require('./baptismal_grid_assign');

const PAIRED_LEFT = {
  contracting_parties: 'name',
  legal_status: 'legalStatus',
  actual_address: 'actualAddress',
  birth: 'datesPlaceOfBirth',
  baptism: 'datesPlaceOfBaptism',
};
const PAIRED_RIGHT = { parents: 'parents' };
const SHARED_LEFT = { marriage_date: 'dateOfMarriage' };
const SHARED_RIGHT = {
  sponsors: 'sponsors',
  minister: 'minister',
  license_no: 'licenseNumber',
  observations: 'observations',
};

function centre(w) {
  const xs = w.vertices.map((v) => v.x);
  const ys = w.vertices.map((v) => v.y);
  return {
    cx: (Math.min(...xs) + Math.max(...xs)) / 2,
    cy: (Math.min(...ys) + Math.max(...ys)) / 2,
    h: Math.max(...ys) - Math.min(...ys),
    word: w,
  };
}
function inRect(cx, cy, c) {
  return cx >= c.x && cx < c.x + c.w && cy >= c.y && cy < c.y + c.h;
}

// Reading order for a cell's words: handwritten line by line, left to right
// within a line. Sorting by centre y alone scrambled words that share a line
// but sit a few pixels apart ("REYNAN JOHN" for "JOHN REYNAN", "1990 20 JULY"
// for "20 JULY 1990"), because handwriting drifts up and down along a line. A
// word joins the current line when its centre is within half a word height of
// the line's centre.
function readingOrder(placed) {
  if (placed.length <= 1) return placed.slice();
  // Words already grouped into lines when they were placed (slope-aware, see
  // placeByColumn) keep those lines.
  if (placed.every((p) => p.lineKey != null)) {
    const byLine = new Map();
    for (const p of placed) {
      if (!byLine.has(p.lineKey)) byLine.set(p.lineKey, []);
      byLine.get(p.lineKey).push(p);
    }
    return [...byLine.values()]
      .sort((a, b) => a[0].lineCy - b[0].lineCy)
      .flatMap((g) => g.sort((a, b) => a.cx - b.cx));
  }
  const hs = placed.map((p) => p.h || 0).filter((h) => h > 0).sort((a, b) => a - b);
  const tol = 0.5 * (hs.length ? hs[Math.floor(hs.length / 2)] : 12);
  const lines = [];
  for (const p of [...placed].sort((a, b) => a.cy - b.cy)) {
    const line = lines[lines.length - 1];
    if (line && p.cy - line.cy <= tol) {
      line.items.push(p);
      line.cy = line.items.reduce((s, q) => s + q.cy, 0) / line.items.length;
    } else {
      lines.push({ cy: p.cy, items: [p] });
    }
  }
  return lines.flatMap((l) => l.items.sort((a, b) => a.cx - b.cx));
}
function joinText(placed) {
  return readingOrder(placed)
    .map((p) => p.word.text)
    .join(' ')
    .replace(/\s+/g, ' ')
    .trim();
}

// The grid's outermost columns stop at the ruled table edge, but handwriting in
// them runs past it: the date of marriage, written down the narrow last column
// of the left page, has every entry's centre beyond that column's right edge
// from about the seventh row on, so it was dropped and the field came back
// empty. Words outside the outermost columns belong to them, so widen the first
// and last columns to the page edges. Likewise the last entry's bottom line is
// often written over the table's bottom rule; take words up to a third of a row
// below it (left page only -- the right page has the priest's signature block
// under its last row).
const BELOW_TABLE_SLACK = 0.35;
function widenOuterCells(page) {
  const cells = (page && page.cells) || [];
  if (cells.length === 0) return cells;
  const minX = Math.min(...cells.map((c) => c.x));
  const maxX = Math.max(...cells.map((c) => c.x + c.w));
  const width = Number(page.width) || maxX;
  return cells.map((c) => {
    let { x, w, h } = c;
    if (x === minX) { w += x; x = 0; }
    if (x + w === maxX) w = Math.max(w, width - x);
    return { ...c, x, w, h };
  });
}

// Split a paired cell's words into the groom (top) and bride (bottom) lines.
//
// A geometric split at the cell's own vertical midpoint is fragile: the CV row
// band is often taller than the four printed lines and the text can sit low or
// high within it, so the cell midpoint cuts through one party's second line.
// Instead, cluster the words into printed lines and split at the midpoint of the
// TEXT's own vertical extent, which tracks where the ink actually is. When the
// words form a single line (one person, or two names on one line) they can't be
// separated -- all go to the groom, flagged uncertain when there are several.
function splitGroomBride(hits, cellHeight) {
  if (hits.length === 0) return { top: [], bottom: [], uncertain: false };
  // Whole lines go to one party: the lines the words were placed in when
  // there are any, otherwise words whose centres sit within a fraction of the
  // cell height.
  let lines;
  if (hits.every((p) => p.lineKey != null)) {
    const byLine = new Map();
    for (const p of hits) {
      if (!byLine.has(p.lineKey)) byLine.set(p.lineKey, { items: [], cy: p.lineCy });
      byLine.get(p.lineKey).items.push(p);
    }
    lines = [...byLine.values()];
  } else {
    const sorted = [...hits].sort((a, b) => a.cy - b.cy);
    const tol = Math.max(8, cellHeight * 0.12);
    lines = [];
    let run = [sorted[0]];
    for (const p of sorted.slice(1)) {
      if (p.cy - run[run.length - 1].cy <= tol) run.push(p);
      else { lines.push(run); run = [p]; }
    }
    lines.push(run);
    lines = lines.map((items) => ({ items, cy: items.reduce((a, p) => a + p.cy, 0) / items.length }));
  }
  lines.sort((a, b) => a.cy - b.cy);

  if (lines.length <= 1) {
    // One printed line: a single person. Can't tell groom from bride, so keep
    // all as the groom and flag when there was more than one word to split.
    return { top: hits, bottom: [], uncertain: hits.length >= 2 };
  }
  const splitY = (lines[0].cy + lines[lines.length - 1].cy) / 2;
  const top = lines.filter((l) => l.cy < splitY).flatMap((l) => l.items);
  const bottom = lines.filter((l) => l.cy >= splitY).flatMap((l) => l.items);
  return { top, bottom, uncertain: top.length === 0 || bottom.length === 0 };
}

// The printed NO-column entry digit is centred on the band and can fall a few
// pixels past the narrow NO column into contracting parties, prefixing a name
// with a stray "3 " / "1 . ". A contracting party's name never begins with a
// digit, so drop a single leading number (with optional trailing dot/comma)
// when readable name text follows. Applied ONLY to the name field -- birth,
// address and parents legitimately begin with numbers.
function stripLeadingEntryNumber(s) {
  // Drop a stray entry number anywhere in the name -- in reading order it can
  // land after the first word ("RICHARD CAMACHO 12") as easily as before it.
  // Names never contain a standalone number, so this is only applied once
  // readable name text remains.
  const kept = String(s || '')
    .split(/\s+/)
    .filter((t) => t && !/^\d{1,3}[.,]?$/.test(t));
  return kept.some((t) => /[a-z]/i.test(t)) ? kept.join(' ') : s;
}

function blankParty() {
  return {
    name: '',
    legalStatus: '',
    actualAddress: '',
    datesPlaceOfBirth: '',
    datesPlaceOfBaptism: '',
    parents: '',
    sponsors: '',
  };
}

// Lines of handwriting each entry holds per column. The paired columns are
// ruled with four printed lines per entry (two for the groom, two for the
// bride); the date of marriage is written month / day / year down its narrow
// column; minister and license take one line.
const MARRIAGE_LINE_CAPS = {
  contracting_parties: 4,
  legal_status: 2,
  actual_address: 4,
  birth: 4,
  baptism: 4,
  marriage_date: 3,
  parents: 4,
  sponsors: 4,
  minister: 2,
  license_no: 1,
  observations: 3,
};
const MARRIAGE_YEAR_ENDS_ENTRY = new Set(['marriage_date']);
const HEADER_ENTRY_ZONE = 0.6;
const MARRIAGE_HEADER_WORDS = new Set([
  'no', 'contracting', 'parties', 'legal', 'status', 'actual', 'address',
  'dates', 'date', 'places', 'place', 'of', 'birth', 'baptism', 'marriage',
  'parents', 'sponsors', 'sponsor', 'minister', 'license', 'observations',
  'observation', 'register', 'and', 'name', 'names', 'page',
]);

// Handwritten lines near the spine run uphill: on the right page's parents
// column a name drops 20-30 px from its last word to its first, more than the
// gap between two written lines, so grouping words by their own height paired
// one line's first name with the line above's surname ("NILO SALIBAY R." for
// "NILO P. SENTURIAS" / "LUMEN R. SALIBAY"). Estimate the column's writing
// slope as the one that stacks the words' centres into the tightest rows, and
// group lines on slope-corrected heights.
const SLOPE_STEPS = 31;
const SLOPE_RANGE = 0.15;
function writingSlope(pts) {
  if (pts.length < 6) return 0;
  const hs = pts.map((p) => p.h).filter((h) => h > 0).sort((a, b) => a - b);
  const bin = Math.max(4, 0.5 * (hs.length ? hs[Math.floor(hs.length / 2)] : 16));
  const xMid = pts.reduce((sum, p) => sum + p.cx, 0) / pts.length;
  let best = { slope: 0, score: -1 };
  for (let i = 0; i < SLOPE_STEPS; i += 1) {
    const slope = -SLOPE_RANGE + (2 * SLOPE_RANGE * i) / (SLOPE_STEPS - 1);
    const counts = new Map();
    for (const p of pts) {
      const b = Math.round((p.cy - slope * (p.cx - xMid)) / bin);
      counts.set(b, (counts.get(b) || 0) + 1);
    }
    let score = 0;
    for (const c of counts.values()) score += c * c;
    // Prefer level writing on a tie.
    if (score > best.score || (score === best.score && Math.abs(slope) < Math.abs(best.slope))) {
      best = { slope, score };
    }
  }
  return best.slope;
}
function slopedLines(pts, bands = []) {
  if (pts.length === 0) return [];
  // The curl is strongest at the top of the page and fades lower down, so
  // measure the slope per entry band (with half a band of context either
  // side) rather than once for the whole column.
  const xMid = pts.reduce((sum, p) => sum + p.cx, 0) / pts.length;
  const slopeOf = new Map();
  const spans = bands.length ? bands : [{ y: -Infinity, h: Infinity }];
  for (const b of spans) {
    const pad = Number.isFinite(b.h) ? 0.5 * b.h : 0;
    const near = pts.filter((p) => p.cy >= b.y - pad && p.cy < b.y + b.h + pad);
    const slope = writingSlope(near);
    for (const p of pts) {
      if (p.cy >= b.y && p.cy < b.y + b.h) slopeOf.set(p, slope);
    }
  }
  const proxyOf = new Map();
  const proxies = pts.map((p) => {
    const dy = -(slopeOf.get(p) || 0) * (p.cx - xMid);
    const proxy = { ...p.word, vertices: p.word.vertices.map((v) => ({ x: v.x, y: v.y + dy })) };
    proxyOf.set(proxy, p.word);
    return proxy;
  });
  return groupLines(proxies).map((line) => ({
    ...line,
    words: line.words.map((w) => proxyOf.get(w)),
  }));
}

/**
 * Place each column's words entry by entry, a whole handwritten line at a time,
 * returning `${row}:${key}` -> placed words.
 *
 * A word's centre against the grid's row rules is not enough on this register:
 * near the spine the page curls, so a rule that is level across the minister
 * column runs 20-40 px lower under the parents column. Each entry's first
 * parent and first sponsor are written just under the rule there and their
 * centres land above the grid line -- every parent and sponsor came back one
 * line late (IMG_20260915_094113 right page). But each entry holds a known
 * number of lines in each column, so -- as for the baptismal register --
 * group the column's words into lines and assign the lines to entries in
 * order, paying for moving a line out of the row it was written in and for
 * overfilling an entry. A line pushed out of an overfull entry carries the
 * shift down the page instead of every entry keeping its neighbour's line.
 *
 * Handwriting in the header band is assigned with the entries; only lines made
 * of printed labels stay in the header row (the route drops it). Small grids
 * (tests, partial pages) use plain centre-point assignment.
 */
function placeByColumn(cells, words, { belowSlack = 0 } = {}) {
  const perCell = new Map();
  const add = (row, key, p) => {
    const k = `${row}:${key}`;
    if (!perCell.has(k)) perCell.set(k, []);
    perCell.get(k).push(p);
  };
  const placed = (words || []).map(centre);
  const byKey = new Map();
  for (const c of cells) {
    if (!byKey.has(c.key)) byKey.set(c.key, []);
    byKey.get(c.key).push(c);
  }
  for (const list of byKey.values()) list.sort((a, b) => a.row - b.row);
  const rowCount = byKey.size ? Math.max(...[...byKey.values()].map((l) => l.length)) : 0;

  if (rowCount < 4) {
    for (const p of placed) {
      const hit = cells.find((c) => inRect(p.cx, p.cy, c));
      if (hit) add(hit.row, hit.key, p);
    }
    return perCell;
  }

  const byWord = new Map(placed.map((p) => [p.word, p]));
  for (const [key, list] of byKey) {
    const top = list[0];
    const last = list[list.length - 1];
    const bottom = last.y + last.h * (1 + belowSlack);
    const mine = placed.filter(
      (p) => p.cx >= top.x && p.cx < top.x + top.w && p.cy >= top.y && p.cy < bottom,
    );
    if (key === 'no' || !MARRIAGE_LINE_CAPS[key]) {
      for (const p of mine) {
        const hit = list.find((c) => p.cy >= c.y && p.cy < c.y + c.h) || (p.cy >= last.y ? last : null);
        if (hit) add(hit.row, key, p);
      }
      continue;
    }
    const lines = slopedLines(mine, list);
    const entryRows = list.slice(1);
    const entryLines = [];
    lines.forEach((line, i) => {
      for (const w of line.words) {
        const p = byWord.get(w);
        p.lineKey = `${key}:${i}`;
        p.lineCy = line.cy;
      }
    });
    for (const line of lines) {
      const pts = line.words.map((w) => byWord.get(w));
      const hasData = String(line.text).toLowerCase().split(/[^a-z0-9]+/)
        .some((t) => t.length >= 2 && /[a-z]/.test(t) && !MARRIAGE_HEADER_WORDS.has(t));
      // A line in the header band is the header's unless it is handwriting in
      // the band's lower part (an entry's first line written just under the
      // header rule). The page title above the column labels ("Register",
      // often misread as "Regizter") stays there either way.
      const inHeader = line.cy < top.y + top.h;
      if (inHeader && (!hasData || line.cy < top.y + HEADER_ENTRY_ZONE * top.h)) {
        for (const p of pts) add(top.row, key, p);
      } else if (!/[A-Za-z0-9]{2}/.test(line.text)) {
        // A speck read as punctuation is not a line of writing.
        for (const p of pts) {
          const hit = list.find((c) => p.cy >= c.y && p.cy < c.y + c.h);
          if (hit) add(hit.row, key, p);
        }
      } else {
        entryLines.push({ line, pts });
      }
    }
    const rows = assignLines(
      entryLines.map((e) => e.line),
      entryRows,
      MARRIAGE_LINE_CAPS[key],
      MARRIAGE_YEAR_ENDS_ENTRY.has(key),
    );
    entryLines.forEach((e, i) => {
      if (rows[i] == null) return;
      for (const p of e.pts) add(entryRows[rows[i]].row, key, p);
    });
  }
  return perCell;
}

function marriageGridToRows(leftPage, leftWords, rightPage, rightWords) {
  const warnings = new Set();
  const rowsMap = new Map(); // rowIndex -> entry skeleton
  const ensure = (r) => {
    if (!rowsMap.has(r)) {
      rowsMap.set(r, {
        index: r,
        lineNo: '',
        groom: blankParty(),
        bride: blankParty(),
        dateOfMarriage: '',
        minister: '',
        licenseNumber: '',
        observations: '',
      });
    }
    return rowsMap.get(r);
  };

  const assign = (page, words, pairedMap, sharedMap, opts) => {
    const cells = widenOuterCells(page);
    const perCell = placeByColumn(cells, words, opts);
    for (const c of cells) {
      const hits = perCell.get(`${c.row}:${c.key}`) || [];
      const entry = ensure(c.row);
      if (c.key === 'no') {
        entry.lineNo = joinText(hits) || entry.lineNo;
        continue;
      }
      if (pairedMap[c.key]) {
        const field = pairedMap[c.key];
        const { top, bottom, uncertain } = splitGroomBride(hits, c.h);
        // The two printed lines couldn't be told apart -- flag for the reviewer.
        if (uncertain) warnings.add('GROOM_BRIDE_SPLIT_UNCERTAIN');
        const clean = field === 'name' ? stripLeadingEntryNumber : (x) => x;
        entry.groom[field] = clean(joinText(top));
        entry.bride[field] = clean(joinText(bottom));
      } else if (sharedMap[c.key]) {
        const field = sharedMap[c.key];
        const text = joinText(hits);
        if (field === 'sponsors') entry.groom.sponsors = text;
        else entry[field] = text;
      }
    }
  };

  assign(leftPage, leftWords, PAIRED_LEFT, SHARED_LEFT, { belowSlack: BELOW_TABLE_SLACK });
  assign(rightPage, rightWords, PAIRED_RIGHT, SHARED_RIGHT);

  const rows = [...rowsMap.entries()].sort((a, b) => a[0] - b[0]).map(([, v]) => v);
  return { rows, warnings: [...warnings] };
}

module.exports = {
  marriageGridToRows,
  PAIRED_LEFT,
  PAIRED_RIGHT,
  SHARED_LEFT,
  SHARED_RIGHT,
};
