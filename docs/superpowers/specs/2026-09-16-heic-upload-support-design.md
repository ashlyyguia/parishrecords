# HEIC upload support for OCR scanning

**Date:** 2026-09-16
**Status:** Approved design, ready for implementation plan

## Problem

iPhones save photos as HEIC by default. When a user uploads a `.HEIC` register
photo through the web/desktop file picker, the scan fails: the OCR pipeline can
only decode JPEG, PNG, and WebP.

Two places enforce this today:

- Backend `sniffImageType` (`backend/src/services/baptismal_image_preprocess.js`)
  rejects any buffer whose magic bytes are not JPEG/PNG/WebP. The baptismal
  scan route gates on it (`baptismal_ocr_firestore.js:216`) **before** handing
  the raw buffer to the Python CV grid service, so HEIC never gets a chance to
  be converted.
- The generic `/api/ocr/scan` route (`ocr_firestore.js`) forwards the base64
  straight to OCR.space with a hardcoded `data:image/jpeg` prefix; OCR.space
  cannot read HEIC either.

The client also can't currently *select* a `.HEIC` file on Windows: the picker
uses `FileType.image`, whose native filter may not surface HEIC, and
`_mimeForExtension` mislabels unknown extensions as `image/jpeg`.

## Goal

A user can upload a `.HEIC` register photo on any platform and have it scanned
successfully, or — if the specific file can't be decoded — see a clear message
and have that one file skipped while the rest of the batch proceeds.

## Key facts that shape the design

- **Register scanning is always server-side.** Both the baptismal path
  (`BaptismalOcrService` → `/api/ocr/baptismal/scan`) and the cloud path
  (`CloudOcrService` → `/api/ocr/scan`) base64-upload bytes to the Node
  backend. Every client platform funnels through the same route, so a single
  server-side conversion point covers **all platforms** for the actual feature.
- **Mobile is already covered.** `image_picker` transcodes HEIC→JPEG on pick
  (iOS) and the camera path is JPEG, so no HEIC ever reaches the server from a
  phone. No mobile code change is needed.
- **`sharp` is already a backend dependency** and `preprocessForOcr` already
  re-encodes to JPEG — but the raw (pre-preprocess) buffer is what goes to the
  Python CV service, so conversion must happen *before* that, at the top of the
  route.

## Design

### Backend — the workhorse (covers all platforms)

New module `backend/src/services/heic_to_jpeg.js`:

- `isHeic(buffer)` — sniffs the ISO-BMFF `ftyp` box and matches HEIF/HEIC major
  brands: `heic`, `heix`, `heif`, `mif1`, `msf1`. Returns `false` for
  JPEG/PNG/WebP and short/garbage buffers. Never trusts a declared mime.
- `heicToJpeg(buffer)` — decodes with the `heic-convert` package
  (pure-JS libheif/WASM, so it behaves identically on Windows dev and
  Render/Linux prod) and returns JPEG bytes at quality `0.92`. Throws on a
  decode failure rather than returning the original buffer, so the caller can
  map the failure to a real error code.

Wire it into both OCR routes, immediately after `Buffer.from(base64)` and the
byte-size check, before any sniff/CV/preprocess/OCR.space work:

```js
if (isHeic(buffer)) {
  try {
    buffer = await heicToJpeg(buffer);
  } catch (e) {
    return fail(res, 'IMAGE_INVALID', scanId); // baptismal route
    // generic route: 400 with its existing shape
  }
}
```

- `baptismal_ocr_firestore.js`: insert between the `buffer.length` checks
  (line ~214) and `sniffImageType` (line ~216). Downstream is untouched — the
  Python CV service, `sniffImageType`, `preprocessForOcr`, and OCR.space all
  only ever see JPEG.
- `ocr_firestore.js`: insert before `callOcrSpace`. This route has no sniff of
  its own, so decode the base64, convert if HEIC, and re-encode base64 for the
  OCR.space call (or pass the buffer through the existing service path).

Add `"heic-convert"` to `backend/package.json` dependencies.

**No change to the Python `ocr_service`** — it never receives HEIC.

### Client — make the file selectable and labeled

`lib/services/ocr_image_pick.dart`:

- On web/desktop (`_useFilePicker`), accept `heic`/`heif` alongside the existing
  image types so the OS picker surfaces them. Use `FileType.custom` with
  `allowedExtensions: ['jpg','jpeg','png','webp','heic','heif']` if
  `FileType.image` does not reliably surface HEIC on Windows.
- `_mimeForExtension` returns `image/heic` for `heic`/`heif`.
- Mobile pick paths unchanged.

### Fallback — clear error, skip the file

Per the chosen behavior: in a multi-page batch, if the server returns
`IMAGE_INVALID` for a page (e.g. a corrupt HEIC that won't decode), skip that
one page with a clear message (e.g. "Couldn't read <name> — try JPG/PNG") and
keep the remaining valid pages in the batch. The baptismal scan page's
per-page loop will surface the skip; exact wiring to be confirmed against the
scan page during planning.

## Testing

- Backend unit tests for `isHeic`: a real HEIC fixture returns true; JPEG/PNG/
  WebP and a short/garbage buffer return false.
- Backend unit test for `heicToJpeg`: converts the HEIC fixture to a buffer with
  JPEG magic bytes (`FF D8 FF`); throws on a non-HEIC/garbage buffer.
- Backend route test: a HEIC upload to `/api/ocr/baptismal/scan` now proceeds
  past the format gate (previously `IMAGE_INVALID`/400).
- Flutter test: `_mimeForExtension` maps `heic`/`heif` → `image/heic` and the
  existing types are unchanged.

## Out of scope (YAGNI)

- Client-side HEIC decoding (heic2any / platform codecs). The offline
  local-Tesseract path is not used for register scanning, and desktop has no
  local HEIC decoder, so this adds surface for no real coverage gain.
- Any change to the Python OCR service.
- Reusing `sharp` for the HEIC decode: its prebuilt binaries don't guarantee
  HEVC/HEIC *decode* on every platform (notably Windows), which conflicts with
  the all-platforms goal; `heic-convert` is deterministic across platforms.
