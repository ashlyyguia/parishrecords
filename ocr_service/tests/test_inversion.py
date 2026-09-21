"""180-degree detection: correct_orientation only guarantees landscape.

A spread photographed upside-down is still landscape, so it passes through
orientation correction unchanged and reaches table.py's row model with the
column-header band at the bottom, where that model does not expect it.

These tests cover the decision machinery and its safe defaults. The
behavioural proof — that a genuinely inverted spread is detected and put back
the right way up — is in tests/test_real_spread.py, against real photographs
in both orientations, because that is the only place the cues have ground
truth. A synthetic fixture built to satisfy these particular cues would be
validating them against themselves.
"""
import cv2
import numpy as np
import pytest

from app.pipeline.inversion import (
    MIN_INVERSION_VOTES,
    _text_band_centroid_offset,
    correct_spread_inversion,
    count_inversion_votes,
    page_upright_cues,
    spread_is_inverted,
)
from app.pipeline.orientation import correct_orientation
from app.pipeline.spread import split_spread
from tests.support.synthetic import make_register_spread, rotate


def _spread():
    return make_register_spread(rows=24, cols_left=5)


def test_a_blank_page_abstains_rather_than_voting():
    blank = np.full((900, 700, 3), 255, np.uint8)
    cues = page_upright_cues(blank)
    assert all(v is None for v in cues.values()), cues
    assert count_inversion_votes(blank, blank) == (0, 0)


def test_a_vertically_symmetric_spread_yields_no_evidence():
    """The synthetic register is ruled symmetrically: equal margins top and
    bottom, no title band, and rules too thin to form measurable text bands.
    There is genuinely nothing to tell 0 from 180 on it, so every cue must
    abstain rather than reading a sign off rounding noise.

    This is the property that makes the deadbands in inversion.py load
    bearing: without them the margin cue reported a confident -0.0007 here,
    which is 0.07% of the page height and pure noise, and voted on it.
    """
    for angle in (0, 180):
        pages = split_spread(rotate(_spread(), angle))
        for page in (pages.left, pages.right):
            cues = page_upright_cues(page)
            assert all(v is None for v in cues.values()), (angle, cues)


def test_the_centroid_cue_abstains_when_ink_carries_no_vertical_bias():
    """The centroid cue reads the sign of each row's vertical ink bias: on a
    genuine upright row the printed rule at the band's bottom edge weights the
    ink downward. When a band is measurable but its ink sits centred — no
    top/bottom bias, so the offset is within the measurement's own resolution —
    the cue must abstain, exactly as the margin and ink cues already do below
    their deadbands, rather than return a near-zero value that is then cast as
    a vote on noise. Two such noise votes were enough to push a
    legitimately-shaky margin cue over the rotation supermajority on a real,
    upright spread, flipping it upside-down.
    """
    h, w = 1400, 1000
    page = np.full((h, w, 3), 255, np.uint8)
    pitch = h // 12
    # Ten measurable bands, each a thick block of ink centred in its band, so
    # every band's centroid sits at its own centre: measurable, but no bias.
    for r in range(1, 11):
        cy = r * pitch
        cv2.rectangle(page, (100, cy - 18), (w - 100, cy + 18), (20, 20, 20), -1)
    assert _text_band_centroid_offset(page) is None


def test_no_evidence_means_no_rotation():
    """The safe default. With fewer than MIN_INVERSION_VOTES cues voting, no
    rotation happens whatever those few cues say: a wrong 180 turns a
    readable spread into an unreadable one and swaps which physical page is
    'left', whereas a missed 180 is still recoverable downstream.
    """
    for angle in (0, 180):
        spread = rotate(_spread(), angle)
        pages = split_spread(spread)
        inverted, votes, cast = spread_is_inverted(pages.left, pages.right)
        assert cast < MIN_INVERSION_VOTES, cast
        assert inverted is False
        result = correct_spread_inversion(spread)
        assert result.rotated_180 is False
        assert np.array_equal(result.image, spread)


def test_votes_are_reported_for_inspection():
    result = correct_spread_inversion(_spread())
    assert result.votes_cast >= 0
    assert 0 <= result.votes_inverted <= result.votes_cast


def test_a_split_vote_does_not_rotate():
    """A bare majority is not enough, by design: the two outcomes are not
    symmetric, so the tie-break goes to leaving the spread alone."""
    for cast in range(MIN_INVERSION_VOTES, 13):
        required = -(-2 * cast // 3)
        assert required > cast / 2, (cast, required)


@pytest.mark.parametrize("angle", [0, 180])
def test_orientation_stage_alone_cannot_tell_these_apart(angle):
    """Pins the gap this module fills. correct_orientation returns a
    landscape image either way and reports no rotation, which is why a
    separate 180 decision is needed at all."""
    result = correct_orientation(rotate(_spread(), angle))
    assert result.image.shape[1] > result.image.shape[0]
    assert result.rotation_applied == 0
