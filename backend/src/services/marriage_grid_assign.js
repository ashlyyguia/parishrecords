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
        const mid = c.y + c.h / 2;
        const top = hits.filter((p) => p.cy < mid);
        const bottom = hits.filter((p) => p.cy >= mid);
        // Two or more words that all land on one side means the two printed
        // lines can't be told apart -- flag it for the reviewer.
        if (hits.length >= 2 && (top.length === 0 || bottom.length === 0)) {
          warnings.add('GROOM_BRIDE_SPLIT_UNCERTAIN');
        }
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
