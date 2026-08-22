/**
 * Builds Vision-shaped word lists for a synthetic baptismal register spread,
 * so layout tests run offline with no credentials and no network.
 *
 * Geometry mirrors attachments/IMG_3120.jpeg: a two-page spread, left page
 * (Baptismal) columns then a gutter then right page (Register) columns.
 */

const PAGE_W = 2000;
const PAGE_H = 1400;
const GUTTER_X0 = 960;
const GUTTER_X1 = 1040;

// [label, centerX] — printed headers. Left page then right page.
const HEADERS = [
  ['NO.', 60],
  ['NAME OF CHILD', 220],
  ['PLACE & DATE OF BIRTH', 480],
  ['L or ILL', 700],
  ['NAME OF PARENTS', 850],
  ['RESIDENTS OF', 1150],
  ['DATE OF BAPTISM', 1350],
  ['MINISTER', 1550],
  ['SPONSORS', 1750],
  ['OBSERVATIONS', 1930],
];

const HEADER_Y = 120;
const FIRST_ROW_Y = 220;
const ROW_H = 60;

function word(text, cx, cy, confidence = 0.9) {
  const w = Math.max(24, text.length * 9);
  const h = 22;
  const x0 = Math.round(cx - w / 2);
  const y0 = Math.round(cy - h / 2);
  const x1 = x0 + w;
  const y1 = y0 + h;
  return {
    text,
    vertices: [
      { x: x0, y: y0 },
      { x: x1, y: y0 },
      { x: x1, y: y1 },
      { x: x0, y: y1 },
    ],
    confidence,
  };
}

/**
 * Splits a header label into per-word entries clustered around its center.
 *
 * Spacing is deliberately tight (20px): calibrateColumns averages the centers
 * of the matched header tokens, so widely-spread header words would drag the
 * derived column center away from the ruled column it labels.
 */
function headerWords(label, cx) {
  const parts = label.split(' ');
  const spacing = 20;
  const start = cx - ((parts.length - 1) * spacing) / 2;
  return parts.map((p, i) => word(p, start + i * spacing, HEADER_Y, 0.99));
}

function rotatePoint(p, rotation, w, h) {
  switch (rotation) {
    case 90: return { x: h - p.y, y: p.x };
    case 180: return { x: w - p.x, y: h - p.y };
    case 270: return { x: p.y, y: w - p.x };
    default: return { x: p.x, y: p.y };
  }
}

/**
 * Rotates a word clockwise by `rotation` degrees about the page.
 * Vertex ORDER is preserved (TL,TR,BR,BL of the glyph), which is what lets
 * normalizeOrientation recover the angle from the baseline vector.
 */
function rotateWord(w, rotation) {
  if (rotation === 0) return w;
  return {
    ...w,
    vertices: w.vertices.map((v) => rotatePoint(v, rotation, PAGE_W, PAGE_H)),
  };
}

const SAMPLE_ROWS = [
  {
    no: '1',
    nameOfChild: ['JEZL', 'ANTOINETTE', 'HITUTUAAN'],
    placeAndBirthDate: ['19', 'FEBRUARY', '2001'],
    parents: ['LITA', 'HITUTUAAN'],
    residentsOf: ['P-2', 'CANITOAN'],
    dateOfBaptism: ['12', 'MAY', '2016'],
    minister: ['FR.', 'PABLITO', 'ARCAPA'],
    sponsors: ['JOMARIE', 'POL'],
  },
  {
    no: '2',
    nameOfChild: ['JULLIE', 'PACITO'],
    placeAndBirthDate: ['7', 'OCTOBER', '2010'],
    parents: ['LYRA', 'PACITO'],
    residentsOf: ['PUROK', '4'],
    dateOfBaptism: ['12', 'MAY', '2016'],
    minister: ['FR.', 'PABLITO', 'ARCAPA'],
    sponsors: ['ANIGTA', 'POL'],
  },
  {
    no: '3',
    nameOfChild: ['JOMAR', 'HITUTUAAN'],
    placeAndBirthDate: ['10', 'JANUARY', '2010'],
    parents: ['LUISA', 'CARBALLO'],
    residentsOf: ['UPPER', 'ILIGAN'],
    dateOfBaptism: ['22', 'MAY', '2016'],
    minister: ['FR.', 'PABLITO', 'ARCAPA'],
    sponsors: ['EDGAR', 'LULLAO'],
  },
];

const COLUMN_X = {
  no: 60,
  nameOfChild: 220,
  placeAndBirthDate: 480,
  parents: 850,
  residentsOf: 1150,
  dateOfBaptism: 1350,
  minister: 1550,
  sponsors: 1750,
};

/**
 * @param {{rotation?: 0|90|180|270, rows?: number, omitHeaders?: string[],
 *          omitNoColumn?: boolean, confidence?: number}} opts
 */
function buildRegisterFixture(opts = {}) {
  const rotation = opts.rotation || 0;
  const rowCount = opts.rows || SAMPLE_ROWS.length;
  const omitHeaders = new Set(opts.omitHeaders || []);
  const confidence = typeof opts.confidence === 'number' ? opts.confidence : 0.9;

  const words = [];

  for (const [label, cx] of HEADERS) {
    if (omitHeaders.has(label)) continue;
    words.push(...headerWords(label, cx));
  }
  // Page titles, used to confirm the gutter split.
  words.push(word('Baptismal', 300, 50, 0.99));
  words.push(word('Register', 1400, 50, 0.99));

  for (let r = 0; r < rowCount; r += 1) {
    const src = SAMPLE_ROWS[r % SAMPLE_ROWS.length];
    const cy = FIRST_ROW_Y + r * ROW_H;
    if (!opts.omitNoColumn) {
      words.push(word(String(r + 1), COLUMN_X.no, cy, 0.95));
    }
    for (const key of Object.keys(COLUMN_X)) {
      if (key === 'no') continue;
      const tokens = src[key] || [];
      const spacing = 60;
      const start = COLUMN_X[key] - ((tokens.length - 1) * spacing) / 2;
      tokens.forEach((t, i) => words.push(word(t, start + i * spacing, cy, confidence)));
    }
  }

  return { words: words.map((w) => rotateWord(w, rotation)), rotation, rowCount };
}

module.exports = {
  buildRegisterFixture,
  PAGE_W,
  PAGE_H,
  GUTTER_X0,
  GUTTER_X1,
  HEADER_Y,
  FIRST_ROW_Y,
  ROW_H,
  COLUMN_X,
  SAMPLE_ROWS,
};
