# Marriage Register OCR — Design

**Date:** 2026-09-16
**Status:** Approved (design), pending implementation plan
**Author:** Ashly Nicole J. Guia (with Claude)

## Goal

Add OCR scanning of the parish **marriage register** spread, mirroring the
existing baptismal OCR pipeline end-to-end. A scanned marriage entry must
produce the **same saved record shape** a manual entry produces
(`marriage_form_screen.dart`), so scanned and typed marriage records are
indistinguishable downstream (record list, detail, certificate generation,
duplicate detection).

Scope decided in brainstorming: **full pipeline, all register columns.**

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

A **scaffold already exists** for marriage: `lib/models/register_marriage_entry.dart`
(`RegisterMarriageEntry` + `MarriagePartyInfo`) mirrors the register layout,
and `marriage_form_screen.dart` defines the canonical saved-notes schema.

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
| License no.              | `marriage.licenseNumber`                  |
| Observations             | `groom.religion` / `bride.religion`       |
| Dates & places of baptism| `remarks` (no dedicated form field)       |

**Approved judgment calls:**
1. **Parents saved as a single blob into `father`** (mother left blank),
   mirroring baptismal's deliberate no-split-of-parents limitation. The
   reviewer splits by hand. Do NOT guess a father/mother midpoint split.
2. **Baptism dates/places → `remarks`** (with a clear label prefix so it's
   obviously carried data, e.g. `Baptism — groom: …; bride: …`).
3. **Observations → `religion`** per party.

`marriage.place` defaults to `"Holy Rosary Parish – Oroquieta City"` (same as
the manual form). `name` = `"Groom & Bride"`. `date` = parsed marriage date or
today. Records saved from OCR review are marked `status: official` (a human
stepped through review), matching baptismal.

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

**Response row shape** (per entry), each leaf an OcrField `{value, confidence,
inherited}`:
```
{ lineNo, groom: {name,status,address,birth,baptism,parents,religion},
  bride: {…same…}, dateOfMarriage, sponsors, minister, licenseNumber }
```

### 3. Flutter

- **`lib/models/ocr_field.dart`** (new): extract `OcrField` + `kOcrReviewThreshold`
  from `baptismal_register_row.dart` into a shared module; both baptismal and
  marriage import it (no marriage→baptismal dependency). Baptismal keeps a
  re-export or updates its import.
- **`lib/models/marriage_register_row.dart`** (new): `MarriageRegisterRow` with
  OcrField-per-field (groom/bride sub-maps + shared fields), `selected`,
  `lineNo`, `fromJson`, `blank()`, `mergedWith()`, and `MarriageOcrScan`
  (mirrors `BaptismalOcrScan`).
- **`lib/services/marriage_ocr_service.dart`** (new, mirrors baptismal service):
  POSTs to the marriage scan route, parses `MarriageOcrScan`, same failure
  taxonomy (`OcrRecovery`).
- **`lib/services/marriage_row_validation.dart`** (new): required = groom name +
  bride name (blocking); date optional. Cross-scan duplicate detection reusing
  the manual form's couple + registry/date logic.
- **`lib/widgets/marriage_ocr_review_table.dart`** (new): wide table with grouped
  **Groom / Bride** sub-columns plus shared columns; same editing, selection,
  insert/delete/merge affordances and `needsReview` highlighting as the
  baptismal table.
- **`lib/screens/admin/pages/marriage_ocr_scan_page.dart`** (new, mirrors
  baptismal page): pick → preview → processing → review → save. Save builds the
  manual-entry notes JSON via a new `ManualRegisterNotes.toMarriageOcrNotesMap`.
  Same injectable seams (ocrService, imagePicker, imageUploader,
  idTokenProvider, saveRecords, existingRecords) for widget tests.
- **Entry point**: the sacrament chooser currently shows "Marriage (coming
  soon)". Replace the paused notice so selecting Marriage opens the new page.
  (Exact routing wiring resolved in the plan.)

## Data flow

```
image bytes
  → MarriageOcrService.scan()
  → POST /api/marriage-ocr/scan
  → fetchGrid(register=marriage)  → rectified crops + cells
  → OCR.space on crops
  → marriageGridToRows()          → groom/bride split, field mapping
  → rows JSON
  → MarriageOcrScan (Flutter)
  → review table (human edits/confirms)
  → save → notes JSON (== manual form) → recordsProvider → Firestore
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
- **Flutter**: `marriage_register_row_test`, `marriage_row_validation_test`,
  `marriage_ocr_service_test`, `marriage_ocr_review_table_test`,
  `marriage_ocr_scan_page_test` — mirroring the baptismal equivalents.
- **E2E sanity**: run the pipeline on a sample photo (e.g. `IMG_3130`) and
  confirm entries land in the right columns with correct groom/bride split.

## Risks

1. **Groom/bride y-split within a cell** is the one genuinely new algorithm.
   Validate against sample photos early; if midpoint split proves fragile,
   fall back to 2-means y-clustering, and always surface
   `GROOM_BRIDE_SPLIT_UNCERTAIN` rather than silently mis-assign.
2. **Parents father/mother** intentionally left as a blob (see judgment call 1).
3. **Wide review table** ergonomics — grouped sub-columns need horizontal
   scroll; mirror baptismal's bounded-scroll approach.
4. **Column boundary drift** — the Python fit reports how many boundaries land
   on detected rules; a bad measurement is caught, not trusted.

## Out of scope (this pass)

- Splitting parents into father/mother from OCR.
- Splitting sponsors beyond the first two witnesses.
- Any change to the baptismal pipeline beyond the shared `OcrField` extraction
  and the `cv_grid_client` `register` param (both backward-compatible).
