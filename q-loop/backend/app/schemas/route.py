from __future__ import annotations

import uuid
from datetime import datetime

from pydantic import BaseModel, ConfigDict


class StopInput(BaseModel):
    shipment_id: uuid.UUID | None = None
    latitude: float
    longitude: float


class RouteCreate(BaseModel):
    vehicle_id: uuid.UUID | None = None
    stops: list[StopInput] = []


class RouteRead(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: uuid.UUID
    tenant_id: uuid.UUID
    vehicle_id: uuid.UUID | None
    status: str
    total_distance_km: float | None
    total_duration_min: int | None
    optimized_by: str
    sa_iterations: int | None
    sa_temperature: float | None
    sa_final_cost: float | None
    dispatched_at: datetime | None
    completed_at: datetime | None
    created_at: datetime


class RouteStopRead(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: uuid.UUID
    route_id: uuid.UUID
    shipment_id: uuid.UUID | None
    stop_sequence: int
    latitude: float
    longitude: float
    estimated_arrival: datetime | None
    actual_arrival: datetime | None
    status: str


class OptimizationRequest(BaseModel):
    initial_temp: float = 1000.0
    cooling_rate: float = 0.995
    max_iterations: int = 10_000


class InlineStop(BaseModel):
    label: str | None = None
    latitude: float
    longitude: float


class InlineOptimizeRequest(BaseModel):
    stops: list[InlineStop]
    initial_temp: float = 1000.0
    cooling_rate: float = 0.995
    max_iterations: int = 10_000


class InlineOptimizedStop(BaseModel):
    sequence: int
    original_index: int
    label: str | None
    latitude: float
    longitude: float


class InlineOptimizeResponse(BaseModel):
    stop_count: int
    initial_distance_km: float
    optimized_distance_km: float
    improvement_pct: float
    iterations_run: int
    stops: list[InlineOptimizedStop]


class BuildFromPointsRequest(BaseModel):
    limit: int = 20  # max stops to include (keep SA fast)
    initial_temp: float = 1000.0
    cooling_rate: float = 0.995
    max_iterations: int = 10_000
