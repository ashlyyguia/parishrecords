import cv2
import numpy as np
import pytest

from app.errors import OcrError
from app.pipeline.column_template import BAPTISMAL_LEFT
from app.pipeline.spread import split_spread
from app.pipeline.table import (
    detect_grid,
    _lay_declared_rows,
    _fit_declared_row_grid,
    _anchor_declared_rows_to_table,
    _cluster_row_segments,
    _row_strip_segments,
    _full_width_row_ys,
    _binary,
    ROW_STRIP_COUNT,
    ROW_STRIP_MIN_SPAN_FRACTION,
)
from tests.support.synthetic import make_register_spread

LINE_COLOR = (140, 60, 40)  # BGR, matches synthetic register blue


def _left_page():
    return split_spread(make_register_spread(rows=24, cols_left=5)).left


def _ruled_page(h: int, w: int, rows: int, cols: int) -> np.ndarray:
    """A bare white page with an evenly pitched full-strength ruled grid.

    No margins, no artifacts — every rule spans the full page in its axis,
    so this isolates the min_gap merge-distance mechanism from the
    peak_floor mechanism tested elsewhere.
    """
    img = np.full((h, w, 3), 250, np.uint8)
    for i in range(cols + 1):
        x = round(i * w / cols)
        cv2.line(img, (x, 0), (x, h - 1), LINE_COLOR, 2)
    for i in range(rows + 1):
        y = round(i * h / rows)
        cv2.line(img, (0, y), (w - 1, y), LINE_COLOR, 2)
    return img


def _column_boundaries(grid) -> list[int]:
    lefts = sorted(set(c.x for c in grid.cells))
    right_edge = max(c.x + c.w for c in grid.cells)
    return lefts + [right_edge]


def _page_with_dominant_column_artifact() -> tuple[np.ndarray, list[int]]:
    """A page whose genuine column rules are short (weak signal) next to one
    full-height artefact stripe (strong signal) — modelling a crisp page
    border or binding shadow next to faded, partially-obscured printed rules.

    Returns the image and the expected genuine column boundary x-positions.
    """
    h, w = 1400, 2400
    img = np.full((h, w, 3), 250, np.uint8)

    # A normal-strength row grid so the row axis is never in question here.
    x0, x1 = 200, 2200
    for i in range(6):
        y = round(i * h / 5)
        cv2.line(img, (x0, y), (x1, y), LINE_COLOR, 2)

    # Genuine column rules: only 200px tall (14% of page height) — well
    # above the erosion kernel length (h // 12 ≈ 116px) so they still
    # register, but far weaker than a full-height feature.
    cols = 15
    xs_expected = [round(x0 + i * (x1 - x0) / cols) for i in range(cols + 1)]
    y_lo, y_hi = 600, 800
    for x in xs_expected:
        cv2.line(img, (x, y_lo), (x, y_hi), LINE_COLOR, 2)

    # The dominant artefact: one full-height stripe near the page edge,
    # outside the table's column range entirely.
    cv2.line(img, (50, 0), (50, h - 1), LINE_COLOR, 2)

    return img, xs_expected


def _page_with_bottom_rows_bleeding_left() -> np.ndarray:
    """A ruled page whose table sits well right of the page's left edge, where
    the *lower* rows' rules bleed leftward across the empty margin to the page
    edge — modelling the book cover, binding shadow, and the hand holding the
    book at the bottom-left of a real spread photograph, whose horizontal ink
    merges with those rows' printed rules and carries their left extent past
    the table's true border.

    A genuine full-width rule reaches the table's left border and no further;
    the border is estimated from the rules' own left extents. A minority of
    rules bleeding to the page edge must not drag that estimate off the true
    border and cause every rule that stops *at* the border (the whole upper
    half of the table) to be discarded as "not full-width".
    """
    h, w = 3000, 2000
    img = np.full((h, w, 3), 250, np.uint8)
    x0, x1 = 500, 1900              # table border a quarter of the way in
    top, header_h, rows = 200, 90, 24
    ys = [top, top + header_h]
    pitch = (h - 120 - ys[1]) / rows
    ys += [int(ys[1] + i * pitch) for i in range(1, rows + 1)]
    bleed_from = ys[2 + rows * 2 // 3]  # lower third bleeds to the page edge
    for y in ys:
        left_x = 0 if y >= bleed_from else x0
        cv2.line(img, (left_x, y), (x1, y), LINE_COLOR, 3)
    for i in range(6):             # five columns, so a template has rules to fit
        x = round(x0 + i * (x1 - x0) / 5)
        cv2.line(img, (x, ys[0]), (x, ys[-1]), LINE_COLOR, 2)
    return img


def test_lower_rows_bleeding_left_do_not_discard_the_genuine_upper_rows():
    # The bug: the left border is estimated from a low percentile of the row
    # rules' left extents, which a minority of rules bleeding to the page edge
    # drags left, so every genuine rule that stops at the true border (here, the
    # whole upper half of the table) is rejected as not full-width. With those
    # anchors gone the declared-row fit collapses and the spread gate refuses a
    # perfectly readable page. Every genuine full-width rule must survive.
    page = _page_with_bottom_rows_bleeding_left()
    binary = _binary(page)
    clustered = _cluster_row_segments(_row_strip_segments(binary))
    min_span = max(2, round(ROW_STRIP_COUNT * ROW_STRIP_MIN_SPAN_FRACTION))
    strong = [c for c in clustered if c[1] >= min_span]
    kept = _full_width_row_ys(strong)
    # Every span-strong cluster in this fixture is a genuine row rule; some
    # merely bleed left. None may be dropped.
    assert len(kept) == len(strong), (len(kept), len(strong))


def test_declared_fit_does_not_skip_the_first_row_when_header_is_misdetected_low():
    # The coarse full-width header pass can, on a bowed page, report a
    # header_top that sits BELOW the first entry's own rule (measured on a real
    # marriage spread: header_top=646 while entry 1's rule was at 501). The comb
    # must still anchor on that first rule. If it does not, it starts one entry
    # too low: the header band then lands on entry 1 (so no header can be
    # dropped) and a spurious extra row falls off the bottom.
    ys = [500, 650, 800, 950, 1100, 1250, 1400]  # seven entry rules, pitch 150
    result = _fit_declared_row_grid(ys, header_top=640, data_row_count=6, height=2000)
    assert result is not None
    start, pitch, _, _ = result
    # The first tooth must sit on the first detected rule, not a full pitch below
    # it (which would leave entry 1 above the grid, inside the header band).
    assert start - ys[0] < pitch * 0.5, (start, ys[0], pitch)


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


def _data_row_bottoms(grid) -> list[int]:
    return [c.y + c.h for c in grid.cells]


def test_declared_count_survives_a_near_left_border_subdivider():
    # The marriage register's interior sub-divider sits in a wide column that
    # begins only a little way in from the table's left border, so — unlike the
    # 0.30 case the detection path already filters — it survives the left-extent
    # filter and lands between genuine row rules at half the pitch. The declared
    # path must still recover the *true* pitch: 24 rows laid on a halved pitch
    # would cover only the top half of the table. Assert the rows reach the
    # bottom of the ruled page, which a halved pitch cannot.
    page = split_spread(
        make_register_spread(rows=24, cols_left=5, subdivider_start_frac=0.05)
    ).left
    grid = detect_grid(page, BAPTISMAL_LEFT, data_row_count=24)
    assert grid.rows == 25
    assert max(_data_row_bottoms(grid)) > 0.85 * page.shape[0]


def test_declared_count_recovers_faded_upper_rows_with_a_subdivider():
    # The marriage register's right page as it actually photographs: the top
    # entries' rules fade into the spine *and* a near-left-border sub-divider
    # halves the visible pitch. The first *detected* genuine rule is then several
    # rows down, so a layout that trusts the median gap (halved) or anchors on
    # the first detected rule overshoots or mis-pitches. The declared path must
    # still span the whole table, top to bottom.
    page = split_spread(
        make_register_spread(rows=24, cols_left=5,
                             subdivider_start_frac=0.05,
                             erase_row_rules_above_frac=0.35)
    ).left
    grid = detect_grid(page, BAPTISMAL_LEFT, data_row_count=24)
    assert grid.rows == 25
    assert min(c.y for c in grid.cells) < 0.20 * page.shape[0]
    assert max(_data_row_bottoms(grid)) > 0.85 * page.shape[0]


def test_declared_count_is_opt_in_detection_path_unchanged():
    # With no declared count the fully-ruled page detects exactly as before.
    grid = detect_grid(_left_page())
    assert grid.rows == 25


def test_detects_five_columns_on_the_left_page():
    grid = detect_grid(_left_page())
    assert grid.cols == 5


def test_detects_the_header_row_plus_24_data_rows():
    grid = detect_grid(_left_page())
    assert grid.rows == 25


def test_wide_interior_subdividers_do_not_double_the_row_count():
    """Pins the IMG_3121 row-doubling bug: an interior sub-divider ruled across
    a register's wide columns (the father/mother name-line inside "parents") is
    a real printed rule at *half* the row pitch. When it happens to be wide
    enough to survive the strip-span filter, it lands exactly between genuine
    row rules and, unless rejected, halves the estimated pitch — turning 24 data
    rows into ~48.

    What tells it apart from a genuine row rule is not its strip span but its
    left extent: a genuine row rule reaches the table's left border, an interior
    sub-divider begins partway across. This models a sub-divider wide enough
    (0.30 of the table width to its right edge) to pass the span filter, and
    asserts the row count is not doubled.
    """
    page = split_spread(
        make_register_spread(rows=24, cols_left=5, subdivider_start_frac=0.30)
    ).left
    grid = detect_grid(page)
    assert grid.rows == 25


def test_cells_are_ordered_top_to_bottom_left_to_right():
    grid = detect_grid(_left_page())
    first = grid.cell(0, 0)
    below = grid.cell(1, 0)
    right = grid.cell(0, 1)
    assert below.y > first.y
    assert right.x > first.x


def test_every_row_column_pair_is_present():
    grid = detect_grid(_left_page())
    assert len(grid.cells) == grid.rows * grid.cols


def test_blank_page_raises_no_table_detected():
    blank = np.full((800, 1200, 3), 255, np.uint8)
    with pytest.raises(OcrError) as e:
        detect_grid(blank)
    assert e.value.code == "no_table_detected"


def test_narrow_columns_on_a_tall_page_are_not_merged():
    """Pins the min_gap axis bug: merging must use the same axis as the
    positions being merged, not the perpendicular kernel dimension.

    On a tall, narrow page (h=6000, w=1200) with 20 narrow columns (true
    pitch 60px), a column min_gap wrongly derived from page height
    (6000 // 21 = 285px, with the column axis's gap_divisor of 21) dwarfs
    the true pitch and collapses distinct column rules together. A min_gap
    correctly derived from page width (1200 // 21 = 57px) stays just under
    the true pitch and does not.

    The worked numbers track detect_grid's actual column-axis gap_divisor;
    if that is retuned, the arithmetic above must be recomputed — but the
    bug being pinned (wrong axis, not wrong divisor) is unaffected either
    way.
    """
    page = _ruled_page(h=6000, w=1200, rows=4, cols=20)
    grid = detect_grid(page)
    assert grid.cols == 20


def test_genuine_rules_survive_a_dominant_artifact():
    """Pins the peak_floor robustness bug: a single feature stronger than
    every genuine rule (a crisp border, crease, or binding shadow) must not
    starve the threshold for the genuine rules.

    16 genuine column rules are deliberately short (weak signal) next to one
    full-height artefact stripe (strong signal). A floor set as a fraction of
    the raw maximum is dominated by the one artefact and misses the genuine
    rules; a floor anchored to a high percentile of the bulk of detections
    is not.
    """
    page, xs_expected = _page_with_dominant_column_artifact()
    grid = detect_grid(page)
    boundaries = _column_boundaries(grid)
    tolerance = 5
    missing = [
        x for x in xs_expected
        if not any(abs(x - b) <= tolerance for b in boundaries)
    ]
    assert not missing, f"genuine column rules not detected: {missing}"


def test_declared_layout_count_is_invariant_to_top_margin():
    # Same fit (origin a, pitch b), two crops whose only difference is how much
    # blank space sits above the table -> header_top differs, count must not.
    a, b = 120.0, 74.0
    tall = _lay_declared_rows(a, b, 0.0, [0], header_top=40, data_row_count=24, height=2268)
    # A crop where the header pass locked low (below entry 1): must still emit
    # the same number of boundaries, not drop the top one.
    low = _lay_declared_rows(a, b, 0.0, [0], header_top=400, data_row_count=24, height=2268)
    assert len(tall) == len(low) == 26


def test_declared_layout_count_is_invariant_to_high_origin():
    # First data row near the page top: entry_top - b would be negative. The
    # top boundary must be clamped in, not filtered out, so the count holds.
    laid = _lay_declared_rows(41.0, 74.0, 0.0, [0], header_top=184, data_row_count=24, height=2268)
    assert len(laid) == 26
    assert laid[0] >= 0
    assert laid == sorted(laid)


def test_synthetic_right_page_still_corroborates():
    """No-regression guard: a clean synthetic right page must still corroborate
    the BAPTISMAL_RIGHT template at or above the acceptance floor after any
    band-detector tuning. A more sensitive detector cannot start inventing rules
    that break a good page.
    """
    from app.pipeline.column_template import BAPTISMAL_RIGHT
    from app.pipeline.spread import split_spread
    from app.pipeline.table import detect_grid

    pages = split_spread(make_register_spread(rows=24, cols_left=5, cols_right=5))
    grid = detect_grid(pages.right, BAPTISMAL_RIGHT, data_row_count=24,
                       gutter_x=0, gutter_side="left")
    assert grid.cols == 5
    assert (grid.column_corroboration or 0.0) >= 0.60


def test_declared_rows_follow_perspective_growth():
    # Rule positions measured on a real tilted photo (IMG_3120, left page): the
    # pitch grows from ~76 px at the top to ~90 px at the bottom. A straight
    # comb drifts a whole row by the last entry; the fitted grid must instead
    # land every boundary on its printed rule.
    ys = [235, 319, 391, 465, 539, 616, 679, 755, 832, 910, 988, 1068, 1148,
          1229, 1311, 1393, 1476, 1562, 1630, 1718, 1805, 1896, 1986, 2076, 2164]
    result = _fit_declared_row_grid(ys, header_top=142, data_row_count=24, height=2268)
    assert result is not None
    a, b, c, _ = result
    teeth = [a + b * k + c * k * k for k in range(25)]
    worst = max(min(abs(t - y) for y in ys) for t in teeth)
    assert worst < 0.25 * b  # every row boundary sits on a printed rule


def test_declared_rows_stay_straight_on_an_even_page():
    ys = [200 + 70 * k for k in range(25)]
    a, b, c, _ = _fit_declared_row_grid(ys, header_top=120, data_row_count=24, height=2268)
    assert abs(c) < 1e-6
    assert a == pytest.approx(200, abs=1)
    assert b == pytest.approx(70, abs=0.5)


def _ruled_binary(width, height, col_xs, top, bottom):
    """A binary page whose only long vertical ink is the table's column rules."""
    img = np.zeros((height, width), np.uint8)
    for x in col_xs:
        img[top:bottom, x:x + 3] = 255
    return img


def test_grid_started_too_high_is_slid_down_to_the_table_bottom():
    # Measured on IMG_3120's right page: the comb locked onto the page edge and
    # title, two rows above the table, so laying 24 rows from there stopped two
    # rows short and the last entries were never read. The column rules end at
    # the last entry's bottom border, which puts entry 24 back inside the grid.
    pitch, n = 70.0, 24
    table_top, first_entry = 150, 220
    rules = [first_entry + pitch * k for k in range(n + 1)]
    bottom = int(rules[-1])
    binary = _ruled_binary(1000, 2268, [100, 300, 600, 900], table_top, bottom)
    a, b, c = _anchor_declared_rows_to_table(
        first_entry - 2 * pitch, pitch, 0.0, n, binary, [int(r) for r in rules], 2268
    )
    assert a == pytest.approx(first_entry, abs=1)
    assert a + b * n + c * n * n == pytest.approx(bottom, abs=1)


def test_grid_that_already_meets_the_table_is_left_alone():
    pitch, n = 70.0, 24
    rules = [220 + pitch * k for k in range(n + 1)]
    binary = _ruled_binary(1000, 2268, [100, 300, 600, 900], 150, int(rules[-1]))
    assert _anchor_declared_rows_to_table(
        220.0, pitch, 0.0, n, binary, [int(r) for r in rules], 2268
    ) == (220.0, pitch, 0.0)


def test_grid_is_never_moved_above_the_table_top():
    # A short table (its bottom detected high, e.g. a page cut off by the
    # frame) must not pull entry 1 up into the title above the table.
    pitch, n = 70.0, 24
    rules = [220 + pitch * k for k in range(n + 1)]
    binary = _ruled_binary(1000, 2268, [100, 300, 600, 900], 200, int(rules[-1] - 3 * pitch))
    a, _, _ = _anchor_declared_rows_to_table(
        220.0, pitch, 0.0, n, binary, [int(r) for r in rules], 2268
    )
    assert a >= 200 - 0.25 * pitch


def test_right_page_grid_on_the_header_band_is_moved_below_it():
    # Measured on IMG_3949's right page: the column rules start at the header
    # band's top (165) and end at the bottom border (1970); the true entries
    # are 24 rows of ~72 px from ~237. A grid fitted 4% too tall a row and slid
    # onto the bottom border starts entry 1 at the header's top, so every
    # entry is read from the row above it. Only the lower half's rules were
    # detected.
    n, top, pitch = 24, 237.0, 72.2
    rules = [int(round(top + pitch * k)) for k in range(10, n + 1)]
    binary = _ruled_binary(1300, 2268, [100, 400, 700, 1100], 165, rules[-1])
    bad_pitch = (rules[-1] - 165) / n
    a, b, c = _anchor_declared_rows_to_table(
        165.0, bad_pitch, 0.0, n, binary, rules, 2268, header_refit=True
    )
    assert a == pytest.approx(top, abs=0.3 * pitch)
    for k in range(10, n + 1):
        assert a + b * k + c * k * k == pytest.approx(top + pitch * k, abs=0.2 * pitch)


def test_left_page_grid_is_not_moved_by_the_header_check():
    n, pitch = 24, 70.0
    rules = [int(round(150 + pitch * k)) for k in range(n + 1)]
    binary = _ruled_binary(1300, 2268, [100, 400, 700, 1100], 140, rules[-1])
    assert _anchor_declared_rows_to_table(
        150.0, pitch, 0.0, n, binary, rules, 2268, header_refit=False
    ) == (150.0, pitch, 0.0)
