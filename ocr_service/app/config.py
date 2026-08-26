import pathlib
from functools import lru_cache

from pydantic_settings import BaseSettings, SettingsConfigDict

# Load ocr_service/.env when present, resolved from this file's location so it
# is found no matter what directory uvicorn is launched from. A real
# environment variable still wins over the file (pydantic-settings precedence),
# so container/CI overrides keep working. This exists so an operator can put
# OCR_SERVICE_KEY in a file once, rather than fight per-shell env-var syntax.
_ENV_FILE = str(pathlib.Path(__file__).resolve().parent.parent / ".env")


class Settings(BaseSettings):
    """Runtime configuration. Every value is overridable by env var."""

    model_config = SettingsConfigDict(
        env_prefix="OCR_", env_file=_ENV_FILE, extra="ignore"
    )

    service_key: str = ""
    confidence_floor: float = 0.75
    ink_density_floor: float = 0.005
    max_upload_mb: int = 15
    engine: str = "paddle"

    @property
    def max_upload_bytes(self) -> int:
        return self.max_upload_mb * 1024 * 1024


@lru_cache
def get_settings() -> Settings:
    return Settings()
