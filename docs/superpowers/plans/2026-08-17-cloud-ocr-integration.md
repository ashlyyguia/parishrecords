# Cloud OCR Integration (OCR.space) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make handwriting-capable OCR.space the primary register-scan engine via a backend proxy, feeding the existing `parseEntriesFromCells` seam, with on-device ML Kit as automatic fallback.

**Architecture:** Flutter downscales the photo and POSTs it to a new `/api/ocr/scan` Express endpoint; the backend calls OCR.space (key in `.env`) and returns normalized `{ text, cells[] }`; Flutter maps cells to `OcrLineBox` → `RegisterOcrScanHelper.scanResultFromCloud` → the existing review UI. Any cloud failure falls back to the current on-device path.

**Tech Stack:** Node 20 / Express (global `fetch`, no new runtime deps), Jest + supertest (backend tests); Flutter/Dart, `package:http`, `firebase_auth`, pure-Dart `image` (downscale), `flutter_test`.

## Global Constraints

- OCR.space key lives ONLY in backend `process.env.OCRSPACE_API_KEY` — never in the client, never logged, never committed.
- Backend normalizes only; the Dart parser stays the single source of truth. Do NOT port parsing logic to Node.
- Engine strategy: cloud primary, on-device fallback on ANY failure (offline / non-2xx / timeout / empty).
- No new backend RUNTIME dependency (use Node 20 global `fetch`); `supertest` may be added as a devDependency for tests.
- Downscale before upload: resize long edge to ≤2000px, JPEG quality 85, resize-only (no grayscale/contrast/sharpen — aggressive enhance measurably hurt recognition).
- Response shapes: success `{ success: true, data: { text, cells, engine } }`; failure `{ success: false, message }`.
- Flutter API calls use `package:http` with headers `{ 'Content-Type': 'application/json', 'Authorization': 'Bearer <firebase idToken>' }` against `BackendConfig.apiBaseUrl`.
- Backend tests: `*.test.js` run by `npm test` (from `backend/`). Flutter tests live under `test/ocr/`, run with `flutter test test/ocr/...`. Flutter package name is `parishrecord`.

---

### Task 1: Backend OCR.space service (call + normalize)

Pure, network-free-testable core: build the OCR.space request and convert its word overlay to generic cells.

**Files:**
- Create: `backend/src/services/ocrspace_service.js`
- Test: `backend/src/services/ocrspace_service.test.js`

**Interfaces:**
- Produces:
  - `overlayToCells(ocrSpaceJson) -> { text: string, cells: Array<{text,left,top,width,height}> }`
  - `async callOcrSpace(imageBase64, { apiKey, fetchImpl = fetch }) -> ocrSpaceJson` — throws on missing key, non-2xx, or `IsErroredOnProcessing`.

- [ ] **Step 1: Write the failing test**

Create `backend/src/services/ocrspace_service.test.js`:

```js
const { overlayToCells, callOcrSpace } = require('./ocrspace_service');

describe('overlayToCells', () => {
  test('maps word overlay to cells and text', () => {
    const sample = {
      ParsedResults: [
        {
          ParsedText: 'ALBERTO SALIGUMBA',
          TextOverlay: {
            Lines: [
              {
                Words: [
                  { WordText: 'ALBERTO', Left: 120, Top: 100, Width: 80, Height: 20 },
                  { WordText: 'SALIGUMBA', Left: 210, Top: 100, Width: 90, Height: 20 },
                ],
              },
            ],
          },
        },
      ],
    };
    const { text, cells } = overlayToCells(sample);
    expect(text).toBe('ALBERTO SALIGUMBA');
    expect(cells).toHaveLength(2);
    expect(cells[0]).toEqual({ text: 'ALBERTO', left: 120, top: 100, width: 80, height: 20 });
  });

  test('handles missing overlay and empty words', () => {
    expect(overlayToCells({}).cells).toEqual([]);
    expect(overlayToCells({ ParsedResults: [{ ParsedText: 'x' }] })).toEqual({ text: 'x', cells: [] });
    const blank = { ParsedResults: [{ TextOverlay: { Lines: [{ Words: [{ WordText: '  ', Left: 1, Top: 1, Width: 1, Height: 1 }] }] } }] };
    expect(overlayToCells(blank).cells).toEqual([]);
  });
});

describe('callOcrSpace', () => {
  test('posts required params and returns parsed json', async () => {
    let captured;
    const fakeFetch = async (url, opts) => {
      captured = { url, opts };
      return { ok: true, json: async () => ({ ParsedResults: [{ ParsedText: 'ok' }] }) };
    };
    const json = await callOcrSpace('BASE64DATA', { apiKey: 'K', fetchImpl: fakeFetch });
    expect(json.ParsedResults[0].ParsedText).toBe('ok');
    expect(captured.url).toContain('ocr.space');
    expect(captured.opts.body).toContain('apikey=K');
    expect(captured.opts.body).toContain('OCREngine=2');
    expect(captured.opts.body).toContain('isOverlayRequired=true');
  });

  test('throws on processing error', async () => {
    const fakeFetch = async () => ({ ok: true, json: async () => ({ IsErroredOnProcessing: true, ErrorMessage: ['bad'] }) });
    await expect(callOcrSpace('X', { apiKey: 'K', fetchImpl: fakeFetch })).rejects.toThrow('bad');
  });

  test('throws when apiKey missing', async () => {
    await expect(callOcrSpace('X', { fetchImpl: async () => ({}) })).rejects.toThrow('OCRSPACE_API_KEY');
  });
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd backend && npx jest src/services/ocrspace_service.test.js`
Expected: FAIL — module `./ocrspace_service` not found.

- [ ] **Step 3: Implement the service**

Create `backend/src/services/ocrspace_service.js`:

```js
const OCR_SPACE_URL = 'https://api.ocr.space/parse/image';

function overlayToCells(ocrSpaceJson) {
  const result = (ocrSpaceJson && ocrSpaceJson.ParsedResults && ocrSpaceJson.ParsedResults[0]) || {};
  const text = result.ParsedText || '';
  const lines = (result.TextOverlay && result.TextOverlay.Lines) || [];
  const cells = [];
  for (const line of lines) {
    for (const w of line.Words || []) {
      const t = (w.WordText || '').trim();
      if (!t) continue;
      cells.push({
        text: t,
        left: Number(w.Left) || 0,
        top: Number(w.Top) || 0,
        width: Number(w.Width) || 0,
        height: Number(w.Height) || 0,
      });
    }
  }
  return { text, cells };
}

async function callOcrSpace(imageBase64, { apiKey, fetchImpl = fetch } = {}) {
  if (!apiKey) throw new Error('OCRSPACE_API_KEY is not configured');
  const params = new URLSearchParams();
  params.append('apikey', apiKey);
  params.append('base64Image', `data:image/jpeg;base64,${imageBase64}`);
  params.append('OCREngine', '2');
  params.append('isOverlayRequired', 'true');
  params.append('scale', 'true');
  params.append('detectOrientation', 'true');
  params.append('isTable', 'true');

  const res = await fetchImpl(OCR_SPACE_URL, {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: params.toString(),
  });
  const json = await res.json();
  if (!res.ok) throw new Error(`OCR.space HTTP ${res.status}`);
  if (json.IsErroredOnProcessing) {
    const msg = Array.isArray(json.ErrorMessage)
      ? json.ErrorMessage.join('; ')
      : json.ErrorMessage || 'OCR.space processing error';
    throw new Error(msg);
  }
  return json;
}

module.exports = { overlayToCells, callOcrSpace, OCR_SPACE_URL };
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd backend && npx jest src/services/ocrspace_service.test.js`
Expected: PASS (all cases).

- [ ] **Step 5: Commit**

```bash
git add backend/src/services/ocrspace_service.js backend/src/services/ocrspace_service.test.js
git commit -m "feat(backend): add OCR.space service (call + overlay-to-cells normalizer)"
```

---

### Task 2: Backend `/api/ocr/scan` route

Thin, authed route that validates input, calls the service, returns normalized data.

**Files:**
- Create: `backend/src/routes/ocr_firestore.js`
- Modify: `backend/src/server.js` (require + mount under `/api/ocr`)
- Modify: `backend/.env.example` (add `OCRSPACE_API_KEY=`)
- Test: `backend/src/routes/ocr_firestore.test.js`

**Interfaces:**
- Consumes: `callOcrSpace`, `overlayToCells` from Task 1.
- Produces: Express router with `POST /scan`, mounted at `/api/ocr` (so full path `POST /api/ocr/scan`).

- [ ] **Step 1: Add supertest (dev dependency)**

Run: `cd backend && npm install --save-dev supertest`
Expected: `supertest` appears under devDependencies in `backend/package.json`.

- [ ] **Step 2: Write the failing test**

Create `backend/src/routes/ocr_firestore.test.js`:

```js
const request = require('supertest');
const express = require('express');
const ocrRoutes = require('./ocr_firestore');

function makeApp() {
  const app = express();
  app.use(express.json({ limit: '10mb' }));
  app.use('/api/ocr', ocrRoutes);
  return app;
}

describe('POST /api/ocr/scan', () => {
  test('400 on invalid recordType / missing image', async () => {
    const res = await request(makeApp()).post('/api/ocr/scan').send({ recordType: 'invalid' });
    expect(res.status).toBe(400);
    expect(res.body.success).toBe(false);
  });

  test('200 with normalized cells on success', async () => {
    process.env.OCRSPACE_API_KEY = 'K';
    global.fetch = jest.fn(async () => ({
      ok: true,
      json: async () => ({
        ParsedResults: [
          { ParsedText: 'A', TextOverlay: { Lines: [{ Words: [{ WordText: 'A', Left: 1, Top: 2, Width: 3, Height: 4 }] }] } },
        ],
      }),
    }));
    const res = await request(makeApp())
      .post('/api/ocr/scan')
      .send({ imageBase64: 'x', recordType: 'baptism' });
    expect(res.status).toBe(200);
    expect(res.body.success).toBe(true);
    expect(res.body.data.engine).toBe('ocrspace');
    expect(res.body.data.cells[0]).toEqual({ text: 'A', left: 1, top: 2, width: 3, height: 4 });
  });

  test('502 when OCR.space errors', async () => {
    process.env.OCRSPACE_API_KEY = 'K';
    global.fetch = jest.fn(async () => ({ ok: true, json: async () => ({ IsErroredOnProcessing: true, ErrorMessage: ['nope'] }) }));
    const res = await request(makeApp())
      .post('/api/ocr/scan')
      .send({ imageBase64: 'x', recordType: 'baptism' });
    expect(res.status).toBe(502);
    expect(res.body.success).toBe(false);
  });
});
```

- [ ] **Step 3: Run test to verify it fails**

Run: `cd backend && npx jest src/routes/ocr_firestore.test.js`
Expected: FAIL — module `./ocr_firestore` not found.

- [ ] **Step 4: Implement the route**

Create `backend/src/routes/ocr_firestore.js`:

```js
const express = require('express');
const { body, validationResult } = require('express-validator');
const { callOcrSpace, overlayToCells } = require('../services/ocrspace_service');

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
    try {
      const json = await callOcrSpace(req.body.imageBase64, { apiKey: process.env.OCRSPACE_API_KEY });
      const { text, cells } = overlayToCells(json);
      return res.json({ success: true, data: { text, cells, engine: 'ocrspace' } });
    } catch (e) {
      return res.status(502).json({ success: false, message: `OCR failed: ${e.message}` });
    }
  },
);

module.exports = router;
```

- [ ] **Step 5: Mount the route + document the env var**

In `backend/src/server.js`, add the require alongside the other route requires (near lines 7-20):

```js
const ocrRoutes = require('./routes/ocr_firestore');
```

and mount it with the other protected routes (after the `app.use('/api', verifyFirebaseToken);` line, near lines 90-101):

```js
app.use('/api/ocr', ocrRoutes);
```

In `backend/.env.example`, add:

```
OCRSPACE_API_KEY=
```

- [ ] **Step 6: Run test to verify it passes**

Run: `cd backend && npx jest src/routes/ocr_firestore.test.js`
Expected: PASS (400, 200, 502 cases).

- [ ] **Step 7: Commit**

```bash
git add backend/src/routes/ocr_firestore.js backend/src/routes/ocr_firestore.test.js backend/src/server.js backend/.env.example backend/package.json backend/package-lock.json
git commit -m "feat(backend): add POST /api/ocr/scan proxying OCR.space"
```

---

### Task 3: Flutter downscale-for-upload helper

Resize-only JPEG shrink so uploads stay under OCR.space's 1MB free-tier cap.

**Files:**
- Modify: `lib/services/register_ocr_image_preprocess.dart`
- Test: `test/ocr/downscale_for_upload_test.dart`

**Interfaces:**
- Produces: `static Future<Uint8List> RegisterOcrImagePreprocess.downscaleForUpload(Uint8List inputBytes, {int maxDim = 2000, int quality = 85})`

- [ ] **Step 1: Write the failing test**

Create `test/ocr/downscale_for_upload_test.dart`:

```dart
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:parishrecord/services/register_ocr_image_preprocess.dart';

void main() {
  test('caps the long edge at maxDim and returns a decodable JPEG', () async {
    final src = img.Image(width: 3000, height: 1500);
    img.fill(src, color: img.ColorRgb8(200, 200, 200));
    final bytes = Uint8List.fromList(img.encodeJpg(src, quality: 90));

    final out = await RegisterOcrImagePreprocess.downscaleForUpload(bytes, maxDim: 2000);
    final decoded = img.decodeImage(out);
    expect(decoded, isNotNull);
    expect(decoded!.width, lessThanOrEqualTo(2000));
    expect(decoded.height, lessThanOrEqualTo(2000));
    expect(out, isNotEmpty);
  });

  test('leaves already-small images decodable', () async {
    final src = img.Image(width: 800, height: 600);
    img.fill(src, color: img.ColorRgb8(10, 10, 10));
    final bytes = Uint8List.fromList(img.encodeJpg(src));
    final out = await RegisterOcrImagePreprocess.downscaleForUpload(bytes);
    expect(img.decodeImage(out), isNotNull);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/ocr/downscale_for_upload_test.dart`
Expected: FAIL — `downscaleForUpload` is undefined.

- [ ] **Step 3: Implement the helper**

In `lib/services/register_ocr_image_preprocess.dart`, add this method inside the `RegisterOcrImagePreprocess` class (e.g. after `rotateBytes`):

```dart
  /// Downscale + JPEG-encode for cloud upload (keeps OCR.space under its 1MB
  /// free-tier cap). Resize only — grayscale/contrast/sharpen measurably hurt
  /// recognition, so they are intentionally omitted here.
  static Future<Uint8List> downscaleForUpload(
    Uint8List inputBytes, {
    int maxDim = 2000,
    int quality = 85,
  }) async {
    if (kIsWeb) return _downscaleJpeg(inputBytes, maxDim, quality);
    return compute(
      _downscaleArgs,
      _DownscaleArgs(inputBytes, maxDim, quality),
    );
  }
```

Then add these top-level declarations at the bottom of the same file (next to `_RotateArgs` / `_rotate`):

```dart
class _DownscaleArgs {
  _DownscaleArgs(this.bytes, this.maxDim, this.quality);
  final Uint8List bytes;
  final int maxDim;
  final int quality;
}

Uint8List _downscaleArgs(_DownscaleArgs a) =>
    _downscaleJpeg(a.bytes, a.maxDim, a.quality);

Uint8List _downscaleJpeg(Uint8List inputBytes, int maxDim, int quality) {
  try {
    final decoded = img.decodeImage(inputBytes);
    if (decoded == null) return inputBytes;
    var out = decoded;
    if (decoded.width > maxDim || decoded.height > maxDim) {
      out = decoded.width >= decoded.height
          ? img.copyResize(decoded, width: maxDim)
          : img.copyResize(decoded, height: maxDim);
    }
    return Uint8List.fromList(img.encodeJpg(out, quality: quality));
  } catch (_) {
    return inputBytes;
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/ocr/downscale_for_upload_test.dart`
Expected: PASS (2 tests).

- [ ] **Step 5: Commit**

```bash
git add lib/services/register_ocr_image_preprocess.dart test/ocr/downscale_for_upload_test.dart
git commit -m "feat(ocr): add downscaleForUpload for cloud OCR (<=2000px, q85)"
```

---

### Task 4: Flutter cloud OCR client

Calls `/api/ocr/scan` with the Firebase token; maps the response to `OcrLineBox` cells. Returns null on any failure (caller falls back).

**Files:**
- Create: `lib/services/cloud_ocr_service.dart`
- Test: `test/ocr/cloud_ocr_service_test.dart`

**Interfaces:**
- Consumes: `OcrLineBox` (+ `OcrLineBox.fromJson`) from `register_ocr_scan_helper.dart`; `BackendConfig.apiBaseUrl`.
- Produces:
  - `class CloudOcrResult { final String text; final List<OcrLineBox> cells; static CloudOcrResult? fromResponseJson(Map<String, dynamic> json); }`
  - `class CloudOcrService { CloudOcrService({http.Client? client}); Future<CloudOcrResult?> scanRegister(Uint8List jpeg, {required String recordType}); }`

- [ ] **Step 1: Write the failing test**

Create `test/ocr/cloud_ocr_service_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:parishrecord/services/cloud_ocr_service.dart';

void main() {
  test('fromResponseJson maps data.cells to OcrLineBox list', () {
    final json = {
      'success': true,
      'data': {
        'text': 'ALBERTO',
        'cells': [
          {'text': 'ALBERTO', 'left': 120, 'top': 100, 'width': 80, 'height': 20},
        ],
      },
    };
    final r = CloudOcrResult.fromResponseJson(json)!;
    expect(r.text, 'ALBERTO');
    expect(r.cells, hasLength(1));
    expect(r.cells.first.text, 'ALBERTO');
    expect(r.cells.first.left, 120);
  });

  test('returns null when success is not true', () {
    expect(CloudOcrResult.fromResponseJson({'success': false}), isNull);
    expect(CloudOcrResult.fromResponseJson({'success': true}), isNull); // no data
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/ocr/cloud_ocr_service_test.dart`
Expected: FAIL — `cloud_ocr_service.dart` not found.

- [ ] **Step 3: Implement the client**

Create `lib/services/cloud_ocr_service.dart`:

```dart
import 'dart:convert';
import 'dart:typed_data';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;

import '../config/backend.dart';
import 'register_ocr_scan_helper.dart';

/// Normalized cloud OCR result: full text + positioned word cells.
class CloudOcrResult {
  CloudOcrResult({required this.text, required this.cells});

  final String text;
  final List<OcrLineBox> cells;

  static CloudOcrResult? fromResponseJson(Map<String, dynamic> json) {
    if (json['success'] != true) return null;
    final data = json['data'];
    if (data is! Map) return null;
    final cells = <OcrLineBox>[];
    final rawCells = data['cells'];
    if (rawCells is List) {
      for (final c in rawCells) {
        if (c is Map) {
          cells.add(OcrLineBox.fromJson(Map<String, dynamic>.from(c)));
        }
      }
    }
    return CloudOcrResult(text: data['text']?.toString() ?? '', cells: cells);
  }
}

/// Sends register photos to the backend OCR proxy (OCR.space).
class CloudOcrService {
  CloudOcrService({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;
  static const Duration _timeout = Duration(seconds: 30);

  /// Returns cloud OCR cells+text, or null on any failure (caller falls back).
  Future<CloudOcrResult?> scanRegister(
    Uint8List jpeg, {
    required String recordType,
  }) async {
    try {
      final idToken = await FirebaseAuth.instance.currentUser?.getIdToken();
      if (idToken == null) return null;
      final res = await _client
          .post(
            Uri.parse('${BackendConfig.apiBaseUrl}/ocr/scan'),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $idToken',
            },
            body: jsonEncode({
              'imageBase64': base64Encode(jpeg),
              'recordType': recordType,
            }),
          )
          .timeout(_timeout);
      if (res.statusCode != 200) return null;
      final decoded = jsonDecode(res.body);
      if (decoded is! Map<String, dynamic>) return null;
      return CloudOcrResult.fromResponseJson(decoded);
    } catch (_) {
      return null;
    }
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/ocr/cloud_ocr_service_test.dart`
Expected: PASS (2 tests).

- [ ] **Step 5: Commit**

```bash
git add lib/services/cloud_ocr_service.dart test/ocr/cloud_ocr_service_test.dart
git commit -m "feat(ocr): add CloudOcrService client for /api/ocr/scan"
```

---

### Task 5: Scan-helper cloud builder + launcher wiring

Turn cloud cells into a `StaffOcrScanResult`, and make the scan launcher try cloud first with on-device fallback.

**Files:**
- Modify: `lib/services/register_ocr_scan_helper.dart` (add imports + two methods)
- Modify: `lib/widgets/register_scan_launcher.dart:312`
- Test: `test/ocr/scan_result_from_cloud_test.dart`

**Interfaces:**
- Consumes: `CloudOcrService`, `CloudOcrResult` (Task 4); `downscaleForUpload` (Task 3); existing `parseEntriesFromCells`, `reconstructTableText`, `_bestEntriesFromSources`, `_lineCount`, `resolveTableRows`, `finalizeScanResult`, `RegisterOcrParser.parseFast/parse/parseMarriageRegister`, `scanXFile`.
- Produces:
  - `static StaffOcrScanResult RegisterOcrScanHelper.scanResultFromCloud(List<OcrLineBox> cells, String text, {String recordType = 'baptism'})`
  - `static Future<StaffOcrScanResult> RegisterOcrScanHelper.scanXFileWithCloud(XFile file, {String recordType = 'baptism', CloudOcrService? cloudService})`

- [ ] **Step 1: Write the failing test**

Create `test/ocr/scan_result_from_cloud_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:parishrecord/services/register_ocr_scan_helper.dart';

void main() {
  test('scanResultFromCloud builds baptism entries from positioned cells', () {
    final cells = <OcrLineBox>[
      const OcrLineBox(text: '1', top: 100, left: 10, width: 15, height: 20),
      const OcrLineBox(text: 'Alberto', top: 100, left: 120, width: 80, height: 20),
      const OcrLineBox(text: 'Saligumba', top: 100, left: 210, width: 90, height: 20),
      const OcrLineBox(text: '07 January 2008', top: 100, left: 320, width: 140, height: 20),
    ];
    final result = RegisterOcrScanHelper.scanResultFromCloud(
      cells,
      '1 Alberto Saligumba 07 January 2008',
      recordType: 'baptism',
    );
    expect(result.entries, isNotEmpty);
    expect(result.entries.first.name.toLowerCase(), contains('alberto'));
    expect(result.isMarriage, isFalse);
  });

  test('scanResultFromCloud handles empty cloud output without throwing', () {
    final result = RegisterOcrScanHelper.scanResultFromCloud(
      const [],
      '',
      recordType: 'baptism',
    );
    expect(result.entries, isA<List>());
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/ocr/scan_result_from_cloud_test.dart`
Expected: FAIL — `scanResultFromCloud` is undefined.

- [ ] **Step 3: Add the cloud builder**

In `lib/services/register_ocr_scan_helper.dart`, add the import near the other service imports at the top:

```dart
import 'cloud_ocr_service.dart';
```

Then add both methods inside the `RegisterOcrScanHelper` class (e.g. right after `scanXFile`):

```dart
  /// Builds a review-ready result from cloud OCR cells + text (no ML Kit).
  static StaffOcrScanResult scanResultFromCloud(
    List<OcrLineBox> cells,
    String text, {
    String recordType = 'baptism',
  }) {
    if (recordType.toLowerCase() == 'marriage') {
      final marriage = RegisterOcrParser.parseMarriageRegister(text).entries;
      return finalizeScanResult(
        StaffOcrScanResult(
          text: text,
          entries: const [],
          marriageEntries: marriage,
          lineCount: _lineCount(text),
          cellCount: cells.length,
        ),
        recordType: recordType,
      );
    }

    final tableText = cells.isNotEmpty ? reconstructTableText(cells) : text;
    final sources = <List<RegisterOcrEntry>>[
      parseEntriesFromCells(cells),
      if (tableText.trim().isNotEmpty)
        RegisterOcrParser.parseFast(tableText).entries,
      if (text.trim().isNotEmpty)
        RegisterOcrParser.parse(text, recordType: recordType).entries,
    ];
    final ocrText = text.trim().isNotEmpty ? text : tableText;
    final entries = resolveTableRows(
      ocrText: ocrText,
      parsed: _bestEntriesFromSources(sources),
      recordType: recordType,
    );
    return finalizeScanResult(
      StaffOcrScanResult(
        text: ocrText,
        entries: entries,
        lineCount: _lineCount(ocrText),
        cellCount: cells.length,
      ),
      recordType: recordType,
    );
  }

  /// Cloud-first scan of one file, falling back to on-device on any failure.
  static Future<StaffOcrScanResult> scanXFileWithCloud(
    XFile file, {
    String recordType = 'baptism',
    CloudOcrService? cloudService,
  }) async {
    final cloud = cloudService ?? CloudOcrService();
    try {
      final rawBytes = await file.readAsBytes();
      final jpeg =
          await RegisterOcrImagePreprocess.downscaleForUpload(rawBytes);
      final cloudResult =
          await cloud.scanRegister(jpeg, recordType: recordType);
      if (cloudResult != null &&
          (cloudResult.cells.isNotEmpty ||
              cloudResult.text.trim().isNotEmpty)) {
        return scanResultFromCloud(
          cloudResult.cells,
          cloudResult.text,
          recordType: recordType,
        );
      }
    } catch (_) {
      // fall through to on-device
    }
    return scanXFile(file, recordType: recordType);
  }
```

> If `_bestEntriesFromSources`, `reconstructTableText`, or `_lineCount` are named slightly differently in the current file, use the exact private names already used inside `prepareScanResult` (that method is the reference — it does the same source-merge for the block path). Do not change their behavior.

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/ocr/scan_result_from_cloud_test.dart`
Expected: PASS (2 tests).

- [ ] **Step 5: Wire the launcher to cloud-first**

In `lib/widgets/register_scan_launcher.dart`, change the scan call at line 312 from `scanXFile` to `scanXFileWithCloud`:

```dart
        final scan = await RegisterOcrScanHelper.scanXFileWithCloud(
          widget.files[i],
          recordType: widget.recordType,
        );
```

- [ ] **Step 6: Verify analyze + full OCR suite**

Run: `flutter analyze lib/services/register_ocr_scan_helper.dart lib/services/cloud_ocr_service.dart lib/widgets/register_scan_launcher.dart`
Expected: no new errors.
Run: `flutter test test/ocr/`
Expected: PASS (all OCR tests, including the harness golden tests).

- [ ] **Step 7: Commit**

```bash
git add lib/services/register_ocr_scan_helper.dart lib/widgets/register_scan_launcher.dart test/ocr/scan_result_from_cloud_test.dart
git commit -m "feat(ocr): cloud-first register scan with on-device fallback"
```

---

## Self-Review

**Spec coverage:**
- Backend `/api/ocr/scan` + OCR.space call (Engine 2, isOverlayRequired) → Task 1 (service) + Task 2 (route) ✅
- Normalize overlay → `{text, cells}`; Dart parser unchanged → Task 1 `overlayToCells` ✅
- `OCRSPACE_API_KEY` in `.env`, key server-side only → Task 2 (env.example + `process.env`) ✅
- Flutter cloud client with Firebase auth header, 30s timeout, null-on-failure → Task 4 ✅
- Downscale ≤2000px / q85 / resize-only → Task 3 ✅
- `scanResultFromCloud` via `parseEntriesFromCells` (+ marriage path) → Task 5 ✅
- Cloud-primary + on-device fallback wired into launcher → Task 5 (`scanXFileWithCloud`, launcher edit) ✅
- Tests: normalizer + callOcrSpace (Task 1), route 400/200/502 (Task 2), downscale (Task 3), response mapping (Task 4), cloud builder (Task 5) ✅
- Non-goals (harness fixtures/baselines, tuning, batch, caching) → not in any task ✅

**Placeholder scan:** No TBD/TODO; every code step has full code. The one conditional note (Task 5 Step 3) names the reference method (`prepareScanResult`) to copy private-helper names from — that is guidance for an exact-name match, not a missing implementation.

**Type consistency:** `overlayToCells`/`callOcrSpace` (Task 1) are consumed by Task 2; `CloudOcrResult.fromResponseJson` + `CloudOcrService.scanRegister` (Task 4) consumed by Task 5; `downscaleForUpload` (Task 3) consumed by Task 5; `scanResultFromCloud` / `scanXFileWithCloud` signatures match between definition (Task 5 Step 3) and the launcher call (Task 5 Step 5). Cell JSON keys (`text/left/top/width/height`) match across backend `overlayToCells`, the route response, `OcrLineBox.fromJson`, and all tests.
