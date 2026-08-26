# Baptismal OCR Review — Add / Delete / Merge Rows

**Date:** 2026-08-26
**Branch:** `feature/baptismal-ocr-record`
**Status:** Design — awaiting review

## Problem

OCR row detection is imperfect on real register photos (over-counts fragmented multi-line entries, occasionally under-counts). The exact count is not reliably recoverable automatically (see `2026-08-26-baptismal-cv-grid-detection-design.md` findings). The human already reviews every field before saving, so the pragmatic fix is to let them correct the row set directly: add a missing entry, delete a spurious one, and merge one entry that OCR split across two rows.

## Goal

Add per-row **insert / delete / merge** controls to the baptismal OCR review table so staff can fix the row set before saving. Pure in-memory edits on the already-loaded rows; no backend or infrastructure.

## Non-goals

- No split-row, undo, or drag-reorder (YAGNI).
- No backend/CV changes.
- Marriage OCR unchanged.

## Components & data flow

**Model — `lib/models/baptismal_register_row.dart`:**
- `BaptismalRegisterRow.blank()` — a row with empty `lineNo`, `selected = true`, and an `OcrField(value: '', confidence: 1)` for every key in `baptismalFieldKeys` (confidence 1 so a blank added row is never flagged low-confidence; empty values aren't flagged anyway).
- `BaptismalRegisterRow mergedWith(BaptismalRegisterRow other)` — pure. For each key in `baptismalFieldKeys`, the merged value is the two rows' trimmed values joined by a space, skipping empties (`'RENE'` + `'HAGANAS'` → `'RENE HAGANAS'`; `''` + `'X'` → `'X'`). The merged field is marked **edited** (via `OcrField.copyWith(value:)`), since a human triggered it. `lineNo` is this row's `lineNo`; `selected` is `this.selected || other.selected`.

**Widget — `lib/widgets/baptismal_ocr_review_table.dart`:**
- New optional callbacks: `void Function(int)? onInsertRowBelow`, `onDeleteRow`, `onMergeWithNext`.
- A `PopupMenuButton<String>` (key `row-menu-$i`) in each row's leading area — in the wide-table row and the card header — with items:
  - `insert` → "Insert blank row below"
  - `merge` → "Merge with row below" (only shown when `i < rows.length - 1` and `onMergeWithNext != null`)
  - `delete` → "Delete row"
- Menu is rendered only when the corresponding callback is non-null (production wires all three; the widget stays usable without them).

**Page — `lib/screens/admin/pages/baptismal_ocr_scan_page.dart`:**
- Wire the three callbacks to `setState` mutations of `_rows`:
  - insert below `i`: `_rows.insert(i + 1, BaptismalRegisterRow.blank())`.
  - delete `i`: `_rows.removeAt(i)`.
  - merge next: `_rows[i] = _rows[i].mergedWith(_rows[i + 1]); _rows.removeAt(i + 1);`.
  - each also sets `_highlightedRow = null` (indices shift).
- `_issues`, `_canSave`, and the "Save N record(s)" count already derive from `_rows`, so they update automatically.

## Error handling / edge cases

- Merge is unavailable on the last row (guarded in the widget and safe in the page).
- Deleting the last row is allowed → empty table → save disabled (existing `_canSave` logic).
- Structural edits clear `_highlightedRow` to avoid a stale highlight index.

## Testing

- **Model** (`test/baptismal_register_row_test.dart`): `blank()` has all keys empty and selected; `mergedWith` space-joins per field, skips empties, marks edited, unions `selected`.
- **Widget** (`test/baptismal_ocr_review_table_test.dart`): the `row-menu-$i` button exists; selecting `insert`/`delete`/`merge` fires the matching callback with the row index; `merge` is absent on the last row.
- **Scan page** (`test/baptismal_ocr_scan_page_test.dart`): insert adds a blank row and bumps the "Save N" count; delete drops a row; merge concatenates two rows' `nameOfChild` and drops one; save still succeeds after edits.

## Scope

Small, single-plan feature. Flutter only. Reuses the existing review table and scan-page state.
