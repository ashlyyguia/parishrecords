# Baptismal OCR — CV Ruled-Grid Row Detection (slim Python service + OCR.space)

**Date:** 2026-08-26
**Branch:** `feature/baptismal-ocr-record`
**Status:** Design — awaiting review

## Problem

On the current OCR.space + Node pipeline, row detection over-counts (37 rows vs 24 on IMG_3120) and can't recover the true row count. Investigation (see [memory / 2026-08-26]) proved exact row counts are **not reliably recoverable from OCR word positions**: OCR reads only 7/24 handwritten row numbers (misread), and word-only clustering/periodicity/per-column methods are all fragile. The true row boundaries are the register's **printed ruled lines** — a visual feature. Row counts also **vary per page** (IMG_3120 = 24; IMG_3121 ≈ 33–34, and is photographed upside-down), so no fixed heuristic works.

## What already exists (reuse, don't rebuild)

The `feature/baptismal-python-ocr` branch has a mature, tested OpenCV pipeline in `ocr_service/` (FastAPI + OpenCV + numpy, plus a PaddleOCR recognizer whose install was the blocker):

- `pipeline/table.py` (1131 lines) — adaptive binarization → long 1-D morphological kernels that isolate printed rules from handwriting → projection-peak detection tuned for faded/broken rules → row/column grid, with a two-page **pitch-agreement gate**. Public API includes `detect_spread_grids(left, right, spread_template)`, `row_boundaries(grid)`, `median_data_row_pitch(grid)`, `GridResult{rows, cols, cells, column_keys}`.
- `pipeline/orientation.py`, `inversion.py` (upside-down spread), `spread.py` (gutter split), `rectify.py` (per-page shear/deskew), `column_template.py` (`BAPTISMAL_REGISTER` column keys).

This grid detector is **OCR-engine-agnostic** (operates on the image, independent of PaddleOCR).

## Goal

Fix row detection by having a **slim Python CV service** detect the ruled grid and return the **rectified page images + grid geometry**; the current Node/OCR.space backend runs OCR.space on those rectified images and assigns words to grid cells. Keep OCR.space for text. Drop PaddleOCR.

## Non-goals

- Do NOT rewrite `table.py` or the CV algorithms (reuse as-is; tune only if Task-1 validation shows it's needed).
- Do NOT revive PaddleOCR or the Python recognizer/parser.
- Marriage/matrimonial OCR (unchanged, out of scope).
- Review UI changes (unchanged).

## Architecture & data flow

Entry point and response shape are unchanged (`POST /api/ocr/baptismal/scan` → `{ success, data:{ scanId, rows, rotation, warnings } }`).

1. **Node** preprocesses the upload (existing `preprocessForOcr`, sharp).
2. **Node → CV service** `POST /v1/grid` (auth header `X-OCR-Service-Key`, from `OCR_SERVICE_KEY`; base URL `OCR_SERVICE_URL`).
3. **CV service** runs `correct_orientation → correct_spread_inversion → split_spread → rectify_page(left/right) → detect_spread_grids(..., BAPTISMAL_REGISTER)` and returns:
   ```json
   {
     "success": true,
     "rotation_applied": 90, "deskew_deg": 1.2,
     "pages": {
       "left":  { "image": "<base64 jpeg of rectified page>", "width": W, "height": H,
                  "cells": [{ "key": "nameOfChild", "row": 0, "x": .., "y": .., "w": .., "h": .. }, ...],
                  "rows": <int>, "cols": <int> },
       "right": { ... }
     },
     "warnings": ["..."]
   }
   ```
   Cells are keyed by the register's field via `BAPTISMAL_REGISTER`; coordinates are in each **rectified page image's** pixel frame.
4. **Node → OCR.space** on each returned rectified page image (Engine 2, `isOverlayRequired`, **`detectOrientation=false`** — the page is already upright/rectified). Yields word boxes in the **same frame as the cells**.
5. **Node assigns** each OCR word to the grid cell whose rect contains the word-box center → per-cell `{value, confidence}` (reading order within a cell as today). Rows are the grid rows; left/right join by row index (grids share one row model via the pitch-agreement gate).
6. Existing **fill-down** + **field mapping** to the 7 captured keys (`nameOfChild, placeAndBirthDate, parents, residentsOf, dateOfBaptism, minister, sponsors`; the template's `legitimacy`/`observations` cells are ignored, matching the current captured-column decision).
7. Return rows to the client.

**Fallback:** if the CV service is unreachable, times out, or refuses the spread (its own `OcrError`), Node runs **today's path** — one OCR.space call on the preprocessed image + `baptismal_register_layout.js` word-clustering — and appends a `CV_UNAVAILABLE` warning so the reviewer knows counts are the imperfect ones.

**Why the coordinate problem is solved:** OCR.space runs on the *same rectified images* the CV service produced, so grid cells and OCR words are in one pixel frame. No relative-coordinate mapping, no OCR.space auto-rotate/scale mismatch.

## Components (isolation & interfaces)

**Python (`ocr_service/`, slim, on this branch):**
- Reused verbatim from the python branch: `pipeline/{orientation,inversion,spread,rectify,column_template,table}.py`, plus `config.py`, `errors.py`, `security.py`, `schemas.py` (trimmed).
- New `main.py`: `GET /health`; `POST /v1/grid` → runs the geometry pipeline, returns rectified images + grid geometry (above). No text recognition.
- Dropped: `pipeline/recognize/` (PaddleOCR), `pipeline/cells.py` crop-for-OCR (not needed; may keep a helper to emit cell rects), `parsers/`.
- Deps: `opencv-python-headless`, `numpy`, `fastapi`, `uvicorn`, `pydantic`. No paddle.

**Node (`backend/src/`):**
- `services/cv_grid_client.js` — `fetchGrid(imageBuffer, { env, fetchImpl })` → typed `{ pages, rotation, warnings }` or throws a coded error the route maps to fallback. Injectable `fetchImpl` for tests (matches existing style).
- `services/baptismal_grid_assign.js` — **pure**: `assignWordsToGrid(cells, words)` → per-cell values; `gridToRows(leftAssigned, rightAssigned)` → the `{ rows, warnings }` shape the route already returns. Reuses the reading-order logic pattern from `baptismal_register_layout.assignCells`.
- Route `baptismal_ocr_firestore.js` — orchestrate: preprocess → try CV path → OCR.space(rectified per page) → assign; on any CV failure, existing path + `CV_UNAVAILABLE`.
- `ocrspace_service.js` — allow `detectOrientation` to be toggled off (add an option; default keeps current behavior).
- `baptismal_register_layout.js` — unchanged; the fallback.

## Error handling

- CV unreachable / timeout (`OCR_TIMEOUT_MS`) / non-2xx → fallback path + `CV_UNAVAILABLE`.
- CV `OcrError` (spread unreadable, corrupt image) → fallback path + `CV_UNAVAILABLE`.
- OCR.space failures on rectified images → existing `OCR_*` codes/mapping.
- Upload validation (type/size) unchanged, before any service call.
- Never log cell values/text (records of minors) — counts, codes, timings only, both services.

## Deployment

- New Python service deployed separately (Render): build `pip install -r ocr_service/requirements.txt`, start `uvicorn app.main:app`. `OCR_SERVICE_URL` + `OCR_SERVICE_KEY` already exist in `backend/.env`.
- Local dev: run `uvicorn` alongside the Node backend. When it isn't running, the fallback keeps scanning working.

## Testing

- **Python:** port the existing `ocr_service/tests` for the reused pipeline modules (table/orientation/rectify/spread) — they already pass (~112) on the python branch. Add tests for the new `/v1/grid` endpoint: synthetic ruled-grid image → asserts row/col counts + cell keys + rectified-image round-trip. Auth-key + refusal (OcrError) cases.
- **Node (Jest):** `cv_grid_client` (mocked fetch: success, timeout, non-2xx, OcrError body); `baptismal_grid_assign` (pure, fixtures: words→cells, reading order, empty cells); route (CV success → grid rows; CV failure → fallback path + `CV_UNAVAILABLE`). `ocrspace_service` detectOrientation toggle.
- **End-to-end validation (evidence, run once):** real pipeline on `attachments/IMG_3120` (expect **24**), `IMG_3121` (hand-count, ≈33–34, inverted), `IMG_3122` (hand-count). Assert detected row counts match hand truth; record findings honestly.

## Key risk & first task

My notes record that a row-recovery tweak on the python branch once **over-counted and regressed IMG_3120**. So **implementation Task 1 is a feasibility check**: bring the reused pipeline onto this branch and run `detect_grid`/`detect_spread_grids` on the real rectified pages, confirming true row counts (24 / ~33–34) before building the Node integration. If the detector is off, tune within `table.py` (its documented parameters: `PEAK_FLOOR_FRACTION`, kernel/gap divisors, `SPREAD_PITCH_TOLERANCE`) — do not rebuild.

## Open decisions (defaults chosen)

- **One CV call returns both pages' rectified images**, Node makes two OCR.space calls (left, right). Acceptable on the registered key. (Alternative — OCR the full rectified spread once — complicates cell/coord bookkeeping; rejected.)
- **Column keys come from the CV `BAPTISMAL_REGISTER` template**, not OCR header matching — more robust; the Node header-calibration is only used on the fallback path.
