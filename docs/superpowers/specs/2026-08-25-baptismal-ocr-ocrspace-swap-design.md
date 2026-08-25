# Baptismal OCR — Swap Engine from Google Cloud Vision to OCR.space

**Date:** 2026-08-25
**Branch:** `feature/baptismal-ocr-record`
**Status:** Design — awaiting review

## Context

A complete baptismal register OCR feature already exists on this branch (built
per `docs/superpowers/specs/2026-08-22-baptismal-ocr-record-design.md` and its
plan). It is wired end-to-end — **Add Record (OCR)** on `/admin/records` →
`/admin/records/ocr-baptism` → the backend route `POST /api/ocr/baptismal/scan`
— and its backend suite passes (156 tests).

The one mismatch with the current requirement: it calls **Google Cloud Vision**
(`documentTextDetection`). The requirement is to use the **OCR.space API**,
which is already configured in `backend/.env` as `OCRSPACE_API_KEY` and is the
engine the parish can actually run today (Vision needs GCP API enablement +
service-account credentials that are not reliably set up — the likely reason the
existing feature "does not work reliably" for the user).

This is therefore **not a rebuild**. The layout/parsing pipeline, preprocessing,
route, Flutter models, review UI, validation, and original-image archival are
OCR-engine-agnostic and stay. Only the OCR I/O boundary changes.

## Goal

Replace the Vision OCR call with an OCR.space call, feeding the **exact same
normalized word shape** into the existing layout pipeline, so an admin can
photograph a baptismal register spread, have OCR.space read it, review/correct
every field, and batch-save verified rows — with OCR.space as the only engine
and its key kept server-side.

## Non-goals

- Marriage/matrimonial OCR (explicitly out of scope, unchanged).
- Rewriting the layout pipeline, review table, models, or scan page.
- Removing the Vision code path is optional (see Open Decisions); the default is
  to leave `@google-cloud/vision` installed but unused to minimize churn.
- Improving raw handwriting accuracy beyond what OCR.space Engine 1 provides;
  the human-review step is the accuracy backstop.

## The contract that must not change

`baptismal_register_layout.js` consumes a list of normalized words:

```js
{ text: 'TESTA', vertices: [ {x,y}×4 as TL,TR,BR,BL ], confidence: 0.93 }
```

The route calls `recognize(preparedBuffer) → { words, fullText }` and passes
`words` straight to `extractBaptismalRows(words)`. **Any engine that produces
this shape works unchanged downstream.** The swap is: make `recognize` call
OCR.space instead of Vision.

## Design

### 1. Rewrite `backend/src/services/baptismal_ocr_service.js`

Replace Vision I/O with OCR.space I/O, reusing the existing
`backend/src/services/ocrspace_service.js` (`callOcrSpace`, `overlayToCells`).

- `recognizeWords(imageBuffer, { fetchImpl, apiKey, env } = {})` →
  `Promise<{ words, fullText }>`.
  - Base64-encode the buffer, call OCR.space via `callOcrSpace` using
    **`OCREngine: '1'`** (see Risk 1 — Engine 1 is the engine that returns word
    bounding boxes), with `isOverlayRequired`, `isTable`, `scale`, and
    `detectOrientation` enabled. `callOcrSpace` currently hardcodes Engine 2 for
    the old `/scan` route; add an optional `engine` parameter that **defaults to
    `'2'`** (preserving that route) and pass `'1'` from here.
  - Convert each overlay word `{ WordText, Left, Top, Width, Height }` into the
    normalized shape. OCR.space boxes are **axis-aligned**, so vertices are:
    `TL(L,T) TR(L+W,T) BR(L+W,T+H) BL(L,T+H)`.
  - `confidence`: OCR.space overlay carries none. Emit a constant `1.0` and
    document why. Per-field low-confidence flagging is intentionally replaced by
    a scan-level banner (Risk 3).
  - `fullText`: `ParsedResults[0].ParsedText`.
- Error mapping (engine-neutral codes, see §4): missing/invalid key →
  `OCR_AUTH`; OCR.space rate-limit/exhausted → `OCR_QUOTA`; HTTP/network/timeout
  → `OCR_UNAVAILABLE`; empty parsed text / zero overlay words → `NO_TEXT_FOUND`.
- `client`/`fetchImpl` stays injectable for offline tests, mirroring
  `ocrspace_service.test.js`.
- Remove `resolveVisionCredentials` and the `@google-cloud/vision` require.

### 2. Rewrite `baptismal_ocr_service.test.js`

Drop Vision-response fixtures; add OCR.space-response fixtures (overlay JSON with
`TextOverlay.Lines[].Words[]`). Assert: normalization to word shape (vertex
order, text join), `NO_TEXT_FOUND` on empty/overlay-less responses, and the
`OCR_*` error mappings. Injected `fetchImpl` — no network.

### 3. Preprocess tuning for OCR.space size limits

`baptismal_image_preprocess.js` stays, but OCR.space (free/registered keys) caps
upload size (~1 MB on free tiers). A grayscale 4096px JPEG can exceed that.
Adjust the OCR-bound copy to stay under the limit — reduce `MAX_EDGE` for this
path and/or lower JPEG quality — validated empirically against the sample images
(Risk + Validation). The **original upload is still archived untouched**.

### 4. Rename `VISION_*` error codes → `OCR_*`

Mechanical, engine-honest rename across the wire contract:

- `backend/src/routes/baptismal_ocr_firestore.js`: `STATUS_BY_CODE` /
  `MESSAGE_BY_CODE` keys (`VISION_AUTH→OCR_AUTH`, `VISION_QUOTA→OCR_QUOTA`,
  `VISION_UNAVAILABLE→OCR_UNAVAILABLE`). HTTP statuses unchanged (500/429/502).
  User-facing messages already say "OCR" — **no UX change**.
- `lib/services/baptismal_ocr_service.dart`: `_recoveryByCode` keys and the
  doc comment referencing "Vision". Recovery mapping is preserved
  (`OCR_QUOTA`→retry, `OCR_UNAVAILABLE`→retry, `OCR_AUTH`→contactAdmin).
- Update the route test and the Dart service test for the renamed codes.

### 5. Confidence UX — scan-level banner

Chosen approach: one banner over the review table — *"This engine can't score
confidence — please verify every field before saving."* Implementation:

- The service emits words at confidence `1.0`, so `OcrField.needsReview` no
  longer fires on confidence. `inherited` (fill-down) flags and required-field
  validation still work unchanged.
- The route adds a warning `CONFIDENCE_UNAVAILABLE` to `result.warnings` for
  every OCR.space scan; the scan page renders the banner when that warning is
  present. Data-driven and testable; no change to `OcrField`'s shape.

### 6. Entry points

Admin is already wired (`/admin/records/ocr-baptism`). Add a staff entry point
to the same new baptismal page without disturbing the classic combined
baptism/marriage scanner (`StaffOcrUploadPage`) that staff still needs for
marriage. Scope this as a small, low-risk addition; if it complicates the
staff shell, defer to a follow-up rather than risk the marriage path.

## Risks & how they're handled

1. **Word boxes require OCR.space Engine 1.** The pipeline needs per-word boxes.
   Engine 1 returns overlay; Engines 2/3 typically return text only. The
   existing `ocrspace_service.js` requests Engine 2 *with* overlay (likely
   yields no cells — a probable cause of past OCR.space unreliability). Use
   Engine 1. **Validate** that overlay words actually return on `IMG_3120`
   before building on it. Trade-off: Engine 1 is weaker on handwriting than
   Vision; the review step absorbs it.
2. **Orientation.** Vision returned rotated quads, letting the pipeline
   auto-detect a sideways 90° page from word-baseline angle. OCR.space returns
   axis-aligned boxes, so `normalizeOrientation` will read every page as
   upright (rotation 0). The sideways sample photos must be made upright *before*
   OCR: rely on OCR.space `detectOrientation`, and if that is insufficient, add
   content-based rotation to the OCR-bound preprocess copy. **This is the
   highest-risk item and must be validated on `IMG_3120–3122`.**
3. **No per-word confidence** → handled by §5 (scan-level banner).
4. **Upload size** → handled by §3 (downscale the OCR-bound copy).

## Validation (must run before calling this done)

- Backend Jest suite green, including the rewritten service/route tests.
- `flutter analyze` clean; Flutter test suite green.
- **Live/sample validation:** run the real pipeline against
  `attachments/IMG_3120.jpeg` (3121, 3122) through OCR.space and confirm: overlay
  words return (Risk 1), the spread is read upright (Risk 2), rows are detected
  and columns assigned to plausible fields. Record findings; tune Engine/rotation
  /size as needed. Compare row/field extraction quality and note it honestly —
  if OCR.space is materially worse than Vision on these images, surface that.

## Open decisions (defaults chosen; confirm during review)

- **Remove Vision entirely?** Default: leave the `@google-cloud/vision` dep and
  the old spec/plan docs in place (dormant), to keep the diff focused. Can be
  removed in a follow-up once OCR.space is validated.
- **Staff entry point** now vs. follow-up: default now, but deferrable (§6).

## Files touched

**Rewrite:** `backend/src/services/baptismal_ocr_service.js` (+ its test).
**Edit:** `backend/src/routes/baptismal_ocr_firestore.js` (codes + warning),
its test; `backend/src/services/baptismal_image_preprocess.js` (OCR-bound size);
`backend/src/services/ocrspace_service.js` (add optional `engine` param,
default `'2'`) + its test; `lib/services/baptismal_ocr_service.dart`
(codes/comment) + test; `lib/screens/admin/pages/baptismal_ocr_scan_page.dart`
(banner); possibly `lib/app/router.dart` + a staff entry (§6).
**Unchanged:** `baptismal_register_layout.js` (+ test), `baptismal_register_row.dart`,
`baptismal_ocr_review_table.dart`, `baptismal_row_validation.dart`.
