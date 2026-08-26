import pytest
from app.config import Settings
from app.errors import OcrError
from app.security import detect_image_type, require_service_key, validate_upload

JPEG = b"\xff\xd8\xff\xe0" + b"\x00" * 64
PNG = b"\x89PNG\r\n\x1a\n" + b"\x00" * 64
WEBP = b"RIFF" + b"\x00\x00\x00\x00" + b"WEBP" + b"\x00" * 64
SETTINGS = Settings(service_key="k", max_upload_mb=1)
UNCONFIGURED = Settings(service_key="", max_upload_mb=1)


def test_detects_jpeg():
    assert detect_image_type(JPEG) == "image/jpeg"


def test_detects_png():
    assert detect_image_type(PNG) == "image/png"


def test_detects_webp():
    assert detect_image_type(WEBP) == "image/webp"


def test_rejects_pdf_disguised_as_image():
    assert detect_image_type(b"%PDF-1.7 fake") is None


def test_validate_upload_rejects_non_image():
    with pytest.raises(OcrError) as e:
        validate_upload(b"%PDF-1.7 fake", SETTINGS)
    assert e.value.code == "invalid_image_type"


def test_validate_upload_rejects_oversize():
    oversize = JPEG + b"\x00" * (1024 * 1024 + 1)
    with pytest.raises(OcrError) as e:
        validate_upload(oversize, SETTINGS)
    assert e.value.code == "image_too_large"


def test_validate_upload_rejects_empty():
    with pytest.raises(OcrError) as e:
        validate_upload(b"", SETTINGS)
    assert e.value.code == "corrupt_image"


def test_validate_upload_accepts_jpeg():
    assert validate_upload(JPEG, SETTINGS) == "image/jpeg"


def test_require_service_key_rejects_missing_key():
    with pytest.raises(OcrError) as e:
        require_service_key(None, SETTINGS)
    assert e.value.code == "unauthorized"
    assert e.value.http_status == 401


def test_require_service_key_rejects_wrong_key():
    with pytest.raises(OcrError) as e:
        require_service_key("wrong", SETTINGS)
    assert e.value.code == "unauthorized"
    assert e.value.http_status == 401


def test_require_service_key_accepts_correct_key():
    # Must return normally — this is the only path with no exception.
    assert require_service_key("k", SETTINGS) is None


def test_require_service_key_rejects_when_server_unconfigured():
    with pytest.raises(OcrError) as e:
        require_service_key("anything", UNCONFIGURED)
    assert e.value.code == "unauthorized"
    assert e.value.http_status == 503
