import hmac

from .config import Settings
from .errors import OcrError

_MAGIC = (
    (b"\xff\xd8\xff", "image/jpeg"),
    (b"\x89PNG\r\n\x1a\n", "image/png"),
)


def detect_image_type(data: bytes) -> str | None:
    """Content-sniff by magic bytes. Never trusts a declared content type."""
    for prefix, mime in _MAGIC:
        if data.startswith(prefix):
            return mime
    if len(data) >= 12 and data[0:4] == b"RIFF" and data[8:12] == b"WEBP":
        return "image/webp"
    return None


def validate_upload(data: bytes, settings: Settings) -> str:
    if not data:
        raise OcrError("corrupt_image", "The uploaded image was empty.")
    if len(data) > settings.max_upload_bytes:
        raise OcrError(
            "image_too_large",
            f"Image exceeds the {settings.max_upload_mb} MB limit.",
            http_status=413,
        )
    mime = detect_image_type(data)
    if mime is None:
        raise OcrError(
            "invalid_image_type", "Only JPEG, PNG and WebP images are accepted."
        )
    return mime


def require_service_key(provided: str | None, settings: Settings) -> None:
    """Constant-time comparison so the key cannot be probed by timing.

    A missing/wrong key from the caller is always 401, even if the server
    itself has no OCR_SERVICE_KEY configured — that is still "unauthorized"
    from the caller's perspective. 503 is reserved for the case where a key
    *was* supplied but the server has nothing configured to compare it to.
    """
    if not provided:
        raise OcrError("unauthorized", "Missing service key.", 401)
    expected = settings.service_key
    if not expected:
        raise OcrError("unauthorized", "Service key is not configured.", 503)
    if not hmac.compare_digest(provided, expected):
        raise OcrError("unauthorized", "Invalid service key.", 401)
