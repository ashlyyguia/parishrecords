# OCR Accuracy Harness — Design

**Date:** 2026-08-17
**Status:** Approved (design)
**Scope:** Approach A only — build a measurement harness for the on-device (ML Kit / native) parish register OCR pipeline, establish a baseline, and make future tuning measurable and regression-safe.

## Problem

The parish register OCR pipeline is mature (~2,700 lines): a geometry path
(`register_ocr_scan_helper.dart`, bounding-box row/column clustering) and a
string path (`register_ocr_parser.dart`, scored multi-strategy regex parsing),
feeding models that map exactly to the Baptismal and Marriage register layouts.

The goal is to **tune extraction accuracy on real photos** (four sample images
in `book-scan/`: two Baptismal pages, two Marriage pages — dense handwritten
two-page spreads shot by hand at an angle).

The blocker: **there is no way to measure accuracy.** No ground-truth fixtures,
no golden tests, no metric — only the unrelated `certificate_ocr_extractor_test.dart`.
Today accuracy can only be checked by running the app on a device and eyeballing
it. You cannot systematically tune 2,700 lines of heuristics that way, and
because ML Kit cannot run inside `flutter test`, you cannot write an ordinary
unit test against it either.

## Honest constraint

On-device ML Kit `TextRecognizer` is optimized for **printed** text. These
registers are dense **cursive handwriting** at an angle. ML Kit reliably reads
printed anchors (minister names `Fr./Msgr.`, year stamps, section headers) and
recovers *structure* reasonably, but it will misread many handwritten names
regardless of parser tuning. This harness measures and improves **row/column
segmentation, dates, and printed fields**; it will not make cursive names highly
accurate. Cracking handwriting recognition is a separate lever (cloud OCR,
Approach C) and is out of scope here.

## Target platform

Native mobile (Android/iOS, **Google ML Kit**). Web/Tesseract fixtures are a
follow-on, not part of this spec.

## Architecture: capture vs. replay

ML Kit runs only on a device/emulator; tests run offline. Split the two:

```
   ON DEVICE (once per image)              OFFLINE (every test run, no ML Kit)
┌──────────────────────────────┐      ┌────────────────────────────────────────┐
│ pick image → ML Kit OCR      │      │ load fixture JSON (cells + flat text)    │
│ → serialize recognized cells │─────▶│ → parseEntriesFromCells(...)             │
│   (text + bounding box) to   │ .json│ → score vs hand-keyed ground truth       │
│   committed fixture JSON      │ file │ → assert ≥ baseline, print field report  │
└──────────────────────────────┘      └────────────────────────────────────────┘
```

### Required refactor (behavior-preserving)

`parseEntriesFromBlocks(List<TextBlock>)` cannot be replayed offline because
`TextBlock` is an ML Kit sealed class. Its first step is already
`linesFromBlocks(blocks)` → `List<OcrLineBox>` (a plain data class we own).
Split it at that seam:

- `parseEntriesFromBlocks(blocks)` → thin wrapper:
  `parseEntriesFromCells(linesFromBlocks(blocks))`.
- `parseEntriesFromCells(List<OcrLineBox> cells)` → holds the existing geometry
  logic; this is what tests replay against.
- `OcrLineBox` gains `toJson` / `fromJson` (it already carries
  `text / top / left / width / height`).

The on-device call path is unchanged; it only gains a testable seam.

## Fixture format

One file per image, committed under `test/ocr/fixtures/`:

```json
{
  "image": "741704936_...n.jpg",
  "recordType": "baptism",
  "page": "left",
  "capturedWith": "mlkit-latin",
  "flatText": "Alberto Saligumba\nTuburan, Villaflor ...",
  "cells": [
    { "text": "1", "top": 412.0, "left": 88.0, "width": 24.0, "height": 30.0 },
    { "text": "Alberto", "top": 410.0, "left": 150.0, "width": 120.0, "height": 32.0 }
  ]
}
```

`cells` is exactly what `linesFromBlocks` produces, so `parseEntriesFromCells`
replays it verbatim. `flatText` feeds the string-path test case.
`recordType` / `page` select the parser and the applicable expectations.

Fixtures are **per-page**: 4 fixtures = 2 baptism pages + 2 marriage pages. Each
logical record is a two-page spread (left page = name/place/birth/parents/
residents; right page = minister/sponsors/observations, aligned by row `No.`),
so per-page expectations assert only fields visible on that page. Cross-page
merge-by-`No.` is a follow-on that reuses these same fixtures.

## Capture tool

A `kDebugMode`-gated dev action (a debug button on the existing preprocess/upload
page, or a hidden `/dev/ocr-dump` route) that:

1. picks an image via the existing `OcrImagePick`,
2. runs `OcrService.recognizeText` (ML Kit),
3. serializes `{image, flatText, cells}` to JSON,
4. writes it to app-documents, copies it to clipboard, and `debugPrint`s it.

Run once per image on an Android emulator to produce the 4 fixtures (retrieve via
clipboard/run-log or `adb pull`). `recordType` / `page` / expected entries are
then filled in by hand. This code is excluded from release builds.

## Ground truth

For each fixture, a hand-keyed `<image>.expected.json` list of correct entries,
stored beside the fixture. Produced by a best-effort first-pass transcription
from the photo, then **verified/corrected by the user** — the harness is only as
trustworthy as this ground truth. To bound transcription risk, start with the
first ~10–15 rows per page rather than all ~24–50.

## Scoring metric

Cursive OCR is never character-perfect, so equality is useless for measuring
improvement. Use a normalized **similarity** metric, in a pure-Dart util
`test/ocr/support/ocr_scoring.dart` (independently unit-tested):

- **Normalize** each field: lowercase, collapse whitespace, strip punctuation.
- **Per-field similarity:** Levenshtein-ratio in `0.0–1.0`, so near-misses earn
  partial credit and small OCR gains are visible.
- **Row alignment:** match extracted ↔ expected entries by `lineNo`; unmatched
  expected rows = misses, extra extracted rows = false positives.
- **Report:** row precision/recall, plus mean similarity **per field** (name,
  date, place&birth, parents, residents, minister, sponsors) — exposes which
  fields are weak so tuning can target them.
- **Headline score** per fixture: weighted mean (name + date weighted higher).

## Test harness & baseline ratchet

- `test/ocr/register_ocr_fixtures_test.dart`: for each fixture, load cells +
  expected, run `parseEntriesFromCells` (and a parallel `flatText` →
  `RegisterOcrParser.parse` case), score, print the full per-field report, and
  `expect(score >= baseline)`.
- **Baselines start at whatever the current pipeline actually scores** — measure
  today, commit those numbers as the floor. Regressions fail; improvements let
  the floor rise. This turns "tune accuracy" into a measurable, regression-safe
  loop.
- Runs with `flutter test test/ocr/` — no device needed after capture.

## Deliverables

1. `parseEntriesFromCells(List<OcrLineBox>)` seam + `parseEntriesFromBlocks`
   wrapper (behavior-preserving).
2. `OcrLineBox` JSON serialization.
3. `kDebugMode` dev capture tool.
4. Four committed fixtures (2 baptism + 2 marriage) generated from `book-scan/`.
5. Hand-keyed, user-verified ground truth per fixture.
6. `ocr_scoring.dart` util + its unit test.
7. `register_ocr_fixtures_test.dart` golden tests with committed baseline floors.

Establishing the baseline number **is** the deliverable of this spec. Actual
heuristic tuning happens against the harness afterward.

## Non-goals (follow-on specs)

- Cross-page merge-by-`No.` testing.
- Preprocessing / auto-deskew / perspective crop-to-table (Approach B).
- Cloud handwriting OCR — Google Cloud Vision / Document AI (Approach C).
- Web / Tesseract fixtures and tuning.
