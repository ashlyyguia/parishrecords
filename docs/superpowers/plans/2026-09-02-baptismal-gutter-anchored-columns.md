# Gutter-Anchored Column Fit Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let a register page whose spine-side (gutter) column rule faded out of the photograph still clear the column-corroboration safety floor, by treating the known gutter as a real table border for the spine-side boundary.

**Architecture:** `split_spread` already crops each page at the gutter, so the gutter is the inner edge of each page (right edge for the left page, left edge for the right). `fit_column_template` gains an optional gutter target: the spine-side outer boundary earns fit-score and corroboration credit for landing near the gutter (its own looser tolerance for the page's inner margin), in addition to interior boundaries being credited by detected vertical rules. `detect_spread_grids` supplies the per-page gutter; everything else is unchanged.

**Tech Stack:** Python 3.10, OpenCV (`opencv-python-headless`), NumPy, pytest. Run tests with `.venv310/Scripts/python -m pytest tests/` from `ocr_service/`.

## Global Constraints

- Privacy: records of minors — never print, log, or assert on cell contents; structure (counts, positions, corroboration) only. `scripts/validate_grids.py` stays structure-only.
- No new dependencies (`opencv-python-headless` only).
- `TEMPLATE_CORROBORATION_FLOOR` (0.60) is NOT changed. The gutter adds legitimate evidence for one boundary; it does not lower the bar.
- Only the **spine-side outer** boundary may be corroborated by the gutter. The non-gutter outer boundary and all interior boundaries still require a detected rule.
- Behavior with no gutter argument (the detection path, and any `detect_grid`/`fit_column_template` call without gutter) is byte-for-byte unchanged.
- `GUTTER_CORROBORATION_TOLERANCE = 0.05` (fraction of fitted table width). Tuned against the real sample spreads: spine-to-gutter margins measured 2.1%–5.9%; 0.05 clears IMG_3118 left (2.7%) with headroom while rejecting a spine boundary placed >5% off the gutter.

---

### Task 1: Gutter target in `fit_column_template`

**Files:**
- Modify: `ocr_service/app/pipeline/table.py` (add `GUTTER_CORROBORATION_TOLERANCE` near the other `TEMPLATE_*` constants ~line 567; extend `fit_column_template` ~lines 813-886)
- Test: `ocr_service/tests/test_column_template.py`

**Interfaces:**
- Consumes: existing `ColumnFit`, `TEMPLATE_CORROBORATION_TOLERANCE`, `TEMPLATE_FIT_BRACKET`, etc.
- Produces:
  - `GUTTER_CORROBORATION_TOLERANCE: float = 0.05`
  - `fit_column_template(template, rule_xs, extent, page_width, gutter_x: float | None = None, gutter_side: str | None = None) -> ColumnFit | None` — when `gutter_x` is given and `gutter_side` is `"left"` or `"right"`, the spine-side outer boundary (index `0` for `"left"`, last for `"right"`) is credited for landing within `GUTTER_CORROBORATION_TOLERANCE * width` of `gutter_x`, in both the fit score and the corroboration count.

- [ ] **Step 1: Write the failing tests**

Add to `ocr_service/tests/test_column_template.py`. Extend the existing `from app.pipeline.table import (...)` block to also import `fit_column_template`:

```python
from app.pipeline.table import (
    TEMPLATE_CORROBORATION_FLOOR,
    detect_column_rule_positions,
    detect_grid,
    detect_spread_grids,
    fit_column_template,
)
```

Tests (add at end of file):

```python
class TestGutterAnchoredFit:
    # Left page: 6 boundaries at fractions (0, .066, .311, .607, .689, 1.0) of a
    # table with extent (100, 1100) -> width 1000, so the true boundary xs are
    # 100, 166, 411, 707, 789, 1100. The spine (gutter) side of the LEFT page is
    # the RIGHT/high-x side, i.e. the last boundary (x=1100).
    EXTENT = (100, 1100)
    PAGE_WIDTH = 1300
    RULES_NO_SPINE = [100, 166, 411, 707, 789]  # every boundary EXCEPT x=1100

    def test_without_gutter_the_missing_spine_rule_costs_a_boundary(self):
        fit = fit_column_template(BAPTISMAL_LEFT, self.RULES_NO_SPINE,
                                  self.EXTENT, self.PAGE_WIDTH)
        assert abs(fit.corroboration - 5 / 6) < 1e-9

    def test_gutter_corroborates_the_spine_boundary_when_its_rule_faded(self):
        # Gutter 20px past the spine boundary (2% of width) -> within tolerance.
        fit = fit_column_template(BAPTISMAL_LEFT, self.RULES_NO_SPINE,
                                  self.EXTENT, self.PAGE_WIDTH,
                                  gutter_x=1120, gutter_side="right")
        assert abs(fit.corroboration - 1.0) < 1e-9

    def test_a_gutter_far_from_the_spine_boundary_gives_no_credit(self):
        # Gutter 200px from the spine boundary (20% of width) -> no credit; a
        # mis-placed spine boundary is not rescued.
        fit = fit_column_template(BAPTISMAL_LEFT, self.RULES_NO_SPINE,
                                  self.EXTENT, self.PAGE_WIDTH,
                                  gutter_x=1300, gutter_side="right")
        assert abs(fit.corroboration - 5 / 6) < 1e-9

    def test_gutter_only_credits_the_spine_side_not_the_far_boundary(self):
        # Rules on every boundary EXCEPT the far (non-gutter, x=100) one; a gutter
        # on the spine side must NOT corroborate the missing far boundary.
        rules_no_far = [166, 411, 707, 789, 1100]
        fit = fit_column_template(BAPTISMAL_LEFT, rules_no_far,
                                  self.EXTENT, self.PAGE_WIDTH,
                                  gutter_x=1120, gutter_side="right")
        assert abs(fit.corroboration - 5 / 6) < 1e-9
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `.venv310/Scripts/python -m pytest tests/test_column_template.py::TestGutterAnchoredFit -v`
Expected: FAIL — `fit_column_template() got an unexpected keyword argument 'gutter_x'` (and the import may already resolve, but the keyword args don't exist).

- [ ] **Step 3: Add the constant**

In `table.py`, after `TEMPLATE_CORROBORATION_FLOOR = 0.60`:

```python
# How near the gutter the spine-side outer boundary must land to count as
# corroborated by it, as a fraction of the fitted table width. Larger than
# TEMPLATE_CORROBORATION_TOLERANCE because the gutter is not a rule the boundary
# sits ON but a border it sits NEAR -- the page's inner white margin lies
# between the last printed rule and the spine. Measured across the sample
# spreads, that margin runs 2-6% of the table width; 0.05 covers the genuine
# margin while still rejecting a spine boundary placed well off the gutter.
GUTTER_CORROBORATION_TOLERANCE = 0.05
```

- [ ] **Step 4: Extend `fit_column_template`**

Change the signature:

```python
def fit_column_template(
    template: ColumnTemplate,
    rule_xs: list[int],
    extent: tuple[int, int],
    page_width: int,
    gutter_x: float | None = None,
    gutter_side: str | None = None,
) -> ColumnFit | None:
```

Replace the scoring/corroboration block (from `# boundaries[i, j, b] = ...` through the `return ColumnFit(...)`) with:

```python
    # boundaries[i, j, b] = los[i] + widths[i, j] * fractions[b]
    boundaries = los[:, None, None] + widths[:, :, None] * fractions[None, None, :]
    tol = TEMPLATE_CORROBORATION_TOLERANCE * widths          # [i, j] rule tolerance

    # Graded credit per boundary: 1.0 dead-on a detected rule, tapering to 0 at
    # the tolerance -- the same scoring the fit has always used.
    if rules.size:
        rule_dist = np.abs(boundaries[..., None] - rules).min(axis=-1)   # [i, j, b]
        credit = np.maximum(0.0, 1.0 - rule_dist / tol[:, :, None])
        matched = rule_dist <= tol[:, :, None]
    else:
        credit = np.zeros(boundaries.shape)
        matched = np.zeros(boundaries.shape, dtype=bool)

    # The spine-side outer boundary is also credited for sitting on the gutter --
    # the book's spine, a known table border -- so a rule that faded there does
    # not sink the fit. Its own, looser tolerance covers the page's inner margin
    # between the last rule and the spine. Only this one boundary is affected.
    if gutter_x is not None and gutter_side in ("left", "right"):
        sb = 0 if gutter_side == "left" else boundaries.shape[-1] - 1
        gtol = GUTTER_CORROBORATION_TOLERANCE * widths                  # [i, j]
        gdist = np.abs(boundaries[..., sb] - float(gutter_x))           # [i, j]
        gcredit = np.maximum(0.0, 1.0 - gdist / gtol)
        credit[..., sb] = np.maximum(credit[..., sb], gcredit)
        matched[..., sb] = matched[..., sb] | (gdist <= gtol)

    score = np.where(allowed, credit.sum(axis=-1), -1.0)
    i, j = np.unravel_index(int(np.argmax(score)), score.shape)

    x_lo, x_hi = float(los[i]), float(los[i] + widths[i, j])
    fitted = boundaries[i, j]
    corroborated = int(matched[i, j].sum())

    return ColumnFit(
        template=template,
        x_lo=x_lo,
        x_hi=x_hi,
        boundaries=[int(round(x)) for x in fitted],
        corroboration=corroborated / len(fitted),
        rule_count=int(rules.size),
    )
```

(This removes the old `tolerance = ...`, the `if rules.size: distance = ... else ...`, and the old `score`/`corroborated` lines, which the block above replaces.)

- [ ] **Step 5: Run tests to verify they pass**

Run: `.venv310/Scripts/python -m pytest tests/test_column_template.py::TestGutterAnchoredFit -v`
Expected: PASS (4 tests).

- [ ] **Step 6: Confirm no regression in the existing fit tests**

Run: `.venv310/Scripts/python -m pytest tests/test_column_template.py -q`
Expected: PASS (all). The no-gutter path is unchanged, so `TestFittingTheTemplate` and `TestTheGateChecksTheFit` still pass.

- [ ] **Step 7: Commit**

```bash
git add ocr_service/app/pipeline/table.py ocr_service/tests/test_column_template.py
git commit -m "feat(ocr): credit the spine-side column boundary against the gutter"
```

---

### Task 2: Thread the gutter through detection

**Files:**
- Modify: `ocr_service/app/pipeline/table.py` (`_fit_columns`, `detect_grid`, `detect_spread_grids`)
- Modify: `ocr_service/tests/test_column_template.py` (`_draw_table`: add `omit_boundary`)
- Test: `ocr_service/tests/test_column_template.py`

**Interfaces:**
- Consumes: `fit_column_template(..., gutter_x, gutter_side)` from Task 1.
- Produces:
  - `_fit_columns(binary, w, clustered_rows, min_row_span, template, gutter_x=None, gutter_side=None)`
  - `detect_grid(page_bgr, column_template=None, data_row_count=None, gutter_x=None, gutter_side=None)`
  - `detect_spread_grids` supplies `gutter_x=left.shape[1]-1, gutter_side="right"` to the left page and `gutter_x=0, gutter_side="left"` to the right page.
  - `_draw_table(..., omit_boundary: int | None = None)` — skips drawing the vertical rule at that boundary index, modelling a faded column rule.

- [ ] **Step 1: Write the failing integration test**

Add to `ocr_service/tests/test_column_template.py`, inside `class TestGutterAnchoredFit`:

```python
    def test_a_faded_spine_rule_clears_the_floor_only_with_the_gutter(self):
        # Left page drawn with its table close to the crop's inner (spine) edge,
        # then its spine-side column rule erased -- the IMG_3118 situation.
        page, _ = _draw_table(BAPTISMAL_LEFT, right_fraction=0.97,
                              omit_boundary=5)
        w = page.shape[1]
        without = detect_grid(page, BAPTISMAL_LEFT)
        with_gutter = detect_grid(page, BAPTISMAL_LEFT,
                                  gutter_x=w - 1, gutter_side="right")
        assert without.column_corroboration < TEMPLATE_CORROBORATION_FLOOR
        assert with_gutter.column_corroboration >= TEMPLATE_CORROBORATION_FLOOR
```

- [ ] **Step 2: Run it to verify it fails**

Run: `.venv310/Scripts/python -m pytest "tests/test_column_template.py::TestGutterAnchoredFit::test_a_faded_spine_rule_clears_the_floor_only_with_the_gutter" -v`
Expected: FAIL — `_draw_table()` has no `omit_boundary` argument (and `detect_grid` has no `gutter_x`).

- [ ] **Step 3: Add `omit_boundary` to `_draw_table`**

In `_draw_table`, change the signature to add `omit_boundary: int | None = None`, and change the vertical-rule loop (currently `for x in truth: cv2.line(...)`) to skip that index:

```python
    truth = [x_lo + int(round(f * table_width)) for f in template.boundaries]
    for index, x in enumerate(truth):
        if index == omit_boundary:
            continue  # this column rule faded out of the photograph
        cv2.line(page, (x, top), (x, bottom), ink, 2)
```

- [ ] **Step 4: Thread gutter through `_fit_columns`, `detect_grid`, `detect_spread_grids`**

`_fit_columns` — add the params and forward them:

```python
def _fit_columns(
    binary: np.ndarray,
    w: int,
    clustered_rows: list[tuple[int, int, int, int]],
    min_row_span: int,
    template: ColumnTemplate,
    gutter_x: float | None = None,
    gutter_side: str | None = None,
) -> ColumnFit | None:
    extent = _table_x_extent(clustered_rows, w, min_row_span)
    if extent is None:
        return None
    rules = _cluster_column_segments(_column_band_segments(binary))
    return fit_column_template(template, rules, extent, w, gutter_x, gutter_side)
```

`detect_grid` — add the params and pass them into the template branch. Change the signature:

```python
def detect_grid(
    page_bgr: np.ndarray,
    column_template: ColumnTemplate | None = None,
    data_row_count: int | None = None,
    gutter_x: float | None = None,
    gutter_side: str | None = None,
) -> GridResult:
```

and the `_fit_columns` call (currently `fit = _fit_columns(binary, w, clustered_rows, min_row_span, column_template)`):

```python
        fit = _fit_columns(binary, w, clustered_rows, min_row_span, column_template,
                           gutter_x=gutter_x, gutter_side=gutter_side)
```

`detect_spread_grids` — supply each page's gutter. After the `row_count = ...` line, add:

```python
    gutters = {
        "left": (left_page_bgr.shape[1] - 1, "right"),
        "right": (0, "left"),
    }
```

and change the `detect_grid` call in the detect loop (currently
`grids[side] = detect_grid(page, templates[side], data_row_count=row_count)`):

```python
            gx, gside = gutters[side]
            grids[side] = detect_grid(page, templates[side], data_row_count=row_count,
                                      gutter_x=gx, gutter_side=gside)
```

- [ ] **Step 5: Run the integration test**

Run: `.venv310/Scripts/python -m pytest "tests/test_column_template.py::TestGutterAnchoredFit" -v`
Expected: PASS (5 tests).

- [ ] **Step 6: Run the whole CV suite**

Run: `.venv310/Scripts/python -m pytest tests/ -q`
Expected: PASS (all). `TestTheGateChecksTheFit` still passes: its well-drawn pages have their spine rule present, so the gutter is redundant and corroboration is unchanged.

- [ ] **Step 7: Commit**

```bash
git add ocr_service/app/pipeline/table.py ocr_service/tests/test_column_template.py
git commit -m "feat(ocr): pass each page's gutter into the column fit"
```

---

### Task 3: Validate on the real spreads

**Files:**
- Uses (no change): `ocr_service/scripts/validate_grids.py`, `attachments/baptismal/IMG_3118 (1).jpeg`, `IMG_3120.jpeg`, `IMG_3121.jpeg`

- [ ] **Step 1: Run structural validation**

Run:
```bash
cd ocr_service
.venv310/Scripts/python scripts/validate_grids.py \
  ../attachments/baptismal/IMG_3120.jpeg \
  ../attachments/baptismal/IMG_3121.jpeg \
  "../attachments/baptismal/IMG_3118 (1).jpeg"
```

Expected:
- IMG_3120: `left rows=24 cols=5 | right rows=24 cols=5` (unchanged — no regression).
- IMG_3121: `left rows=24 cols=5 | right rows=24 cols=5` (unchanged — no regression).
- IMG_3118 (1): now reports both pages (no longer `FAILED ... column edges`). The left page corroboration reaches 67% via the gutter, clearing the 60% floor. If it still `FAILED`, record the exact message — its separate outer-border ambiguity (rules at 736 vs 808) is out of scope and may keep it below the floor; that is an accepted outcome, not a regression.

- [ ] **Step 2: No commit** (validation only).

---

### Task 4: Full regression sweep

**Files:**
- Uses: `ocr_service/tests/`, `backend/` Jest suites, Flutter `test/`

- [ ] **Step 1: Python CV suite**

Run: `cd ocr_service && .venv310/Scripts/python -m pytest tests/ -q`
Expected: PASS (all).

- [ ] **Step 2: Backend suites that consume the grid**

Run: `cd backend && npx jest src/routes/baptismal_ocr_firestore.test.js src/services/cv_grid_client.test.js src/services/baptismal_grid_assign.test.js`
Expected: PASS (all) — unchanged by this plan; proves the returned grid contract still holds.

- [ ] **Step 3: Flutter OCR service test**

Run: `flutter test test/baptismal_ocr_service_test.dart`
Expected: PASS (all).

- [ ] **Step 4: Final commit only if an incidental fix was needed**

```bash
git add -A
git commit -m "test(ocr): regression sweep for gutter-anchored columns"
```

---

## Self-Review

**Spec coverage:**
- Locate gutter per page (crop inner edge) → Task 2 (`detect_spread_grids` gutters map). ✓
- Anchor spine-side boundary in the fit (score) → Task 1 (`credit` feeds `score`). ✓
- Count the gutter in corroboration → Task 1 (`matched` feeds `corroborated`). ✓
- Safety: floor unchanged, only spine-side outer boundary affected, gutter needs real proximity → Task 1 tests (`test_a_gutter_far...`, `test_gutter_only_credits_the_spine_side...`) + constant note. ✓
- Testing: synthetic faded-spine clears floor only with gutter (Task 2), safety no-rescue (Task 1), real spreads no-regression + IMG_3118 recorded (Task 3), full suites (Task 4). ✓
- Backend/Flutter unchanged → Task 4 Steps 2-3. ✓

**Placeholder scan:** No TBD/TODO; every code step has literal code. ✓

**Type consistency:** `gutter_x: float | None`, `gutter_side: str | None` identical across `fit_column_template` (Task 1), `_fit_columns`, `detect_grid`, `detect_spread_grids` (Task 2). Spine index rule (`0` for `"left"`, last for `"right"`) stated in Task 1 interface and used in code. `GUTTER_CORROBORATION_TOLERANCE` defined Task 1, used only there. `_draw_table(..., omit_boundary)` defined and used in Task 2. ✓

**Known limitation (recorded, not a gap):** IMG_3118's outer (non-gutter) border ambiguity is explicitly out of scope; Task 3 Step 1 records the outcome either way.
