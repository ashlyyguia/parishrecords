# Marriage register: CV grid template (Sub-project 1 of 3)

## Context

Marriage scanning mirrors baptismal (Add Record (OCR) → scan → CV grid → OCR →
review → save), but is a **large, multi-subsystem feature** split into three
sequenced sub-projects, each with its own spec/plan:

1. **CV marriage grid template (this spec).** Grid a marriage spread reliably.
2. Backend marriage cell→field mapping (`gridToRows` parameterized by register).
3. Flutter marriage scan + review + save.

This spec is Sub-project 1 only. It is the foundation the other two build on,
and it decides feasibility.

## Problem

The CV grid pipeline (orientation → inversion → spread split → rectify →
`detect_spread_grids`) is template-driven and currently hardcodes
`BAPTISMAL_REGISTER`. To grid a marriage spread it needs (a) a marriage column
template and (b) a way to select it. But a study of the sample images surfaced a
prerequisite:

- Orientation (auto-rotates the sideways photo, `rotation=90`) and spread
  splitting **both work** on the marriage images.
- The sample marriage images are **~1152px per page** (~400KB), roughly **half**
  baptismal's ~2268px, and the marriage register is **denser** (~28-30 entries
  with more internal sub-dividers — groom and bride lines inside several
  columns). At native resolution the row detector finds only ~3 rows and cannot
  measure the table extent. Upscaling ~2-2.5× recovers 28-33 detected rows on
  some pages, but erratically (a page grids at 2.5× yet fails at 3×).

So Sub-project 1 is a marriage template **plus resolution normalization**, not a
template alone. The row detector is tuned for ~2200px pages; keeping input in
that range is what makes detection work.

## Approach

Add the marriage template as data, route to it by register type, and normalize
input resolution so the row detector operates in the range it was tuned for. No
change to the detection/geometry algorithms or the safety gate.

## Design

### 1. Marriage column template — `ocr_service/app/pipeline/column_template.py`

Add `MARRIAGE_LEFT`, `MARRIAGE_RIGHT`, and `MARRIAGE_REGISTER =
SpreadColumnTemplate(...)` beside the baptismal ones. Column keys (confirmed with
the user, used by Sub-project 2 to map fields):

- **Left "Marriage" page (7):** `no`, `contracting_parties`, `legal_status`,
  `actual_address`, `birth`, `baptism`, `marriage_date`
- **Right "Register" page (5):** `parents`, `sponsors`, `minister`,
  `license_no`, `observations`

The boundary **proportions** and `data_row_count` are *measured from the
samples during implementation*, using the method `column_template.py` already
documents (read each header-band column edge as a fraction of the table's own
width; confirm the reading agrees across several sample spreads). This is data,
identical in kind to how `BAPTISMAL_REGISTER` was built — the spec fixes the
column identity and count; the plan records the measured floats. `MARRIAGE_LEFT`
declares 7 columns (8 boundaries); `MARRIAGE_RIGHT` declares 5 (6 boundaries).

### 2. Register-type routing — `ocr_service/app/main.py` (+ backend client)

`/v1/grid` reads a `register` value (query param `?register=marriage`, default
`baptism`) and selects the template from a small map
`{"baptism": BAPTISMAL_REGISTER, "marriage": MARRIAGE_REGISTER}`. An unknown
value falls back to `baptism` (today's behaviour). `data_row_count` and the
column template both come from the selected `SpreadColumnTemplate`, so no other
endpoint code changes.

The backend `cv_grid_client.fetchGrid` gains an optional `register` and appends
it to the `/v1/grid` URL. The baptismal caller passes nothing (defaults to
`baptism`); Sub-project 2's marriage caller passes `marriage`. This spec adds the
plumbing and its default; it does not add a marriage backend caller.

### 3. Resolution normalization — new `ocr_service/app/pipeline/resolution.py`

A small, single-purpose module: `normalize_resolution(image, min_row_axis,
max_scale)` upscales an image so its **row axis** (the page's shorter, vertical
dimension after orientation) reaches `min_row_axis`, with the scale factor
capped at `max_scale` and **never** downscaling. `main.py` applies it to the
oriented+inverted spread before `split_spread`, so both pages and all returned
geometry live in one consistent, upscaled frame (higher-res page images also
help the OCR that Sub-project 2 runs). `min_row_axis` (~2200) and `max_scale`
(~3.0) are set from the sample measurements in the plan; the baptismal path is
unaffected because its pages already exceed `min_row_axis` (no upscale applied).

### 4. Validation gate (go/no-go)

`scripts/validate_grids.py` gains an optional `--register marriage` and is run
against every sample under `attachments/marriage/`. Success = both pages grid
with **7 columns (left) / 5 columns (right)** and **matching row counts** that
pass the existing spread gate, on the majority of samples. This gate is the
honest test of whether the marriage register grids reliably enough to build
Sub-projects 2/3 on. If it fails on most samples, that is the signal to obtain
higher-resolution captures (the reliable lever) before proceeding — recorded as
the outcome, not worked around by weakening the safety gate.

## Testing

- **Template declaration (unit):** `MARRIAGE_LEFT`/`MARRIAGE_RIGHT` have 7/5
  columns and valid boundaries; `MARRIAGE_REGISTER.data_row_count` is set; the
  dataclass self-validation (boundaries 0→1, strictly increasing) passes.
- **Register routing (endpoint):** `/v1/grid?register=marriage` selects the
  marriage template (assert via a stubbed `detect_spread_grids` that receives
  `MARRIAGE_REGISTER`); no/unknown `register` selects baptismal (unchanged).
- **Resolution normalization (unit):** an image below `min_row_axis` is upscaled
  to at least it (factor ≤ `max_scale`); one already above is returned unchanged
  (never downscaled); aspect ratio preserved.
- **Backend client (unit):** `fetchGrid(..., { register: 'marriage' })` calls
  `/v1/grid?register=marriage`; the default omits it / sends baptism.
- **Real-image validation:** `validate_grids.py --register marriage` on the
  samples — structure only, never prints cell text (records of minors).
- Full CV + backend suites stay green; the baptismal path is byte-for-byte
  unchanged (default register, pages already above `min_row_axis`).

## Risks & limitations

- **Low-res samples.** The user chose to proceed with the current ~1152px
  samples. Normalization upscales them, but interpolating already-degraded
  images does not add detail, so gridding may remain erratic. The validation
  gate will show this honestly; higher-resolution capture is the durable fix.
- **Density.** The marriage register is denser than baptismal; if normalization
  alone does not stabilise row detection, density-specific row-detector tuning
  is a follow-up — deliberately **out of scope** here to keep this sub-project
  to "template + routing + normalization" and let the gate decide.

## Out of scope

- Backend cell→field mapping and the `/scan` register parameter (Sub-project 2).
- Flutter marriage scan/review/save and routing (Sub-project 3).
- Any change to detection geometry, the spread safety gate, or the baptismal
  template.
- Groom/bride line-splitting within a cell (a Sub-project 2 concern — the CV
  grid detects entry rows and columns only).
