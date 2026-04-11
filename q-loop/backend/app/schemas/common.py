from __future__ import annotations

import uuid
from typing import Any, Generic, TypeVar

from pydantic import BaseModel, ConfigDict

T = TypeVar("T")


class PaginatedResponse(BaseModel, Generic[T]):
    items: list[T]
    total: int
    page: int
    page_size: int
    has_next: bool


class ErrorDetail(BaseModel):
    field: str | None = None
    message: str
    code: str | None = None


class ErrorResponse(BaseModel):
    detail: str
    errors: list[ErrorDetail] | None = None
    request_id: str | None = None


class UUIDModel(BaseModel):
    model_config = ConfigDict(from_attributes=True)
    id: uuid.UUID


class TokenResponse(BaseModel):
    access_token: str
    refresh_token: str
    token_type: str = "bearer"
    expires_in: int  # seconds


class MessageResponse(BaseModel):
    message: str
    data: dict[str, Any] | None = None
