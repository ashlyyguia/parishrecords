# Register Fill-Down (batch date / minister) — Design

**Date:** 2026-08-18
**Status:** Approved (design)
**Scope:** Add a "fill-down" control to the editable scan preview so staff set the baptism **date** and **minister** once and apply them to all selected baptism rows — making left-page-only scans savable without right-page OCR.

## Problem

A scanned baptism-**left** page has name / place&birth / parents / residents but **no baptism date** (that column is on the right page). Saving requires a date (`RegisterOcrEntry.isValid` needs a date, and `saveRegisterOcrEntries` uses `entry.date!`), so left-only rows can't be saved as-is. Full right-page OCR is hard (no row anchors; grouped date/minister cells). But the baptism date and minister are **constant across each batch** on the right page — so typing each once and filling it across the selected rows is a robust, low-cost path to savable records.

## Approach

No right-page OCR. Add a bulk-apply ("fill-down") action to the existing editable preview (`StaffOcrResultPage`, baptism only), leveraging that the table already parses a typed date into `entry.date` and that direct save is already wired.

## Component: fill-down mutation (pure)

`applyRegisterFillDown(List<RegisterOcrEntry> entries, {String? date, String? minister}) -> int` (returns rows changed):
- For each entry with `selected == true`:
  - if `date` is non-empty: set `baptismDateText = date` and `date = RegisterOcrParser.parseDate(date)` (may be null if unparseable — `baptismDateText` still set so the row shows it; `parseDate` handles "16 May 2016" and numeric forms).
  - if `minister` is non-empty: set `minister = minister`.
- Rows with `selected == false` are untouched.
- Returns the count of selected rows updated.

Pure and unit-testable without UI. Lives beside the other register helpers (e.g. a static on `RegisterOcrScanHelper` or a small top-level function in the scan-helper file).

## Component: dialog + wiring (thin)

On `StaffOcrResultPage` (baptism, `!_isMarriage`):
- A toolbar button **"Set date / minister…"** next to "Add row".
- Opens an `AlertDialog` with two `TextField`s (Baptism date, hint "e.g. 16 May 2016"; Minister, optional) and an **"Apply to N selected"** action (N = count of currently-selected rows; disabled when N = 0).
- On apply: call `applyRegisterFillDown(_entries, date: …, minister: …)`, `setState`, close the dialog, and show a snackbar "Applied to N row(s)."

## Data flow

```
Scan baptism-left → editable preview (rows, no date)
   → "Set date / minister…" → type once → Apply to selected
   → applyRegisterFillDown sets baptismDateText + parsed date (+ minister)
   → rows become valid → existing "Save" commits to Firestore
```

## Testing

- **Unit:** `applyRegisterFillDown` — sets date + parsed `date` and minister on selected rows only; leaves unselected rows unchanged; returns the changed count; handles an unparseable date (keeps `baptismDateText`, `date` null).
- Dialog wiring is thin and covered by manual/emulator check.

## Non-goals

- Right-page OCR / positional merge.
- Sponsors or residents fill-down (stay per-row editable).
- Marriage register (different fields: date of marriage, minister, license no.).
