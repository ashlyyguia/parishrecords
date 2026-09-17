/**
 * Word-clustering fallback for marriage-register spreads.
 *
 * The CV grid service is the primary path; this runs only when CV is
 * unavailable, turning OCR.space words-with-boxes into marriage rows by the
 * same calibrate-columns-against-printed-headers approach as
 * `baptismal_register_layout.js`, whose primitives it reuses.
 *
 * What's different from the baptismal fallback: a marriage entry occupies TWO
 * printed lines within one ruled row -- the groom on the top line, the bride on
 * the bottom. So rows are anchored on the printed NO. digits (one per entry,
 * not one per line), the resulting entry bands span both lines, and each
 * "paired" column's cell is split at the band's vertical midpoint into groom
 * (above) and bride (below). The right page has no NO. column, but the two
 * rectified halves share a y-axis (they were split from one photo), so the
 * left page's entry bands are reused to place the right page's words -- the
 * same shared-y-axis reasoning the CV grid-assign relies on.
 */

const {
  boxOf,
  normalizeOrientation,
  splitSpread,
  calibrateColumns,
} = require('./baptismal_register_layout');

// Distinctive header tokens per column; fallbackRatio is the column centre as a
// fraction of page width, used only when the printed header can't be read.
// NOTE: marriageDate's 'marriage' token also appears in the left page's
// "Marriage" title; the title sits in the title band above the header band, so
// it can drag this centre when the printed header is faint. This is the
// fallback path (CV is primary) and the calibration warnings surface the
// uncertainty; the declared CV template is the accurate route.
const LEFT_COLUMNS = [
  { key: 'lineNo', header: ['no'], fallbackRatio: 0.02 },
  { key: 'contractingParties', header: ['contracting'], fallbackRatio: 0.12 },
  { key: 'legalStatus', header: ['legal', 'status'], fallbackRatio: 0.25 },
  { key: 'actualAddress', header: ['actual', 'address'], fallbackRatio: 0.38 },
  { key: 'birth', header: ['birth'], fallbackRatio: 0.57 },
  { key: 'baptism', header: ['baptism'], fallbackRatio: 0.77 },
  { key: 'marriageDate', header: ['marriage'], fallbackRatio: 0.93 },
];

const RIGHT_COLUMNS = [
  { key: 'parents', header: ['parents'], fallbackRatio: 0.15 },
  { key: 'sponsors', header: ['sponsors'], fallbackRatio: 0.42 },
  { key: 'minister', header: ['minister'], fallbackRatio: 0.63 },
  { key: 'licenseNo', header: ['license'], fallbackRatio: 0.78 },
  { key: 'observations', header: ['observations'], fallbackRatio: 0.92 },
];

// Paired columns carry one value per printed line (groom then bride).
const PAIRED_FIELD = {
  contractingParties: 'name',
  legalStatus: 'legalStatus',
  actualAddress: 'actualAddress',
  birth: 'datesPlaceOfBirth',
  baptism: 'datesPlaceOfBaptism',
  parents: 'parents',
};
// Shared columns span both lines. sponsors is shared but stored on the groom.
const SHARED_FIELD = {
  marriageDate: 'dateOfMarriage',
  minister: 'minister',
  licenseNo: 'licenseNumber',
  observations: 'observations',
};

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

function joinItems(items) {
  return items
    .slice()
    .sort((a, b) => a.box.cy - b.box.cy || a.box.cx - b.box.cx)
    .map((i) => i.text)
    .join(' ')
    .replace(/\s+/g, ' ')
    .trim();
}

function medianHeight(boxes) {
  if (boxes.length === 0) return 20;
  const hs = boxes.map((b) => b.h).sort((a, b) => a - b);
  return hs[Math.floor(hs.length / 2)] || 20;
}

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
 * Entry bands from the printed NO. digits: one band per numbered entry,
 * spanning that entry's two printed lines. Bands are the midpoints between
 * adjacent anchors; the first/last extend by half the median pitch.
 *
 * Fallback when no NO. digit is legible: cluster every left-page data word by y
 * (noisier -- may over-split a two-line entry, which the reviewer sees via
 * ROW_ANCHOR_FALLBACK) and treat each cluster as a band.
 */
function detectEntryBands(leftWords, columns, headerMaxY) {
  const warnings = [];
  if (!leftWords || leftWords.length === 0) return { bands: [], warnings };

  const lineNoCol = (columns || []).find((c) => c.key === 'lineNo');
  const boxes = leftWords.map((w) => ({ ...boxOf(w), text: w.text }));
  const tolerance = medianHeight(boxes) * 0.9;

  let anchors = [];
  if (lineNoCol) {
    anchors = boxes
      .filter(
        (b) =>
          b.cx >= lineNoCol.x0 &&
          b.cx < lineNoCol.x1 &&
          b.cy > headerMaxY &&
          /^\d{1,3}$/.test(b.text),
      )
      .map((b) => ({ cy: b.cy, lineNo: b.text }));
  }

  let clusters;
  if (anchors.length >= 1) {
    // One numeral per entry already, so cluster loosely to merge a split digit.
    clusters = clusterByY(anchors, tolerance).map((c) => ({
      cy: c.cy,
      lineNo: c.members[0].lineNo,
    }));
  } else {
    if (lineNoCol) warnings.push('ROW_ANCHOR_FALLBACK');
    const dataBoxes = boxes.filter((b) => b.cy > headerMaxY);
    clusters = clusterByY(dataBoxes, tolerance).map((c) => ({ cy: c.cy, lineNo: null }));
  }

  if (clusters.length === 0) return { bands: [], warnings };

  const pitch =
    clusters.length > 1
      ? (clusters[clusters.length - 1].cy - clusters[0].cy) / (clusters.length - 1)
      : tolerance * 3;

  const bands = clusters.map((c, i) => {
    const prev = clusters[i - 1];
    const next = clusters[i + 1];
    return {
      index: i,
      lineNo: c.lineNo,
      y0: prev ? (prev.cy + c.cy) / 2 : c.cy - pitch / 2,
      y1: next ? (c.cy + next.cy) / 2 : c.cy + pitch / 2,
    };
  });
  return { bands, warnings };
}

/**
 * Places one page's words into the given entry bands and columns, returning
 * per-band `{ groom, bride, shared }` blobs. Paired columns split at the band
 * midpoint; shared columns take the whole band.
 */
function assignPage(pageWords, columns, bands) {
  const perBand = bands.map(() => ({}));
  let splitUncertain = false;

  const buckets = bands.map(() => {
    const b = {};
    for (const c of columns) b[c.key] = [];
    return b;
  });

  for (const w of pageWords || []) {
    const box = boxOf(w);
    const bi = bands.findIndex((r) => box.cy >= r.y0 && box.cy < r.y1);
    if (bi === -1) continue;
    const col = columns.find((c) => box.cx >= c.x0 && box.cx < c.x1);
    if (!col) continue;
    buckets[bi][col.key].push({ text: w.text, box });
  }

  bands.forEach((band, bi) => {
    const out = { groom: {}, bride: {}, shared: {} };
    const mid = (band.y0 + band.y1) / 2;
    for (const col of columns) {
      const items = buckets[bi][col.key];
      if (PAIRED_FIELD[col.key]) {
        const field = PAIRED_FIELD[col.key];
        const top = items.filter((i) => i.box.cy < mid);
        const bottom = items.filter((i) => i.box.cy >= mid);
        if (items.length >= 2 && (top.length === 0 || bottom.length === 0)) {
          splitUncertain = true;
        }
        out.groom[field] = joinItems(top);
        out.bride[field] = joinItems(bottom);
      } else if (col.key === 'sponsors') {
        out.groom.sponsors = joinItems(items);
      } else if (SHARED_FIELD[col.key]) {
        out.shared[SHARED_FIELD[col.key]] = joinItems(items);
      }
    }
    perBand[bi] = out;
  });

  return { perBand, splitUncertain };
}

// Carry minister and dateOfMarriage down into empty cells; the register repeats
// them down a batch. Only these two, matching the baptismal fill-down.
const DITTO = /^(-?\s*do\s*-?|["”]|,,|-{2,})$/i;
function isEmpty(v) {
  const s = (v || '').trim();
  return s === '' || DITTO.test(s);
}
function applyFillDown(rows) {
  const carried = { minister: null, dateOfMarriage: null };
  for (const row of rows) {
    for (const key of ['minister', 'dateOfMarriage']) {
      if (!isEmpty(row[key])) carried[key] = row[key].trim();
      else if (carried[key]) row[key] = carried[key];
    }
  }
  return rows;
}

/**
 * Full fallback pipeline: raw OCR words in, marriage rows out.
 * @throws {Error} with .code = 'LAYOUT_UNRECOGNIZED'
 */
function extractMarriageRows(words) {
  const oriented = normalizeOrientation(words);
  const spread = splitSpread(oriented.words);

  const hasTitle = (list, title) =>
    list.some((w) => w.text.toLowerCase().replace(/[^a-z]/g, '') === title);
  const gutterConfirmed = hasTitle(spread.left, 'marriage') && hasTitle(spread.right, 'register');

  const leftCal = calibrateColumns(spread.left, LEFT_COLUMNS);
  const rightCal = calibrateColumns(spread.right, RIGHT_COLUMNS);

  const leftMatched = leftCal.columns.filter((c) => c.matched).length;
  const rightMatched = rightCal.columns.filter((c) => c.matched).length;
  // A non-register document tends to land on one side of splitSpread's gutter
  // guess and rack up coincidental matches there; a genuine spread shows print
  // on both halves. Require evidence on each side and combined, same thresholds
  // as the baptismal guard.
  if (leftMatched + rightMatched < 3 || leftMatched < 1 || rightMatched < 1) {
    const err = new Error('LAYOUT_UNRECOGNIZED: this does not look like a marriage register page');
    err.code = 'LAYOUT_UNRECOGNIZED';
    throw err;
  }

  const { bands, warnings: bandWarnings } = detectEntryBands(
    spread.left,
    leftCal.columns,
    leftCal.headerMaxY,
  );

  const left = assignPage(spread.left, leftCal.columns, bands);
  const right = assignPage(spread.right, rightCal.columns, bands);

  const rows = bands.map((band, i) => {
    const l = left.perBand[i] || { groom: {}, bride: {}, shared: {} };
    const r = right.perBand[i] || { groom: {}, bride: {}, shared: {} };
    const groom = { ...blankParty(), ...l.groom, ...r.groom };
    const bride = { ...blankParty(), ...l.bride, ...r.bride };
    return {
      index: i,
      lineNo: band.lineNo || String(i + 1),
      groom,
      bride,
      dateOfMarriage: l.shared.dateOfMarriage || '',
      minister: r.shared.minister || '',
      licenseNumber: r.shared.licenseNumber || '',
      observations: r.shared.observations || '',
    };
  });

  applyFillDown(rows);

  const warnings = [
    ...new Set([
      ...leftCal.warnings,
      ...rightCal.warnings,
      ...bandWarnings,
      ...(left.splitUncertain || right.splitUncertain ? ['GROOM_BRIDE_SPLIT_UNCERTAIN'] : []),
      ...(gutterConfirmed ? [] : ['GUTTER_UNCONFIRMED']),
    ]),
  ];

  return { rows, rotation: oriented.rotation, gutterX: spread.gutterX, warnings };
}

module.exports = {
  LEFT_COLUMNS,
  RIGHT_COLUMNS,
  calibrateColumns,
  detectEntryBands,
  assignPage,
  applyFillDown,
  extractMarriageRows,
};
