from dataclasses import dataclass
from typing import NoReturn

import cv2
import numpy as np

from ..errors import OcrError
from .column_template import ColumnTemplate, SpreadColumnTemplate

MIN_COLS = 2
MIN_ROWS = 3

# How far the two halves of one spread may disagree about their row pitch
# before the pair is refused. The pages are two halves of a single physical
# ruled table, so their pitches describe the same printed spacing; the only
# legitimate difference is the perspective scale between the two halves of a
# hand-held photograph, which is small. Anything larger means at least one
# page's row model is wrong.
SPREAD_PITCH_TOLERANCE = 0.10


@dataclass(frozen=True)
class CellRect:
    row: int
    col: int
    x: int
    y: int
    w: int
    h: int


@dataclass(frozen=True)
class GridResult:
    rows: int
    cols: int
    cells: list[CellRect]
    # Populated only when a declared column template was fitted (see
    # detect_grid). ``column_keys`` names each column with the field key the
    # rest of the system uses; ``table_x_lo``/``table_x_hi`` record the
    # horizontal extent the template was fitted into, measured from this
    # page's own row rules; ``column_corroboration`` is the fraction of the
    # fitted boundaries that landed on an independently detected vertical
    # rule. They stay None on the template-free path so a caller can tell a
    # fitted grid from a purely detected one rather than guessing.
    column_keys: tuple[str, ...] | None = None
    table_x_lo: int | None = None
    table_x_hi: int | None = None
    column_corroboration: float | None = None

    def cell(self, row: int, col: int) -> CellRect | None:
        for c in self.cells:
            if c.row == row and c.col == col:
                return c
        return None


def _binary(page_bgr: np.ndarray) -> np.ndarray:
    gray = cv2.cvtColor(page_bgr, cv2.COLOR_BGR2GRAY)
    return cv2.adaptiveThreshold(
        gray, 255, cv2.ADAPTIVE_THRESH_GAUSSIAN_C, cv2.THRESH_BINARY_INV, 25, 12
    )


# Fraction of the reference "full-strength rule" level at which a projection
# peak still counts as a rule. Well below 1.0 because a printed rule on a
# photographed page is faded, partly obscured, or clipped by the erosion over
# much of its length: holding every rule to the strength of the best-preserved
# one would discard most of a real register's grid. Shared by both projection
# passes below so the two axes judge "is this a rule" by one standard.
PEAK_FLOOR_FRACTION = 0.45

# Percentile of the *non-zero* projection values used as that reference level.
# See _line_positions for why a percentile beats the raw maximum here.
PEAK_REFERENCE_PERCENTILE = 90


def _line_positions(
    binary: np.ndarray,
    axis: int,
    kernel_span: int,
    merge_span: int,
    kernel_divisor: int = 12,
    gap_divisor: int = 60,
) -> list[int]:
    """Isolate rules along one axis with a long 1-D morphological kernel.

    A kernel far longer than any handwriting stroke survives only for printed
    rules, so the projection peaks are the grid lines themselves — not text.

    ``kernel_span`` and ``merge_span`` are deliberately separate parameters,
    even though callers sometimes pass the same value for both by
    coincidence of a square-ish page: the kernel needs the *perpendicular*
    page dimension (a horizontal rule's kernel scales with page width; a
    vertical rule's with page height), while the merge distance needs the
    dimension positions are measured *along* (row y-positions merge against
    page height; column x-positions merge against page width). Collapsing
    both into one ``span`` silently uses the wrong dimension for one of the
    two on any page whose aspect ratio, or column/row density, differs from
    roughly square.

    ``kernel_divisor`` and ``gap_divisor`` default to conservative, long/tight
    values that suit a dense axis of many, closely-pitched rules (row
    detection uses the default kernel_divisor but calls with a wider
    gap_divisor — see detect_grid). The column axis on a real, bound-book
    photograph needs its own, wider tuning on both: even after per-page shear
    rectification, a physically curved page leaves each column with a little
    *residual, non-uniform* tilt that a single global affine cannot remove
    (rectify.py corrects one shear angle for the whole page; page curvature
    varies it slightly by position). A column-length kernel then loses
    contiguity along the same drift mechanism rectify.py exists to fix,
    fragmenting one physical column into several weak candidates spread
    across a wider gap than adjacent genuine columns' own spacing would
    suggest. Columns are also far more widely spaced than rows in this
    document (five columns vs. ~25 rows across a similar span), so a larger
    merge gap consolidates a fragmented column's pieces without reaching far
    enough to swallow a neighbouring, genuinely distinct one.
    """
    length = max(10, kernel_span // kernel_divisor)
    ksize = (length, 1) if axis == 1 else (1, length)
    kernel = cv2.getStructuringElement(cv2.MORPH_RECT, ksize)
    lines = cv2.erode(binary, kernel, iterations=1)
    lines = cv2.dilate(lines, kernel, iterations=1)

    projection = lines.sum(axis=axis) / 255.0
    nonzero = projection[projection > 0]
    if nonzero.size == 0:
        return []
    # A high percentile of the *non-zero* projection values, rather than the
    # raw maximum, is the reference "full-strength rule" level. A single
    # dominant artefact (a crisp border, binding crease, or shadow band that
    # survives the erosion more cleanly than faded or partially-obscured
    # printed rules) is one outlier among many genuine rule detections; the
    # 90th percentile is set by the bulk of ordinary rules and is not pulled
    # up by a small number of outliers the way the raw maximum is.
    peak_floor = float(np.percentile(nonzero, PEAK_REFERENCE_PERCENTILE)) * PEAK_FLOOR_FRACTION

    # Collapse each run of above-threshold indices to its centre, so a rule
    # several pixels thick yields one position.
    positions: list[int] = []
    run: list[int] = []
    for i, value in enumerate(projection):
        if value >= peak_floor:
            run.append(i)
        elif run:
            positions.append(int(np.mean(run)))
            run = []
    if run:
        positions.append(int(np.mean(run)))

    # Merge positions closer together than a plausible cell, measured along
    # the same axis the positions live on.
    min_gap = max(6, merge_span // gap_divisor)
    merged: list[int] = []
    for p in positions:
        if merged and p - merged[-1] < min_gap:
            merged[-1] = (merged[-1] + p) // 2
        else:
            merged.append(p)
    return merged


# --- Row-axis piecewise detection ---
#
# rectify.py removes each page's overall shear, but a bound book's pages are
# not flat: the printed rules *bow* slightly across the page (strongest near
# the spine), an artefact a single per-page affine cannot remove. A row
# rule's erosion kernel run at full page width loses contiguity along that
# bow — measured on the real sample: only a handful of rules survive
# thresholding at all at full width, because the kernel requires the rule to
# stay in the same row of pixels across its whole span, and a bowed rule
# does not. Splitting the page into narrow vertical strips and detecting
# within each strip independently, with a kernel sized to the *strip*
# width rather than the page width, keeps each kernel's span short enough
# that a bowed rule is locally near-straight within it — this is the change
# that lets a bowed line survive detection at all.
#
# These are named constants, not magic numbers, because they were tuned by
# measurement against the real sample and a reviewer may need to re-tune
# them against other samples.
ROW_STRIP_COUNT = 10
ROW_STRIP_KERNEL_DIVISOR = 4
ROW_STRIP_CLUSTER_TOLERANCE = 20
ROW_STRIP_MIN_SPAN_FRACTION = 0.5
ROW_FIT_TOLERANCE_FRACTION = 0.3

# When a declared row count is laid down (see _lay_declared_rows), the fitted
# pitch is trusted only if the detected run is strong enough to anchor an
# extrapolation across faded rows: at least ROW_ANCHOR_MIN_RUN on-curve rows,
# spanning at least ROW_ANCHOR_MIN_SPAN_FRACTION of the declared count so the
# pitch has a long enough lever arm. Below that the anchor is guesswork, so the
# detector falls back and the spread gate refuses rather than invent rows.
ROW_ANCHOR_MIN_RUN = 5
ROW_ANCHOR_MIN_SPAN_FRACTION = 0.5

# How far right of the table's left border a strong row cluster may begin and
# still count as a genuine, full-width row rule, as a fraction of the table
# width. This is the property that tells a genuine row boundary from an interior
# sub-divider that the strip-span filter cannot: a printed row rule runs the
# whole width of the table and so meets its left border, while a sub-divider
# ruled across only the register's wide right-hand columns (the father/mother
# name-line inside "parents"/"sponsors") begins partway across. Measured on the
# real samples, genuine rules begin within ~1% of the table width of the border
# while such sub-dividers begin 12-40% in, so a threshold in between rejects the
# sub-dividers without discarding any genuine rule. Left too loose it would keep
# a sub-divider — which sits at half the row pitch and doubles the row count
# (see IMG_3121: 43 rows found where 24 exist); left too tight it could drop a
# genuine rule whose left end faded, but that is safe because the pitch fit only
# needs enough self-consistent rules and extends the curve across the gaps.
ROW_RULE_LEFT_MARGIN_FRACTION = 0.06


def _row_strip_segments(
    binary: np.ndarray,
    n_strips: int = ROW_STRIP_COUNT,
    kernel_divisor: int = ROW_STRIP_KERNEL_DIVISOR,
) -> list[tuple[int, int, int, int]]:
    """Detect short row-rule segments independently within vertical strips.

    Returns ``(y, strip_index, x_lo, x_hi)`` points — one per short rule
    segment found within some strip, with the horizontal extent of the rule
    ink that produced it. The extent is what later bounds the table
    horizontally: a printed row rule stops at the table's outer border, so
    where the row rules run *is* where the table is, measured from the
    register itself rather than from page colour or brightness (which vary
    with the room the photograph was taken in).

    A genuine, full-width row rule typically contributes
    a point from most strips it survives in; a sub-divider ruled *inside*
    one wide column (this register's multi-line "sponsors" and "parents"
    columns each have an internal line for a second name) can only ever
    contribute points from the strips that overlap that one column, however
    strong its own local signal is — this is what later lets a genuine
    boundary be told apart from a column-confined one.
    """
    _, w = binary.shape
    points: list[tuple[int, int, int, int]] = []
    for i in range(n_strips):
        x0 = i * w // n_strips
        x1 = (i + 1) * w // n_strips if i < n_strips - 1 else w
        strip = binary[:, x0:x1]
        length = max(10, (x1 - x0) // kernel_divisor)
        kernel = cv2.getStructuringElement(cv2.MORPH_RECT, (length, 1))
        lines = cv2.erode(strip, kernel, iterations=1)
        lines = cv2.dilate(lines, kernel, iterations=1)

        projection = lines.sum(axis=1) / 255.0
        nonzero = projection[projection > 0]
        if nonzero.size == 0:
            continue
        # Same standard as the full-width pass in _line_positions, and named
        # rather than repeated as a literal so the two cannot drift apart:
        # a rule is a rule whether it is measured across the page or across
        # one strip of it.
        floor = float(np.percentile(nonzero, PEAK_REFERENCE_PERCENTILE)) * PEAK_FLOOR_FRACTION

        def _record(run: list[int]) -> None:
            band = lines[run[0]:run[-1] + 1] > 0
            columns = np.nonzero(band.any(axis=0))[0]
            if columns.size:
                points.append((int(np.mean(run)), i,
                               x0 + int(columns.min()), x0 + int(columns.max())))

        run: list[int] = []
        for y, value in enumerate(projection):
            if value >= floor:
                run.append(y)
            elif run:
                _record(run)
                run = []
        if run:
            _record(run)
    return points


def _cluster_row_segments(
    points: list[tuple[int, int, int, int]],
    tolerance: int = ROW_STRIP_CLUSTER_TOLERANCE,
) -> list[tuple[int, int, int, int]]:
    """Group per-strip segments into row candidates, keeping each one's
    *strip span* — the range of strip indices that contributed to it.

    Strip span, not raw point count, is what separates a genuine full-width
    row rule (built from strips spread across the page) from a
    column-confined sub-divider (built only from the few adjacent strips
    overlapping that one column): a strong, faded-but-real rule and a
    crisp sub-divider can produce similar point *counts*, but the
    sub-divider can never span strips on both sides of columns it doesn't
    reach.

    Returns ``(y_centroid, strip_span, x_lo, x_hi)`` tuples, sorted by y,
    where the x range is the union of the contributing segments' extents —
    how far across the page this one physical rule was seen to run.
    """
    if not points:
        return []
    ordered = sorted(points)
    clusters: list[list[tuple[int, int, int, int]]] = [[ordered[0]]]
    for point in ordered[1:]:
        if point[0] - clusters[-1][-1][0] <= tolerance:
            clusters[-1].append(point)
        else:
            clusters.append([point])
    result = []
    for cluster in clusters:
        ys = [p[0] for p in cluster]
        strips = [p[1] for p in cluster]
        span = max(strips) - min(strips) + 1
        result.append((int(np.mean(ys)), span,
                       min(p[2] for p in cluster), max(p[3] for p in cluster)))
    return result


def _classify_on_curve(
    candidate_ys: list[int], a: float, b: float, c: float, tolerance_frac: float
) -> tuple[list[int], list[int]]:
    """Split candidates into (row index, y) pairs that agree with the
    quadratic curve ``a + b*k + c*k**2`` within tolerance, discarding the
    rest. ``k`` is recovered from ``y`` with a couple of Newton steps
    (exact for the quadratic; c is small enough in practice that two steps
    converge comfortably) rather than a closed-form root, to keep this
    symmetric with the fitting code below.
    """
    ks: list[int] = []
    ps: list[int] = []
    for y in candidate_ys:
        k = (y - a) / b if b else 0.0
        for _ in range(3):
            f = a + b * k + c * k * k - y
            fp = b + 2 * c * k
            if fp == 0:
                break
            k -= f / fp
        k_round = round(k)
        local_pitch = b + 2 * c * k_round
        if local_pitch <= 0:
            continue
        predicted = a + b * k_round + c * k_round * k_round
        if abs(predicted - y) < tolerance_frac * local_pitch:
            ks.append(k_round)
            ps.append(y)
    return ks, ps


def _fit_row_curve(
    candidate_ys: list[int],
    tolerance_frac: float = ROW_FIT_TOLERANCE_FRACTION,
    iterations: int = 6,
) -> tuple[float, float, float, list[int]] | None:
    """Fit position as a quadratic function of row index, ``a + b*k +
    c*k**2``, to whichever candidates agree with each other, iterating to
    convergence.

    A single *constant* pitch (the straight-line model used before this
    function) turned out to be the wrong shape for this document: measured
    on the real sample, the local spacing between confidently-detected row
    candidates grows smoothly from top to bottom of a page (roughly
    70px near the header to 90px near the bottom on one page) — consistent
    with residual perspective/curvature that a single per-page shear
    correction (rectify.py) cannot remove, since that correction is a
    single global affine and curvature is not affine. A quadratic captures
    a smoothly accelerating (or decelerating) pitch with one extra
    parameter; fit directly, every candidate here landed on-curve on the
    real sample, where the linear model had to discard several.

    ``a``, ``b`` and ``c`` are entirely derived from ``candidate_ys`` —
    never fixed constants. As with the linear model this replaced, a
    single-pass residual check drifts out of tolerance over a long enough
    run for a small per-row error to compound, so this reclassifies against
    each round's *own* refit rather than a fixed initial guess.

    Returns None when there isn't enough self-consistent evidence to fit
    reliably.
    """
    if len(candidate_ys) < 4:
        return None
    gaps = [candidate_ys[i + 1] - candidate_ys[i] for i in range(len(candidate_ys) - 1)]
    median_gap = float(np.median(gaps))
    if median_gap <= 0:
        return None
    plausible = [g for g in gaps if 0.5 * median_gap < g < 1.5 * median_gap]
    b = float(np.median(plausible)) if plausible else median_gap
    a = float(candidate_ys[0])
    c = 0.0

    ks: list[int] = []
    for _ in range(iterations + 1):
        ks, ps = _classify_on_curve(candidate_ys, a, b, c, tolerance_frac)
        if len(ks) < 4:
            return None
        ks_arr = np.array(ks, dtype=np.float64)
        ps_arr = np.array(ps, dtype=np.float64)
        design = np.vstack([ks_arr**2, ks_arr, np.ones_like(ks_arr)]).T
        c, b, a = np.linalg.lstsq(design, ps_arr, rcond=None)[0]
        if b <= 0:
            return None

    return a, b, c, ks


def _extend_row_curve(
    a: float,
    b: float,
    c: float,
    k_start: int,
    all_row_ys: list[int],
    tolerance_frac: float = ROW_FIT_TOLERANCE_FRACTION,
    max_steps: int = 60,
) -> int:
    """Walk the fitted curve forward one row-step at a time past
    ``k_start``, accepting each further step only when it is independently
    corroborated by *some* detected row-rule cluster — of any strip span,
    not just the confidently-"strong" ones the curve was fit from — within
    tolerance of the curve's own prediction. Stops at the first
    unsupported step.

    This is how each page's own table extent is determined, in place of
    extrapolating the curve indefinitely or trusting an externally-derived
    pixel range: measured on the real sample, the printed column rules'
    own vertical extent runs a few hundred pixels past the true last row on
    the page that has trailing text below the ruled table (a
    certification/signature block, in this register) — extending row
    detection to match the column extent would walk straight into that
    unrelated content. Requiring row evidence at every step, rather than
    trusting where *unrelated* ink stops, avoids that.
    """
    all_ys = np.array(sorted(set(all_row_ys)), dtype=np.float64)
    k = k_start
    for _ in range(max_steps):
        k_next = k + 1
        local_pitch = b + 2 * c * k_next
        if local_pitch <= 0:
            break
        predicted = a + b * k_next + c * k_next * k_next
        if all_ys.size == 0 or not np.any(np.abs(all_ys - predicted) <= tolerance_frac * local_pitch):
            break
        k = k_next
    return k


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


def _full_width_row_ys(
    strong: list[tuple[int, int, int, int]],
    margin_fraction: float = ROW_RULE_LEFT_MARGIN_FRACTION,
) -> list[int]:
    """From the strip-span-strong row clusters, keep only those that reach the
    table's left border, returning their y-positions in input order.

    A genuine row rule spans the whole table and so meets its left border; an
    interior sub-divider ruled across only the register's wide right-hand
    columns begins partway across. Strip span alone cannot separate them — a
    sub-divider spanning several wide columns survives the span filter — but the
    left extent can: it is the one property a full-width rule has that an
    interior one does not.

    The border is estimated as the 25th percentile of the clusters' left
    extents, which stays inside the genuine population even when nearly as many
    sub-dividers are present (they all sit to its right). Clusters beginning
    more than ``margin_fraction`` of the table width to the right of that border
    are dropped. Passed through unchanged when there are too few clusters to
    estimate a border from.
    """
    if len(strong) < 5:
        return [c[0] for c in strong]
    x_los = np.array([c[2] for c in strong], dtype=np.float64)
    x_his = np.array([c[3] for c in strong], dtype=np.float64)
    border = float(np.percentile(x_los, 25))
    table_width = float(np.percentile(x_his, 75)) - border
    if table_width <= 0:
        return [c[0] for c in strong]
    margin = max(float(ROW_STRIP_CLUSTER_TOLERANCE), margin_fraction * table_width)
    return [c[0] for c in strong if c[2] <= border + margin]


def _detect_row_boundaries(
    binary: np.ndarray,
    w: int,
    h: int,
    clustered: list[tuple[int, int, int, int]] | None = None,
    data_row_count: int | None = None,
) -> list[int]:
    """The full set of row-boundary y-positions: header band top, then the
    fitted grid of data-row boundaries, extended to cover this page's own
    detected table extent.

    The header band's top edge comes from a single full-page-width pass
    (the same detector used before the strip refactor): it is one reliable
    landmark near the top of the page, found even where rows lower down bow
    out of a full-width kernel's reach. It is deliberately kept separate
    from the data-row curve fit below — the header band is legitimately a
    different height from a data row, so folding it into the fit would bias
    the estimated pitch.

    Falls back to the (possibly fragmented, but never fabricated) full-width
    candidates whenever there isn't enough strip evidence to fit a curve —
    never invents row structure out of noise.
    """
    header_candidates = _line_positions(
        binary, axis=1, kernel_span=w, merge_span=h, gap_divisor=50
    )
    if not header_candidates:
        return []
    header_top = header_candidates[0]

    if clustered is None:
        clustered = _cluster_row_segments(_row_strip_segments(binary))
    min_span = max(2, round(ROW_STRIP_COUNT * ROW_STRIP_MIN_SPAN_FRACTION))
    strong = _full_width_row_ys([c for c in clustered if c[1] >= min_span])
    if len(strong) < 5:
        return header_candidates

    # The candidate closest to the header is excluded from the fit: it is
    # not a data-row boundary, and it would bias the pitch estimate toward
    # the header's own (legitimately different) height.
    fit = _fit_row_curve(strong[1:])
    if fit is None:
        return header_candidates
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


def _table_x_bounds(
    clustered: list[tuple[int, int, int, int]], min_span: int
) -> tuple[float, float] | None:
    """How far the table runs horizontally, from where its row rules run.

    A printed row rule stops at the table's outer border, so the rules
    themselves say where the table is — no appeal to page colour or
    brightness, which depend on the room the photograph was taken in rather
    than on the register.

    Both ends are quartiles rather than the extreme observed values: a rule
    that happens to merge with a horizontal feature *outside* the table (a
    shadow line, a floor edge, the page's own edge) reports an extent far
    too wide, and one or two such rules would otherwise stretch the bounds
    over the whole image. Quartiles are set by the bulk of ordinary rules.

    Returns None when too few rules were seen for quartiles to mean anything.
    """
    strong = [c for c in clustered if c[1] >= min_span]
    if len(strong) < 5:
        return None
    los = np.array([c[2] for c in strong], dtype=np.float64)
    his = np.array([c[3] for c in strong], dtype=np.float64)

    lo = float(np.percentile(los, 25))
    hi = float(np.percentile(his, 75))
    if hi <= lo:
        return None

    # Widen by each end's own interquartile spread, so a page whose rules
    # disagree about where the table ends is judged loosely and one whose
    # rules agree closely is judged tightly. The tolerance is the
    # measurement's own uncertainty, not a fixed number of pixels — and it
    # never falls below the distance at which two detections are already
    # treated as the same rule.
    lo_margin = max(float(np.percentile(los, 75) - np.percentile(los, 25)),
                    ROW_STRIP_CLUSTER_TOLERANCE)
    hi_margin = max(float(np.percentile(his, 75) - np.percentile(his, 25)),
                    ROW_STRIP_CLUSTER_TOLERANCE)
    return lo - lo_margin, hi + hi_margin


# --- Column axis: bow-tolerant rule evidence, table extent, template fit -----
#
# The column axis needs its own evidence, separate from _line_positions, for
# the same reason the row axis did: a bound book's pages are curved, so a
# printed vertical rule drifts sideways down the page and loses contiguity
# under a kernel run at the full page height. Measured on the sample
# photographs, a rule can drift tens of pixels between the top and the bottom
# of the table. Splitting the page into short horizontal bands and detecting
# within each keeps every kernel's span short enough that a bowed rule is
# locally near-straight, exactly as ROW_STRIP_COUNT does for rows.
#
# These positions are *evidence*, not the answer. They include the register's
# internal sub-dividers, which cannot be told from logical column boundaries by
# any property of the mark itself (see column_template.py), and they miss
# genuine boundaries that are too faint to survive erosion. They are used to
# corroborate a declared template's fit, never to decide the column count.
COLUMN_BAND_COUNT = 20
COLUMN_BAND_KERNEL_DIVISOR = 4
COLUMN_CLUSTER_TOLERANCE = 15
COLUMN_MIN_SPAN_FRACTION = 0.5

# Fraction of the peak row-rule coverage at which the table is still considered
# to be present, when measuring how far it runs horizontally. Not 1.0: the
# printed rules nearest the spine fade or bow out of detection on a bound
# book, so requiring every rule to reach a given x would report a table
# narrower than the one on the page. Not near 0.0 either: a single rule that
# merges with a shadow or a surface edge beyond the paper would then stretch
# the measurement across the whole image. Swept over all six sample page
# halves, every value from 0.5 to 0.8 gives the same fit to within a few
# pixels, so 0.6 sits in the middle of a wide flat region rather than on a
# tuned point.
TABLE_EXTENT_COVERAGE_FRACTION = 0.6

# How far the template fit may move each end of the table away from the
# coverage-measured extent, as a fraction of that extent's own width. The
# measurement is honest but not exact — most of all at the spine, where the
# rules fade before reaching the border — so the fit is allowed to correct it,
# within a bound that keeps the search near the measured table rather than
# letting it wander the page.
TEMPLATE_FIT_BRACKET = 0.25

# ...and how far the fitted width may depart from the measured one, for the
# same reason and with the same intent.
TEMPLATE_MIN_WIDTH_RATIO = 0.85
TEMPLATE_MAX_WIDTH_RATIO = 1.30

# Number of candidate positions tried for each end of the table.
TEMPLATE_FIT_STEPS = 90

# How near a detected vertical rule a fitted boundary must land to count as
# corroborated, as a fraction of the fitted table width. It is not a precision
# target: because the rules bow, a single straight boundary is a compromise
# over the table's height and genuinely sits tens of pixels from the printed
# rule at the top and bottom. Measured on the sample photographs, this value
# is large enough that correct fits score 0.67-1.00 and small enough that
# deliberately wrong ones (the same template shifted by a twentieth of the
# table width, rescaled by 15%, or the facing page's template applied instead)
# score 0.00-0.50.
TEMPLATE_CORROBORATION_TOLERANCE = 0.025

# The floor a fit must clear to be trusted, set between those two measured
# ranges. A fit below it is a fit to the wrong extent: the declared
# proportions are not landing on the register's own rules, so the columns
# would be named confidently and cut in the wrong places.
TEMPLATE_CORROBORATION_FLOOR = 0.60

# How near the gutter the spine-side outer boundary must land to count as
# corroborated by it, as a fraction of the fitted table width. Larger than
# TEMPLATE_CORROBORATION_TOLERANCE because the gutter is not a rule the boundary
# sits ON but a border it sits NEAR -- the page's inner white margin lies
# between the last printed rule and the spine. Measured across the sample
# spreads, that margin runs 2-6% of the table width; 0.05 covers the genuine
# margin while still rejecting a spine boundary placed well off the gutter.
GUTTER_CORROBORATION_TOLERANCE = 0.05


@dataclass(frozen=True)
class ColumnFit:
    """A declared template fitted to one page's measured table extent."""

    template: ColumnTemplate
    x_lo: float
    x_hi: float
    boundaries: list[int]
    corroboration: float
    rule_count: int

    @property
    def width(self) -> float:
        return self.x_hi - self.x_lo


def _column_band_segments(
    binary: np.ndarray,
    n_bands: int = COLUMN_BAND_COUNT,
    kernel_divisor: int = COLUMN_BAND_KERNEL_DIVISOR,
) -> list[tuple[int, int]]:
    """Detect short vertical-rule segments independently within horizontal
    bands. Returns ``(x, band_index)`` points."""
    h, _ = binary.shape
    points: list[tuple[int, int]] = []
    for i in range(n_bands):
        y0 = i * h // n_bands
        y1 = (i + 1) * h // n_bands if i < n_bands - 1 else h
        band = binary[y0:y1]
        length = max(10, (y1 - y0) // kernel_divisor)
        kernel = cv2.getStructuringElement(cv2.MORPH_RECT, (1, length))
        lines = cv2.dilate(cv2.erode(band, kernel), kernel)

        projection = lines.sum(axis=0) / 255.0
        nonzero = projection[projection > 0]
        if nonzero.size == 0:
            continue
        # The same "is this a rule" standard both other passes use.
        floor = float(np.percentile(nonzero, PEAK_REFERENCE_PERCENTILE)) * PEAK_FLOOR_FRACTION

        run: list[int] = []
        for x, value in enumerate(projection):
            if value >= floor:
                run.append(x)
            elif run:
                points.append((int(np.mean(run)), i))
                run = []
        if run:
            points.append((int(np.mean(run)), i))
    return points


def detect_column_rule_positions(
    page_bgr: np.ndarray,
    min_band_span_fraction: float = COLUMN_MIN_SPAN_FRACTION,
) -> list[int]:
    """The x-positions of vertical rules that run down most of the page.

    Public so a caller — in particular a test — can check a fitted template
    against the same independent evidence the fit was scored on. Clusters seen
    in too few bands are dropped: a rule that appears in only a couple of
    horizontal bands is a stroke of handwriting or a smudge, not a ruling that
    runs the height of the table.
    """
    return _cluster_column_segments(
        _column_band_segments(_binary(page_bgr)), min_band_span_fraction
    )


def _cluster_column_segments(
    points: list[tuple[int, int]],
    min_band_span_fraction: float = COLUMN_MIN_SPAN_FRACTION,
    tolerance: int = COLUMN_CLUSTER_TOLERANCE,
    n_bands: int = COLUMN_BAND_COUNT,
) -> list[int]:
    if not points:
        return []
    ordered = sorted(points)
    clusters: list[list[tuple[int, int]]] = [[ordered[0]]]
    for point in ordered[1:]:
        if point[0] - clusters[-1][-1][0] <= tolerance:
            clusters[-1].append(point)
        else:
            clusters.append([point])

    min_span = max(2, round(n_bands * min_band_span_fraction))
    result: list[int] = []
    for cluster in clusters:
        bands = [p[1] for p in cluster]
        if max(bands) - min(bands) + 1 >= min_span:
            result.append(int(np.mean([p[0] for p in cluster])))
    return result


def _table_x_extent(
    clustered_rows: list[tuple[int, int, int, int]],
    width: int,
    min_span: int,
    coverage_fraction: float = TABLE_EXTENT_COVERAGE_FRACTION,
) -> tuple[int, int] | None:
    """How far the table runs horizontally, from where its row rules run.

    A printed row rule spans exactly the table's width and stops at its outer
    border, so counting how many rules cover each x gives a plateau whose
    edges are the table's edges — measured from the register itself, with no
    appeal to page colour or brightness (which describe the room the
    photograph was taken in, not the book).

    Counting *coverage* rather than looking at where individual rules start
    and end is what makes this robust: a rule that merges with something
    outside the table reports an extent far too wide, and a rule that fades
    near the spine reports one too narrow, but neither moves a plateau that
    two dozen other rules agree on.

    Returns None when too few rules were seen for a plateau to mean anything.
    """
    strong = [c for c in clustered_rows if c[1] >= min_span]
    if len(strong) < 5:
        return None
    coverage = np.zeros(width, dtype=np.int32)
    for _, _, lo, hi in strong:
        coverage[max(0, lo):min(width, hi + 1)] += 1
    peak = int(coverage.max())
    if peak <= 0:
        return None
    inside = np.nonzero(coverage >= peak * coverage_fraction)[0]
    if inside.size < 2:
        return None
    return int(inside.min()), int(inside.max())


def fit_column_template(
    template: ColumnTemplate,
    rule_xs: list[int],
    extent: tuple[int, int],
    page_width: int,
    gutter_x: float | None = None,
    gutter_side: str | None = None,
) -> ColumnFit | None:
    """Place a declared column ruling onto this page by scale and offset.

    The template supplies the proportions; the page supplies where the table
    is and how wide. ``extent`` is the coverage-measured table extent, used as
    the starting point and to bracket the search — the fit is free to correct
    it within TEMPLATE_FIT_BRACKET, because the measurement fades where the
    rules do, but not free to place the table somewhere else entirely.

    Among candidate placements the one chosen is the one whose boundaries sit
    closest to the page's own detected vertical rules, scored so that a
    boundary contributes in proportion to how near a rule it lands rather than
    passing or failing a threshold. A hard threshold made the choice turn on
    single pixels and let a placement that happened to clip four rules beat
    one that sat squarely on five; the graded score does not.

    Returns None when the extent is unusable. The returned fit always carries
    its own corroboration, so a caller can refuse a placement that the page
    does not support — this function does not decide that, because how much
    corroboration is enough is a policy question and belongs at the gate.
    """
    lo0, hi0 = float(extent[0]), float(extent[1])
    measured_width = hi0 - lo0
    if measured_width <= 0 or page_width <= 1:
        return None

    fractions = np.asarray(template.boundaries, dtype=np.float64)
    rules = np.asarray(sorted(rule_xs), dtype=np.float64)

    margin = TEMPLATE_FIT_BRACKET * measured_width
    los = np.linspace(max(0.0, lo0 - margin), min(page_width - 1.0, lo0 + margin),
                      TEMPLATE_FIT_STEPS)
    his = np.linspace(max(0.0, hi0 - margin), min(page_width - 1.0, hi0 + margin),
                      TEMPLATE_FIT_STEPS)

    widths = his[None, :] - los[:, None]
    allowed = (
        (widths >= TEMPLATE_MIN_WIDTH_RATIO * measured_width)
        & (widths <= TEMPLATE_MAX_WIDTH_RATIO * measured_width)
    )
    if not allowed.any():
        return None

    # boundaries[i, j, b] = los[i] + widths[i, j] * fractions[b]
    boundaries = los[:, None, None] + widths[:, :, None] * fractions[None, None, :]
    tol = TEMPLATE_CORROBORATION_TOLERANCE * widths          # [i, j] rule tolerance

    # Graded credit per boundary: 1.0 dead-on a detected rule, tapering to 0 at
    # the tolerance -- the same scoring the fit has always used.
    if rules.size:
        rule_dist = np.abs(boundaries[..., None] - rules).min(axis=-1)   # [i, j, b]
        credit = np.maximum(0.0, 1.0 - rule_dist / tol[:, :, None])
        matched = rule_dist <= tol[:, :, None]
    else:
        credit = np.zeros(boundaries.shape)
        matched = np.zeros(boundaries.shape, dtype=bool)

    # The spine-side outer boundary is also credited for sitting on the gutter --
    # the book's spine, a known table border -- so a rule that faded there does
    # not sink the fit. Its own, looser tolerance covers the page's inner margin
    # between the last rule and the spine. Only this one boundary is affected.
    if gutter_x is not None and gutter_side in ("left", "right"):
        sb = 0 if gutter_side == "left" else boundaries.shape[-1] - 1
        gtol = GUTTER_CORROBORATION_TOLERANCE * widths                  # [i, j]
        gdist = np.abs(boundaries[..., sb] - float(gutter_x))           # [i, j]
        gcredit = np.maximum(0.0, 1.0 - gdist / gtol)
        credit[..., sb] = np.maximum(credit[..., sb], gcredit)
        matched[..., sb] = matched[..., sb] | (gdist <= gtol)

    score = np.where(allowed, credit.sum(axis=-1), -1.0)
    i, j = np.unravel_index(int(np.argmax(score)), score.shape)

    x_lo, x_hi = float(los[i]), float(los[i] + widths[i, j])
    fitted = boundaries[i, j]
    corroborated = int(matched[i, j].sum())

    return ColumnFit(
        template=template,
        x_lo=x_lo,
        x_hi=x_hi,
        boundaries=[int(round(x)) for x in fitted],
        corroboration=corroborated / len(fitted),
        rule_count=int(rules.size),
    )


def row_boundaries(grid: GridResult) -> list[int]:
    """The distinct row-boundary y-positions of a grid, top to bottom.

    One more than ``grid.rows``: every row's top edge, plus the bottom edge of
    the last row.
    """
    tops = sorted({c.y for c in grid.cells})
    if not tops:
        return []
    return tops + [max(c.y + c.h for c in grid.cells)]


def median_data_row_pitch(grid: GridResult) -> float:
    """Median spacing between consecutive *data*-row boundaries.

    The first gap is dropped: it spans the column-header band, which is
    legitimately taller than a data row and would drag the median toward a
    spacing no data row actually has.
    """
    boundaries = row_boundaries(grid)
    gaps = [boundaries[i + 1] - boundaries[i] for i in range(len(boundaries) - 1)]
    if len(gaps) < 2:
        return float(gaps[0]) if gaps else 0.0
    return float(np.median(gaps[1:]))


def detect_row_rule_segments(
    page_bgr: np.ndarray, min_strip_span_fraction: float = 0.0
) -> list[int]:
    """The raw, per-strip detected row-rule y-positions, pooled and
    clustered by proximity — independent of the pitch model in
    ``_detect_row_boundaries``.

    Exposed so a caller (in particular, a test) can check that a final row
    grid actually tracks the physical page: a boundary produced purely by
    even spacing, with no relationship to the document, will not land near
    any of these; a boundary recovered from the document usually will. Some
    genuine boundaries are legitimately absent from this list — a rule too
    faint or bowed to survive even strip-local detection is exactly why the
    pitch model exists — so a grid is not expected to match all of them,
    only most.

    ``min_strip_span_fraction`` optionally drops clusters seen across too
    few of the page's vertical strips. The default of 0.0 keeps every
    cluster, which is what an anchoring check wants: it is asking whether a
    boundary corresponds to *any* detected ink, and a rule that survived in
    only a few strips is still evidence of a rule. A caller reasoning about
    the table's overall shape wants the opposite — pass the same fraction
    the row-grid fit uses (ROW_STRIP_MIN_SPAN_FRACTION) to keep only
    clusters wide enough to be full-width rules rather than sub-dividers
    ruled inside one wide column.
    """
    clustered = _cluster_row_segments(_row_strip_segments(_binary(page_bgr)))
    if min_strip_span_fraction <= 0.0:
        return [y for y, _, _, _ in clustered]
    min_span = max(2, round(ROW_STRIP_COUNT * min_strip_span_fraction))
    return [y for y, span, _, _ in clustered if span >= min_span]


def detect_grid(
    page_bgr: np.ndarray,
    column_template: ColumnTemplate | None = None,
    data_row_count: int | None = None,
    gutter_x: float | None = None,
    gutter_side: str | None = None,
) -> GridResult:
    """Recover the table from its printed rules.

    Row and column identity come from page geometry, never from recognized
    text — so an unreadable row number or a misread name cannot shift a row
    or move a value into the wrong column.

    ``column_template`` declares the register's column ruling in proportions
    of the table's own width (see column_template.py). When given, the columns
    are that ruling, fitted to the table extent this page's row rules
    themselves report; when omitted, the columns are detected from the
    vertical rules alone. The template path exists because a register that
    sub-divides its own columns cannot be read by counting rules; the
    detection path stays for pages with no declared layout, and neither is a
    fallback for the other — the caller chooses.
    """
    h, w = page_bgr.shape[:2]
    binary = _binary(page_bgr)
    clustered_rows = _cluster_row_segments(_row_strip_segments(binary))
    min_row_span = max(2, round(ROW_STRIP_COUNT * ROW_STRIP_MIN_SPAN_FRACTION))

    # Rows: see _detect_row_boundaries — a page-bow-tolerant, piecewise
    # detector that fits an evenly-spaced grid to whichever row candidates
    # agree with each other, rather than trusting a single full-width pass.
    ys = _detect_row_boundaries(binary, w, h, clustered_rows, data_row_count=data_row_count)

    fit: ColumnFit | None = None
    if column_template is None:
        xs = _detect_column_boundaries(binary, w, h, clustered_rows, min_row_span)
    else:
        fit = _fit_columns(binary, w, clustered_rows, min_row_span, column_template,
                           gutter_x=gutter_x, gutter_side=gutter_side)
        xs = list(fit.boundaries) if fit is not None else []

    if len(xs) < MIN_COLS + 1 or len(ys) < 2:
        raise OcrError(
            "no_table_detected",
            "Couldn't find the register's ruled grid in this image.",
        )
    if len(ys) < MIN_ROWS + 1:
        raise OcrError("no_rows_detected", "Found a grid but no readable rows.")

    cells = [
        CellRect(
            row=r, col=c,
            x=xs[c], y=ys[r],
            w=xs[c + 1] - xs[c], h=ys[r + 1] - ys[r],
        )
        for r in range(len(ys) - 1)
        for c in range(len(xs) - 1)
    ]
    return GridResult(
        rows=len(ys) - 1,
        cols=len(xs) - 1,
        cells=cells,
        column_keys=None if fit is None else tuple(fit.template.columns),
        table_x_lo=None if fit is None else int(round(fit.x_lo)),
        table_x_hi=None if fit is None else int(round(fit.x_hi)),
        column_corroboration=None if fit is None else fit.corroboration,
    )


def _detect_column_boundaries(
    binary: np.ndarray,
    w: int,
    h: int,
    clustered_rows: list[tuple[int, int, int, int]],
    min_row_span: int,
) -> list[int]:
    """Columns from the vertical rules alone, for a page with no declared
    layout.

    Kernel scales with height; merge distance scales with width. Wider
    kernel/gap divisors than the row axis — see _line_positions' docstring for
    why the column axis needs its own tolerance on a real, bound-book
    photograph.
    """
    xs = _line_positions(
        binary, axis=0, kernel_span=h, merge_span=w,
        kernel_divisor=40, gap_divisor=21,
    )

    # Drop column candidates that fall outside the table altogether. A
    # photographed register is surrounded by whatever it was resting on, and
    # the surroundings supply long straight edges — the page's own edge, a
    # binding shadow, a wall or floor line — which survive a vertical erosion
    # exactly as a printed column rule does. Measured on the real samples,
    # this let two positions lying entirely off the paper become "columns" on
    # one page, shifting every column index on it: a value would then be read
    # under a neighbouring heading, which no downstream check could notice.
    # The table's own row rules say where the table is, so they are what
    # bounds the search.
    bounds = _table_x_bounds(clustered_rows, min_span=min_row_span)
    if bounds is not None:
        x_lo, x_hi = bounds
        xs = [x for x in xs if x_lo <= x <= x_hi]
    return xs


def _fit_columns(
    binary: np.ndarray,
    w: int,
    clustered_rows: list[tuple[int, int, int, int]],
    min_row_span: int,
    template: ColumnTemplate,
    gutter_x: float | None = None,
    gutter_side: str | None = None,
) -> ColumnFit | None:
    extent = _table_x_extent(clustered_rows, w, min_row_span)
    if extent is None:
        return None
    rules = _cluster_column_segments(_column_band_segments(binary))
    return fit_column_template(template, rules, extent, w, gutter_x, gutter_side)


@dataclass(frozen=True)
class SpreadGrids:
    """Two page grids that have been checked against each other.

    Only ever constructed by ``detect_spread_grids``, and only when the two
    pages agree, so holding one of these is itself the evidence that the
    left/right row-position join is safe to perform. ``rows`` and ``cols`` are
    the agreed counts — the same on both pages by construction.
    """
    left: GridResult
    right: GridResult
    rows: int
    cols: int
    left_pitch: float
    right_pitch: float
    # None unless a spread template was fitted; see detect_grid.
    left_corroboration: float | None = None
    right_corroboration: float | None = None


def _refuse(detail: str) -> NoReturn:
    """Raise the error the Flutter workflow already handles.

    The message is written for a parish staff member holding the camera, not
    for a developer: it says what looked wrong about the *photograph* and what
    to do next. It carries only structural counts — never recognized text, a
    name, a date, or a file path.
    """
    raise OcrError(
        "no_table_detected",
        "Couldn't read this register spread reliably. " + detail + " "
        "Please retake the photo with the book opened flat, both pages fully "
        "in frame, and even lighting, then tap Retry OCR — or tap Continue "
        "Manually to type this spread in.",
    )


def _check_template_fit(
    side: str, grid: GridResult, template: ColumnTemplate, page_width: int
) -> None:
    """Refuse a page whose declared ruling did not actually land on it.

    Fitting a template always produces boundaries — that is what fitting
    means — so the count alone proves nothing, and a fit to the wrong extent
    would name every column confidently while cutting all of them in the
    wrong places. These are the checks that make the fit answerable to the
    page:

    * the fitted table must have the number of columns the template declares,
      which catches a template and a fit that have drifted out of step;
    * the fitted extent must lie within the page and have real width, since
      an extent running off the crop means the table was not located;
    * enough of the fitted boundaries must land on a vertical rule the page
      itself supplied. This is the load-bearing one. It is the only check
      that can tell a correctly placed ruling from a plausible-looking
      misplacement, because it is the only one that asks the register rather
      than the declaration.
    """
    if grid.cols != template.column_count:
        _refuse(
            f"The {side} page came out with {grid.cols} columns where this "
            f"register has {template.column_count}."
        )
    if grid.table_x_lo is None or grid.table_x_hi is None:
        _refuse(f"The edges of the ruled table could not be found on the {side} page.")
    if not (0 <= grid.table_x_lo < grid.table_x_hi <= page_width):
        _refuse(
            f"The ruled table on the {side} page was traced past the edge of "
            f"the photograph, so part of it is out of frame."
        )
    corroboration = grid.column_corroboration or 0.0
    if corroboration < TEMPLATE_CORROBORATION_FLOOR:
        _refuse(
            f"Only {corroboration:.0%} of the column edges expected on the "
            f"{side} page could be matched to a printed line in the "
            f"photograph, so entries could be filed under the wrong heading."
        )


def detect_spread_grids(
    left_page_bgr: np.ndarray,
    right_page_bgr: np.ndarray,
    pitch_tolerance: float = SPREAD_PITCH_TOLERANCE,
    spread_template: SpreadColumnTemplate | None = None,
) -> SpreadGrids:
    """Detect both pages of a spread, and refuse unless they agree.

    The two halves of a register spread are one continuous ruled table: the
    same physical rows run across the gutter, so a row's details on the left
    page belong with that same row's details on the right. A later stage joins
    them *by row position*, which is only sound if both pages found the same
    rows. If they did not, the join silently files one child's birth details
    against another child's baptism — a corruption nothing downstream can
    detect, because every value is individually plausible.

    So this refuses rather than guesses. Three things must hold:

    * both pages must report the same number of columns — a disagreement means
      at least one page merged or split a column, so values would land in the
      wrong *field*, not merely the wrong row;
    * both pages must report exactly the same number of rows — not "within
      one", because a single row of drift misfiles every record after it;
    * their median data-row pitches must agree to within ``pitch_tolerance``.
      Equal counts alone can still hide a wrong grid: one page can find the
      right number of boundaries in the wrong places, and two different
      pitches for one physical table is a cheap, independent way to catch it.

    When ``spread_template`` is given, each page's columns come from that
    register's declared ruling rather than from counting vertical rules, and
    three further conditions apply per page — see ``_check_template_fit``.

    The expected column count is deliberately *not* written down here. Without
    a template it is whatever the two pages independently agree on; with one it
    is whatever that template declares. Either way this stays correct for a
    register ruled with a different number of columns; that this particular
    register has five is a property of the template and of the tests, not one
    the detector assumes.

    Raises OcrError("no_table_detected") on any disagreement, and lets
    detect_grid's own OcrError through (annotated with which page failed) when
    a page yields no grid at all.
    """
    templates = {
        "left": None if spread_template is None else spread_template.left,
        "right": None if spread_template is None else spread_template.right,
    }
    row_count = None if spread_template is None else spread_template.data_row_count
    # Each page was cropped at the gutter (the spine), so the gutter is the
    # page's inner edge: the right edge of the left page, the left edge of the
    # right page. It is a known table border used to anchor the spine-side
    # column boundary when that printed rule has faded (see fit_column_template).
    gutters = {
        "left": (left_page_bgr.shape[1] - 1, "right"),
        "right": (0, "left"),
    }
    grids: dict[str, GridResult] = {}
    for side, page in (("left", left_page_bgr), ("right", right_page_bgr)):
        try:
            gx, gside = gutters[side]
            grids[side] = detect_grid(page, templates[side], data_row_count=row_count,
                                      gutter_x=gx, gutter_side=gside)
        except OcrError:
            _refuse(f"The {side} page's ruled grid could not be found at all.")
    left, right = grids["left"], grids["right"]

    for side, page in (("left", left_page_bgr), ("right", right_page_bgr)):
        template = templates[side]
        if template is not None:
            _check_template_fit(side, grids[side], template, page.shape[1])

    if left.cols != right.cols:
        _refuse(
            f"The two pages disagree about how many columns the register has "
            f"({left.cols} on the left page, {right.cols} on the right), so "
            f"entries could be filed under the wrong heading."
        )

    if left.rows != right.rows:
        _refuse(
            f"The two pages disagree about how many rows the register has "
            f"({left.rows} on the left page, {right.rows} on the right), so "
            f"each entry's details could be paired with the wrong person."
        )

    left_pitch = median_data_row_pitch(left)
    right_pitch = median_data_row_pitch(right)
    if left_pitch <= 0 or right_pitch <= 0:
        _refuse("The spacing between rows could not be measured on both pages.")

    ratio = max(left_pitch, right_pitch) / min(left_pitch, right_pitch)
    if ratio - 1.0 > pitch_tolerance:
        _refuse(
            f"The rows are spaced {ratio - 1.0:.0%} further apart on one page "
            f"than the other, although both pages are halves of the same "
            f"ruled table, so at least one page was not read correctly."
        )

    return SpreadGrids(
        left=left,
        right=right,
        rows=left.rows,
        cols=left.cols,
        left_pitch=left_pitch,
        right_pitch=right_pitch,
        left_corroboration=left.column_corroboration,
        right_corroboration=right.column_corroboration,
    )
