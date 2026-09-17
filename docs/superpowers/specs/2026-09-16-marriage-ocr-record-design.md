# Marriage Register OCR — Design

**Date:** 2026-09-16
**Status:** Approved (design), pending implementation plan
**Author:** Ashly Nicole J. Guia (with Claude)

## Goal

Add OCR scanning of the parish **marriage register** spread, mirroring the
existing baptismal OCR pipeline end-to-end. A scanned marriage entry must
produce the **same saved record shape** the existing manual marriage
**register** entry produces (the flat `manual_marriage_register` schema from
`ManualRegisterNotes.toMarriageNotesMap`, built from `RegisterMarriageEntry`),
so scanned and typed marriage records are indistinguishable downstream (record
list, detail, certificate generation, duplicate detection).

Scope decided in brainstorming: **full pipeline, all register columns.**
Approach corrected 2026-09-16 after discovering the existing marriage
infrastructure (see Background) — reuse it rather than build a parallel model.

## Background

The baptismal OCR feature already ships a three-layer pipeline:

1. **Python CV service** (`ocr_service/`) — detects the register's ruled grid,
   returns rectified page crops + labeled cells. `column_template.py` is
   *data only* and its docstring explicitly anticipates this work: *"Adding
   support for another register book — a marriage or burial register — is a
   matter of adding another `ColumnTemplate` constant here. No detection code
   changes."*
2. **Node backend** (`baptismal_ocr_firestore.js`, `baptismal_grid_assign.js`,
   `baptismal_register_layout.js`) — OCR.space on the crops, word→cell
   assignment, with a word-clustering fallback when CV is unavailable.
3. **Flutter** (`baptismal_ocr_scan_page.dart`, `baptismal_ocr_review_table.dart`,
   `baptismal_register_row.dart`, `baptismal_row_validation.dart`) —
   pick → preview → OCR → review/edit → save.

**Substantial marriage infrastructure already exists** (the legacy ML-Kit OCR
path) and is reused here:
- `lib/models/register_marriage_entry.dart` (`RegisterMarriageEntry` +
  `MarriagePartyInfo`) — mirrors the register layout column-for-column.
- `lib/widgets/register_marriage_table.dart` (`RegisterMarriageTable`) — an
  editable review table with exactly these columns and horizontal scroll.
- `ManualRegisterNotes.toMarriageNotesMap` — the flat `manual_marriage_register`
  save schema (the analog of `toBaptismalOcrNotesMap`).
- `lib/screens/staff/pages/staff_ocr_upload_page.dart` (`StaffOcrUploadPage`,
  routed at `/admin/ocr/upload` + `/staff/ocr/upload`) — the legacy ML-Kit
  marriage/baptism scanner. **Left untouched**; the new CV-grid scanner is an
  additional, higher-quality route.

Two `marriage` notes schemas exist and must not be confused: the **flat
register** schema above (what this feature saves) and the **certificate** form
schema in `marriage_form_screen.dart` (`marriage`/`groom`/`bride`/`witnesses`
nesting) — the latter is NOT the target here.

## The marriage register layout (from sample photos)

A two-page spread, same photographing style as baptismal. 12 logical columns:

**Left page** (title "Marriage"):
1. NO.
2. CONTRACTING PARTIES — *paired* (groom top line, bride bottom line)
3. LEGAL STATUS — *paired* (e.g. single / single)
4. ACTUAL ADDRESS — *paired*
5. DATES & PLACES OF BIRTH — *paired*
6. DATES & PLACES OF BAPTISM — *paired*
7. DATE OF MARRIAGE — shared

**Right page** (title "Register"):
8. PARENTS — *paired* (each party's parents)
9. SPONSORS OF MARRIAGE — shared (list of witnesses)
10. MINISTER — shared
11. LICENSE NO. — shared
12. OBSERVATIONS — *paired* (typically "catholic" / rite per party)

Each numbered entry occupies **two physical writing lines** (groom on top,
bride below), which is what makes most columns "paired."

## Field mapping: register → saved notes

The save writes the **identical** JSON `marriage_form_screen.dart` builds, so
records match regardless of entry method.

| Register column          | Saved notes field                         |
|--------------------------|-------------------------------------------|
| NO.                      | `meta.lineNo`                             |
| Contracting parties      | `groom.fullName` / `bride.fullName`       |
| Legal status             | `groom.civilStatus` / `bride.civilStatus` |
| Actual address           | `groom.address` / `bride.address`         |
| Dates & places of birth  | `groom.ageOrDob` / `bride.ageOrDob`       |
| Date of marriage         | `marriage.date`                           |
| Parents                  | `groom.father` / `bride.father` (blob)    |
| Sponsors of marriage     | `witnesses.witness1` / `witnesses.witness2` |
| Minister                 | `marriage.officiant`                      |
| License no.              | `licenseNumber`                           |
| Observations             | `observations`                            |
| Dates & places of baptism| `groom.datesPlaceOfBaptism` / `bride.datesPlaceOfBaptism` |

**Save target (corrected 2026-09-16):** The saved record uses the **flat
marriage register schema** — the same one `ManualRegisterNotes.toMarriageNotesMap`
already produces for the legacy path (`source: manual_marriage_register`),
built from `RegisterMarriageEntry` / `MarriagePartyInfo`. Every register column
maps **1:1** to a model field, so there is **no lossy mapping** — the earlier
plan to fold parents→father, baptism→remarks and observations→religion (which
targeted the *certificate* form `marriage_form_screen.dart`) is **dropped**.

`MarriagePartyInfo` per-party fields: `name`, `legalStatus`, `actualAddress`,
`datesPlaceOfBirth`, `datesPlaceOfBaptism`, `parents`, `sponsors`. Shared
entry fields: `dateOfMarriage`, `minister`, `licenseNumber`, `observations`,
`lineNo`. (Note: `sponsors` exists per-party on the model; the register's
Sponsors-of-Marriage column is one shared list, so the OCR writes it to
`groom.sponsors` and leaves `bride.sponsors` empty — the reviewer can adjust.)

`name` (the `ParishRecord.name`) = `entry.recordDisplayName` (`"Groom & Bride"`).
`date` = `ManualRegisterNotes.marriageDateForEntry(entry)` (parsed
`dateOfMarriage`, or today). Records saved from OCR review are marked
`status: official` and carry scan provenance (`ocrScanId`, `originalImagePath`),
matching `toBaptismalOcrNotesMap`.

## Component design

### 1. Python CV service (`ocr_service/`)

- **`app/pipeline/column_template.py`**: add `MARRIAGE_LEFT`, `MARRIAGE_RIGHT`
  `ColumnTemplate`s and a `MARRIAGE_REGISTER` `SpreadColumnTemplate`. Column
  `key`s are the downstream field keys (`no`, `contracting_parties`,
  `legal_status`, `actual_address`, `birth`, `baptism`, `marriage_date`;
  `parents`, `sponsors`, `minister`, `license_no`, `observations`). Boundary
  fractions (of the table's own extent) are **measured from the straight-on
  sample photos** during implementation, read independently on ≥3 photos and
  required to agree to ~0.01, exactly as the baptismal boundaries were derived.
  `data_row_count` = number of numbered entries the printed form is ruled for.
- **`app/main.py`**: `/v1/grid` reads a `register` query param
  (`marriage`|`baptismal`, default `baptismal`) and selects the spread template.
  No detection-code changes.

### 2. Node backend

- **`cv_grid_client.js`**: `fetchGrid(buffer, { register })` appends
  `?register=…` to the CV URL. Default `baptismal` keeps existing callers
  unchanged.
- **`marriage_grid_assign.js`** (new, mirrors `baptismal_grid_assign.js`):
  maps grid cell `key`s → marriage fields. For **paired** columns, split the
  cell's words into groom (top) / bride (bottom) by each word's y-center vs the
  cell's vertical midpoint. Shared columns take all words. Emits
  `GROOM_BRIDE_SPLIT_UNCERTAIN` when a paired cell has words but they can't be
  cleanly separated into two y-bands.
- **`marriage_register_layout.js`** (new, mirrors `baptismal_register_layout.js`):
  word-clustering fallback. Column header tokens: left — `contracting`,
  `legal`/`status`, `actual`/`address`, `birth`, `baptism`, `marriage`/`date`;
  right — `parents`, `sponsors`, `minister`, `license`, `observations`. Gutter
  titles confirmed via `marriage` (left) / `register` (right). Groom/bride
  split within each row band by y as above.
- **`marriage_ocr_firestore.js`** (new, mirrors `baptismal_ocr_firestore.js`):
  `/scan` route — same image gate (HEIC convert, magic bytes, decodability,
  size), CV-first with `register: 'marriage'`, OCR on crops,
  `marriageGridToRows`, fallback on non-refusal CV errors. Same error codes and
  copy, with marriage-appropriate `LAYOUT_UNRECOGNIZED` message. Mounted
  alongside the baptismal router in `server.js`.

**Response row shape** (per entry). OCR.space provides no per-field
confidence, so the response carries plain string values (matching the
`RegisterMarriageEntry` model), plus a scan-level `warnings` array. Paired
columns carry `groom`/`bride` sub-values; shared columns are flat:
```
{
  scanId, rotation, warnings: [...],
  rows: [
    { lineNo,
      groom: { name, legalStatus, actualAddress, datesPlaceOfBirth,
               datesPlaceOfBaptism, parents, sponsors },
      bride: { …same keys… },
      dateOfMarriage, minister, licenseNumber, observations }
  ]
}
```
This is the JSON shape `MarriageOcrService` parses into
`List<RegisterMarriageEntry>` (via a `RegisterMarriageEntry.fromScanJson`
factory / `ManualRegisterNotes`-style mapper), so no new per-cell model is
introduced.

### 3. Flutter (reuse existing marriage model + table)

No `OcrField` extraction and no new row model — OCR.space has no per-field
confidence, so plain strings on `RegisterMarriageEntry` suffice.

- **`lib/models/register_marriage_entry.dart`** (modify): add a
  `RegisterMarriageEntry.fromScanJson(Map)` factory that builds an entry (with
  a fresh uuid) from one backend row of the shape above. Pure, no I/O.
- **`lib/services/marriage_ocr_service.dart`** (new, mirrors
  `baptismal_ocr_service.dart`): POSTs `{scanId, imageBase64}` to the marriage
  scan route, reuses the same `OcrRecovery` / failure taxonomy, returns a
  `MarriageOcrScan { scanId, rotation, warnings, entries: List<RegisterMarriageEntry> }`.
- **`lib/utils/manual_register_notes.dart`** (modify): add
  `toMarriageOcrNotesMap({volNo, seriesNo, entry, scanId, imagePath,
  status='official'})` — the flat register schema from `toMarriageNotesMap`
  plus `ocrScanId` / `originalImagePath`, mirroring `toBaptismalOcrNotesMap`.
  `source` stays `manual_marriage_register` so existing readers
  (`isManualMarriageMap`, record detail, search) keep working unchanged.
- **`lib/services/marriage_row_validation.dart`** (new): required to save an
  entry = groom name **and** bride name non-empty (blocking); date optional
  (falls back to today). Cross-scan duplicate detection reusing the
  couple + registry/date logic from `marriage_form_screen._findPossibleDuplicates`.
- **`lib/widgets/register_marriage_table.dart`** (reuse; extend if needed): the
  existing editable marriage table already has the exact columns. Add row
  selection checkboxes / per-row highlight hooks only if the scan page needs
  them beyond the current `onChanged`/`onSelectionChanged`/`onRemove` seams.
- **`lib/screens/admin/pages/marriage_ocr_scan_page.dart`** (new, mirrors
  `baptismal_ocr_scan_page.dart`): pick → preview → processing → review → save.
  Review step hosts `RegisterMarriageTable`. Save builds notes via
  `toMarriageOcrNotesMap` and writes `RecordType.marriage` records. Same
  injectable seams (ocrService, imagePicker, imageUploader, idTokenProvider,
  saveRecords, existingRecords) for widget tests.
- **Entry point / routing**: add `/admin/records/ocr-marriage` →
  `MarriageOcrScanPage` (alongside `/admin/records/ocr-baptism`). The baptismal
  page's sacrament chooser currently shows "Marriage (coming soon)"; selecting
  Marriage there navigates to the new route instead of showing the paused notice.

## Data flow

```
image bytes
  → MarriageOcrService.scan()
  → POST /api/marriage-ocr/scan
  → fetchGrid(register=marriage)  → rectified crops + cells
  → OCR.space on crops
  → marriageGridToRows()          → groom/bride split, field mapping
  → rows JSON
  → MarriageOcrScan → List<RegisterMarriageEntry> (Flutter)
  → RegisterMarriageTable (human edits/confirms)
  → save → toMarriageOcrNotesMap (flat register schema) → recordsProvider → Firestore
```

## Error handling & warnings

Reuse baptismal codes/status/messages. New:
- `GROOM_BRIDE_SPLIT_UNCERTAIN` — a paired cell's two lines couldn't be
  separated; reviewer must check groom vs bride assignment for that row.
Marriage-specific copy for `LAYOUT_UNRECOGNIZED` / `SPREAD_UNREADABLE`.

## Testing (TDD at every layer)

- **Python**: `test_column_template` (marriage template valid, boundaries
  strictly increasing, count matches); `test_grid_endpoint` with
  `register=marriage`; synthetic marriage fixture in `tests/support/synthetic.py`.
- **Node**: `marriage_register_layout.test.js` (column calibration + groom/bride
  y-split + gutter/title confirm + row detection), `marriage_grid_assign.test.js`
  (key mapping + paired split + shared cells), `marriage_ocr_firestore.test.js`
  (route: auth, image gate, CV path, fallback, error mapping).
- **Flutter**: `register_marriage_entry_test` (the `fromScanJson` factory),
  `marriage_row_validation_test`, `marriage_ocr_service_test`,
  `manual_register_notes` marriage-OCR-notes coverage, and
  `marriage_ocr_scan_page_test` — mirroring the baptismal equivalents.
- **E2E sanity**: run the pipeline on a sample photo (e.g. `IMG_3130`) and
  confirm entries land in the right columns with correct groom/bride split.

## Risks

1. **Groom/bride y-split within a cell** is the one genuinely new algorithm.
   Validate against sample photos early; if midpoint split proves fragile,
   fall back to 2-means y-clustering, and always surface
   `GROOM_BRIDE_SPLIT_UNCERTAIN` rather than silently mis-assign.
2. **`sponsors` per-party vs shared** — the model carries `sponsors` per party
   but the register column is one shared list; OCR writes it to `groom.sponsors`.
   Reviewer adjusts. Not a data-loss issue, just a placement choice.
3. **Wide review table** ergonomics — `RegisterMarriageTable` already handles
   horizontal scroll (`_minTableWidth = 2480`); reuse as-is.
4. **Column boundary drift** — the Python fit reports how many boundaries land
   on detected rules; a bad measurement is caught, not trusted.

## Out of scope (this pass)

- Splitting parents into father/mother from OCR (kept as one `parents` blob per
  party, matching the register column and the legacy manual path).
- Splitting sponsors beyond the shared list into per-party.
- Any change to the baptismal pipeline beyond the `cv_grid_client` `register`
  param (backward-compatible; default `baptismal`).
- Any change to or removal of the legacy ML-Kit marriage path
  (`StaffOcrUploadPage` etc.); the new CV-grid scanner is an additional route.
