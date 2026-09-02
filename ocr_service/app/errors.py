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

# Structural reasons a spread is refused, surfaced to help the user retake.
# Never carries cell text -- only which check failed.
REFUSAL_REASONS = frozenset(
    {"grid_not_found", "columns_unmatched", "rows_disagree", "pitch_mismatch"}
)
REFUSAL_SIDES = frozenset({"left", "right", "both"})


class OcrError(Exception):
    """Carries a stable machine-readable code. Never carries a file path."""

    def __init__(
        self,
        code: str,
        message: str,
        http_status: int = 400,
        reason: str | None = None,
        side: str | None = None,
    ) -> None:
        if code not in ERROR_CODES:
            raise ValueError(f"unknown error code: {code}")
        if reason is not None and reason not in REFUSAL_REASONS:
            raise ValueError(f"unknown refusal reason: {reason}")
        if side is not None and side not in REFUSAL_SIDES:
            raise ValueError(f"unknown refusal side: {side}")
        super().__init__(message)
        self.code = code
        self.message = message
        self.http_status = http_status
        self.reason = reason
        self.side = side
