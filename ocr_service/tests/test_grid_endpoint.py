import base64
from types import SimpleNamespace

import cv2
from fastapi.testclient import TestClient

import app.main as main_module
from app.config import get_settings
from app.main import app
from tests.support.synthetic import make_register_spread

client = TestClient(app)


def _fake_grid():
    cells = [
        SimpleNamespace(row=r, col=c, x=c * 20, y=r * 20, w=20, h=20)
        for r in range(7)
        for c in range(5)
    ]
    return SimpleNamespace(
        rows=7,
        cols=5,
        cells=cells,
        column_keys=("no", "child_name", "place_and_birth_date", "l_or_ill", "parents"),
    )


def _fake_spread(*_args, **_kwargs):
    return SimpleNamespace(left=_fake_grid(), right=_fake_grid())


def _png_bytes(bgr):
    ok, buf = cv2.imencode(".png", bgr)
    assert ok
    return buf.tobytes()


def test_health():
    assert client.get("/health").json() == {"status": "ok"}


def test_grid_returns_geometry_for_a_spread(monkeypatch):
    # The detector itself is covered by the pipeline unit tests; here we test
    # the ENDPOINT wiring (auth, decode, preprocessing, response shape) in
    # isolation by stubbing detect_spread_grids -- the generic synthetic
    # doesn't match the real register's column proportions, which the
    # template-corroboration gate (correctly) refuses.
    monkeypatch.setenv("OCR_SERVICE_KEY", "k")
    get_settings.cache_clear()
    monkeypatch.setattr(main_module, "detect_spread_grids", _fake_spread)
    spread = make_register_spread(rows=24, cols_left=5, cols_right=5)  # decodes + preprocesses cleanly
    res = client.post(
        "/v1/grid", content=_png_bytes(spread), headers={"X-OCR-Service-Key": "k"}
    )
    assert res.status_code == 200, res.text
    body = res.json()
    assert body["success"] is True
    for side in ("left", "right"):
        page = body["pages"][side]
        assert page["rows"] == 6  # 7 rules -> 6 data rows
        assert page["cols"] == 5
        assert page["cells"]
        assert page["cells"][0]["key"] == "no"
        assert all({"key", "row", "x", "y", "w", "h"} <= set(c) for c in page["cells"])
        assert base64.b64decode(page["image_b64"])  # decodable image
    get_settings.cache_clear()


def test_refusal_response_includes_reason_and_side(monkeypatch):
    from app.errors import OcrError

    def _raise(*_a, **_k):
        raise OcrError("no_table_detected", "Couldn't read this spread.",
                       reason="rows_disagree", side="both")

    monkeypatch.setenv("OCR_SERVICE_KEY", "k")
    get_settings.cache_clear()
    monkeypatch.setattr(main_module, "detect_spread_grids", _raise)
    spread = make_register_spread(rows=24, cols_left=5, cols_right=5)
    res = client.post(
        "/v1/grid", content=_png_bytes(spread), headers={"X-OCR-Service-Key": "k"}
    )
    assert res.status_code >= 400
    body = res.json()
    assert body["success"] is False
    assert body["reason"] == "rows_disagree"
    assert body["side"] == "both"
    get_settings.cache_clear()


def test_grid_rejects_missing_key(monkeypatch):
    monkeypatch.setenv("OCR_SERVICE_KEY", "k")
    get_settings.cache_clear()
    res = client.post("/v1/grid", content=b"\xff\xd8\xffdata")
    assert res.status_code == 401
    assert res.json()["code"] == "unauthorized"
    get_settings.cache_clear()


def test_grid_rejects_corrupt_image(monkeypatch):
    monkeypatch.setenv("OCR_SERVICE_KEY", "k")
    get_settings.cache_clear()
    res = client.post(
        "/v1/grid",
        content=b"\xff\xd8\xffnotreallyanimage",
        headers={"X-OCR-Service-Key": "k"},
    )
    assert res.status_code == 400
    assert res.json()["code"] == "corrupt_image"
    get_settings.cache_clear()
