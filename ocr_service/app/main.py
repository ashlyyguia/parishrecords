import base64
import logging

import cv2
import numpy as np
from fastapi import FastAPI, Header, Request
from fastapi.responses import JSONResponse

from .config import get_settings
from .errors import OcrError
from .pipeline.column_template import BAPTISMAL_REGISTER
from .pipeline.inversion import correct_spread_inversion
from .pipeline.orientation import correct_orientation
from .pipeline.rectify import rectify_page
from .pipeline.spread import split_spread
from .pipeline.table import detect_spread_grids
from .security import require_service_key, validate_upload

logging.basicConfig(level=logging.INFO)
log = logging.getLogger("ocr_service")

app = FastAPI(title="Parish Register Grid", version="2.0.0")


@app.exception_handler(OcrError)
async def _ocr_error_handler(_: Request, exc: OcrError) -> JSONResponse:
    log.warning("request failed: %s", exc.code)  # code only, never cell text
    return JSONResponse(
        status_code=exc.http_status,
        content={"success": False, "code": exc.code, "message": exc.message},
    )


@app.get("/health")
async def health() -> dict:
    return {"status": "ok"}


def _decode(data: bytes) -> np.ndarray:
    image = cv2.imdecode(np.frombuffer(data, np.uint8), cv2.IMREAD_COLOR)
    if image is None:
        raise OcrError("corrupt_image", "The image could not be decoded.")
    return image


def _page_payload(page_bgr: np.ndarray, grid) -> dict:
    ok, buf = cv2.imencode(".jpg", page_bgr, [cv2.IMWRITE_JPEG_QUALITY, 85])
    if not ok:
        raise OcrError("corrupt_image", "Rectified page could not be encoded.")
    keys = grid.column_keys
    cells = []
    for c in grid.cells:
        key = keys[c.col] if keys and 0 <= c.col < len(keys) else str(c.col)
        cells.append({"key": key, "row": c.row, "x": c.x, "y": c.y, "w": c.w, "h": c.h})
    h, w = page_bgr.shape[:2]
    return {
        "image_b64": base64.b64encode(buf.tobytes()).decode("ascii"),
        "width": int(w),
        "height": int(h),
        # A grid with N horizontal rules bounds N-1 data rows.
        "rows": max(0, grid.rows - 1),
        "cols": grid.cols,
        "cells": cells,
    }


@app.post("/v1/grid")
async def detect_grid_endpoint(
    request: Request,
    x_ocr_service_key: str | None = Header(default=None),
) -> dict:
    settings = get_settings()
    require_service_key(x_ocr_service_key, settings)
    data = await request.body()
    validate_upload(data, settings)

    oriented = correct_orientation(_decode(data))
    spread = correct_spread_inversion(oriented.image).image
    pages = split_spread(spread)
    left = rectify_page(pages.left).image
    right = rectify_page(pages.right).image
    grids = detect_spread_grids(left, right, spread_template=BAPTISMAL_REGISTER)

    return {
        "success": True,
        "rotation_applied": oriented.rotation_applied,
        "deskew_deg": round(oriented.deskew_deg, 2),
        "pages": {
            "left": _page_payload(left, grids.left),
            "right": _page_payload(right, grids.right),
        },
        "warnings": [],
    }
