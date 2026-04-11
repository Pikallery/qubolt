from __future__ import annotations

import uuid
from datetime import datetime
from enum import Enum
from typing import Any

from pydantic import BaseModel, ConfigDict


class IngestionSourceType(str, Enum):
    DELIVERY_LOGISTICS = "delivery_logistics"
    ECOMMERCE_ANALYTICS = "ecommerce_analytics"
    DELIVERY_POINTS = "delivery_points"
    DELHIVERY_ROUTES = "delhivery_routes"
    MOBILE_SALES = "mobile_sales"
    RETURNS_SUSTAINABILITY = "returns_sustainability"
    EWASTE_GENERATION = "ewaste_generation"
    EWASTE_RECYCLERS = "ewaste_recyclers"
    MSW_GENERATION = "msw_generation"
    CUSTOM = "custom"


class IngestionJobCreate(BaseModel):
    source_type: IngestionSourceType
    file_name: str
    file_size_bytes: int | None = None


class IngestionJobRead(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: uuid.UUID
    tenant_id: uuid.UUID
    source_type: str
    file_name: str
    row_count_total: int | None
    row_count_ok: int
    row_count_error: int
    status: str
    started_at: datetime | None
    finished_at: datetime | None
    error_summary: dict[str, Any] | None
    created_at: datetime


class IngestionErrorRead(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: uuid.UUID
    job_id: uuid.UUID
    row_number: int | None
    raw_data: dict[str, Any] | None
    validation_errors: dict[str, Any] | None
    created_at: datetime


class IngestionReport(BaseModel):
    job_id: uuid.UUID
    rows_processed: int
    rows_inserted: int
    rows_updated: int
    rows_failed: int
    errors: list[dict[str, Any]] = []
