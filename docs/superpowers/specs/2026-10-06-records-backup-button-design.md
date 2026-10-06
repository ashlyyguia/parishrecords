# Design: "Back Up" button on `/admin/records`

**Date:** 2026-10-06
**Status:** Approved for planning

## Goal

Add a backup action to the Admin Records page (`/admin/records`) that lets an
admin download a JSON backup of the scanned register/certificate record **data**
currently shown on the page.

## Context & constraints

- Records live in Firestore across four collections (`baptism_records`,
  `marriage_records`, `confirmation_records`, `funeral_records`) and are loaded
  into `AdminRecordsPage._records` via `RecordsRepository.list()` with **no row
  limit**.
- Scanned image *files* are **not** stored server-side: register OCR scans are
  built in the router without an `imageUploader` (so `image_ref` stays null),
  and certificate scans only persist locally (native) or trigger a one-time
  browser download (web). Therefore this feature backs up record **data only**
  (names, dates, parish, OCR fields in `notes`, certificate status) — not image
  binaries. Image archiving is explicitly out of scope.
- An existing `AdminBackupPage` already exports data as CSV/JSON/PDF but caps at
  1000 rows and lives on a separate page. This feature is a lighter, in-context
  action on the records page and does not modify that page.
- `ExportService.exportJson(filename, data)` already handles both web (blob
  download) and native (file write) and is reused as-is.

## Behavior

- Add a **"Back Up (JSON)"** button to the header action `Wrap` in
  `AdminRecordsPage` (alongside Manual Register / Import CSV / Add Record (OCR) /
  Scan Certificate / Add Record).
- On press, serialize **the records currently matching the page's filters** —
  the same filtered + sorted list the table renders via `_load()` (applies type,
  parish, date-range, and search) — to JSON via `ExportService.exportJson`.
- Filename: `records_backup_<count>_<YYYY-MM-DDTHH-MM-SS>.json` (colons in the
  timestamp replaced with `-`, matching the existing backup page convention).
- Busy state: disable the button while the export runs.
- Feedback via snackbar:
  - Success: `Backed up N records.`
  - Failure: `Backup failed: <error>`.
  - Empty filtered list: `No records to back up.` and skip the download.

## Serialization (the testable unit)

Extract a pure top-level function into a new file
`lib/services/records_backup.dart`:

```dart
List<Map<String, dynamic>> recordsToBackupJson(List<ParishRecord> records)
```

Each record maps to a full-fidelity map matching the shape `AdminBackupPage`
already uses, for consistency:

```
{
  'id': String,
  'type': String,              // record.type.name
  'name': String,
  'date': String,              // record.date.toIso8601String()
  'imagePath': String?,        // record.imagePath (often null)
  'parish': String?,
  'notes': String?,            // includes OCR-extracted fields JSON
  'certificateStatus': String, // record.certificateStatus.name
}
```

The widget maps its filtered `_load()` items back to their `ParishRecord`
objects (each `_load()` item already carries the live `record` under the
`'record'` key), passes the list to `recordsToBackupJson`, then hands the result
to `ExportService.exportJson`.

## Testing

Unit test `recordsToBackupJson` in `test/records_backup_test.dart`:

- Field mapping is correct for a populated record.
- `date` is ISO-8601 formatted.
- Null `imagePath` / `notes` / `parish` are preserved as null.
- `type` and `certificateStatus` serialize to their enum `.name`.
- Empty input returns an empty list.

## Out of scope

- Archiving or downloading scanned image binaries.
- Any change to the scan/OCR capture flow or backend/storage.
- Changes to the existing `AdminBackupPage`.
- Restore/import of a backup file (export only).
