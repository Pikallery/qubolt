from __future__ import annotations

import uuid
from datetime import datetime

from fastapi import APIRouter, HTTPException, Query
from pydantic import BaseModel, ConfigDict
from sqlalchemy import func, select

from app.dependencies import CurrentTenant, CurrentUser, DBSession
from app.models.shipment import Shipment, ShipmentEvent
from app.models.user import User

router = APIRouter(prefix="/drivers", tags=["drivers"])


# ── Schemas ──────────────────────────────────────────────────────────────────

class DriverPerformanceSummary(BaseModel):
    driver_id: uuid.UUID
    full_name: str | None
    email: str
    total_shipments: int
    on_time_count: int
    delayed_count: int
    avg_rating: float | None
    total_distance_km: float | None


class DriverShipmentHistory(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: uuid.UUID
    external_id: str | None
    status: str
    region: str | None
    distance_km: float | None
    is_delayed: bool
    rating: int | None
    created_at: datetime


# ── Endpoints ────────────────────────────────────────────────────────────────

@router.get("/performance", response_model=list[DriverPerformanceSummary])
async def list_driver_performance(
    tenant: CurrentTenant,
    db: DBSession,
    _: CurrentUser,
):
    # Get all drivers in this tenant
    drivers_result = await db.execute(
        select(User).where(User.tenant_id == tenant.id, User.role == "driver", User.is_active == True)
    )
    drivers = drivers_result.scalars().all()

    summaries: list[DriverPerformanceSummary] = []
    for driver in drivers:
        # Subquery: shipments where this driver recorded an event
        shipment_ids_subq = (
            select(ShipmentEvent.shipment_id)
            .where(ShipmentEvent.recorded_by == driver.id)
            .distinct()
            .subquery()
        )

        stats_result = await db.execute(
            select(
                func.count(Shipment.id).label("total"),
                func.count().filter(Shipment.is_delayed == False).label("on_time"),
                func.count().filter(Shipment.is_delayed == True).label("delayed"),
                func.avg(Shipment.rating).label("avg_rating"),
                func.sum(Shipment.distance_km).label("total_distance"),
            ).where(
                Shipment.id.in_(select(shipment_ids_subq.c.shipment_id)),
                Shipment.tenant_id == tenant.id,
            )
        )
        row = stats_result.one()
        summaries.append(DriverPerformanceSummary(
            driver_id=driver.id,
            full_name=driver.full_name,
            email=driver.email,
            total_shipments=row.total or 0,
            on_time_count=row.on_time or 0,
            delayed_count=row.delayed or 0,
            avg_rating=round(float(row.avg_rating), 2) if row.avg_rating else None,
            total_distance_km=round(float(row.total_distance), 2) if row.total_distance else None,
        ))

    return summaries


@router.get("/{driver_id}/performance", response_model=DriverPerformanceSummary)
async def get_driver_performance(
    driver_id: uuid.UUID,
    tenant: CurrentTenant,
    db: DBSession,
    _: CurrentUser,
):
    # Verify driver exists
    driver_result = await db.execute(
        select(User).where(User.id == driver_id, User.tenant_id == tenant.id, User.role == "driver")
    )
    driver = driver_result.scalar_one_or_none()
    if not driver:
        raise HTTPException(status_code=404, detail="Driver not found")

    shipment_ids_subq = (
        select(ShipmentEvent.shipment_id)
        .where(ShipmentEvent.recorded_by == driver.id)
        .distinct()
        .subquery()
    )

    stats_result = await db.execute(
        select(
            func.count(Shipment.id).label("total"),
            func.count().filter(Shipment.is_delayed == False).label("on_time"),
            func.count().filter(Shipment.is_delayed == True).label("delayed"),
            func.avg(Shipment.rating).label("avg_rating"),
            func.sum(Shipment.distance_km).label("total_distance"),
        ).where(
            Shipment.id.in_(select(shipment_ids_subq.c.shipment_id)),
            Shipment.tenant_id == tenant.id,
        )
    )
    row = stats_result.one()

    return DriverPerformanceSummary(
        driver_id=driver.id,
        full_name=driver.full_name,
        email=driver.email,
        total_shipments=row.total or 0,
        on_time_count=row.on_time or 0,
        delayed_count=row.delayed or 0,
        avg_rating=round(float(row.avg_rating), 2) if row.avg_rating else None,
        total_distance_km=round(float(row.total_distance), 2) if row.total_distance else None,
    )


@router.get("/{driver_id}/history", response_model=list[DriverShipmentHistory])
async def get_driver_history(
    driver_id: uuid.UUID,
    tenant: CurrentTenant,
    db: DBSession,
    _: CurrentUser,
):
    # Verify driver exists
    driver_result = await db.execute(
        select(User).where(User.id == driver_id, User.tenant_id == tenant.id, User.role == "driver")
    )
    driver = driver_result.scalar_one_or_none()
    if not driver:
        raise HTTPException(status_code=404, detail="Driver not found")

    shipment_ids_subq = (
        select(ShipmentEvent.shipment_id)
        .where(ShipmentEvent.recorded_by == driver.id)
        .distinct()
        .subquery()
    )

    result = await db.execute(
        select(Shipment)
        .where(
            Shipment.id.in_(select(shipment_ids_subq.c.shipment_id)),
            Shipment.tenant_id == tenant.id,
        )
        .order_by(Shipment.created_at.desc())
        .limit(50)
    )
    shipments = result.scalars().all()
    return [DriverShipmentHistory.model_validate(s) for s in shipments]
