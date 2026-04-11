from __future__ import annotations

import uuid

from fastapi import APIRouter, HTTPException
from sqlalchemy import Integer, func, select

from app.dependencies import CurrentTenant, CurrentUser, DBSession
from app.models.shipment import Shipment
from app.schemas.ai_insight import ETAPrediction, InsightRequest, InsightResponse, RouteExplanation
from app.services import ai_service

router = APIRouter(prefix="/ai", tags=["ai"])


@router.post("/insight")
async def supply_chain_insight(
    body: InsightRequest,
    tenant: CurrentTenant,
    db: DBSession,
    _: CurrentUser,
):
    """
    Analyse shipments or answer a free-form query with DeepSeek-R1.
    If query is provided without shipment_ids, uses analytics overview data.
    """
    # Free-form query mode — pull aggregate stats automatically
    if body.query and not body.shipment_ids:
        stats = await db.execute(
            select(
                func.count(Shipment.id).label("total"),
                func.count(Shipment.id).filter(Shipment.is_delayed == True).label("delayed"),
                func.avg(Shipment.delivery_cost).label("avg_cost"),
                func.avg(Shipment.distance_km).label("avg_dist"),
                func.avg(Shipment.rating).label("avg_rating"),
            ).where(Shipment.tenant_id == tenant.id)
        )
        row = stats.first()
        total = row.total or 0
        delayed = row.delayed or 0
        summaries = [{
            "_context": body.query,
            "total_shipments": total,
            "delayed": delayed,
            "delay_rate": f"{(delayed / total * 100) if total else 0:.1f}%",
            "avg_cost_inr": float(row.avg_cost) if row.avg_cost else None,
            "avg_distance_km": float(row.avg_dist) if row.avg_dist else None,
            "avg_rating": float(row.avg_rating) if row.avg_rating else None,
            "region": "Odisha",
        }]
        result = await ai_service.get_supply_chain_insight(summaries)
        return {
            "insight": result.narrative,
            "reasoning": result.reasoning,
            "delay_patterns": result.delay_patterns,
            "partner_risks": result.partner_risks,
            "cost_anomalies": result.cost_anomalies,
            "generated_at": result.generated_at.isoformat(),
        }

    # Standard mode with shipment IDs
    result = await db.execute(
        select(Shipment)
        .where(
            Shipment.id.in_(body.shipment_ids[:50]),
            Shipment.tenant_id == tenant.id,
        )
    )
    shipments = result.scalars().all()
    if not shipments:
        raise HTTPException(status_code=404, detail="No shipments found for given IDs")

    summaries = [
        {
            "id": str(s.id),
            "status": s.status,
            "is_delayed": s.is_delayed,
            "region": s.region,
            "distance_km": float(s.distance_km) if s.distance_km else None,
            "delivery_cost": float(s.delivery_cost) if s.delivery_cost else None,
            "partner_id": str(s.partner_id) if s.partner_id else None,
            "vehicle_type": s.vehicle_type,
            "delivery_mode": s.delivery_mode,
            "rating": s.rating,
            "refund_requested": s.refund_requested,
        }
        for s in shipments
    ]
    if body.context:
        summaries.append({"_context": body.context})

    return await ai_service.get_supply_chain_insight(summaries)


@router.post("/route-explain/{route_id}", response_model=RouteExplanation)
async def explain_route(
    route_id: uuid.UUID,
    tenant: CurrentTenant,
    db: DBSession,
    _: CurrentUser,
):
    """Generate a plain-English explanation of the SA route optimization decision."""
    from app.models.route import Route, RouteStop
    result = await db.execute(
        select(Route).where(Route.id == route_id, Route.tenant_id == tenant.id)
    )
    route = result.scalar_one_or_none()
    if not route:
        raise HTTPException(status_code=404, detail="Route not found")

    stops_result = await db.execute(
        select(RouteStop)
        .where(RouteStop.route_id == route_id)
        .order_by(RouteStop.stop_sequence)
    )
    stops = stops_result.scalars().all()

    route_summary = {
        "route_id": str(route.id),
        "status": route.status,
        "total_distance_km": float(route.total_distance_km) if route.total_distance_km else None,
        "stop_count": len(stops),
        "sa_iterations": route.sa_iterations,
        "sa_final_cost": float(route.sa_final_cost) if route.sa_final_cost else None,
        "stops": [
            {"seq": s.stop_sequence, "lat": float(s.latitude), "lon": float(s.longitude)}
            for s in stops
        ],
    }
    return await ai_service.get_route_explanation(route_summary)


@router.post("/eta-predict/{shipment_id}", response_model=ETAPrediction)
async def predict_eta(
    shipment_id: uuid.UUID,
    tenant: CurrentTenant,
    db: DBSession,
    _: CurrentUser,
):
    """Predict delivery ETA for a shipment using DeepSeek-R1."""
    result = await db.execute(
        select(Shipment).where(Shipment.id == shipment_id, Shipment.tenant_id == tenant.id)
    )
    shipment = result.scalar_one_or_none()
    if not shipment:
        raise HTTPException(status_code=404, detail="Shipment not found")

    summary = {
        "id": str(shipment.id),
        "status": shipment.status,
        "region": shipment.region,
        "distance_km": float(shipment.distance_km) if shipment.distance_km else None,
        "vehicle_type": shipment.vehicle_type,
        "delivery_mode": shipment.delivery_mode,
        "weather_at_dispatch": shipment.weather_at_dispatch,
        "is_delayed": shipment.is_delayed,
        "created_at": shipment.created_at.isoformat() if shipment.created_at else None,
    }
    return await ai_service.predict_eta(summary)
