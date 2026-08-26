# Baptismal CV Ruled-Grid Row Detection — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Detect the register's true rows from its printed ruled lines using a slim Python OpenCV service, and have the Node/OCR.space backend run OCR on the rectified page images the service returns, assigning words into the detected grid cells — with graceful fallback to today's word-clustering.

**Architecture:** Reuse the proven, tested OpenCV grid detector from `feature/baptismal-python-ocr` (`ocr_service/app/pipeline/*`) unchanged, wrapped in a new slim FastAPI `/v1/grid` endpoint that returns **rectified page images + grid geometry** (no PaddleOCR). Node calls it, runs OCR.space (Engine 2, `detectOrientation` off) on the returned rectified images so words and grid cells share one coordinate frame, assigns words to cells, and falls back to `baptismal_register_layout.js` when the CV service is unavailable.

**Tech Stack:** Python 3.10 + FastAPI + OpenCV (`opencv-python-headless`) + numpy + pytest (CV service); Node/Express + Jest + `sharp` (backend). No PaddleOCR.

**Spec:** `docs/superpowers/specs/2026-08-26-baptismal-cv-grid-detection-design.md`

## Global Constraints

- **Branch:** all work lands on `feature/baptismal-ocr-record`. Never commit to `main`, `master`, `development`, or `ocr`.
- **Scope:** baptismal only. Do not revive PaddleOCR, the Python recognizer, or the Python parser.
- **Reuse, don't rewrite:** `ocr_service/app/pipeline/{orientation,inversion,spread,rectify,column_template,table}.py` are copied verbatim from `feature/baptismal-python-ocr`. Tune `table.py`'s documented parameters only if Task 2 validation requires it; never rewrite the algorithms.
- **Coordinate rule:** OCR.space runs on the **rectified page images the CV service returns**, with `detectOrientation=false`. Grid cells and OCR words are therefore in the same pixel frame.
- **Never log cell values or recognized text** (records of minors). Log counts, codes, timings only — both services.
- **CV-service auth:** header `X-OCR-Service-Key`, value from `OCR_SERVICE_KEY`; base URL `OCR_SERVICE_URL`; timeout `OCR_TIMEOUT_MS`. All already present in `backend/.env`.
- **Fallback:** any CV failure (unreachable, timeout, non-2xx, refusal) → today's single-OCR.space + `baptismal_register_layout.js` path, with a `CV_UNAVAILABLE` warning appended. Never hard-fail because CV is down.
- **Backend envelope unchanged:** `POST /api/ocr/baptismal/scan` still returns `{ success, data:{ scanId, rows, rotation, warnings } }`.
- **`docs/` is gitignored** but plan/spec files are tracked — use `git add -f` for anything under `docs/`.
- **Node style:** `flutter` is not involved here; run `cd backend && npx jest <file>` per task. **Python:** `cd ocr_service && python -m pytest <file>`.

## Grid → field key mapping (single source of truth)

The CV grid names columns in snake_case; the backend uses camelCase. Task 6 defines this map; every later reference uses it verbatim:

```
no                    -> lineNo         (row number; not a field, drives lineNo)
child_name            -> nameOfChild
place_and_birth_date  -> placeAndBirthDate
parents               -> parents
residents_of          -> residentsOf
baptism_date          -> dateOfBaptism
minister              -> minister
sponsors              -> sponsors
l_or_ill              -> (ignored)
observations          -> (ignored)
```

## File Structure

**Python (`ocr_service/`, new on this branch):**

| File | Responsibility |
|------|----------------|
| `app/pipeline/{orientation,inversion,spread,rectify,column_template,table}.py` | Reused verbatim. CV geometry. |
| `app/{__init__,config,errors,security}.py` | Reused verbatim. Settings, error codes, auth/upload validation. |
| `app/schemas.py` | **Rewritten** — grid-response models (no entries/fields). |
| `app/main.py` | **Rewritten** — `GET /health`, `POST /v1/grid` (geometry only, no OCR). |
| `requirements.txt` | **New slim** — no paddle. |
| `.env.example`, `README.md` | Reused/updated run notes. |
| `tests/…` | Reused pipeline tests + rewritten endpoint test. |

**Node (`backend/src/`):**

| File | Responsibility |
|------|----------------|
| `services/cv_grid_client.js` | HTTP client for `/v1/grid`; typed result or coded failure. |
| `services/baptismal_grid_assign.js` | Pure: assign OCR words to grid cells → rows/fields. |
| `services/ocrspace_service.js` | **Modify** — optional `detectOrientation` flag. |
| `routes/baptismal_ocr_firestore.js` | **Modify** — CV orchestration + fallback. |

---

### Task 1: Vendor the CV pipeline and get its unit tests green

**Files:**
- Create (copy verbatim from `feature/baptismal-python-ocr`): the pipeline + support modules and their tests (commands below).
- Create: `ocr_service/requirements.txt` (slim).

**Interfaces:**
- Produces (for later tasks): `correct_orientation(bgr) -> OrientationResult{image, rotation_applied:int, deskew_deg:float}`; `correct_spread_inversion(spread_bgr) -> InversionResult{image}`; `split_spread(bgr) -> SpreadPages{left, right}`; `rectify_page(page_bgr) -> RectifyResult{image}`; `detect_spread_grids(left_bgr, right_bgr, spread_template) -> SpreadGrids{left, right}` where each is `GridResult{rows:int, cols:int, cells:list[CellRect], column_keys:tuple[str,...]|None}` and `CellRect{row:int, col:int, x:int, y:int, w:int, h:int}`; `BAPTISMAL_REGISTER` (from `column_template`).

- [ ] **Step 1: Copy the reused source and tests from the Python branch**

```bash
cd /e/parishrecord
git checkout feature/baptismal-python-ocr -- \
  ocr_service/app/__init__.py \
  ocr_service/app/config.py \
  ocr_service/app/errors.py \
  ocr_service/app/security.py \
  ocr_service/app/pipeline/__init__.py \
  ocr_service/app/pipeline/orientation.py \
  ocr_service/app/pipeline/inversion.py \
  ocr_service/app/pipeline/spread.py \
  ocr_service/app/pipeline/rectify.py \
  ocr_service/app/pipeline/column_template.py \
  ocr_service/app/pipeline/table.py \
  ocr_service/tests/__init__.py \
  ocr_service/tests/support/__init__.py \
  ocr_service/tests/support/synthetic.py \
  ocr_service/tests/test_table.py \
  ocr_service/tests/test_orientation.py \
  ocr_service/tests/test_rectify.py \
  ocr_service/tests/test_spread.py \
  ocr_service/tests/test_inversion.py \
  ocr_service/tests/test_column_template.py \
  ocr_service/tests/test_spread_gate.py \
  ocr_service/tests/test_security.py \
  ocr_service/.env.example
```

If any path does not exist on that branch, list `git ls-tree -r --name-only feature/baptismal-python-ocr | grep ocr_service` and adjust — do not invent files.

- [ ] **Step 2: Write the slim requirements**

Create `ocr_service/requirements.txt`:

```
fastapi==0.115.6
uvicorn[standard]==0.34.0
opencv-python-headless==4.10.0.84
numpy==2.1.3
pydantic==2.10.4
pydantic-settings==2.7.0
python-multipart==0.0.20
pytest==8.3.4
httpx==0.28.1
```

(`httpx` is for FastAPI's `TestClient`. Pin to whatever the venv already resolved if these exact versions are unavailable — the on-disk `ocr_service/.venv` already has compatible cv2/numpy/fastapi/uvicorn.)

- [ ] **Step 3: Install and run the ported pipeline tests**

```bash
cd /e/parishrecord/ocr_service
python -m pip install -r requirements.txt
python -m pytest tests/ -q
```

Expected: PASS. These tests were green on the source branch and depend only on the reused modules. If a test imports a dropped module (`recognize`, `parsers`, `cells`, `main`), it was copied by mistake — remove that test file (only the modules listed in Step 1 are in scope).

- [ ] **Step 4: Commit**

```bash
cd /e/parishrecord
git add ocr_service/app ocr_service/tests ocr_service/requirements.txt ocr_service/.env.example
git commit -m "feat(ocr): vendor reusable OpenCV register-grid pipeline (no PaddleOCR)"
```

---

### Task 2: Feasibility gate — validate grid counts on the real pages

Proves the reused detector yields true row counts BEFORE building the integration. This is the highest-risk item (a row-recovery tweak once over-counted IMG_3120 on the source branch).

**Files:**
- Create: `ocr_service/scripts/validate_grids.py`

**Interfaces:**
- Consumes: Task 1 pipeline functions.

- [ ] **Step 1: Establish ground truth**

Hand-count the data rows in each sample by reading the NO. column: `attachments/IMG_3120.jpeg` = **24**; `IMG_3121.jpeg` and `IMG_3122.jpeg` = count them now and write the numbers here before running the script. (3121 is photographed upside-down and denser — expect ≈33–34.)

- [ ] **Step 2: Write the validation script**

Create `ocr_service/scripts/validate_grids.py`:

```python
"""Reports detected row/col counts per page for the real sample spreads.
Structure only -- never prints cell contents (records of minors)."""
import sys, pathlib
import cv2
sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent.parent))
from app.pipeline.orientation import correct_orientation
from app.pipeline.inversion import correct_spread_inversion
from app.pipeline.spread import split_spread
from app.pipeline.rectify import rectify_page
from app.pipeline.table import detect_spread_grids
from app.pipeline.column_template import BAPTISMAL_REGISTER

def run(path):
    bgr = cv2.imread(path)
    oriented = correct_orientation(bgr)
    spread = correct_spread_inversion(oriented.image).image
    pages = split_spread(spread)
    left = rectify_page(pages.left).image
    right = rectify_page(pages.right).image
    grids = detect_spread_grids(left, right, spread_template=BAPTISMAL_REGISTER)
    # A GridResult with N horizontal rules bounds N-1 data rows.
    print(f"{path}: rotation={oriented.rotation_applied} deskew={oriented.deskew_deg:.1f} "
          f"left rows={max(0, grids.left.rows-1)} cols={grids.left.cols} | "
          f"right rows={max(0, grids.right.rows-1)} cols={grids.right.cols}")

if __name__ == "__main__":
    for p in sys.argv[1:]:
        try:
            run(p)
        except Exception as e:  # noqa: BLE001
            print(f"{p}: FAILED {type(e).__name__}: {e}")
```

- [ ] **Step 3: Run against all three samples**

```bash
cd /e/parishrecord/ocr_service
python scripts/validate_grids.py ../attachments/IMG_3120.jpeg ../attachments/IMG_3121.jpeg ../attachments/IMG_3122.jpeg
```

Expected: left/right `rows` match the hand counts from Step 1 (IMG_3120 → 24). Record the actual output.

- [ ] **Step 4: Gate decision**

- If counts match (±0): proceed to Task 3.
- If counts are off: tune ONLY `table.py`'s documented constants (`PEAK_FLOOR_FRACTION`, `PEAK_REFERENCE_PERCENTILE`, `_line_positions` `kernel_divisor`/`gap_divisor`, `SPREAD_PITCH_TOLERANCE`), re-running `python -m pytest tests/` after each change to keep the unit tests green, until real counts match. **Do not rewrite the algorithm.** If no parameter set satisfies both the unit tests and the real pages, STOP and report — the detector needs deeper work and the plan's assumption is wrong.

- [ ] **Step 5: Commit**

```bash
cd /e/parishrecord
git add ocr_service/scripts/validate_grids.py ocr_service/app/pipeline/table.py
git commit -m "test(ocr): validate register-grid row counts on real pages

Findings (rows detected vs hand truth): IMG_3120 <n>/24, IMG_3121 <n>/<gt>, IMG_3122 <n>/<gt>."
```

---

### Task 3: Slim `/v1/grid` FastAPI endpoint

**Files:**
- Create (rewrite): `ocr_service/app/schemas.py`, `ocr_service/app/main.py`
- Create: `ocr_service/tests/test_grid_endpoint.py`

**Interfaces:**
- Consumes: Task 1 pipeline; `validate_upload`, `require_service_key`, `get_settings`, `OcrError`.
- Produces (for Node Task 5): `POST /v1/grid` returning
  ```json
  { "success": true, "rotation_applied": 90, "deskew_deg": 1.2,
    "pages": { "left": { "image_b64": "...", "width": 1400, "height": 1000, "rows": 25, "cols": 5,
                         "cells": [{"key":"child_name","row":0,"x":10,"y":40,"w":200,"h":45}, ...] },
               "right": { ... } },
    "warnings": [] }
  ```
  `rows` here is the DATA-row count (`grid.rows - 1`). `key` is `column_keys[cell.col]`. Errors use `OcrError` → `{success:false, code, message}` with its `http_status`.

- [ ] **Step 1: Write the failing endpoint test**

Create `ocr_service/tests/test_grid_endpoint.py`:

```python
import base64
import cv2
import numpy as np
from fastapi.testclient import TestClient
from app.main import app
from app.config import get_settings
from tests.support.synthetic import make_spread  # reused helper: builds a ruled register spread

client = TestClient(app)

def _png_bytes(bgr):
    ok, buf = cv2.imencode(".png", bgr)
    assert ok
    return buf.tobytes()

def _key():
    return get_settings().service_key or ""

def test_health():
    assert client.get("/health").json() == {"status": "ok"}

def test_grid_returns_geometry_for_a_synthetic_spread(monkeypatch):
    monkeypatch.setenv("OCR_SERVICE_KEY", "k")
    get_settings.cache_clear()
    spread = make_spread(rows=6)  # support helper; 6 data rows
    res = client.post("/v1/grid", content=_png_bytes(spread), headers={"X-OCR-Service-Key": "k"})
    assert res.status_code == 200
    body = res.json()
    assert body["success"] is True
    for side in ("left", "right"):
        page = body["pages"][side]
        assert page["rows"] >= 5  # ~6 data rows detected
        assert page["cols"] >= 2
        assert page["cells"]
        assert all({"key", "row", "x", "y", "w", "h"} <= set(c) for c in page["cells"])
        assert base64.b64decode(page["image_b64"])  # decodable image
    get_settings.cache_clear()

def test_grid_rejects_missing_key(monkeypatch):
    monkeypatch.setenv("OCR_SERVICE_KEY", "k")
    get_settings.cache_clear()
    res = client.post("/v1/grid", content=b"\xff\xd8\xffdata")
    assert res.status_code == 401
    assert res.json()["code"] == "unauthorized"
    get_settings.cache_clear()

def test_grid_rejects_corrupt_image(monkeypatch):
    monkeypatch.setenv("OCR_SERVICE_KEY", "k")
    get_settings.cache_clear()
    res = client.post("/v1/grid", content=b"\xff\xd8\xffnotreallyanimage",
                      headers={"X-OCR-Service-Key": "k"})
    assert res.status_code == 400
    assert res.json()["code"] == "corrupt_image"
    get_settings.cache_clear()
```

If `make_spread` has a different name/signature, open `ocr_service/tests/support/synthetic.py` and use the real synthetic-spread builder it provides (it is what the reused `test_table.py` already uses).

- [ ] **Step 2: Run to verify it fails**

```bash
cd /e/parishrecord/ocr_service && python -m pytest tests/test_grid_endpoint.py -q
```
Expected: FAIL — `/v1/grid` not defined yet.

- [ ] **Step 3: Write the schemas**

Create `ocr_service/app/schemas.py`:

```python
from pydantic import BaseModel


class CellModel(BaseModel):
    key: str
    row: int
    x: int
    y: int
    w: int
    h: int


class PageGridModel(BaseModel):
    image_b64: str
    width: int
    height: int
    rows: int
    cols: int
    cells: list[CellModel]


class GridResponse(BaseModel):
    success: bool
    rotation_applied: int
    deskew_deg: float
    pages: dict[str, PageGridModel]
    warnings: list[str]
```

- [ ] **Step 4: Write the slim `main.py`**

Create `ocr_service/app/main.py`:

```python
import base64
import logging

import cv2
import numpy as np
from fastapi import FastAPI, Header, Request
from fastapi.responses import JSONResponse

from .config import get_settings
from .errors import OcrError
from .pipeline.column_template import BAPTISMAL_REGISTER
from .pipeline.inversion import correct_spread_inversion
from .pipeline.orientation import correct_orientation
from .pipeline.rectify import rectify_page
from .pipeline.spread import split_spread
from .pipeline.table import detect_spread_grids
from .security import require_service_key, validate_upload

logging.basicConfig(level=logging.INFO)
log = logging.getLogger("ocr_service")

app = FastAPI(title="Parish Register Grid", version="2.0.0")


@app.exception_handler(OcrError)
async def _ocr_error_handler(_: Request, exc: OcrError) -> JSONResponse:
    log.warning("request failed: %s", exc.code)  # code only, never cell text
    return JSONResponse(
        status_code=exc.http_status,
        content={"success": False, "code": exc.code, "message": exc.message},
    )


@app.get("/health")
async def health() -> dict:
    return {"status": "ok"}


def _decode(data: bytes) -> np.ndarray:
    image = cv2.imdecode(np.frombuffer(data, np.uint8), cv2.IMREAD_COLOR)
    if image is None:
        raise OcrError("corrupt_image", "The image could not be decoded.")
    return image


def _page_payload(page_bgr: np.ndarray, grid) -> dict:
    ok, buf = cv2.imencode(".jpg", page_bgr, [cv2.IMWRITE_JPEG_QUALITY, 85])
    if not ok:
        raise OcrError("corrupt_image", "Rectified page could not be encoded.")
    keys = grid.column_keys
    cells = []
    for c in grid.cells:
        key = keys[c.col] if keys and 0 <= c.col < len(keys) else str(c.col)
        cells.append({"key": key, "row": c.row, "x": c.x, "y": c.y, "w": c.w, "h": c.h})
    h, w = page_bgr.shape[:2]
    return {
        "image_b64": base64.b64encode(buf.tobytes()).decode("ascii"),
        "width": int(w), "height": int(h),
        # A grid with N horizontal rules bounds N-1 data rows.
        "rows": max(0, grid.rows - 1), "cols": grid.cols, "cells": cells,
    }


@app.post("/v1/grid")
async def detect_grid_endpoint(
    request: Request,
    x_ocr_service_key: str | None = Header(default=None),
) -> dict:
    settings = get_settings()
    require_service_key(x_ocr_service_key, settings)
    data = await request.body()
    validate_upload(data, settings)

    oriented = correct_orientation(_decode(data))
    spread = correct_spread_inversion(oriented.image).image
    pages = split_spread(spread)
    left = rectify_page(pages.left).image
    right = rectify_page(pages.right).image
    grids = detect_spread_grids(left, right, spread_template=BAPTISMAL_REGISTER)

    return {
        "success": True,
        "rotation_applied": oriented.rotation_applied,
        "deskew_deg": round(oriented.deskew_deg, 2),
        "pages": {
            "left": _page_payload(left, grids.left),
            "right": _page_payload(right, grids.right),
        },
        "warnings": [],
    }
```

- [ ] **Step 5: Run tests**

```bash
cd /e/parishrecord/ocr_service && python -m pytest tests/test_grid_endpoint.py -q
```
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
cd /e/parishrecord
git add ocr_service/app/main.py ocr_service/app/schemas.py ocr_service/tests/test_grid_endpoint.py
git commit -m "feat(ocr): slim /v1/grid endpoint returning rectified pages + grid geometry"
```

---

### Task 4: OCR.space `detectOrientation` toggle

**Files:**
- Modify: `backend/src/services/ocrspace_service.js`
- Test: `backend/src/services/ocrspace_service.test.js`

**Interfaces:**
- Produces: `callOcrSpace(imageBase64, { apiKey, fetchImpl, engine, detectOrientation })` — `detectOrientation` optional, **defaults `true`** (unchanged behavior); when `false`, sends `detectOrientation=false`.

- [ ] **Step 1: Write the failing test**

Append to `backend/src/services/ocrspace_service.test.js`:

```js
  test('lets the caller turn off detectOrientation (default stays true)', async () => {
    const bodies = [];
    const fakeFetch = async (url, opts) => {
      bodies.push(opts.body);
      return { ok: true, json: async () => ({ ParsedResults: [{ ParsedText: 'ok' }] }) };
    };
    await callOcrSpace('X', { apiKey: 'K', fetchImpl: fakeFetch, detectOrientation: false });
    await callOcrSpace('X', { apiKey: 'K', fetchImpl: fakeFetch });
    expect(bodies[0]).toContain('detectOrientation=false');
    expect(bodies[1]).toContain('detectOrientation=true');
  });
```

- [ ] **Step 2: Run to verify it fails**

```bash
cd /e/parishrecord/backend && npx jest src/services/ocrspace_service.test.js -t detectOrientation
```
Expected: FAIL.

- [ ] **Step 3: Implement**

In `backend/src/services/ocrspace_service.js`, change the signature and the `detectOrientation` line:

```js
async function callOcrSpace(imageBase64, { apiKey, fetchImpl = fetch, engine = '2', detectOrientation = true } = {}) {
```
```js
  params.append('detectOrientation', detectOrientation ? 'true' : 'false');
```

- [ ] **Step 4: Run tests**

```bash
cd /e/parishrecord/backend && npx jest src/services/ocrspace_service.test.js
```
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
cd /e/parishrecord
git add backend/src/services/ocrspace_service.js backend/src/services/ocrspace_service.test.js
git commit -m "feat(ocr): allow disabling OCR.space detectOrientation"
```

---

### Task 5: Node CV-grid client

**Files:**
- Create: `backend/src/services/cv_grid_client.js`
- Test: `backend/src/services/cv_grid_client.test.js`

**Interfaces:**
- Consumes: `/v1/grid` (Task 3); env `OCR_SERVICE_URL`, `OCR_SERVICE_KEY`, `OCR_TIMEOUT_MS`.
- Produces: `fetchGrid(imageBuffer, { env, fetchImpl }) -> Promise<{ rotationApplied, deskewDeg, warnings, pages: { left, right } }>` where each page is `{ imageBuffer: Buffer, width, height, rows, cols, cells: [{key,row,x,y,w,h}] }`. Throws `CvGridError` with `.code ∈ CV_DISABLED | CV_UNREACHABLE | CV_REFUSED | CV_BAD_RESPONSE`. `CV_DISABLED` when `OCR_SERVICE_URL` is unset (feature simply off → caller uses fallback).

- [ ] **Step 1: Write the failing test**

Create `backend/src/services/cv_grid_client.test.js`:

```js
const { fetchGrid, CvGridError } = require('./cv_grid_client');

const env = { OCR_SERVICE_URL: 'http://cv.local', OCR_SERVICE_KEY: 'k', OCR_TIMEOUT_MS: '5000' };
const okBody = {
  success: true, rotation_applied: 90, deskew_deg: 1.1, warnings: [],
  pages: {
    left: { image_b64: Buffer.from('LEFTIMG').toString('base64'), width: 100, height: 200, rows: 6, cols: 5,
            cells: [{ key: 'child_name', row: 0, x: 1, y: 2, w: 3, h: 4 }] },
    right: { image_b64: Buffer.from('RIGHTIMG').toString('base64'), width: 100, height: 200, rows: 6, cols: 5, cells: [] },
  },
};

test('parses a successful grid response into buffers + cells', async () => {
  const fetchImpl = async () => ({ ok: true, status: 200, json: async () => okBody });
  const grid = await fetchGrid(Buffer.from('img'), { env, fetchImpl });
  expect(grid.rotationApplied).toBe(90);
  expect(grid.pages.left.imageBuffer.toString()).toBe('LEFTIMG');
  expect(grid.pages.left.cells[0].key).toBe('child_name');
  expect(grid.pages.right.rows).toBe(6);
});

test('CV_DISABLED when no service URL is configured', async () => {
  await expect(fetchGrid(Buffer.from('img'), { env: {}, fetchImpl: async () => ({}) }))
    .rejects.toMatchObject({ code: 'CV_DISABLED' });
});

test('CV_UNREACHABLE on a network throw', async () => {
  const fetchImpl = async () => { throw new Error('ECONNREFUSED'); };
  await expect(fetchGrid(Buffer.from('img'), { env, fetchImpl }))
    .rejects.toMatchObject({ code: 'CV_UNREACHABLE' });
});

test('CV_REFUSED on a 4xx OcrError body', async () => {
  const fetchImpl = async () => ({ ok: false, status: 422, json: async () => ({ success: false, code: 'no_table_detected' }) });
  await expect(fetchGrid(Buffer.from('img'), { env, fetchImpl }))
    .rejects.toMatchObject({ code: 'CV_REFUSED' });
});

test('CV_BAD_RESPONSE on malformed success body', async () => {
  const fetchImpl = async () => ({ ok: true, status: 200, json: async () => ({ success: true }) });
  await expect(fetchGrid(Buffer.from('img'), { env, fetchImpl }))
    .rejects.toMatchObject({ code: 'CV_BAD_RESPONSE' });
});
```

- [ ] **Step 2: Run to verify it fails**

```bash
cd /e/parishrecord/backend && npx jest src/services/cv_grid_client.test.js
```
Expected: FAIL — module not found.

- [ ] **Step 3: Implement**

Create `backend/src/services/cv_grid_client.js`:

```js
/**
 * Client for the Python CV grid service (POST /v1/grid). The service key
 * never reaches the browser -- only the Node backend calls this. Any failure
 * is a coded CvGridError the route maps to the word-clustering fallback.
 */

class CvGridError extends Error {
  constructor(code, message) {
    super(message || code);
    this.code = code;
  }
}

function parsePage(raw) {
  if (!raw || typeof raw !== 'object') throw new CvGridError('CV_BAD_RESPONSE', 'missing page');
  const cells = Array.isArray(raw.cells) ? raw.cells : [];
  if (typeof raw.image_b64 !== 'string' || !raw.image_b64) {
    throw new CvGridError('CV_BAD_RESPONSE', 'missing page image');
  }
  return {
    imageBuffer: Buffer.from(raw.image_b64, 'base64'),
    width: Number(raw.width) || 0,
    height: Number(raw.height) || 0,
    rows: Number(raw.rows) || 0,
    cols: Number(raw.cols) || 0,
    cells: cells.map((c) => ({
      key: String(c.key), row: Number(c.row) || 0,
      x: Number(c.x) || 0, y: Number(c.y) || 0, w: Number(c.w) || 0, h: Number(c.h) || 0,
    })),
  };
}

async function fetchGrid(imageBuffer, { env = process.env, fetchImpl = fetch } = {}) {
  const baseUrl = env.OCR_SERVICE_URL;
  if (!baseUrl) throw new CvGridError('CV_DISABLED', 'OCR_SERVICE_URL not set');
  const timeoutMs = Number(env.OCR_TIMEOUT_MS) || 20000;

  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), timeoutMs);
  let res;
  try {
    res = await fetchImpl(`${baseUrl.replace(/\/$/, '')}/v1/grid`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/octet-stream',
        'X-OCR-Service-Key': env.OCR_SERVICE_KEY || '',
      },
      body: imageBuffer,
      signal: controller.signal,
    });
  } catch (e) {
    throw new CvGridError('CV_UNREACHABLE', e && e.message);
  } finally {
    clearTimeout(timer);
  }

  let body;
  try { body = await res.json(); } catch (e) { throw new CvGridError('CV_BAD_RESPONSE', 'non-JSON'); }

  if (!res.ok || !body || body.success !== true) {
    // A structured OcrError (4xx/5xx) means the service ran but refused/failed
    // this image -- treat as "CV can't help here", i.e. fall back.
    throw new CvGridError('CV_REFUSED', body && body.code);
  }
  if (!body.pages || !body.pages.left || !body.pages.right) {
    throw new CvGridError('CV_BAD_RESPONSE', 'missing pages');
  }
  return {
    rotationApplied: Number(body.rotation_applied) || 0,
    deskewDeg: Number(body.deskew_deg) || 0,
    warnings: Array.isArray(body.warnings) ? body.warnings.map(String) : [],
    pages: { left: parsePage(body.pages.left), right: parsePage(body.pages.right) },
  };
}

module.exports = { fetchGrid, CvGridError };
```

- [ ] **Step 4: Run tests**

```bash
cd /e/parishrecord/backend && npx jest src/services/cv_grid_client.test.js
```
Expected: PASS — 5 tests.

- [ ] **Step 5: Commit**

```bash
cd /e/parishrecord
git add backend/src/services/cv_grid_client.js backend/src/services/cv_grid_client.test.js
git commit -m "feat(ocr): add CV grid-service client with typed failures"
```

---

### Task 6: Assign OCR words to grid cells → rows

**Files:**
- Create: `backend/src/services/baptismal_grid_assign.js`
- Test: `backend/src/services/baptismal_grid_assign.test.js`

**Interfaces:**
- Consumes: normalized OCR words `{ text, vertices:[TL,TR,BR,BL], confidence }` (from `recognizeWords`); grid pages from Task 5; `applyFillDown` from `baptismal_register_layout.js` (already exported).
- Produces:
  - `GRID_KEY_TO_FIELD` — the mapping table above.
  - `assignPage(page, words) -> Map<number, Record<fieldKey,{value,confidence}>>` keyed by row index (only mapped, captured keys; `no`→lineNo captured separately).
  - `gridToRows(leftPage, leftWords, rightPage, rightWords) -> { rows, warnings }` where `rows[i] = { lineNo, fields: { <baptismalFieldKey>: { value, confidence, inherited } } }` — the exact shape `baptismal_ocr_firestore.js` already serializes.

- [ ] **Step 1: Write the failing test**

Create `backend/src/services/baptismal_grid_assign.test.js`:

```js
const { gridToRows, GRID_KEY_TO_FIELD } = require('./baptismal_grid_assign');

// One word whose box-centre lands inside a given cell rect.
const wordAt = (text, cx, cy) => ({
  text,
  vertices: [
    { x: cx - 5, y: cy - 5 }, { x: cx + 5, y: cy - 5 },
    { x: cx + 5, y: cy + 5 }, { x: cx - 5, y: cy + 5 },
  ],
  confidence: 1,
});
const cell = (key, row, x, y, w, h) => ({ key, row, x, y, w, h });

test('maps grid snake_case keys to backend field keys', () => {
  expect(GRID_KEY_TO_FIELD.child_name).toBe('nameOfChild');
  expect(GRID_KEY_TO_FIELD.baptism_date).toBe('dateOfBaptism');
  expect(GRID_KEY_TO_FIELD.l_or_ill).toBeUndefined();
});

test('places words into the correct cell and row, joins left+right', () => {
  const leftPage = { cells: [
    cell('no', 0, 0, 0, 40, 40), cell('child_name', 0, 40, 0, 200, 40),
    cell('no', 1, 0, 40, 40, 40), cell('child_name', 1, 40, 40, 200, 40),
  ] };
  const rightPage = { cells: [
    cell('minister', 0, 0, 0, 200, 40), cell('baptism_date', 0, 200, 0, 120, 40),
    cell('minister', 1, 0, 40, 200, 40), cell('baptism_date', 1, 200, 40, 120, 40),
  ] };
  const leftWords = [wordAt('1', 20, 20), wordAt('JUAN', 140, 20), wordAt('2', 20, 60), wordAt('MARIA', 140, 60)];
  const rightWords = [wordAt('FR.PADRE', 100, 20), wordAt('12MAY2016', 260, 20)];

  const { rows } = gridToRows(leftPage, leftWords, rightPage, rightWords);
  expect(rows).toHaveLength(2);
  expect(rows[0].lineNo).toBe('1');
  expect(rows[0].fields.nameOfChild.value).toBe('JUAN');
  expect(rows[0].fields.minister.value).toBe('FR.PADRE');
  expect(rows[0].fields.dateOfBaptism.value).toBe('12MAY2016');
  expect(rows[1].fields.nameOfChild.value).toBe('MARIA');
});

test('ignored columns (l_or_ill, observations) never appear as fields', () => {
  const leftPage = { cells: [cell('l_or_ill', 0, 0, 0, 40, 40)] };
  const rightPage = { cells: [cell('observations', 0, 0, 0, 200, 40)] };
  const { rows } = gridToRows(leftPage, [wordAt('L', 20, 20)], rightPage, [wordAt('note', 100, 20)]);
  expect(rows[0].fields.legitimacy).toBeUndefined();
  expect(rows[0].fields.observations).toBeUndefined();
});

test('a word outside every cell is dropped, leaving the field empty', () => {
  const leftPage = { cells: [cell('child_name', 0, 40, 0, 200, 40)] };
  const { rows } = gridToRows(leftPage, [wordAt('STRAY', 500, 500)], { cells: [] }, []);
  expect(rows[0].fields.nameOfChild.value).toBe('');
});
```

- [ ] **Step 2: Run to verify it fails**

```bash
cd /e/parishrecord/backend && npx jest src/services/baptismal_grid_assign.test.js
```
Expected: FAIL — module not found.

- [ ] **Step 3: Implement**

Create `backend/src/services/baptismal_grid_assign.js`:

```js
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
  return { cx: (Math.min(...xs) + Math.max(...xs)) / 2, cy: (Math.min(...ys) + Math.max(...ys)) / 2, word };
}

function inRect(cx, cy, c) {
  return cx >= c.x && cx < c.x + c.w && cy >= c.y && cy < c.y + c.h;
}

// Collect words per cell, then join in reading order (top line then left-to-
// right) using the same convention as the fallback pipeline: cluster by y at a
// coarse tolerance, sort each line by x.
function cellValue(words) {
  if (words.length === 0) return { value: '', confidence: 0 };
  const heights = words.map((w) => {
    const ys = w.vertices.map((v) => v.y);
    return Math.max(...ys) - Math.min(...ys);
  }).sort((a, b) => a - b);
  const tol = (heights[Math.floor(heights.length / 2)] || 20) * 0.7;
  const withC = words.map(centre);
  withC.sort((a, b) => (Math.abs(a.cy - b.cy) > tol ? a.cy - b.cy : a.cx - b.cx));
  const value = withC.map((w) => w.word.text).join(' ').replace(/\s+/g, ' ').trim();
  const confidence = withC.reduce((s, w) => s + (w.word.confidence || 0), 0) / withC.length;
  return { value, confidence };
}

/** Row index -> { fieldKey|'no': [words] }. */
function bucket(page, words) {
  const cells = (page && page.cells) || [];
  const perCell = new Map(); // `${row}:${key}` -> words[]
  const centres = words.map(centre);
  for (const { cx, cy, word } of centres) {
    const hit = cells.find((c) => inRect(cx, cy, c));
    if (!hit) continue;
    const k = `${hit.row}:${hit.key}`;
    if (!perCell.has(k)) perCell.set(k, []);
    perCell.get(k).push(word);
  }
  return { cells, perCell };
}

function rowIndices(page) {
  const rows = new Set();
  for (const c of (page && page.cells) || []) rows.add(c.row);
  return [...rows].sort((a, b) => a - b);
}

function gridToRows(leftPage, leftWords, rightPage, rightWords) {
  const left = bucket(leftPage, leftWords || []);
  const right = bucket(rightPage, rightWords || []);
  const indices = [...new Set([...rowIndices(leftPage), ...rowIndices(rightPage)])].sort((a, b) => a - b);

  const rows = indices.map((rowIdx) => {
    const fields = {};
    for (const src of [left, right]) {
      for (const [k, words] of src.perCell) {
        const [r, key] = k.split(':');
        if (Number(r) !== rowIdx) continue;
        const fieldKey = GRID_KEY_TO_FIELD[key];
        if (!fieldKey) continue; // 'no', 'l_or_ill', 'observations'
        fields[fieldKey] = { ...cellValue(words), inherited: false };
      }
    }
    // Ensure every captured field exists even when empty.
    for (const fk of Object.values(GRID_KEY_TO_FIELD)) {
      if (!fields[fk]) fields[fk] = { value: '', confidence: 0, inherited: false };
    }
    const noWords = left.perCell.get(`${rowIdx}:no`) || [];
    const lineNo = cellValue(noWords).value || String(rowIdx + 1);
    return { index: rowIdx, lineNo, fields };
  });

  const { rows: filled } = applyFillDown(rows);
  return { rows: filled, warnings: [] };
}

module.exports = { GRID_KEY_TO_FIELD, gridToRows };
```

- [ ] **Step 4: Run tests**

```bash
cd /e/parishrecord/backend && npx jest src/services/baptismal_grid_assign.test.js
```
Expected: PASS — 4 tests.

- [ ] **Step 5: Commit**

```bash
cd /e/parishrecord
git add backend/src/services/baptismal_grid_assign.js backend/src/services/baptismal_grid_assign.test.js
git commit -m "feat(ocr): assign OCR.space words into CV grid cells -> rows"
```

---

### Task 7: Wire the CV path into the route with fallback

**Files:**
- Modify: `backend/src/routes/baptismal_ocr_firestore.js`
- Test: `backend/src/routes/baptismal_ocr_firestore.test.js`

**Interfaces:**
- Consumes: `fetchGrid` (Task 5), `gridToRows` (Task 6), `recognizeWords` (existing), `preprocessForOcr` (existing), `extractBaptismalRows` (existing fallback).
- Produces: same response envelope; the CV path adds no engine-specific warning beyond `CONFIDENCE_UNAVAILABLE`; the fallback path adds `CV_UNAVAILABLE`.

- [ ] **Step 1: Write the failing tests**

The route factory `createBaptismalOcrRouter(deps)` already injects `recognize`, `extract`, `preprocess`. Add two injectable deps: `fetchGrid` and `recognizeImage` (OCR on a specific page buffer). Append to `backend/src/routes/baptismal_ocr_firestore.test.js`:

```js
describe('CV grid path', () => {
  const gridPages = {
    pages: {
      left: { imageBuffer: Buffer.from('L'), cells: [
        { key: 'no', row: 0, x: 0, y: 0, w: 40, h: 40 },
        { key: 'child_name', row: 0, x: 40, y: 0, w: 200, h: 40 },
      ] },
      right: { imageBuffer: Buffer.from('R'), cells: [
        { key: 'minister', row: 0, x: 0, y: 0, w: 200, h: 40 },
      ] },
    },
    rotationApplied: 90, deskewDeg: 0.5, warnings: [],
  };
  const wordAt = (text, cx, cy) => ({
    text, confidence: 1,
    vertices: [{ x: cx - 5, y: cy - 5 }, { x: cx + 5, y: cy - 5 }, { x: cx + 5, y: cy + 5 }, { x: cx - 5, y: cy + 5 }],
  });

  test('uses CV rows when the grid service succeeds', async () => {
    const app = express();
    app.use('/api/ocr/baptismal', createBaptismalOcrRouter({
      verifyToken: (req, _res, next) => { req.user = { uid: 'u', role: 'admin' }; next(); },
      fetchGrid: async () => gridPages,
      recognizeImage: async (buf) => (buf.toString() === 'L'
        ? { words: [wordAt('1', 20, 20), wordAt('JUAN', 140, 20)] }
        : { words: [wordAt('FR.X', 100, 20)] }),
    }).router);
    const res = await request(app).post('/api/ocr/baptismal/scan')
      .send({ scanId: 's1', imageBase64: b64(JPEG) });
    expect(res.status).toBe(200);
    expect(res.body.data.rows).toHaveLength(1);
    expect(res.body.data.rows[0].fields.nameOfChild.value).toBe('JUAN');
    expect(res.body.data.warnings).not.toContain('CV_UNAVAILABLE');
    expect(res.body.data.warnings).toContain('CONFIDENCE_UNAVAILABLE');
  });

  test('falls back to word-clustering with CV_UNAVAILABLE when the grid service fails', async () => {
    const { CvGridError } = require('../services/cv_grid_client');
    const app = express();
    app.use('/api/ocr/baptismal', createBaptismalOcrRouter({
      verifyToken: (req, _res, next) => { req.user = { uid: 'u', role: 'admin' }; next(); },
      fetchGrid: async () => { throw new CvGridError('CV_UNREACHABLE', 'down'); },
      recognize: async () => ({ words: [{ text: 'X', vertices: [], confidence: 1 }] }),
      extract: () => ({ rows: [{ index: 0, lineNo: '1', fields: {} }], rotation: 0, warnings: [] }),
    }).router);
    const res = await request(app).post('/api/ocr/baptismal/scan')
      .send({ scanId: 's1', imageBase64: b64(JPEG) });
    expect(res.status).toBe(200);
    expect(res.body.data.rows).toHaveLength(1);
    expect(res.body.data.warnings).toContain('CV_UNAVAILABLE');
  });
});
```

- [ ] **Step 2: Run to verify it fails**

```bash
cd /e/parishrecord/backend && npx jest src/routes/baptismal_ocr_firestore.test.js -t "CV grid path"
```
Expected: FAIL — `fetchGrid`/`recognizeImage` deps not wired.

- [ ] **Step 3: Implement**

In `backend/src/routes/baptismal_ocr_firestore.js`:

Add requires near the top:
```js
const { fetchGrid: defaultFetchGrid } = require('../services/cv_grid_client');
const { gridToRows } = require('../services/baptismal_grid_assign');
const { recognizeWords: defaultRecognize } = require('../services/baptismal_ocr_service');
```

In `createBaptismalOcrRouter(deps = {})`, add:
```js
  const fetchGrid = deps.fetchGrid || defaultFetchGrid;
  // OCR on one prepared page image, detectOrientation off (already rectified).
  const recognizeImage = deps.recognizeImage
    || ((buf) => defaultRecognize(buf, { detectOrientation: false }));
```
(For this to work, `recognizeWords` must forward `detectOrientation` to `callOcrSpace` — add `detectOrientation` to its options in `baptismal_ocr_service.js` and pass it through, defaulting `true`.)

Replace the body of the `try { ... }` that currently does `preprocess → recognize → extract` with a CV-first version:

```js
      let result;
      let extraWarnings = [];
      try {
        const grid = await fetchGrid(buffer, {});
        // OCR each rectified page image the CV service returned. Downscale to
        // stay under OCR.space's upload limit.
        const leftPrep = await preprocess(grid.pages.left.imageBuffer, {
          maxEdge: 2000, quality: 80,
        });
        const rightPrep = await preprocess(grid.pages.right.imageBuffer, {
          maxEdge: 2000, quality: 80,
        });
        const [leftOcr, rightOcr] = await Promise.all([
          recognizeImage(leftPrep), recognizeImage(rightPrep),
        ]);
        const built = gridToRows(
          grid.pages.left, leftOcr.words, grid.pages.right, rightOcr.words,
        );
        result = { rows: built.rows, rotation: grid.rotationApplied, warnings: [...grid.warnings, ...built.warnings] };
      } catch (cvErr) {
        // Any CV failure -> today's word-clustering path. OCR.space failures
        // there keep their own OCR_* codes (rethrown to the outer catch).
        const prepared = await preprocess(buffer, { maxEdge: OCRSPACE_MAX_EDGE, quality: OCRSPACE_JPEG_QUALITY });
        const { words } = await recognize(prepared);
        result = extract(words);
        extraWarnings = ['CV_UNAVAILABLE'];
      }

      console.log(
        `[baptismal-ocr] scan=${sanitizeScanIdForLog(scanId)} rows=${result.rows.length} ` +
        `rotation=${result.rotation} warnings=${result.warnings.length} ms=${Date.now() - startedAt}`,
      );

      return res.json({
        success: true,
        data: {
          scanId,
          rows: result.rows,
          rotation: result.rotation,
          warnings: [...result.warnings, ...extraWarnings, 'CONFIDENCE_UNAVAILABLE'],
        },
      });
```

Keep the existing outer `catch (e)` (OCR_* / INTERNAL_ERROR mapping) exactly as-is: an OCR.space failure inside the fallback still throws a coded error and is handled there.

- [ ] **Step 4: Run the whole route + service suite**

```bash
cd /e/parishrecord/backend && npx jest baptismal
```
Expected: PASS (existing 151 + new CV-path tests). Fix any assertion that assumed the old single-warning array (the success envelope now may include `CV_UNAVAILABLE`).

- [ ] **Step 5: Commit**

```bash
cd /e/parishrecord
git add backend/src/routes/baptismal_ocr_firestore.js backend/src/routes/baptismal_ocr_firestore.test.js backend/src/services/baptismal_ocr_service.js
git commit -m "feat(ocr): CV-grid row detection with word-clustering fallback"
```

---

### Task 8: End-to-end validation + deploy notes

**Files:**
- Modify: `ocr_service/.env.example`, create `ocr_service/README.md`
- Modify: `CLAUDE.md` / `AGENTS.md` (one line noting the CV service)

**Interfaces:** none (documentation + manual validation).

- [ ] **Step 1: Run the CV service locally and validate end-to-end**

```bash
cd /e/parishrecord/ocr_service && OCR_SERVICE_KEY=devkey python -m uvicorn app.main:app --port 8900 &
cd /e/parishrecord/backend  # then, with OCR_SERVICE_URL=http://localhost:8900 OCR_SERVICE_KEY=devkey set,
# drive one scan of attachments/IMG_3120.jpeg through the route (a small node
# script or the existing probe adapted). Confirm rows == 24 and fields land in
# the right columns. Record findings.
```

Expected: row count matches the Task-2 hand truth; no `CV_UNAVAILABLE` warning when the service is up.

- [ ] **Step 2: Write run/deploy notes**

Create `ocr_service/README.md`: how to install (`pip install -r requirements.txt`), run (`uvicorn app.main:app`), the two env vars (`OCR_SERVICE_KEY`), the `/v1/grid` contract, and the Render deploy (build `pip install -r requirements.txt`, start `uvicorn app.main:app --host 0.0.0.0 --port $PORT`). Note that the Node backend needs `OCR_SERVICE_URL` + `OCR_SERVICE_KEY` set to reach it, and that scanning still works (fallback) when it is down.

- [ ] **Step 3: Full regression**

```bash
cd /e/parishrecord/ocr_service && python -m pytest -q
cd /e/parishrecord/backend && npx jest
cd /e/parishrecord && flutter analyze && flutter test
```
Expected: all green (Flutter unaffected by this backend/Python work).

- [ ] **Step 4: Commit**

```bash
cd /e/parishrecord
git add ocr_service/README.md ocr_service/.env.example CLAUDE.md AGENTS.md
git commit -m "docs(ocr): CV grid service run/deploy notes + end-to-end validation"
```

---

## Self-Review Notes

- **Spec coverage:** slim service + `/v1/grid` → Tasks 1,3; reuse pipeline verbatim → Task 1; feasibility gate → Task 2; OCR on rectified images (detectOrientation off) → Tasks 4,7; CV client → Task 5; word→cell assignment + field mapping → Task 6; route orchestration + `CV_UNAVAILABLE` fallback → Task 7; deploy/env/validation → Task 8. Non-goals (PaddleOCR, parser, marriage, UI) untouched.
- **Placeholder scan:** the only `<n>`/`<gt>` placeholders are Task-2/Task-8 runtime findings (evidence by design) and the hand counts the implementer fills in from the images.
- **Type consistency:** `fetchGrid → { pages:{left,right:{imageBuffer,cells:[{key,row,x,y,w,h}]}}, rotationApplied, warnings }` is produced in Task 5 and consumed identically in Tasks 6/7; `gridToRows(leftPage,leftWords,rightPage,rightWords) → {rows,warnings}` with `rows[i].fields[fieldKey]={value,confidence,inherited}` matches the route's existing serialization and the Flutter `BaptismalRegisterRow.fromJson`; `GRID_KEY_TO_FIELD` is the one mapping used in Task 6 and asserted in its test; `callOcrSpace(..., {detectOrientation})` (Task 4) is forwarded by `recognizeWords(buf,{detectOrientation})` used in Task 7.
- **Risk:** Task 2 is the gate; if the reused detector can't hit true counts by parameter tuning, stop and report rather than proceeding.
