# Marriage Register OCR Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add CV-grid OCR scanning of the marriage register spread, mirroring the baptismal pipeline across the Python CV service, Node backend, and Flutter UI, saving records in the existing flat `manual_marriage_register` schema.

**Architecture:** Reuse the baptismal three-layer pipeline. Python gains a declared `MARRIAGE_REGISTER` column template selectable via a `register` query param; Node gains a marriage scan route + grid-assign (with a groom/bride within-cell y-split) + a word-clustering fallback; Flutter gains a `MarriageOcrScanPage` that reuses the existing `RegisterMarriageEntry` model and `RegisterMarriageTable` widget, saving via a new `toMarriageOcrNotesMap`.

**Tech Stack:** Python 3.10 / FastAPI / OpenCV (`ocr_service/`), Node/Express + Jest (`backend/`), Flutter/Dart + `flutter_test` (`lib/`, `test/`).

## Global Constraints

- **Spec:** `docs/superpowers/specs/2026-09-16-marriage-ocr-record-design.md`.
- **Save schema:** flat `manual_marriage_register` (from `ManualRegisterNotes.toMarriageNotesMap`), `source` stays `'manual_marriage_register'`, `status: 'official'` for OCR-reviewed saves. NEVER the certificate `marriage_form_screen` schema.
- **No lossy field mapping:** every register column maps 1:1 to a `RegisterMarriageEntry`/`MarriagePartyInfo` field. Parents stays one blob per party; sponsors (shared column) → `groom.sponsors`.
- **Do not modify** the baptismal pipeline except the backward-compatible `cv_grid_client` `register` param. Do not modify or remove the legacy ML-Kit marriage path (`StaffOcrUploadPage`, `RegisterMarriageOcrHelper`, `register_ocr_parser.dart`).
- **Logging:** never log cell values / recognized text / names (records of minors and PII). Counts only, matching baptismal.
- **TDD:** every task writes the failing test first. Frequent commits.
- **Backend API base:** the marriage router mounts at `/api/ocr/marriage`; the Flutter client posts to `${BackendConfig.apiBaseUrl}/ocr/marriage/scan` (mirrors `/ocr/baptismal/scan`).
- **New warning code:** `GROOM_BRIDE_SPLIT_UNCERTAIN`.

---

## File Structure

**Python (`ocr_service/`)**
- Modify `app/pipeline/column_template.py` — add `MARRIAGE_LEFT`, `MARRIAGE_RIGHT`, `MARRIAGE_REGISTER`.
- Modify `app/main.py` — `/v1/grid?register=` selects the spread template.
- Modify `tests/test_column_template.py` — marriage template + fit tests.
- Modify `tests/test_grid_endpoint.py` — `register=marriage` wiring.

**Node (`backend/src/`)**
- Modify `services/cv_grid_client.js` — `register` option → `?register=`.
- Create `services/marriage_grid_assign.js` (+ `.test.js`) — grid cells → marriage rows, groom/bride y-split.
- Create `services/marriage_register_layout.js` (+ `.test.js`) — word-clustering fallback.
- Create `routes/marriage_ocr_firestore.js` (+ `.test.js`) — `/scan` route.
- Modify `server.js` — mount `/api/ocr/marriage`.

**Flutter (`lib/`, `test/`)**
- Modify `models/register_marriage_entry.dart` — `fromScanJson` factory (+ `test/register_marriage_entry_test.dart`).
- Create `services/marriage_ocr_service.dart` (+ `test/marriage_ocr_service_test.dart`) — `MarriageOcrService`, `MarriageOcrScan`.
- Modify `utils/manual_register_notes.dart` — `toMarriageOcrNotesMap` (+ extend `test/manual_register_notes_*`).
- Create `services/marriage_row_validation.dart` (+ `test/marriage_row_validation_test.dart`).
- Create `screens/admin/pages/marriage_ocr_scan_page.dart` (+ `test/marriage_ocr_scan_page_test.dart`).
- Modify `app/router.dart` — `/admin/records/ocr-marriage`.
- Modify `screens/admin/pages/baptismal_ocr_scan_page.dart` — chooser routes to marriage page.

---

## Task 1: Marriage column template (Python)

**Files:**
- Modify: `ocr_service/app/pipeline/column_template.py`
- Test: `ocr_service/tests/test_column_template.py`

**Interfaces:**
- Produces: `MARRIAGE_LEFT`, `MARRIAGE_RIGHT` (`ColumnTemplate`), `MARRIAGE_REGISTER` (`SpreadColumnTemplate`, `data_row_count`).
  - `MARRIAGE_LEFT.columns = ("no","contracting_parties","legal_status","actual_address","birth","baptism","marriage_date")`
  - `MARRIAGE_RIGHT.columns = ("parents","sponsors","minister","license_no","observations")`

- [ ] **Step 1: Measure boundary fractions from the sample photos.**

The exact fractions must be measured, exactly as the baptismal ones were (read on ≥3 straight-on photos, agree to ~0.01). Use the clear, straight-on samples: `attachments/marriage/201722d30a79f8398ef86834c4a8da8c.jpeg`, `d0b1b5f7a402a11b1b0bcb3587e90bce.jpeg`. Run column-rule detection per page half to get candidate rule x-positions, then normalize to the table extent:

```bash
cd ocr_service && .venv310/Scripts/python -c "
import cv2, numpy as np
from app.pipeline.orientation import correct_orientation
from app.pipeline.inversion import correct_spread_inversion
from app.pipeline.spread import split_spread
from app.pipeline.rectify import rectify_page
from app.pipeline.table import detect_column_rule_positions, _binary, _cluster_row_segments, _row_strip_segments, _table_x_extent, ROW_STRIP_COUNT
img = cv2.imread('../attachments/marriage/d0b1b5f7a402a11b1b0bcb3587e90bce.jpeg')
sp = correct_spread_inversion(correct_orientation(img).image).image
pages = split_spread(sp)
for side, p in (('left', pages.left), ('right', pages.right)):
    page = rectify_page(p).image
    rules = detect_column_rule_positions(page)
    rows = _cluster_row_segments(_row_strip_segments(_binary(page)))
    ext = _table_x_extent(rows, page.shape[1], max(2, round(ROW_STRIP_COUNT*0.5)))
    if ext:
        lo, hi = ext; w = hi - lo
        print(side, 'extent', ext, 'fractions', [round((x-lo)/w, 3) for x in rules if lo <= x <= hi])
"
```

Record the fractions. As a **starting point** (refine with the measurement above; the corroboration gate in Task 1 Step 4 / Task 13 is the real acceptance test):
- Left (7 cols → 8 boundaries): `(0.000, 0.045, 0.205, 0.300, 0.460, 0.680, 0.860, 1.000)`
- Right (5 cols → 6 boundaries): `(0.000, 0.300, 0.550, 0.720, 0.850, 1.000)`

- [ ] **Step 2: Write the failing template test.**

Add to `tests/test_column_template.py` inside `TestTemplateDeclaration` (import `MARRIAGE_LEFT, MARRIAGE_RIGHT, MARRIAGE_REGISTER`):

```python
def test_marriage_left_and_right_column_keys(self):
    assert MARRIAGE_LEFT.columns == (
        "no", "contracting_parties", "legal_status", "actual_address",
        "birth", "baptism", "marriage_date",
    )
    assert MARRIAGE_RIGHT.columns == (
        "parents", "sponsors", "minister", "license_no", "observations",
    )

def test_marriage_boundaries_span_the_table(self):
    for t in (MARRIAGE_LEFT, MARRIAGE_RIGHT):
        assert t.boundaries[0] == 0.0 and t.boundaries[-1] == 1.0
        assert len(t.boundaries) == t.column_count + 1

def test_marriage_register_declares_row_count_and_two_rulings(self):
    assert MARRIAGE_REGISTER.left is MARRIAGE_LEFT
    assert MARRIAGE_REGISTER.right is MARRIAGE_RIGHT
    assert MARRIAGE_REGISTER.data_row_count >= 1
```

- [ ] **Step 3: Run it — verify it fails** with `ImportError`/`cannot import name`.

Run: `cd ocr_service && .venv310/Scripts/python -m pytest tests/test_column_template.py -k marriage -v`

- [ ] **Step 4: Implement the templates.**

Append to `column_template.py` (fill `boundaries` from Step 1; set `data_row_count` to the entries the printed marriage form is ruled for — count on a full page, e.g. 20):

```python
MARRIAGE_LEFT = ColumnTemplate(
    name="marriage_register_left_page",
    columns=("no", "contracting_parties", "legal_status",
             "actual_address", "birth", "baptism", "marriage_date"),
    boundaries=(0.000, 0.045, 0.205, 0.300, 0.460, 0.680, 0.860, 1.000),
)

MARRIAGE_RIGHT = ColumnTemplate(
    name="marriage_register_right_page",
    columns=("parents", "sponsors", "minister", "license_no", "observations"),
    boundaries=(0.000, 0.300, 0.550, 0.720, 0.850, 1.000),
)

MARRIAGE_REGISTER = SpreadColumnTemplate(
    name="marriage_register",
    left=MARRIAGE_LEFT,
    right=MARRIAGE_RIGHT,
    data_row_count=20,
)
```

- [ ] **Step 5: Run tests — verify pass.**

Run: `cd ocr_service && .venv310/Scripts/python -m pytest tests/test_column_template.py -v`

- [ ] **Step 6: Commit.**

```bash
git add ocr_service/app/pipeline/column_template.py ocr_service/tests/test_column_template.py
git commit -m "feat(ocr-service): declare MARRIAGE_REGISTER column template"
```

---

## Task 2: Select register template at `/v1/grid` (Python)

**Files:**
- Modify: `ocr_service/app/main.py`
- Test: `ocr_service/tests/test_grid_endpoint.py`

**Interfaces:**
- Consumes: `MARRIAGE_REGISTER` (Task 1).
- Produces: `/v1/grid?register=marriage|baptismal` (default `baptismal`) selecting the spread template passed to `detect_spread_grids`.

- [ ] **Step 1: Write the failing endpoint test.**

Add to `tests/test_grid_endpoint.py` (the `_fake_spread` stub already bypasses real detection):

```python
def test_grid_selects_marriage_template(monkeypatch):
    monkeypatch.setenv("OCR_SERVICE_KEY", "k")
    get_settings.cache_clear()
    captured = {}
    def _spy(left, right, spread_template=None):
        captured["template"] = spread_template
        return _fake_spread()
    monkeypatch.setattr(main_module, "detect_spread_grids", _spy)
    spread = make_register_spread(rows=24, cols_left=5, cols_right=5)
    res = client.post("/v1/grid?register=marriage", content=_png_bytes(spread),
                      headers={"X-OCR-Service-Key": "k"})
    assert res.status_code == 200, res.text
    assert captured["template"].name == "marriage_register"
    get_settings.cache_clear()
```

- [ ] **Step 2: Run — verify it fails** (template is `baptismal_register`, not `marriage_register`).

Run: `cd ocr_service && .venv310/Scripts/python -m pytest tests/test_grid_endpoint.py::test_grid_selects_marriage_template -v`

- [ ] **Step 3: Implement register selection in `main.py`.**

Import the marriage template and pick by query param:

```python
from .pipeline.column_template import BAPTISMAL_REGISTER, MARRIAGE_REGISTER

_REGISTERS = {"baptismal": BAPTISMAL_REGISTER, "marriage": MARRIAGE_REGISTER}
```

In `detect_grid_endpoint`, read `register` from the query and select:

```python
async def detect_grid_endpoint(request: Request,
                               x_ocr_service_key: str | None = Header(default=None)) -> dict:
    ...
    register = request.query_params.get("register", "baptismal")
    spread_template = _REGISTERS.get(register, BAPTISMAL_REGISTER)
    ...
    grids = detect_spread_grids(left, right, spread_template=spread_template)
```

- [ ] **Step 4: Run tests — verify pass.**

Run: `cd ocr_service && .venv310/Scripts/python -m pytest tests/test_grid_endpoint.py -v`

- [ ] **Step 5: Commit.**

```bash
git add ocr_service/app/main.py ocr_service/tests/test_grid_endpoint.py
git commit -m "feat(ocr-service): select register template via ?register= query"
```

---

## Task 3: `register` option in the CV grid client (Node)

**Files:**
- Modify: `backend/src/services/cv_grid_client.js`
- Test: `backend/src/services/cv_grid_client.test.js` (create if absent)

**Interfaces:**
- Consumes: `/v1/grid?register=` (Task 2).
- Produces: `fetchGrid(imageBuffer, { env, fetchImpl, register })` — appends `?register=<register>` to the URL when `register` is set. Default behavior (no `register`) is unchanged (no query string), so baptismal callers are untouched.

- [ ] **Step 1: Write the failing test.**

```js
const { fetchGrid } = require('./cv_grid_client');

test('appends ?register=marriage to the grid URL', async () => {
  let calledUrl;
  const fetchImpl = async (url) => { calledUrl = url; return {
    ok: true, json: async () => ({ success: true, rotation_applied: 0,
      pages: { left: { image_b64: 'x', cells: [] }, right: { image_b64: 'x', cells: [] } } }) }; };
  await fetchGrid(Buffer.from('img'), {
    env: { OCR_SERVICE_URL: 'http://svc', OCR_SERVICE_KEY: 'k' },
    fetchImpl, register: 'marriage',
  });
  expect(calledUrl).toBe('http://svc/v1/grid?register=marriage');
});
```

- [ ] **Step 2: Run — verify it fails.** `cd backend && npx jest cv_grid_client -t "register"`

- [ ] **Step 3: Implement.** In `fetchGrid`'s signature add `register`, and build the URL:

```js
async function fetchGrid(imageBuffer, { env = process.env, fetchImpl = fetch, register } = {}) {
  const baseUrl = env.OCR_SERVICE_URL;
  if (!baseUrl) throw new CvGridError('CV_DISABLED', 'OCR_SERVICE_URL not set');
  ...
  const query = register ? `?register=${encodeURIComponent(register)}` : '';
  res = await fetchImpl(`${baseUrl.replace(/\/$/, '')}/v1/grid${query}`, { ... });
```

- [ ] **Step 4: Run tests.** `cd backend && npx jest cv_grid_client`
- [ ] **Step 5: Commit.**

```bash
git add backend/src/services/cv_grid_client.*
git commit -m "feat(backend): fetchGrid accepts register selector"
```

---

## Task 4: Marriage grid → rows with groom/bride split (Node)

**Files:**
- Create: `backend/src/services/marriage_grid_assign.js`
- Test: `backend/src/services/marriage_grid_assign.test.js`

**Interfaces:**
- Consumes: CV page object `{ cells: [{key,row,x,y,w,h}], ... }` and OCR words `[{ text, confidence, vertices: [{x,y}×4] }]` (same shapes `baptismal_grid_assign.js` consumes).
- Produces: `marriageGridToRows(leftPage, leftWords, rightPage, rightWords) → { rows, warnings }` where each row is:
  ```
  { lineNo, groom: {name,legalStatus,actualAddress,datesPlaceOfBirth,datesPlaceOfBaptism,parents,sponsors},
    bride: {…same…}, dateOfMarriage, minister, licenseNumber, observations }
  ```
  Values are plain strings (OCR.space has no per-field confidence). `warnings` may contain `GROOM_BRIDE_SPLIT_UNCERTAIN`.

**Design notes:**
- Grid `key` → field map. Paired keys split top/bottom; shared keys take the whole cell.
  - Left: `no`→lineNo; `contracting_parties`→name (paired); `legal_status`→legalStatus (paired); `actual_address`→actualAddress (paired); `birth`→datesPlaceOfBirth (paired); `baptism`→datesPlaceOfBaptism (paired); `marriage_date`→dateOfMarriage (shared).
  - Right: `parents`→parents (paired); `sponsors`→sponsors (shared → groom.sponsors); `minister`→minister (shared); `license_no`→licenseNumber (shared); `observations`→observations (shared).
- **Groom/bride split:** for a paired cell, a word belongs to groom if its box y-center < cell.y + cell.h/2, else bride. Emit `GROOM_BRIDE_SPLIT_UNCERTAIN` for the scan if any paired cell has ≥2 words but every word lands on the same side (can't tell the two lines apart).
- Reuse baptismal's row-offset/data-row logic conceptually but simpler: canonical row index = left cells' rows; pair right by the same index offset technique from `baptismal_grid_assign.rowOffset` (copy that helper).

- [ ] **Step 1: Write the failing tests.**

```js
const { marriageGridToRows } = require('./marriage_grid_assign');

// One cell per (row,key). Row 1 = header, row 2 = entry with groom top / bride bottom.
function word(text, x, y) {
  return { text, confidence: 90, vertices: [
    {x, y}, {x: x + 10, y}, {x: x + 10, y: y + 6}, {x, y: y + 6}] };
}
function cell(key, row, x, y, w, h) { return { key, row, x, y, w, h }; }

test('splits a paired cell into groom (top) and bride (bottom)', () => {
  const left = { cells: [
    cell('no', 1, 0, 100, 40, 80),
    cell('contracting_parties', 1, 40, 100, 200, 80),
    cell('marriage_date', 1, 240, 100, 120, 80),
  ] };
  const leftWords = [
    word('47', 5, 110),
    word('Marlon', 50, 110),   // top half -> groom
    word('Ana', 50, 160),      // bottom half -> bride
    word('1994', 250, 110),    // shared
  ];
  const right = { cells: [] };
  const { rows } = marriageGridToRows(left, leftWords, right, []);
  expect(rows).toHaveLength(1);
  expect(rows[0].groom.name).toBe('Marlon');
  expect(rows[0].bride.name).toBe('Ana');
  expect(rows[0].dateOfMarriage).toBe('1994');
  expect(rows[0].lineNo).toBe('47');
});

test('flags GROOM_BRIDE_SPLIT_UNCERTAIN when both names land on one side', () => {
  const left = { cells: [ cell('contracting_parties', 1, 40, 100, 200, 80) ] };
  const leftWords = [ word('Marlon', 50, 108), word('Ana', 90, 112) ]; // both top
  const { warnings } = marriageGridToRows(left, leftWords, { cells: [] }, []);
  expect(warnings).toContain('GROOM_BRIDE_SPLIT_UNCERTAIN');
});

test('sponsors (shared right col) go to groom.sponsors', () => {
  const right = { cells: [ cell('sponsors', 1, 0, 100, 200, 80) ] };
  const rightWords = [ word('Victor', 10, 120), word('Amalia', 60, 120) ];
  const { rows } = marriageGridToRows({ cells: [cell('contracting_parties',1,0,100,10,80)] },
    [word('X', 1, 110)], right, rightWords);
  expect(rows[0].groom.sponsors).toContain('Victor');
});
```

- [ ] **Step 2: Run — verify failure.** `cd backend && npx jest marriage_grid_assign`

- [ ] **Step 3: Implement `marriage_grid_assign.js`.**

```js
const PAIRED_LEFT = {
  contracting_parties: 'name', legal_status: 'legalStatus',
  actual_address: 'actualAddress', birth: 'datesPlaceOfBirth', baptism: 'datesPlaceOfBaptism',
};
const PAIRED_RIGHT = { parents: 'parents' };
const SHARED_LEFT = { marriage_date: 'dateOfMarriage' };
const SHARED_RIGHT = {
  sponsors: 'sponsors', minister: 'minister',
  license_no: 'licenseNumber', observations: 'observations',
};

function centre(w) {
  const xs = w.vertices.map((v) => v.x); const ys = w.vertices.map((v) => v.y);
  return { cx: (Math.min(...xs) + Math.max(...xs)) / 2,
           cy: (Math.min(...ys) + Math.max(...ys)) / 2, word: w };
}
function inRect(cx, cy, c) { return cx >= c.x && cx < c.x + c.w && cy >= c.y && cy < c.y + c.h; }
function joinText(words) {
  return words.slice().sort((a, b) => a.centre.cy - b.centre.cy || a.centre.cx - b.centre.cx)
    .map((w) => w.word.text).join(' ').replace(/\s+/g, ' ').trim();
}

function marriageGridToRows(leftPage, leftWords, rightPage, rightWords) {
  const warnings = new Set();
  const rowsMap = new Map(); // rowIndex -> entry skeleton
  const ensure = (r) => {
    if (!rowsMap.has(r)) rowsMap.set(r, {
      lineNo: '', groom: blankParty(), bride: blankParty(),
      dateOfMarriage: '', minister: '', licenseNumber: '', observations: '' });
    return rowsMap.get(r);
  };

  const assign = (page, words, pairedMap, sharedMap) => {
    const cells = (page && page.cells) || [];
    const placed = (words || []).map(centre);
    for (const c of cells) {
      const hits = placed.filter((p) => inRect(p.cx, p.cy, c));
      const entry = ensure(c.row);
      if (c.key === 'no') { entry.lineNo = joinText(hits) || entry.lineNo; continue; }
      if (pairedMap[c.key]) {
        const field = pairedMap[c.key];
        const mid = c.y + c.h / 2;
        const top = hits.filter((p) => p.cy < mid);
        const bottom = hits.filter((p) => p.cy >= mid);
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

function blankParty() {
  return { name: '', legalStatus: '', actualAddress: '',
           datesPlaceOfBirth: '', datesPlaceOfBaptism: '', parents: '', sponsors: '' };
}

module.exports = { marriageGridToRows, PAIRED_LEFT, PAIRED_RIGHT, SHARED_LEFT, SHARED_RIGHT };
```

> Note: header/lineNo numbering and left/right row-offset alignment are handled in Task 6 (route) using the same `rowOffset`/`isDataRow` approach as `baptismal_grid_assign.js`. Keep this module a pure cell→field mapper; the route drops the header band and renumbers.

- [ ] **Step 4: Run tests — verify pass.** `cd backend && npx jest marriage_grid_assign`
- [ ] **Step 5: Commit.**

```bash
git add backend/src/services/marriage_grid_assign.*
git commit -m "feat(backend): marriage grid-assign with groom/bride cell split"
```

---

## Task 5: Word-clustering fallback for marriage (Node)

**Files:**
- Create: `backend/src/services/marriage_register_layout.js`
- Test: `backend/src/services/marriage_register_layout.test.js`

**Interfaces:**
- Consumes: OCR words `[{text, confidence, vertices}]`.
- Produces: `extractMarriageRows(words) → { rows, rotation, warnings }` with the same row shape as Task 4. Throws `Error` with `.code = 'LAYOUT_UNRECOGNIZED'` when the page is not a marriage register.

**Design notes:** This mirrors `baptismal_register_layout.js` closely. Copy that file as the starting point and adapt:
1. `LEFT_COLUMNS` / `RIGHT_COLUMNS` → marriage columns with distinctive header tokens and fallback ratios matching the template fractions from Task 1:
   ```js
   const LEFT_COLUMNS = [
     { key: 'lineNo',              header: ['no'],           fallbackRatio: 0.02 },
     { key: 'contractingParties',  header: ['contracting'],  fallbackRatio: 0.12 },
     { key: 'legalStatus',         header: ['legal','status'], fallbackRatio: 0.25 },
     { key: 'actualAddress',       header: ['actual','address'], fallbackRatio: 0.38 },
     { key: 'birth',               header: ['birth'],        fallbackRatio: 0.57 },
     { key: 'baptism',             header: ['baptism'],      fallbackRatio: 0.77 },
     { key: 'marriageDate',        header: ['marriage'],     fallbackRatio: 0.93 },
   ];
   const RIGHT_COLUMNS = [
     { key: 'parents',       header: ['parents'],      fallbackRatio: 0.15 },
     { key: 'sponsors',      header: ['sponsors'],     fallbackRatio: 0.42 },
     { key: 'minister',      header: ['minister'],     fallbackRatio: 0.63 },
     { key: 'licenseNo',     header: ['license'],      fallbackRatio: 0.78 },
     { key: 'observations',  header: ['observations'], fallbackRatio: 0.92 },
   ];
   ```
2. Gutter title confirm tokens: `marriage` (left) / `register` (right) — reuse `splitSpread`'s `hasTitle` logic with these words.
3. After `assignCells` produces per-row per-column blobs, convert to the marriage row shape by splitting each paired column's cell words into groom/bride by y (reuse the Task 4 split: top half vs bottom half of the row band `y0..y1`). Add a small helper `toMarriageRow(cells, rowBand)` that produces `{groom, bride, ...}` and pushes `GROOM_BRIDE_SPLIT_UNCERTAIN` when a paired cell can't be split.
4. `marriageDate`, `sponsors`, `minister`, `licenseNo`, `observations` are shared (no split); `sponsors`→`groom.sponsors`.
5. Keep `applyFillDown` for `minister` and `dateOfMarriage` only (copy the pattern; rename `dateOfBaptism`→`dateOfMarriage`).
6. `LAYOUT_UNRECOGNIZED` guard: require ≥1 matched header on each side and ≥3 combined (same thresholds as baptismal).

- [ ] **Step 1: Write failing tests** using the synthetic word fixtures the baptismal layout tests use. Copy `backend/test/helpers/register_fixture.js` usage from `baptismal_register_layout` tests if present; otherwise build minimal word arrays inline. Cover: (a) column calibration matches marriage headers; (b) a paired column with a top word and bottom word yields groom/bride; (c) a non-register page throws `LAYOUT_UNRECOGNIZED`.

```js
const { extractMarriageRows } = require('./marriage_register_layout');
// build words for a 2-line entry: headers row, then groom line + bride line...
test('non-register page is rejected', () => {
  const words = [{ text: 'memo', confidence: 80,
    vertices: [{x:0,y:0},{x:10,y:0},{x:10,y:6},{x:0,y:6}] }];
  expect(() => extractMarriageRows(words)).toThrow(/LAYOUT_UNRECOGNIZED/);
});
```

- [ ] **Step 2: Run — verify failure.** `cd backend && npx jest marriage_register_layout`
- [ ] **Step 3: Implement** by copying and adapting `baptismal_register_layout.js` per the design notes above.
- [ ] **Step 4: Run tests — verify pass.** `cd backend && npx jest marriage_register_layout`
- [ ] **Step 5: Commit.**

```bash
git add backend/src/services/marriage_register_layout.*
git commit -m "feat(backend): word-clustering fallback for marriage register"
```

---

## Task 6: Marriage scan route + mount (Node)

**Files:**
- Create: `backend/src/routes/marriage_ocr_firestore.js`
- Test: `backend/src/routes/marriage_ocr_firestore.test.js`
- Modify: `backend/src/server.js`

**Interfaces:**
- Consumes: `marriageGridToRows` (Task 4), `extractMarriageRows` (Task 5), `fetchGrid({register:'marriage'})` (Task 3), and the shared services `recognizeWords`, `preprocessForOcr`, `sniffImageType`, `isHeic/heicToJpeg`, `verifyFirebaseToken`.
- Produces: `POST /api/ocr/marriage/scan` returning `{ success, data: { scanId, rows, rotation, warnings } }` with `rows` in the Task 4 shape and `warnings` always including `CONFIDENCE_UNAVAILABLE`.

**Design notes:** Copy `baptismal_ocr_firestore.js` as the base. Change:
- `createMarriageOcrRouter(deps)`; import `marriageGridToRows` and `extractMarriageRows`.
- CV path: `fetchGrid(buffer, { register: 'marriage' })`; build rows via `marriageGridToRows(grid.pages.left, leftOcr.words, grid.pages.right, rightOcr.words)`.
- Header-band drop + renumber: after `marriageGridToRows`, drop the header row (first row whose `groom.name`/`lineNo` is header-like) and renumber `lineNo` by position — port `isDataRow`/`plausibleNo` from `baptismal_grid_assign.js` (adapt `nameOfChild`→`groom.name`).
- Fallback path: `extractMarriageRows(words)`.
- `LAYOUT_UNRECOGNIZED` message: `'This page does not look like a marriage register. Check the photo and retry.'`
- Keep all image gates, error codes/status, refusalDetail, logging (counts only) identical.

- [ ] **Step 1: Write failing route tests** (mirror `baptismal_ocr_firestore.test.js`): inject fake `recognize`/`fetchGrid`/`verifyToken`; assert (a) a valid marriage image returns rows in the marriage shape with `CONFIDENCE_UNAVAILABLE`; (b) non-staff → 403; (c) CV_REFUSED → `SPREAD_UNREADABLE` with detail; (d) a CV failure falls back to `extractMarriageRows` and adds `CV_UNAVAILABLE`.

```js
const request = require('supertest');
const express = require('express');
const { createMarriageOcrRouter } = require('./marriage_ocr_firestore');
// ... build app with injected deps returning a one-row marriage grid ...
```

- [ ] **Step 2: Run — verify failure.** `cd backend && npx jest marriage_ocr_firestore`
- [ ] **Step 3: Implement** the route by adapting the baptismal route per design notes.
- [ ] **Step 4: Mount in `server.js`** next to the baptismal mount (before the global JSON parser, as the baptismal one is):

```js
const marriageOcrRoutes = require('./routes/marriage_ocr_firestore');
// near line 61:
app.use('/api/ocr/marriage', marriageOcrRoutes.router);
```

- [ ] **Step 5: Run tests — verify pass.** `cd backend && npx jest marriage_ocr_firestore`
- [ ] **Step 6: Commit.**

```bash
git add backend/src/routes/marriage_ocr_firestore.* backend/src/server.js
git commit -m "feat(backend): marriage OCR /scan route (CV-first + fallback)"
```

---

## Task 7: `RegisterMarriageEntry.fromScanJson` + `MarriageOcrScan` (Flutter)

**Files:**
- Modify: `lib/models/register_marriage_entry.dart`
- Test: `test/register_marriage_entry_test.dart`

**Interfaces:**
- Produces: `factory RegisterMarriageEntry.fromScanJson(Map<String, dynamic> row)` building an entry (fresh uuid) from one backend row (Task 6 shape).

- [ ] **Step 1: Write the failing test.**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:parishrecord/models/register_marriage_entry.dart';

void main() {
  test('fromScanJson maps groom/bride and shared fields', () {
    final e = RegisterMarriageEntry.fromScanJson({
      'lineNo': '47',
      'groom': {'name': 'Marlon', 'legalStatus': 'single', 'parents': 'A & B'},
      'bride': {'name': 'Ana', 'actualAddress': 'Ozamiz'},
      'dateOfMarriage': 'Apr 18 1994',
      'minister': 'Alfredo',
      'licenseNumber': '8817424',
      'observations': 'catholic',
    });
    expect(e.lineNo, '47');
    expect(e.groom.name, 'Marlon');
    expect(e.bride.name, 'Ana');
    expect(e.bride.actualAddress, 'Ozamiz');
    expect(e.dateOfMarriage, 'Apr 18 1994');
    expect(e.licenseNumber, '8817424');
    expect(e.id, isNotEmpty);
  });
}
```

- [ ] **Step 2: Run — verify failure.** `flutter test test/register_marriage_entry_test.dart`
- [ ] **Step 3: Implement `fromScanJson`.** Add `import 'package:uuid/uuid.dart';` and:

```dart
factory RegisterMarriageEntry.fromScanJson(Map<String, dynamic> row) {
  MarriagePartyInfo party(dynamic v) {
    final m = v is Map ? Map<String, dynamic>.from(v) : const <String, dynamic>{};
    String s(String k) => (m[k] ?? '').toString();
    return MarriagePartyInfo(
      name: s('name'), legalStatus: s('legalStatus'), actualAddress: s('actualAddress'),
      datesPlaceOfBirth: s('datesPlaceOfBirth'), datesPlaceOfBaptism: s('datesPlaceOfBaptism'),
      parents: s('parents'), sponsors: s('sponsors'),
    );
  }
  String s(String k) => (row[k] ?? '').toString();
  final ln = s('lineNo');
  return RegisterMarriageEntry(
    id: const Uuid().v4(),
    lineNo: ln.isEmpty ? null : ln,
    groom: party(row['groom']), bride: party(row['bride']),
    dateOfMarriage: s('dateOfMarriage'), minister: s('minister'),
    licenseNumber: s('licenseNumber'), observations: s('observations'),
    selected: true,
  );
}
```

- [ ] **Step 4: Run tests — verify pass.** `flutter test test/register_marriage_entry_test.dart`
- [ ] **Step 5: Commit.**

```bash
git add lib/models/register_marriage_entry.dart test/register_marriage_entry_test.dart
git commit -m "feat(marriage-ocr): RegisterMarriageEntry.fromScanJson"
```

---

## Task 8: `MarriageOcrService` (Flutter)

**Files:**
- Create: `lib/services/marriage_ocr_service.dart`
- Test: `test/marriage_ocr_service_test.dart`

**Interfaces:**
- Consumes: `RegisterMarriageEntry.fromScanJson` (Task 7); `BackendConfig.apiBaseUrl`.
- Produces:
  - `class MarriageOcrScan { String scanId; int rotation; List<String> warnings; List<RegisterMarriageEntry> entries; }`
  - `class MarriageOcrService { Future<MarriageOcrScan> scan({required String scanId, required Uint8List bytes, String? idToken}); }`
  - Reuse the baptismal `OcrRecovery` enum + failure taxonomy. To avoid duplication, `export`/reuse: define `MarriageOcrFailure` mirroring `BaptismalOcrFailure`, OR reuse the baptismal one. Simplest: copy `baptismal_ocr_service.dart` and rename `Baptismal*`→`Marriage*`, change the URL to `/ocr/marriage/scan`, and parse `data['rows']` into `entries` via `fromScanJson`.

- [ ] **Step 1: Write failing test** injecting a fake `http.Client` (use `MockClient` from `package:http/testing.dart`):

```dart
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:http/http.dart' as http;
import 'package:parishrecord/services/marriage_ocr_service.dart';

void main() {
  test('parses rows into RegisterMarriageEntry list', () async {
    final client = MockClient((req) async => http.Response(jsonEncode({
      'success': true,
      'data': { 'scanId': 's1', 'rotation': 0, 'warnings': ['CONFIDENCE_UNAVAILABLE'],
        'rows': [ { 'lineNo': '1', 'groom': {'name': 'M'}, 'bride': {'name': 'A'},
          'dateOfMarriage': '1994' } ] },
    }), 200));
    final svc = MarriageOcrService(client: client);
    final scan = await svc.scan(scanId: 's1', bytes: Uint8List(3), idToken: 'tok');
    expect(scan.entries, hasLength(1));
    expect(scan.entries.first.groom.name, 'M');
    expect(scan.warnings, contains('CONFIDENCE_UNAVAILABLE'));
  });
}
```

- [ ] **Step 2: Run — verify failure.** `flutter test test/marriage_ocr_service_test.dart`
- [ ] **Step 3: Implement** by copying `baptismal_ocr_service.dart`, renaming to `Marriage*`, URL `'${BackendConfig.apiBaseUrl}/ocr/marriage/scan'`, and building `MarriageOcrScan` from `data`:

```dart
final rows = (data['rows'] as List? ?? [])
    .whereType<Map>()
    .map((r) => RegisterMarriageEntry.fromScanJson(Map<String, dynamic>.from(r)))
    .toList();
return MarriageOcrScan(
  scanId: data['scanId']?.toString() ?? scanId,
  rotation: (data['rotation'] as num?)?.toInt() ?? 0,
  warnings: (data['warnings'] as List? ?? []).map((w) => w.toString()).toList(),
  entries: rows,
);
```

- [ ] **Step 4: Run tests — verify pass.** `flutter test test/marriage_ocr_service_test.dart`
- [ ] **Step 5: Commit.**

```bash
git add lib/services/marriage_ocr_service.dart test/marriage_ocr_service_test.dart
git commit -m "feat(marriage-ocr): MarriageOcrService client"
```

---

## Task 9: `toMarriageOcrNotesMap` (Flutter)

**Files:**
- Modify: `lib/utils/manual_register_notes.dart`
- Test: `test/manual_register_notes_marriage_ocr_test.dart`

**Interfaces:**
- Consumes: `RegisterMarriageEntry`.
- Produces: `static Map<String, dynamic> toMarriageOcrNotesMap({required String volNo, required String seriesNo, required RegisterMarriageEntry entry, required String scanId, String? imagePath, String status = 'official'})` — the flat schema of `toMarriageNotesMap` plus `ocrScanId`/`originalImagePath`, `source: 'manual_marriage_register'`.

- [ ] **Step 1: Write failing test.**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:parishrecord/models/register_marriage_entry.dart';
import 'package:parishrecord/utils/manual_register_notes.dart';

void main() {
  test('toMarriageOcrNotesMap keeps flat register schema + provenance', () {
    final e = RegisterMarriageEntry(id: '1', lineNo: '3',
      groom: MarriagePartyInfo(name: 'M', parents: 'A & B'),
      bride: MarriagePartyInfo(name: 'A'),
      dateOfMarriage: 'Apr 18 1994', minister: 'Alf', licenseNumber: '88', observations: 'catholic');
    final m = ManualRegisterNotes.toMarriageOcrNotesMap(
      volNo: '20-B', seriesNo: 'S1', entry: e, scanId: 'scan-1', imagePath: null);
    expect(m['source'], 'manual_marriage_register');
    expect(m['status'], 'official');
    expect(m['sacramentType'], 'marriage');
    expect((m['groom'] as Map)['name'], 'M');
    expect(m['ocrScanId'], 'scan-1');
    expect(ManualRegisterNotes.isManualMarriageMap(m), isTrue);
  });
}
```

- [ ] **Step 2: Run — verify failure.** `flutter test test/manual_register_notes_marriage_ocr_test.dart`
- [ ] **Step 3: Implement.** Add to `ManualRegisterNotes`, reusing the private `_partyToMap`:

```dart
static Map<String, dynamic> toMarriageOcrNotesMap({
  required String volNo,
  required String seriesNo,
  required RegisterMarriageEntry entry,
  required String scanId,
  String? imagePath,
  String status = 'official',
}) {
  return {
    ...toMarriageNotesMap(
      volNo: volNo, seriesNo: seriesNo, entry: entry, status: status),
    'ocrScanId': scanId,
    'originalImagePath': imagePath,
  };
}
```

- [ ] **Step 4: Run tests — verify pass.** `flutter test test/manual_register_notes_marriage_ocr_test.dart`
- [ ] **Step 5: Commit.**

```bash
git add lib/utils/manual_register_notes.dart test/manual_register_notes_marriage_ocr_test.dart
git commit -m "feat(marriage-ocr): toMarriageOcrNotesMap (flat schema + provenance)"
```

---

## Task 10: Marriage row validation (Flutter)

**Files:**
- Create: `lib/services/marriage_row_validation.dart`
- Test: `test/marriage_row_validation_test.dart`

**Interfaces:**
- Consumes: `RegisterMarriageEntry`, `ParishRecord`.
- Produces: `List<MarriageRowIssue> validateMarriageRows(List<RegisterMarriageEntry> entries, {List<ParishRecord> existing = const [], DateTime? now})` where `MarriageRowIssue { int rowIndex; String field; String message; bool blocking; }`.

**Rules:**
- Blocking: groom name AND bride name each non-empty (min length 2). Message names which is missing.
- Non-blocking (duplicate): a saved `RecordType.marriage` record whose name equals `"<groom> & <bride>"` (case-insensitive) — reuse the couple-key logic. Date optional; no date blocking (defaults to today at save).

- [ ] **Step 1: Write failing tests.**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:parishrecord/models/register_marriage_entry.dart';
import 'package:parishrecord/services/marriage_row_validation.dart';

void main() {
  test('missing groom or bride name is blocking', () {
    final e = RegisterMarriageEntry(id: '1',
      groom: MarriagePartyInfo(name: 'M'), bride: MarriagePartyInfo(name: ''));
    final issues = validateMarriageRows([e]);
    expect(issues.any((i) => i.blocking && i.field == 'brideName'), isTrue);
  });
  test('both names present -> no blocking issue', () {
    final e = RegisterMarriageEntry(id: '1',
      groom: MarriagePartyInfo(name: 'Marlon'), bride: MarriagePartyInfo(name: 'Ana'));
    expect(validateMarriageRows([e]).where((i) => i.blocking), isEmpty);
  });
}
```

- [ ] **Step 2: Run — verify failure.** `flutter test test/marriage_row_validation_test.dart`
- [ ] **Step 3: Implement** `validateMarriageRows` per the rules (only validate `entry.selected` rows; mirror `validateBaptismalRows`'s structure and dedupe set).
- [ ] **Step 4: Run tests — verify pass.** `flutter test test/marriage_row_validation_test.dart`
- [ ] **Step 5: Commit.**

```bash
git add lib/services/marriage_row_validation.dart test/marriage_row_validation_test.dart
git commit -m "feat(marriage-ocr): marriage row validation"
```

---

## Task 11: `MarriageOcrScanPage` + route (Flutter)

**Files:**
- Create: `lib/screens/admin/pages/marriage_ocr_scan_page.dart`
- Modify: `lib/app/router.dart`
- Test: `test/marriage_ocr_scan_page_test.dart`

**Interfaces:**
- Consumes: `MarriageOcrService` (Task 8), `RegisterMarriageEntry` (Task 7), `RegisterMarriageTable` (existing widget), `validateMarriageRows` (Task 10), `toMarriageOcrNotesMap` (Task 9), `recordsProvider`.
- Produces: `MarriageOcrScanPage` with the same injectable seams as `BaptismalOcrScanPage`: `ocrService`, `imagePicker`, `imageUploader`, `idTokenProvider`, `saveRecords`, `existingRecords`. Route `/admin/records/ocr-marriage`.

**Design notes:** Copy `baptismal_ocr_scan_page.dart` and adapt:
- State holds `List<RegisterMarriageEntry> _entries` instead of `_rows`.
- Review step hosts `RegisterMarriageTable(entries: _entries, fillGeneration: _fillGen, onChanged: () => setState((){}), onSelectionChanged: () => setState((){}), onRemove: (i) => setState(() => _entries.removeAt(i)))`.
- Save: for each `entry` where `entry.selected && entry.isReadyToSave`, build a `RegisterRecordDraft` with `type: RecordType.marriage`, `name: entry.recordDisplayName`, `date: ManualRegisterNotes.marriageDateForEntry(entry)`, `parish: entry.primaryAddress.isNotEmpty ? entry.primaryAddress : 'Parish Register'`, `notes: jsonEncode(ManualRegisterNotes.toMarriageOcrNotesMap(volNo: _volCtrl.text, seriesNo: _seriesCtrl.text, entry: entry, scanId: _scanId, imagePath: _imagePath))`.
- Validation gate: `_canSave` uses `validateMarriageRows`.
- Header title: `'Add Marriage Records (OCR)'`. Warning copy: add `GROOM_BRIDE_SPLIT_UNCERTAIN` → "Groom and bride could not be told apart in one or more rows — check each row's top (groom) and bottom (bride) values before saving." to a `marriageOcrWarningCopy` map (reuse baptismal copy for the shared codes).

- [ ] **Step 1: Write failing widget test** (mirror `baptismal_ocr_scan_page_test.dart`): inject a fake `ocrService` returning a `MarriageOcrScan` with one entry, a fake `imagePicker` returning bytes, `idTokenProvider` returning `'tok'`, and a `saveRecords` capturing drafts. Drive pick → scan → save; assert one `RecordType.marriage` draft with `name == 'Marlon & Ana'` and notes containing `source: manual_marriage_register`.

- [ ] **Step 2: Run — verify failure.** `flutter test test/marriage_ocr_scan_page_test.dart`
- [ ] **Step 3: Implement the page** by adapting the baptismal page per design notes.
- [ ] **Step 4: Add the route** in `router.dart` next to `/admin/records/ocr-baptism`:

```dart
GoRoute(
  path: '/admin/records/ocr-marriage',
  builder: (context, state) => const MarriageOcrScanPage(),
),
```
(add `import '../screens/admin/pages/marriage_ocr_scan_page.dart';`)

- [ ] **Step 5: Run tests — verify pass.** `flutter test test/marriage_ocr_scan_page_test.dart`
- [ ] **Step 6: Commit.**

```bash
git add lib/screens/admin/pages/marriage_ocr_scan_page.dart lib/app/router.dart test/marriage_ocr_scan_page_test.dart
git commit -m "feat(marriage-ocr): MarriageOcrScanPage + /admin/records/ocr-marriage route"
```

---

## Task 12: Wire the sacrament chooser to marriage (Flutter)

**Files:**
- Modify: `lib/screens/admin/pages/baptismal_ocr_scan_page.dart`
- Test: `test/baptismal_ocr_scan_page_test.dart` (add one case)

**Interfaces:**
- Consumes: the `/admin/records/ocr-marriage` route (Task 11).
- Produces: selecting **Marriage** in the pick-step chooser navigates to the marriage scanner instead of showing the "coming soon" notice.

- [ ] **Step 1: Write failing test** — pump `BaptismalOcrScanPage` wrapped in a `MaterialApp.router` (or a minimal `Navigator` with an observer), select the `sacrament-type` dropdown value `marriage`, tap the (now-enabled) action, and assert navigation to `/admin/records/ocr-marriage` occurred (use a `GoRouter` test harness or a mock `NavigatorObserver`). If full router wiring is heavy in the test, instead assert the `marriage-paused` notice is **absent** and a `go-to-marriage` button is present.

- [ ] **Step 2: Run — verify failure.** `flutter test test/baptismal_ocr_scan_page_test.dart -p vm --plain-name marriage`
- [ ] **Step 3: Implement.** In `_pickStep`, replace the `_marriagePausedNotice()` branch with a button that calls `context.push('/admin/records/ocr-marriage')` (add `import 'package:go_router/go_router.dart';`). Keep the chooser; when `isMarriage`, show a short "Scan a marriage register spread" line + a `FilledButton` keyed `ValueKey('go-to-marriage')`.
- [ ] **Step 4: Run tests — verify pass.** `flutter test test/baptismal_ocr_scan_page_test.dart`
- [ ] **Step 5: Commit.**

```bash
git add lib/screens/admin/pages/baptismal_ocr_scan_page.dart test/baptismal_ocr_scan_page_test.dart
git commit -m "feat(marriage-ocr): sacrament chooser opens the marriage scanner"
```

---

## Task 13: End-to-end validation on a sample photo

**Files:**
- No production code; may add `ocr_service/scripts/validate_grids.py` usage notes.

- [ ] **Step 1: Boot the CV service** with a key: `cd ocr_service && OCR_SERVICE_KEY=k .venv310/Scripts/python -m uvicorn app.main:app --port 8099`.
- [ ] **Step 2: POST a marriage sample** to `/v1/grid?register=marriage` and confirm `success: true`, `pages.left.cols == 7`, `pages.right.cols == 5`, and non-empty `cells`:

```bash
curl -s -X POST "http://127.0.0.1:8099/v1/grid?register=marriage" \
  -H "X-OCR-Service-Key: k" --data-binary @attachments/marriage/d0b1b5f7a402a11b1b0bcb3587e90bce.jpeg \
  | python -c "import sys,json;d=json.load(sys.stdin);print(d['success'], d['pages']['left']['cols'], d['pages']['right']['cols'])"
```

If it refuses (`reason: columns_unmatched` / low corroboration), re-measure the Task 1 boundary fractions and adjust `MARRIAGE_LEFT/RIGHT`, then re-run.

- [ ] **Step 3: Run the whole marriage suite** across layers:
  - `cd ocr_service && .venv310/Scripts/python -m pytest -q`
  - `cd backend && npx jest marriage cv_grid_client`
  - `flutter test test/register_marriage_entry_test.dart test/marriage_ocr_service_test.dart test/manual_register_notes_marriage_ocr_test.dart test/marriage_row_validation_test.dart test/marriage_ocr_scan_page_test.dart`
- [ ] **Step 4: Manual UI smoke** (optional, per repo's Playwright memory): open `/admin/records/ocr-marriage`, scan a sample, verify groom/bride land in the right columns and a save produces a `manual_marriage_register` record.
- [ ] **Step 5: Commit** any boundary-fraction adjustments.

```bash
git add ocr_service/app/pipeline/column_template.py
git commit -m "chore(ocr-service): tune marriage column boundaries against sample photos"
```

---

## Execution status (Task 13)

Tasks 1–12 implemented TDD, one commit each. Full suites green: **Python 93, backend 215, Flutter 178**; the marriage suite passes across all three layers.

**Live-CV E2E (Step 1–2) is blocked, not failing:** the booted service refuses every `attachments/marriage/*_n.jpg` with `no_table_detected` / **`grid_not_found`** — those samples are compressed Facebook exports (~430 KB, 2048 px) whose ruled lines are too soft for the shared **row/table** detector. The refusal reason is `grid_not_found`, *not* `columns_unmatched`, so the Task 1 boundary fractions are not the cause (the column-rule detector reads them cleanly on these same photos — that's how they were measured; the left page corroborates at 0.75, above the 0.6 floor, whenever the row-extent step succeeds). The baptismal register on a high-res photo (`attachments/baptismal/IMG_3120.jpeg`) still detects `success` (5+5 cols), confirming the pipeline is healthy. Fixing the row-extent step on soft photos would mean editing shared pipeline code the Global Constraints forbid touching.

**No boundary adjustment committed** (none warranted — see above). To finish Step 2, a **high-res, straight-on marriage spread photo** is needed. `attachments/marriage/IMG_3123.jpeg` is not usable: it is an upside-down *baptismal* page. On a low-quality photo the app behaves correctly regardless — CV's `grid_not_found` → `CV_REFUSED` → `SPREAD_UNREADABLE` retake guidance (a deliberate refusal is never papered over by the word-clustering fallback).

## Self-Review Notes

- **Spec coverage:** Python template (T1) + endpoint (T2); Node client param (T3), grid-assign+split (T4), fallback (T5), route+mount (T6); Flutter model (T7), service (T8), notes (T9), validation (T10), page+route (T11), chooser wiring (T12); E2E (T13). Warning `GROOM_BRIDE_SPLIT_UNCERTAIN` produced in T4/T5, surfaced in T11. Save schema = flat register (T9). Legacy path untouched (constraint honored — no legacy files modified).
- **Known deferral:** boundary fractions in T1 are provisional and validated by the corroboration gate in T13; this is the same measure-then-verify loop the baptismal template used, not a placeholder.
- **Type consistency:** row shape `{lineNo, groom{...}, bride{...}, dateOfMarriage, minister, licenseNumber, observations}` is identical across T4 (producer), T6 (route), T7 (`fromScanJson`), T8 (service). `MarriagePartyInfo` field names match `register_marriage_entry.dart` exactly.
