import pathlib

import cv2
import numpy as np
import pytest

from app.pipeline.rectify import measure_rule_angles, rectify_page
from app.pipeline.spread import split_spread
from app.pipeline.table import detect_grid
from tests.support.synthetic import make_register_spread, shear_image


def _left_page(h_deg: float = 0.0, v_deg: float = 0.0) -> np.ndarray:
    """Split first, then shear the isolated page — matching production order.

    The real pipeline always runs split_spread on an already roughly-deskewed
    spread (correct_orientation runs first) and only discovers per-page shear
    afterwards, on the isolated page. Shearing the *whole* spread before
    splitting instead — as an earlier version of this fixture did — pushes
    the gutter far enough that split_spread's column-ink search finds it in
    the wrong place, cropping the left page's own rightmost column rule out
    of existence before rectify_page ever sees it. That is a fixture-order
    bug, not something rectify_page can or should compensate for: no
    transform can recover pixels absent from its input.
    """
    spread = make_register_spread(rows=24, cols_left=5)
    page = split_spread(spread).left
    if h_deg or v_deg:
        page = shear_image(page, h_deg, v_deg)
    return page


def test_measures_a_known_shear():
    h, v = measure_rule_angles(_left_page(h_deg=-2.5, v_deg=4.0))
    assert abs(h - (-2.5)) < 1.5, h
    assert abs(v - 4.0) < 1.5, v


def test_straight_page_measures_near_zero():
    h, v = measure_rule_angles(_left_page())
    assert abs(h) < 1.0
    assert abs(v) < 1.0


def test_rectify_removes_the_shear():
    rectified = rectify_page(_left_page(h_deg=-2.5, v_deg=4.0))
    h, v = measure_rule_angles(rectified.image)
    assert abs(h) < 1.0, h
    assert abs(v) < 1.0, v


def test_rectify_reports_what_it_measured():
    result = rectify_page(_left_page(h_deg=-2.5, v_deg=4.0))
    assert abs(result.h_angle_deg - (-2.5)) < 1.5
    assert abs(result.v_angle_deg - 4.0) < 1.5


def test_rectify_is_near_identity_on_a_straight_page():
    page = _left_page()
    result = rectify_page(page)
    assert result.image.shape == page.shape
    assert abs(result.h_angle_deg) < 1.0
    assert abs(result.v_angle_deg) < 1.0


def test_sheared_page_grids_correctly_after_rectify():
    """The whole point: detect_grid fails on shear and succeeds after rectify."""
    sheared = _left_page(h_deg=-2.5, v_deg=4.0)
    rectified = rectify_page(sheared).image
    grid = detect_grid(rectified)
    assert grid.cols == 5, grid.cols
    assert 24 <= grid.rows <= 26, grid.rows


def test_unmeasurable_page_is_returned_unchanged():
    blank = np.full((600, 900, 3), 255, np.uint8)
    result = rectify_page(blank)
    assert result.h_angle_deg == 0.0
    assert result.v_angle_deg == 0.0
    assert np.array_equal(result.image, blank)
