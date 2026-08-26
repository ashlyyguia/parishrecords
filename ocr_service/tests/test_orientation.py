import pytest
from app.pipeline.orientation import correct_orientation
from tests.support.synthetic import make_register_spread, rotate, skew


@pytest.mark.parametrize("deg", [0, 90, 180, 270])
def test_restores_landscape_orientation(deg):
    src = make_register_spread()
    result = correct_orientation(rotate(src, deg))
    h, w = result.image.shape[:2]
    assert w > h, f"expected landscape after correcting {deg} deg, got {w}x{h}"


def test_reports_rotation_for_portrait_input():
    src = make_register_spread()
    result = correct_orientation(rotate(src, 90))
    assert result.rotation_applied in (90, 270)


def test_deskew_is_small_on_straight_input():
    result = correct_orientation(make_register_spread())
    assert abs(result.deskew_deg) < 1.0


def test_deskew_detects_known_tilt():
    """A stubbed _estimate_skew returning 0.0 would fail this: it must find
    the applied tilt, not just stay under a ceiling on straight input.

    Empirically (see task-2-report.md), correct_orientation reports a
    deskew_deg of roughly -1x the angle applied by skew() — cv2's rotation
    matrix angle and the Hough line-angle convention have opposite sign due
    to the image y-axis pointing down. We assert on that observed sign
    rather than assuming one.
    """
    tilted = skew(make_register_spread(), 3.0)
    result = correct_orientation(tilted)
    assert abs(result.deskew_deg - (-3.0)) < 1.0


def test_deskew_correction_reduces_residual_skew():
    """A stubbed _estimate_skew returning 0.0 would report the same (zero)
    residual on both passes; the real detector must show the second pass
    is meaningfully straighter than the first.
    """
    tilted = skew(make_register_spread(), 3.0)
    first_pass = correct_orientation(tilted)
    second_pass = correct_orientation(first_pass.image)
    assert abs(second_pass.deskew_deg) < abs(first_pass.deskew_deg) / 2
