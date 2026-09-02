# Baptismal register: declared row count

## Problem

Scanning IMG_3121 and IMG_3122 (baptismal register spreads) fails: the CV grid
service refuses them (`no_table_detected`) because the two page halves disagree
on row count, and the backend now honestly surfaces a "retake the photo" banner.
The user needs these specific spreads to scan into the register's 24 entries.

Investigation (see `[[project-baptismal-ocr-ocrspace-swap]]` memory and the
`table.py` row detector) proved the cause is **physical, not a tuning bug**: on
these photographs the printed row-rules have *faded out of the image itself* in
the lower/middle of the right pages — only ~17–18 of 24 rules survive as
detectable ink. A rule detector cannot find lines that are not in the pixels.
Concretely, after the left-page sub-divider fix already shipped:

- IMG_3120: left 24 / right 24 — scans, correct.
- IMG_3121: left 24 / right 26 — right over-runs a trailing signature block.
- IMG_3122: left 22 / right 26 — right over-runs; left under-detects faded rows.

The handwritten *entries* in the faded rows are still present in the image and
are still OCR'd — only the printed ruling faded. So the fix is not "detect the
rules better"; it is "know the ruling."

## Approach

This register is a printed book with a fixed ruling of **24 data rows**, exactly
as it has a fixed 5-column layout. The column layout is already *declared* in
`column_template.py` rather than detected, for the same class of reason (printed
sub-dividers are indistinguishable from logical boundaries by any property of
the mark). We extend that same principle to rows: declare the row count and lay
the grid down at that count, anchored to the two measurements that remain
reliable even when most rules have faded — the header-band top and the row
pitch fitted from the confidently-detected top run.

Rejected alternatives:

- **Detect the rules better.** Infeasible — the rules are not in the image.
- **Relax the spread gate to reconcile counts.** Hacky, and still does not tell
  the pipeline *where* the 24 rows are, which is what cell/field assignment
  needs.

## Design

### 1. Template data — `ocr_service/app/pipeline/column_template.py`

Add `data_row_count: int` to `SpreadColumnTemplate` and set it to `24` on
`BAPTISMAL_REGISTER`. This is data, not logic: it declares a property of the
printed book alongside the column proportions. `ColumnTemplate` (per page) is
unchanged; the row count is a spread-level property shared by both halves.

### 2. Row placement — `ocr_service/app/pipeline/table.py`

`detect_grid` and `_detect_row_boundaries` gain an optional
`data_row_count: int | None = None`.

- When `None` (no template, or a different book): behaviour is unchanged — the
  existing detect-and-extend path (`_extend_row_curve` out to the detected
  table extent) runs exactly as today.
- When set: keep the current header-top detection and the current
  `_fit_row_curve` pitch fit from the strong top run, but replace the
  extend-to-detected-extent step with laying down **exactly `data_row_count`
  data rows from the first data row at the fitted pitch** (quadratic, so smooth
  pitch drift is preserved). The faded region is filled by extrapolation.

The returned boundaries remain `[header_top] + data_grid`, so downstream code
(`row_boundaries`, `median_data_row_pitch`, cell construction) is unchanged;
only how far `data_grid` extends changes.

### 3. Anchoring (the make-or-break detail)

The N rows must begin at the *true* first data row, or every row shifts. The
anchor is the first strong row-candidate below the header top; pitch and
curvature come from the existing `_fit_row_curve`. This is precisely where the
earlier reverted row-forcing attempt went wrong, so it is pinned with explicit
tests on all three real spreads — including IMG_3120's known left-page
header/row-1 merge, where the header-adjacent candidate is dropped from the fit
and the anchor must still land on entry 1, not entry 2.

### 4. Safety — unchanged philosophy

We do **not** blindly stamp 24 rows onto any image. The pipeline still refuses
(→ CV `no_table_detected` → backend `SPREAD_UNREADABLE` → "retake" banner) when
it cannot trust its anchor:

- `_fit_row_curve` returns `None` (no self-consistent pitch) → refuse, as today.
- The two pages' median pitches disagree beyond `SPREAD_PITCH_TOLERANCE` →
  refuse, as today.
- Column corroboration below `TEMPLATE_CORROBORATION_FLOOR` → refuse, as today.
- **New sanity gate:** the fitted clean run must contain at least
  `ROW_ANCHOR_MIN_RUN` consistent rows before we trust the pitch enough to
  extrapolate to `data_row_count`. Below that, the pitch is too weak an anchor
  and we refuse rather than invent rows from noise. (Constant tuned in the plan
  against the three real spreads; IMG_3122 left is the weakest case.)

With both pages declared to the same count, `left.rows == right.rows` holds by
construction, so the row-count arm of the spread gate passes — but the pitch and
corroboration arms remain the real safety checks.

### 5. Backend / Flutter

No changes. The backend derives rows from the returned cells, the CV client and
route are untouched, and a still-unreadable spread continues to reach the
`SPREAD_UNREADABLE` "retake" path shipped earlier.

## Testing

- **Synthetic (new):** a register spread whose lower rows' *horizontal rules*
  are erased (entries/handwriting kept) must still yield exactly 24 correctly
  positioned rows via the declared count.
- **Synthetic (unchanged path):** with `data_row_count=None`, detection behaves
  exactly as before (existing tests stay green).
- **Safety (new):** a spread with too short/weak a detectable run still refuses
  rather than extrapolating.
- **Real spreads:** IMG_3120 stays 24/24 *and* content-correct (no field
  misfiling — cross-check with `gridToRows` alignment); IMG_3121 and IMG_3122
  reach 24/24 and pass the spread gate. Validated with
  `scripts/validate_grids.py` (structure only — never prints cell text).
- **Full suites green:** Python (`ocr_service/tests`), backend Jest (route +
  cv_client + grid_assign), Flutter (`baptismal_ocr_service`).

## Out of scope

- Detecting a variable row count per spread (user confirmed the book is always
  ruled for 24).
- Any change to the column template, the OCR engine, or the review UI.
- Upstream reconciliation of the shared spread row-grid across the gutter
  (`detect_spread_grids`) beyond what the declared count already gives for free.
