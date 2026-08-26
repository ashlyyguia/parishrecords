"""The spread-level quality gate: both pages must agree, or nothing is returned.

These use the synthetic generator only, so they pin the *refusal contract*
independently of whether any particular real photograph currently grids
correctly. tests/test_real_spread.py exercises the same gate on real photos.
"""
import cv2
import numpy as np
import pytest

from app.errors import OcrError
from app.pipeline.spread import split_spread
from app.pipeline.table import (
    SPREAD_PITCH_TOLERANCE,
    detect_grid,
    detect_spread_grids,
    median_data_row_pitch,
    row_boundaries,
)
from tests.support.synthetic import make_register_spread

# Words that would mean the message is leaking the register's contents rather
# than describing the photograph. The gate reports structure only.
FORBIDDEN_IN_MESSAGE = ("name", "child", "parent", "sponsor", "minister",
                        "baptism date", "\\", "/", ".jpeg", ".jpg", ".png")


def _pages(rows: int = 24, cols_left: int = 5, cols_right: int = 5):
    spread = make_register_spread(rows=rows, cols_left=cols_left, cols_right=cols_right)
    pages = split_spread(spread)
    return pages.left, pages.right


def _assert_safe_refusal(error: OcrError, *expected_words: str) -> None:
    assert error.code == "no_table_detected", error.code
    message = error.message
    lowered = message.lower()
    for word in expected_words:
        assert word in lowered, f"message does not say what disagreed: {message!r}"
    for word in FORBIDDEN_IN_MESSAGE:
        assert word not in lowered, f"message leaks {word!r}: {message!r}"
    # The Flutter workflow offers exactly these two recoveries on this code;
    # the message is what tells a staff member which one to reach for.
    assert "retry" in lowered and "manually" in lowered, message


def test_agreeing_pages_are_returned():
    left, right = _pages()
    result = detect_spread_grids(left, right)
    assert result.rows == detect_grid(left).rows
    assert result.cols == detect_grid(left).cols
    assert result.left.rows == result.right.rows
    assert result.left.cols == result.right.cols


def test_expected_column_count_is_not_written_into_the_detector():
    """The gate must accept a register ruled with a different column count.

    Five columns per page is a property of *this* register, asserted in the
    real-photo tests. Hardcoding it in production would make the service
    refuse a different register book outright instead of reading it.
    """
    left, right = _pages(cols_left=4, cols_right=4)
    result = detect_spread_grids(left, right)
    assert result.cols == 4


def test_column_count_disagreement_is_refused():
    left, right = _pages(cols_left=5, cols_right=4)
    with pytest.raises(OcrError) as e:
        detect_spread_grids(left, right)
    _assert_safe_refusal(e.value, "column")


def test_row_count_disagreement_is_refused():
    """Row counts must match exactly — this is the corruption the whole
    architecture exists to prevent, since a one-row drift pairs every
    subsequent entry with the wrong person and nothing downstream can tell."""
    left = split_spread(make_register_spread(rows=24)).left
    right = split_spread(make_register_spread(rows=20)).right
    left_rows = detect_grid(left).rows
    right_rows = detect_grid(right).rows
    assert left_rows != right_rows, "fixture no longer produces disagreeing rows"

    with pytest.raises(OcrError) as e:
        detect_spread_grids(left, right)
    _assert_safe_refusal(e.value, "row")


def test_pitch_disagreement_is_refused_even_when_the_counts_match():
    """Equal counts are not sufficient. A page can find the right *number* of
    boundaries in the wrong places; two different pitches for one physical
    table catches that independently of the counts.
    """
    left, right = _pages()
    # Squeeze one page vertically. The rules stay evenly pitched and equal in
    # number, so only the pitch check can catch this.
    squeezed = cv2.resize(right, (right.shape[1], int(right.shape[0] * 0.75)),
                          interpolation=cv2.INTER_AREA)
    left_grid, right_grid = detect_grid(left), detect_grid(squeezed)
    assert left_grid.rows == right_grid.rows, "fixture must keep row counts equal"
    assert left_grid.cols == right_grid.cols, "fixture must keep column counts equal"
    ratio = (max(median_data_row_pitch(left_grid), median_data_row_pitch(right_grid))
             / min(median_data_row_pitch(left_grid), median_data_row_pitch(right_grid)))
    assert ratio - 1.0 > SPREAD_PITCH_TOLERANCE, "fixture must exceed the tolerance"

    with pytest.raises(OcrError) as e:
        detect_spread_grids(left, squeezed)
    _assert_safe_refusal(e.value, "spaced")


def test_an_ungriddable_page_is_refused_naming_the_side():
    left, _ = _pages()
    blank = np.full((800, 1200, 3), 255, np.uint8)
    with pytest.raises(OcrError) as e:
        detect_spread_grids(left, blank)
    _assert_safe_refusal(e.value, "right page")


def test_row_boundaries_are_one_more_than_the_row_count():
    left, _ = _pages()
    grid = detect_grid(left)
    assert len(row_boundaries(grid)) == grid.rows + 1
