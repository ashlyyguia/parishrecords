"""Draws a synthetic register spread so tests never need real scans."""
import cv2
import numpy as np

W, H = 2400, 1400
MARGIN = 60
GUTTER_HALF = 24


def make_register_spread(rows: int = 24, cols_left: int = 5, cols_right: int = 5, gutter_offset: int = 0) -> np.ndarray:
    """White page, blue ruled grid, a header band, two pages split by a gutter.

    Args:
        rows: Number of data rows (plus header).
        cols_left: Columns on left page.
        cols_right: Columns on right page.
        gutter_offset: Horizontal offset from centre (pixels). Default 0 = centred.
                       Set to ~-200 for ~40% gutter position.
    """
    img = np.full((H, W, 3), 250, np.uint8)
    mid = W // 2 + gutter_offset
    line = (140, 60, 40)  # BGR, register blue

    for x0, x1, cols in ((MARGIN, mid - GUTTER_HALF, cols_left),
                         (mid + GUTTER_HALF, W - MARGIN, cols_right)):
        top, bottom = MARGIN, H - MARGIN
        header_h = 70
        # rows: one header band plus `rows` data rows
        ys = [top, top + header_h]
        pitch = (bottom - ys[1]) / rows
        ys += [int(ys[1] + i * pitch) for i in range(1, rows + 1)]
        for y in ys:
            cv2.line(img, (x0, y), (x1, y), line, 2)
        xs = [int(x0 + i * (x1 - x0) / cols) for i in range(cols + 1)]
        for x in xs:
            cv2.line(img, (x, top), (x, bottom), line, 2)
        # ink in every data cell so blank-detection tests have signal
        for r in range(rows):
            for c in range(cols):
                cx, cy = xs[c] + 12, int(ys[2 + r] - pitch / 2) + 6
                cv2.putText(img, f"r{r}c{c}", (cx, cy),
                            cv2.FONT_HERSHEY_SIMPLEX, 0.5, (20, 20, 20), 1)
    return img


def rotate(img: np.ndarray, degrees: int) -> np.ndarray:
    if degrees == 90:
        return cv2.rotate(img, cv2.ROTATE_90_CLOCKWISE)
    if degrees == 180:
        return cv2.rotate(img, cv2.ROTATE_180)
    if degrees == 270:
        return cv2.rotate(img, cv2.ROTATE_90_COUNTERCLOCKWISE)
    return img.copy()


def shear_image(img: np.ndarray, h_deg: float, v_deg: float) -> np.ndarray:
    """Tilt horizontal rules by h_deg and vertical rules by v_deg, independently.

    This is the inverse of what rectify_page must undo. BORDER_REPLICATE keeps
    the page background white so Hough does not see a false frame.
    """
    h = np.radians(h_deg)
    v = np.radians(v_deg)
    # columns are the images of the x and y basis vectors
    a = np.array([[np.cos(h), np.sin(v)],
                  [np.sin(h), np.cos(v)]], dtype=np.float64)
    rows, cols = img.shape[:2]
    c = np.array([cols / 2.0, rows / 2.0])
    m = np.zeros((2, 3), dtype=np.float64)
    m[:, :2] = a
    m[:, 2] = c - a @ c
    return cv2.warpAffine(img, m, (cols, rows), flags=cv2.INTER_CUBIC,
                          borderMode=cv2.BORDER_REPLICATE)


def skew(img: np.ndarray, degrees: float) -> np.ndarray:
    """Rotate by an arbitrary (non-90-multiple) angle, simulating hand-held tilt.

    Uses BORDER_REPLICATE so the page background stays white instead of going
    black — a black border would give the Hough transform false edges and
    make skew-detection tests measure the wrong thing.
    """
    h, w = img.shape[:2]
    m = cv2.getRotationMatrix2D((w / 2, h / 2), degrees, 1.0)
    return cv2.warpAffine(
        img, m, (w, h), flags=cv2.INTER_CUBIC,
        borderMode=cv2.BORDER_REPLICATE,
    )
