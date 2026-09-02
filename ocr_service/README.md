# Parish Register Grid Service

A slim FastAPI + OpenCV service that finds the **ruled grid** of a baptismal
register spread and returns rectified page images plus per-cell geometry. It
does **no OCR and no recognition** — the Node backend runs OCR.space on the
rectified images this service returns, so words and grid cells share one pixel
frame. There is no PaddleOCR and no text recognition here.

It is optional: if this service is unreachable or unconfigured, the backend
falls back to word-clustering on a single OCR.space pass (see
`backend/src/routes/baptismal_ocr_firestore.js`). Scanning keeps working; the
grid just isn't used.

## Privacy

These pages are records of minors. The service logs **counts, codes, and
timings only** — never cell contents or recognized text. Keep it that way.

## Endpoints

### `GET /health`
Returns `{"status": "ok"}`.

### `POST /v1/grid`
- **Auth:** header `X-OCR-Service-Key` must equal `OCR_SERVICE_KEY`.
- **Body:** raw image bytes (`Content-Type: application/octet-stream`), JPEG/PNG.
- **Response:**

  ```json
  {
    "success": true,
    "rotation_applied": 0,
    "deskew_deg": -2.78,
    "pages": {
      "left":  { "image_b64": "...", "width": 2037, "height": 2268,
                 "rows": 23, "cols": 5,
                 "cells": [{"key": "child_name", "row": 0, "x": 10, "y": 40, "w": 200, "h": 45}, ...] },
      "right": { ... }
    },
    "warnings": []
  }
  ```

  - `cells` carry the authoritative row indexing; the backend assigns each OCR
    word to the cell whose rect contains its box centre.
  - `key` is one of `no`, `child_name`, `place_and_birth_date`, `parents`,
    `residents_of`, `l_or_ill` (left) / `baptism_date`, `minister`,
    `residents_of`, `sponsors`, `observations` (right). The backend maps these
    to its field keys and ignores `l_or_ill` / `observations`.
  - Note: the `rows` scalar is `grid.rows - 1` and can read one lower than the
    number of distinct row indices present in `cells`. The backend derives rows
    from `cells`, not from this scalar, so it is informational only.
- **Errors:** `OcrError` → `{ "success": false, "code": ..., "message": ... }`
  with an HTTP status (401 `unauthorized`, 400 `corrupt_image`, 413/422 for
  upload/table problems). Any non-2xx makes the backend fall back.

## Run locally

> **This service must be running whenever you scan.** The backend is CV-first:
> if it can't reach this service it silently falls back to word-clustering,
> which mangles rotated / two-page / angled register photos. Start it alongside
> the backend, in its own window.

First-time setup:

```bash
cd ocr_service
python -m venv .venv310            # Python 3.10
.venv310/Scripts/python -m pip install -r requirements.txt   # Windows
# .venv310/bin/pip install -r requirements.txt               # POSIX
```

Then, every time you run the backend, start this too:

```bash
# From anywhere in the repo. Defaults: port 8000, key dev-key (matches backend/.env).
ocr_service/scripts/start-ocr-service.sh          # Git Bash / POSIX
```

On Windows you can also just double-click `ocr_service/scripts/start-ocr-service.bat`.

Override the port/key with env vars:

```bash
OCR_SERVICE_KEY=devkey PORT=8000 ocr_service/scripts/start-ocr-service.sh
```

Then point the backend at it in `backend/.env`:

```
OCR_SERVICE_URL=http://127.0.0.1:8000
OCR_SERVICE_KEY=devkey            # must match this service's OCR_SERVICE_KEY
OCR_TIMEOUT_MS=120000
```

## Tests

```bash
.venv310/Scripts/python -m pytest tests/ -q      # pipeline + endpoint (72)
```

Structure-only validation against real sample spreads (no cell text printed):

```bash
.venv310/Scripts/python scripts/validate_grids.py ../attachments/IMG_3120.jpeg
```

## Deploy (Render or similar)

- **Build:** `pip install -r requirements.txt`
- **Start:** `uvicorn app.main:app --host 0.0.0.0 --port $PORT`
- **Env:** set `OCR_SERVICE_KEY` to a long random string and mirror it (plus
  `OCR_SERVICE_URL`) into the Node backend's environment.
- Uses `opencv-python-headless`, so no system GUI libraries are required.
