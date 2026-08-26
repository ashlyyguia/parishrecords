"""Decide whether a register spread was photographed upside-down, and fix it.

``correct_orientation`` only guarantees a *landscape* frame: it cannot tell 0
from 180 degrees, because both are landscape. Everything downstream of it
assumes the register reads top-to-bottom — most sharply, ``table.py``'s row
model, which treats the first detected row band as the column-header row and
excludes it from the data-row pitch fit. Feeding that model an inverted page
puts the header at the bottom, so the fit is anchored to the wrong end of the
table.

Why this runs on the *spread* and not on a page in isolation
------------------------------------------------------------
Rotating each page half independently would make each half read the right way
up while leaving them on the wrong sides of each other: in an inverted photo
``split_spread``'s "left" half holds the physically *right* page. A later task
joins the left page's child/birth columns to the right page's baptism columns,
so swapping them silently files every value under the wrong field. The
evidence is gathered per page (each half votes), but the correction is applied
to the whole spread, which keeps left and right identity intact.

No recognizer is used or needed: every cue below is a measurement of ink
geometry, not of characters.
"""
from dataclasses import dataclass

import cv2
import numpy as np

from .table import ROW_STRIP_CLUSTER_TOLERANCE, detect_row_rule_segments

# How the cues combine
# ---------------------
# A cue's *sign* is its vote: positive means "this page looks upright". Only
# the sign is used, never the magnitude, because the three cues measure
# unrelated quantities on unrelated scales (a fraction of total ink, a
# fraction of page height, a fraction of a text band's height). Averaging
# them would let whichever cue happens to have the widest numeric range
# decide on its own. A cue that measures exactly 0.0 — a blank page, or one
# where too few rules were found for the measurement to mean anything —
# abstains instead of voting either way.
#
# What happens when the cues disagree: nothing. Disagreement lowers the
# inverted-vote count below the supermajority, so the spread is left exactly
# as it came in. That is the deliberate default, because the two outcomes are
# not symmetric. Failing to rotate a genuinely inverted spread is
# recoverable: it may still grid, and if it does not, the spread-level
# quality gate refuses it and the operator is asked to retake the photo.
# Rotating an upright spread is not recoverable: it turns a readable spread
# into an unreadable one, and it also swaps which physical page is "left",
# which is precisely the mix-up the pipeline exists to prevent. So the bar to
# act is high and the bar to do nothing is zero.

# At least this many cues must actually vote before a rotation is considered.
# Below three, a "two-thirds supermajority" degenerates: 2 of 2, or 1 of 1,
# is a single measurement deciding unopposed. Three is the smallest number at
# which the rule can survive one cue being wrong, which is the property being
# bought here — and every cue misfired on at least one real page half during
# tuning, so one being wrong is the expected case, not the pathological one.
MIN_INVERSION_VOTES = 3

# The supermajority required to rotate, as a fraction of the votes cast.
# Deliberately not a bare majority: see the asymmetry above. Measured across
# both halves of all three real spreads, in their as-shot orientation and
# rotated 180 degrees (six spreads, six votes each), an upright spread drew
# 0-1 inverted votes and an inverted spread drew 5-6. Two thirds of six is
# four, which sits clear of both clusters rather than between two adjacent
# observations, so this is a separation the data supports rather than a
# threshold fitted to it.
INVERSION_VOTE_NUMERATOR = 2
INVERSION_VOTE_DENOMINATOR = 3

# Row-rule clusters must be seen across at least this fraction of the page's
# vertical strips to count as a genuine full-width rule for the margin cue
# (the same standard table.py applies when fitting the row grid).
_MARGIN_CUE_MIN_SPAN_FRACTION = 0.5

# Below this many detected rules, the first and last are not the table's two
# ends — they are just whichever two survived thresholding, so the margins
# either side of them measure nothing. Six is two more than the four points
# table.py needs to fit a row curve at all: a page too poor to fit is
# certainly too poor to have its margins compared.
MIN_RULES_FOR_MARGIN_CUE = 6


@dataclass(frozen=True)
class InversionResult:
    image: np.ndarray
    rotated_180: bool
    votes_inverted: int
    votes_cast: int


def _binary(page_bgr: np.ndarray) -> np.ndarray:
    gray = cv2.cvtColor(page_bgr, cv2.COLOR_BGR2GRAY)
    return cv2.adaptiveThreshold(
        gray, 255, cv2.ADAPTIVE_THRESH_GAUSSIAN_C, cv2.THRESH_BINARY_INV, 25, 12
    )


def _row_ink(page_bgr: np.ndarray) -> np.ndarray:
    return (_binary(page_bgr) > 0).sum(axis=1).astype(np.float64)


def _ink_below_midline(page_bgr: np.ndarray) -> float | None:
    """Ink in the lower half of the page minus ink in the upper half.

    A register page opens with a printed title band that is mostly white
    space, and the ruled table then fills downward; the lower half therefore
    carries more ink than the upper half. Positive means upright; None
    abstains.

    This is the weakest-justified of the three cues and is deliberately the
    most eager to abstain. The imbalance it measures is small even on a
    clearly upright page, and it depends on how full the register happens to
    be rather than on how it is ruled, so its sign on a nearly-balanced page
    says nothing. It abstains unless the imbalance exceeds one row's worth of
    ink — the smallest unit of vertical structure a ruled table has, taken
    from the page's own detected rule count rather than assumed.
    """
    profile = _row_ink(page_bgr)
    total = profile.sum()
    if total <= 0:
        return None
    half = len(profile) // 2
    imbalance = float((profile[half:].sum() - profile[:half].sum()) / total)

    rules = detect_row_rule_segments(
        page_bgr, min_strip_span_fraction=_MARGIN_CUE_MIN_SPAN_FRACTION
    )
    if len(rules) < MIN_RULES_FOR_MARGIN_CUE:
        return None
    if abs(imbalance) < 1.0 / len(rules):
        return None
    return imbalance


def _table_margin_asymmetry(page_bgr: np.ndarray) -> float | None:
    """Gap below the last detected row rule minus the gap above the first,
    as a fraction of page height.

    The table starts close under the title band but stops well short of the
    page's bottom edge, so the trailing margin is the larger of the two.
    Positive means upright; None abstains, when too few rules are detected
    for the two margins to mean anything.
    """
    height = page_bgr.shape[0]
    if height <= 0:
        return None
    rules = detect_row_rule_segments(
        page_bgr, min_strip_span_fraction=_MARGIN_CUE_MIN_SPAN_FRACTION
    )
    # Fewer rules than this and "first" and "last" are not describing the
    # table's two ends, just the two strongest survivors of thresholding.
    if len(rules) < MIN_RULES_FOR_MARGIN_CUE:
        return None
    leading = rules[0]
    trailing = height - 1 - rules[-1]
    difference = trailing - leading
    # Abstain when the two margins differ by less than the precision the
    # endpoints were measured to. Each endpoint is a *cluster* of per-strip
    # detections, and ROW_STRIP_CLUSTER_TOLERANCE is the distance within
    # which table.py already treats two detections as the same physical rule
    # — so a gap difference smaller than that is below this cue's own
    # resolution, and its sign is noise. Without this the cue votes
    # confidently on a symmetric page, where it has nothing to say.
    if abs(difference) < ROW_STRIP_CLUSTER_TOLERANCE:
        return None
    return float(difference / height)


def _text_band_centroid_offset(page_bgr: np.ndarray) -> float | None:
    """How far each line of ink sits below the centre of its own band,
    median over bands, as a fraction of band height.

    Each ruled row holds handwriting sitting on a printed rule, so a row's
    ink is bottom-weighted: the rule contributes a dense stripe at the
    bottom edge of the band while the writing above it is sparse. Positive
    means upright; None abstains, when no band is tall enough to measure.
    """
    profile = _row_ink(page_bgr)
    if profile.max() <= 0:
        return None
    # A tenth of the strongest line is low enough to catch faint rows and
    # high enough to ignore speckle; the threshold is relative to the page's
    # own strongest line, never an absolute ink count.
    threshold = profile.max() * 0.10
    bands: list[tuple[int, int]] = []
    run: list[int] = []
    for y, value in enumerate(profile):
        if value >= threshold:
            run.append(y)
        elif run:
            bands.append((run[0], run[-1]))
            run = []
    if run:
        bands.append((run[0], run[-1]))

    offsets = []
    for y0, y1 in bands:
        span = y1 - y0
        # Bands thinner than this carry too few rows of pixels for a
        # centroid to say anything; scale with the page so the rule holds at
        # any capture resolution.
        if span < max(4, page_bgr.shape[0] // 400):
            continue
        weights = profile[y0:y1 + 1]
        if weights.sum() <= 0:
            continue
        ys = np.arange(y0, y1 + 1, dtype=np.float64)
        centroid = float((weights * ys).sum() / weights.sum())
        offsets.append((centroid - (y0 + y1) / 2.0) / span)
    return float(np.median(offsets)) if offsets else None


PAGE_CUES = (
    ("ink_below_midline", _ink_below_midline),
    ("table_margin_asymmetry", _table_margin_asymmetry),
    ("text_band_centroid", _text_band_centroid_offset),
)


def page_upright_cues(page_bgr: np.ndarray) -> dict[str, float | None]:
    """Every cue's signed score for one page. Positive means upright, None
    means the cue abstained because the page gave it nothing to measure.

    Exposed so a caller (in particular, a test) can see *why* a spread was or
    was not rotated, without re-deriving the measurements.
    """
    return {name: fn(page_bgr) for name, fn in PAGE_CUES}


def count_inversion_votes(*pages_bgr: np.ndarray) -> tuple[int, int]:
    """(votes for inverted, votes cast) pooled over the given pages."""
    inverted = 0
    cast = 0
    for page in pages_bgr:
        for score in page_upright_cues(page).values():
            if score is None:
                continue
            cast += 1
            if score < 0.0:
                inverted += 1
    return inverted, cast


def spread_is_inverted(left_bgr: np.ndarray, right_bgr: np.ndarray) -> tuple[bool, int, int]:
    """Whether both halves agree, by supermajority, that the spread is upside-down."""
    inverted, cast = count_inversion_votes(left_bgr, right_bgr)
    if cast < MIN_INVERSION_VOTES:
        return False, inverted, cast
    required = -(-INVERSION_VOTE_NUMERATOR * cast // INVERSION_VOTE_DENOMINATOR)
    return inverted >= required, inverted, cast


def correct_spread_inversion(spread_bgr: np.ndarray) -> InversionResult:
    """Return the spread the right way up, rotating it 180 degrees if needed.

    Never raises, and never rotates without a supermajority of cues from both
    halves: an unrotated ambiguous spread is recoverable downstream, a
    wrongly-rotated one is not.
    """
    # Imported here rather than at module scope: spread.py is a peer stage and
    # importing it at the top would make the two modules import each other if
    # split_spread ever wants an inversion cue.
    from .spread import split_spread

    pages = split_spread(spread_bgr)
    inverted, votes, cast = spread_is_inverted(pages.left, pages.right)
    if not inverted:
        return InversionResult(
            image=spread_bgr, rotated_180=False, votes_inverted=votes, votes_cast=cast
        )
    return InversionResult(
        image=cv2.rotate(spread_bgr, cv2.ROTATE_180),
        rotated_180=True,
        votes_inverted=votes,
        votes_cast=cast,
    )
