# HEIC Upload Support Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let users upload iPhone `.HEIC` register photos and have them scanned, by transcoding HEIC→JPEG once on the Node backend before any OCR work.

**Architecture:** Register scanning is always server-side — every platform base64-uploads bytes to the Node backend. A single conversion point at the top of each OCR route (before magic-byte sniffing, the Python CV grid call, preprocessing, and OCR.space) converts HEIC to JPEG, so nothing downstream ever sees HEIC. The client only changes enough to make `.heic`/`.heif` files selectable and correctly labeled. Mobile needs no change (`image_picker` already transcodes on pick).

**Tech Stack:** Node/Express + jest/supertest (backend), `heic-convert` (pure-JS libheif/WASM decoder), `sharp` (already present), Flutter + `file_picker` + flutter_test (client).

## Global Constraints

- Backend is CommonJS (`require`/`module.exports`); tests are colocated `*.test.js` run by `jest`.
- Never log or echo image bytes, pixel dimensions, or recognized text — these are records of minors. (Existing route invariant.)
- Magic-byte sniffing only; never trust a client-declared mime.
- HEIC decoder must work identically on Windows (dev) and Linux (Render prod) — use `heic-convert`, not `sharp`'s optional HEIF codec.
- Accepted downstream image types stay JPEG/PNG/WebP; HEIC is converted to JPEG before it reaches that gate, never added to the accepted set.
- Flutter client is unchanged on mobile; edits touch only `lib/services/ocr_image_pick.dart`.

---

### Task 1: Backend `heic_to_jpeg` module + committed HEIC fixture

**Files:**
- Create: `backend/src/services/heic_to_jpeg.js`
- Create: `backend/src/services/heic_to_jpeg.test.js`
- Create: `backend/test/fixtures/sample.heic` (copied from a real sample; committed so CI has it)
- Modify: `backend/package.json` (add `heic-convert` dependency)

**Interfaces:**
- Produces: `isHeic(buffer: Buffer): boolean` and `async heicToJpeg(buffer: Buffer): Promise<Buffer>`.
  - `isHeic` returns true only for ISO-BMFF `ftyp` boxes whose major brand is a HEIF/HEIC brand; false for JPEG/PNG/WebP/short/garbage buffers.
  - `heicToJpeg` returns JPEG bytes (magic `FF D8 FF`); **rejects** (throws) on undecodable input rather than returning the original.

- [ ] **Step 1: Install the decoder dependency**

Run:
```bash
cd backend && npm install heic-convert
```
Expected: `heic-convert` (and its `libheif-js` dep) added to `backend/package.json` + `package-lock.json`.

- [ ] **Step 2: Create the committed test fixture**

The real samples in `attachments/baptismal/` are git-ignored, so copy one into a tracked fixtures dir (the destination is NOT ignored — no `-f` needed):
```bash
cd /e/parishrecord && mkdir -p backend/test/fixtures && cp attachments/baptismal/IMG_3937.HEIC backend/test/fixtures/sample.heic
```
Expected: `backend/test/fixtures/sample.heic` exists (~1.8MB, `ftypheic` at bytes 4–12).

- [ ] **Step 3: Write the failing tests**

Create `backend/src/services/heic_to_jpeg.test.js`:
```js
const fs = require('fs');
const path = require('path');
const { isHeic, heicToJpeg } = require('./heic_to_jpeg');

const FIXTURE = path.join(__dirname, '..', '..', 'test', 'fixtures', 'sample.heic');
const heic = fs.readFileSync(FIXTURE);

describe('isHeic', () => {
  test('detects a real iPhone HEIC by its ftyp brand', () => {
    expect(isHeic(heic)).toBe(true);
  });

  test('rejects JPEG, PNG, and WebP magic bytes', () => {
    expect(isHeic(Buffer.from([0xff, 0xd8, 0xff, 0xe0, 0, 0]))).toBe(false);
    expect(isHeic(Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]))).toBe(false);
    const webp = Buffer.concat([Buffer.from('RIFF'), Buffer.from([0, 0, 0, 0]), Buffer.from('WEBP')]);
    expect(isHeic(webp)).toBe(false);
  });

  test('rejects a short buffer and an ftyp box with a non-HEIF brand', () => {
    expect(isHeic(Buffer.from([0, 0, 0, 0x20]))).toBe(false); // too short for a brand
    const mp4 = Buffer.concat([Buffer.from([0, 0, 0, 0x20]), Buffer.from('ftypmp42'), Buffer.alloc(8, 0)]);
    expect(isHeic(mp4)).toBe(false);
  });
});

describe('heicToJpeg', () => {
  test('converts a real HEIC to JPEG bytes', async () => {
    const out = await heicToJpeg(heic);
    expect(Buffer.isBuffer(out)).toBe(true);
    expect(out.length).toBeGreaterThan(0);
    expect(out[0]).toBe(0xff);
    expect(out[1]).toBe(0xd8);
    expect(out[2]).toBe(0xff);
  }, 20000);

  test('rejects an ftyp-heic header with a garbage body', async () => {
    const fake = Buffer.concat([Buffer.from([0, 0, 0, 0x20]), Buffer.from('ftypheic'), Buffer.alloc(64, 0)]);
    await expect(heicToJpeg(fake)).rejects.toBeTruthy();
  });
});
```

- [ ] **Step 4: Run the tests to verify they fail**

Run: `cd backend && npx jest src/services/heic_to_jpeg.test.js`
Expected: FAIL — `Cannot find module './heic_to_jpeg'`.

- [ ] **Step 5: Implement the module**

Create `backend/src/services/heic_to_jpeg.js`:
```js
/**
 * HEIC/HEIF -> JPEG normalization.
 *
 * iPhones save photos as HEIC by default. The rest of the OCR pipeline only
 * decodes JPEG/PNG/WebP (magic-byte gate in baptismal_image_preprocess.js,
 * and the Python CV grid service), so a HEIC upload must be transcoded to
 * JPEG once, at the top of each OCR route, before any of that runs.
 *
 * `heic-convert` (pure-JS libheif/WASM) is used deliberately instead of
 * sharp: sharp's prebuilt binaries do not guarantee HEVC/HEIC *decode* on
 * every platform (notably Windows dev machines), and this must behave
 * identically in dev and on the Linux host.
 */

// ISO-BMFF `ftyp` major brands that mean HEIF/HEIC still-image content.
// (AVIF is intentionally excluded — different codec, not what iPhones emit.)
const HEIF_BRANDS = new Set([
  'heic', 'heix', 'heim', 'heis', 'hevc', 'hevx', 'mif1', 'msf1', 'heif',
]);

/**
 * True only when the buffer is a HEIF/HEIC image, sniffed by its `ftyp` box.
 * Never trusts a declared mime/extension.
 */
function isHeic(buffer) {
  if (!Buffer.isBuffer(buffer) || buffer.length < 12) return false;
  if (buffer.toString('latin1', 4, 8) !== 'ftyp') return false;
  return HEIF_BRANDS.has(buffer.toString('latin1', 8, 12));
}

/**
 * Decodes HEIC bytes and re-encodes as JPEG. Throws (rejects) on undecodable
 * input so the caller can map the failure to a real "unsupported image"
 * error rather than silently passing HEIC downstream.
 */
async function heicToJpeg(buffer) {
  const convert = require('heic-convert');
  const out = await convert({ buffer, format: 'JPEG', quality: 0.92 });
  return Buffer.from(out);
}

module.exports = { isHeic, heicToJpeg, HEIF_BRANDS };
```

- [ ] **Step 6: Run the tests to verify they pass**

Run: `cd backend && npx jest src/services/heic_to_jpeg.test.js`
Expected: PASS (5 tests).

- [ ] **Step 7: Commit**

```bash
git add backend/src/services/heic_to_jpeg.js backend/src/services/heic_to_jpeg.test.js backend/package.json backend/package-lock.json backend/test/fixtures/sample.heic
git commit -m "feat(ocr): add HEIC->JPEG normalization module

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 2: Wire HEIC normalization into the baptismal scan route

**Files:**
- Modify: `backend/src/routes/baptismal_ocr_firestore.js` (import + one conversion block near line 214)
- Modify: `backend/src/routes/baptismal_ocr_firestore.test.js` (add HEIC cases)

**Interfaces:**
- Consumes: `isHeic`, `heicToJpeg` from `../services/heic_to_jpeg` (Task 1).
- Behavior: a valid HEIC upload proceeds exactly as a JPEG would (200); an undecodable HEIC returns `IMAGE_INVALID`/400 and never calls `recognize`.

- [ ] **Step 1: Write the failing tests**

In `backend/src/routes/baptismal_ocr_firestore.test.js`, add near the top (after the existing `require`s):
```js
const fs = require('fs');
const pathlib = require('path');
const HEIC = fs.readFileSync(pathlib.join(__dirname, '..', '..', 'test', 'fixtures', 'sample.heic'));
```
Then add a new describe block at the end of the file (before the final closing lines):
```js
describe('HEIC upload support', () => {
  test('accepts a real HEIC upload and reaches recognition (200)', async () => {
    const recognize = jest.fn(async () => ({ words: [{ text: 'X', vertices: [], confidence: 1 }], fullText: 'X' }));
    const res = await request(appWith({ recognize })).post('/api/ocr/baptismal/scan')
      .send({ scanId: 's1', imageBase64: b64(HEIC) });
    expect(res.status).toBe(200);
    expect(res.body.success).toBe(true);
  }, 25000);

  test('rejects an undecodable HEIC with IMAGE_INVALID and never calls recognition', async () => {
    const fake = Buffer.concat([Buffer.from([0, 0, 0, 0x20]), Buffer.from('ftypheic'), Buffer.alloc(64, 0)]);
    const recognize = jest.fn(async () => ({ words: [], fullText: '' }));
    const res = await request(appWith({ recognize })).post('/api/ocr/baptismal/scan')
      .send({ scanId: 's1', imageBase64: b64(fake) });
    expect(res.status).toBe(400);
    expect(res.body.code).toBe('IMAGE_INVALID');
    expect(recognize).not.toHaveBeenCalled();
  });
});
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `cd backend && npx jest src/routes/baptismal_ocr_firestore.test.js -t "HEIC upload support"`
Expected: FAIL — the real HEIC is currently rejected at the `sniffImageType` gate with `IMAGE_INVALID`/400, so the "accepts a real HEIC" test fails on `expect(res.status).toBe(200)`.

- [ ] **Step 3: Add the import**

In `backend/src/routes/baptismal_ocr_firestore.js`, add to the requires at the top (near the other `../services/...` imports):
```js
const { isHeic, heicToJpeg } = require('../services/heic_to_jpeg');
```

- [ ] **Step 4: Insert the conversion block**

In the `/scan` handler, immediately AFTER the oversize check
`if (buffer.length > MAX_IMAGE_BYTES) return fail(res, 'IMAGE_TOO_LARGE', scanId);`
and BEFORE `const mime = sniffImageType(buffer);`, insert:
```js
      // iPhone uploads are HEIC by default. Convert once, here, before the
      // JPEG/PNG/WebP magic-byte gate and before the raw buffer is handed to
      // the Python CV grid service -- so nothing downstream ever sees HEIC.
      // An undecodable HEIC is a genuine bad-image case (IMAGE_INVALID), the
      // same class as any other file that can't be decoded.
      if (isHeic(buffer)) {
        try {
          buffer = await heicToJpeg(buffer);
        } catch (e) {
          return fail(res, 'IMAGE_INVALID', scanId);
        }
      }
```
Note: `buffer` is already declared with `let` (line ~199), so reassignment is valid.

- [ ] **Step 5: Run the tests to verify they pass**

Run: `cd backend && npx jest src/routes/baptismal_ocr_firestore.test.js`
Expected: PASS (all existing tests + the 2 new HEIC tests).

- [ ] **Step 6: Commit**

```bash
git add backend/src/routes/baptismal_ocr_firestore.js backend/src/routes/baptismal_ocr_firestore.test.js
git commit -m "feat(ocr): convert HEIC uploads on the baptismal scan route

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 3: Wire HEIC normalization into the generic `/api/ocr/scan` route

**Files:**
- Modify: `backend/src/routes/ocr_firestore.js` (refactor to an injectable factory + conversion)
- Modify: `backend/src/server.js:109` (mount `ocrRoutes.router`)
- Create: `backend/src/routes/ocr_firestore.test.js`

**Interfaces:**
- Consumes: `isHeic`, `heicToJpeg` (Task 1); `overlayToCells`, `callOcrSpace` (existing `ocrspace_service`).
- Produces: `createOcrRouter({ ocr })` where `ocr(imageBase64: string) => Promise<ocrSpaceJson>`; default `ocr` calls `callOcrSpace` with the env API key. Module also exports `router` (a default instance) for `server.js`.

- [ ] **Step 1: Write the failing test**

Create `backend/src/routes/ocr_firestore.test.js`:
```js
const fs = require('fs');
const path = require('path');
const express = require('express');
const request = require('supertest');
const { createOcrRouter } = require('./ocr_firestore');

const HEIC = fs.readFileSync(path.join(__dirname, '..', '..', 'test', 'fixtures', 'sample.heic'));
const b64 = (buf) => buf.toString('base64');
const OK_JSON = { ParsedResults: [{ ParsedText: 'hi', TextOverlay: { Lines: [] } }] };

function appWith(ocr) {
  const app = express();
  app.use(express.json({ limit: '20mb' }));
  app.use('/api/ocr', createOcrRouter({ ocr }));
  return app;
}

describe('POST /api/ocr/scan HEIC support', () => {
  test('passes JPEG straight through to the OCR backend', async () => {
    let seen;
    const ocr = async (imageBase64) => { seen = imageBase64; return OK_JSON; };
    const jpeg = Buffer.from([0xff, 0xd8, 0xff, 0xe0, 0, 0]);
    const res = await request(appWith(ocr)).post('/api/ocr/scan')
      .send({ imageBase64: b64(jpeg), recordType: 'baptism' });
    expect(res.status).toBe(200);
    expect(res.body.success).toBe(true);
    expect(seen).toBe(b64(jpeg)); // unchanged
  });

  test('converts a HEIC upload to JPEG before calling the OCR backend', async () => {
    let seen;
    const ocr = async (imageBase64) => { seen = imageBase64; return OK_JSON; };
    const res = await request(appWith(ocr)).post('/api/ocr/scan')
      .send({ imageBase64: b64(HEIC), recordType: 'baptism' });
    expect(res.status).toBe(200);
    const forwarded = Buffer.from(seen, 'base64');
    expect(forwarded[0]).toBe(0xff); // JPEG magic
    expect(forwarded[1]).toBe(0xd8);
    expect(forwarded[2]).toBe(0xff);
  }, 25000);

  test('rejects an undecodable HEIC with 400 and never calls the OCR backend', async () => {
    const ocr = jest.fn(async () => OK_JSON);
    const fake = Buffer.concat([Buffer.from([0, 0, 0, 0x20]), Buffer.from('ftypheic'), Buffer.alloc(64, 0)]);
    const res = await request(appWith(ocr)).post('/api/ocr/scan')
      .send({ imageBase64: b64(fake), recordType: 'baptism' });
    expect(res.status).toBe(400);
    expect(res.body.success).toBe(false);
    expect(ocr).not.toHaveBeenCalled();
  });
});
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `cd backend && npx jest src/routes/ocr_firestore.test.js`
Expected: FAIL — `createOcrRouter is not a function` (module currently exports only the router).

- [ ] **Step 3: Refactor the route to a factory with HEIC conversion**

Replace the entire contents of `backend/src/routes/ocr_firestore.js` with:
```js
const express = require('express');
const { body, validationResult } = require('express-validator');
const { callOcrSpace, overlayToCells } = require('../services/ocrspace_service');
const { isHeic, heicToJpeg } = require('../services/heic_to_jpeg');

function createOcrRouter(deps = {}) {
  const ocr = deps.ocr
    || ((imageBase64) => callOcrSpace(imageBase64, { apiKey: process.env.OCRSPACE_API_KEY }));

  const router = express.Router();

  router.post(
    '/scan',
    [
      body('imageBase64').isString().notEmpty(),
      body('recordType').isIn(['baptism', 'marriage']),
    ],
    async (req, res) => {
      const errors = validationResult(req);
      if (!errors.isEmpty()) {
        return res.status(400).json({ success: false, message: 'Invalid request', errors: errors.array() });
      }

      // iPhone uploads are HEIC by default; OCR.space only reads JPEG/PNG/WebP.
      // Convert here before forwarding. An undecodable HEIC is a bad image.
      let imageBase64 = req.body.imageBase64;
      const buffer = Buffer.from(imageBase64, 'base64');
      if (isHeic(buffer)) {
        try {
          imageBase64 = (await heicToJpeg(buffer)).toString('base64');
        } catch (e) {
          return res.status(400).json({ success: false, message: 'That file is not a supported image. Use JPEG, PNG, or WebP.' });
        }
      }

      try {
        const json = await ocr(imageBase64);
        const { text, cells } = overlayToCells(json);
        return res.json({ success: true, data: { text, cells, engine: 'ocrspace' } });
      } catch (e) {
        return res.status(502).json({ success: false, message: `OCR failed: ${e.message}` });
      }
    },
  );

  return router;
}

module.exports = { createOcrRouter, router: createOcrRouter() };
```

- [ ] **Step 4: Update the server mount**

In `backend/src/server.js`, line 109, change:
```js
app.use('/api/ocr', ocrRoutes);
```
to:
```js
app.use('/api/ocr', ocrRoutes.router);
```
(The `require('./routes/ocr_firestore')` at line 21 now yields `{ createOcrRouter, router }`; `.router` is the mounted instance.)

- [ ] **Step 5: Run the tests to verify they pass**

Run: `cd backend && npx jest src/routes/ocr_firestore.test.js`
Expected: PASS (3 tests).

- [ ] **Step 6: Run the full backend suite for regressions**

Run: `cd backend && npx jest`
Expected: PASS (all suites, including the server-mount-order test in `baptismal_ocr_firestore.test.js`).

- [ ] **Step 7: Commit**

```bash
git add backend/src/routes/ocr_firestore.js backend/src/routes/ocr_firestore.test.js backend/src/server.js
git commit -m "feat(ocr): convert HEIC uploads on the generic OCR scan route

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 4: Make `.heic`/`.heif` selectable and correctly labeled in the client picker

**Files:**
- Modify: `lib/services/ocr_image_pick.dart` (extension allow-list + mime mapping)
- Create: `test/services/ocr_image_pick_test.dart`

**Interfaces:**
- Produces: `OcrImagePick.mimeForExtension(String? ext) -> String` (was the private `_mimeForExtension`), annotated `@visibleForTesting`. Returns `image/heic` for `heic`/`heif`, `image/png` for `png`, `image/webp` for `webp`, `image/jpeg` otherwise.
- Behavior: on web/desktop the file picker offers `.heic`/`.heif` alongside jpg/png/webp so the OS dialog surfaces them (default `FileType.image` may hide HEIC on Windows).

- [ ] **Step 1: Write the failing test**

Create `test/services/ocr_image_pick_test.dart`:
```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:parishrecord/services/ocr_image_pick.dart';

void main() {
  group('OcrImagePick.mimeForExtension', () {
    test('maps heic and heif to image/heic', () {
      expect(OcrImagePick.mimeForExtension('heic'), 'image/heic');
      expect(OcrImagePick.mimeForExtension('HEIC'), 'image/heic');
      expect(OcrImagePick.mimeForExtension('heif'), 'image/heic');
    });

    test('keeps the existing image types', () {
      expect(OcrImagePick.mimeForExtension('png'), 'image/png');
      expect(OcrImagePick.mimeForExtension('webp'), 'image/webp');
      expect(OcrImagePick.mimeForExtension('jpg'), 'image/jpeg');
      expect(OcrImagePick.mimeForExtension('jpeg'), 'image/jpeg');
      expect(OcrImagePick.mimeForExtension(null), 'image/jpeg');
    });
  });
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `flutter test test/services/ocr_image_pick_test.dart`
Expected: FAIL — `mimeForExtension` is not defined (currently private `_mimeForExtension`).

- [ ] **Step 3: Expose and extend the mime mapping**

In `lib/services/ocr_image_pick.dart`:

(a) Add the `@visibleForTesting` import if not present (foundation is already imported via `package:flutter/foundation.dart` — `visibleForTesting` comes from `package:flutter/foundation.dart`, already imported).

(b) Rename `_mimeForExtension` to a testable method and add the HEIC branch:
```dart
  @visibleForTesting
  static String mimeForExtension(String? ext) {
    switch (ext?.toLowerCase()) {
      case 'png':
        return 'image/png';
      case 'webp':
        return 'image/webp';
      case 'heic':
      case 'heif':
        return 'image/heic';
      case 'jpg':
      case 'jpeg':
      default:
        return 'image/jpeg';
    }
  }
```

(c) Update the single caller (in `pickImages`) from `_mimeForExtension(f.extension)` to `mimeForExtension(f.extension)`.

- [ ] **Step 4: Make HEIC selectable in the file picker**

In `pickImages`, replace the `FilePicker.platform.pickFiles(...)` call's `type: FileType.image` with an explicit custom allow-list so the OS dialog surfaces `.heic`/`.heif` (notably on Windows, where `FileType.image` may not):
```dart
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['jpg', 'jpeg', 'png', 'webp', 'heic', 'heif'],
        allowMultiple: allowMultiple,
        withData: true,
      );
```
Leave the rest of `pickImages` (the `XFile.fromData` loop) unchanged.

- [ ] **Step 5: Run the test to verify it passes**

Run: `flutter test test/services/ocr_image_pick_test.dart`
Expected: PASS (2 tests).

- [ ] **Step 6: Analyze for regressions**

Run: `flutter analyze lib/services/ocr_image_pick.dart`
Expected: No new issues.

- [ ] **Step 7: Commit**

```bash
git add lib/services/ocr_image_pick.dart test/services/ocr_image_pick_test.dart
git commit -m "feat(ocr): allow HEIC/HEIF selection in the register photo picker

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Notes / decisions folded in

- **No scan-page change.** The baptismal scan page picks one image at a time (`allowMultiple: false`) and already handles `BaptismalOcrFailure` (`IMAGE_INVALID` → `OcrRecovery.differentImage`) by showing a clear error banner and returning to the preview step. That already satisfies the chosen "clear error, skip this file" fallback for a single-image flow — a multi-file batch-skip would be dead code.
- **No Python service change.** Conversion happens in Node before `fetchGrid(buffer)`, so the Python CV grid service only ever receives JPEG.
- **Mobile untouched.** `image_picker` transcodes HEIC→JPEG on pick (iOS) and the camera path is JPEG, so no HEIC reaches the backend from a phone.

## Self-review

- **Spec coverage:** backend module (Task 1) ✓; baptismal route (Task 2) ✓; generic route (Task 3) ✓; client selectable + labeled (Task 4) ✓; fallback = clear error + skip (folded in, existing behavior) ✓; tests for isHeic/heicToJpeg/route/mime ✓; `heic-convert` dependency ✓; no Python change ✓.
- **Placeholders:** none — every step has runnable commands/code.
- **Type consistency:** `isHeic`/`heicToJpeg` signatures identical across Tasks 1–3; `createOcrRouter({ ocr })` defined in Task 3 and mounted via `.router` in the same task; `mimeForExtension` defined and consumed within Task 4.
