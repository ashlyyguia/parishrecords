from dataclasses import dataclass

import cv2
import numpy as np

MAX_ANGLE_DEG = 15.0
MIN_DET = 0.1


@dataclass(frozen=True)
class RectifyResult:
    image: np.ndarray
    h_angle_deg: float
    v_angle_deg: float


def _binary(page_bgr: np.ndarray) -> np.ndarray:
    gray = cv2.cvtColor(page_bgr, cv2.COLOR_BGR2GRAY)
    return cv2.adaptiveThreshold(
        gray, 255, cv2.ADAPTIVE_THRESH_GAUSSIAN_C, cv2.THRESH_BINARY_INV, 25, 12
    )


def _isolate_rules(binary: np.ndarray, axis: int, kernel_span: int) -> np.ndarray:
    """Morphologically isolate long rules along one axis.

    ``axis`` selects the rule orientation to keep: 1 for horizontal rules
    (kernel is wide and 1px tall), 0 for vertical rules (kernel is tall and
    1px wide). ``kernel_span`` is the perpendicular page dimension.

    Unlike table.py's grid detector (which only ever runs on already-rectified,
    near-axis-aligned pages), this runs on pages that may carry up to
    MAX_ANGLE_DEG of shear — the whole point of measuring them. A 1px-thin
    kernel spanning a large fraction of the page loses contiguity with the
    rule as it drifts across that span (drift = kernel_length * tan(angle)),
    so the kernel here is deliberately much shorter than table.py's — long
    enough to separate rules from handwriting strokes, short enough that the
    drift over its own length stays smaller than the rule's stroke width even
    at the maximum tolerated shear angle.
    """
    length = max(10, kernel_span // 100)
    ksize = (length, 1) if axis == 1 else (1, length)
    kernel = cv2.getStructuringElement(cv2.MORPH_RECT, ksize)
    lines = cv2.erode(binary, kernel, iterations=1)
    lines = cv2.dilate(lines, kernel, iterations=1)
    return lines


def _hough_segments(lines_img: np.ndarray, min_line_length: int) -> np.ndarray | None:
    segments = cv2.HoughLinesP(
        lines_img, 1, np.pi / 720, threshold=100,
        minLineLength=max(20, min_line_length), maxLineGap=20,
    )
    return segments[:, 0] if segments is not None else None


def _median_horizontal_angle(lines_img: np.ndarray, tolerance_deg: float = 20.0) -> float | None:
    """Median Hough-segment angle near horizontal (0deg), or None if unmeasurable.

    Segment endpoint order from HoughLinesP is arbitrary (either end can come
    first), so each segment is normalised to point rightward (dx >= 0) before
    its angle is taken — otherwise a reversed segment's angle would be ~180
    degrees off and get dropped by the tolerance filter instead of counted.
    """
    segments = _hough_segments(lines_img, lines_img.shape[1] // 8)
    if segments is None:
        return None
    angles = []
    for x1, y1, x2, y2 in segments:
        dx, dy = int(x2) - int(x1), int(y2) - int(y1)
        if dx < 0:
            dx, dy = -dx, -dy
        angles.append(float(np.degrees(np.arctan2(dy, dx))))
    angles = [a for a in angles if abs(a) <= tolerance_deg]
    return float(np.median(angles)) if angles else None


def _median_vertical_angle(lines_img: np.ndarray, tolerance_deg: float = 20.0) -> float | None:
    """Median Hough-segment angle off vertical (90deg), or None if unmeasurable.

    Reported as signed degrees off true vertical so it composes directly with
    the horizontal angle in the shear transform: positive means the rule
    leans the same way a positive v_deg in shear_image leans it. Segments are
    normalised to point downward (dy >= 0) before measuring, for the same
    reason horizontal segments are normalised to point rightward.
    """
    segments = _hough_segments(lines_img, lines_img.shape[0] // 8)
    if segments is None:
        return None
    off_vertical = []
    for x1, y1, x2, y2 in segments:
        dx, dy = int(x2) - int(x1), int(y2) - int(y1)
        if dy < 0:
            dx, dy = -dx, -dy
        raw = float(np.degrees(np.arctan2(dy, dx)))
        off_vertical.append(90.0 - raw)
    off_vertical = [a for a in off_vertical if abs(a) <= tolerance_deg]
    return float(np.median(off_vertical)) if off_vertical else None


def _measure_or_none(page_bgr: np.ndarray) -> tuple[float | None, float | None]:
    """Like measure_rule_angles, but preserves None for an unmeasurable axis.

    rectify_page needs to distinguish "measured exactly 0.0" from "no lines
    found" (per the guard rail below); the public measure_rule_angles
    collapses both to 0.0 for callers that only want a best-effort angle.
    """
    h, w = page_bgr.shape[:2]
    binary = _binary(page_bgr)

    h_lines = _isolate_rules(binary, axis=1, kernel_span=w)
    v_lines = _isolate_rules(binary, axis=0, kernel_span=h)

    h_angle = _median_horizontal_angle(h_lines)
    v_angle = _median_vertical_angle(v_lines)
    return h_angle, v_angle


def measure_rule_angles(page_bgr: np.ndarray) -> tuple[float, float]:
    """Measure the dominant horizontal-rule and vertical-rule directions.

    Each axis is measured from its own separately-isolated binary so
    handwriting strokes surviving one erosion cannot contaminate the other
    axis's estimate. Returns 0.0 for either angle that cannot be measured
    (no lines found).
    """
    h_angle, v_angle = _measure_or_none(page_bgr)
    return (h_angle if h_angle is not None else 0.0,
            v_angle if v_angle is not None else 0.0)


def rectify_page(page_bgr: np.ndarray) -> RectifyResult:
    """Straighten a page's horizontal and vertical rules onto the true axes.

    Rotation alone cannot fix this: the two axes can disagree with each other
    (shear) independently of the page's overall tilt. This builds the unique
    linear map sending the measured rule directions to the true x/y axes and
    applies it about the page centre.

    Never raises. Degrades to returning the page unchanged (with angles
    reported as 0.0) if either angle cannot be measured, if a measured angle
    exceeds the plausible range, or if the resulting transform is singular.
    """
    h_angle, v_angle = _measure_or_none(page_bgr)

    if h_angle is None or v_angle is None:
        return RectifyResult(image=page_bgr, h_angle_deg=0.0, v_angle_deg=0.0)

    if abs(h_angle) > MAX_ANGLE_DEG or abs(v_angle) > MAX_ANGLE_DEG:
        return RectifyResult(image=page_bgr, h_angle_deg=0.0, v_angle_deg=0.0)

    h_rad = np.radians(h_angle)
    v_rad = np.radians(v_angle)
    h_vec = np.array([np.cos(h_rad), np.sin(h_rad)])
    v_vec = np.array([np.sin(v_rad), np.cos(v_rad)])
    basis = np.column_stack((h_vec, v_vec))

    det = np.linalg.det(basis)
    if abs(det) < MIN_DET:
        return RectifyResult(image=page_bgr, h_angle_deg=0.0, v_angle_deg=0.0)

    a = np.linalg.inv(basis)

    rows, cols = page_bgr.shape[:2]
    c = np.array([cols / 2.0, rows / 2.0])
    m = np.zeros((2, 3), dtype=np.float64)
    m[:, :2] = a
    m[:, 2] = c - a @ c

    rectified = cv2.warpAffine(
        page_bgr, m, (cols, rows), flags=cv2.INTER_CUBIC,
        borderMode=cv2.BORDER_REPLICATE,
    )
    return RectifyResult(image=rectified, h_angle_deg=h_angle, v_angle_deg=v_angle)
