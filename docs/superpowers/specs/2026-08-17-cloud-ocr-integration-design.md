# Cloud OCR Integration (OCR.space) — Design

**Date:** 2026-08-17
**Status:** Approved (design)
**Scope:** Add free, handwriting-capable cloud OCR (OCR.space) as the primary engine for parish register scanning, proxied through the existing Node/Express backend, with on-device ML Kit as automatic fallback. Reuses the existing `parseEntriesFromCells` seam and review UI.

## Problem & evidence

On-device Google ML Kit cannot read these handwritten sacramental registers — a validated ceiling of ~8 usable fragments per page, mostly printed headers (measured via the debug fixture dump). **OCR.space** (free tier, no billing) Engine 2 read ~all 24 rows at ~70–85% character accuracy on the same page, and returns **word bounding boxes** (`isOverlayRequired=true`) that map 1:1 onto the existing `OcrLineBox {text, top, left, width, height}`. Paid cloud OCR (Google Vision) is ruled out by cost.

## Decisions (settled)

- **Call site:** backend proxy. The app already depends on this Express backend for all `/api/*` features, so an OCR route adds no new production/hosting dependency, and the OCR.space key stays server-side.
- **Engine strategy:** cloud primary, on-device fallback. Register scans use OCR.space by default; on any failure (offline / non-2xx / timeout) they fall back to the existing on-device ML Kit path.
- **Backend responsibility:** normalize only. The endpoint converts OCR.space output to a generic `{text, cells[]}`; the Dart parser (`parseEntriesFromCells`) stays the single source of truth — no parser logic ported to Node.

## Architecture & data flow

```
Flutter (staff scan)                Backend  /api/ocr/scan            OCR.space
─────────────────────               ───────────────────────          ─────────
RegisterScanLauncher
  → downscale to <1MB  ── base64 ──▶ verifyFirebaseToken (staff/admin)
    (reuse preprocess)               → POST OCR.space (Engine 2,
                                        isOverlayRequired, key from .env)  ──▶
                                     ◀── ParsedText + word overlay ───────────
                                     → normalize to {text, cells[]}
  ◀──── {text, cells[]} ────────────
  → List<OcrLineBox>
  → RegisterOcrScanHelper.parseEntriesFromCells(cells)
  → StaffOcrScanResult → existing review table

  on any failure (offline / non-2xx / timeout)
  → fall back to existing on-device ML Kit path (unchanged)
```

The cloud path joins the pipeline at the harness seam: cloud gives `cells`, `parseEntriesFromCells` turns them into entries (the same method the golden tests cover). Everything downstream — review/edit/save UI — is untouched.

## Component: backend endpoint

New file `backend/src/routes/ocr_firestore.js`, mounted `app.use('/api/ocr', ocrRoutes)` after `verifyFirebaseToken` (staff/admin-authed like the rest). Uses Node 20's global `fetch` — no new dependency.

**`POST /api/ocr/scan`**
- Request body: `{ "imageBase64": "<jpeg base64, no data: prefix>", "recordType": "baptism" | "marriage" }`.
- Validation: `express-validator` — `imageBase64` non-empty string; `recordType` in `['baptism','marriage']`.
- Calls OCR.space `POST https://api.ocr.space/parse/image`, `application/x-www-form-urlencoded`:
  - `apikey` = `process.env.OCRSPACE_API_KEY`
  - `base64Image` = `data:image/jpeg;base64,<imageBase64>`
  - `OCREngine=2`, `isOverlayRequired=true`, `scale=true`, `detectOrientation=true`, `isTable=true`
- Success response: `{ success: true, data: { text, cells, engine: "ocrspace" } }`
  - `text` = `ParsedResults[0].ParsedText`
  - `cells` = flatten `ParsedResults[0].TextOverlay.Lines[].Words[]` → `{ text: WordText, left: Left, top: Top, width: Width, height: Height }` (numbers).
- Failure: `{ success: false, message }` — `400` for invalid input, `502` when OCR.space returns `IsErroredOnProcessing` / non-2xx / missing overlay, `500` for unexpected errors. Matches the project's `{ success, message }` convention.
- Config: add `OCRSPACE_API_KEY=` to `.env` and `.env.example`; document the route in Swagger (`backend/src/swagger.js`) like the others. Key is never logged.

**Normalizer** (`overlayToCells(ocrSpaceJson) -> { text, cells }`): a pure function, unit-tested against a saved sample response (no network).

## Component: Flutter cloud OCR client

New file `lib/services/cloud_ocr_service.dart`:
- `class CloudOcrResult { final String text; final List<OcrLineBox> cells; }`
- `Future<CloudOcrResult?> scanRegister(Uint8List jpeg, {required String recordType})`:
  - `POST ${BackendConfig.apiBaseUrl}/ocr/scan` via `package:http`, headers `{ 'Content-Type': 'application/json', 'Authorization': 'Bearer $idToken' }` (Firebase `getIdToken()`), body `jsonEncode({ 'imageBase64': base64Encode(jpeg), 'recordType': recordType })`.
  - ~30s timeout. On 2xx + `success:true`, parse `data.cells` via the existing `OcrLineBox.fromJson` and `data.text`. On any error/timeout/`success:false`, return `null` (caller falls back).

## Component: scan-helper cloud entry point

`RegisterOcrScanHelper.scanResultFromCloud(List<OcrLineBox> cells, String text, {required String recordType}) -> StaffOcrScanResult`:
- baptism → `parseEntriesFromCells(cells)`; marriage → the existing marriage parse path fed from cells/text.
- Builds `StaffOcrScanResult(text: text, entries/marriageEntries, lineCount, cellCount)` — the cloud analogue of the existing block path.

## Component: launcher cloud-first-with-fallback

In `RegisterScanLauncher` (the scan-with-progress path):
1. Downscale picked bytes with `RegisterOcrImagePreprocess` (resize ≤2000px long edge, JPEG q≈85 — under the 1MB free-tier cap; no aggressive contrast, which measurably hurt recognition).
2. `cloudOcr.scanRegister(bytes, recordType: …)`.
3. Non-null → `scanResultFromCloud(...)`. Null → existing on-device path (unchanged).

One branch point; all downstream UI unchanged.

## Image sizing, limits, errors

- **1MB free-tier cap:** enforced by the ≤2000px downscale (also the resolution that scored best; full-res measurably hurt ML Kit and risks the cap).
- **OCR.space errors** (`IsErroredOnProcessing`, HTTP 403 billing / 429 rate limit) → backend `success:false` → client falls back.
- **Timeout:** ~30s client timeout → fallback.
- **Key safety:** `OCRSPACE_API_KEY` only in backend `.env`; never in the client, never logged, never committed. (The earlier plaintext-shared Google Vision key must be rotated/deleted.)

## Testing

- **Backend (Jest):** `overlayToCells` normalizer maps a saved OCR.space sample response to the expected `cells[]` + `text`. Pure function, no network.
- **Flutter (unit):** `CloudOcrResult` / cells JSON → `List<OcrLineBox>` mapping round-trips correctly.
- **Reused:** `parseEntriesFromCells` is already golden-tested (OCR accuracy harness, Tasks 1–4).

## Non-goals (follow-on specs)

- OCR.space fixtures + baselines in the measurement harness (point the debug capture tool at `/api/ocr/scan`, hand-key ground truth, lock baselines) — the next spec, so we measure the real engine.
- Parser accuracy tuning (comes after we measure).
- Multi-page/batch cloud scanning, response caching, queuing OCR jobs to Firestore.
- Web/Tesseract removal (the backend path already serves web; cleanup is separate).
