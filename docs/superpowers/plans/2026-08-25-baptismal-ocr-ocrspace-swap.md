# Baptismal OCR — OCR.space Engine Swap Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the Google Cloud Vision OCR call in the existing, tested baptismal register OCR feature with an OCR.space call, feeding the identical normalized word shape into the unchanged layout pipeline.

**Architecture:** Only the OCR I/O boundary changes. `baptismal_ocr_service.js` stops calling Vision and instead calls OCR.space (Engine 1, which returns word bounding boxes) via the existing `ocrspace_service.js`, normalizing OCR.space's axis-aligned overlay boxes into the same `{ text, vertices:[TL,TR,BR,BL], confidence }` shape `baptismal_register_layout.js` already consumes. Because OCR.space has no per-word confidence, a scan-level banner replaces per-field confidence flagging. Everything downstream (layout, review UI, models, validation, storage) is reused unchanged.

**Tech Stack:** Node/Express + `sharp` + Jest (backend); Flutter + Riverpod + `http` + `flutter_test` (frontend). OCR.space HTTP API via `OCRSPACE_API_KEY`.

**Spec:** `docs/superpowers/specs/2026-08-25-baptismal-ocr-ocrspace-swap-design.md`

## Global Constraints

Every task's requirements implicitly include this section.

- **Branch:** all work lands on `feature/baptismal-ocr-record`. Never commit to `main`, `master`, `development`, or `ocr`.
- **Scope:** baptismal registers only. Do not implement or touch marriage/matrimonial OCR.
- **OCR.space key never reaches the client.** OCR.space is called only from `backend/src/services/baptismal_ocr_service.js` (via `ocrspace_service.js`). The key resolves from `OCRSPACE_API_KEY`.
- **Never log cell values or recognized text.** These are records of minors. Log counts, error codes, timings, and `scanId` (sanitized) only.
- **Backend response envelope:** `{ success: true, data: ... }` or `{ success: false, message: ..., code: ... }`. HTTP statuses per `STATUS_BY_CODE` are unchanged by this work.
- **Engine 1 is mandatory** for the baptismal path — it is the OCR.space engine that returns word bounding boxes. Engines 2/3 return text only and would break the geometry pipeline.
- **Do NOT modify** `baptismal_register_layout.js`, `baptismal_register_row.dart`, `baptismal_ocr_review_table.dart`, `baptismal_row_validation.dart`, `ocr_firestore.js`, `register_ocr_parser.dart`, or any `staff_ocr_*` page. `ocrspace_service.js` IS modified here (additive `engine` param) — this supersedes the older plan's do-not-touch note on it.
- **`docs/` is gitignored** but plan/spec files are tracked. Use `git add -f` for anything under `docs/`.
- **Dart style:** run `flutter analyze` before each Flutter commit; it must be clean.
- **Error codes are engine-neutral `OCR_*`** on the wire: `OCR_AUTH`, `OCR_QUOTA`, `OCR_UNAVAILABLE` (replacing the old `VISION_*`). `NO_TEXT_FOUND`, `LAYOUT_UNRECOGNIZED`, `IMAGE_INVALID`, `IMAGE_TOO_LARGE`, `INTERNAL_ERROR` are unchanged.

## Normalized word shape (the contract that must not change)

`extractBaptismalRows(words)` consumes a list of:

```js
{ text: 'TESTA', vertices: [ {x,y}, {x,y}, {x,y}, {x,y} ] /* TL,TR,BR,BL */, confidence: 1 }
```

## File Structure

**Backend — modify:**

| File | Change |
|------|--------|
| `backend/src/services/ocrspace_service.js` | Add optional `engine` param to `callOcrSpace` (default `'2'`). |
| `backend/src/services/ocrspace_service.test.js` | Assert engine param passthrough + default. |
| `backend/src/services/baptismal_ocr_service.js` | **Rewrite:** Vision I/O → OCR.space I/O producing the word shape; `OCR_*` error codes. |
| `backend/src/services/baptismal_ocr_service.test.js` | **Rewrite:** OCR.space fixtures + injected `fetchImpl`. |
| `backend/src/services/baptismal_image_preprocess.js` | `preprocessForOcr(buffer, opts)` gains `maxEdge`/`quality` opts (defaults preserve current behavior). |
| `backend/src/services/baptismal_image_preprocess.test.js` | Assert opts honored. |
| `backend/src/routes/baptismal_ocr_firestore.js` | Rename `VISION_*`→`OCR_*`; pass OCR.space size opts to preprocess; append `CONFIDENCE_UNAVAILABLE` warning. |
| `backend/src/routes/baptismal_ocr_firestore.test.js` | Update code names; assert `CONFIDENCE_UNAVAILABLE` in warnings. |

**Frontend — modify:**

| File | Change |
|------|--------|
| `lib/services/baptismal_ocr_service.dart` | Rename `VISION_*`→`OCR_*` in `_recoveryByCode`; update Vision→OCR.space comments. |
| `test/baptismal_ocr_service_test.dart` | Update code names. |
| `lib/screens/admin/pages/baptismal_ocr_scan_page.dart` | OCR.space processing text; scan-level confidence banner; keep `CONFIDENCE_UNAVAILABLE` out of the red warnings panel. |
| `test/baptismal_ocr_scan_page_test.dart` | Add confidence-banner tests. |

**Backend — create (validation only):** `backend/scripts/probe_ocrspace.js`.

---

### Task 1: Parameterize the OCR.space engine

**Files:**
- Modify: `backend/src/services/ocrspace_service.js`
- Test: `backend/src/services/ocrspace_service.test.js`

**Interfaces:**
- Produces: `callOcrSpace(imageBase64, { apiKey, fetchImpl, engine })` — `engine` optional, **defaults to `'2'`**; sent as the `OCREngine` form field.

- [ ] **Step 1: Update the existing tests to pin both default and override**

In `backend/src/services/ocrspace_service.test.js`, the first `callOcrSpace` test already asserts `OCREngine=2` with no engine passed — leave it. Add a new test after it:

```js
  test('honors an explicit engine and defaults to 2', async () => {
    const bodies = [];
    const fakeFetch = async (url, opts) => {
      bodies.push(opts.body);
      return { ok: true, json: async () => ({ ParsedResults: [{ ParsedText: 'ok' }] }) };
    };
    await callOcrSpace('X', { apiKey: 'K', fetchImpl: fakeFetch, engine: '1' });
    await callOcrSpace('X', { apiKey: 'K', fetchImpl: fakeFetch });
    expect(bodies[0]).toContain('OCREngine=1');
    expect(bodies[1]).toContain('OCREngine=2');
  });
```

- [ ] **Step 2: Run to verify it fails**

Run: `cd backend && npx jest src/services/ocrspace_service.test.js -t "honors an explicit engine"`
Expected: FAIL — `bodies[0]` contains `OCREngine=2` (engine is currently hardcoded).

- [ ] **Step 3: Implement**

In `backend/src/services/ocrspace_service.js`, change the signature and the `OCREngine` line:

```js
async function callOcrSpace(imageBase64, { apiKey, fetchImpl = fetch, engine = '2' } = {}) {
```

```js
  params.append('OCREngine', String(engine));
```

- [ ] **Step 4: Run tests**

Run: `cd backend && npx jest src/services/ocrspace_service.test.js`
Expected: PASS (all, including the new test).

- [ ] **Step 5: Commit**

```bash
git add backend/src/services/ocrspace_service.js backend/src/services/ocrspace_service.test.js
git commit -m "feat(ocr): allow selecting the OCR.space engine (default 2)"
```

---

### Task 2: Rewrite the OCR service to call OCR.space

**Files:**
- Modify (rewrite): `backend/src/services/baptismal_ocr_service.js`
- Test (rewrite): `backend/src/services/baptismal_ocr_service.test.js`

**Interfaces:**
- Consumes: `callOcrSpace`, `overlayToCells` (Task 1 / `ocrspace_service.js`).
- Produces: `recognizeWords(imageBuffer, { apiKey, fetchImpl, env } = {})` → `Promise<{ words, fullText }>`. `words[i] = { text, vertices:[TL,TR,BR,BL], confidence: 1 }`. Throws errors carrying `.code ∈ OCR_AUTH | OCR_QUOTA | OCR_UNAVAILABLE | NO_TEXT_FOUND`. The old `resolveVisionCredentials` export is removed.

- [ ] **Step 1: Replace the test file**

Overwrite `backend/src/services/baptismal_ocr_service.test.js` with:

```js
const { recognizeWords } = require('./baptismal_ocr_service');

// OCR.space overlay response with two words on one line.
const okResponse = {
  ParsedResults: [
    {
      ParsedText: 'TESTA SAMPLE',
      TextOverlay: {
        Lines: [
          {
            Words: [
              { WordText: 'TESTA', Left: 120, Top: 100, Width: 60, Height: 22 },
              { WordText: 'SAMPLE', Left: 190, Top: 100, Width: 90, Height: 22 },
            ],
          },
        ],
      },
    },
  ],
};

const fetchReturning = (json, ok = true) => async () => ({ ok, status: ok ? 200 : 500, json: async () => json });

describe('recognizeWords (OCR.space)', () => {
  test('normalizes overlay words to text + TL,TR,BR,BL vertices + confidence 1', async () => {
    const { words, fullText } = await recognizeWords(Buffer.from('x'), {
      apiKey: 'K', env: {}, fetchImpl: fetchReturning(okResponse),
    });
    expect(fullText).toBe('TESTA SAMPLE');
    expect(words).toHaveLength(2);
    expect(words[0].text).toBe('TESTA');
    expect(words[0].confidence).toBe(1);
    // Axis-aligned box (L,T,W,H) -> TL,TR,BR,BL.
    expect(words[0].vertices).toEqual([
      { x: 120, y: 100 }, { x: 180, y: 100 }, { x: 180, y: 122 }, { x: 120, y: 122 },
    ]);
  });

  test('throws NO_TEXT_FOUND when the overlay has no words', async () => {
    const empty = { ParsedResults: [{ ParsedText: '' }] };
    await expect(
      recognizeWords(Buffer.from('x'), { apiKey: 'K', env: {}, fetchImpl: fetchReturning(empty) }),
    ).rejects.toMatchObject({ code: 'NO_TEXT_FOUND' });
  });

  test('throws OCR_AUTH when no key is configured', async () => {
    await expect(
      recognizeWords(Buffer.from('x'), { env: {}, fetchImpl: fetchReturning(okResponse) }),
    ).rejects.toMatchObject({ code: 'OCR_AUTH' });
  });

  test('maps an OCR.space rate-limit message to OCR_QUOTA', async () => {
    const errJson = { IsErroredOnProcessing: true, ErrorMessage: ['You have exceeded your concurrent connections / rate limit'] };
    await expect(
      recognizeWords(Buffer.from('x'), { apiKey: 'K', env: {}, fetchImpl: fetchReturning(errJson) }),
    ).rejects.toMatchObject({ code: 'OCR_QUOTA' });
  });

  test('maps a network failure to OCR_UNAVAILABLE', async () => {
    const fetchImpl = async () => { throw new Error('socket hang up'); };
    await expect(
      recognizeWords(Buffer.from('x'), { apiKey: 'K', env: {}, fetchImpl }),
    ).rejects.toMatchObject({ code: 'OCR_UNAVAILABLE' });
  });

  test('maps an HTTP error to OCR_UNAVAILABLE', async () => {
    await expect(
      recognizeWords(Buffer.from('x'), { apiKey: 'K', env: {}, fetchImpl: fetchReturning({}, false) }),
    ).rejects.toMatchObject({ code: 'OCR_UNAVAILABLE' });
  });
});
```

- [ ] **Step 2: Run to verify it fails**

Run: `cd backend && npx jest src/services/baptismal_ocr_service.test.js`
Expected: FAIL — old export shape / Vision assertions gone; `recognizeWords` not yet OCR.space-based.

- [ ] **Step 3: Rewrite the service**

Overwrite `backend/src/services/baptismal_ocr_service.js` with:

```js
/**
 * OCR.space I/O for baptismal register scans.
 *
 * This module is the ONLY place OCR.space is called for baptismal scans. It
 * performs no layout analysis (see baptismal_register_layout.js) and never
 * lets the API key reach the client. It normalizes OCR.space's axis-aligned
 * word overlay into the { text, vertices:[TL,TR,BR,BL], confidence } shape the
 * layout pipeline consumes.
 *
 * Engine 1 is required: it is the OCR.space engine that returns word bounding
 * boxes. Engines 2/3 return text only, which the geometry pipeline can't use.
 */

const { callOcrSpace, overlayToCells } = require('./ocrspace_service');

function codedError(message, code) {
  const err = new Error(message);
  err.code = code;
  return err;
}

// callOcrSpace throws plain Errors; classify them by message into the wire
// codes the route maps to HTTP statuses. A missing key is a server
// misconfiguration (OCR_AUTH). Rate/quota messages are transient (OCR_QUOTA).
// Everything else (network, HTTP, unknown processing error) is treated as a
// reach-the-service problem (OCR_UNAVAILABLE, retryable).
function mapOcrSpaceError(err) {
  const msg = String((err && err.message) || '');
  if (/OCRSPACE_API_KEY/i.test(msg)) {
    return codedError('OCR_AUTH: OCR.space key is not configured', 'OCR_AUTH');
  }
  if (/quota|exceeded|rate ?limit|too many|throttl/i.test(msg)) {
    return codedError('OCR_QUOTA: OCR.space rate limit reached', 'OCR_QUOTA');
  }
  return codedError('OCR_UNAVAILABLE: could not reach OCR.space', 'OCR_UNAVAILABLE');
}

/**
 * Runs OCR.space Engine 1 on the prepared image and normalizes the response.
 * @returns {Promise<{words: Array, fullText: string}>}
 */
async function recognizeWords(imageBuffer, options = {}) {
  const env = options.env || process.env;
  const apiKey = options.apiKey || env.OCRSPACE_API_KEY;

  let json;
  try {
    json = await callOcrSpace(imageBuffer.toString('base64'), {
      apiKey,
      fetchImpl: options.fetchImpl,
      engine: '1',
    });
  } catch (e) {
    throw mapOcrSpaceError(e);
  }

  const { text, cells } = overlayToCells(json);
  if (!cells || cells.length === 0) {
    throw codedError('NO_TEXT_FOUND: OCR.space returned no word boxes', 'NO_TEXT_FOUND');
  }

  const words = cells.map((c) => ({
    text: c.text,
    vertices: [
      { x: c.left, y: c.top },
      { x: c.left + c.width, y: c.top },
      { x: c.left + c.width, y: c.top + c.height },
      { x: c.left, y: c.top + c.height },
    ],
    confidence: 1,
  }));

  return { words, fullText: text || '' };
}

module.exports = { recognizeWords };
```

- [ ] **Step 4: Run tests**

Run: `cd backend && npx jest src/services/baptismal_ocr_service.test.js`
Expected: PASS — 6 tests.

- [ ] **Step 5: Commit**

```bash
git add backend/src/services/baptismal_ocr_service.js backend/src/services/baptismal_ocr_service.test.js
git commit -m "feat(ocr): recognize baptismal register words via OCR.space"
```

---

### Task 3: Route — rename codes and emit the confidence warning

**Files:**
- Modify: `backend/src/routes/baptismal_ocr_firestore.js`
- Test: `backend/src/routes/baptismal_ocr_firestore.test.js`

**Interfaces:**
- Consumes: `recognizeWords` (Task 2) throwing `OCR_*` codes.
- Produces: success response `data.warnings` always includes `'CONFIDENCE_UNAVAILABLE'`; error codes `OCR_AUTH`/`OCR_QUOTA`/`OCR_UNAVAILABLE` map to 500/429/502.

- [ ] **Step 1: Update the route tests**

In `backend/src/routes/baptismal_ocr_firestore.test.js`:

Replace the `test.each` code list:

```js
  test.each([
    ['OCR_AUTH', 500],
    ['OCR_QUOTA', 429],
    ['OCR_UNAVAILABLE', 502],
    ['NO_TEXT_FOUND', 422],
  ])('maps %s to HTTP %i', async (code, status) => {
```

Replace the two `failure('VISION_QUOTA')` usages (in "never echoes cell values in an error body" and any other) with `failure('OCR_QUOTA')`.

Add a warning assertion inside the existing "returns extracted rows for a valid JPEG" test, after the `warnings` expectation — note `extract()` returns `['GUTTER_UNCONFIRMED']` and the route now appends the confidence code:

```js
    expect(data.warnings).toEqual(['GUTTER_UNCONFIRMED', 'CONFIDENCE_UNAVAILABLE']);
```

(remove the prior `expect(data.warnings).toEqual(['GUTTER_UNCONFIRMED'])` line it replaces.)

- [ ] **Step 2: Run to verify it fails**

Run: `cd backend && npx jest src/routes/baptismal_ocr_firestore.test.js`
Expected: FAIL — `OCR_*` codes unmapped; warnings missing `CONFIDENCE_UNAVAILABLE`.

- [ ] **Step 3: Implement — rename codes**

In `backend/src/routes/baptismal_ocr_firestore.js`, rename the three keys in **both** `STATUS_BY_CODE` and `MESSAGE_BY_CODE` (`VISION_AUTH`→`OCR_AUTH`, `VISION_QUOTA`→`OCR_QUOTA`, `VISION_UNAVAILABLE`→`OCR_UNAVAILABLE`), keeping their existing values/messages. HTTP statuses stay 500/429/502.

- [ ] **Step 4: Implement — append the confidence warning**

In the success `res.json(...)`, change the warnings field so OCR.space's lack of per-word confidence is always signalled:

```js
        return res.json({
          success: true,
          data: {
            scanId,
            rows: result.rows,
            rotation: result.rotation,
            // OCR.space returns no per-word confidence, so the per-field
            // low-confidence flag can't fire. Signal the review UI to show a
            // scan-level "verify every field" banner instead.
            warnings: [...result.warnings, 'CONFIDENCE_UNAVAILABLE'],
          },
        });
```

- [ ] **Step 5: Run tests**

Run: `cd backend && npx jest src/routes/baptismal_ocr_firestore.test.js`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add backend/src/routes/baptismal_ocr_firestore.js backend/src/routes/baptismal_ocr_firestore.test.js
git commit -m "feat(ocr): OCR_* error codes and scan-level confidence warning"
```

---

### Task 4: Bound the OCR-bound image size for OCR.space

**Files:**
- Modify: `backend/src/services/baptismal_image_preprocess.js`
- Modify: `backend/src/routes/baptismal_ocr_firestore.js`
- Test: `backend/src/services/baptismal_image_preprocess.test.js`

**Interfaces:**
- Produces: `preprocessForOcr(buffer, { maxEdge, quality } = {})` — options default to the current `MAX_EDGE` (4096) and quality 92, so existing callers are unaffected. The baptismal route passes smaller values to stay under OCR.space's upload limit.

- [ ] **Step 1: Write the failing test**

Append to `backend/src/services/baptismal_image_preprocess.test.js`:

```js
const sharp = require('sharp');
const { preprocessForOcr } = require('./baptismal_image_preprocess');

test('preprocessForOcr honors a maxEdge option', async () => {
  const src = await sharp({
    create: { width: 3000, height: 2000, channels: 3, background: { r: 128, g: 128, b: 128 } },
  }).jpeg().toBuffer();

  const out = await preprocessForOcr(src, { maxEdge: 1000, quality: 70 });
  const meta = await sharp(out).metadata();
  expect(Math.max(meta.width, meta.height)).toBeLessThanOrEqual(1000);
});
```

- [ ] **Step 2: Run to verify it fails**

Run: `cd backend && npx jest src/services/baptismal_image_preprocess.test.js -t "honors a maxEdge"`
Expected: FAIL — options are ignored (fixed 4096 output ≥ 1000 only by luck; the 3000px source resizes to 3000, > 1000).

- [ ] **Step 3: Implement**

In `baptismal_image_preprocess.js`, change `preprocessForOcr` to accept options (defaults preserve behavior):

```js
async function preprocessForOcr(buffer, { maxEdge = MAX_EDGE, quality = 92 } = {}) {
```

and use them in the pipeline:

```js
    return await sharp(buffer, { limitInputPixels: MAX_INPUT_PIXELS })
      .rotate() // honour EXIF orientation
      .resize({ width: maxEdge, height: maxEdge, fit: 'inside', withoutEnlargement: true })
      .grayscale()
      .normalize()
      .sharpen()
      .jpeg({ quality })
      .toBuffer();
```

- [ ] **Step 4: Pass OCR.space-tuned values from the route**

In `baptismal_ocr_firestore.js`, define constants near the top (after `ACCEPTED`) and use them at the `preprocess` call. These starting values keep a grayscale JPEG comfortably under OCR.space's ~1 MB upload limit; Task 7 validates/tunes them:

```js
// OCR.space (registered free tier) caps uploads near 1 MB. A grayscale JPEG
// at these bounds stays well under that while preserving enough detail for
// Engine 1 to read register handwriting. Tuned against attachments/IMG_3120.
const OCRSPACE_MAX_EDGE = 2500;
const OCRSPACE_JPEG_QUALITY = 80;
```

```js
        const prepared = await preprocess(buffer, {
          maxEdge: OCRSPACE_MAX_EDGE,
          quality: OCRSPACE_JPEG_QUALITY,
        });
```

- [ ] **Step 5: Run tests**

Run: `cd backend && npx jest baptismal`
Expected: PASS — the whole baptismal suite (the route test's injected/real preprocess still works; the tiny fixtures are unaffected by the smaller cap).

- [ ] **Step 6: Commit**

```bash
git add backend/src/services/baptismal_image_preprocess.js backend/src/services/baptismal_image_preprocess.test.js backend/src/routes/baptismal_ocr_firestore.js
git commit -m "feat(ocr): bound OCR-bound image size for OCR.space upload limits"
```

---

### Task 5: Flutter client — rename error codes

**Files:**
- Modify: `lib/services/baptismal_ocr_service.dart`
- Test: `test/baptismal_ocr_service_test.dart`

**Interfaces:**
- Consumes: backend `OCR_*` codes (Task 3).
- Produces: `_recoveryByCode` maps `OCR_QUOTA`/`OCR_UNAVAILABLE`→retry and `OCR_AUTH`→contactAdmin (behavior identical to before, code strings renamed).

- [ ] **Step 1: Update the tests**

In `test/baptismal_ocr_service_test.dart`, replace every `VISION_QUOTA`→`OCR_QUOTA`, `VISION_UNAVAILABLE`→`OCR_UNAVAILABLE`, `VISION_AUTH`→`OCR_AUTH` (in the `serviceReturning(...)` bodies, the `.having((f) => f.code, ...)` matchers, and the test names/descriptions in the `OcrRecovery mapping` group).

- [ ] **Step 2: Run to verify it fails**

Run: `flutter test test/baptismal_ocr_service_test.dart`
Expected: FAIL — client still maps `OCR_*` via the default `retry`, so `OCR_AUTH` yields `retryable: true` where the updated test expects `false`.

- [ ] **Step 3: Implement**

In `lib/services/baptismal_ocr_service.dart`, in `_recoveryByCode` rename the three keys:

```dart
    'OCR_QUOTA': OcrRecovery.retry,
    'OCR_UNAVAILABLE': OcrRecovery.retry,
```

```dart
    'OCR_AUTH': OcrRecovery.contactAdmin,
```

Update the doc comment above `_recoveryByCode` and the class-level doc comment so they say OCR.space instead of Vision (e.g. class doc: `/// Sends register photos to the backend OCR.space proxy.` and `/// OCR.space credentials live on the server; this client only ever sees the`; in the map comment replace the `VISION_QUOTA, VISION_UNAVAILABLE` / `VISION_AUTH` references with `OCR_QUOTA, OCR_UNAVAILABLE` / `OCR_AUTH` and "Vision is deterministic" → "OCR is deterministic").

- [ ] **Step 4: Run tests + analyze**

Run: `flutter test test/baptismal_ocr_service_test.dart && flutter analyze lib/services/baptismal_ocr_service.dart`
Expected: PASS; analyze clean.

- [ ] **Step 5: Commit**

```bash
git add lib/services/baptismal_ocr_service.dart test/baptismal_ocr_service_test.dart
git commit -m "refactor(ocr): rename VISION_* client codes to OCR_*"
```

---

### Task 6: Scan page — OCR.space wording and the confidence banner

**Files:**
- Modify: `lib/screens/admin/pages/baptismal_ocr_scan_page.dart`
- Test: `test/baptismal_ocr_scan_page_test.dart`

**Interfaces:**
- Consumes: `BaptismalOcrScan.warnings` containing `'CONFIDENCE_UNAVAILABLE'` (Task 3).
- Produces: a review-step info banner keyed `ValueKey('confidence-banner')`; `CONFIDENCE_UNAVAILABLE` never appears in the red `_warningsPanel`.

- [ ] **Step 1: Write the failing tests**

Add to `test/baptismal_ocr_scan_page_test.dart` (reuses the file's `harness`, `serviceReturning`, `_png`, and `_scanBody` helpers). Add a body builder with warnings at the top of the file next to `_scanBody`:

```dart
Map<String, dynamic> _scanBodyWithWarnings(List<String> warnings) {
  final body = _scanBody();
  (body['data'] as Map<String, dynamic>)['warnings'] = warnings;
  return body;
}
```

Then add tests:

```dart
  testWidgets('shows the confidence banner when CONFIDENCE_UNAVAILABLE is present', (tester) async {
    final svc = serviceReturning(200, _scanBodyWithWarnings(['CONFIDENCE_UNAVAILABLE']));
    await tester.pumpWidget(harness(service: svc));
    await tester.tap(find.byKey(const ValueKey('pick-image')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Scan / Process OCR'));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('confidence-banner')), findsOneWidget);
    // It must NOT be rendered inside the red "Review these before saving" panel.
    expect(find.text('Review these before saving'), findsNothing);
  });

  testWidgets('keeps CONFIDENCE_UNAVAILABLE out of the red warnings panel but still shows layout warnings', (tester) async {
    final svc = serviceReturning(
      200,
      _scanBodyWithWarnings(['GUTTER_UNCONFIRMED', 'CONFIDENCE_UNAVAILABLE']),
    );
    await tester.pumpWidget(harness(service: svc));
    await tester.tap(find.byKey(const ValueKey('pick-image')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Scan / Process OCR'));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('confidence-banner')), findsOneWidget);
    expect(find.text('Review these before saving'), findsOneWidget);
  });
```

- [ ] **Step 2: Run to verify it fails**

Run: `flutter test test/baptismal_ocr_scan_page_test.dart -j 1`
Expected: FAIL — no `confidence-banner`; the red panel currently renders whenever `_warnings.isNotEmpty` (including for the confidence-only case).

- [ ] **Step 3: Implement — processing text**

In `_processingStep()`, change the text `'Reading the register with Google Cloud Vision...'` to `'Reading the register with OCR.space...'`.

- [ ] **Step 4: Implement — filter warnings and add the banner**

In `_reviewStep()`, replace the two leading conditional children:

```dart
        if (_warnings.isNotEmpty) _warningsPanel(context),
        if (_archiveFailed) _archiveFailedNotice(context),
```

with:

```dart
        if (_warnings.contains('CONFIDENCE_UNAVAILABLE'))
          _confidenceBanner(context),
        if (_layoutWarnings.isNotEmpty) _warningsPanel(context, _layoutWarnings),
        if (_archiveFailed) _archiveFailedNotice(context),
```

Add a getter next to `_issues`:

```dart
  /// Layout warnings only — the confidence notice is surfaced by its own
  /// banner, not the red "review these before saving" panel.
  List<String> get _layoutWarnings =>
      _warnings.where((c) => c != 'CONFIDENCE_UNAVAILABLE').toList();
```

Change `_warningsPanel` to take the codes it renders:

```dart
  Widget _warningsPanel(BuildContext context, List<String> codes) {
```

and change its `for (final code in _warnings)` loop to `for (final code in codes)`.

Add the banner widget (info-styled, distinct from the red panel) after `_warningsPanel`:

```dart
  /// OCR.space returns no per-field confidence, so there is nothing to flag
  /// cell-by-cell. This scan-level banner tells the reviewer to verify every
  /// field before saving.
  Widget _confidenceBanner(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      key: const ValueKey('confidence-banner'),
      margin: const EdgeInsets.fromLTRB(12, 12, 12, 0),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.secondaryContainer,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: scheme.outline),
      ),
      child: Row(
        children: [
          Icon(Icons.fact_check_outlined, color: scheme.onSecondaryContainer),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'This OCR engine cannot score confidence. Please verify every '
              'field against the page before saving.',
              style: TextStyle(color: scheme.onSecondaryContainer),
            ),
          ),
        ],
      ),
    );
  }
```

- [ ] **Step 5: Run tests + analyze**

Run: `flutter test test/baptismal_ocr_scan_page_test.dart -j 1 && flutter analyze lib/screens/admin/pages/baptismal_ocr_scan_page.dart`
Expected: PASS; analyze clean.

- [ ] **Step 6: Commit**

```bash
git add lib/screens/admin/pages/baptismal_ocr_scan_page.dart test/baptismal_ocr_scan_page_test.dart
git commit -m "feat(ocr): OCR.space wording and scan-level confidence banner"
```

---

### Task 7: Validate on the real sample images (Engine 1 overlay, orientation, accuracy)

This task produces **evidence**, not a behavior change beyond tuning constants. It requires network access and a real `OCRSPACE_API_KEY` in `backend/.env`, so it is run by the human/executor, not the automated suite. It directly addresses the spec's three risks.

**Files:**
- Create: `backend/scripts/probe_ocrspace.js`

- [ ] **Step 1: Write the probe script**

Create `backend/scripts/probe_ocrspace.js`:

```js
/**
 * One-off local validation: runs the real OCR.space path on a sample register
 * image and reports STRUCTURE ONLY (counts, rotation, per-field populated
 * flags) -- never dumps recognized values, which are records of minors.
 *
 * Usage: node backend/scripts/probe_ocrspace.js attachments/IMG_3120.jpeg
 * Requires OCRSPACE_API_KEY in backend/.env (loaded via dotenv) and network.
 */
require('dotenv').config({ path: require('path').join(__dirname, '..', '.env') });
const fs = require('fs');
const { preprocessForOcr } = require('../src/services/baptismal_image_preprocess');
const { recognizeWords } = require('../src/services/baptismal_ocr_service');
const { extractBaptismalRows } = require('../src/services/baptismal_register_layout');

(async () => {
  const file = process.argv[2] || 'attachments/IMG_3120.jpeg';
  const raw = fs.readFileSync(file);
  const prepared = await preprocessForOcr(raw, { maxEdge: 2500, quality: 80 });
  console.log(`prepared bytes: ${prepared.length} (base64 ~${Math.round(prepared.length * 1.34 / 1024)}KB)`);

  const { words } = await recognizeWords(prepared);
  console.log(`words with boxes: ${words.length}`); // Risk 1: must be > 0

  const result = extractBaptismalRows(words);
  console.log(`rotation detected: ${result.rotation}`); // Risk 2
  console.log(`rows detected: ${result.rows.length}`);
  console.log(`warnings: ${result.warnings.join(', ') || '(none)'}`);
  for (const row of result.rows) {
    const populated = Object.entries(row.fields)
      .filter(([, f]) => f && f.value && f.value.trim())
      .map(([k]) => k);
    console.log(`  line ${row.lineNo}: ${populated.length} fields -> ${populated.join(', ')}`);
  }
})().catch((e) => { console.error(`probe failed: ${e.code || ''} ${e.message}`); process.exit(1); });
```

- [ ] **Step 2: Run the probe on all three samples**

Run:
```bash
cd backend && node scripts/probe_ocrspace.js attachments/IMG_3120.jpeg
node scripts/probe_ocrspace.js attachments/IMG_3121.jpeg
node scripts/probe_ocrspace.js attachments/IMG_3122.jpeg
```

Record for each: prepared size, `words with boxes` (**Risk 1: must be > 0** — if 0, Engine 1 returned no overlay; stop and reassess), `rotation detected` (**Risk 2**: on the sideways spreads, confirm the rows/fields still populate sensibly), `rows detected`, and which fields populate per row.

- [ ] **Step 3: Tune if needed**

- If uploads are rejected as too large, lower `OCRSPACE_MAX_EDGE`/`OCRSPACE_JPEG_QUALITY` in `baptismal_ocr_firestore.js` (and the probe) and re-run.
- If the sideways spread reads as rotation 0 but fields land in the wrong columns (Risk 2 realized), add content-based rotation to the OCR-bound preprocess copy (a `.rotate(90|180|270)` chosen from OCR.space's detected orientation, or a portrait/landscape heuristic on the source aspect ratio) — implement as a follow-on step here with its own preprocess test, since the layout module must not change.
- Note findings honestly in the commit message; if OCR.space Engine 1 is materially worse than Vision on these images, surface that to the user rather than declaring success.

- [ ] **Step 4: Commit the script and findings**

```bash
git add backend/scripts/probe_ocrspace.js
git commit -m "test(ocr): add OCR.space sample-image validation probe

Findings on attachments/IMG_3120-3122: <fill in words/rotation/rows per image>."
```

- [ ] **Step 5: Full regression**

Run: `cd backend && npx jest && cd .. && flutter analyze && flutter test`
Expected: backend suite green (incl. baptismal), `flutter analyze` clean, Flutter suite green.

---

## Self-Review Notes

- **Spec coverage:** §1 service rewrite → Task 2; §2 test rewrite → Task 2; §3 preprocess size → Task 4; §4 code rename → Tasks 3 & 5; §5 confidence banner → Tasks 3 (warning) & 6 (UI); §6 entry points → admin already wired (staff entry deferred per spec default; no task); engine param prerequisite → Task 1; validation/Risks 1–3 → Task 7. Vision-removal is an explicit non-goal (left dormant).
- **Placeholder scan:** the only "fill in" is Task 7's commit message findings, which are runtime evidence by design.
- **Type consistency:** `recognizeWords(imageBuffer, { apiKey, fetchImpl, env })` and the `{text, vertices, confidence}` word shape are consistent across Tasks 2/3/7; `preprocessForOcr(buffer, { maxEdge, quality })` consistent across Tasks 4/7; `OCR_AUTH|OCR_QUOTA|OCR_UNAVAILABLE` consistent across Tasks 2/3/5; `_warningsPanel(context, codes)` and `_layoutWarnings`/`_confidenceBanner` consistent within Task 6.
