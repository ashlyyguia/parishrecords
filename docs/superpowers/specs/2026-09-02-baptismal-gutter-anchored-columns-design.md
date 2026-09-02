# Baptismal register: gutter-anchored column fit

## Problem

Some register spreads refuse to scan because the **left page's spine-side (gutter)
column rule has faded out of the photograph**, dropping the column-fit
corroboration below the 60% safety floor. Measured on `attachments/baptismal/IMG_3118 (1).jpeg`:

- Right page fits at 100% corroboration.
- Left page fits at **50%** (3 of 6 boundaries land on a detected vertical
  rule). The single largest miss is the **spine-side outer border**: the fitted
  boundary is at x≈1911 while the nearest detected rule is 342px away — because
  the printed rule nearest the spine faded/was lost to binding shadow and
  curvature. `detect_spread_grids` → `_check_template_fit` refuses at 50% < 60%.

This is the column analogue of the faded-row-rule problem already solved by
declaring the row count: a printed line that is not in the image cannot be
detected. The register's column *layout* is already declared
(`column_template.py`); what fails here is the **corroboration check** that
proves the declared template landed on the page, because the rule it wants to
match on the spine side is gone.

The corroboration floor is load-bearing — a mis-placed column fit files every
value under the wrong heading, worse than a row error — so it must not be
lowered. The fix must add a *legitimate* source of evidence for the spine-side
border, not weaken the check.

## Key insight

A spread is one continuous ruled table photographed across the **gutter** (the
book's spine). `split_spread` already locates the gutter (`SpreadPages.gutter_x`)
and crops each page at it, so the gutter is the **inner edge of each page crop**
— the right edge for the left page, the left edge for the right page. The
table's spine-side border sits just inside that edge. The gutter is therefore a
*known table border*, available without detecting any (faded) rule and without
round-tripping through the facing page.

## Approach

Treat the gutter as a known border of the table when fitting and scoring the
column template on each page: the spine-side outer boundary is anchored to, and
corroborated by, the gutter position, while interior boundaries continue to be
corroborated by independently detected vertical rules.

Rejected alternatives:

- **Corroboration-only (lighter "Approach A").** Count the gutter in the score
  but leave the fit's placement untouched. Simpler, but it only rewards a fit
  that already happened to land on the gutter; it does not *pull* an ambiguous
  fit toward the gutter. We want the gutter to improve the placement, not just
  the grade.
- **Full cross-page mapping.** Map the confident right page's gutter border into
  the left page's frame through both rectify transforms and the split. Redundant
  — `gutter_x` gives the gutter directly — and far more complex.
- **Lower the corroboration floor.** Unsafe: at low corroboration the fit may be
  genuinely mis-placed, and a column error mis-files every field.

## Design

### 1. Locate the gutter in each page's frame

`split_spread` returns `gutter_x` and crops each page at it, so in each page's
own (cropped) frame the gutter is the inner edge: `width - 1` for the left page,
`0` for the right page. `rectify_page` keeps the canvas size and applies only a
small shear, so the gutter stays at that inner edge to within the shear — the
same order of slack the corroboration tolerance already allows for bowed rules.
The gutter position in the page frame is therefore taken as the crop's inner
edge; no new geometry tracking through rectify is required.

`detect_spread_grids` passes, per page, the gutter position and which side is the
spine (left page → high-x / right edge; right page → low-x / left edge) down
into `detect_grid` → `_fit_columns` → `fit_column_template`. The template-free
detection path and any `detect_grid` call without a spread context pass no
gutter and behave exactly as today.

### 2. Anchor the spine-side boundary in the fit

`fit_column_template` already scores each candidate placement by how near its
boundaries land to detected vertical rules. Extend the score so the **spine-side
outer boundary** also earns credit for landing near the gutter position, using
the same graded (distance-based) scoring and the same
`TEMPLATE_CORROBORATION_TOLERANCE`. Among otherwise-competing placements the fit
now prefers the one whose spine border sits on the gutter, rather than one that
reaches an interior rule by coincidence.

### 3. Count the gutter in corroboration

The spine-side outer boundary counts as corroborated if it lands within
tolerance of the gutter **or** of a detected vertical rule; interior boundaries
are corroborated by detected rules only, as today. `column_corroboration` stays
a fraction of all boundaries, so the floor's meaning is unchanged; the gutter
simply restores the one boundary that reliably fades on bound books. For
IMG_3118 left this yields 3 interior matches + the gutter = 4/6 = 67% ≥ 60%.

### 4. Safety

- `TEMPLATE_CORROBORATION_FLOOR` (60%) is unchanged.
- The gutter is a genuine table border (the spine), so anchoring to it is
  evidence, not a free pass: a fit whose spine boundary is far from the gutter
  earns nothing there and a page with few interior rules **and** an off-gutter
  spine border still refuses.
- Only the spine-side *outer* boundary may be corroborated by the gutter. The
  outer border on the *non*-gutter side, and all interior boundaries, still
  require detected rules — so the number of independently-verified boundaries
  needed to clear the floor is unchanged for every boundary except the one that
  is genuinely unverifiable by rule on a bound book.
- Empirical gate: no known-good spread (IMG_3120, IMG_3121) may regress in
  corroboration or column placement, and a deliberately mis-placed fit must
  still be refused.

### 5. Backend / Flutter

No changes. `detect_grid` still returns the same `GridResult`
(`column_corroboration` now reflects the gutter where applicable); the backend
derives fields from cells and a refusal still reaches the `SPREAD_UNREADABLE`
retake banner.

## Testing

- **Synthetic (new):** a left-page table whose spine-side column rule is not
  drawn (interior rules kept) fits and clears the floor via the gutter anchor.
- **Synthetic (safety, new):** a fit whose spine boundary is placed away from
  the gutter earns no gutter credit and, with interior rules removed, still
  refuses — the gutter does not rescue a genuinely mis-placed fit.
- **Unit:** `fit_column_template` given a gutter target scores/corroborates the
  spine-side boundary against it; given none, behaves exactly as today.
- **Real spreads:** IMG_3120 and IMG_3121 keep their column placement and stay
  ≥ floor (no regression); IMG_3118 (1) is recorded — it passes if its fit is
  genuinely gutter-aligned, and still refuses if its remaining outer-border
  ambiguity keeps it below the floor. Validated structure-only via
  `scripts/validate_grids.py` (never prints cell text — records of minors).
- **Full suites green:** Python `ocr_service/tests`, backend Jest
  (route + cv_client + grid_assign), Flutter `baptismal_ocr_service`.

## Out of scope

- The left page's *outer* (non-gutter) border ambiguity (e.g. IMG_3118's rules
  at 736 vs 808) — the gutter constraint does not address it, so a spread that
  is ambiguous there may still refuse. That is acceptable: the goal is to make
  the faded-spine-column *class* safe, not to force any single photo.
- Lowering the corroboration floor, changing the OCR engine, or the review UI.
- Cross-page column reconciliation beyond using the shared `gutter_x`.
