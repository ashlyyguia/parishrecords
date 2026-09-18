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
    word: w,
  };
}
function inRect(cx, cy, c) {
  return cx >= c.x && cx < c.x + c.w && cy >= c.y && cy < c.y + c.h;
}
function joinText(placed) {
  return placed
    .slice()
    .sort((a, b) => a.cy - b.cy || a.cx - b.cx)
    .map((p) => p.word.text)
    .join(' ')
    .replace(/\s+/g, ' ')
    .trim();
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
  const sorted = [...hits].sort((a, b) => a.cy - b.cy);
  const tol = Math.max(8, cellHeight * 0.12);
  const lineCentres = [];
  let run = [sorted[0].cy];
  for (const p of sorted.slice(1)) {
    if (p.cy - run[run.length - 1] <= tol) run.push(p.cy);
    else { lineCentres.push(run.reduce((a, b) => a + b, 0) / run.length); run = [p.cy]; }
  }
  lineCentres.push(run.reduce((a, b) => a + b, 0) / run.length);

  if (lineCentres.length <= 1) {
    // One printed line: a single person. Can't tell groom from bride, so keep
    // all as the groom and flag when there was more than one word to split.
    return { top: hits, bottom: [], uncertain: hits.length >= 2 };
  }
  const splitY = (lineCentres[0] + lineCentres[lineCentres.length - 1]) / 2;
  const top = hits.filter((p) => p.cy < splitY);
  const bottom = hits.filter((p) => p.cy >= splitY);
  return { top, bottom, uncertain: top.length === 0 || bottom.length === 0 };
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

  const assign = (page, words, pairedMap, sharedMap) => {
    const cells = (page && page.cells) || [];
    const placed = (words || []).map(centre);
    for (const c of cells) {
      const hits = placed.filter((p) => inRect(p.cx, p.cy, c));
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
        entry.groom[field] = joinText(top);
        entry.bride[field] = joinText(bottom);
      } else if (sharedMap[c.key]) {
        const field = sharedMap[c.key];
        const text = joinText(hits);
        if (field === 'sponsors') entry.groom.sponsors = text;
        else entry[field] = text;
      }
    }
  };

  assign(leftPage, leftWords, PAIRED_LEFT, SHARED_LEFT);
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
