ERROR_CODES = frozenset(
    {
        "invalid_image_type",
        "image_too_large",
        "corrupt_image",
        "no_table_detected",
        "no_rows_detected",
        "recognizer_failed",
        "unauthorized",
    }
)


class OcrError(Exception):
    """Carries a stable machine-readable code. Never carries a file path."""

    def __init__(self, code: str, message: str, http_status: int = 400) -> None:
        if code not in ERROR_CODES:
            raise ValueError(f"unknown error code: {code}")
        super().__init__(message)
        self.code = code
        self.message = message
        self.http_status = http_status
