from __future__ import annotations

from functools import lru_cache
from pathlib import Path
from typing import Literal

from pydantic import AnyHttpUrl, field_validator
from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(
        env_file=".env",
        env_file_encoding="utf-8",
        case_sensitive=False,
        extra="ignore",
    )

    # App
    APP_NAME: str = "Qubolt"
    APP_ENV: Literal["development", "staging", "production"] = "development"
    APP_VERSION: str = "0.1.0"
    LOG_LEVEL: str = "INFO"

    # Database
    DATABASE_URL: str = "postgresql+asyncpg://qloop:qloop_secret@localhost:5432/qloop_db"
    DATABASE_URL_SYNC: str = "postgresql+psycopg2://qloop:qloop_secret@localhost:5432/qloop_db"
    DB_POOL_SIZE: int = 10
    DB_MAX_OVERFLOW: int = 20
    DB_POOL_TIMEOUT: int = 30

    # Redis / Celery
    REDIS_URL: str = "redis://localhost:6379/0"
    CELERY_BROKER_URL: str = "redis://localhost:6379/0"
    CELERY_RESULT_BACKEND: str = "redis://localhost:6379/1"

    # Security
    SECRET_KEY: str = "insecure-dev-key-replace-in-prod"
    JWT_ALGORITHM: str = "HS256"
    ACCESS_TOKEN_EXPIRE_MINUTES: int = 480
    REFRESH_TOKEN_EXPIRE_DAYS: int = 30
    QR_TOKEN_EXPIRE_SECONDS: int = 300  # 5 minutes

    # Google Gemini AI
    GEMINI_API_KEY: str = ""
    GEMINI_API_KEY_FALLBACK: str = ""
    GEMINI_MODEL: str = "gemini-2.0-flash"
    GEMINI_TEMPERATURE: float = 0.6
    GEMINI_TOP_P: float = 0.9
    GEMINI_MAX_TOKENS: int = 4096
    AI_CONCURRENCY_LIMIT: int = 5

    # Twilio
    TWILIO_ACCOUNT_SID: str = ""
    TWILIO_AUTH_TOKEN: str = ""
    TWILIO_PHONE_NUMBER: str = ""
    TWILIO_TWIML_BASE_URL: str = ""

    # Mapbox
    MAPBOX_ACCESS_TOKEN: str = ""

    # Upload
    UPLOAD_DIR: Path = Path("/app/uploads")
    MAX_UPLOAD_SIZE_MB: int = 50

    # Simulated Annealing defaults
    SA_INITIAL_TEMP: float = 1000.0
    SA_COOLING_RATE: float = 0.995
    SA_MAX_ITERATIONS: int = 10_000

    @field_validator("UPLOAD_DIR", mode="before")
    @classmethod
    def ensure_upload_dir(cls, v: str | Path) -> Path:
        p = Path(v)
        p.mkdir(parents=True, exist_ok=True)
        return p

    @property
    def is_production(self) -> bool:
        return self.APP_ENV == "production"

    @property
    def cors_origins(self) -> list[str]:
        if self.APP_ENV == "development":
            return ["*"]
        return ["https://app.qubolt.io"]


@lru_cache
def get_settings() -> Settings:
    return Settings()


settings = get_settings()
