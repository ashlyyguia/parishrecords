"""Runs every photo through the same pipeline as POST /v1/grid and reports
the verdict per photo: OK (rows/cols per page) or the refusal code, reason
and side. Structure only -- never prints or saves cell contents.

Usage: python scripts/batch_grid_report.py baptismal|marriage <files...>
"""
import sys, pathlib, time, json
import cv2
sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent.parent))
from app.errors import OcrError
from app.pipeline.column_template import BAPTISMAL_REGISTER, MARRIAGE_REGISTER
from app.pipeline.inversion import correct_spread_inversion
from app.pipeline.orientation import correct_orientation
from app.pipeline.rectify import rectify_page
from app.pipeline.spread import split_spread
from app.pipeline.table import detect_spread_grids

REG = {"baptismal": BAPTISMAL_REGISTER, "marriage": MARRIAGE_REGISTER}


def run(path, template):
    data = pathlib.Path(path).read_bytes()
    import numpy as np
    img = cv2.imdecode(np.frombuffer(data, np.uint8), cv2.IMREAD_COLOR)
    if img is None:
        return {"file": pathlib.Path(path).name, "ok": False, "code": "corrupt_image"}
    t = time.time()
    try:
        from app.main import _detect_with_retries
        oriented, _left, _right, g = _detect_with_retries(img, template)
        rows_l = len({c.row for c in g.left.cells}); rows_r = len({c.row for c in g.right.cells})
        return {"file": pathlib.Path(path).name, "ok": True, "rot": oriented.rotation_applied,
                "rows": [rows_l, rows_r], "cols": [g.left.cols, g.right.cols],
                "size": [img.shape[1], img.shape[0]], "s": round(time.time() - t, 1)}
    except OcrError as e:
        return {"file": pathlib.Path(path).name, "ok": False, "code": e.code, "reason": e.reason,
                "side": e.side, "size": [img.shape[1], img.shape[0]], "s": round(time.time() - t, 1)}
    except Exception as e:  # noqa: BLE001
        return {"file": pathlib.Path(path).name, "ok": False, "code": "EXCEPTION:" + type(e).__name__,
                "size": [img.shape[1], img.shape[0]]}


if __name__ == "__main__":
    template = REG[sys.argv[1]]
    for p in sys.argv[2:]:
        print(json.dumps(run(p, template)), flush=True)
