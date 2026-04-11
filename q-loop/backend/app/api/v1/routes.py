from __future__ import annotations

import uuid

from fastapi import APIRouter, HTTPException, Query, status
from sqlalchemy import select

from app.dependencies import CurrentTenant, CurrentUser, DBSession, require_min_role
from app.models.route import Route, RouteStop
from app.models.customer import CustomerAddress
from app.schemas.route import (
    BuildFromPointsRequest,
    InlineOptimizeRequest,
    InlineOptimizeResponse,
    InlineOptimizedStop,
    OptimizationRequest,
    RouteCreate,
    RouteRead,
    RouteStopRead,
    StopInput,
)

router = APIRouter(prefix="/routes", tags=["routes"])


@router.get("", response_model=list[RouteRead])
async def list_routes(
    tenant: CurrentTenant,
    db: DBSession,
    _: CurrentUser,
    route_status: str | None = Query(None, alias="status"),
):
    stmt = select(Route).where(Route.tenant_id == tenant.id)
    if route_status:
        stmt = stmt.where(Route.status == route_status)
    stmt = stmt.order_by(Route.created_at.desc()).limit(100)
    result = await db.execute(stmt)
    return [RouteRead.model_validate(r) for r in result.scalars().all()]


@router.post("", response_model=RouteRead, status_code=status.HTTP_201_CREATED)
async def create_route(
    body: RouteCreate, tenant: CurrentTenant, db: DBSession, current_user: CurrentUser
):
    route = Route(tenant_id=tenant.id, vehicle_id=body.vehicle_id)
    db.add(route)
    await db.flush()

    for i, stop_in in enumerate(body.stops):
        stop = RouteStop(
            route_id=route.id,
            tenant_id=tenant.id,
            shipment_id=stop_in.shipment_id,
            stop_sequence=i,
            latitude=stop_in.latitude,
            longitude=stop_in.longitude,
        )
        db.add(stop)

    await db.flush()
    return RouteRead.model_validate(route)


@router.get("/{route_id}", response_model=RouteRead)
async def get_route(route_id: uuid.UUID, tenant: CurrentTenant, db: DBSession, _: CurrentUser):
    result = await db.execute(
        select(Route).where(Route.id == route_id, Route.tenant_id == tenant.id)
    )
    route = result.scalar_one_or_none()
    if not route:
        raise HTTPException(status_code=404, detail="Route not found")
    return RouteRead.model_validate(route)


@router.delete("/{route_id}", status_code=status.HTTP_204_NO_CONTENT,
               dependencies=[require_min_role("admin")])
async def delete_route(route_id: uuid.UUID, tenant: CurrentTenant, db: DBSession):
    result = await db.execute(
        select(Route).where(Route.id == route_id, Route.tenant_id == tenant.id)
    )
    route = result.scalar_one_or_none()
    if not route:
        raise HTTPException(status_code=404, detail="Route not found")
    await db.delete(route)


@router.post("/{route_id}/optimize")
async def trigger_optimization(
    route_id: uuid.UUID,
    body: OptimizationRequest,
    tenant: CurrentTenant,
    db: DBSession,
    _: CurrentUser,
):
    """
    Enqueue SA route optimization as a background Celery task.
    Returns task_id to poll status.
    """
    # Verify route belongs to tenant
    result = await db.execute(
        select(Route).where(Route.id == route_id, Route.tenant_id == tenant.id)
    )
    if not result.scalar_one_or_none():
        raise HTTPException(status_code=404, detail="Route not found")

    from app.workers.route_optimizer import optimize_route_task
    task = optimize_route_task.delay(
        route_id=str(route_id),
        tenant_id=str(tenant.id),
        initial_temp=body.initial_temp,
        cooling_rate=body.cooling_rate,
        max_iterations=body.max_iterations,
    )
    return {"task_id": task.id, "status": "queued", "route_id": str(route_id)}


@router.get("/{route_id}/optimize/status")
async def optimization_status(route_id: uuid.UUID, task_id: str, _: CurrentUser):
    """Poll the background optimization job status."""
    from app.workers.celery_app import celery_app
    result = celery_app.AsyncResult(task_id)
    return {
        "task_id": task_id,
        "state": result.state,
        "result": result.result if result.ready() else None,
    }


@router.get("/{route_id}/stops", response_model=list[RouteStopRead])
async def get_route_stops(
    route_id: uuid.UUID, tenant: CurrentTenant, db: DBSession, _: CurrentUser
):
    result = await db.execute(
        select(RouteStop)
        .where(RouteStop.route_id == route_id, RouteStop.tenant_id == tenant.id)
        .order_by(RouteStop.stop_sequence)
    )
    return [RouteStopRead.model_validate(s) for s in result.scalars().all()]


@router.post("/optimize-inline", response_model=InlineOptimizeResponse)
async def optimize_inline(body: InlineOptimizeRequest, _: CurrentUser):
    """
    Run Simulated Annealing on arbitrary lat/lon coordinates — no DB, instant result.
    Useful for testing the optimizer or building UI demos.
    Max 100 stops (SA is O(n²) per iteration).
    """
    if len(body.stops) < 2:
        raise HTTPException(status_code=400, detail="Need at least 2 stops to optimize.")
    if len(body.stops) > 100:
        raise HTTPException(status_code=400, detail="Max 100 stops for inline optimization.")

    from app.services.routing_service import SAResult, Stop, simulated_annealing

    stops = [
        Stop(index=i, lat=s.latitude, lon=s.longitude)
        for i, s in enumerate(body.stops)
    ]
    result: SAResult = simulated_annealing(
        stops,
        initial_temp=body.initial_temp,
        cooling_rate=body.cooling_rate,
        max_iterations=body.max_iterations,
    )

    ordered_stops = [
        InlineOptimizedStop(
            sequence=seq,
            original_index=orig_idx,
            label=body.stops[orig_idx].label,
            latitude=body.stops[orig_idx].latitude,
            longitude=body.stops[orig_idx].longitude,
        )
        for seq, orig_idx in enumerate(result.ordered_indices)
    ]

    return InlineOptimizeResponse(
        stop_count=len(stops),
        initial_distance_km=result.initial_distance_km,
        optimized_distance_km=result.total_distance_km,
        improvement_pct=result.improvement_pct,
        iterations_run=result.iterations_run,
        stops=ordered_stops,
    )


@router.post("/build-from-delivery-points", response_model=dict)
async def build_from_delivery_points(
    body: BuildFromPointsRequest,
    tenant: CurrentTenant,
    db: DBSession,
    _: CurrentUser,
):
    """
    Build a route from the real Rourkela delivery points (lat/lon in DB),
    run SA optimization inline, save the optimized Route, and return results.
    """
    from app.services.routing_service import SAResult, Stop, simulated_annealing

    # Pull delivery point coordinates from customer_addresses
    result = await db.execute(
        select(CustomerAddress)
        .where(
            CustomerAddress.tenant_id == tenant.id,
            CustomerAddress.latitude.isnot(None),
            CustomerAddress.longitude.isnot(None),
        )
        .order_by(CustomerAddress.created_at)
        .limit(body.limit)
    )
    addresses = result.scalars().all()

    if len(addresses) < 2:
        raise HTTPException(
            status_code=404,
            detail="Not enough geo-tagged delivery points found. Ingest delivery_points_rourkela.csv first.",
        )

    stops = [
        Stop(index=i, lat=float(addr.latitude), lon=float(addr.longitude))
        for i, addr in enumerate(addresses)
    ]

    sa_result: SAResult = simulated_annealing(
        stops,
        initial_temp=body.initial_temp,
        cooling_rate=body.cooling_rate,
        max_iterations=body.max_iterations,
    )

    # Persist as a Route
    route = Route(tenant_id=tenant.id, status="active")
    db.add(route)
    await db.flush()

    for new_seq, orig_idx in enumerate(sa_result.ordered_indices):
        addr = addresses[orig_idx]
        stop = RouteStop(
            route_id=route.id,
            tenant_id=tenant.id,
            stop_sequence=new_seq,
            latitude=float(addr.latitude),
            longitude=float(addr.longitude),
        )
        db.add(stop)

    from sqlalchemy import update
    await db.execute(
        update(Route).where(Route.id == route.id).values(
            total_distance_km=sa_result.total_distance_km,
            sa_iterations=sa_result.iterations_run,
            sa_temperature=sa_result.final_temperature,
            sa_final_cost=sa_result.total_distance_km,
            status="active",
        )
    )
    await db.flush()

    return {
        "route_id": str(route.id),
        "stop_count": len(stops),
        "initial_distance_km": sa_result.initial_distance_km,
        "optimized_distance_km": sa_result.total_distance_km,
        "improvement_pct": sa_result.improvement_pct,
        "iterations_run": sa_result.iterations_run,
        "ordered_stops": [
            {
                "sequence": seq,
                "area": addresses[orig_idx].area,
                "pincode": addresses[orig_idx].pincode,
                "latitude": float(addresses[orig_idx].latitude),
                "longitude": float(addresses[orig_idx].longitude),
            }
            for seq, orig_idx in enumerate(sa_result.ordered_indices)
        ],
    }


@router.post("/{route_id}/optimize-sync")
async def optimize_sync(
    route_id: uuid.UUID,
    body: OptimizationRequest,
    tenant: CurrentTenant,
    db: DBSession,
    _: CurrentUser,
):
    """
    Run SA optimization synchronously (in-request) for an existing route.
    Returns results immediately — no polling needed.
    Best for routes with < 50 stops.
    """
    result = await db.execute(
        select(Route).where(Route.id == route_id, Route.tenant_id == tenant.id)
    )
    if not result.scalar_one_or_none():
        raise HTTPException(status_code=404, detail="Route not found")

    from app.services.routing_service import optimize_route
    summary = await optimize_route(
        db=db,
        route_id=route_id,
        initial_temp=body.initial_temp,
        cooling_rate=body.cooling_rate,
        max_iterations=body.max_iterations,
    )
    return summary
