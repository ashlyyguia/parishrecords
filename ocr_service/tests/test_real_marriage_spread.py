"""Behavioural regression against a real marriage spread photograph.

The inversion cues only have ground truth on real photographs (a synthetic
fixture built to satisfy them would validate them against themselves — see
test_inversion.py), so the proof that a genuinely upright spread is *not*
flipped, and then grids, belongs here.

The sample photographs are local-only (``attachments/`` is git-ignored: they
carry the names of real people, including minors) so this skips cleanly when
they are absent — on CI, or any checkout without them — and only asserts when
run against the operator's own scans. Structure only: it checks row/column
counts and the rotation decision, never cell contents.
"""
import pathlib

import cv2
import pytest

from app.errors import OcrError
from app.pipeline.column_template import MARRIAGE_REGISTER
from app.pipeline.inversion import correct_spread_inversion
from app.pipeline.orientation import correct_orientation
from app.pipeline.rectify import rectify_page
from app.pipeline.spread import split_spread
from app.pipeline.table import detect_spread_grids

_MARRIAGE_DIR = pathlib.Path(__file__).resolve().parents[2] / "attachments" / "marriage"
# An upright, straight-on, high-resolution spread whose lower-left corner shows
# the book cover and the hand holding it — the artefacts that used to make the
# grid service (1) read the spread as upside-down and (2) drop the upper rows.
_UPRIGHT_SPREAD = _MARRIAGE_DIR / "IMG_20260915_094103_305.jpg"


def _grid_a_spread(path: pathlib.Path):
    bgr = cv2.imread(str(path))
    assert bgr is not None, f"could not read {path.name}"
    oriented = correct_orientation(bgr)
    inversion = correct_spread_inversion(oriented.image)
    pages = split_spread(inversion.image)
    left = rectify_page(pages.left).image
    right = rectify_page(pages.right).image
    grids = detect_spread_grids(left, right, spread_template=MARRIAGE_REGISTER)
    return inversion, grids


@pytest.mark.skipif(not _UPRIGHT_SPREAD.exists(),
                    reason="local sample spread not present")
def test_an_upright_spread_is_not_flipped_and_grids_cleanly():
    inversion, grids = _grid_a_spread(_UPRIGHT_SPREAD)
    # It was photographed the right way up; it must not be rotated.
    assert inversion.rotated_180 is False
    # And it must then grid to the marriage register's declared shape. A grid
    # with N row rules bounds N-1 rows here, the first of which is the printed
    # column-header band, so the data-row count is grids.rows - 1 (the endpoint
    # reports exactly this).
    assert grids.rows - 1 == MARRIAGE_REGISTER.data_row_count
    assert grids.left.cols == MARRIAGE_REGISTER.left.column_count
    assert grids.right.cols == MARRIAGE_REGISTER.right.column_count
