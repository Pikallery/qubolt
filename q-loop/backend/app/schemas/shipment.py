from __future__ import annotations

import uuid
from datetime import datetime

from pydantic import BaseModel, ConfigDict, Field


class ShipmentCreate(BaseModel):
    customer_id: uuid.UUID | None = None
    partner_id: uuid.UUID | None = None
    external_id: str | None = None
    package_type: str | None = None
    vehicle_type: str | None = None
    delivery_mode: str | None = None
    region: str | None = None
    weather_at_dispatch: str | None = None
    distance_km: float | None = None
    weight_kg: float | None = None
    order_value_inr: float | None = None
    delivery_cost: float | None = None
    priority: str = "medium"
    platform: str | None = None
    expected_at: datetime | None = None


class ShipmentRead(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: uuid.UUID
    tenant_id: uuid.UUID
    external_id: str | None
    customer_id: uuid.UUID | None
    partner_id: uuid.UUID | None
    assigned_driver_id: uuid.UUID | None = None
    hub_operator_id: uuid.UUID | None = None
    employment_type: str = "company"
    package_type: str | None
    vehicle_type: str | None
    delivery_mode: str | None
    region: str | None
    distance_km: float | None
    weight_kg: float | None
    order_value_inr: float | None
    delivery_cost: float | None
    priority: str
    status: str
    is_delayed: bool
    refund_requested: bool
    rating: int | None
    expected_at: datetime | None
    delivered_at: datetime | None
    created_at: datetime


class ShipmentUpdate(BaseModel):
    status: str | None = None
    is_delayed: bool | None = None
    delivered_at: datetime | None = None
    rating: int | None = Field(None, ge=1, le=5)
    refund_requested: bool | None = None
    assigned_driver_id: uuid.UUID | None = None
    hub_operator_id: uuid.UUID | None = None
    employment_type: str | None = None


class ShipmentEventCreate(BaseModel):
    event_type: str
    location_lat: float | None = None
    location_lon: float | None = None
    note: str | None = None
    occurred_at: datetime | None = None


class ShipmentEventRead(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: uuid.UUID
    shipment_id: uuid.UUID
    event_type: str
    location_lat: float | None
    location_lon: float | None
    note: str | None
    recorded_by: uuid.UUID | None
    occurred_at: datetime
