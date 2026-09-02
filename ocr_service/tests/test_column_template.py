"""The declared column ruling, and fitting it to a page.

Everything here is drawn in-process, so these hold without any real
photograph. The drawing helper is local to this file on purpose: it needs to
produce the one thing the shared synthetic generator deliberately does not —
a table that does *not* fill its page crop, with sub-dividers ruled inside its
own columns — and the shared generator must not grow special cases to serve
one test.
"""
import cv2
import numpy as np
import pytest

from app.errors import OcrError
from app.pipeline.column_template import (
    BAPTISMAL_LEFT,
    BAPTISMAL_REGISTER,
    BAPTISMAL_RIGHT,
    ColumnTemplate,
)
from app.pipeline.table import (
    TEMPLATE_CORROBORATION_FLOOR,
    detect_column_rule_positions,
    detect_grid,
    detect_spread_grids,
)

# A table drawn at these fractions of the page crop. Deliberately not centred
# and not full width: the point of the exercise is that the template is fitted
# to the *table*, wherever the table happens to sit in the crop.
TABLE_LEFT_FRACTION = 0.28
TABLE_RIGHT_FRACTION = 0.91


def _draw_table(
    template: ColumnTemplate,
    width: int = 1600,
    height: int = 1400,
    left_fraction: float = TABLE_LEFT_FRACTION,
    right_fraction: float = TABLE_RIGHT_FRACTION,
    rows: int = 20,
    sub_divided: tuple[int, ...] = (),
) -> tuple[np.ndarray, list[int]]:
    """Draw a ruled table with ``template``'s proportions, and return the page
    together with the true boundary positions.

    ``sub_divided`` names columns to rule down the middle — the register's own
    habit, and the reason a rule-counting detector cannot recover this layout.
    Everything outside the table is drawn as background, so the crop is not
    the table.
    """
    page = np.full((height, width, 3), 250, np.uint8)
    # Something beyond the paper's edge, as a photograph would have.
    cv2.rectangle(page, (0, 0), (int(width * left_fraction * 0.6), height),
                  (170, 170, 165), -1)

    x_lo = int(width * left_fraction)
    x_hi = int(width * right_fraction)
    table_width = x_hi - x_lo
    top, bottom = int(height * 0.08), int(height * 0.94)
    ink = (140, 60, 40)

    truth = [x_lo + int(round(f * table_width)) for f in template.boundaries]
    for x in truth:
        cv2.line(page, (x, top), (x, bottom), ink, 2)
    for index in sub_divided:
        middle = (truth[index] + truth[index + 1]) // 2
        cv2.line(page, (middle, top), (middle, bottom), ink, 2)

    header_bottom = top + (bottom - top) // (rows + 2)
    ys = [top, header_bottom]
    pitch = (bottom - header_bottom) / rows
    ys += [int(header_bottom + i * pitch) for i in range(1, rows + 1)]
    for y in ys:
        cv2.line(page, (x_lo, y), (x_hi, y), ink, 2)
    return page, truth


class TestTemplateDeclaration:
    """The template is data, and it validates itself."""

    def test_this_register_has_five_columns_on_each_page(self):
        assert BAPTISMAL_LEFT.column_count == 5
        assert BAPTISMAL_RIGHT.column_count == 5

    def test_columns_are_named_with_the_system_s_own_field_keys(self):
        assert BAPTISMAL_LEFT.columns == (
            "no", "child_name", "place_and_birth_date", "l_or_ill", "parents",
        )
        assert BAPTISMAL_RIGHT.columns == (
            "residents_of", "baptism_date", "minister", "sponsors", "observations",
        )

    def test_boundaries_span_the_table_not_the_page(self):
        for template in (BAPTISMAL_LEFT, BAPTISMAL_RIGHT):
            assert template.boundaries[0] == 0.0
            assert template.boundaries[-1] == 1.0

    def test_a_miscounted_template_is_rejected_on_construction(self):
        with pytest.raises(ValueError, match="boundaries"):
            ColumnTemplate(name="bad", columns=("a", "b"), boundaries=(0.0, 1.0))

    def test_boundaries_that_do_not_increase_are_rejected(self):
        with pytest.raises(ValueError, match="increase"):
            ColumnTemplate(name="bad", columns=("a", "b", "c"),
                           boundaries=(0.0, 0.7, 0.5, 1.0))

    def test_a_spread_pairs_two_different_page_rulings(self):
        assert BAPTISMAL_REGISTER.left is not BAPTISMAL_REGISTER.right
        assert BAPTISMAL_REGISTER.left.boundaries != BAPTISMAL_REGISTER.right.boundaries


class TestFittingTheTemplate:
    def test_the_template_is_fitted_to_the_table_not_to_the_page_crop(self):
        """The heart of it: the table occupies a minority of the crop, and the
        fitted boundaries must land on the table's own rules regardless."""
        page, truth = _draw_table(BAPTISMAL_LEFT)
        grid = detect_grid(page, BAPTISMAL_LEFT)

        assert grid.cols == BAPTISMAL_LEFT.column_count
        xs = sorted({c.x for c in grid.cells} | {c.x + c.w for c in grid.cells})
        assert len(xs) == len(truth)
        worst = max(abs(a - b) for a, b in zip(xs, truth))
        # Well inside the narrowest column, which is 6.6% of the table.
        assert worst <= 0.01 * (truth[-1] - truth[0]), (
            f"fitted boundaries {xs} vs drawn {truth}, worst off by {worst}px"
        )

    def test_a_page_crop_that_frames_the_table_differently_fits_the_same(self):
        """The proportions are of the table, so moving the table within the
        crop must not change which cell a column key names."""
        near, near_truth = _draw_table(BAPTISMAL_LEFT, left_fraction=0.10,
                                       right_fraction=0.70)
        far, far_truth = _draw_table(BAPTISMAL_LEFT, left_fraction=0.34,
                                     right_fraction=0.97)
        for page, truth in ((near, near_truth), (far, far_truth)):
            grid = detect_grid(page, BAPTISMAL_LEFT)
            assert grid.cols == BAPTISMAL_LEFT.column_count
            assert grid.column_keys == BAPTISMAL_LEFT.columns
            assert abs(grid.table_x_lo - truth[0]) <= 0.02 * (truth[-1] - truth[0])
            assert abs(grid.table_x_hi - truth[-1]) <= 0.02 * (truth[-1] - truth[0])

    def test_sub_dividers_inside_columns_do_not_change_the_column_count(self):
        """The failure that made a rule-counting detector unusable on this
        register. The sub-dividers are drawn identically to real boundaries,
        so nothing about the marks distinguishes them."""
        page, truth = _draw_table(BAPTISMAL_LEFT, sub_divided=(3, 4))
        detected = detect_column_rule_positions(page)
        assert len(detected) > len(truth), (
            "fixture must actually produce extra vertical rules, otherwise "
            "this test proves nothing"
        )
        grid = detect_grid(page, BAPTISMAL_LEFT)
        assert grid.cols == BAPTISMAL_LEFT.column_count

    def test_the_fit_records_where_it_put_the_table_and_how_well_it_matched(self):
        page, truth = _draw_table(BAPTISMAL_RIGHT)
        grid = detect_grid(page, BAPTISMAL_RIGHT)
        assert grid.column_keys == BAPTISMAL_RIGHT.columns
        assert 0 <= grid.table_x_lo < grid.table_x_hi <= page.shape[1]
        assert grid.column_corroboration >= TEMPLATE_CORROBORATION_FLOOR

    def test_a_grid_detected_without_a_template_records_no_fit(self):
        """A caller must be able to tell a fitted grid from a detected one."""
        page, _ = _draw_table(BAPTISMAL_LEFT)
        grid = detect_grid(page)
        assert grid.column_keys is None
        assert grid.table_x_lo is None
        assert grid.column_corroboration is None

    def test_a_page_with_no_table_at_all_is_refused_not_fitted(self):
        """Fitting always produces boundaries — that is what fitting means. A
        page with nothing to fit them to must raise, not return five confident
        columns over blank paper."""
        blank = np.full((1400, 1600, 3), 250, np.uint8)
        with pytest.raises(OcrError):
            detect_grid(blank, BAPTISMAL_LEFT)


class TestTheGateChecksTheFit:
    def _spread(self, **kwargs):
        left, _ = _draw_table(BAPTISMAL_LEFT, **kwargs)
        right, _ = _draw_table(BAPTISMAL_RIGHT, **kwargs)
        return left, right

    def test_two_well_fitted_pages_are_accepted(self):
        left, right = self._spread()
        spread = detect_spread_grids(left, right,
                                     spread_template=BAPTISMAL_REGISTER)
        assert spread.cols == 5
        assert spread.left.column_keys == BAPTISMAL_LEFT.columns
        assert spread.right.column_keys == BAPTISMAL_RIGHT.columns
        assert spread.left_corroboration >= TEMPLATE_CORROBORATION_FLOOR
        assert spread.right_corroboration >= TEMPLATE_CORROBORATION_FLOOR

    def test_a_page_whose_ruling_does_not_match_the_template_is_refused(self):
        """The check that keeps the declaration answerable to the page. The
        right page here is drawn with the *left* page's ruling: the fit still
        produces five columns, so only corroboration can catch it."""
        left, _ = _draw_table(BAPTISMAL_LEFT)
        mismatched, _ = _draw_table(BAPTISMAL_LEFT)
        with pytest.raises(OcrError) as excinfo:
            detect_spread_grids(left, mismatched,
                                spread_template=BAPTISMAL_REGISTER)
        message = excinfo.value.message.lower()
        assert excinfo.value.code == "no_table_detected"
        assert "column edges" in message, excinfo.value.message
        assert "right" in message, excinfo.value.message
        # Still safe to show a staff member: structure only.
        for leak in ("\\", "/", ".jpeg", "template", "corrobor"):
            assert leak not in message, excinfo.value.message

    def test_the_refusal_names_both_recoveries_the_app_offers(self):
        left, _ = _draw_table(BAPTISMAL_LEFT)
        mismatched, _ = _draw_table(BAPTISMAL_LEFT)
        with pytest.raises(OcrError) as excinfo:
            detect_spread_grids(left, mismatched,
                                spread_template=BAPTISMAL_REGISTER)
        message = excinfo.value.message.lower()
        assert "retry" in message and "manually" in message, excinfo.value.message


def test_register_declares_its_fixed_row_count():
    # The book is ruled for a fixed number of entries, a property of the
    # printed form just like its column proportions.
    assert BAPTISMAL_REGISTER.data_row_count == 24
