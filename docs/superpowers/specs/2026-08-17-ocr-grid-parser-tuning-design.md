# OCR Grid Parser Tuning (Baptism-Left) — Design

**Date:** 2026-08-17
**Status:** Approved (design)
**Scope:** Fix register row reconstruction for real OCR.space cells on the **baptism-left** page: a pitch-based grid reconstructor, measured against a real fixture + hand-keyed ground truth via the existing accuracy harness, tuned until the ~24 rows come out clean. Other pages/marriage are follow-on.

## Problem & evidence

Cloud OCR (OCR.space) reads the handwritten baptism register well (validated: 401 correctly-shaped word cells, good text). But feeding those real cells through `RegisterOcrScanHelper.parseEntriesFromCells` produced **102 scrambled rows** instead of ~24 — names from multiple people merged, columns misaligned.

Root cause (measured on `book-scan/baptism_left.cells.json`): the parser reconstructs rows from the register's **"No." column**, but OCR.space recognized only **13 of ~24 row numbers** (`5,6,10,12,13,14,16,19,19,20,21,22,24` — missing 1–4, 7–9, 11, etc., plus a duplicate). Banding rows between sparse/wrong anchors collapses several entries into one row.

The reliable signal the data hands us: the rows are **evenly pitched** (~48–58px; tops span 301→1630 for 24 entries). Reconstructing rows from that pitch — engine-agnostically — instead of trusting recognized numbers is the fix.

## Approach (chosen)

A new pure, unit-testable **grid reconstructor** — not tuning the existing anchor heuristics (which build on the wrong signal), not string-parsing OCR.space's messy flat text.

## Architecture & data flow

```
OCR.space cells (List<OcrLineBox>)
        │
        ▼
reconstructBaptismGrid(cells)   ← NEW, pure, unit-tested
   1. column x-bands   2. row grid from pitch   3. assign + merge
        │
        ▼
List<RegisterOcrEntry>  (~24, one per register row)
        │
        ├──► top-priority strategy inside parseEntriesFromCells
        │     (plausibility guardrail: falls back to existing strategies
        │      if it yields <3 rows or empty names — never regresses on-device)
        ▼
scanResultFromCloud → review table   (downstream unchanged)

MEASUREMENT (offline harness):
  fixture cells + hand-keyed expected → scanResultFromCloud → ocr_scoring → baseline/target
```

The reconstructor is self-contained: input `List<OcrLineBox>`, output `List<RegisterOcrEntry>`, no I/O, no engine coupling.

## Component: `reconstructBaptismGrid`

`static List<RegisterOcrEntry> RegisterOcrScanHelper.reconstructBaptismGrid(List<OcrLineBox> cells)`:

1. **Column bands.** Cluster cell `centerX` into gap-separated bands (reuse `_detectColumnCenters`-style logic), map left-to-right onto the known baptism-left columns: `No | Name of Child | Place & Date of Birth | Name of Parents | Residents of`. The narrow "L/Ill" checkbox column is ignored.
2. **Row grid from pitch (the core fix).** Estimate row **pitch** and **phase** from whatever No.-column numeric cells exist, normalizing each gap by the difference in row numbers (e.g., `6@664 → 10@857` = 193/4 ≈ 48px) and taking the median (~50px). Project evenly-spaced row centers from the first data row to the last, yielding ~24 rows regardless of which numbers were read. If too few numeric anchors exist to estimate pitch, fall back to gap-based y-clustering of the leftmost name column.
3. **Assign + merge.** Drop header cells (above the first row center). Assign each remaining cell to the nearest row center (tolerance ≈ pitch/2) and to its column band. Within each (row, column), concatenate cells sorted by `(top, left)` — this merges the two-line child name (given + surname) into one string.
4. **Build entries.** One `RegisterOcrEntry` per row: sequential `lineNo` 1..N, plus `name`, `placeAndBirthDate`, `parents`, `residentsOf`, reusing existing `entryFromColumnTexts` / date-parsing helpers. Rows with no recognizable name are dropped.

**Integration:** `parseEntriesFromCells` tries `reconstructBaptismGrid` first; if it returns a plausible result (≥3 rows with non-empty names) that result is used, otherwise the existing strategies run as today. This keeps the ML Kit / on-device path unaffected.

## Component: fixture, ground truth, scoring

- **Fixture:** convert `book-scan/baptism_left.cells.json` to the harness schema and commit as `test/ocr/fixtures/baptism_left.json` — `{image, recordType:"baptism", page:"left", capturedWith:"ocrspace", flatText, cells}`.
- **Ground truth:** `test/ocr/fixtures/baptism_left.expected.json` — 24 hand-keyed rows (`lineNo`, `name`, `placeAndBirthDate`, `parents`, `residentsOf`), drafted from the photo and **verified by the user** before the numbers are trusted.
- **Scoring:** reuse `test/ocr/support/ocr_scoring.dart`, `register_ocr_fixture.dart` (`loadFixture`/`loadExpected`/`entryToFieldMap`). Left-page fixtures have empty minister/sponsors on both sides (neutral in scoring).

## Baseline & acceptance target

- **Baseline:** measure the current scrambled output first and record it (low row recall + low name similarity) — the "before" number.
- **Golden-test target:** row structure first, then names — **row recall ≥ 0.9** and **mean name similarity ≥ 0.6** (allowing OCR character errors on cursive). Place/parents/residents are reported but not gated in this first pass. Exact committed floors are the measured tuned result rounded down.
- **Known metric caveat:** scoring matches rows by `lineNo`, and the reconstructor numbers rows sequentially 1..N, so a missed middle row shifts subsequent positions and is penalized hard. Intentional — getting the row grid right is the goal.

## Testing

- **Unit tests for `reconstructBaptismGrid`** with a small synthetic cell set (2–3 rows, two-line names, a couple of recognized No. cells): assert row count, given+surname merge, and column assignment. Pure and deterministic.
- **Golden test** on the committed real fixture: `scanResultFromCloud(cells, flatText, recordType:"baptism")` → `entryToFieldMap` → `scoreRows` → assert ≥ target, print the per-field report.

## Non-goals (follow-on specs)

- Baptism-right page, both marriage pages, cross-page merge-by-No.
- Deep per-field tuning beyond the row-recall + name target (place/parents/residents optimization).
- Generalizing column mapping to other register books/layouts.
- Capturing the remaining fixtures via the debug tool (this spec uses the already-captured baptism-left cells).
