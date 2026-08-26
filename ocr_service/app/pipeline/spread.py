from dataclasses import dataclass

import cv2
import numpy as np


@dataclass(frozen=True)
class SpreadPages:
    left: np.ndarray
    right: np.ndarray
    gutter_x: int


def split_spread(bgr: np.ndarray) -> SpreadPages:
    """Split a two-page spread at the gutter.

    The gutter is the column with the least local ink (sharp strokes: rules,
    handwriting, text). Adaptive thresholding removes low-frequency brightness
    gradients (spine shadows), detecting only the high-frequency edges that
    matter for finding the crease. Searching the middle half (25%–75%) allows
    off-centre framing while avoiding wide outer margins.
    """
    w = bgr.shape[1]
    gray = cv2.cvtColor(bgr, cv2.COLOR_BGR2GRAY)
    # Adaptive threshold: detect local ink (sharp features), removing gradual shadows
    binary = cv2.adaptiveThreshold(
        gray, 255, cv2.ADAPTIVE_THRESH_GAUSSIAN_C, cv2.THRESH_BINARY_INV, 31, 15
    )
    ink = binary.astype(np.uint16)
    col_ink = ink.sum(axis=0)

    # Smooth so a single clean pixel column cannot win.
    kernel = max(3, w // 200 | 1)
    smoothed = cv2.blur(col_ink.astype(np.float32).reshape(1, -1), (kernel, 1)).ravel()

    lo, hi = int(w * 0.25), int(w * 0.75)
    gutter_x = int(lo + int(np.argmin(smoothed[lo:hi])))

    pad = max(4, w // 300)
    left = bgr[:, : max(1, gutter_x - pad)]
    right = bgr[:, min(w - 1, gutter_x + pad) :]
    return SpreadPages(left=left, right=right, gutter_x=gutter_x)
