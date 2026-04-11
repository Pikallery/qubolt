"""
Analytics endpoints — aggregated KPIs from ingested shipment data.
All queries are scoped to the current tenant.
"""
from __future__ import annotations

from fastapi import APIRouter, Query
from sqlalchemy import Numeric, case, func, select, text

from app.dependencies import CurrentTenant, CurrentUser, DBSession
from app.models.shipment import Shipment

router = APIRouter(prefix="/analytics", tags=["analytics"])


# ── Overview KPIs ─────────────────────────────────────────────────────────────

@router.get("/overview")
async def overview(tenant: CurrentTenant, db: DBSession, _: CurrentUser):
    """
    Top-level KPIs: shipment counts, delay rate, refund rate,
    avg distance, avg delivery cost, avg rating.
    """
    result = await db.execute(
        select(
            func.count(Shipment.id).label("total_shipments"),
            func.sum(case((Shipment.is_delayed == True, 1), else_=0)).label("delayed_count"),
            func.sum(case((Shipment.refund_requested == True, 1), else_=0)).label("refund_count"),
            func.sum(case((Shipment.status == "delivered", 1), else_=0)).label("delivered_count"),
            func.sum(case((Shipment.status == "in_transit", 1), else_=0)).label("in_transit_count"),
            func.sum(case((Shipment.status == "pending", 1), else_=0)).label("pending_count"),
            func.round(func.avg(Shipment.distance_km).cast(Numeric()), 2).label("avg_distance_km"),
            func.round(func.avg(Shipment.delivery_cost).cast(Numeric()), 2).label("avg_delivery_cost"),
            func.round(func.avg(Shipment.order_value_inr).cast(Numeric()), 2).label("avg_order_value_inr"),
            func.round(func.avg(Shipment.rating).cast(Numeric()), 2).label("avg_rating"),
        ).where(Shipment.tenant_id == tenant.id)
    )
    row = result.one()
    total = row.total_shipments or 1  # avoid div-by-zero

    return {
        "total_shipments": row.total_shipments,
        "delivered_count": row.delivered_count,
        "in_transit_count": row.in_transit_count,
        "pending_count": row.pending_count,
        "delayed_count": row.delayed_count,
        "delay_rate_pct": round((row.delayed_count or 0) / total * 100, 2),
        "refund_count": row.refund_count,
        "refund_rate_pct": round((row.refund_count or 0) / total * 100, 2),
        "avg_distance_km": float(row.avg_distance_km) if row.avg_distance_km else None,
        "avg_delivery_cost_inr": float(row.avg_delivery_cost) if row.avg_delivery_cost else None,
        "avg_order_value_inr": float(row.avg_order_value_inr) if row.avg_order_value_inr else None,
        "avg_rating": float(row.avg_rating) if row.avg_rating else None,
    }


# ── By Region ─────────────────────────────────────────────────────────────────

@router.get("/by-region")
async def by_region(
    tenant: CurrentTenant,
    db: DBSession,
    _: CurrentUser,
    limit: int = Query(20, ge=1, le=50),
):
    """Shipment counts + delay rate broken down by region (top N by volume)."""
    result = await db.execute(
        select(
            Shipment.region,
            func.count(Shipment.id).label("total"),
            func.sum(case((Shipment.is_delayed == True, 1), else_=0)).label("delayed"),
            func.sum(case((Shipment.refund_requested == True, 1), else_=0)).label("refunds"),
            func.round(func.avg(Shipment.distance_km).cast(Numeric()), 2).label("avg_distance_km"),
            func.round(func.avg(Shipment.delivery_cost).cast(Numeric()), 2).label("avg_cost"),
        )
        .where(Shipment.tenant_id == tenant.id, Shipment.region.isnot(None))
        .group_by(Shipment.region)
        .order_by(func.count(Shipment.id).desc())
        .limit(limit)
    )
    rows = result.all()
    return [
        {
            "region": r.region,
            "total": r.total,
            "delayed": r.delayed,
            "delay_rate_pct": round((r.delayed or 0) / r.total * 100, 2),
            "refunds": r.refunds,
            "avg_distance_km": float(r.avg_distance_km) if r.avg_distance_km else None,
            "avg_cost_inr": float(r.avg_cost) if r.avg_cost else None,
        }
        for r in rows
    ]


# ── By Vehicle Type ───────────────────────────────────────────────────────────

@router.get("/by-vehicle")
async def by_vehicle(tenant: CurrentTenant, db: DBSession, _: CurrentUser):
    """Shipment breakdown by vehicle type (bike, truck, etc.)."""
    result = await db.execute(
        select(
            Shipment.vehicle_type,
            func.count(Shipment.id).label("total"),
            func.sum(case((Shipment.is_delayed == True, 1), else_=0)).label("delayed"),
            func.round(func.avg(Shipment.distance_km).cast(Numeric()), 2).label("avg_distance_km"),
            func.round(func.avg(Shipment.delivery_cost).cast(Numeric()), 2).label("avg_cost"),
        )
        .where(Shipment.tenant_id == tenant.id, Shipment.vehicle_type.isnot(None))
        .group_by(Shipment.vehicle_type)
        .order_by(func.count(Shipment.id).desc())
    )
    rows = result.all()
    return [
        {
            "vehicle_type": r.vehicle_type,
            "total": r.total,
            "delayed": r.delayed,
            "delay_rate_pct": round((r.delayed or 0) / r.total * 100, 2),
            "avg_distance_km": float(r.avg_distance_km) if r.avg_distance_km else None,
            "avg_cost_inr": float(r.avg_cost) if r.avg_cost else None,
        }
        for r in rows
    ]


# ── By Delivery Mode ──────────────────────────────────────────────────────────

@router.get("/by-delivery-mode")
async def by_delivery_mode(tenant: CurrentTenant, db: DBSession, _: CurrentUser):
    """Breakdown by delivery mode (same_day, express, standard, etc.)."""
    result = await db.execute(
        select(
            Shipment.delivery_mode,
            func.count(Shipment.id).label("total"),
            func.sum(case((Shipment.is_delayed == True, 1), else_=0)).label("delayed"),
            func.round(func.avg(Shipment.distance_km).cast(Numeric()), 2).label("avg_distance_km"),
        )
        .where(Shipment.tenant_id == tenant.id, Shipment.delivery_mode.isnot(None))
        .group_by(Shipment.delivery_mode)
        .order_by(func.count(Shipment.id).desc())
    )
    rows = result.all()
    return [
        {
            "delivery_mode": r.delivery_mode,
            "total": r.total,
            "delayed": r.delayed,
            "delay_rate_pct": round((r.delayed or 0) / r.total * 100, 2),
            "avg_distance_km": float(r.avg_distance_km) if r.avg_distance_km else None,
        }
        for r in rows
    ]


# ── By Platform ───────────────────────────────────────────────────────────────

@router.get("/by-platform")
async def by_platform(tenant: CurrentTenant, db: DBSession, _: CurrentUser):
    """Breakdown by e-commerce platform (Blinkit, Swiggy Instamart, etc.)."""
    result = await db.execute(
        select(
            Shipment.platform,
            func.count(Shipment.id).label("total"),
            func.sum(case((Shipment.is_delayed == True, 1), else_=0)).label("delayed"),
            func.sum(case((Shipment.refund_requested == True, 1), else_=0)).label("refunds"),
            func.round(func.avg(Shipment.order_value_inr).cast(Numeric()), 2).label("avg_order_value"),
            func.round(func.avg(Shipment.rating).cast(Numeric()), 2).label("avg_rating"),
        )
        .where(Shipment.tenant_id == tenant.id, Shipment.platform.isnot(None))
        .group_by(Shipment.platform)
        .order_by(func.count(Shipment.id).desc())
    )
    rows = result.all()
    return [
        {
            "platform": r.platform,
            "total": r.total,
            "delayed": r.delayed,
            "delay_rate_pct": round((r.delayed or 0) / r.total * 100, 2),
            "refunds": r.refunds,
            "refund_rate_pct": round((r.refunds or 0) / r.total * 100, 2),
            "avg_order_value_inr": float(r.avg_order_value) if r.avg_order_value else None,
            "avg_rating": float(r.avg_rating) if r.avg_rating else None,
        }
        for r in rows
    ]


# ── By Priority ───────────────────────────────────────────────────────────────

@router.get("/by-priority")
async def by_priority(tenant: CurrentTenant, db: DBSession, _: CurrentUser):
    """Breakdown by shipment priority (high, medium, low)."""
    result = await db.execute(
        select(
            Shipment.priority,
            func.count(Shipment.id).label("total"),
            func.sum(case((Shipment.is_delayed == True, 1), else_=0)).label("delayed"),
            func.round(func.avg(Shipment.distance_km).cast(Numeric()), 2).label("avg_distance_km"),
        )
        .where(Shipment.tenant_id == tenant.id)
        .group_by(Shipment.priority)
        .order_by(func.count(Shipment.id).desc())
    )
    rows = result.all()
    return [
        {
            "priority": r.priority,
            "total": r.total,
            "delayed": r.delayed,
            "delay_rate_pct": round((r.delayed or 0) / r.total * 100, 2),
            "avg_distance_km": float(r.avg_distance_km) if r.avg_distance_km else None,
        }
        for r in rows
    ]


# ── Sustainability Benchmarks ─────────────────────────────────────────────────

@router.get("/sustainability")
async def sustainability(
    tenant: CurrentTenant,
    db: DBSession,
    _: CurrentUser,
    benchmark_type: str | None = Query(None),
):
    """
    E-waste generation, recycler stats, and MSW benchmarks
    ingested from Rajya Sabha datasets.
    """
    stmt = text("""
        SELECT benchmark_type, financial_year, state_ut,
               metric_name, metric_value, unit, source
        FROM sustainability_benchmarks
        WHERE tenant_id = :tid
        {}
        ORDER BY benchmark_type, financial_year, state_ut
        LIMIT 500
    """.format("AND benchmark_type = :btype" if benchmark_type else ""))

    params: dict = {"tid": tenant.id}
    if benchmark_type:
        params["btype"] = benchmark_type

    result = await db.execute(stmt, params)
    rows = result.mappings().all()
    return [dict(r) for r in rows]
