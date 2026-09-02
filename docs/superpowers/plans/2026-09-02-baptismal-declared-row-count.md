# Declared Register Row Count — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make faded baptismal spreads (IMG_3121, and IMG_3120 without its last-row truncation) scan into the register's fixed 24 data rows by *declaring* the row count in the template and laying the grid on the fitted pitch, instead of extending row detection to wherever ruled ink happens to survive.

**Architecture:** The register is a printed book with a fixed 24-row ruling, exactly as it has a fixed 5-column layout already declared in `column_template.py`. Add a `data_row_count` to the spread template; when present, `table.py`'s row logic keeps its reliable header + pitch fit but lays down exactly N data rows from the first data row (extrapolating across faded rules) rather than extending to detected extent. All safety refusals (pitch fit success, pitch agreement across pages, column corroboration) stay; a new anchor-strength gate refuses when the detected run is too weak to trust extrapolation.

**Tech Stack:** Python 3.10, OpenCV (`opencv-python-headless`), NumPy, pytest. CV service under `ocr_service/`; run tests with `.venv310/Scripts/python -m pytest tests/`.

## Global Constraints

- Privacy: this service logs/handles records of minors. Never print, log, or assert on cell contents — structure (counts, positions) only. `scripts/validate_grids.py` is structure-only by design; keep it that way.
- No new dependencies. `opencv-python-headless` only (no GUI libs).
- The template-free detection path (`data_row_count=None`, i.e. `detect_grid(page)` with no template) MUST behave exactly as today. The declared-count behavior is opt-in via the spread template.
- Backend and Flutter are OUT OF SCOPE — they already derive rows from the returned cells and already surface a refusal as the `SPREAD_UNREADABLE` "retake" banner.
- A grid with N declared data rows returns `N + 1` cell-rows: one header band on top, then N data rows (matches the existing `test_detects_the_header_row_plus_24_data_rows` expectation of `grid.rows == 25`).

---

### Task 1: Declare the row count in the register template

**Files:**
- Modify: `ocr_service/app/pipeline/column_template.py`
- Test: `ocr_service/tests/test_column_template.py`

**Interfaces:**
- Produces: `SpreadColumnTemplate.data_row_count: int`; `BAPTISMAL_REGISTER.data_row_count == 24`.

- [ ] **Step 1: Write the failing test**

Add to `ocr_service/tests/test_column_template.py` (top-level, near the other imports — `BAPTISMAL_REGISTER` is already imported):

```python
def test_register_declares_its_fixed_row_count():
    # The book is ruled for a fixed number of entries, a property of the
    # printed form just like its column proportions.
    assert BAPTISMAL_REGISTER.data_row_count == 24
```

- [ ] **Step 2: Run test to verify it fails**

Run: `.venv310/Scripts/python -m pytest tests/test_column_template.py::test_register_declares_its_fixed_row_count -v`
Expected: FAIL — `AttributeError: 'SpreadColumnTemplate' object has no attribute 'data_row_count'`.

- [ ] **Step 3: Add the field and set it**

In `column_template.py`, add the field to the dataclass:

```python
@dataclass(frozen=True)
class SpreadColumnTemplate:
    """The two page layouts of one open register book.

    A spread is photographed as a single image of two facing pages, and the
    two pages carry different halves of one continuous ruled table -- so they
    have different column rulings and must be given different templates. This
    pairs them so a caller cannot accidentally fit the left page's ruling to
    the right page.

    ``data_row_count`` is the number of *data* rows the printed book is ruled
    for (excluding the column-header band). It is declared, not detected, for
    the same reason the column proportions are: it is a fixed property of the
    printed form, and on a faded or angled photograph the lower row rules can
    drop out of the image entirely -- there is nothing left to detect. See
    ``table._lay_declared_rows``.
    """

    name: str
    left: ColumnTemplate
    right: ColumnTemplate
    data_row_count: int
```

Then set it on the constant (add the argument to the existing `BAPTISMAL_REGISTER = SpreadColumnTemplate(...)` call):

```python
BAPTISMAL_REGISTER = SpreadColumnTemplate(
    name="baptismal_register",
    left=BAPTISMAL_LEFT,
    right=BAPTISMAL_RIGHT,
    data_row_count=24,
)
```

- [ ] **Step 4: Run test to verify it passes**

Run: `.venv310/Scripts/python -m pytest tests/test_column_template.py::test_register_declares_its_fixed_row_count -v`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add ocr_service/app/pipeline/column_template.py ocr_service/tests/test_column_template.py
git commit -m "feat(ocr): declare fixed 24-row ruling on the register template"
```

---

### Task 2: `_lay_declared_rows` helper + anchor constants

**Files:**
- Modify: `ocr_service/app/pipeline/table.py` (add constants near the other `ROW_*` constants ~line 180; add the helper next to `_extend_row_curve`)
- Test: `ocr_service/tests/test_table.py`

**Interfaces:**
- Consumes: fit output `(a, b, c, ks)` from `_fit_row_curve` (a=position at k=0, b=pitch, c=curvature, ks=sorted list of on-curve integer row indices).
- Produces:
  - `ROW_ANCHOR_MIN_RUN: int = 5`
  - `ROW_ANCHOR_MIN_SPAN_FRACTION: float = 0.5`
  - `_lay_declared_rows(a: float, b: float, c: float, ks: list[int], header_top: int, data_row_count: int, height: int) -> list[int]` — returns row-boundary y-positions: header-band top, then `data_row_count + 1` boundaries on the fitted curve (the N data-row tops plus the bottom edge of the last row), dropping any that fall off the page.

- [ ] **Step 1: Write the failing tests**

Add to `ocr_service/tests/test_table.py`. Import the helper and constants at the top (extend the existing `from app.pipeline.table import ...` line):

```python
from app.pipeline.table import detect_grid, _lay_declared_rows
```

Tests:

```python
def test_lay_declared_rows_fills_to_the_declared_count():
    # Pitch 100, no curvature, first data row at y=200, header top at y=50.
    # Only five rows were detected, but the book is ruled for 24.
    ys = _lay_declared_rows(200.0, 100.0, 0.0, [0, 1, 2, 3, 4],
                            header_top=50, data_row_count=24, height=10000)
    assert ys[0] == 50          # header band top
    assert ys[1] == 200         # first data row top
    assert ys[-1] == 200 + 24 * 100  # bottom edge of the 24th row (k=24)
    # header top + 24 data-row tops + 1 bottom edge == 26 boundaries == 25 rows
    assert len(ys) == 26


def test_lay_declared_rows_clamps_the_header_above_the_first_row():
    # The full-width header pass can lock onto the FIRST DATA ROW's own rule,
    # reporting a header_top at or below entry 1 (seen on IMG_3121's right
    # page). The header boundary must still sit strictly above entry 1.
    ys = _lay_declared_rows(200.0, 100.0, 0.0, [0, 1, 2],
                            header_top=205, data_row_count=24, height=10000)
    assert ys[0] < ys[1]
    assert ys[1] == 200


def test_lay_declared_rows_drops_rows_that_fall_off_the_page():
    # A crop too short to contain all 24 rows must not fabricate off-page
    # boundaries; the spread gate then refuses on the resulting count mismatch.
    ys = _lay_declared_rows(200.0, 100.0, 0.0, [0, 1, 2],
                            header_top=50, data_row_count=24, height=1500)
    assert all(0 <= y <= 1499 for y in ys)
    assert ys == sorted(ys)
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `.venv310/Scripts/python -m pytest tests/test_table.py -k lay_declared_rows -v`
Expected: FAIL — `ImportError`/`cannot import name '_lay_declared_rows'`.

- [ ] **Step 3: Add constants and the helper**

In `table.py`, next to the existing row constants (after `ROW_FIT_TOLERANCE_FRACTION = 0.3`):

```python
# When a declared row count is laid down (see _lay_declared_rows), the fitted
# pitch is trusted only if the detected run is strong enough to anchor an
# extrapolation across faded rows: at least ROW_ANCHOR_MIN_RUN on-curve rows,
# spanning at least ROW_ANCHOR_MIN_SPAN_FRACTION of the declared count so the
# pitch has a long enough lever arm. Below that the anchor is guesswork, so the
# detector falls back and the spread gate refuses rather than invent rows.
ROW_ANCHOR_MIN_RUN = 5
ROW_ANCHOR_MIN_SPAN_FRACTION = 0.5
```

Add the helper immediately after `_extend_row_curve`:

```python
def _lay_declared_rows(
    a: float,
    b: float,
    c: float,
    ks: list[int],
    header_top: int,
    data_row_count: int,
    height: int,
) -> list[int]:
    """Boundaries for a *declared* number of data rows.

    The book is ruled for a fixed number of entries, so instead of extending
    detection to wherever ruled ink survives (which over-runs into a trailing
    signature block, or stops early where the rules faded out of the
    photograph), lay the grid on the fitted curve: the header-band top, then
    ``data_row_count`` data-row tops plus the bottom edge of the last row. The
    faded region is filled by extrapolation; the handwriting there is still in
    the image and still OCR'd, so it drops into the right cell.

    The first data row is the fit's lowest index ``k0``. The header band sits
    above it; keep the detected ``header_top`` unless the full-width header
    pass locked onto entry 1's own rule (so it landed at or below entry 1), in
    which case place the header one pitch above entry 1. Boundaries that fall
    off the page are dropped, so a crop too short to hold all the rows yields a
    short grid the spread gate then refuses rather than a fabricated one.
    """
    k0 = min(ks)

    def y(k: int) -> float:
        return a + b * k + c * k * k

    entry_top = y(k0)
    top = min(float(header_top), entry_top - b)
    boundaries = [top] + [y(k) for k in range(k0, k0 + data_row_count + 1)]
    rounded = [int(round(v)) for v in boundaries]
    return [v for v in rounded if 0 <= v <= height - 1]
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `.venv310/Scripts/python -m pytest tests/test_table.py -k lay_declared_rows -v`
Expected: PASS (3 tests).

- [ ] **Step 5: Commit**

```bash
git add ocr_service/app/pipeline/table.py ocr_service/tests/test_table.py
git commit -m "feat(ocr): _lay_declared_rows lays a fixed row count on the fitted pitch"
```

---

### Task 3: Wire the declared count through detection

**Files:**
- Modify: `ocr_service/app/pipeline/table.py` (`_detect_row_boundaries`, `detect_grid`, `detect_spread_grids`)
- Modify: `ocr_service/tests/support/synthetic.py` (add faded-lower-rows option)
- Test: `ocr_service/tests/test_table.py`

**Interfaces:**
- Consumes: `_lay_declared_rows`, `ROW_ANCHOR_MIN_RUN`, `ROW_ANCHOR_MIN_SPAN_FRACTION` (Task 2); `SpreadColumnTemplate.data_row_count` (Task 1).
- Produces:
  - `_detect_row_boundaries(binary, w, h, clustered=None, data_row_count: int | None = None)`
  - `detect_grid(page_bgr, column_template=None, data_row_count: int | None = None)`
  - `make_register_spread(..., erase_row_rules_below_frac: float | None = None)` — when set, horizontal row rules below that fraction of the table height are not drawn (handwriting/cell ink and column rules are still drawn), modelling rules that faded out of the photograph.

- [ ] **Step 1: Write the failing tests**

Add to `ocr_service/tests/test_table.py`. Extend the imports:

```python
from app.errors import OcrError  # already imported near the top; keep one copy
from app.pipeline.column_template import BAPTISMAL_LEFT
```

Tests:

```python
def test_declared_count_recovers_faded_lower_rows():
    # Lower-half row rules erased from the image (as on IMG_3121's right page),
    # handwriting kept. Detection alone under-counts; the declared count lays
    # the full ruling on the pitch fitted from the surviving upper rules.
    page = split_spread(
        make_register_spread(rows=24, cols_left=5, erase_row_rules_below_frac=0.55)
    ).left
    grid = detect_grid(page, BAPTISMAL_LEFT, data_row_count=24)
    assert grid.rows == 25  # header band + 24 data rows


def test_declared_count_refuses_when_the_anchor_is_too_weak():
    # Almost all row rules erased -> too short a run to trust extrapolation.
    # The detector must fall back (yielding too few boundaries) so detect_grid
    # refuses rather than stamping 24 rows onto noise.
    page = split_spread(
        make_register_spread(rows=24, cols_left=5, erase_row_rules_below_frac=0.10)
    ).left
    with pytest.raises(OcrError):
        detect_grid(page, BAPTISMAL_LEFT, data_row_count=24)


def test_declared_count_is_opt_in_detection_path_unchanged():
    # With no declared count the fully-ruled page detects exactly as before.
    grid = detect_grid(_left_page())
    assert grid.rows == 25
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `.venv310/Scripts/python -m pytest tests/test_table.py -k "declared_count" -v`
Expected: FAIL — `make_register_spread()` has no `erase_row_rules_below_frac` argument, and `detect_grid()` has no `data_row_count` argument.

- [ ] **Step 3: Add the faded-rows option to the synthetic generator**

In `ocr_service/tests/support/synthetic.py`, extend `make_register_spread`'s signature with `erase_row_rules_below_frac: float | None = None` and, in the per-page loop, replace the row-rule drawing so rules below the cutoff are skipped (column rules and cell text are unchanged and still drawn):

```python
        cutoff = (None if erase_row_rules_below_frac is None
                  else top + erase_row_rules_below_frac * (bottom - top))
        for y in ys:
            if cutoff is not None and y > cutoff:
                continue  # this rule faded out of the photograph
            cv2.line(img, (x0, y), (x1, y), line, 2)
```

Document the new argument in the docstring: "``erase_row_rules_below_frac``: when set, horizontal row rules below this fraction of the table height are not drawn — the handwriting and column rules remain — modelling rules that faded out of a real photograph. Used to test the declared-row-count path in `table.py`."

- [ ] **Step 4: Thread `data_row_count` through the three functions**

In `_detect_row_boundaries`, change the signature and replace the tail (from `a, b, c, ks = fit` onward):

```python
def _detect_row_boundaries(
    binary: np.ndarray,
    w: int,
    h: int,
    clustered: list[tuple[int, int, int, int]] | None = None,
    data_row_count: int | None = None,
) -> list[int]:
```

```python
    a, b, c, ks = fit

    if data_row_count is not None:
        # Declared ruling: lay exactly data_row_count rows on the fitted pitch,
        # but only when the detected run is a trustworthy anchor. Otherwise fall
        # back so the spread gate refuses rather than extrapolate from noise.
        if (len(ks) < ROW_ANCHOR_MIN_RUN
                or (max(ks) - min(ks)) < ROW_ANCHOR_MIN_SPAN_FRACTION * data_row_count):
            return header_candidates
        return _lay_declared_rows(a, b, c, ks, header_top, data_row_count, h)

    k_min = min(ks)
    k_max = _extend_row_curve(a, b, c, max(ks), [y for y, _, _, _ in clustered])

    data_grid = [int(round(a + b * k + c * k * k)) for k in range(k_min, k_max + 1)]
    data_grid = [y for y in data_grid if header_top < y <= h - 1]
    return [header_top] + data_grid
```

In `detect_grid`, add the parameter and pass it to `_detect_row_boundaries`:

```python
def detect_grid(
    page_bgr: np.ndarray,
    column_template: ColumnTemplate | None = None,
    data_row_count: int | None = None,
) -> GridResult:
```

Find the row-detection call (currently `ys = _detect_row_boundaries(binary, w, h, clustered_rows)`) and change it to:

```python
    ys = _detect_row_boundaries(binary, w, h, clustered_rows, data_row_count=data_row_count)
```

In `detect_spread_grids`, derive the count from the spread template and pass it to each page:

```python
    row_count = None if spread_template is None else spread_template.data_row_count
```

and change the per-side call (currently `grids[side] = detect_grid(page, templates[side])`) to:

```python
            grids[side] = detect_grid(page, templates[side], data_row_count=row_count)
```

- [ ] **Step 5: Run the new tests**

Run: `.venv310/Scripts/python -m pytest tests/test_table.py -k "declared_count" -v`
Expected: PASS (3 tests).

- [ ] **Step 6: Keep the existing spread-gate test honest**

The gate test `test_two_well_fitted_pages_are_accepted` (in `tests/test_column_template.py`) draws its pages with `_draw_table`'s default `rows=20` but now goes through `BAPTISMAL_REGISTER` (declared count 24). Draw those pages with 24 rows so the physical ruling matches the declaration. In `test_column_template.py`, change `TestTheGateChecksTheFit._spread` to draw 24 rows:

```python
    def _spread(self, **kwargs):
        kwargs.setdefault("rows", 24)
        left, _ = _draw_table(BAPTISMAL_LEFT, **kwargs)
        right, _ = _draw_table(BAPTISMAL_RIGHT, **kwargs)
        return left, right
```

- [ ] **Step 7: Run the whole CV suite**

Run: `.venv310/Scripts/python -m pytest tests/ -q`
Expected: PASS (all). If `test_two_well_fitted_pages_are_accepted` fails on a row count/pitch mismatch, confirm Step 6 was applied. Any other failure is a wiring regression — fix before committing.

- [ ] **Step 8: Commit**

```bash
git add ocr_service/app/pipeline/table.py ocr_service/tests/support/synthetic.py ocr_service/tests/test_table.py ocr_service/tests/test_column_template.py
git commit -m "feat(ocr): lay the declared row count when a spread template provides it"
```

---

### Task 4: Validate on the real spreads

**Files:**
- Uses (no change): `ocr_service/scripts/validate_grids.py`, `attachments/baptismal/IMG_3120.jpeg`, `IMG_3121.jpeg`, `IMG_3122.jpeg`

**Interfaces:**
- Consumes: the wired `detect_spread_grids(..., spread_template=BAPTISMAL_REGISTER)` from Task 3.

- [ ] **Step 1: Run structural validation on all three spreads**

Run:
```bash
cd ocr_service
.venv310/Scripts/python scripts/validate_grids.py \
  ../attachments/baptismal/IMG_3120.jpeg \
  ../attachments/baptismal/IMG_3121.jpeg \
  ../attachments/baptismal/IMG_3122.jpeg
```

Expected (validate_grids prints `grid.rows - 1`, so 24 means `grid.rows == 25` = header + 24 data rows):
- IMG_3120: `left rows=24 cols=5 | right rows=24 cols=5` (previously the last entry was truncated to 23).
- IMG_3121: `left rows=24 cols=5 | right rows=24 cols=5` — now PASSES the spread gate (previously refused: left 24 / right 26).
- IMG_3122: either passes at `24/24`, or still `FAILED ... disagree about how many rows` (its left page detected only ~8 rules with a faint top; if the anchor is too weak the gate refuses — an honest outcome, not a regression). Record which occurred.

- [ ] **Step 2: Confirm IMG_3120 did not regress into misfiling**

`validate_grids` is structure-only. Confirm IMG_3120 still reports 24/24 with 5 columns each (above) — that is the structural guarantee. Content-level alignment is owned by the backend `gridToRows` (unchanged here) and its own test suite (Task 5).

- [ ] **Step 3: No commit** (validation only — no files changed).

---

### Task 5: Full regression sweep

**Files:**
- Uses: `ocr_service/tests/`, `backend/` Jest suites, Flutter `test/`

- [ ] **Step 1: Python CV suite**

Run: `cd ocr_service && .venv310/Scripts/python -m pytest tests/ -q`
Expected: PASS (all).

- [ ] **Step 2: Backend suites that touch this pipeline**

Run: `cd backend && npx jest src/routes/baptismal_ocr_firestore.test.js src/services/cv_grid_client.test.js src/services/baptismal_grid_assign.test.js`
Expected: PASS (all). These are unchanged by this plan but prove the row/cell contract the backend consumes still holds.

- [ ] **Step 3: Flutter OCR service test**

Run: `flutter test test/baptismal_ocr_service_test.dart`
Expected: PASS (all).

- [ ] **Step 4: Final commit if any incidental fixes were needed**

Only if Steps 1-3 required a change; otherwise nothing to commit.

```bash
git add -A
git commit -m "test(ocr): regression sweep for declared row count"
```

---

## Self-Review

**Spec coverage:**
- Template data (`data_row_count` on `SpreadColumnTemplate` + `BAPTISMAL_REGISTER=24`) → Task 1. ✓
- Row placement (lay N rows when declared; unchanged when `None`) → Tasks 2, 3. ✓
- Anchoring (first data row = fit `k_min`; header clamped above entry 1 — the IMG_3121-right case) → Task 2 (`_lay_declared_rows`, `test_lay_declared_rows_clamps_the_header_above_the_first_row`). ✓
- Safety (fit success and pitch/corroboration refusals unchanged; new anchor-strength gate) → Task 3 (`ROW_ANCHOR_MIN_RUN`/`SPAN_FRACTION`, `test_declared_count_refuses_when_the_anchor_is_too_weak`). ✓
- Testing: synthetic faded-rows regression, safety refusal, unchanged detection path → Task 3; real spreads → Task 4; full suites → Task 5. ✓
- Backend/Flutter out of scope, still surface refusal as retake → confirmed unchanged, exercised in Task 5. ✓

**Placeholder scan:** No TBD/TODO; every code step has literal code. ✓

**Type consistency:** `_lay_declared_rows(a, b, c, ks, header_top, data_row_count, height)` — same name and argument order in Task 2 (definition + tests) and Task 3 (call site). `data_row_count` is the parameter name across `_detect_row_boundaries`, `detect_grid`, and `SpreadColumnTemplate.data_row_count`. `_fit_row_curve` returns `(a, b, c, ks)` as consumed. ✓

**Known limitation (recorded, not a gap):** IMG_3122's left page detected only ~8 row rules with a faint top; its first fitted row may not be entry 1, so it may refuse under the anchor-strength gate rather than mis-anchor. This is the intended safe behavior for a genuinely under-detected page (Task 4 Step 1 records the outcome); forcing it was explicitly out of scope per the design's "refuse rather than invent" safety stance.
