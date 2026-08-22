# Baptismal Register OCR (Google Cloud Vision) — Design

**Date:** 2026-08-22
**Status:** Approved (design)
**Branch:** `feature/baptismal-ocr-record` (cut from `ocr` @ ffc30b7)
**Scope:** Rebuild the `/admin/records` → **Add Record (OCR)** flow for **baptismal registers only**, using Google Cloud Vision handwriting OCR behind the backend, with deterministic header-anchored field extraction and a mandatory human review step before any record is saved.

## Problem

### The source document

The samples in `attachments/` (`IMG_3120.jpeg`, `IMG_3121.jpeg`, `IMG_3122.jpeg`) are **not** baptismal certificates. All three are photographs of the same artifact: a bound **Baptismal Register** book, shot on a table at arbitrary rotation (3120 is 90°, 3121 and 3122 are 180°). Each photo captures a two-page spread holding ~24 numbered entries.

Columns, left page (titled *Baptismal*):

| Column | Notes |
|---|---|
| `NO.` | 1..24, printed rule + handwritten numeral |
| `NAME OF CHILD` | two sub-columns: given name(s) \| surname |
| `PLACE & DATE OF BIRTH` | free text, often two lines, e.g. "19 FEBRUARY 2001 / NORTHERN MINDANAO MEDICAL CENTER, CAGAYAN DE ORO CITY" |
| `L or ILL` | legitimacy check-space, usually blank or a tick |
| `NAME OF PARENTS (Mother's Maiden Name)` | two sub-columns: father \| mother |

Columns, right page (titled *Register*):

| Column | Notes |
|---|---|
| `RESIDENTS OF` | address |
| `DATE OF BAPTISM` | e.g. "12 MAY 2016" |
| `MINISTER` | e.g. "FR. PABLITO ARCAPA" |
| `SPONSORS` | two sub-columns |
| `OBSERVATIONS` | mostly blank; carries annotations such as "Married to ..." |

Characteristics that drive the design: all-caps ballpoint handwriting, cramped and variable; heavy repetition down the `MINISTER` and `DATE OF BAPTISM` columns (long runs of the same value, sometimes written as ditto); paper warped at the gutter so ruled column lines bow; a footer reading "In certification thereof, FR. PABLITO D. ARCAPA, Parish Priest".

### Why the current implementation is unreliable

The saved schema is fine. Extraction is the problem.

1. **Wrong engine.** `backend/src/routes/ocr_firestore.js` calls OCR.space (`backend/src/services/ocrspace_service.js`), a printed-text engine with no handwriting model. On-device ML Kit and web Tesseract fare no better on cursive ballpoint. This alone caps achievable accuracy regardless of downstream parsing.
2. **Nondeterministic parsing.** `lib/services/register_ocr_scan_helper.dart` (1592 lines) and `lib/services/register_ocr_parser.dart` (1366 lines) reconstruct the grid from word boxes by clustering, then run five competing strategies — `_parseEntriesFromRowAnchors`, `_entriesFromColumnLayout`, `buildFallbackRowsFromText`, `buildChunkedVerticalRows`, `buildEveryLineRows` — and pick a winner by score (`_bestEntriesFromSources`, `_entryScore`). Which strategy wins shifts on tiny input changes, so results are not reproducible and failures are not diagnosable.
3. **No orientation handling.** Nothing rotates the page. Every sample photo is rotated.
4. **Fragile page join.** The left/right spread is stitched by three alternative paths (`_mergeRegisterPagesByLineNo`, `_mergeRegisterPagesByIndex`, `_appendRegisterPagesSequential`) selected heuristically.

## Decisions

| Decision | Choice | Rationale |
|---|---|---|
| Scan scope | **All rows on the page** | The document is a ledger. One record per scan would mean 24 scans per spread. |
| Field mapping | **Header-anchored geometry** | Printed headers are the one thing OCR reads near-perfectly; they calibrate the grid per photo. Deterministic, testable, no extra API cost. |
| Orientation | **Auto-detect + manual override** | Samples are rotated 90°/180°; detection handles the common case, the override handles the rest. |
| Existing OCR code | **Left in place; new path added alongside** | `staff_ocr_upload_page`, `staff_ocr_bulk_records_page`, `certificate_ocr_extractor` and the household matcher all depend on it. Removing it balloons this branch past baptismal scope. Cleanup is a follow-up. |
| `L/ILL` + `OBSERVATIONS` | **Added to the schema** | Real columns in the book. Additive change, so existing saved records still decode. |

Marriage/matrimonial OCR is explicitly **out of scope**. The layout module is written so a second column map can be added later without touching the Vision or transport layers.

## Architecture

```
Flutter (admin)                    Backend (Express)              Google
─────────────────                  ───────────────────            ──────
BaptismalOcrScanPage
  ├─ pick/capture (OcrImagePick)
  ├─ upload original ──────────────────────────────────────────► Firebase Storage
  │                                                               baptism_scans/{year}/{scanId}.jpg
  ├─ POST /ocr/baptismal/scan ────► baptismal_ocr route
  │                                   ├─ authz + file validation
  │                                   ├─ preprocess (copy only)
  │                                   ├─ BaptismalOcrService ────► Cloud Vision
  │                                   │                            documentTextDetection
  │                                   └─ baptismal_register_layout
  │                                        (pure functions)
  ◄─ rows[] with per-field confidence ─┘
  ├─ Review & edit table
  ├─ Validate required fields
  └─ addRecordsBatch ──────────────► Firestore
```

### Backend: `backend/src/services/baptismal_ocr_service.js`

Sole owner of Vision I/O. Nothing else in the codebase talks to Vision.

- `@google-cloud/vision` `documentTextDetection` (the dense/handwriting-capable mode), `imageContext.languageHints = ['en']`.
- Credentials resolved from `GOOGLE_CLOUD_VISION_CREDENTIALS_JSON`; falls back to `FIREBASE_SERVICE_ACCOUNT_JSON` when unset, since it is the same GCP project — that path only requires enabling the Vision API on the existing project.
- Returns normalized words: `{ text, vertices[4], confidence }`. No parsing, no layout logic.
- Credentials never leave the server. The Flutter client has no Vision dependency and no key.

### Backend: `backend/src/services/baptismal_register_layout.js`

Pure functions, no I/O, no Vision types beyond the normalized word shape. This is the module that determines accuracy, and it is the module under test.

1. **`normalizeOrientation(words)`** — each word's baseline vector comes from its vertex order (`v[0] → v[1]`). Take the modal angle across all words, snap to the nearest 90°, and rotate every coordinate into a space where text reads left-to-right. A coordinate transform only: no re-OCR, no image rewrite, no second API call.
2. **`splitSpread(words)`** — the gutter is the widest low-word-density vertical band in the middle third of the page. Confirmed by locating the printed *Baptismal* and *Register* page titles on either side.
3. **`calibrateColumns(words, pageSide)`** — fuzzy-match printed headers (`NO.`, `NAME OF CHILD`, `PLACE & DATE OF BIRTH`, `L or ILL`, `NAME OF PARENTS`, `RESIDENTS OF`, `DATE OF BAPTISM`, `MINISTER`, `SPONSORS`, `OBSERVATIONS`) to derive x-bands calibrated to *this* photo, absorbing skew and zoom. If a header is unreadable, fall back to proportional bands from the known template and set a `LAYOUT_UNCERTAIN` warning on the scan.
4. **`detectRows(words, columns)`** — cluster the `NO.` column's numerals by y into row anchors and y-bands. Falls back to y-clustering across all left-page words when the numerals are unreadable.
5. **`assignCells(words, columns, rows)`** — each word's box center falls in exactly one (row, column) pair. Words concatenate in reading order. Cell confidence is the mean of its words' confidences.
6. **`joinPages(leftRows, rightRows)`** — join by row index. Both pages share one physical ruling, so index alignment is exact once rows are detected on each side. A row-count mismatch raises a warning rather than silently truncating.
7. **`applyFillDown(rows)`** — narrow, explicit ditto handling for `minister` and `dateOfBaptism` only, applied only when the cell is empty or holds a ditto mark. Every inherited value is tagged `inherited: true` so the reviewer can see it was not actually read.

A value that cannot be confidently placed is left empty and flagged — never guessed.

**Sub-column handling.** `NAME OF CHILD` (given \| surname), `NAME OF PARENTS` (father \| mother) and `SPONSORS` are physically two sub-columns each, but the existing saved schema is flat. Sub-columns are detected during calibration and concatenated on output: name parts joined with a space, parents and sponsors joined with `" / "` — matching what `ManualRegisterNotes.parentsText` already produces and reads back.

Row output shape:

```json
{
  "lineNo": "1",
  "fields": {
    "nameOfChild":      { "value": "JEZL ANTOINETTE HITUTUAAN", "confidence": 0.71 },
    "placeAndBirthDate":{ "value": "19 FEBRUARY 2001 ...",      "confidence": 0.54 },
    "legitimacy":       { "value": "",                          "confidence": 0.0  },
    "parents":          { "value": "LITA / HITUTUAAN",          "confidence": 0.62 },
    "residentsOf":      { "value": "P-2 CANITOAN, CAGAYAN DE ORO CITY", "confidence": 0.66 },
    "dateOfBaptism":    { "value": "12 MAY 2016", "confidence": 0.81, "inherited": false },
    "minister":         { "value": "FR. PABLITO ARCAPA", "confidence": 0.78, "inherited": true },
    "sponsors":         { "value": "...", "confidence": 0.49 },
    "observations":     { "value": "", "confidence": 0.0 }
  }
}
```

`needsReview` is derived client-side from `confidence < 0.60 || inherited || (required && empty)`.

### Backend: `backend/src/routes/baptismal_ocr_firestore.js`

`POST /ocr/baptismal/scan`

- `verifyFirebaseToken`, then role ∈ {`admin`, `staff`}.
- File validation: mime sniffed from **magic bytes**, not the client's claim; accepted set `{image/jpeg, image/png, image/webp}`; hard cap 10 MB.
- Response: `{ success: true, data: { scanId, rows, columns, rotation, pageSplit, warnings } }`, where `scanId` is generated **client-side** (uuid) and sent with the request, so the Storage upload and the OCR call agree on it without a round-trip ordering dependency; `columns` returns the calibrated x-bands and `rotation` the applied angle, both so the review screen can draw row/column highlights over the image; `warnings` is a list of non-fatal codes such as `LAYOUT_UNCERTAIN` or `ROW_COUNT_MISMATCH`.
- Errors carry a machine-readable `code` so the UI can give a specific message and a specific retry affordance:

| Code | HTTP | Meaning |
|---|---|---|
| `IMAGE_INVALID` | 400 | Not a supported image, or magic bytes disagree with the declared type |
| `IMAGE_TOO_LARGE` | 413 | Over 10 MB |
| `VISION_AUTH` | 500 | Credentials missing or rejected (server misconfiguration) |
| `VISION_QUOTA` | 429 | Vision quota or rate limit hit |
| `VISION_UNAVAILABLE` | 502 | Vision unreachable or timed out |
| `NO_TEXT_FOUND` | 422 | Vision returned no text — blank, blurred, or unreadable photo |
| `LAYOUT_UNRECOGNIZED` | 422 | Text found but no column headers matched; not a baptismal register page |

- **Logging:** counts, codes, timings, `scanId` only. Never cell values — these are records of minors.

### Preprocessing

`sharp` operates on a **buffer copy**: grayscale → normalize → sharpen → cap the long edge at 4096px, purely to feed Vision. The original bytes are never mutated and are the bytes archived to Storage.

*Risk, stated up front:* `sharp` is a native module and can need a platform flag on Render. If it obstructs deploy, the fallback is sending the original buffer — Vision handles it acceptably — rather than blocking the feature. This will be noted, not silently swapped.

### Frontend

| File | Responsibility |
|---|---|
| `lib/models/baptismal_register_row.dart` | `BaptismalRegisterRow`, `OcrField { value, confidence, inherited, needsReview }` |
| `lib/services/baptismal_ocr_service.dart` | Typed HTTP client for `/ocr/baptismal/scan`; maps error codes to typed failures |
| `lib/screens/admin/pages/baptismal_ocr_scan_page.dart` | The stepper |

The stepper:

- **Step 1 — Upload/Capture.** Reuses `OcrImagePick.pickRegisterPages`, which already does camera on mobile and file-picker on web/desktop. Shows a preview with rotate-left / rotate-right manual override. Primary action: *Scan / Process OCR*.
- **Step 2 — Processing.** Determinate-where-possible progress with explicit stage labels (uploading original → recognizing text → mapping fields).
- **Step 3 — Review.** Zoomable image pane beside the editable table. Tapping a row highlights its band on the image. Amber = low confidence, blue = inherited by fill-down, red = required and empty. Every cell is editable. Rows can be deselected.
- **Step 4 — Validate.** Save is blocked until every *selected* row satisfies the rules below; a summary names the offending rows.
- **Step 5 — Save.** Batch commit, then a confirmation naming the count saved and linking back to `/admin/records`.

The `/admin/records` "Add Record (OCR)" button (currently `context.push('/admin/ocr/upload')`, `lib/screens/admin/pages/records_page.dart:346`) repoints to the new route. Staff OCR pages, certificate scan, and household OCR-matching keep their existing path untouched.

### Validation

Per selected row, before save:

- `nameOfChild` — required, non-empty after trim.
- `dateOfBaptism` — required, must parse (reuse `RegisterOcrParser.parseDate`, which already handles "16 May 2016" and numeric forms).
- Date sanity — parsed baptism date within 1900..today.
- Birth date, when parseable from `placeAndBirthDate`, must not fall after the baptism date.
- All other fields optional; saved as trimmed text.
- **Duplicate check** — same `nameOfChild` + same baptism date already in records warns and requires explicit override. No duplicate detection exists in the codebase today, so this is new behavior.

### Save path and image preservation

Reuses `RegisterRecordDraft` + `ref.read(recordsProvider.notifier).addRecordsBatch(drafts)`, matching `lib/services/register_ocr_record_save.dart`.

`ManualRegisterNotes.toNotesMap` gains `legitimacy`, `observations`, `ocrScanId`, `originalImagePath`, and `source: 'baptismal_ocr_vision'`. Additive — `tryDecode` and the existing readers are unaffected, and older records without these keys still decode.

The original image uploads **before** OCR to Firebase Storage at `baptism_scans/{year}/{scanId}.jpg`, following the `putData` convention already used in `lib/services/events_repository.dart`. A failed scan therefore never loses the upload, and retry costs no re-upload.

## Error handling

Every failure keeps the uploaded image in memory and on Storage, and offers *Retry OCR* without re-picking the file.

| Condition | User-facing behavior |
|---|---|
| Invalid format / too large | Rejected at pick time where possible, at the route otherwise; message names the limit |
| `VISION_AUTH` | "OCR is not configured on the server" + admin-facing hint; retry disabled (retrying cannot help) |
| `VISION_QUOTA` / `VISION_UNAVAILABLE` / network | Transient message + retry enabled |
| `NO_TEXT_FOUND` | Suggests re-photographing with better light/framing; retry enabled |
| `LAYOUT_UNRECOGNIZED` | Explains the page did not look like a baptismal register; offers to proceed to a blank manual table with the image attached |
| Low confidence | Not an error — flagged amber in review |
| Missing required fields | Blocks save, names the rows |

## Testing

Vision responses for the three `attachments/` images are recorded **once** and committed as JSON fixtures under `backend/test/fixtures/`. Layout tests then run offline — no credentials, no quota, no network — which is what makes this pipeline regression-testable in a way the current one is not.

**Backend (Jest):**
- `normalizeOrientation` — 0°, 90°, 180°, 270° inputs all normalize to the same reading frame.
- `splitSpread` — gutter found on all three fixtures; page titles confirm sides.
- `calibrateColumns` — all ten headers matched; missing-header fallback sets `LAYOUT_UNCERTAIN`.
- `detectRows` — row count matches the fixture; fallback path exercised with the `NO.` column removed.
- `assignCells` — spot-checked cells land in the right column for known rows.
- `joinPages` — index join; row-count mismatch warns rather than truncates.
- `applyFillDown` — fills only `minister`/`dateOfBaptism`, only into empty/ditto cells, tags `inherited`.
- Route — authz, role gate, magic-byte validation, size cap, and each error code, with Vision mocked.

**Flutter:**
- Model parsing from the response envelope, including `needsReview` derivation.
- Validation rules: required fields, date parse, date sanity, birth-before-baptism, duplicate detection.
- Widget test: review table edits a cell, deselects a row, and confirms save stays blocked while a required field is empty.

**Manual, against the sample images:** correct field population, editing OCR results, missing required fields, invalid image, simulated API failure, save after corrections, and a regression pass confirming existing non-OCR baptismal record entry still works.

## Constraints and known limits

- **Fixture recording needs credentials.** Vision cannot be called from this environment. Until fixtures are recorded against the real API, layout logic is developed against hand-authored fixtures derived from the sample images; the recorded fixtures are required before accuracy claims are made.
- **Network required.** This path cannot scan offline the way the ML Kit path can. The old path remains available for that.
- **One register template.** Column calibration targets the layout in `attachments/`. A structurally different register book will hit `LAYOUT_UNRECOGNIZED` rather than produce wrong data — the intended failure mode.

## Non-goals

- Marriage/matrimonial OCR.
- Retiring ML Kit, Tesseract, or OCR.space, or refactoring `register_ocr_scan_helper.dart` / `register_ocr_parser.dart`.
- Changing certificate scanning or household OCR-matching.
- Auto-saving any OCR output without human review.
