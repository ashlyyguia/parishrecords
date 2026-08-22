# Baptismal Register OCR (Google Cloud Vision) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Rebuild `/admin/records` → **Add Record (OCR)** so an admin can photograph a baptismal register spread, have Google Cloud Vision read the handwriting, see every field mapped into the correct column with confidence flags, correct it, and batch-save the verified rows.

**Architecture:** Vision is called only from the backend (`baptismal_ocr_service.js`). A separate pure-function module (`baptismal_register_layout.js`) turns Vision's words-with-boxes into register rows by calibrating column x-bands against the **printed** column headers and row y-bands against the printed `NO.` column — deterministic, and unit-testable offline against fixtures. Flutter uploads the original image to Storage, posts to `/api/ocr/baptismal/scan`, and renders an editable review table that blocks save until required fields validate.

**Tech Stack:** Node/Express + `@google-cloud/vision` + `sharp` + Jest (backend); Flutter + Riverpod + GoRouter + `firebase_storage` + `http` (frontend).

**Spec:** `docs/superpowers/specs/2026-08-22-baptismal-ocr-record-design.md`

## Global Constraints

Every task's requirements implicitly include this section.

- **Branch:** all work lands on `feature/baptismal-ocr-record`. Never commit to `main`, `master`, `development`, or `ocr`.
- **Scope:** baptismal registers only. Do not implement marriage/matrimonial OCR.
- **Credentials never reach the client.** Vision is called only from `backend/src/services/baptismal_ocr_service.js`. Credentials resolve from `GOOGLE_CLOUD_VISION_CREDENTIALS_JSON`, falling back to `FIREBASE_SERVICE_ACCOUNT_JSON`.
- **Never log cell values.** These are records of minors. Log counts, error codes, timings, and `scanId` only.
- **Do not modify** `lib/services/register_ocr_scan_helper.dart`, `lib/services/register_ocr_parser.dart`, `backend/src/routes/ocr_firestore.js`, `backend/src/services/ocrspace_service.js`, or any `staff_ocr_*` page. The old path stays working.
- **Schema changes are additive only.** Existing saved records must still decode through `ManualRegisterNotes.tryDecode`.
- **Backend response envelope:** `{ success: true, data: ... }` or `{ success: false, message: ..., code: ... }`.
- **Confidence threshold for review flagging:** `confidence < 0.60`.
- **Accepted uploads:** `image/jpeg`, `image/png`, `image/webp`, sniffed by magic bytes. Hard cap **10 MB**.
- **`docs/` is gitignored in this repo but plan/spec files are tracked.** Use `git add -f` for anything under `docs/`.
- **Dart style:** run `flutter analyze` before each Flutter commit; it must be clean.
- **Existing deps are sufficient client-side** (`uuid ^4.2.1`, `image ^4.8.0`, `http ^1.2.2`, `firebase_storage ^13.0.3`, `file_picker`, `image_picker`, `cross_file`). Only the backend gains new dependencies.

## Normalized word shape

Every layout function consumes and produces this shape. It is the single contract across Tasks 1–7.

```js
// One OCR word with its quadrilateral, in image pixel coordinates.
{
  text: 'JEZL',
  vertices: [ {x:120,y:100}, {x:180,y:100}, {x:180,y:122}, {x:120,y:122} ], // TL,TR,BR,BL
  confidence: 0.93,
}
```

## File Structure

**Backend — create:**

| File | Responsibility |
|------|----------------|
| `backend/src/services/baptismal_ocr_service.js` | Only Vision I/O. Credentials, `documentTextDetection`, normalize response to word shape. No layout logic. |
| `backend/src/services/baptismal_register_layout.js` | Pure functions: orientation, gutter split, column calibration, row detection, cell assignment, page join, fill-down, orchestrator. No I/O. |
| `backend/src/services/baptismal_image_preprocess.js` | `sharp` pipeline on a buffer copy. Isolated so a deploy problem here can't take the feature down. |
| `backend/src/routes/baptismal_ocr_firestore.js` | Authz, file validation, error-code mapping, orchestration. |
| `backend/test/helpers/register_fixture.js` | Synthesizes Vision-shaped word lists for a register page at any rotation. Makes Tasks 2–7 testable without network. |
| `backend/scripts/record_vision_fixture.js` | One-off: calls real Vision on `attachments/*.jpeg`, writes JSON fixtures. |

**Backend — modify:** `backend/src/server.js` (mount route), `backend/package.json` (deps), `backend/.env.example` (document env vars).

**Frontend — create:**

| File | Responsibility |
|------|----------------|
| `lib/models/baptismal_register_row.dart` | `OcrField`, `BaptismalRegisterRow`, response parsing. |
| `lib/services/baptismal_ocr_service.dart` | HTTP client + typed `BaptismalOcrFailure`. |
| `lib/services/baptismal_row_validation.dart` | Pure validation rules. No UI, no Firestore. |
| `lib/screens/admin/pages/baptismal_ocr_scan_page.dart` | The stepper (upload → processing → review → save). |
| `lib/widgets/baptismal_ocr_review_table.dart` | The editable table widget. Split out because the page would otherwise grow past 600 lines. |

**Frontend — modify:** `lib/utils/manual_register_notes.dart` (additive schema), `lib/app/router.dart` (new route), `lib/screens/admin/pages/records_page.dart:346` (repoint button).

---

### Task 1: Vision client service

**Files:**
- Create: `backend/src/services/baptismal_ocr_service.js`
- Test: `backend/src/services/baptismal_ocr_service.test.js`
- Modify: `backend/package.json`

**Interfaces:**
- Consumes: nothing.
- Produces:
  - `resolveVisionCredentials(env)` → `{ credentials }` object for the Vision client constructor. Throws `Error` with `.code = 'VISION_AUTH'` when neither env var is present or parseable.
  - `recognizeWords(imageBuffer, { client })` → `Promise<{ words: Word[], fullText: string }>`. `client` is injectable for tests (matches the `fetchImpl` injection style already used in `ocrspace_service.test.js`). Throws errors carrying `.code` ∈ `VISION_AUTH | VISION_QUOTA | VISION_UNAVAILABLE | NO_TEXT_FOUND`.

- [ ] **Step 1: Add the dependency**

```bash
cd backend && npm install @google-cloud/vision@^4.3.2
```

- [ ] **Step 2: Write the failing test**

Create `backend/src/services/baptismal_ocr_service.test.js`:

```js
const { resolveVisionCredentials, recognizeWords } = require('./baptismal_ocr_service');

describe('resolveVisionCredentials', () => {
  test('prefers the dedicated Vision credentials', () => {
    const env = {
      GOOGLE_CLOUD_VISION_CREDENTIALS_JSON: '{"project_id":"vision-proj"}',
      FIREBASE_SERVICE_ACCOUNT_JSON: '{"project_id":"fb-proj"}',
    };
    expect(resolveVisionCredentials(env).credentials.project_id).toBe('vision-proj');
  });

  test('falls back to the Firebase service account', () => {
    const env = { FIREBASE_SERVICE_ACCOUNT_JSON: '{"project_id":"fb-proj"}' };
    expect(resolveVisionCredentials(env).credentials.project_id).toBe('fb-proj');
  });

  test('throws VISION_AUTH when nothing is configured', () => {
    expect(() => resolveVisionCredentials({})).toThrow(/VISION_AUTH|not configured/);
    try { resolveVisionCredentials({}); } catch (e) { expect(e.code).toBe('VISION_AUTH'); }
  });

  test('throws VISION_AUTH on unparseable JSON', () => {
    try {
      resolveVisionCredentials({ GOOGLE_CLOUD_VISION_CREDENTIALS_JSON: 'not json' });
    } catch (e) {
      expect(e.code).toBe('VISION_AUTH');
    }
  });
});

describe('recognizeWords', () => {
  const visionResponse = {
    fullTextAnnotation: {
      text: 'JEZL ANTOINETTE',
      pages: [{
        blocks: [{
          paragraphs: [{
            words: [
              {
                confidence: 0.93,
                boundingBox: { vertices: [{x:120,y:100},{x:180,y:100},{x:180,y:122},{x:120,y:122}] },
                symbols: [{ text: 'J' }, { text: 'E' }, { text: 'Z' }, { text: 'L' }],
              },
              {
                confidence: 0.71,
                boundingBox: { vertices: [{x:190,y:100},{x:300,y:100},{x:300,y:122},{x:190,y:122}] },
                symbols: 'ANTOINETTE'.split('').map((t) => ({ text: t })),
              },
            ],
          }],
        }],
      }],
    },
  };

  const fakeClient = (response) => ({ documentTextDetection: async () => [response] });

  test('normalizes words to text + vertices + confidence', async () => {
    const { words, fullText } = await recognizeWords(Buffer.from('x'), { client: fakeClient(visionResponse) });
    expect(fullText).toBe('JEZL ANTOINETTE');
    expect(words).toHaveLength(2);
    expect(words[0].text).toBe('JEZL');
    expect(words[0].confidence).toBeCloseTo(0.93);
    expect(words[0].vertices[0]).toEqual({ x: 120, y: 100 });
    expect(words[1].text).toBe('ANTOINETTE');
  });

  test('throws NO_TEXT_FOUND on an empty annotation', async () => {
    try {
      await recognizeWords(Buffer.from('x'), { client: fakeClient({}) });
      throw new Error('should have thrown');
    } catch (e) {
      expect(e.code).toBe('NO_TEXT_FOUND');
    }
  });

  test('maps a quota error to VISION_QUOTA', async () => {
    const client = { documentTextDetection: async () => { const e = new Error('quota'); e.code = 8; throw e; } };
    try {
      await recognizeWords(Buffer.from('x'), { client });
    } catch (e) {
      expect(e.code).toBe('VISION_QUOTA');
    }
  });

  test('maps an auth error to VISION_AUTH', async () => {
    const client = { documentTextDetection: async () => { const e = new Error('denied'); e.code = 7; throw e; } };
    try {
      await recognizeWords(Buffer.from('x'), { client });
    } catch (e) {
      expect(e.code).toBe('VISION_AUTH');
    }
  });

  test('maps anything else to VISION_UNAVAILABLE', async () => {
    const client = { documentTextDetection: async () => { throw new Error('socket hang up'); } };
    try {
      await recognizeWords(Buffer.from('x'), { client });
    } catch (e) {
      expect(e.code).toBe('VISION_UNAVAILABLE');
    }
  });
});
```

- [ ] **Step 3: Run test to verify it fails**

Run: `cd backend && npx jest src/services/baptismal_ocr_service.test.js`
Expected: FAIL — `Cannot find module './baptismal_ocr_service'`

- [ ] **Step 4: Implement**

Create `backend/src/services/baptismal_ocr_service.js`:

```js
/**
 * Google Cloud Vision I/O for baptismal register scans.
 *
 * This module is the ONLY place Vision is called. It performs no layout
 * analysis — see baptismal_register_layout.js for that. Credentials never
 * leave the server.
 */

function codedError(message, code) {
  const err = new Error(message);
  err.code = code;
  return err;
}

/**
 * Resolves Vision service-account credentials from the environment.
 * Prefers a dedicated Vision key; falls back to the Firebase service account
 * because it belongs to the same GCP project (the Vision API just needs
 * enabling on it).
 */
function resolveVisionCredentials(env) {
  const raw =
    env.GOOGLE_CLOUD_VISION_CREDENTIALS_JSON || env.FIREBASE_SERVICE_ACCOUNT_JSON;
  if (!raw) {
    throw codedError(
      'VISION_AUTH: no Vision credentials configured (set GOOGLE_CLOUD_VISION_CREDENTIALS_JSON)',
      'VISION_AUTH',
    );
  }
  try {
    return { credentials: JSON.parse(raw) };
  } catch (e) {
    throw codedError('VISION_AUTH: credentials JSON is not parseable', 'VISION_AUTH');
  }
}

let cachedClient = null;

function defaultClient(env) {
  if (cachedClient) return cachedClient;
  // Required lazily so unit tests can inject a fake client without the
  // real SDK (or credentials) being present.
  const vision = require('@google-cloud/vision');
  cachedClient = new vision.ImageAnnotatorClient(resolveVisionCredentials(env));
  return cachedClient;
}

// gRPC status codes we care about: 7 = PERMISSION_DENIED, 16 = UNAUTHENTICATED,
// 8 = RESOURCE_EXHAUSTED (quota).
function mapVisionError(err) {
  if (err.code === 'NO_TEXT_FOUND' || err.code === 'VISION_AUTH') return err;
  if (err.code === 7 || err.code === 16) {
    return codedError('VISION_AUTH: Vision rejected the credentials', 'VISION_AUTH');
  }
  if (err.code === 8) {
    return codedError('VISION_QUOTA: Vision quota exceeded', 'VISION_QUOTA');
  }
  return codedError('VISION_UNAVAILABLE: could not reach Vision', 'VISION_UNAVAILABLE');
}

function wordText(word) {
  return (word.symbols || []).map((s) => s.text || '').join('');
}

/**
 * Runs handwriting-capable OCR and normalizes the response.
 * @returns {Promise<{words: Array, fullText: string}>}
 */
async function recognizeWords(imageBuffer, options = {}) {
  const client = options.client || defaultClient(options.env || process.env);
  let response;
  try {
    const [result] = await client.documentTextDetection({
      image: { content: imageBuffer },
      imageContext: { languageHints: ['en'] },
    });
    response = result;
  } catch (e) {
    throw mapVisionError(e);
  }

  const annotation = response && response.fullTextAnnotation;
  if (!annotation || !annotation.text) {
    throw codedError('NO_TEXT_FOUND: Vision found no text in the image', 'NO_TEXT_FOUND');
  }

  const words = [];
  for (const page of annotation.pages || []) {
    for (const block of page.blocks || []) {
      for (const paragraph of block.paragraphs || []) {
        for (const word of paragraph.words || []) {
          const text = wordText(word).trim();
          if (!text) continue;
          const vertices = ((word.boundingBox || {}).vertices || []).map((v) => ({
            x: v.x || 0,
            y: v.y || 0,
          }));
          if (vertices.length !== 4) continue;
          words.push({
            text,
            vertices,
            confidence: typeof word.confidence === 'number' ? word.confidence : 0,
          });
        }
      }
    }
  }

  if (words.length === 0) {
    throw codedError('NO_TEXT_FOUND: no readable words in the image', 'NO_TEXT_FOUND');
  }

  return { words, fullText: annotation.text };
}

module.exports = { resolveVisionCredentials, recognizeWords };
```

- [ ] **Step 5: Run tests**

Run: `cd backend && npx jest src/services/baptismal_ocr_service.test.js`
Expected: PASS — 9 tests.

- [ ] **Step 6: Commit**

```bash
git add backend/src/services/baptismal_ocr_service.js backend/src/services/baptismal_ocr_service.test.js backend/package.json backend/package-lock.json
git commit -m "feat(ocr): add Cloud Vision client service for baptismal scans"
```

---

### Task 2: Fixture helper + orientation normalization

**Files:**
- Create: `backend/test/helpers/register_fixture.js`
- Create: `backend/src/services/baptismal_register_layout.js`
- Test: `backend/src/services/baptismal_register_layout.test.js`

**Interfaces:**
- Consumes: the normalized word shape from Task 1.
- Produces:
  - `buildRegisterFixture({ rotation = 0, rows = 3 })` → `{ words }` — a synthetic two-page spread with printed headers and handwritten cells, rotated by 0/90/180/270.
  - `boxOf(word)` → `{ x0, y0, x1, y1, cx, cy, w, h }`
  - `normalizeOrientation(words)` → `{ rotation: 0|90|180|270, words }` with vertices rotated so text reads left-to-right.

- [ ] **Step 1: Write the fixture helper**

Create `backend/test/helpers/register_fixture.js`:

```js
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
```

- [ ] **Step 2: Write the failing test**

Create `backend/src/services/baptismal_register_layout.test.js`:

```js
const { boxOf, normalizeOrientation } = require('./baptismal_register_layout');
const { buildRegisterFixture } = require('../../test/helpers/register_fixture');

describe('boxOf', () => {
  test('returns the axis-aligned bounds and center', () => {
    const w = {
      text: 'X',
      vertices: [{ x: 10, y: 20 }, { x: 30, y: 20 }, { x: 30, y: 40 }, { x: 10, y: 40 }],
      confidence: 1,
    };
    expect(boxOf(w)).toEqual({ x0: 10, y0: 20, x1: 30, y1: 40, cx: 20, cy: 30, w: 20, h: 20 });
  });
});

describe('normalizeOrientation', () => {
  test('leaves an upright page alone', () => {
    const { words } = buildRegisterFixture({ rotation: 0 });
    const out = normalizeOrientation(words);
    expect(out.rotation).toBe(0);
  });

  for (const rotation of [90, 180, 270]) {
    test(`recovers a page rotated ${rotation} degrees`, () => {
      const upright = normalizeOrientation(buildRegisterFixture({ rotation: 0 }).words);
      const rotated = normalizeOrientation(buildRegisterFixture({ rotation }).words);

      // Same reading frame: the header row must sit above the first data row,
      // and 'NO.' must be leftmost, exactly as in the upright page.
      const headerOf = (out, text) => out.words.find((w) => w.text === text);
      expect(boxOf(headerOf(rotated, 'NO.')).cy).toBeLessThan(
        boxOf(headerOf(rotated, 'JEZL')).cy,
      );
      expect(boxOf(headerOf(rotated, 'NO.')).cx).toBeLessThan(
        boxOf(headerOf(rotated, 'JEZL')).cx,
      );
      expect(rotated.words).toHaveLength(upright.words.length);
    });
  }
});
```

- [ ] **Step 3: Run test to verify it fails**

Run: `cd backend && npx jest src/services/baptismal_register_layout.test.js`
Expected: FAIL — `Cannot find module './baptismal_register_layout'`

- [ ] **Step 4: Implement**

Create `backend/src/services/baptismal_register_layout.js`:

```js
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
```

- [ ] **Step 5: Run tests**

Run: `cd backend && npx jest src/services/baptismal_register_layout.test.js`
Expected: PASS — 5 tests.

If a rotation case fails, the bug is almost certainly the inverse-rotation
mapping in `rotatePointBack`. Verify by rotating a single known point through
`register_fixture.rotatePoint` and back; they must round-trip.

- [ ] **Step 6: Commit**

```bash
git add backend/test/helpers/register_fixture.js backend/src/services/baptismal_register_layout.js backend/src/services/baptismal_register_layout.test.js
git commit -m "feat(ocr): add register fixture helper and orientation normalization"
```

---

### Task 3: Gutter split

**Files:**
- Modify: `backend/src/services/baptismal_register_layout.js`
- Test: `backend/src/services/baptismal_register_layout.test.js`

**Interfaces:**
- Consumes: `boxOf`, `normalizeOrientation` (Task 2).
- Produces: `splitSpread(words)` → `{ gutterX: number, left: Word[], right: Word[], confirmed: boolean }`. `confirmed` is true when the "Baptismal" and "Register" page titles were found on their expected sides.

- [ ] **Step 1: Write the failing test**

Append to `backend/src/services/baptismal_register_layout.test.js`:

```js
const { splitSpread } = require('./baptismal_register_layout');
const { GUTTER_X0, GUTTER_X1 } = require('../../test/helpers/register_fixture');

describe('splitSpread', () => {
  test('finds the gutter and confirms it via the page titles', () => {
    const { words } = normalizeOrientation(buildRegisterFixture({ rotation: 0 }).words);
    const out = splitSpread(words);
    expect(out.gutterX).toBeGreaterThanOrEqual(GUTTER_X0 - 60);
    expect(out.gutterX).toBeLessThanOrEqual(GUTTER_X1 + 60);
    expect(out.confirmed).toBe(true);
    expect(out.left.some((w) => w.text === 'CHILD')).toBe(true);
    expect(out.right.some((w) => w.text === 'MINISTER')).toBe(true);
    expect(out.left.some((w) => w.text === 'MINISTER')).toBe(false);
  });

  test('splits correctly on a rotated page too', () => {
    const { words } = normalizeOrientation(buildRegisterFixture({ rotation: 180 }).words);
    const out = splitSpread(words);
    expect(out.left.some((w) => w.text === 'CHILD')).toBe(true);
    expect(out.right.some((w) => w.text === 'SPONSORS')).toBe(true);
  });

  test('reports unconfirmed when the page titles are missing', () => {
    const { words } = normalizeOrientation(buildRegisterFixture({ rotation: 0 }).words);
    const stripped = words.filter((w) => w.text !== 'Baptismal' && w.text !== 'Register');
    expect(splitSpread(stripped).confirmed).toBe(false);
  });
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd backend && npx jest src/services/baptismal_register_layout.test.js -t splitSpread`
Expected: FAIL — `splitSpread is not a function`

- [ ] **Step 3: Implement**

Add to `backend/src/services/baptismal_register_layout.js` (before `module.exports`):

```js
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

  const hasTitle = (list, title) =>
    list.some((w) => w.text.toLowerCase() === title);
  const confirmed = hasTitle(left, 'baptismal') && hasTitle(right, 'register');

  return { gutterX: bestX, left, right, confirmed };
}
```

Add `splitSpread` to `module.exports`.

- [ ] **Step 4: Run tests**

Run: `cd backend && npx jest src/services/baptismal_register_layout.test.js`
Expected: PASS — 8 tests.

- [ ] **Step 5: Commit**

```bash
git add backend/src/services/baptismal_register_layout.js backend/src/services/baptismal_register_layout.test.js
git commit -m "feat(ocr): split register spread at the gutter"
```

---

### Task 4: Column calibration

**Files:**
- Modify: `backend/src/services/baptismal_register_layout.js`
- Test: `backend/src/services/baptismal_register_layout.test.js`

**Interfaces:**
- Consumes: `boxOf`, `splitSpread`.
- Produces:
  - `LEFT_COLUMNS` / `RIGHT_COLUMNS` — column descriptors `{ key, header, fallbackRatio }`.
  - `calibrateColumns(pageWords, columnDefs)` → `{ columns: [{ key, x0, x1, matched }], warnings: string[] }`. Column x-bands are the midpoints between adjacent matched header centers. Unmatched headers fall back to `fallbackRatio` of the page width and add a `LAYOUT_UNCERTAIN` warning.

- [ ] **Step 1: Write the failing test**

Append to the layout test file:

```js
const { calibrateColumns, LEFT_COLUMNS, RIGHT_COLUMNS } = require('./baptismal_register_layout');

describe('calibrateColumns', () => {
  const pages = () => {
    const { words } = normalizeOrientation(buildRegisterFixture({ rotation: 0 }).words);
    return splitSpread(words);
  };

  test('matches every left-page header', () => {
    const { columns, warnings } = calibrateColumns(pages().left, LEFT_COLUMNS);
    expect(columns.map((c) => c.key)).toEqual([
      'lineNo', 'nameOfChild', 'placeAndBirthDate', 'legitimacy', 'parents',
    ]);
    expect(columns.every((c) => c.matched)).toBe(true);
    expect(warnings).toEqual([]);
  });

  test('matches every right-page header', () => {
    const { columns, warnings } = calibrateColumns(pages().right, RIGHT_COLUMNS);
    expect(columns.map((c) => c.key)).toEqual([
      'residentsOf', 'dateOfBaptism', 'minister', 'sponsors', 'observations',
    ]);
    expect(columns.every((c) => c.matched)).toBe(true);
    expect(warnings).toEqual([]);
  });

  test('produces bands in ascending, non-overlapping order', () => {
    const { columns } = calibrateColumns(pages().left, LEFT_COLUMNS);
    for (let i = 1; i < columns.length; i += 1) {
      expect(columns[i].x0).toBeGreaterThanOrEqual(columns[i - 1].x1 - 0.001);
    }
  });

  test('falls back and warns when a header is unreadable', () => {
    const { words } = normalizeOrientation(
      buildRegisterFixture({ rotation: 0, omitHeaders: ['L or ILL'] }).words,
    );
    const { columns, warnings } = calibrateColumns(splitSpread(words).left, LEFT_COLUMNS);
    expect(warnings).toContain('LAYOUT_UNCERTAIN');
    expect(columns.find((c) => c.key === 'legitimacy').matched).toBe(false);
    expect(columns).toHaveLength(5);
  });

  test('warns when no header matches at all', () => {
    const { warnings } = calibrateColumns([], LEFT_COLUMNS);
    expect(warnings).toContain('LAYOUT_UNCERTAIN');
  });

  // Regression: matching on 'name' hits both "NAME OF CHILD" and "NAME OF
  // PARENTS", averaging them into a center over the birth-date column.
  test('does not let the parents header drag the child-name column right', () => {
    const { columns } = calibrateColumns(pages().left, LEFT_COLUMNS);
    const name = columns.find((c) => c.key === 'nameOfChild');
    const place = columns.find((c) => c.key === 'placeAndBirthDate');
    expect(name.x1).toBeLessThanOrEqual(place.x0 + 0.001);
    // The child's given name sits at x=160 in the fixture; it must land in the
    // name column, not in lineNo or place.
    expect(160).toBeGreaterThanOrEqual(name.x0);
    expect(160).toBeLessThan(name.x1);
  });
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd backend && npx jest src/services/baptismal_register_layout.test.js -t calibrateColumns`
Expected: FAIL — `calibrateColumns is not a function`

- [ ] **Step 3: Implement**

Add to the layout module:

```js
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

const HEADER_BAND_RATIO = 0.25; // headers live in the top quarter of the page

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
    if (tokens.some((t) => text === t || text.startsWith(t))) hits.push(b.cx);
  }
  if (hits.length === 0) return null;
  return hits.reduce((a, b) => a + b, 0) / hits.length;
}

/**
 * Calibrates column x-bands for one page.
 * @returns {{columns: Array<{key,x0,x1,matched}>, warnings: string[]}}
 */
function calibrateColumns(pageWords, columnDefs) {
  const warnings = [];
  if (!pageWords || pageWords.length === 0) {
    return { columns: [], warnings: ['LAYOUT_UNCERTAIN'] };
  }

  const boxes = pageWords.map(boxOf);
  const minX = Math.min(...boxes.map((b) => b.x0));
  const maxX = Math.max(...boxes.map((b) => b.x1));
  const minY = Math.min(...boxes.map((b) => b.y0));
  const maxY = Math.max(...boxes.map((b) => b.y1));
  const width = maxX - minX;
  const band = { headerMaxY: minY + (maxY - minY) * HEADER_BAND_RATIO };

  const centers = columnDefs.map((def) => {
    const found = findHeaderCenter(pageWords, def.header, band);
    return {
      key: def.key,
      center: found === null ? minX + width * def.fallbackRatio : found,
      matched: found !== null,
    };
  });

  if (centers.some((c) => !c.matched)) warnings.push('LAYOUT_UNCERTAIN');

  // Bands are the midpoints between adjacent column centers.
  const columns = centers.map((c, i) => {
    const prev = centers[i - 1];
    const next = centers[i + 1];
    const x0 = prev ? (prev.center + c.center) / 2 : minX - 1;
    const x1 = next ? (c.center + next.center) / 2 : maxX + 1;
    return { key: c.key, x0, x1, matched: c.matched };
  });

  return { columns, warnings };
}
```

Add `LEFT_COLUMNS`, `RIGHT_COLUMNS`, `calibrateColumns` to `module.exports`.

- [ ] **Step 4: Run tests**

Run: `cd backend && npx jest src/services/baptismal_register_layout.test.js`
Expected: PASS — 13 tests.

- [ ] **Step 5: Commit**

```bash
git add backend/src/services/baptismal_register_layout.js backend/src/services/baptismal_register_layout.test.js
git commit -m "feat(ocr): calibrate register column bands from printed headers"
```

---

### Task 5: Row detection

**Files:**
- Modify: `backend/src/services/baptismal_register_layout.js`
- Test: `backend/src/services/baptismal_register_layout.test.js`

**Interfaces:**
- Consumes: `boxOf`, `calibrateColumns`.
- Produces: `detectRows(pageWords, columns)` → `{ rows: [{ index, lineNo, y0, y1 }], warnings: string[] }`. Anchored on the `lineNo` column's numerals; falls back to y-clustering of all page words and warns `ROW_ANCHOR_FALLBACK`.

- [ ] **Step 1: Write the failing test**

Append to the layout test file:

```js
const { detectRows } = require('./baptismal_register_layout');

describe('detectRows', () => {
  const leftPage = (opts = {}) => {
    const { words } = normalizeOrientation(buildRegisterFixture({ rows: 6, ...opts }).words);
    const left = splitSpread(words).left;
    return { left, columns: calibrateColumns(left, LEFT_COLUMNS).columns };
  };

  test('anchors rows on the NO. column', () => {
    const { left, columns } = leftPage();
    const { rows, warnings } = detectRows(left, columns);
    expect(rows).toHaveLength(6);
    expect(rows.map((r) => r.lineNo)).toEqual(['1', '2', '3', '4', '5', '6']);
    expect(warnings).toEqual([]);
  });

  test('rows are ordered top to bottom and do not overlap', () => {
    const { left, columns } = leftPage();
    const { rows } = detectRows(left, columns);
    for (let i = 1; i < rows.length; i += 1) {
      expect(rows[i].y0).toBeGreaterThanOrEqual(rows[i - 1].y1 - 0.001);
    }
  });

  test('falls back to y-clustering when the NO. column is unreadable', () => {
    const { left, columns } = leftPage({ omitNoColumn: true });
    const { rows, warnings } = detectRows(left, columns);
    expect(warnings).toContain('ROW_ANCHOR_FALLBACK');
    expect(rows).toHaveLength(6);
    expect(rows[0].lineNo).toBe(null);
  });

  test('returns no rows for an empty page', () => {
    expect(detectRows([], []).rows).toEqual([]);
  });
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd backend && npx jest src/services/baptismal_register_layout.test.js -t detectRows`
Expected: FAIL — `detectRows is not a function`

- [ ] **Step 3: Implement**

Add to the layout module:

```js
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
 * Primary anchor: the numerals in the lineNo column. Fallback: y-clustering
 * across every word on the page, which is noisier and therefore warns.
 */
function detectRows(pageWords, columns) {
  const warnings = [];
  if (!pageWords || pageWords.length === 0) return { rows: [], warnings };

  const lineNoCol = (columns || []).find((c) => c.key === 'lineNo');
  const boxes = pageWords.map((w) => ({ ...boxOf(w), text: w.text }));
  const tolerance = medianHeight(boxes) * 0.9;
  const headerMaxY =
    Math.min(...boxes.map((b) => b.y0)) +
    (Math.max(...boxes.map((b) => b.y1)) - Math.min(...boxes.map((b) => b.y0))) *
      HEADER_BAND_RATIO;

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

  let clusters;
  if (anchors.length >= 2) {
    clusters = clusterByY(anchors, tolerance).map((c) => ({
      cy: c.cy,
      lineNo: c.members[0].text,
    }));
  } else {
    warnings.push('ROW_ANCHOR_FALLBACK');
    clusters = clusterByY(
      boxes.filter((b) => b.cy > headerMaxY),
      tolerance,
    ).map((c) => ({ cy: c.cy, lineNo: null }));
  }

  if (clusters.length === 0) return { rows: [], warnings };

  // Row bands are the midpoints between adjacent anchors; the first and last
  // extend by half the median row pitch.
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
```

Add `detectRows` to `module.exports`.

- [ ] **Step 4: Run tests**

Run: `cd backend && npx jest src/services/baptismal_register_layout.test.js`
Expected: PASS — 17 tests.

- [ ] **Step 5: Commit**

```bash
git add backend/src/services/baptismal_register_layout.js backend/src/services/baptismal_register_layout.test.js
git commit -m "feat(ocr): detect register row bands from the NO. column"
```

---

### Task 6: Cell assignment

**Files:**
- Modify: `backend/src/services/baptismal_register_layout.js`
- Test: `backend/src/services/baptismal_register_layout.test.js`

**Interfaces:**
- Consumes: `boxOf`, `calibrateColumns`, `detectRows`.
- Produces: `assignCells(pageWords, columns, rows)` → `Array<Record<string, {value: string, confidence: number}>>`, one entry per row, keyed by column key. Words within a cell are joined in reading order (top-to-bottom by line, then left-to-right).

Sub-column note: `nameOfChild`, `parents` and `sponsors` are physically two sub-columns. They are treated as one band here and joined with a space; the ` / ` separator for `parents` and `sponsors` is applied in Task 7 where sub-column geometry is known.

- [ ] **Step 1: Write the failing test**

Append to the layout test file:

```js
const { assignCells } = require('./baptismal_register_layout');

describe('assignCells', () => {
  const setup = () => {
    const { words } = normalizeOrientation(buildRegisterFixture({ rows: 3 }).words);
    const { left, right } = splitSpread(words);
    const leftCols = calibrateColumns(left, LEFT_COLUMNS).columns;
    const rightCols = calibrateColumns(right, RIGHT_COLUMNS).columns;
    return {
      left, right, leftCols, rightCols,
      leftRows: detectRows(left, leftCols).rows,
      rightRows: detectRows(right, rightCols).rows,
    };
  };

  test('places handwriting in the correct left-page columns', () => {
    const s = setup();
    const cells = assignCells(s.left, s.leftCols, s.leftRows);
    expect(cells).toHaveLength(3);
    expect(cells[0].nameOfChild.value).toBe('JEZL ANTOINETTE HITUTUAAN');
    expect(cells[0].placeAndBirthDate.value).toBe('19 FEBRUARY 2001');
    expect(cells[0].parents.value).toBe('LITA HITUTUAAN');
    expect(cells[1].nameOfChild.value).toBe('JULLIE PACITO');
  });

  test('places handwriting in the correct right-page columns', () => {
    const s = setup();
    const cells = assignCells(s.right, s.rightCols, s.rightRows);
    expect(cells[0].dateOfBaptism.value).toBe('12 MAY 2016');
    expect(cells[0].minister.value).toBe('FR. PABLITO ARCAPA');
    expect(cells[2].dateOfBaptism.value).toBe('22 MAY 2016');
  });

  test('averages word confidence per cell', () => {
    const { words } = normalizeOrientation(
      buildRegisterFixture({ rows: 1, confidence: 0.4 }).words,
    );
    const { left } = splitSpread(words);
    const cols = calibrateColumns(left, LEFT_COLUMNS).columns;
    const rows = detectRows(left, cols).rows;
    const cells = assignCells(left, cols, rows);
    expect(cells[0].nameOfChild.confidence).toBeCloseTo(0.4, 2);
  });

  test('leaves an unwritten column empty rather than guessing', () => {
    const s = setup();
    const cells = assignCells(s.left, s.leftCols, s.leftRows);
    expect(cells[0].legitimacy.value).toBe('');
    expect(cells[0].legitimacy.confidence).toBe(0);
  });

  test('never assigns header words to a data row', () => {
    const s = setup();
    const cells = assignCells(s.left, s.leftCols, s.leftRows);
    const all = cells.map((c) => Object.values(c).map((f) => f.value).join(' ')).join(' ');
    expect(all).not.toContain('CHILD');
    expect(all).not.toContain('PARENTS');
  });
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd backend && npx jest src/services/baptismal_register_layout.test.js -t assignCells`
Expected: FAIL — `assignCells is not a function`

- [ ] **Step 3: Implement**

Add to the layout module:

```js
/**
 * Assigns every word to exactly one (row, column) cell by box center.
 *
 * A word whose center falls outside every row band or every column band is
 * dropped — that is deliberate. Guessing is worse than an empty field the
 * reviewer can see and fill in.
 */
function assignCells(pageWords, columns, rows) {
  const cells = rows.map(() => {
    const row = {};
    for (const col of columns) row[col.key] = { words: [] };
    return row;
  });

  for (const w of pageWords) {
    const b = boxOf(w);
    const rowIndex = rows.findIndex((r) => b.cy >= r.y0 && b.cy < r.y1);
    if (rowIndex === -1) continue;
    const col = columns.find((c) => b.cx >= c.x0 && b.cx < c.x1);
    if (!col) continue;
    cells[rowIndex][col.key].words.push({ text: w.text, confidence: w.confidence, box: b });
  }

  return cells.map((row) => {
    const out = {};
    for (const key of Object.keys(row)) {
      const items = row[key].words;
      if (items.length === 0) {
        out[key] = { value: '', confidence: 0 };
        continue;
      }
      // Reading order: group into lines by y, then left-to-right within a line.
      const lineTolerance = medianHeight(items.map((i) => i.box)) * 0.7;
      const sorted = [...items].sort((a, b) => {
        if (Math.abs(a.box.cy - b.box.cy) > lineTolerance) return a.box.cy - b.box.cy;
        return a.box.cx - b.box.cx;
      });
      const value = sorted.map((i) => i.text).join(' ').replace(/\s+/g, ' ').trim();
      const confidence =
        sorted.reduce((sum, i) => sum + (i.confidence || 0), 0) / sorted.length;
      out[key] = { value, confidence };
    }
    return out;
  });
}
```

Add `assignCells` to `module.exports`.

- [ ] **Step 4: Run tests**

Run: `cd backend && npx jest src/services/baptismal_register_layout.test.js`
Expected: PASS — 22 tests.

- [ ] **Step 5: Commit**

```bash
git add backend/src/services/baptismal_register_layout.js backend/src/services/baptismal_register_layout.test.js
git commit -m "feat(ocr): assign register words to row/column cells"
```

---

### Task 7: Page join, fill-down, and the orchestrator

**Files:**
- Modify: `backend/src/services/baptismal_register_layout.js`
- Test: `backend/src/services/baptismal_register_layout.test.js`

**Interfaces:**
- Consumes: everything from Tasks 2–6.
- Produces:
  - `joinPages(leftCells, rightCells, leftRows)` → `{ rows, warnings }` — index join; a row-count mismatch warns `ROW_COUNT_MISMATCH` and joins the overlap.
  - `applyFillDown(rows)` → `{ rows, filled: number }` — fills only `minister` and `dateOfBaptism`, only into empty/ditto cells, tagging `inherited: true`.
  - `extractBaptismalRows(words)` → `{ rows, rotation, gutterX, columns: { left, right }, warnings }` — the single entry point the route calls. Throws an error with `.code = 'LAYOUT_UNRECOGNIZED'` when no column header matched on either page.

- [ ] **Step 1: Write the failing test**

Append to the layout test file:

```js
const { joinPages, applyFillDown, extractBaptismalRows } = require('./baptismal_register_layout');

describe('applyFillDown', () => {
  const row = (over) => ({
    lineNo: '1',
    fields: {
      nameOfChild: { value: 'A', confidence: 0.9 },
      dateOfBaptism: { value: '', confidence: 0 },
      minister: { value: '', confidence: 0 },
      sponsors: { value: '', confidence: 0 },
      ...over,
    },
  });

  test('fills empty minister and date from the row above, tagged inherited', () => {
    const rows = [
      row({ dateOfBaptism: { value: '12 MAY 2016', confidence: 0.9 }, minister: { value: 'FR. ARCAPA', confidence: 0.9 } }),
      row(),
    ];
    const { rows: out, filled } = applyFillDown(rows);
    expect(out[1].fields.dateOfBaptism.value).toBe('12 MAY 2016');
    expect(out[1].fields.dateOfBaptism.inherited).toBe(true);
    expect(out[1].fields.minister.inherited).toBe(true);
    expect(out[0].fields.dateOfBaptism.inherited).toBe(false);
    expect(filled).toBe(2);
  });

  test('treats a ditto mark as empty', () => {
    const rows = [
      row({ minister: { value: 'FR. ARCAPA', confidence: 0.9 } }),
      row({ minister: { value: '-do-', confidence: 0.5 } }),
    ];
    expect(applyFillDown(rows).rows[1].fields.minister.value).toBe('FR. ARCAPA');
  });

  test('never fills sponsors or names', () => {
    const rows = [
      row({ sponsors: { value: 'JOMARIE POL', confidence: 0.9 } }),
      row(),
    ];
    const out = applyFillDown(rows).rows;
    expect(out[1].fields.sponsors.value).toBe('');
    expect(out[1].fields.nameOfChild.value).toBe('A');
  });

  test('leaves a real value alone', () => {
    const rows = [
      row({ minister: { value: 'FR. ARCAPA', confidence: 0.9 } }),
      row({ minister: { value: 'FR. JEZON', confidence: 0.9 } }),
    ];
    expect(applyFillDown(rows).rows[1].fields.minister.value).toBe('FR. JEZON');
    expect(applyFillDown(rows).rows[1].fields.minister.inherited).toBe(false);
  });
});

describe('joinPages', () => {
  test('joins left and right by row index', () => {
    const left = [{ nameOfChild: { value: 'A', confidence: 0.9 } }];
    const right = [{ minister: { value: 'FR. X', confidence: 0.8 } }];
    const { rows, warnings } = joinPages(left, right, [{ lineNo: '1' }]);
    expect(rows).toHaveLength(1);
    expect(rows[0].lineNo).toBe('1');
    expect(rows[0].fields.nameOfChild.value).toBe('A');
    expect(rows[0].fields.minister.value).toBe('FR. X');
    expect(warnings).toEqual([]);
  });

  test('warns and joins the overlap on a row-count mismatch', () => {
    const left = [{ nameOfChild: { value: 'A', confidence: 1 } }, { nameOfChild: { value: 'B', confidence: 1 } }];
    const right = [{ minister: { value: 'FR. X', confidence: 1 } }];
    const { rows, warnings } = joinPages(left, right, [{ lineNo: '1' }, { lineNo: '2' }]);
    expect(warnings).toContain('ROW_COUNT_MISMATCH');
    expect(rows).toHaveLength(2);
    expect(rows[1].fields.minister.value).toBe('');
  });
});

describe('extractBaptismalRows', () => {
  test('extracts a full spread end to end', () => {
    const { words } = buildRegisterFixture({ rows: 3, rotation: 0 });
    const out = extractBaptismalRows(words);
    expect(out.rotation).toBe(0);
    expect(out.rows).toHaveLength(3);
    expect(out.rows[0].fields.nameOfChild.value).toBe('JEZL ANTOINETTE HITUTUAAN');
    expect(out.rows[0].fields.dateOfBaptism.value).toBe('12 MAY 2016');
    expect(out.rows[0].fields.parents.value).toBe('LITA HITUTUAAN');
    expect(out.rows[0].lineNo).toBe('1');
  });

  test('produces identical field values regardless of page rotation', () => {
    const upright = extractBaptismalRows(buildRegisterFixture({ rows: 3, rotation: 0 }).words);
    for (const rotation of [90, 180, 270]) {
      const rotated = extractBaptismalRows(buildRegisterFixture({ rows: 3, rotation }).words);
      expect(rotated.rows.map((r) => r.fields.nameOfChild.value))
        .toEqual(upright.rows.map((r) => r.fields.nameOfChild.value));
      expect(rotated.rotation).toBe(rotation);
    }
  });

  test('throws LAYOUT_UNRECOGNIZED when nothing looks like a register', () => {
    const junk = [
      { text: 'HELLO', vertices: [{x:0,y:0},{x:50,y:0},{x:50,y:20},{x:0,y:20}], confidence: 0.9 },
      { text: 'WORLD', vertices: [{x:60,y:0},{x:110,y:0},{x:110,y:20},{x:60,y:20}], confidence: 0.9 },
    ];
    try {
      extractBaptismalRows(junk);
      throw new Error('should have thrown');
    } catch (e) {
      expect(e.code).toBe('LAYOUT_UNRECOGNIZED');
    }
  });
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd backend && npx jest src/services/baptismal_register_layout.test.js -t extractBaptismalRows`
Expected: FAIL — `extractBaptismalRows is not a function`

- [ ] **Step 3: Implement**

Add to the layout module:

```js
const ALL_KEYS = [
  ...LEFT_COLUMNS.map((c) => c.key).filter((k) => k !== 'lineNo'),
  ...RIGHT_COLUMNS.map((c) => c.key),
];

const DITTO = /^(-?\s*do\s*-?|["”]|,,|-{2,})$/i;

function isEmptyCell(field) {
  const v = (field && field.value ? field.value : '').trim();
  return v === '' || DITTO.test(v);
}

/** Joins left- and right-page cells into whole register rows by index. */
function joinPages(leftCells, rightCells, leftRows) {
  const warnings = [];
  const count = Math.max(leftCells.length, rightCells.length);
  if (leftCells.length !== rightCells.length) warnings.push('ROW_COUNT_MISMATCH');

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
 * Full pipeline: raw Vision words in, register rows out.
 * @throws {Error} with .code = 'LAYOUT_UNRECOGNIZED'
 */
function extractBaptismalRows(words) {
  const oriented = normalizeOrientation(words);
  const spread = splitSpread(oriented.words);

  const leftCal = calibrateColumns(spread.left, LEFT_COLUMNS);
  const rightCal = calibrateColumns(spread.right, RIGHT_COLUMNS);

  const matchedCount =
    leftCal.columns.filter((c) => c.matched).length +
    rightCal.columns.filter((c) => c.matched).length;
  if (matchedCount < 3) {
    const err = new Error(
      'LAYOUT_UNRECOGNIZED: this does not look like a baptismal register page',
    );
    err.code = 'LAYOUT_UNRECOGNIZED';
    throw err;
  }

  const leftRows = detectRows(spread.left, leftCal.columns);
  const rightRows = detectRows(spread.right, rightCal.columns);

  const leftCells = assignCells(spread.left, leftCal.columns, leftRows.rows);
  const rightCells = assignCells(spread.right, rightCal.columns, rightRows.rows);

  const joined = joinPages(leftCells, rightCells, leftRows.rows);
  const { rows } = applyFillDown(joined.rows);

  const warnings = [
    ...new Set([
      ...leftCal.warnings,
      ...rightCal.warnings,
      ...leftRows.warnings,
      ...rightRows.warnings,
      ...joined.warnings,
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
```

Add `joinPages`, `applyFillDown`, `extractBaptismalRows` to `module.exports`.

- [ ] **Step 4: Run tests**

Run: `cd backend && npx jest src/services/baptismal_register_layout.test.js`
Expected: PASS — 31 tests.

- [ ] **Step 5: Commit**

```bash
git add backend/src/services/baptismal_register_layout.js backend/src/services/baptismal_register_layout.test.js
git commit -m "feat(ocr): join register pages, fill down repeats, add orchestrator"
```

---

### Task 8: Image preprocessing

**Files:**
- Create: `backend/src/services/baptismal_image_preprocess.js`
- Test: `backend/src/services/baptismal_image_preprocess.test.js`
- Modify: `backend/package.json`

**Interfaces:**
- Consumes: nothing.
- Produces:
  - `sniffImageType(buffer)` → `'image/jpeg' | 'image/png' | 'image/webp' | null` (magic bytes, not the client's claim).
  - `preprocessForOcr(buffer)` → `Promise<Buffer>`. Enhances a **copy**; returns the original buffer unchanged if `sharp` is unavailable or throws.

Isolated in its own module so a `sharp` deploy problem degrades to "OCR on the original bytes" rather than taking the feature down.

- [ ] **Step 1: Add the dependency**

```bash
cd backend && npm install sharp@^0.33.5
```

- [ ] **Step 2: Write the failing test**

Create `backend/src/services/baptismal_image_preprocess.test.js`:

```js
const { sniffImageType, preprocessForOcr } = require('./baptismal_image_preprocess');

describe('sniffImageType', () => {
  test('detects JPEG', () => {
    expect(sniffImageType(Buffer.from([0xff, 0xd8, 0xff, 0xe0, 0, 0]))).toBe('image/jpeg');
  });

  test('detects PNG', () => {
    expect(sniffImageType(Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]))).toBe('image/png');
  });

  test('detects WebP', () => {
    const buf = Buffer.concat([
      Buffer.from('RIFF'), Buffer.from([0, 0, 0, 0]), Buffer.from('WEBP'),
    ]);
    expect(sniffImageType(buf)).toBe('image/webp');
  });

  test('rejects a PDF masquerading as an image', () => {
    expect(sniffImageType(Buffer.from('%PDF-1.4'))).toBe(null);
  });

  test('rejects empty and tiny buffers', () => {
    expect(sniffImageType(Buffer.alloc(0))).toBe(null);
    expect(sniffImageType(Buffer.from([0xff]))).toBe(null);
  });
});

describe('preprocessForOcr', () => {
  test('returns a usable buffer and does not mutate the input', async () => {
    const sharp = require('sharp');
    const original = await sharp({
      create: { width: 40, height: 30, channels: 3, background: { r: 200, g: 200, b: 200 } },
    }).jpeg().toBuffer();
    const copy = Buffer.from(original);

    const out = await preprocessForOcr(original);

    expect(Buffer.isBuffer(out)).toBe(true);
    expect(out.length).toBeGreaterThan(0);
    expect(original.equals(copy)).toBe(true); // original untouched
  });

  test('falls back to the original buffer when processing fails', async () => {
    const notAnImage = Buffer.from('definitely not an image');
    const out = await preprocessForOcr(notAnImage);
    expect(out).toBe(notAnImage);
  });
});
```

- [ ] **Step 3: Run test to verify it fails**

Run: `cd backend && npx jest src/services/baptismal_image_preprocess.test.js`
Expected: FAIL — `Cannot find module './baptismal_image_preprocess'`

- [ ] **Step 4: Implement**

Create `backend/src/services/baptismal_image_preprocess.js`:

```js
/**
 * Image validation and OCR pre-processing.
 *
 * Preprocessing operates on a COPY. The original upload is what gets archived
 * to Storage and must never be mutated here.
 */

const MAX_EDGE = 4096;

/** Identifies an image by magic bytes. Never trust the client's declared mime. */
function sniffImageType(buffer) {
  if (!Buffer.isBuffer(buffer) || buffer.length < 12) return null;
  if (buffer[0] === 0xff && buffer[1] === 0xd8 && buffer[2] === 0xff) return 'image/jpeg';
  if (
    buffer[0] === 0x89 && buffer[1] === 0x50 && buffer[2] === 0x4e && buffer[3] === 0x47 &&
    buffer[4] === 0x0d && buffer[5] === 0x0a && buffer[6] === 0x1a && buffer[7] === 0x0a
  ) return 'image/png';
  if (buffer.slice(0, 4).toString() === 'RIFF' && buffer.slice(8, 12).toString() === 'WEBP') {
    return 'image/webp';
  }
  return null;
}

/**
 * Enhances contrast and sharpness to help Vision read cramped ballpoint
 * handwriting. Returns the ORIGINAL buffer unchanged if sharp is unavailable
 * or fails — degraded accuracy beats a broken feature.
 */
async function preprocessForOcr(buffer) {
  let sharp;
  try {
    sharp = require('sharp');
  } catch (e) {
    return buffer;
  }
  try {
    return await sharp(buffer)
      .rotate() // honour EXIF orientation
      .resize({ width: MAX_EDGE, height: MAX_EDGE, fit: 'inside', withoutEnlargement: true })
      .grayscale()
      .normalize()
      .sharpen()
      .jpeg({ quality: 92 })
      .toBuffer();
  } catch (e) {
    return buffer;
  }
}

module.exports = { sniffImageType, preprocessForOcr, MAX_EDGE };
```

- [ ] **Step 5: Run tests**

Run: `cd backend && npx jest src/services/baptismal_image_preprocess.test.js`
Expected: PASS — 7 tests.

If `npm install sharp` fails on this platform, note it in the commit message,
skip the two `preprocessForOcr` tests with `test.skip`, and continue — the
module already degrades to returning the original buffer. Report the failure
rather than silently dropping preprocessing.

- [ ] **Step 6: Commit**

```bash
git add backend/src/services/baptismal_image_preprocess.js backend/src/services/baptismal_image_preprocess.test.js backend/package.json backend/package-lock.json
git commit -m "feat(ocr): add image validation and OCR preprocessing"
```

---

### Task 9: Scan route

**Files:**
- Create: `backend/src/routes/baptismal_ocr_firestore.js`
- Test: `backend/src/routes/baptismal_ocr_firestore.test.js`
- Modify: `backend/src/server.js`, `backend/.env.example`

**Interfaces:**
- Consumes: `recognizeWords` (Task 1), `extractBaptismalRows` (Task 7), `sniffImageType` / `preprocessForOcr` (Task 8).
- Produces: `POST /api/ocr/baptismal/scan`. Body `{ scanId: string, imageBase64: string }`. Responds `{ success: true, data: { scanId, rows, columns, rotation, gutterX, warnings } }`.
- Exports `createBaptismalOcrRouter({ recognize, extract, preprocess, verifyToken })` for injection in tests, plus a default router instance as `module.exports.router`.

**Note on body size — read carefully, this is easy to get wrong.** `server.js:58` sets a global `express.json({ limit: '10mb' })` that runs *before every route mount*. Base64 inflates a 10 MB image to ~13.4 MB, so a valid scan would be rejected by that global parser with a generic Express 413 before this route's handler ever ran — and a router-level parser mounted at line ~91 would be dead code, because the global parser has already consumed (or rejected) the body.

The route must therefore be mounted **before** `app.use(express.json({ limit: '10mb' }))`, with its own 20 MB parser. Mounting early also means it sits ahead of `app.use('/api', verifyFirebaseToken)`, so this router applies `verifyFirebaseToken` itself — injectable as `verifyToken` so tests can substitute a pass-through.

- [ ] **Step 1: Write the failing test**

Create `backend/src/routes/baptismal_ocr_firestore.test.js`:

```js
const express = require('express');
const request = require('supertest');
const { createBaptismalOcrRouter } = require('./baptismal_ocr_firestore');

const JPEG = Buffer.concat([Buffer.from([0xff, 0xd8, 0xff, 0xe0]), Buffer.alloc(16, 1)]);
const b64 = (buf) => buf.toString('base64');

function appWith(overrides = {}, role = 'admin') {
  const app = express();
  app.use('/api/ocr/baptismal', createBaptismalOcrRouter({
    // Stand in for verifyFirebaseToken so tests need no Firebase.
    verifyToken: (req, _res, next) => { req.user = { uid: 'u1', role }; next(); },
    recognize: async () => ({ words: [{ text: 'X', vertices: [], confidence: 1 }], fullText: 'X' }),
    extract: () => ({ rows: [{ index: 0, lineNo: '1', fields: {} }], rotation: 0, gutterX: 500, columns: { left: [], right: [] }, warnings: [] }),
    ...overrides,
  }));
  return app;
}

describe('POST /api/ocr/baptismal/scan', () => {
  test('returns extracted rows for a valid JPEG', async () => {
    const res = await request(appWith()).post('/api/ocr/baptismal/scan')
      .send({ scanId: 's1', imageBase64: b64(JPEG) });
    expect(res.status).toBe(200);
    expect(res.body.success).toBe(true);
    expect(res.body.data.scanId).toBe('s1');
    expect(res.body.data.rows).toHaveLength(1);
    expect(res.body.data.rotation).toBe(0);
  });

  test('rejects a parishioner', async () => {
    const res = await request(appWith({}, 'parishioner')).post('/api/ocr/baptismal/scan')
      .send({ scanId: 's1', imageBase64: b64(JPEG) });
    expect(res.status).toBe(403);
    expect(res.body.success).toBe(false);
  });

  test('allows staff', async () => {
    const res = await request(appWith({}, 'staff')).post('/api/ocr/baptismal/scan')
      .send({ scanId: 's1', imageBase64: b64(JPEG) });
    expect(res.status).toBe(200);
  });

  test('rejects a missing scanId', async () => {
    const res = await request(appWith()).post('/api/ocr/baptismal/scan')
      .send({ imageBase64: b64(JPEG) });
    expect(res.status).toBe(400);
  });

  test('rejects a non-image payload with IMAGE_INVALID', async () => {
    const res = await request(appWith()).post('/api/ocr/baptismal/scan')
      .send({ scanId: 's1', imageBase64: b64(Buffer.from('%PDF-1.4 not an image')) });
    expect(res.status).toBe(400);
    expect(res.body.code).toBe('IMAGE_INVALID');
  });

  test('rejects an oversized image with IMAGE_TOO_LARGE', async () => {
    const big = Buffer.concat([Buffer.from([0xff, 0xd8, 0xff, 0xe0]), Buffer.alloc(11 * 1024 * 1024, 1)]);
    const res = await request(appWith()).post('/api/ocr/baptismal/scan')
      .send({ scanId: 's1', imageBase64: b64(big) });
    expect(res.status).toBe(413);
    expect(res.body.code).toBe('IMAGE_TOO_LARGE');
  });

  const failure = (code) => async () => { const e = new Error(code); e.code = code; throw e; };

  test.each([
    ['VISION_AUTH', 500],
    ['VISION_QUOTA', 429],
    ['VISION_UNAVAILABLE', 502],
    ['NO_TEXT_FOUND', 422],
  ])('maps %s to HTTP %i', async (code, status) => {
    const res = await request(appWith({ recognize: failure(code) }))
      .post('/api/ocr/baptismal/scan').send({ scanId: 's1', imageBase64: b64(JPEG) });
    expect(res.status).toBe(status);
    expect(res.body.code).toBe(code);
    expect(res.body.success).toBe(false);
  });

  test('maps LAYOUT_UNRECOGNIZED from the extractor to 422', async () => {
    const res = await request(appWith({
      extract: () => { const e = new Error('nope'); e.code = 'LAYOUT_UNRECOGNIZED'; throw e; },
    })).post('/api/ocr/baptismal/scan').send({ scanId: 's1', imageBase64: b64(JPEG) });
    expect(res.status).toBe(422);
    expect(res.body.code).toBe('LAYOUT_UNRECOGNIZED');
  });

  test('never echoes cell values in an error body', async () => {
    const res = await request(appWith({ recognize: failure('VISION_QUOTA') }))
      .post('/api/ocr/baptismal/scan').send({ scanId: 's1', imageBase64: b64(JPEG) });
    expect(JSON.stringify(res.body)).not.toContain('imageBase64');
  });
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd backend && npx jest src/routes/baptismal_ocr_firestore.test.js`
Expected: FAIL — `Cannot find module './baptismal_ocr_firestore'`

- [ ] **Step 3: Implement**

Create `backend/src/routes/baptismal_ocr_firestore.js`:

```js
const express = require('express');
const { body, validationResult } = require('express-validator');

const { verifyFirebaseToken } = require('../middleware/auth');
const { recognizeWords } = require('../services/baptismal_ocr_service');
const { extractBaptismalRows } = require('../services/baptismal_register_layout');
const { sniffImageType, preprocessForOcr } = require('../services/baptismal_image_preprocess');

const MAX_IMAGE_BYTES = 10 * 1024 * 1024;
const ACCEPTED = new Set(['image/jpeg', 'image/png', 'image/webp']);

const STATUS_BY_CODE = {
  IMAGE_INVALID: 400,
  IMAGE_TOO_LARGE: 413,
  VISION_AUTH: 500,
  VISION_QUOTA: 429,
  VISION_UNAVAILABLE: 502,
  NO_TEXT_FOUND: 422,
  LAYOUT_UNRECOGNIZED: 422,
};

const MESSAGE_BY_CODE = {
  IMAGE_INVALID: 'That file is not a supported image. Use JPEG, PNG, or WebP.',
  IMAGE_TOO_LARGE: 'That image is larger than 10 MB. Please use a smaller photo.',
  VISION_AUTH: 'OCR is not configured on the server. Contact an administrator.',
  VISION_QUOTA: 'The OCR service is rate-limited right now. Try again shortly.',
  VISION_UNAVAILABLE: 'Could not reach the OCR service. Check your connection and retry.',
  NO_TEXT_FOUND: 'No readable text was found. Retake the photo with better lighting and framing.',
  LAYOUT_UNRECOGNIZED: 'This page does not look like a baptismal register. Check the photo and retry.',
};

function requireStaffOrAdmin(req, res, next) {
  const role = req.user && req.user.role;
  const isAdmin = (req.user && req.user.admin === true) || role === 'admin';
  if (isAdmin || role === 'staff') return next();
  return res.status(403).json({ success: false, message: 'Staff or admin role required' });
}

function createBaptismalOcrRouter(deps = {}) {
  const recognize = deps.recognize || recognizeWords;
  const extract = deps.extract || extractBaptismalRows;
  const preprocess = deps.preprocess || preprocessForOcr;
  const verifyToken = deps.verifyToken || verifyFirebaseToken;

  const router = express.Router();

  // Base64 inflates a 10MB image to ~13.4MB, over the app-wide 10mb limit.
  // This router is mounted BEFORE the global parser in server.js so this
  // limit is the one that applies — see the mount step.
  router.use(express.json({ limit: '20mb' }));

  router.post(
    '/scan',
    verifyToken,
    requireStaffOrAdmin,
    [body('scanId').isString().trim().notEmpty(), body('imageBase64').isString().notEmpty()],
    async (req, res) => {
      const errors = validationResult(req);
      if (!errors.isEmpty()) {
        return res.status(400).json({
          success: false,
          message: 'scanId and imageBase64 are required',
          code: 'IMAGE_INVALID',
        });
      }

      const { scanId } = req.body;
      const startedAt = Date.now();

      let buffer;
      try {
        buffer = Buffer.from(req.body.imageBase64, 'base64');
      } catch (e) {
        return fail(res, 'IMAGE_INVALID', scanId);
      }

      if (buffer.length > MAX_IMAGE_BYTES) return fail(res, 'IMAGE_TOO_LARGE', scanId);

      const mime = sniffImageType(buffer);
      if (!mime || !ACCEPTED.has(mime)) return fail(res, 'IMAGE_INVALID', scanId);

      try {
        const prepared = await preprocess(buffer);
        const { words } = await recognize(prepared);
        const result = extract(words);

        // Log counts only — never cell values (records of minors).
        console.log(
          `[baptismal-ocr] scan=${scanId} words=${words.length} rows=${result.rows.length} ` +
          `rotation=${result.rotation} warnings=${result.warnings.length} ms=${Date.now() - startedAt}`,
        );

        return res.json({
          success: true,
          data: {
            scanId,
            rows: result.rows,
            columns: result.columns,
            rotation: result.rotation,
            gutterX: result.gutterX,
            warnings: result.warnings,
          },
        });
      } catch (e) {
        return fail(res, STATUS_BY_CODE[e.code] ? e.code : 'VISION_UNAVAILABLE', scanId);
      }
    },
  );

  return router;
}

function fail(res, code, scanId) {
  console.warn(`[baptismal-ocr] scan=${scanId} failed code=${code}`);
  return res.status(STATUS_BY_CODE[code] || 500).json({
    success: false,
    code,
    message: MESSAGE_BY_CODE[code] || 'OCR failed.',
  });
}

module.exports = { createBaptismalOcrRouter, router: createBaptismalOcrRouter() };
```

- [ ] **Step 4: Run tests**

Run: `cd backend && npx jest src/routes/baptismal_ocr_firestore.test.js`
Expected: PASS — 13 tests. (The two body-size tests in Step 5b are added after
the mount and will fail until Step 5 is done — run them with the rest at Step 7.)

- [ ] **Step 5: Mount the route (ordering matters)**

In `backend/src/server.js`, add beside the other route requires (after line 21):

```js
const baptismalOcrRoutes = require('./routes/baptismal_ocr_firestore');
```

Then mount it **immediately before** the global body parser at line 58 —
i.e. between `app.use(limiter);` and `app.use(express.json({ limit: '10mb' }));`:

```js
// Baptismal register OCR: mounted ahead of the global 10mb JSON parser
// because a base64 register photo runs to ~13.4MB. This router brings its
// own 20mb parser and its own verifyFirebaseToken.
app.use('/api/ocr/baptismal', baptismalOcrRoutes.router);

// Body parsing middleware
app.use(express.json({ limit: '10mb' }));
```

Do **not** mount it down with the other `/api/*` routes — the global parser
would reject a valid scan with a generic 413 before this handler ran, and the
router's own parser would never execute.

- [ ] **Step 5b: Prove the ordering with a test**

Append to `backend/src/routes/baptismal_ocr_firestore.test.js`:

```js
describe('body size ordering', () => {
  // Regression: mounted after server.js's global express.json({limit:'10mb'}),
  // a valid ~13.4MB base64 scan dies with a generic Express 413 and never
  // reaches our handler. The router must own a 20mb parser and be mounted
  // ahead of the global one.
  test('accepts a base64 body over 10MB', async () => {
    // 8MB of image bytes -> ~10.9MB of base64, past the global 10mb limit.
    const image = Buffer.concat([
      Buffer.from([0xff, 0xd8, 0xff, 0xe0]),
      Buffer.alloc(8 * 1024 * 1024, 1),
    ]);
    const res = await request(appWith()).post('/api/ocr/baptismal/scan')
      .send({ scanId: 's1', imageBase64: b64(image) });
    expect(res.status).toBe(200);
    expect(res.body.success).toBe(true);
  });

  test('server.js mounts the router before the global JSON parser', () => {
    const fs = require('fs');
    const path = require('path');
    const src = fs.readFileSync(path.join(__dirname, '..', 'server.js'), 'utf8');
    const mountAt = src.indexOf("app.use('/api/ocr/baptismal'");
    const globalJsonAt = src.indexOf("express.json({ limit: '10mb' })");
    expect(mountAt).toBeGreaterThan(-1);
    expect(globalJsonAt).toBeGreaterThan(-1);
    expect(mountAt).toBeLessThan(globalJsonAt);
  });
});
```

- [ ] **Step 6: Document the env vars**

Append to `backend/.env.example` (create it if absent):

```
# Google Cloud Vision — handwriting OCR for baptismal registers.
# Service-account JSON, single line. Falls back to FIREBASE_SERVICE_ACCOUNT_JSON
# when unset (same GCP project; the Vision API must be enabled on it).
GOOGLE_CLOUD_VISION_CREDENTIALS_JSON=
```

- [ ] **Step 7: Run the whole backend suite**

Run: `cd backend && npm test`
Expected: PASS, including the pre-existing `ocrspace_service` and `ocr_firestore` tests — they must be untouched.

- [ ] **Step 8: Commit**

```bash
git add backend/src/routes/baptismal_ocr_firestore.js backend/src/routes/baptismal_ocr_firestore.test.js backend/src/server.js backend/.env.example
git commit -m "feat(ocr): add /api/ocr/baptismal/scan route with typed error codes"
```

---

### Task 10: Flutter models

**Files:**
- Create: `lib/models/baptismal_register_row.dart`
- Test: `test/baptismal_register_row_test.dart`

**Interfaces:**
- Consumes: the route's response envelope (Task 9).
- Produces:
  - `class OcrField { String value; final double confidence; final bool inherited; bool get needsReview; }`
  - `class BaptismalRegisterRow { String lineNo; Map<String, OcrField> fields; bool selected; OcrField field(String key); }`
  - `class BaptismalOcrScan { final String scanId; final List<BaptismalRegisterRow> rows; final int rotation; final List<String> warnings; static BaptismalOcrScan fromJson(Map<String, dynamic>); }`
  - `const baptismalFieldKeys` — ordered list of the nine field keys.
  - `const baptismalFieldLabels` — key → human label.

- [ ] **Step 1: Write the failing test**

Create `test/baptismal_register_row_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:parishrecord/models/baptismal_register_row.dart';

void main() {
  group('OcrField', () {
    test('flags low confidence for review', () {
      expect(OcrField(value: 'X', confidence: 0.42).needsReview, isTrue);
      expect(OcrField(value: 'X', confidence: 0.91).needsReview, isFalse);
    });

    test('flags inherited values for review even at high confidence', () {
      expect(
        OcrField(value: 'FR. ARCAPA', confidence: 0.99, inherited: true).needsReview,
        isTrue,
      );
    });

    test('does not flag an empty optional field', () {
      expect(OcrField(value: '', confidence: 0).needsReview, isFalse);
    });
  });

  group('BaptismalOcrScan.fromJson', () {
    final json = {
      'scanId': 'abc',
      'rotation': 90,
      'warnings': ['LAYOUT_UNCERTAIN'],
      'rows': [
        {
          'index': 0,
          'lineNo': '1',
          'fields': {
            'nameOfChild': {'value': 'JEZL ANTOINETTE', 'confidence': 0.71, 'inherited': false},
            'dateOfBaptism': {'value': '12 MAY 2016', 'confidence': 0.0, 'inherited': true},
          },
        },
      ],
    };

    test('parses rows, fields, rotation and warnings', () {
      final scan = BaptismalOcrScan.fromJson(json);
      expect(scan.scanId, 'abc');
      expect(scan.rotation, 90);
      expect(scan.warnings, ['LAYOUT_UNCERTAIN']);
      expect(scan.rows, hasLength(1));
      expect(scan.rows.first.lineNo, '1');
      expect(scan.rows.first.field('nameOfChild').value, 'JEZL ANTOINETTE');
      expect(scan.rows.first.field('dateOfBaptism').inherited, isTrue);
    });

    test('fills every known key even when the server omits it', () {
      final scan = BaptismalOcrScan.fromJson(json);
      for (final key in baptismalFieldKeys) {
        expect(scan.rows.first.fields.containsKey(key), isTrue, reason: 'missing $key');
      }
      expect(scan.rows.first.field('sponsors').value, '');
    });

    test('rows default to selected', () {
      expect(BaptismalOcrScan.fromJson(json).rows.first.selected, isTrue);
    });

    test('every field key has a label', () {
      for (final key in baptismalFieldKeys) {
        expect(baptismalFieldLabels[key], isNotNull, reason: 'no label for $key');
      }
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/baptismal_register_row_test.dart`
Expected: FAIL — target of URI doesn't exist.

- [ ] **Step 3: Implement**

Create `lib/models/baptismal_register_row.dart`:

```dart
/// Ordered field keys for a baptismal register row, matching the column
/// order of the physical book (left page, then right page).
const List<String> baptismalFieldKeys = [
  'nameOfChild',
  'placeAndBirthDate',
  'legitimacy',
  'parents',
  'residentsOf',
  'dateOfBaptism',
  'minister',
  'sponsors',
  'observations',
];

const Map<String, String> baptismalFieldLabels = {
  'nameOfChild': 'Name of Child',
  'placeAndBirthDate': 'Place & Date of Birth',
  'legitimacy': 'L or ILL',
  'parents': 'Parents (Mother\'s Maiden Name)',
  'residentsOf': 'Residents Of',
  'dateOfBaptism': 'Date of Baptism',
  'minister': 'Minister',
  'sponsors': 'Sponsors',
  'observations': 'Observations',
};

/// Fields the register always fills in and that the app requires to save.
const Set<String> baptismalRequiredFields = {'nameOfChild', 'dateOfBaptism'};

/// Below this, OCR output is shown as needing verification.
const double kOcrReviewThreshold = 0.60;

/// One extracted cell: the text, how sure OCR was, and whether it was carried
/// down from the row above rather than actually read.
class OcrField {
  OcrField({required this.value, required this.confidence, this.inherited = false});

  String value;
  final double confidence;
  final bool inherited;

  /// True when a human should look at this before it is saved.
  bool get needsReview {
    if (value.trim().isEmpty) return false;
    return inherited || confidence < kOcrReviewThreshold;
  }

  factory OcrField.fromJson(Map<String, dynamic>? json) {
    if (json == null) return OcrField(value: '', confidence: 0);
    return OcrField(
      value: json['value']?.toString() ?? '',
      confidence: (json['confidence'] as num?)?.toDouble() ?? 0,
      inherited: json['inherited'] == true,
    );
  }

  OcrField copyWith({String? value}) =>
      OcrField(value: value ?? this.value, confidence: confidence, inherited: inherited);
}

/// One row of the register — one prospective baptism record.
class BaptismalRegisterRow {
  BaptismalRegisterRow({
    required this.lineNo,
    required this.fields,
    this.selected = true,
  });

  String lineNo;
  final Map<String, OcrField> fields;
  bool selected;

  OcrField field(String key) => fields[key] ?? OcrField(value: '', confidence: 0);

  void setValue(String key, String value) {
    fields[key] = field(key).copyWith(value: value);
  }

  factory BaptismalRegisterRow.fromJson(Map<String, dynamic> json) {
    final rawFields = json['fields'];
    final map = <String, OcrField>{};
    for (final key in baptismalFieldKeys) {
      final raw = rawFields is Map ? rawFields[key] : null;
      map[key] = OcrField.fromJson(
        raw is Map ? Map<String, dynamic>.from(raw) : null,
      );
    }
    return BaptismalRegisterRow(
      lineNo: json['lineNo']?.toString() ?? '',
      fields: map,
    );
  }
}

/// A whole scanned spread.
class BaptismalOcrScan {
  BaptismalOcrScan({
    required this.scanId,
    required this.rows,
    required this.rotation,
    required this.warnings,
  });

  final String scanId;
  final List<BaptismalRegisterRow> rows;
  final int rotation;
  final List<String> warnings;

  factory BaptismalOcrScan.fromJson(Map<String, dynamic> json) {
    final rawRows = json['rows'];
    return BaptismalOcrScan(
      scanId: json['scanId']?.toString() ?? '',
      rotation: (json['rotation'] as num?)?.toInt() ?? 0,
      warnings: (json['warnings'] as List?)?.map((w) => w.toString()).toList() ?? const [],
      rows: rawRows is List
          ? rawRows
              .whereType<Map>()
              .map((r) => BaptismalRegisterRow.fromJson(Map<String, dynamic>.from(r)))
              .toList()
          : <BaptismalRegisterRow>[],
    );
  }
}
```

- [ ] **Step 4: Run tests**

Run: `flutter test test/baptismal_register_row_test.dart && flutter analyze lib/models/baptismal_register_row.dart`
Expected: PASS, analyze clean.

- [ ] **Step 5: Commit**

```bash
git add lib/models/baptismal_register_row.dart test/baptismal_register_row_test.dart
git commit -m "feat(ocr): add baptismal register row models"
```

---

### Task 11: Flutter OCR client

**Files:**
- Create: `lib/services/baptismal_ocr_service.dart`
- Test: `test/baptismal_ocr_service_test.dart`

**Interfaces:**
- Consumes: `BaptismalOcrScan` (Task 10), `BackendConfig.apiBaseUrl` (`lib/config/backend.dart`).
- Produces:
  - `class BaptismalOcrFailure implements Exception { final String code; final String message; final bool retryable; }`
  - `class BaptismalOcrService { Future<BaptismalOcrScan> scan({required String scanId, required Uint8List bytes, String? idToken}); }` — constructor takes an optional `http.Client` for tests. Throws `BaptismalOcrFailure`.

- [ ] **Step 1: Write the failing test**

Create `test/baptismal_ocr_service_test.dart`:

```dart
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:parishrecord/services/baptismal_ocr_service.dart';

void main() {
  final bytes = Uint8List.fromList([0xff, 0xd8, 0xff, 0xe0, 1, 2, 3]);

  BaptismalOcrService serviceReturning(int status, Object body) {
    return BaptismalOcrService(
      client: MockClient((req) async => http.Response(jsonEncode(body), status)),
    );
  }

  test('parses a successful scan', () async {
    final svc = serviceReturning(200, {
      'success': true,
      'data': {
        'scanId': 's1',
        'rotation': 0,
        'warnings': <String>[],
        'rows': [
          {'lineNo': '1', 'fields': {'nameOfChild': {'value': 'JEZL', 'confidence': 0.9}}}
        ],
      },
    });
    final scan = await svc.scan(scanId: 's1', bytes: bytes, idToken: 't');
    expect(scan.rows, hasLength(1));
    expect(scan.rows.first.field('nameOfChild').value, 'JEZL');
  });

  test('sends the bearer token and base64 body', () async {
    late http.Request captured;
    final svc = BaptismalOcrService(client: MockClient((req) async {
      captured = req;
      return http.Response(
        jsonEncode({'success': true, 'data': {'scanId': 's1', 'rows': [], 'rotation': 0, 'warnings': []}}),
        200,
      );
    }));
    await svc.scan(scanId: 's1', bytes: bytes, idToken: 'TOKEN');
    expect(captured.headers['Authorization'], 'Bearer TOKEN');
    final body = jsonDecode(captured.body) as Map<String, dynamic>;
    expect(body['scanId'], 's1');
    expect(body['imageBase64'], base64Encode(bytes));
  });

  test('surfaces a typed failure with the server code', () async {
    final svc = serviceReturning(429, {
      'success': false, 'code': 'VISION_QUOTA', 'message': 'rate limited',
    });
    await expectLater(
      svc.scan(scanId: 's1', bytes: bytes, idToken: 't'),
      throwsA(isA<BaptismalOcrFailure>()
          .having((f) => f.code, 'code', 'VISION_QUOTA')
          .having((f) => f.retryable, 'retryable', true)),
    );
  });

  test('marks VISION_AUTH as not retryable', () async {
    final svc = serviceReturning(500, {
      'success': false, 'code': 'VISION_AUTH', 'message': 'not configured',
    });
    await expectLater(
      svc.scan(scanId: 's1', bytes: bytes, idToken: 't'),
      throwsA(isA<BaptismalOcrFailure>().having((f) => f.retryable, 'retryable', false)),
    );
  });

  test('maps a network error to a retryable NETWORK failure', () async {
    final svc = BaptismalOcrService(
      client: MockClient((_) async => throw const http.ClientException('offline')),
    );
    await expectLater(
      svc.scan(scanId: 's1', bytes: bytes, idToken: 't'),
      throwsA(isA<BaptismalOcrFailure>()
          .having((f) => f.code, 'code', 'NETWORK')
          .having((f) => f.retryable, 'retryable', true)),
    );
  });

  test('maps an unparseable body to a retryable failure', () async {
    final svc = BaptismalOcrService(
      client: MockClient((_) async => http.Response('<html>502</html>', 502)),
    );
    await expectLater(
      svc.scan(scanId: 's1', bytes: bytes, idToken: 't'),
      throwsA(isA<BaptismalOcrFailure>()),
    );
  });

  test('fails fast without an auth token', () async {
    final svc = serviceReturning(200, {'success': true, 'data': {}});
    await expectLater(
      svc.scan(scanId: 's1', bytes: bytes, idToken: null),
      throwsA(isA<BaptismalOcrFailure>().having((f) => f.code, 'code', 'UNAUTHENTICATED')),
    );
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/baptismal_ocr_service_test.dart`
Expected: FAIL — target of URI doesn't exist.

- [ ] **Step 3: Implement**

Create `lib/services/baptismal_ocr_service.dart`:

```dart
import 'dart:convert';
import 'dart:typed_data';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;

import '../config/backend.dart';
import '../models/baptismal_register_row.dart';

/// A scan failure the UI can act on: show [message], offer retry when
/// [retryable].
class BaptismalOcrFailure implements Exception {
  const BaptismalOcrFailure({
    required this.code,
    required this.message,
    required this.retryable,
  });

  final String code;
  final String message;
  final bool retryable;

  @override
  String toString() => 'BaptismalOcrFailure($code): $message';
}

/// Sends register photos to the backend Vision proxy.
///
/// Vision credentials live on the server; this client only ever sees the
/// extracted rows.
class BaptismalOcrService {
  BaptismalOcrService({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;
  static const Duration _timeout = Duration(seconds: 60);

  // Codes where retrying the same image cannot help.
  static const Set<String> _permanent = {
    'VISION_AUTH',
    'IMAGE_INVALID',
    'IMAGE_TOO_LARGE',
    'LAYOUT_UNRECOGNIZED',
    'UNAUTHENTICATED',
  };

  static const Map<String, String> _fallbackMessages = {
    'NETWORK': 'Could not reach the server. Check your connection and retry.',
    'UNAUTHENTICATED': 'You are signed out. Sign in again to scan.',
    'BAD_RESPONSE': 'The server returned an unexpected response. Please retry.',
  };

  Future<BaptismalOcrScan> scan({
    required String scanId,
    required Uint8List bytes,
    String? idToken,
  }) async {
    final token = idToken ?? await FirebaseAuth.instance.currentUser?.getIdToken();
    if (token == null || token.isEmpty) {
      throw _failure('UNAUTHENTICATED', null);
    }

    http.Response res;
    try {
      res = await _client
          .post(
            Uri.parse('${BackendConfig.apiBaseUrl}/ocr/baptismal/scan'),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $token',
            },
            body: jsonEncode({
              'scanId': scanId,
              'imageBase64': base64Encode(bytes),
            }),
          )
          .timeout(_timeout);
    } catch (_) {
      throw _failure('NETWORK', null);
    }

    Map<String, dynamic>? decoded;
    try {
      final raw = jsonDecode(res.body);
      if (raw is Map<String, dynamic>) decoded = raw;
    } catch (_) {
      decoded = null;
    }

    if (decoded == null) throw _failure('BAD_RESPONSE', null);

    if (res.statusCode != 200 || decoded['success'] != true) {
      throw _failure(
        decoded['code']?.toString() ?? 'BAD_RESPONSE',
        decoded['message']?.toString(),
      );
    }

    final data = decoded['data'];
    if (data is! Map) throw _failure('BAD_RESPONSE', null);
    return BaptismalOcrScan.fromJson(Map<String, dynamic>.from(data));
  }

  BaptismalOcrFailure _failure(String code, String? serverMessage) {
    return BaptismalOcrFailure(
      code: code,
      message: serverMessage ?? _fallbackMessages[code] ?? 'OCR failed. Please retry.',
      retryable: !_permanent.contains(code),
    );
  }
}
```

- [ ] **Step 4: Run tests**

Run: `flutter test test/baptismal_ocr_service_test.dart && flutter analyze lib/services/baptismal_ocr_service.dart`
Expected: PASS — 7 tests, analyze clean.

- [ ] **Step 5: Commit**

```bash
git add lib/services/baptismal_ocr_service.dart test/baptismal_ocr_service_test.dart
git commit -m "feat(ocr): add baptismal OCR backend client with typed failures"
```

---

### Task 12: Additive schema — legitimacy and observations

**Files:**
- Modify: `lib/utils/manual_register_notes.dart`
- Test: `test/manual_register_notes_baptismal_test.dart`

**Interfaces:**
- Consumes: `RegisterOcrEntry` (`lib/models/register_ocr_entry.dart`).
- Produces: `ManualRegisterNotes.toBaptismalOcrNotesMap({volNo, seriesNo, lineNo, fields, scanId, imagePath})` → `Map<String, dynamic>`. `fields` is `Map<String, String>` keyed by `baptismalFieldKeys`.

The existing `toNotesMap` is left alone so the manual register page keeps its
exact behavior. The new function adds `legitimacy`, `observations`,
`ocrScanId`, `originalImagePath`, and `source: 'baptismal_ocr_vision'`.

- [ ] **Step 1: Write the failing test**

Create `test/manual_register_notes_baptismal_test.dart`:

```dart
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:parishrecord/utils/manual_register_notes.dart';

void main() {
  Map<String, dynamic> build() => ManualRegisterNotes.toBaptismalOcrNotesMap(
        volNo: '4',
        seriesNo: '2016',
        lineNo: '1',
        scanId: 'scan-1',
        imagePath: 'baptism_scans/2026/scan-1.jpg',
        fields: const {
          'nameOfChild': 'JEZL ANTOINETTE HITUTUAAN',
          'placeAndBirthDate': '19 FEBRUARY 2001',
          'legitimacy': 'L',
          'parents': 'LITA / HITUTUAAN',
          'residentsOf': 'P-2 CANITOAN',
          'dateOfBaptism': '12 MAY 2016',
          'minister': 'FR. PABLITO ARCAPA',
          'sponsors': 'JOMARIE / POL',
          'observations': 'Married to X',
        },
      );

  test('carries every register column including the two new ones', () {
    final map = build();
    expect(map['nameOfChild'], 'JEZL ANTOINETTE HITUTUAAN');
    expect(map['legitimacy'], 'L');
    expect(map['observations'], 'Married to X');
    expect(map['minister'], 'FR. PABLITO ARCAPA');
    expect(map['volNo'], '4');
    expect(map['lineNo'], '1');
  });

  test('records provenance', () {
    final map = build();
    expect(map['source'], 'baptismal_ocr_vision');
    expect(map['sacramentType'], 'baptism');
    expect(map['ocrScanId'], 'scan-1');
    expect(map['originalImagePath'], 'baptism_scans/2026/scan-1.jpg');
  });

  test('stays readable by the existing decoder as a flat baptism layout', () {
    final decoded = ManualRegisterNotes.tryDecode(jsonEncode(build()))!;
    expect(ManualRegisterNotes.isManualBaptismMap(decoded), isTrue);
    expect(ManualRegisterNotes.usesFlatRegisterLayout(decoded), isTrue);
    expect(ManualRegisterNotes.isManualMarriageMap(decoded), isFalse);
  });

  test('converts to a RegisterOcrEntry through the existing path', () {
    final entry = ManualRegisterNotes.entryFromMap(build());
    expect(entry.name, 'JEZL ANTOINETTE HITUTUAAN');
    expect(entry.baptismDateText, '12 MAY 2016');
    expect(entry.minister, 'FR. PABLITO ARCAPA');
    expect(entry.parents, 'LITA / HITUTUAAN');
  });

  test('omitted optional fields become empty strings, not null', () {
    final map = ManualRegisterNotes.toBaptismalOcrNotesMap(
      volNo: '', seriesNo: '', lineNo: '2', scanId: 's', imagePath: null,
      fields: const {'nameOfChild': 'A', 'dateOfBaptism': '1 JAN 2020'},
    );
    expect(map['observations'], '');
    expect(map['legitimacy'], '');
    expect(map['originalImagePath'], isNull);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/manual_register_notes_baptismal_test.dart`
Expected: FAIL — `toBaptismalOcrNotesMap` isn't defined.

- [ ] **Step 3: Implement**

Add to `lib/utils/manual_register_notes.dart`, inside the `ManualRegisterNotes`
class (after `toNotesMap`):

```dart
  /// Notes payload for a row verified through the Vision baptismal OCR flow.
  ///
  /// Additive relative to [toNotesMap]: adds `legitimacy`, `observations` and
  /// scan provenance. Keeps `source` recognisable to [isManualBaptismMap] via
  /// the `nameOfChild` key, so existing readers and the flat register editor
  /// keep working.
  static Map<String, dynamic> toBaptismalOcrNotesMap({
    required String volNo,
    required String seriesNo,
    required String lineNo,
    required Map<String, String> fields,
    required String scanId,
    String? imagePath,
    String status = 'official',
  }) {
    String at(String key) => (fields[key] ?? '').trim();
    return {
      'source': 'baptismal_ocr_vision',
      'status': status,
      'sacramentType': 'baptism',
      'volNo': volNo,
      'seriesNo': seriesNo,
      'lineNo': lineNo,
      'nameOfChild': at('nameOfChild'),
      'placeAndBirthDate': at('placeAndBirthDate'),
      'legitimacy': at('legitimacy'),
      'parents': at('parents'),
      'residentsOf': at('residentsOf'),
      'dateOfBaptism': at('dateOfBaptism'),
      'minister': at('minister'),
      'sponsors': at('sponsors'),
      'observations': at('observations'),
      'ocrScanId': scanId,
      'originalImagePath': imagePath,
    };
  }
```

- [ ] **Step 4: Run tests**

Run: `flutter test test/manual_register_notes_baptismal_test.dart && flutter analyze lib/utils/manual_register_notes.dart`
Expected: PASS — 5 tests, analyze clean.

- [ ] **Step 5: Verify nothing else regressed**

Run: `flutter test`
Expected: PASS. If a pre-existing test fails, it is unrelated to this change —
record the failure and its cause before continuing rather than fixing it here.

- [ ] **Step 6: Commit**

```bash
git add lib/utils/manual_register_notes.dart test/manual_register_notes_baptismal_test.dart
git commit -m "feat(ocr): add legitimacy and observations to the baptism notes schema"
```

---

### Task 13: Row validation

**Files:**
- Create: `lib/services/baptismal_row_validation.dart`
- Test: `test/baptismal_row_validation_test.dart`

**Interfaces:**
- Consumes: `BaptismalRegisterRow` (Task 10), `RegisterOcrParser.parseDate` (`lib/services/register_ocr_parser.dart`), `ParishRecord` (`lib/models/record.dart`).
- Produces:
  - `class RowIssue { final int rowIndex; final String field; final String message; final bool blocking; }`
  - `List<RowIssue> validateBaptismalRows(List<BaptismalRegisterRow> rows, {List<ParishRecord> existing = const [], DateTime? now})`
  - `DateTime? baptismDateOf(BaptismalRegisterRow row)`

Rules: `nameOfChild` required; `dateOfBaptism` required and parseable; parsed
date within 1900..today; a birth date parseable out of `placeAndBirthDate` must
not fall after the baptism date; a duplicate (same trimmed lowercase name +
same baptism day) against `existing` or another selected row is **non-blocking**
so the user can override. Unselected rows are skipped entirely.

- [ ] **Step 1: Write the failing test**

Create `test/baptismal_row_validation_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:parishrecord/models/baptismal_register_row.dart';
import 'package:parishrecord/models/record.dart';
import 'package:parishrecord/services/baptismal_row_validation.dart';

BaptismalRegisterRow row({
  String name = 'JEZL ANTOINETTE',
  String date = '12 MAY 2016',
  String birth = '19 FEBRUARY 2001',
  bool selected = true,
  String lineNo = '1',
}) {
  final r = BaptismalRegisterRow(
    lineNo: lineNo,
    fields: {for (final k in baptismalFieldKeys) k: OcrField(value: '', confidence: 0.9)},
    selected: selected,
  );
  r.setValue('nameOfChild', name);
  r.setValue('dateOfBaptism', date);
  r.setValue('placeAndBirthDate', birth);
  return r;
}

void main() {
  final now = DateTime(2026, 8, 22);

  test('accepts a complete row', () {
    expect(validateBaptismalRows([row()], now: now), isEmpty);
  });

  test('blocks a missing name', () {
    final issues = validateBaptismalRows([row(name: '  ')], now: now);
    expect(issues.single.field, 'nameOfChild');
    expect(issues.single.blocking, isTrue);
  });

  test('blocks a missing baptism date', () {
    final issues = validateBaptismalRows([row(date: '')], now: now);
    expect(issues.single.field, 'dateOfBaptism');
    expect(issues.single.blocking, isTrue);
  });

  test('blocks an unparseable baptism date', () {
    final issues = validateBaptismalRows([row(date: 'sometime in may')], now: now);
    expect(issues.single.field, 'dateOfBaptism');
    expect(issues.single.blocking, isTrue);
  });

  test('blocks a future baptism date', () {
    final issues = validateBaptismalRows([row(date: '1 JANUARY 2030')], now: now);
    expect(issues.single.blocking, isTrue);
    expect(issues.single.message, contains('future'));
  });

  test('blocks a baptism date before 1900', () {
    expect(validateBaptismalRows([row(date: '5 MAY 1899')], now: now).single.blocking, isTrue);
  });

  test('blocks a birth date after the baptism date', () {
    final issues = validateBaptismalRows(
      [row(date: '12 MAY 2016', birth: '19 FEBRUARY 2020')], now: now,
    );
    expect(issues.single.field, 'placeAndBirthDate');
    expect(issues.single.blocking, isTrue);
  });

  test('ignores an unparseable birth date rather than blocking', () {
    expect(
      validateBaptismalRows([row(birth: 'CAGAYAN DE ORO CITY')], now: now),
      isEmpty,
    );
  });

  test('skips unselected rows entirely', () {
    expect(validateBaptismalRows([row(name: '', selected: false)], now: now), isEmpty);
  });

  test('flags a duplicate of an existing record without blocking', () {
    final existing = [
      ParishRecord(
        id: '1', type: RecordType.baptism,
        name: 'jezl antoinette', date: DateTime(2016, 5, 12),
      ),
    ];
    final issues = validateBaptismalRows([row()], existing: existing, now: now);
    expect(issues.single.blocking, isFalse);
    expect(issues.single.message, contains('already'));
  });

  test('flags a duplicate between two selected rows', () {
    final issues = validateBaptismalRows([row(lineNo: '1'), row(lineNo: '2')], now: now);
    expect(issues.where((i) => !i.blocking), hasLength(1));
  });

  test('reports the row index so the UI can point at it', () {
    final issues = validateBaptismalRows([row(), row(name: '')], now: now);
    expect(issues.single.rowIndex, 1);
  });

  test('baptismDateOf parses the register format', () {
    expect(baptismDateOf(row(date: '12 MAY 2016')), DateTime(2016, 5, 12));
    expect(baptismDateOf(row(date: 'nonsense')), isNull);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/baptismal_row_validation_test.dart`
Expected: FAIL — target of URI doesn't exist.

- [ ] **Step 3: Implement**

Create `lib/services/baptismal_row_validation.dart`:

```dart
import '../models/baptismal_register_row.dart';
import '../models/record.dart';
import 'register_ocr_parser.dart';

/// One problem found in a row. [blocking] issues prevent saving; non-blocking
/// ones (duplicates) are warnings the user may knowingly override.
class RowIssue {
  const RowIssue({
    required this.rowIndex,
    required this.field,
    required this.message,
    required this.blocking,
  });

  final int rowIndex;
  final String field;
  final String message;
  final bool blocking;
}

/// Parses the baptism date out of a row, or null when it isn't readable.
DateTime? baptismDateOf(BaptismalRegisterRow row) {
  final text = row.field('dateOfBaptism').value.trim();
  if (text.isEmpty) return null;
  return RegisterOcrParser.parseDate(text);
}

/// Pulls a birth date out of the free-text "place & date of birth" cell.
/// Returns null when no date is present — that is normal, not an error.
DateTime? _birthDateOf(BaptismalRegisterRow row) {
  final text = row.field('placeAndBirthDate').value.trim();
  if (text.isEmpty) return null;
  return RegisterOcrParser.parseDate(text);
}

String _dupKey(String name, DateTime date) =>
    '${name.trim().toLowerCase()}|${date.year}-${date.month}-${date.day}';

/// Validates the selected rows before they are saved.
///
/// Nothing here touches Firestore or the UI, so it is cheap to test.
List<RowIssue> validateBaptismalRows(
  List<BaptismalRegisterRow> rows, {
  List<ParishRecord> existing = const [],
  DateTime? now,
}) {
  final today = now ?? DateTime.now();
  final issues = <RowIssue>[];

  final seen = <String>{
    for (final r in existing)
      if (r.type == RecordType.baptism) _dupKey(r.name, r.date),
  };

  for (var i = 0; i < rows.length; i++) {
    final row = rows[i];
    if (!row.selected) continue;

    final name = row.field('nameOfChild').value.trim();
    if (name.isEmpty) {
      issues.add(RowIssue(
        rowIndex: i,
        field: 'nameOfChild',
        message: 'Name of child is required.',
        blocking: true,
      ));
    }

    final dateText = row.field('dateOfBaptism').value.trim();
    final date = baptismDateOf(row);
    if (dateText.isEmpty) {
      issues.add(RowIssue(
        rowIndex: i,
        field: 'dateOfBaptism',
        message: 'Date of baptism is required.',
        blocking: true,
      ));
      continue;
    }
    if (date == null) {
      issues.add(RowIssue(
        rowIndex: i,
        field: 'dateOfBaptism',
        message: 'Date of baptism is not a readable date (try "12 May 2016").',
        blocking: true,
      ));
      continue;
    }
    if (date.isAfter(today)) {
      issues.add(RowIssue(
        rowIndex: i,
        field: 'dateOfBaptism',
        message: 'Date of baptism is in the future.',
        blocking: true,
      ));
      continue;
    }
    if (date.year < 1900) {
      issues.add(RowIssue(
        rowIndex: i,
        field: 'dateOfBaptism',
        message: 'Date of baptism is before 1900 — check the year.',
        blocking: true,
      ));
      continue;
    }

    final birth = _birthDateOf(row);
    if (birth != null && birth.isAfter(date)) {
      issues.add(RowIssue(
        rowIndex: i,
        field: 'placeAndBirthDate',
        message: 'Date of birth is after the date of baptism.',
        blocking: true,
      ));
    }

    if (name.isNotEmpty) {
      final key = _dupKey(name, date);
      if (seen.contains(key)) {
        issues.add(RowIssue(
          rowIndex: i,
          field: 'nameOfChild',
          message: 'A baptism for this name and date already exists.',
          blocking: false,
        ));
      } else {
        seen.add(key);
      }
    }
  }

  return issues;
}
```

- [ ] **Step 4: Run tests**

Run: `flutter test test/baptismal_row_validation_test.dart && flutter analyze lib/services/baptismal_row_validation.dart`
Expected: PASS — 14 tests, analyze clean.

- [ ] **Step 5: Commit**

```bash
git add lib/services/baptismal_row_validation.dart test/baptismal_row_validation_test.dart
git commit -m "feat(ocr): add baptismal row validation with duplicate warnings"
```

---

### Task 14: Review table widget

**Files:**
- Create: `lib/widgets/baptismal_ocr_review_table.dart`
- Test: `test/baptismal_ocr_review_table_test.dart`

**Interfaces:**
- Consumes: `BaptismalRegisterRow`, `baptismalFieldKeys`, `baptismalFieldLabels`, `RowIssue` (Tasks 10, 13).
- Produces: `class BaptismalOcrReviewTable extends StatelessWidget` with
  `{ required List<BaptismalRegisterRow> rows, required List<RowIssue> issues, required void Function(int rowIndex, String field, String value) onChanged, required void Function(int rowIndex, bool selected) onSelectedChanged, int? highlightedRow, void Function(int rowIndex)? onRowTap }`.

Cell colouring: blocking issue → `colorScheme.errorContainer`; `field.needsReview` → amber; `field.inherited` → blue; otherwise transparent.

- [ ] **Step 1: Write the failing test**

Create `test/baptismal_ocr_review_table_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:parishrecord/models/baptismal_register_row.dart';
import 'package:parishrecord/services/baptismal_row_validation.dart';
import 'package:parishrecord/widgets/baptismal_ocr_review_table.dart';

BaptismalRegisterRow makeRow({String name = 'JEZL', double confidence = 0.9}) {
  final r = BaptismalRegisterRow(
    lineNo: '1',
    fields: {
      for (final k in baptismalFieldKeys) k: OcrField(value: '', confidence: confidence),
    },
  );
  r.setValue('nameOfChild', name);
  r.setValue('dateOfBaptism', '12 MAY 2016');
  return r;
}

Widget harness(Widget child) => MaterialApp(home: Scaffold(body: SingleChildScrollView(child: child)));

void main() {
  testWidgets('renders a labelled editable field per column', (tester) async {
    await tester.pumpWidget(harness(BaptismalOcrReviewTable(
      rows: [makeRow()],
      issues: const [],
      onChanged: (_, __, ___) {},
      onSelectedChanged: (_, __) {},
    )));
    expect(find.text('Name of Child'), findsOneWidget);
    expect(find.text('Date of Baptism'), findsOneWidget);
    expect(find.text('Observations'), findsOneWidget);
    expect(find.text('JEZL'), findsOneWidget);
  });

  testWidgets('reports edits through onChanged', (tester) async {
    final edits = <List<Object>>[];
    await tester.pumpWidget(harness(BaptismalOcrReviewTable(
      rows: [makeRow()],
      issues: const [],
      onChanged: (i, f, v) => edits.add([i, f, v]),
      onSelectedChanged: (_, __) {},
    )));
    await tester.enterText(find.byKey(const ValueKey('cell-0-nameOfChild')), 'CORRECTED');
    expect(edits.last, [0, 'nameOfChild', 'CORRECTED']);
  });

  testWidgets('reports deselection', (tester) async {
    final changes = <List<Object>>[];
    await tester.pumpWidget(harness(BaptismalOcrReviewTable(
      rows: [makeRow()],
      issues: const [],
      onChanged: (_, __, ___) {},
      onSelectedChanged: (i, v) => changes.add([i, v]),
    )));
    await tester.tap(find.byKey(const ValueKey('row-select-0')));
    expect(changes.last, [0, false]);
  });

  testWidgets('shows the issue message on a blocking field', (tester) async {
    await tester.pumpWidget(harness(BaptismalOcrReviewTable(
      rows: [makeRow(name: '')],
      issues: const [RowIssue(
        rowIndex: 0, field: 'nameOfChild',
        message: 'Name of child is required.', blocking: true,
      )],
      onChanged: (_, __, ___) {},
      onSelectedChanged: (_, __) {},
    )));
    expect(find.text('Name of child is required.'), findsOneWidget);
  });

  testWidgets('marks a low-confidence cell as needing verification', (tester) async {
    await tester.pumpWidget(harness(BaptismalOcrReviewTable(
      rows: [makeRow(confidence: 0.3)],
      issues: const [],
      onChanged: (_, __, ___) {},
      onSelectedChanged: (_, __) {},
    )));
    expect(find.byIcon(Icons.help_outline), findsWidgets);
  });

  testWidgets('shows the line number for each row', (tester) async {
    await tester.pumpWidget(harness(BaptismalOcrReviewTable(
      rows: [makeRow()],
      issues: const [],
      onChanged: (_, __, ___) {},
      onSelectedChanged: (_, __) {},
    )));
    expect(find.text('Line 1'), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/baptismal_ocr_review_table_test.dart`
Expected: FAIL — target of URI doesn't exist.

- [ ] **Step 3: Implement**

Create `lib/widgets/baptismal_ocr_review_table.dart`:

```dart
import 'package:flutter/material.dart';

import '../models/baptismal_register_row.dart';
import '../services/baptismal_row_validation.dart';

/// Editable review table for OCR-extracted baptismal register rows.
///
/// One card per register line so it stays usable on a phone; a wide data grid
/// would force horizontal scrolling through nine columns.
class BaptismalOcrReviewTable extends StatelessWidget {
  const BaptismalOcrReviewTable({
    super.key,
    required this.rows,
    required this.issues,
    required this.onChanged,
    required this.onSelectedChanged,
    this.highlightedRow,
    this.onRowTap,
  });

  final List<BaptismalRegisterRow> rows;
  final List<RowIssue> issues;
  final void Function(int rowIndex, String field, String value) onChanged;
  final void Function(int rowIndex, bool selected) onSelectedChanged;
  final int? highlightedRow;
  final void Function(int rowIndex)? onRowTap;

  RowIssue? _issueFor(int rowIndex, String field) {
    for (final issue in issues) {
      if (issue.rowIndex == rowIndex && issue.field == field) return issue;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < rows.length; i++) _rowCard(context, i, rows[i]),
      ],
    );
  }

  Widget _rowCard(BuildContext context, int index, BaptismalRegisterRow row) {
    final scheme = Theme.of(context).colorScheme;
    final highlighted = highlightedRow == index;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: highlighted ? scheme.primary : scheme.outlineVariant.withValues(alpha: 0.4),
          width: highlighted ? 2 : 1,
        ),
      ),
      child: InkWell(
        onTap: onRowTap == null ? null : () => onRowTap!(index),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Checkbox(
                    key: ValueKey('row-select-$index'),
                    value: row.selected,
                    onChanged: (v) => onSelectedChanged(index, v ?? false),
                  ),
                  Text(
                    'Line ${row.lineNo}',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ],
              ),
              const SizedBox(height: 4),
              for (final key in baptismalFieldKeys) _cell(context, index, row, key),
            ],
          ),
        ),
      ),
    );
  }

  Widget _cell(
    BuildContext context,
    int rowIndex,
    BaptismalRegisterRow row,
    String key,
  ) {
    final scheme = Theme.of(context).colorScheme;
    final field = row.field(key);
    final issue = _issueFor(rowIndex, key);
    final required = baptismalRequiredFields.contains(key);

    Color? fill;
    if (issue != null && issue.blocking) {
      fill = scheme.errorContainer.withValues(alpha: 0.35);
    } else if (field.inherited) {
      fill = Colors.blue.withValues(alpha: 0.10);
    } else if (field.needsReview) {
      fill = Colors.amber.withValues(alpha: 0.18);
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: TextFormField(
        key: ValueKey('cell-$rowIndex-$key'),
        initialValue: field.value,
        onChanged: (v) => onChanged(rowIndex, key, v),
        minLines: 1,
        maxLines: 3,
        decoration: InputDecoration(
          labelText: required
              ? '${baptismalFieldLabels[key]} *'
              : baptismalFieldLabels[key],
          filled: fill != null,
          fillColor: fill,
          isDense: true,
          border: const OutlineInputBorder(),
          errorText: issue != null && issue.blocking ? issue.message : null,
          helperText: issue != null && !issue.blocking ? issue.message : null,
          suffixIcon: field.inherited
              ? const Tooltip(
                  message: 'Carried down from the row above — verify it',
                  child: Icon(Icons.arrow_downward, size: 18),
                )
              : field.needsReview
                  ? const Tooltip(
                      message: 'Low OCR confidence — verify this value',
                      child: Icon(Icons.help_outline, size: 18),
                    )
                  : null,
        ),
      ),
    );
  }
}
```

- [ ] **Step 4: Run tests**

Run: `flutter test test/baptismal_ocr_review_table_test.dart && flutter analyze lib/widgets/baptismal_ocr_review_table.dart`
Expected: PASS — 6 tests, analyze clean.

- [ ] **Step 5: Commit**

```bash
git add lib/widgets/baptismal_ocr_review_table.dart test/baptismal_ocr_review_table_test.dart
git commit -m "feat(ocr): add editable baptismal OCR review table"
```

---

### Task 15: Scan page

**Files:**
- Create: `lib/screens/admin/pages/baptismal_ocr_scan_page.dart`
- Test: `test/baptismal_ocr_scan_page_test.dart`

**Interfaces:**
- Consumes: `OcrImagePick.pickRegisterPages` (`lib/services/ocr_image_pick.dart`), `BaptismalOcrService` (Task 11), `BaptismalOcrReviewTable` (Task 14), `validateBaptismalRows` (Task 13), `ManualRegisterNotes.toBaptismalOcrNotesMap` (Task 12), `RegisterRecordDraft` (`lib/models/register_ocr_entry.dart`), `recordsProvider.addRecordsBatch` (`lib/providers/records_provider.dart`).
- Produces: `class BaptismalOcrScanPage extends ConsumerStatefulWidget { const BaptismalOcrScanPage({super.key, BaptismalOcrService? ocrService, Future<Uint8List?> Function(BuildContext)? imagePicker, Future<String?> Function(String scanId, Uint8List bytes)? imageUploader}); }` — the three injectable seams keep the widget testable without a camera, a network, or Firebase.

Steps: `pick` → `preview` → `processing` → `review`.

- [ ] **Step 1: Write the failing test**

Create `test/baptismal_ocr_scan_page_test.dart`:

```dart
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'dart:convert';
import 'package:parishrecord/screens/admin/pages/baptismal_ocr_scan_page.dart';
import 'package:parishrecord/services/baptismal_ocr_service.dart';

// A 1x1 PNG is enough — the page only needs bytes Image.memory can decode.
final _png = Uint8List.fromList([
  0x89,0x50,0x4E,0x47,0x0D,0x0A,0x1A,0x0A,0x00,0x00,0x00,0x0D,0x49,0x48,0x44,0x52,
  0x00,0x00,0x00,0x01,0x00,0x00,0x00,0x01,0x08,0x06,0x00,0x00,0x00,0x1F,0x15,0xC4,
  0x89,0x00,0x00,0x00,0x0A,0x49,0x44,0x41,0x54,0x78,0x9C,0x63,0x00,0x01,0x00,0x00,
  0x05,0x00,0x01,0x0D,0x0A,0x2D,0xB4,0x00,0x00,0x00,0x00,0x49,0x45,0x4E,0x44,0xAE,
  0x42,0x60,0x82,
]);

Map<String, dynamic> _scanBody({String name = 'JEZL ANTOINETTE'}) => {
      'success': true,
      'data': {
        'scanId': 's1',
        'rotation': 0,
        'warnings': <String>[],
        'rows': [
          {
            'lineNo': '1',
            'fields': {
              'nameOfChild': {'value': name, 'confidence': 0.9},
              'dateOfBaptism': {'value': '12 MAY 2016', 'confidence': 0.9},
            },
          },
        ],
      },
    };

Widget harness({
  required BaptismalOcrService service,
  Future<Uint8List?> Function(BuildContext)? picker,
}) {
  return ProviderScope(
    child: MaterialApp(
      home: BaptismalOcrScanPage(
        ocrService: service,
        imagePicker: picker ?? (_) async => _png,
        imageUploader: (_, __) async => 'baptism_scans/2026/s1.jpg',
      ),
    ),
  );
}

BaptismalOcrService serviceReturning(int status, Object body) => BaptismalOcrService(
      client: MockClient((_) async => http.Response(jsonEncode(body), status)),
    );

void main() {
  testWidgets('starts on the upload step', (tester) async {
    await tester.pumpWidget(harness(service: serviceReturning(200, _scanBody())));
    expect(find.text('Upload or capture a register page'), findsOneWidget);
    expect(find.text('Scan / Process OCR'), findsNothing);
  });

  testWidgets('shows a preview and the scan action after picking', (tester) async {
    await tester.pumpWidget(harness(service: serviceReturning(200, _scanBody())));
    await tester.tap(find.byKey(const ValueKey('pick-image')));
    await tester.pumpAndSettle();
    expect(find.byType(Image), findsOneWidget);
    expect(find.text('Scan / Process OCR'), findsOneWidget);
  });

  testWidgets('runs OCR and lands on the review step', (tester) async {
    await tester.pumpWidget(harness(service: serviceReturning(200, _scanBody())));
    await tester.tap(find.byKey(const ValueKey('pick-image')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Scan / Process OCR'));
    await tester.pumpAndSettle();
    expect(find.text('JEZL ANTOINETTE'), findsOneWidget);
    expect(find.textContaining('Save'), findsWidgets);
  });

  testWidgets('blocks save while a required field is empty', (tester) async {
    await tester.pumpWidget(harness(service: serviceReturning(200, _scanBody(name: ''))));
    await tester.tap(find.byKey(const ValueKey('pick-image')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Scan / Process OCR'));
    await tester.pumpAndSettle();
    expect(find.text('Name of child is required.'), findsOneWidget);
    final saveButton = tester.widget<FilledButton>(find.byKey(const ValueKey('save-rows')));
    expect(saveButton.onPressed, isNull);
  });

  testWidgets('unblocks save once the field is corrected', (tester) async {
    await tester.pumpWidget(harness(service: serviceReturning(200, _scanBody(name: ''))));
    await tester.tap(find.byKey(const ValueKey('pick-image')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Scan / Process OCR'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('cell-0-nameOfChild')), 'CORRECTED');
    await tester.pumpAndSettle();
    final saveButton = tester.widget<FilledButton>(find.byKey(const ValueKey('save-rows')));
    expect(saveButton.onPressed, isNotNull);
  });

  testWidgets('shows a retryable error and keeps the image', (tester) async {
    await tester.pumpWidget(harness(
      service: serviceReturning(429, {'success': false, 'code': 'VISION_QUOTA', 'message': 'rate limited'}),
    ));
    await tester.tap(find.byKey(const ValueKey('pick-image')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Scan / Process OCR'));
    await tester.pumpAndSettle();
    expect(find.text('rate limited'), findsOneWidget);
    expect(find.text('Retry OCR'), findsOneWidget);
    expect(find.byType(Image), findsOneWidget); // image survived the failure
  });

  testWidgets('hides retry for a non-retryable configuration error', (tester) async {
    await tester.pumpWidget(harness(
      service: serviceReturning(500, {'success': false, 'code': 'VISION_AUTH', 'message': 'not configured'}),
    ));
    await tester.tap(find.byKey(const ValueKey('pick-image')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Scan / Process OCR'));
    await tester.pumpAndSettle();
    expect(find.text('not configured'), findsOneWidget);
    expect(find.text('Retry OCR'), findsNothing);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/baptismal_ocr_scan_page_test.dart`
Expected: FAIL — target of URI doesn't exist.

- [ ] **Step 3: Implement**

Create `lib/screens/admin/pages/baptismal_ocr_scan_page.dart`:

```dart
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../models/baptismal_register_row.dart';
import '../../../models/record.dart';
import '../../../models/register_ocr_entry.dart';
import '../../../providers/records_provider.dart';
import '../../../services/baptismal_ocr_service.dart';
import '../../../services/baptismal_row_validation.dart';
import '../../../services/ocr_image_pick.dart';
import '../../../utils/manual_register_notes.dart';
import '../../../widgets/baptismal_ocr_review_table.dart';

enum _Step { pick, preview, processing, review }

/// Scan → OCR → review → save, for baptismal register spreads.
///
/// The image, the picker and the uploader are injectable so widget tests can
/// run without a camera, a network or Firebase.
class BaptismalOcrScanPage extends ConsumerStatefulWidget {
  const BaptismalOcrScanPage({
    super.key,
    this.ocrService,
    this.imagePicker,
    this.imageUploader,
  });

  final BaptismalOcrService? ocrService;
  final Future<Uint8List?> Function(BuildContext context)? imagePicker;
  final Future<String?> Function(String scanId, Uint8List bytes)? imageUploader;

  @override
  ConsumerState<BaptismalOcrScanPage> createState() => _BaptismalOcrScanPageState();
}

class _BaptismalOcrScanPageState extends ConsumerState<BaptismalOcrScanPage> {
  static const _uuid = Uuid();

  late final BaptismalOcrService _service = widget.ocrService ?? BaptismalOcrService();

  _Step _step = _Step.pick;
  Uint8List? _bytes;
  String _scanId = '';
  String? _imagePath;
  List<BaptismalRegisterRow> _rows = [];
  List<String> _warnings = const [];
  BaptismalOcrFailure? _failure;
  int? _highlightedRow;
  bool _saving = false;

  final _volCtrl = TextEditingController();
  final _seriesCtrl = TextEditingController();

  @override
  void dispose() {
    _volCtrl.dispose();
    _seriesCtrl.dispose();
    super.dispose();
  }

  List<RowIssue> get _issues => validateBaptismalRows(_rows);
  bool get _canSave =>
      !_saving &&
      _rows.any((r) => r.selected) &&
      !_issues.any((i) => i.blocking);

  Future<void> _pick() async {
    Uint8List? bytes;
    if (widget.imagePicker != null) {
      bytes = await widget.imagePicker!(context);
    } else {
      if (!mounted) return;
      final files = await OcrImagePick.pickRegisterPages(
        context,
        allowMultiple: false,
        fullResolution: true,
      );
      if (files.isNotEmpty) bytes = await files.first.readAsBytes();
    }
    if (bytes == null || !mounted) return;
    setState(() {
      _bytes = bytes;
      _scanId = _uuid.v4();
      _imagePath = null;
      _failure = null;
      _rows = [];
      _step = _Step.preview;
    });
  }

  Future<void> _runOcr() async {
    final bytes = _bytes;
    if (bytes == null) return;
    setState(() {
      _step = _Step.processing;
      _failure = null;
    });

    // Archive the ORIGINAL bytes first, so a failed scan never loses the
    // upload and a retry costs no re-upload.
    if (_imagePath == null && widget.imageUploader != null) {
      try {
        _imagePath = await widget.imageUploader!(_scanId, bytes);
      } catch (_) {
        _imagePath = null;
      }
    }

    try {
      final scan = await _service.scan(scanId: _scanId, bytes: bytes);
      if (!mounted) return;
      setState(() {
        _rows = scan.rows;
        _warnings = scan.warnings;
        _step = _Step.review;
      });
    } on BaptismalOcrFailure catch (e) {
      if (!mounted) return;
      setState(() {
        _failure = e;
        _step = _Step.preview;
      });
    }
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final selected = _rows.where((r) => r.selected).toList();
    final drafts = <RegisterRecordDraft>[];

    for (final row in selected) {
      final date = baptismDateOf(row);
      if (date == null) continue;
      final fields = {
        for (final key in baptismalFieldKeys) key: row.field(key).value.trim(),
      };
      drafts.add(RegisterRecordDraft(
        type: RecordType.baptism,
        name: fields['nameOfChild'] ?? '',
        date: date,
        parish: (fields['residentsOf'] ?? '').isNotEmpty
            ? fields['residentsOf']
            : 'Parish Register',
        imagePath: _imagePath,
        notes: _encodeNotes(row, fields),
      ));
    }

    try {
      final saved = await ref.read(recordsProvider.notifier).addRecordsBatch(drafts);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Saved $saved baptismal record(s).')),
      );
      Navigator.of(context).maybePop();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Save failed: $e')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  String _encodeNotes(BaptismalRegisterRow row, Map<String, String> fields) {
    final map = ManualRegisterNotes.toBaptismalOcrNotesMap(
      volNo: _volCtrl.text.trim(),
      seriesNo: _seriesCtrl.text.trim(),
      lineNo: row.lineNo,
      fields: fields,
      scanId: _scanId,
      imagePath: _imagePath,
    );
    return jsonEncode(map);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Add Baptismal Records (OCR)')),
      body: switch (_step) {
        _Step.pick => _pickStep(),
        _Step.preview => _previewStep(),
        _Step.processing => _processingStep(),
        _Step.review => _reviewStep(),
      },
    );
  }

  Widget _pickStep() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.document_scanner_outlined, size: 64),
          const SizedBox(height: 12),
          const Text('Upload or capture a register page'),
          const SizedBox(height: 16),
          FilledButton.icon(
            key: const ValueKey('pick-image'),
            onPressed: _pick,
            icon: const Icon(Icons.add_photo_alternate_outlined),
            label: const Text('Choose image'),
          ),
        ],
      ),
    );
  }

  Widget _previewStep() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_failure != null) _errorBanner(_failure!),
          if (_bytes != null)
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 360),
              child: Image.memory(_bytes!, fit: BoxFit.contain),
            ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _runOcr,
            icon: const Icon(Icons.play_arrow),
            label: Text(_failure != null && _failure!.retryable
                ? 'Retry OCR'
                : 'Scan / Process OCR'),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: _pick,
            icon: const Icon(Icons.refresh),
            label: const Text('Choose a different image'),
          ),
        ],
      ),
    );
  }

  Widget _errorBanner(BaptismalOcrFailure failure) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.errorContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(Icons.error_outline, color: scheme.onErrorContainer),
          const SizedBox(width: 12),
          Expanded(
            child: Text(failure.message,
                style: TextStyle(color: scheme.onErrorContainer)),
          ),
        ],
      ),
    );
  }

  Widget _processingStep() {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircularProgressIndicator(),
          SizedBox(height: 16),
          Text('Reading the register with Google Cloud Vision…'),
          SizedBox(height: 4),
          Text('This can take a few seconds for a full page.'),
        ],
      ),
    );
  }

  Widget _reviewStep() {
    final issues = _issues;
    final blocking = issues.where((i) => i.blocking).length;
    final selected = _rows.where((r) => r.selected).length;

    return Column(
      children: [
        if (_warnings.isNotEmpty)
          Padding(
            padding: const EdgeInsets.all(12),
            child: Text(
              'OCR warnings: ${_warnings.join(', ')} — check the values carefully.',
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _volCtrl,
                  decoration: const InputDecoration(labelText: 'Vol. No.'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: _seriesCtrl,
                  decoration: const InputDecoration(labelText: 'Series'),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: SingleChildScrollView(
            child: BaptismalOcrReviewTable(
              rows: _rows,
              issues: issues,
              highlightedRow: _highlightedRow,
              onRowTap: (i) => setState(() => _highlightedRow = i),
              onChanged: (i, field, value) {
                setState(() => _rows[i].setValue(field, value));
              },
              onSelectedChanged: (i, v) => setState(() => _rows[i].selected = v),
            ),
          ),
        ),
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              children: [
                if (blocking > 0)
                  Text('$blocking field(s) need attention before saving.',
                      style: TextStyle(color: Theme.of(context).colorScheme.error)),
                const SizedBox(height: 8),
                FilledButton.icon(
                  key: const ValueKey('save-rows'),
                  onPressed: _canSave ? _save : null,
                  icon: const Icon(Icons.save_outlined),
                  label: Text('Save $selected record(s)'),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
```

- [ ] **Step 4: Run tests**

Run: `flutter test test/baptismal_ocr_scan_page_test.dart && flutter analyze lib/screens/admin/pages/baptismal_ocr_scan_page.dart`
Expected: PASS — 7 tests, analyze clean.

- [ ] **Step 5: Commit**

```bash
git add lib/screens/admin/pages/baptismal_ocr_scan_page.dart test/baptismal_ocr_scan_page_test.dart
git commit -m "feat(ocr): add baptismal OCR scan page with review and validation"
```

---

### Task 16: Route wiring

**Files:**
- Modify: `lib/app/router.dart`, `lib/screens/admin/pages/records_page.dart`
- Test: `test/baptismal_ocr_route_test.dart`

**Interfaces:**
- Consumes: `BaptismalOcrScanPage` (Task 15).
- Produces: route `/admin/records/ocr-baptism`.

The old `/admin/ocr/upload` route stays registered — staff pages still link to it.

- [ ] **Step 1: Write the failing test**

Create `test/baptismal_ocr_route_test.dart`:

```dart
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('admin records page points Add Record (OCR) at the new route', () async {
    final source = await _read('lib/screens/admin/pages/records_page.dart');
    expect(source, contains("/admin/records/ocr-baptism"));
    expect(source, contains('Add Record (OCR)'));
  });

  test('router registers the new baptismal OCR route', () async {
    final source = await _read('lib/app/router.dart');
    expect(source, contains("path: '/admin/records/ocr-baptism'"));
    expect(source, contains('BaptismalOcrScanPage'));
  });

  test('the legacy staff OCR upload route is left intact', () async {
    final source = await _read('lib/app/router.dart');
    expect(source, contains("path: '/staff/ocr/upload'"));
    expect(source, contains("path: '/admin/ocr/upload'"));
  });
}

Future<String> _read(String path) async => File(path).readAsString();
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/baptismal_ocr_route_test.dart`
Expected: FAIL — the route string isn't present.

- [ ] **Step 3: Register the route**

In `lib/app/router.dart`, add the import beside the other admin page imports:

```dart
import '../screens/admin/pages/baptismal_ocr_scan_page.dart';
```

and add this `GoRoute` immediately after the `/admin/ocr/upload` route (around line 612):

```dart
          GoRoute(
            path: '/admin/records/ocr-baptism',
            builder: (context, state) => const BaptismalOcrScanPage(),
          ),
```

- [ ] **Step 4: Repoint the button**

In `lib/screens/admin/pages/records_page.dart`, change line 346 from:

```dart
                  onPressed: () => context.push('/admin/ocr/upload'),
```

to:

```dart
                  onPressed: () => context.push('/admin/records/ocr-baptism'),
```

Leave the label, icon, and styling exactly as they are.

- [ ] **Step 5: Run tests**

Run: `flutter test test/baptismal_ocr_route_test.dart && flutter analyze`
Expected: PASS — 3 tests, analyze clean across the whole project.

- [ ] **Step 6: Run the full suite**

Run: `flutter test`
Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add lib/app/router.dart lib/screens/admin/pages/records_page.dart test/baptismal_ocr_route_test.dart
git commit -m "feat(ocr): route Add Record (OCR) to the new baptismal scan page"
```

---

### Task 17: Fixture recording script and setup docs

**Files:**
- Create: `backend/scripts/record_vision_fixture.js`
- Create: `docs/superpowers/notes/2026-08-22-baptismal-ocr-setup.md`
- Modify: `backend/package.json` (script entry)

This task produces the tooling to record real Vision responses. **Running it
requires credentials that are not available in the development environment** —
the script is the deliverable; executing it is a follow-up for whoever holds
the GCP key.

- [ ] **Step 1: Write the script**

Create `backend/scripts/record_vision_fixture.js`:

```js
#!/usr/bin/env node
/**
 * Records real Cloud Vision responses for the sample register photos, so the
 * layout tests can run offline against genuine OCR output.
 *
 * Usage (from the repo root, with credentials in the environment):
 *   node backend/scripts/record_vision_fixture.js
 *
 * Writes backend/test/fixtures/vision-<name>.json — the normalized word list,
 * NOT the raw Vision payload, to keep the fixtures small and stable.
 */

const fs = require('fs');
const path = require('path');

const { recognizeWords } = require('../src/services/baptismal_ocr_service');
const { preprocessForOcr } = require('../src/services/baptismal_image_preprocess');

const ATTACHMENTS = path.join(__dirname, '..', '..', 'attachments');
const OUT_DIR = path.join(__dirname, '..', 'test', 'fixtures');

async function main() {
  if (!process.env.GOOGLE_CLOUD_VISION_CREDENTIALS_JSON &&
      !process.env.FIREBASE_SERVICE_ACCOUNT_JSON) {
    console.error(
      'No Vision credentials in the environment. Set ' +
      'GOOGLE_CLOUD_VISION_CREDENTIALS_JSON (or FIREBASE_SERVICE_ACCOUNT_JSON) ' +
      'and make sure the Vision API is enabled on that project.',
    );
    process.exit(1);
  }

  fs.mkdirSync(OUT_DIR, { recursive: true });

  const files = fs.readdirSync(ATTACHMENTS).filter((f) => /\.(jpe?g|png|webp)$/i.test(f));
  if (files.length === 0) {
    console.error(`No images found in ${ATTACHMENTS}`);
    process.exit(1);
  }

  for (const file of files) {
    const buffer = fs.readFileSync(path.join(ATTACHMENTS, file));
    const prepared = await preprocessForOcr(buffer);
    const { words } = await recognizeWords(prepared);
    const name = path.basename(file).replace(/\.[^.]+$/, '').toLowerCase();
    const out = path.join(OUT_DIR, `vision-${name}.json`);
    fs.writeFileSync(out, JSON.stringify({ words }, null, 2));
    console.log(`${file}: ${words.length} words -> ${path.relative(process.cwd(), out)}`);
  }
}

main().catch((e) => {
  console.error(`Failed (${e.code || 'ERROR'}): ${e.message}`);
  process.exit(1);
});
```

- [ ] **Step 2: Add the npm script**

In `backend/package.json`, add to `"scripts"`:

```json
    "record:vision-fixtures": "node scripts/record_vision_fixture.js"
```

- [ ] **Step 3: Verify the guard path works without credentials**

Run: `cd backend && node scripts/record_vision_fixture.js`
Expected: exits 1 with the "No Vision credentials" message — no stack trace, no
network call. This is the only part of the script testable here.

- [ ] **Step 4: Write the setup note**

Create `docs/superpowers/notes/2026-08-22-baptismal-ocr-setup.md`:

```markdown
# Baptismal OCR — setup and verification

## Enabling Google Cloud Vision

1. In the Google Cloud console, open the project that owns the Firebase
   service account and enable the **Cloud Vision API**.
2. Either reuse that service account (no further config — the backend falls
   back to `FIREBASE_SERVICE_ACCOUNT_JSON`), or create a dedicated service
   account with the **Cloud Vision AI User** role and set its JSON key as
   `GOOGLE_CLOUD_VISION_CREDENTIALS_JSON` (single line) in the backend `.env`
   and in the Render dashboard.
3. Restart the backend. A misconfiguration surfaces as `VISION_AUTH` and the
   UI shows "OCR is not configured on the server."

## Recording test fixtures

Layout tests run against synthetic fixtures by default. To pin them to real
OCR output:

```bash
cd backend && npm run record:vision-fixtures
```

This writes `backend/test/fixtures/vision-img_3120.json` and friends from the
images in `attachments/`. Commit them.

## Manual verification checklist

Run against `attachments/IMG_3120.jpeg` (rotated 90°) and `IMG_3121.jpeg`
(rotated 180°):

- [ ] Fields land in the correct columns; names are not mixed with dates.
- [ ] The rotated pages produce the same rows as an upright photo would.
- [ ] Low-confidence cells are tinted amber; filled-down minister/date cells
      are tinted blue.
- [ ] Editing a cell updates the value and clears its error.
- [ ] Clearing a name blocks Save and names the offending row.
- [ ] Uploading a PDF is rejected with a clear message.
- [ ] With the backend stopped, scanning shows a retryable network error and
      the image survives the failure.
- [ ] Saving writes records visible in `/admin/records`.
- [ ] `/admin/records` → Manual Register and Import CSV still work unchanged.
- [ ] Staff OCR upload (`/staff/ocr/upload`) still works unchanged.
```

- [ ] **Step 5: Commit**

```bash
git add backend/scripts/record_vision_fixture.js backend/package.json
git add -f docs/superpowers/notes/2026-08-22-baptismal-ocr-setup.md
git commit -m "chore(ocr): add Vision fixture recorder and setup notes"
```

---

### Task 18: Full verification pass

**Files:** none created — this task proves the work.

- [ ] **Step 1: Backend suite**

Run: `cd backend && npm test`
Expected: PASS, including the pre-existing `ocrspace_service.test.js` and
`ocr_firestore.test.js`. Record the total count.

- [ ] **Step 2: Flutter analyze**

Run: `flutter analyze`
Expected: "No issues found."

- [ ] **Step 3: Flutter suite**

Run: `flutter test`
Expected: PASS. Note any pre-existing failures separately from new ones.

- [ ] **Step 4: Confirm the old path is untouched**

Run:

```bash
git diff --name-only main...HEAD -- lib/services/register_ocr_scan_helper.dart lib/services/register_ocr_parser.dart backend/src/routes/ocr_firestore.js backend/src/services/ocrspace_service.js
```

Expected: empty output. If anything is listed, that violates a global
constraint — revert those files.

- [ ] **Step 5: Report honestly**

State plainly which of the manual checks in
`docs/superpowers/notes/2026-08-22-baptismal-ocr-setup.md` were actually run
and which could not be (anything needing live Vision credentials). Do not
claim end-to-end accuracy that was never measured against the real API.

- [ ] **Step 6: Commit any fixes**

```bash
git add -A
git commit -m "fix(ocr): address verification findings"
```

---

## Self-Review

**Spec coverage:**

| Spec requirement | Task |
|---|---|
| Feature branch | Done before planning (`feature/baptismal-ocr-record`) |
| Study sample image | Done in brainstorming; encoded in the fixture geometry (Task 2) |
| Google Cloud Vision, server-side | 1, 9 |
| Scan or upload + preview | 15 |
| OCR processing + preprocessing, original preserved | 8, 15 |
| Editable OCR preview with confidence flags | 14, 15 |
| Baptismal fields from existing schema + two new | 10, 12 |
| Validation before saving, duplicates | 13, 15 |
| Image-to-field accuracy (header-anchored) | 2–7 |
| Error handling, retry without losing image | 9, 11, 15 |
| Dedicated service, separated concerns | 1, 7, 8 (Vision I/O, layout, imaging all separate) |
| Security: no client credentials, file validation, no sensitive logging | 1, 8, 9 |
| UI/UX five steps | 15 |
| No matrimonial OCR | Global constraints; nothing in any task touches marriage |
| Testing | Every task; 17, 18 |

**Placeholder scan:** no TBD/TODO. Every code step carries real code. No "similar to Task N" back-references.

**Type consistency checked:** the word shape `{text, vertices, confidence}` is produced by `recognizeWords` (Task 1) and consumed unchanged by `normalizeOrientation` (Task 2) through `extractBaptismalRows` (Task 7). The row shape `{index, lineNo, fields: {key: {value, confidence, inherited}}}` is produced by `joinPages`/`applyFillDown` (Task 7), serialized by the route (Task 9), and parsed by `BaptismalOcrScan.fromJson` (Task 10). `baptismalFieldKeys` (Task 10) is the key set used by the review table (Task 14), the notes map (Task 12), and the save path (Task 15). `RowIssue` (Task 13) is consumed by Tasks 14 and 15 with matching field names.

**Second bug, caught in the pre-flight scan (already fixed above):** Task 9 originally mounted the scan route with the other `/api/*` routes and gave it a router-level `express.json({ limit: '20mb' })`. That parser would have been dead code — `server.js:58` installs a global 10 MB JSON parser that runs before every route mount, so a valid ~13.4 MB base64 register photo would have died with a generic Express 413 and never reached the handler. The route now mounts ahead of the global parser and carries its own `verifyFirebaseToken` (injectable for tests); two regression tests pin both the size behavior and the mount ordering.

**Bug caught during self-review (already fixed above):** Task 4's column matcher originally used `['name', 'child']` for `nameOfChild`. Because the register has *two* headers containing "NAME" — `NAME OF CHILD` and `NAME OF PARENTS` — averaging both hits put the column center at x≈407 instead of 220, landing the child-name band on top of the birth-date column. Every extracted name would have been silently wrong. Fixed by matching only distinctive tokens and tightening fixture header spacing so matched-token averages track the ruled column; a regression test in Task 4 pins it.

**One deliberate gap:** Task 17 delivers the fixture recorder but cannot run it without credentials. Task 18 Step 5 requires reporting that honestly rather than claiming measured accuracy.
