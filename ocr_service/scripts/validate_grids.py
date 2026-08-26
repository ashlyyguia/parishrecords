"""Reports detected row/col counts per page for the real sample spreads.
Structure only -- never prints cell contents (records of minors)."""
import sys, pathlib
import cv2
sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent.parent))
from app.pipeline.orientation import correct_orientation
from app.pipeline.inversion import correct_spread_inversion
from app.pipeline.spread import split_spread
from app.pipeline.rectify import rectify_page
from app.pipeline.table import detect_spread_grids
from app.pipeline.column_template import BAPTISMAL_REGISTER


def run(path):
    bgr = cv2.imread(path)
    if bgr is None:
        print(f"{path}: could not read")
        return
    oriented = correct_orientation(bgr)
    spread = correct_spread_inversion(oriented.image).image
    pages = split_spread(spread)
    left = rectify_page(pages.left).image
    right = rectify_page(pages.right).image
    grids = detect_spread_grids(left, right, spread_template=BAPTISMAL_REGISTER)
    # A GridResult with N horizontal rules bounds N-1 data rows.
    print(f"{path}: rotation={oriented.rotation_applied} deskew={oriented.deskew_deg:.1f} "
          f"left rows={max(0, grids.left.rows-1)} cols={grids.left.cols} | "
          f"right rows={max(0, grids.right.rows-1)} cols={grids.right.cols}")


if __name__ == "__main__":
    for p in sys.argv[1:]:
        try:
            run(p)
        except Exception as e:  # noqa: BLE001
            print(f"{p}: FAILED {type(e).__name__}: {e}")
