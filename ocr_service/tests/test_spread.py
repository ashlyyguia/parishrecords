import cv2
import numpy as np

from app.pipeline.spread import split_spread
from tests.support.synthetic import make_register_spread


def test_gutter_is_near_the_centre():
    img = make_register_spread()
    pages = split_spread(img)
    centre = img.shape[1] // 2
    assert abs(pages.gutter_x - centre) < img.shape[1] * 0.12


def test_pages_are_non_empty_and_roughly_equal():
    pages = split_spread(make_register_spread())
    lw = pages.left.shape[1]
    rw = pages.right.shape[1]
    assert lw > 100 and rw > 100
    assert abs(lw - rw) < max(lw, rw) * 0.35


def test_pages_do_not_overlap_the_gutter():
    img = make_register_spread()
    pages = split_spread(img)
    assert pages.left.shape[1] + pages.right.shape[1] <= img.shape[1]


def test_gutter_is_found_off_centre():
    """Proves the algorithm analyzes pixel content, not stubbed to width // 2."""
    # Gutter at ~40% width (offset -200 from centre on 2400px wide image)
    img = make_register_spread(gutter_offset=-200)
    pages = split_spread(img)
    expected_gutter = img.shape[1] // 2 - 200
    # Must find gutter within ±50 pixels
    assert abs(pages.gutter_x - expected_gutter) < 50


def test_gutter_found_despite_spine_shadow():
    """Adaptive threshold removes low-frequency shadows while keeping sharp strokes.

    This tests robustness to a book that does not lie perfectly flat.
    A dark vertical band over the gutter simulates a shadow.
    """
    img = make_register_spread()
    h, w = img.shape[:2]
    mid = w // 2
    # Draw a dark shadow band (width ~100px) over the gutter
    shadow_width = 100
    cv2.rectangle(
        img,
        (mid - shadow_width // 2, 0),
        (mid + shadow_width // 2, h),
        (80, 80, 80),  # Dark grey shadow
        -1,
    )
    pages = split_spread(img)
    # Gutter should still be found near centre despite the shadow
    centre = w // 2
    assert abs(pages.gutter_x - centre) < w * 0.12
