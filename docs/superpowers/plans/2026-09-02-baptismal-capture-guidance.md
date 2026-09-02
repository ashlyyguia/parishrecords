# Capture Guidance Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Help staff capture a readable register photo — an upfront how-to-photograph checklist at the upload step, and specific "what was wrong" guidance when a scan is refused.

**Architecture:** Piece A is a Flutter-only checklist widget shown on the scan page's pick and preview steps. Piece B threads a structural `reason`+`side` from the CV service's refusal through the backend (which maps them to curated capture wording as a `detail` field) to the app's error banner. No detection code or safety gate changes.

**Tech Stack:** Python 3.10 / FastAPI / OpenCV (CV service), Node/Express/Jest (backend), Flutter/Dart (app). CV tests: `ocr_service/.venv310/Scripts/python -m pytest tests/`. Backend: `npx jest` in `backend/`. Flutter: `flutter test`.

## Global Constraints

- Records of minors: `reason` and `side` are structural only (which check failed, which page). No counts, cell text, names, dates, or file paths cross any boundary. CV logs stay "code only".
- No detection/geometry/safety-gate changes. Guidance only.
- Backend owns all user-facing wording; the CV service emits codes only (never forward its raw human message).
- `reason` ∈ {`grid_not_found`, `columns_unmatched`, `rows_disagree`, `pitch_mismatch`}. `side` ∈ {`left`, `right`, `both`}.
- No new dependencies in any layer.

---

### Task 1 (Piece A): Upfront capture checklist

**Files:**
- Modify: `lib/screens/admin/pages/baptismal_ocr_scan_page.dart` (`_pickStep`, `_previewStep`; add a `_captureGuide()` helper)
- Test: `test/baptismal_ocr_scan_page_test.dart`

**Interfaces:**
- Produces: a capture-guide widget keyed `const ValueKey('capture-guide')`, rendered on the pick step and the preview step.

- [ ] **Step 1: Write the failing test**

Add to `test/baptismal_ocr_scan_page_test.dart` (inside `main()`, alongside the other `testWidgets`):

```dart
  testWidgets('shows the capture checklist on the upload step', (tester) async {
    await tester.pumpWidget(harness(service: serviceReturning(200, _emptyScanBody())));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('capture-guide')), findsOneWidget);
    expect(find.textContaining('flat'), findsWidgets); // "lay the book flat"
  });
```

- [ ] **Step 2: Run it to verify it fails**

Run: `flutter test test/baptismal_ocr_scan_page_test.dart --plain-name "shows the capture checklist on the upload step"`
Expected: FAIL — no widget with key `capture-guide`.

- [ ] **Step 3: Implement the capture guide**

In `baptismal_ocr_scan_page.dart`, add the helper (place it next to `_pickStep`):

```dart
  Widget _captureGuide() {
    const tips = <(IconData, String)>[
      (Icons.menu_book_outlined,
          'Lay the book flat and press the spine down — the top cause of an unreadable page.'),
      (Icons.crop_free, 'Fit both pages fully in the frame, straight-on.'),
      (Icons.wb_sunny_outlined, 'Even lighting — no glare or shadow across the page.'),
      (Icons.zoom_in, "Fill the frame with the register; don't shoot from far away."),
    ];
    return Card(
      key: const ValueKey('capture-guide'),
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('For a readable scan',
                style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            for (final (icon, text) in tips)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(icon, size: 20),
                    const SizedBox(width: 10),
                    Expanded(child: Text(text)),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
```

In `_pickStep`, insert the guide above the "Choose image" button — change the children list of its `Column` so `_captureGuide()` appears before the `FilledButton.icon`:

```dart
          const Text('Upload or capture a register page'),
          const SizedBox(height: 16),
          _captureGuide(),
          FilledButton.icon(
```

In `_previewStep`, render the guide at the top of the scroll column (before the error banner) so it is present when the user is deciding how to retake — change the start of the `Column` children in the returned `SingleChildScrollView`:

```dart
        children: [
          _captureGuide(),
          if (failure != null) _errorBanner(failure),
```

- [ ] **Step 4: Run it to verify it passes**

Run: `flutter test test/baptismal_ocr_scan_page_test.dart --plain-name "shows the capture checklist on the upload step"`
Expected: PASS.

- [ ] **Step 5: Run the whole scan-page suite (no regression)**

Run: `flutter test test/baptismal_ocr_scan_page_test.dart`
Expected: PASS (all).

- [ ] **Step 6: Commit**

```bash
git add lib/screens/admin/pages/baptismal_ocr_scan_page.dart test/baptismal_ocr_scan_page_test.dart
git commit -m "feat(ocr): add a how-to-photograph checklist to the scan page"
```

---

### Task 2 (Piece B — CV): emit reason + side on refusal

**Files:**
- Modify: `ocr_service/app/errors.py`, `ocr_service/app/main.py`, `ocr_service/app/pipeline/table.py`
- Test: `ocr_service/tests/test_spread_gate.py`, `ocr_service/tests/test_grid_endpoint.py`

**Interfaces:**
- Produces:
  - `errors.REFUSAL_REASONS`, `errors.REFUSAL_SIDES` (frozensets).
  - `OcrError(code, message, http_status=400, reason=None, side=None)` with `.reason`, `.side` attributes; validates `reason`/`side` against the frozensets.
  - `table._refuse(detail, reason=None, side=None)` passes them to `OcrError`.
  - `/v1/grid` refusal JSON includes `reason` and `side` when present.

- [ ] **Step 1: Write the failing tests**

Add to `ocr_service/tests/test_spread_gate.py`:

```python
def test_a_row_disagreement_refusal_carries_reason_and_side():
    import numpy as np
    from app.pipeline.table import detect_spread_grids
    from app.pipeline.column_template import BAPTISMAL_REGISTER
    # Two blank pages -> the spread gate refuses; we only assert the refusal
    # carries structured reason/side, not which specific reason (that is pinned
    # per call site in the unit tests below).
    blank = np.full((900, 1400, 3), 255, np.uint8)
    with pytest.raises(OcrError) as e:
        detect_spread_grids(blank, blank, spread_template=BAPTISMAL_REGISTER)
    assert e.value.reason in {"grid_not_found", "columns_unmatched",
                              "rows_disagree", "pitch_mismatch"}
    assert e.value.side in {"left", "right", "both"}
```

Add to `ocr_service/tests/test_spread_gate.py` a direct `_refuse` unit test:

```python
def test_refuse_validates_and_carries_reason_side():
    from app.pipeline.table import _refuse
    with pytest.raises(OcrError) as e:
        _refuse("Detail here.", reason="rows_disagree", side="both")
    assert e.value.reason == "rows_disagree"
    assert e.value.side == "both"
    assert e.value.code == "no_table_detected"
```

- [ ] **Step 2: Run to verify they fail**

Run: `.venv310/Scripts/python -m pytest tests/test_spread_gate.py -k "reason" -v`
Expected: FAIL — `OcrError`/`_refuse` take no `reason`/`side`.

- [ ] **Step 3: Extend `OcrError`**

In `ocr_service/app/errors.py`, after `ERROR_CODES`:

```python
# Structural reasons a spread is refused, surfaced to help the user retake.
# Never carries cell text -- only which check failed.
REFUSAL_REASONS = frozenset(
    {"grid_not_found", "columns_unmatched", "rows_disagree", "pitch_mismatch"}
)
REFUSAL_SIDES = frozenset({"left", "right", "both"})
```

Change `OcrError.__init__`:

```python
    def __init__(
        self,
        code: str,
        message: str,
        http_status: int = 400,
        reason: str | None = None,
        side: str | None = None,
    ) -> None:
        if code not in ERROR_CODES:
            raise ValueError(f"unknown error code: {code}")
        if reason is not None and reason not in REFUSAL_REASONS:
            raise ValueError(f"unknown refusal reason: {reason}")
        if side is not None and side not in REFUSAL_SIDES:
            raise ValueError(f"unknown refusal side: {side}")
        super().__init__(message)
        self.code = code
        self.message = message
        self.http_status = http_status
        self.reason = reason
        self.side = side
```

- [ ] **Step 4: Pass reason/side through `_refuse` and every call site**

In `ocr_service/app/pipeline/table.py`, change `_refuse`:

```python
def _refuse(detail: str, reason: str | None = None, side: str | None = None) -> NoReturn:
    """Raise the error the Flutter workflow already handles.

    The message is written for a parish staff member holding the camera, not
    for a developer: it says what looked wrong about the *photograph* and what
    to do next. It carries only structural counts -- never recognized text, a
    name, a date, or a file path. ``reason``/``side`` are the machine-readable
    form of the same, so the app can show targeted retake guidance.
    """
    raise OcrError(
        "no_table_detected",
        "Couldn't read this register spread reliably. " + detail + " "
        "Please retake the photo with the book opened flat, both pages fully "
        "in frame, and even lighting, then tap Retry OCR — or tap Continue "
        "Manually to type this spread in.",
        reason=reason,
        side=side,
    )
```

Update each call site (all in `table.py`) to pass `reason`/`side`:

In `_check_template_fit` (uses local `side`):

```python
    if grid.cols != template.column_count:
        _refuse(
            f"The {side} page came out with {grid.cols} columns where this "
            f"register has {template.column_count}.",
            reason="columns_unmatched", side=side,
        )
    if grid.table_x_lo is None or grid.table_x_hi is None:
        _refuse(f"The edges of the ruled table could not be found on the {side} page.",
                reason="grid_not_found", side=side)
    if not (0 <= grid.table_x_lo < grid.table_x_hi <= page_width):
        _refuse(
            f"The ruled table on the {side} page was traced past the edge of "
            f"the photograph, so part of it is out of frame.",
            reason="grid_not_found", side=side,
        )
    corroboration = grid.column_corroboration or 0.0
    if corroboration < TEMPLATE_CORROBORATION_FLOOR:
        _refuse(
            f"Only {corroboration:.0%} of the column edges expected on the "
            f"{side} page could be matched to a printed line in the "
            f"photograph, so entries could be filed under the wrong heading.",
            reason="columns_unmatched", side=side,
        )
```

In `detect_spread_grids` — the detect loop and the cross-page checks:

```python
        except OcrError:
            _refuse(f"The {side} page's ruled grid could not be found at all.",
                    reason="grid_not_found", side=side)
```

```python
    if left.cols != right.cols:
        _refuse(
            f"The two pages disagree about how many columns the register has "
            f"({left.cols} on the left page, {right.cols} on the right), so "
            f"entries could be filed under the wrong heading.",
            reason="columns_unmatched", side="both",
        )

    if left.rows != right.rows:
        _refuse(
            f"The two pages disagree about how many rows the register has "
            f"({left.rows} on the left page, {right.rows} on the right), so "
            f"each entry's details could be paired with the wrong person.",
            reason="rows_disagree", side="both",
        )

    left_pitch = median_data_row_pitch(left)
    right_pitch = median_data_row_pitch(right)
    if left_pitch <= 0 or right_pitch <= 0:
        _refuse("The spacing between rows could not be measured on both pages.",
                reason="pitch_mismatch", side="both")

    ratio = max(left_pitch, right_pitch) / min(left_pitch, right_pitch)
    if ratio - 1.0 > pitch_tolerance:
        _refuse(
            f"The rows are spaced {ratio - 1.0:.0%} further apart on one page "
            f"than the other, although both pages are halves of the same "
            f"ruled table, so at least one page was not read correctly.",
            reason="pitch_mismatch", side="both",
        )
```

- [ ] **Step 5: Include reason/side in the endpoint JSON**

In `ocr_service/app/main.py`, change `_ocr_error_handler`:

```python
@app.exception_handler(OcrError)
async def _ocr_error_handler(_: Request, exc: OcrError) -> JSONResponse:
    log.warning("request failed: %s", exc.code)  # code only, never cell text
    content = {"success": False, "code": exc.code, "message": exc.message}
    if exc.reason is not None:
        content["reason"] = exc.reason
    if exc.side is not None:
        content["side"] = exc.side
    return JSONResponse(status_code=exc.http_status, content=content)
```

- [ ] **Step 6: Add the endpoint test**

Add to `ocr_service/tests/test_grid_endpoint.py` a test that a refusal response carries `reason`/`side`. Follow the file's existing client/fixture style (a `TestClient` posting bytes that cannot form a grid). Concretely, add:

```python
def test_refusal_response_includes_reason_and_side(client):
    # A blank white spread cannot form a grid -> refused with structured fields.
    import numpy as np, cv2
    blank = np.full((900, 1400, 3), 255, np.uint8)
    ok, buf = cv2.imencode(".jpg", blank)
    resp = client.post(
        "/v1/grid",
        content=buf.tobytes(),
        headers={"Content-Type": "application/octet-stream",
                 "X-OCR-Service-Key": TEST_KEY},
    )
    assert resp.status_code >= 400
    body = resp.json()
    assert body["success"] is False
    assert body["reason"] in {"grid_not_found", "columns_unmatched",
                              "rows_disagree", "pitch_mismatch"}
    assert body["side"] in {"left", "right", "both"}
```

If `client`/`TEST_KEY` fixtures are named differently in `test_grid_endpoint.py`, reuse that file's existing fixture names (do not invent new ones) — only the assertions above are new.

- [ ] **Step 7: Run the CV suite**

Run: `.venv310/Scripts/python -m pytest tests/ -q`
Expected: PASS (all). If the endpoint test's fixture names were guessed wrong, fix them to match the file and re-run.

- [ ] **Step 8: Commit**

```bash
git add ocr_service/app/errors.py ocr_service/app/main.py ocr_service/app/pipeline/table.py ocr_service/tests/test_spread_gate.py ocr_service/tests/test_grid_endpoint.py
git commit -m "feat(ocr): emit structured reason/side with each spread refusal"
```

---

### Task 3 (Piece B — backend): map reason/side to a capture hint

**Files:**
- Modify: `backend/src/services/cv_grid_client.js`, `backend/src/routes/baptismal_ocr_firestore.js`
- Test: `backend/src/services/cv_grid_client.test.js`, `backend/src/routes/baptismal_ocr_firestore.test.js`

**Interfaces:**
- Consumes: `/v1/grid` refusal JSON `{code, message, reason, side}` (Task 2).
- Produces:
  - `CvGridError` carries `.reason` and `.side`.
  - The `/scan` `SPREAD_UNREADABLE` response body includes a `detail` string when a reason maps to one.

- [ ] **Step 1: Write the failing tests**

Add to `backend/src/services/cv_grid_client.test.js`:

```javascript
test('CV_REFUSED carries the reason and side from the service', async () => {
  const fetchImpl = async () => ({ ok: false, status: 422, json: async () => ({
    success: false, code: 'no_table_detected', reason: 'columns_unmatched', side: 'left',
  }) });
  await expect(fetchGrid(Buffer.from('img'), { env, fetchImpl }))
    .rejects.toMatchObject({ code: 'CV_REFUSED', reason: 'columns_unmatched', side: 'left' });
});
```

Add to `backend/src/routes/baptismal_ocr_firestore.test.js` (in the `CV grid path` describe):

```javascript
  test('a CV refusal surfaces a capture-guidance detail for the failing page', async () => {
    const { CvGridError } = require('../services/cv_grid_client');
    const err = new CvGridError('CV_REFUSED', 'no_table_detected');
    err.reason = 'columns_unmatched';
    err.side = 'left';
    const app = express();
    app.use('/api/ocr/baptismal', createBaptismalOcrRouter({
      verifyToken: (req, _res, next) => { req.user = { uid: 'u', role: 'admin' }; next(); },
      fetchGrid: async () => { throw err; },
    }));
    const res = await request(app).post('/api/ocr/baptismal/scan')
      .send({ scanId: 's1', imageBase64: b64(JPEG) });
    expect(res.status).toBe(422);
    expect(res.body.code).toBe('SPREAD_UNREADABLE');
    expect(res.body.detail).toMatch(/left page/i);
    expect(JSON.stringify(res.body)).not.toContain('no_table_detected');
  });

  test('a CV refusal with no known reason has no detail', async () => {
    const { CvGridError } = require('../services/cv_grid_client');
    const err = new CvGridError('CV_REFUSED', 'no_table_detected'); // no reason/side
    const app = express();
    app.use('/api/ocr/baptismal', createBaptismalOcrRouter({
      verifyToken: (req, _res, next) => { req.user = { uid: 'u', role: 'admin' }; next(); },
      fetchGrid: async () => { throw err; },
    }));
    const res = await request(app).post('/api/ocr/baptismal/scan')
      .send({ scanId: 's1', imageBase64: b64(JPEG) });
    expect(res.status).toBe(422);
    expect(res.body.detail).toBeUndefined();
  });
```

- [ ] **Step 2: Run to verify they fail**

Run: `cd backend && npx jest src/services/cv_grid_client.test.js src/routes/baptismal_ocr_firestore.test.js -t "reason|capture-guidance|no known reason"`
Expected: FAIL — `CvGridError` has no `reason`, and the route emits no `detail`.

- [ ] **Step 3: Carry reason/side on `CvGridError`**

In `backend/src/services/cv_grid_client.js`, extend the class and the refusal throw:

```javascript
class CvGridError extends Error {
  constructor(code, message, reason = null, side = null) {
    super(message || code);
    this.code = code;
    this.reason = reason;
    this.side = side;
  }
}
```

In the refusal branch (currently
`throw new CvGridError(serviceCode === 'unauthorized' ? 'CV_AUTH' : 'CV_REFUSED', serviceCode);`):

```javascript
    const serviceCode = body && body.code;
    if (serviceCode === 'unauthorized') {
      throw new CvGridError('CV_AUTH', serviceCode);
    }
    throw new CvGridError('CV_REFUSED', serviceCode,
      body && body.reason ? String(body.reason) : null,
      body && body.side ? String(body.side) : null);
```

- [ ] **Step 4: Map reason/side to a detail in the route**

In `backend/src/routes/baptismal_ocr_firestore.js`, add a mapping helper near the top (after `MESSAGE_BY_CODE`):

```javascript
// Curated, capture-oriented guidance for a refused spread. The CV service
// emits only a structural reason/side (never cell text); the backend owns the
// wording. Returns null for an unknown/missing reason (fall back to the
// generic SPREAD_UNREADABLE message alone).
function refusalDetail(reason, side) {
  const where = side === 'left' ? 'left' : side === 'right' ? 'right' : null;
  switch (reason) {
    case 'grid_not_found':
      return where
        ? `The ${where} page's ruled lines couldn't be found — lay the book flat, fill the frame with the page, and retake.`
        : "The register's ruled lines couldn't be found — lay the book flat, fill the frame, and retake.";
    case 'columns_unmatched':
      return where
        ? `The ${where} page's column lines were too faint or curved to read — press the book flat near the spine and retake.`
        : 'The column lines were too faint or curved to read — press the book flat near the spine and retake.';
    case 'rows_disagree':
    case 'pitch_mismatch':
      return "The two pages didn't line up — flatten the book so both pages sit in the same plane, keep both fully in frame, and retake.";
    default:
      return null;
  }
}
```

In the inner `catch (cvErr)`, where `CV_REFUSED` is turned into `SPREAD_UNREADABLE`, attach the detail. Change:

```javascript
          if (cvErr && cvErr.code === 'CV_REFUSED') {
            const unreadable = new Error('cv refused spread');
            unreadable.code = 'SPREAD_UNREADABLE';
            throw unreadable;
          }
```

to:

```javascript
          if (cvErr && cvErr.code === 'CV_REFUSED') {
            const unreadable = new Error('cv refused spread');
            unreadable.code = 'SPREAD_UNREADABLE';
            unreadable.detail = refusalDetail(cvErr.reason, cvErr.side);
            throw unreadable;
          }
```

In the outer `catch (e)` where `fail(res, code, scanId)` is called, pass the detail through. Change `fail` to accept an optional detail and include it:

```javascript
        const code = e && STATUS_BY_CODE[e.code] ? e.code : 'INTERNAL_ERROR';
        return fail(res, code, scanId, e && e.detail);
```

and update `fail`:

```javascript
function fail(res, code, scanId, detail) {
  console.warn(`[baptismal-ocr] scan=${sanitizeScanIdForLog(scanId)} failed code=${code}`);
  const body = {
    success: false,
    code,
    message: MESSAGE_BY_CODE[code] || 'OCR failed.',
  };
  if (detail) body.detail = detail;
  return res.status(STATUS_BY_CODE[code] || 500).json(body);
}
```

- [ ] **Step 5: Run the backend tests**

Run: `cd backend && npx jest src/services/cv_grid_client.test.js src/routes/baptismal_ocr_firestore.test.js`
Expected: PASS (all — new tests plus the existing suite, since `fail`'s extra arg is optional and unused elsewhere).

- [ ] **Step 6: Commit**

```bash
git add backend/src/services/cv_grid_client.js backend/src/services/cv_grid_client.test.js backend/src/routes/baptismal_ocr_firestore.js backend/src/routes/baptismal_ocr_firestore.test.js
git commit -m "feat(ocr): map a CV refusal reason/side to a capture-guidance detail"
```

---

### Task 4 (Piece B — Flutter): show the detail

**Files:**
- Modify: `lib/services/baptismal_ocr_service.dart`, `lib/screens/admin/pages/baptismal_ocr_scan_page.dart`
- Test: `test/baptismal_ocr_service_test.dart`, `test/baptismal_ocr_scan_page_test.dart`

**Interfaces:**
- Consumes: the `/scan` `SPREAD_UNREADABLE` body `{code, message, detail}` (Task 3).
- Produces: `BaptismalOcrFailure.detail` (nullable); the error banner renders it.

- [ ] **Step 1: Write the failing tests**

Add to `test/baptismal_ocr_service_test.dart`:

```dart
  test('parses the capture-guidance detail from a refusal', () async {
    final svc = serviceReturning(422, {
      'success': false,
      'code': 'SPREAD_UNREADABLE',
      'message': 'Could not read this register spread reliably.',
      'detail': "The left page's column lines were too faint to read.",
    });
    await expectLater(
      svc.scan(scanId: 's1', bytes: bytes, idToken: 't'),
      throwsA(isA<BaptismalOcrFailure>()
          .having((f) => f.code, 'code', 'SPREAD_UNREADABLE')
          .having((f) => f.detail, 'detail',
              "The left page's column lines were too faint to read.")),
    );
  });
```

Add to `test/baptismal_ocr_scan_page_test.dart`:

```dart
  testWidgets('shows the capture-guidance detail when a scan is refused',
      (tester) async {
    final svc = serviceReturning(422, {
      'success': false,
      'code': 'SPREAD_UNREADABLE',
      'message': 'Could not read this register spread reliably.',
      'detail': "The left page's column lines were too faint to read.",
    });
    await tester.pumpWidget(harness(service: svc));
    await tester.tap(find.byKey(const ValueKey('pick-image')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Scan / Process OCR'));
    await tester.pumpAndSettle();
    expect(find.textContaining('too faint to read'), findsOneWidget);
  });
```

- [ ] **Step 2: Run to verify they fail**

Run: `flutter test test/baptismal_ocr_service_test.dart test/baptismal_ocr_scan_page_test.dart --plain-name "detail"`
Expected: FAIL — `BaptismalOcrFailure` has no `detail`; banner does not render it.

- [ ] **Step 3: Add `detail` to the failure model and parse it**

In `lib/services/baptismal_ocr_service.dart`, add the field to `BaptismalOcrFailure`:

```dart
class BaptismalOcrFailure implements Exception {
  const BaptismalOcrFailure({
    required this.code,
    required this.message,
    required this.recovery,
    this.detail,
  });

  final String code;
  final String message;
  final OcrRecovery recovery;

  /// Optional capture-guidance text for a refused spread (which page / what to
  /// fix). Populated from the server's `detail` field when present.
  final String? detail;
```

Thread it through `_failure` and the non-2xx path. Change `_failure`:

```dart
  BaptismalOcrFailure _failure(String code, String? serverMessage, [String? detail]) {
    return BaptismalOcrFailure(
      code: code,
      message: serverMessage ?? _fallbackMessages[code] ?? 'OCR failed. Please retry.',
      recovery: _recoveryByCode[code] ?? OcrRecovery.retry,
      detail: detail,
    );
  }
```

and the non-2xx throw (currently
`throw _failure(decoded['code']?.toString() ?? _codeForStatus(res.statusCode), decoded['message']?.toString() ?? decoded['error']?.toString());`):

```dart
      throw _failure(
        decoded['code']?.toString() ?? _codeForStatus(res.statusCode),
        decoded['message']?.toString() ?? decoded['error']?.toString(),
        decoded['detail']?.toString(),
      );
```

- [ ] **Step 4: Render the detail in the error banner**

In `lib/screens/admin/pages/baptismal_ocr_scan_page.dart` `_errorBanner`, after the existing `hint` block (inside the `Column` children), add the detail line:

```dart
          if (failure.detail != null) ...[
            const SizedBox(height: 8),
            Text(failure.detail!, style: TextStyle(color: scheme.onErrorContainer)),
          ],
```

- [ ] **Step 5: Run the Flutter tests**

Run: `flutter test test/baptismal_ocr_service_test.dart test/baptismal_ocr_scan_page_test.dart`
Expected: PASS (all).

- [ ] **Step 6: Commit**

```bash
git add lib/services/baptismal_ocr_service.dart lib/screens/admin/pages/baptismal_ocr_scan_page.dart test/baptismal_ocr_service_test.dart test/baptismal_ocr_scan_page_test.dart
git commit -m "feat(ocr): show capture-guidance detail in the scan error banner"
```

---

### Task 5: Full regression sweep

- [ ] **Step 1: CV suite**

Run: `cd ocr_service && .venv310/Scripts/python -m pytest tests/ -q`
Expected: PASS (all).

- [ ] **Step 2: Backend suites**

Run: `cd backend && npx jest src/routes/baptismal_ocr_firestore.test.js src/services/cv_grid_client.test.js src/services/baptismal_grid_assign.test.js`
Expected: PASS (all).

- [ ] **Step 3: Flutter OCR tests**

Run: `flutter test test/baptismal_ocr_service_test.dart test/baptismal_ocr_scan_page_test.dart`
Expected: PASS (all).

- [ ] **Step 4: Final commit only if an incidental fix was needed**

```bash
git add -A
git commit -m "test(ocr): regression sweep for capture guidance"
```

---

## Self-Review

**Spec coverage:**
- Piece A upfront guide on pick + preview steps → Task 1. ✓
- Piece B CV emits reason/side (OcrError, _refuse call sites, endpoint JSON) → Task 2. ✓
- Piece B backend maps (reason, side) → detail, keeps generic message, no cell text → Task 3. ✓
- Piece B Flutter shows detail → Task 4. ✓
- Reason enum / side values exact → Global Constraints + Task 2 frozensets + Task 3 mapping. ✓
- Privacy (structural only, backend owns copy) → Task 2 (codes only) + Task 3 (`refusalDetail`) + no-leak assertion. ✓
- Testing per layer + full suites → Tasks 1-5. ✓
- Detection/safety untouched → no task modifies detection; unchanged suites in Task 5. ✓

**Placeholder scan:** No TBD/TODO; every code step has literal code. The one soft spot — `test_grid_endpoint.py` fixture names — is explicitly flagged in Task 2 Step 6 with instructions to reuse the file's existing fixtures. ✓

**Type consistency:** `reason`/`side` names identical across `OcrError` (Py), endpoint JSON, `CvGridError` (JS), `refusalDetail(reason, side)`, and `BaptismalOcrFailure.detail` (Dart). `refusalDetail` returns `string|null`; route only sets `body.detail` when truthy; Flutter reads `decoded['detail']`. `_failure(code, serverMessage, [detail])` optional third arg matches all existing 2-arg calls. ✓
