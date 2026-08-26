from dataclasses import dataclass

import cv2
import numpy as np


@dataclass(frozen=True)
class OrientationResult:
    image: np.ndarray
    rotation_applied: int
    deskew_deg: float


def _binary(bgr: np.ndarray) -> np.ndarray:
    gray = cv2.cvtColor(bgr, cv2.COLOR_BGR2GRAY)
    return cv2.adaptiveThreshold(
        gray, 255, cv2.ADAPTIVE_THRESH_GAUSSIAN_C, cv2.THRESH_BINARY_INV, 31, 15
    )


def _estimate_skew(binary: np.ndarray) -> float:
    """Median angle of long near-horizontal lines. The ruled grid dominates."""
    lines = cv2.HoughLinesP(
        binary, 1, np.pi / 720, threshold=200,
        minLineLength=binary.shape[1] // 4, maxLineGap=20,
    )
    if lines is None:
        return 0.0
    angles = []
    for x1, y1, x2, y2 in lines[:, 0]:
        angle = np.degrees(np.arctan2(y2 - y1, x2 - x1))
        if abs(angle) < 20:  # near-horizontal only
            angles.append(angle)
    return float(np.median(angles)) if angles else 0.0


def _rotate_bound(bgr: np.ndarray, degrees: float) -> np.ndarray:
    h, w = bgr.shape[:2]
    m = cv2.getRotationMatrix2D((w / 2, h / 2), degrees, 1.0)
    return cv2.warpAffine(
        bgr, m, (w, h), flags=cv2.INTER_CUBIC,
        borderMode=cv2.BORDER_REPLICATE,
    )


def correct_orientation(bgr: np.ndarray) -> OrientationResult:
    """Make the spread landscape, then remove residual skew.

    A register spread is always wider than it is tall, so a portrait frame
    means the photo was taken rotated. Distinguishing 90 from 270 (and 0 from
    180) needs text-direction analysis; the recognizer is orientation-tolerant
    per cell, so we only guarantee landscape and record what we applied.
    """
    rotation = 0
    working = bgr
    h, w = working.shape[:2]
    if h > w:
        working = cv2.rotate(working, cv2.ROTATE_90_CLOCKWISE)
        rotation = 90

    skew = _estimate_skew(_binary(working))
    if abs(skew) > 0.2:
        working = _rotate_bound(working, skew)
    else:
        skew = 0.0

    return OrientationResult(image=working, rotation_applied=rotation, deskew_deg=skew)
