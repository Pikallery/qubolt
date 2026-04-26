from __future__ import annotations

import uuid
from datetime import datetime, timedelta, timezone

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


class EarningTransaction(BaseModel):
    date: str
    desc: str
    amount: float
    is_income: bool


class EarningsSummary(BaseModel):
    today: float
    this_week: float
    pending_payout: float
    transactions: list[EarningTransaction]


def _calc_earning(distance_km: float | None, priority: str | None) -> float:
    dist = distance_km or 15.0
    base = dist * 8.0
    p = (priority or "medium").lower()
    if p == "high":
        base *= 1.5
    elif p == "low":
        base *= 0.85
    return round(base, 2)


@router.get("/me/earnings", response_model=EarningsSummary)
async def get_my_earnings(
    tenant: CurrentTenant,
    current_user: CurrentUser,
    db: DBSession,
):
    """Return real earnings for the logged-in driver based on delivered shipments."""
    now = datetime.now(timezone.utc)
    today_start = now.replace(hour=0, minute=0, second=0, microsecond=0)
    week_start = today_start - timedelta(days=today_start.weekday())

    result = await db.execute(
        select(Shipment)
        .where(
            Shipment.tenant_id == tenant.id,
            Shipment.assigned_driver_id == current_user.id,
            Shipment.status == "delivered",
        )
        .order_by(Shipment.delivered_at.desc())
        .limit(100)
    )
    shipments = result.scalars().all()

    transactions: list[EarningTransaction] = []
    today_total = 0.0
    week_total = 0.0

    for s in shipments:
        amount = _calc_earning(
            float(s.distance_km) if s.distance_km else None,
            s.priority,
        )
        delivered = s.delivered_at or s.created_at
        if delivered.tzinfo is None:
            delivered = delivered.replace(tzinfo=timezone.utc)

        if delivered >= today_start:
            label = f"Today {delivered.strftime('%H:%M')}"
            today_total += amount
        else:
            days_ago = (now.date() - delivered.date()).days
            if days_ago == 1:
                label = f"Yesterday {delivered.strftime('%H:%M')}"
            else:
                label = delivered.strftime("%a %d %b")

        if delivered >= week_start:
            week_total += amount

        transactions.append(EarningTransaction(
            date=label,
            desc=s.external_id or str(s.id)[:8],
            amount=amount,
            is_income=True,
        ))

    return EarningsSummary(
        today=round(today_total, 2),
        this_week=round(week_total, 2),
        pending_payout=round(week_total * 0.3, 2),
        transactions=transactions,
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
