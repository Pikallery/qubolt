from __future__ import annotations

import uuid
from datetime import datetime

from pydantic import BaseModel, ConfigDict, Field


class TenantCreate(BaseModel):
    slug: str = Field(min_length=3, max_length=100, pattern=r"^[a-z0-9-]+$")
    name: str = Field(min_length=1, max_length=255)
    plan: str = "starter"
    max_users: int = 5
    max_shipments: int = 1000


class TenantRead(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: uuid.UUID
    slug: str
    name: str
    plan: str
    max_users: int
    max_shipments: int
    is_active: bool
    created_at: datetime


class TenantUpdate(BaseModel):
    name: str | None = None
    plan: str | None = None
    max_users: int | None = None
    max_shipments: int | None = None
    is_active: bool | None = None
