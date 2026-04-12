from __future__ import annotations

import uuid
from datetime import datetime, timezone

from fastapi import APIRouter, HTTPException, Query, status
from pydantic import BaseModel
from sqlalchemy import select

from app.dependencies import CurrentTenant, CurrentUser, DBSession, require_min_role
from app.models.audit import Notification
from app.models.shipment import Shipment, ShipmentEvent
from app.models.user import User
from app.schemas.common import PaginatedResponse
from app.schemas.shipment import (
    ShipmentCreate,
    ShipmentEventCreate,
    ShipmentEventRead,
    ShipmentRead,
    ShipmentUpdate,
)
from app.utils.pagination import paginate

router = APIRouter(prefix="/shipments", tags=["shipments"])


async def _create_notification(
    db,
    tenant_id: uuid.UUID,
    recipient_id: uuid.UUID,
    title: str,
    body: str,
    resource_id: uuid.UUID | None = None,
) -> None:
    notif = Notification(
        tenant_id=tenant_id,
        recipient_id=recipient_id,
        channel="push",
        payload={"title": title, "body": body, "resource_id": str(resource_id) if resource_id else None},
        status="delivered",
    )
    db.add(notif)


class AssignDriverBody(BaseModel):
    driver_id: uuid.UUID


@router.get("", response_model=PaginatedResponse)
async def list_shipments(
    tenant: CurrentTenant,
    db: DBSession,
    _: CurrentUser,
    page: int = Query(1, ge=1),
    page_size: int = Query(50, ge=1, le=200),
    status_filter: str | None = Query(None, alias="status"),
    region: str | None = None,
    partner_id: uuid.UUID | None = None,
    assigned_driver_id: uuid.UUID | None = None,
):
    stmt = select(Shipment).where(Shipment.tenant_id == tenant.id)
    if status_filter:
        stmt = stmt.where(Shipment.status == status_filter)
    if region:
        stmt = stmt.where(Shipment.region == region)
    if partner_id:
        stmt = stmt.where(Shipment.partner_id == partner_id)
    if assigned_driver_id:
        stmt = stmt.where(Shipment.assigned_driver_id == assigned_driver_id)
    stmt = stmt.order_by(Shipment.created_at.desc())
    return await paginate(db, stmt, page, page_size, ShipmentRead)


@router.post("", response_model=ShipmentRead, status_code=status.HTTP_201_CREATED)
async def create_shipment(
    body: ShipmentCreate,
    tenant: CurrentTenant,
    db: DBSession,
    _: CurrentUser,
):
    shipment = Shipment(tenant_id=tenant.id, **body.model_dump(exclude_unset=True))
    db.add(shipment)
    await db.flush()
    return ShipmentRead.model_validate(shipment)


@router.get("/{shipment_id}", response_model=ShipmentRead)
async def get_shipment(
    shipment_id: uuid.UUID, tenant: CurrentTenant, db: DBSession, _: CurrentUser
):
    result = await db.execute(
        select(Shipment).where(Shipment.id == shipment_id, Shipment.tenant_id == tenant.id)
    )
    shipment = result.scalar_one_or_none()
    if not shipment:
        raise HTTPException(status_code=404, detail="Shipment not found")
    return ShipmentRead.model_validate(shipment)


@router.patch("/{shipment_id}", response_model=ShipmentRead)
async def update_shipment(
    shipment_id: uuid.UUID,
    body: ShipmentUpdate,
    tenant: CurrentTenant,
    db: DBSession,
    current_user: CurrentUser,
):
    result = await db.execute(
        select(Shipment).where(Shipment.id == shipment_id, Shipment.tenant_id == tenant.id)
    )
    shipment = result.scalar_one_or_none()
    if not shipment:
        raise HTTPException(status_code=404, detail="Shipment not found")

    old_status = shipment.status
    for field, value in body.model_dump(exclude_unset=True).items():
        setattr(shipment, field, value)

    new_status = shipment.status
    ext = shipment.external_id or str(shipment_id)[:8]

    # Step 3: driver hits "Mark Delivered to Hub" → status = in_transit → notify hub gatekeepers
    if old_status != "in_transit" and new_status == "in_transit":
        hub_result = await db.execute(
            select(User).where(
                User.tenant_id == tenant.id,
                User.role == "gatekeeper",
                User.is_active == True,
            )
        )
        for hub_user in hub_result.scalars().all():
            await _create_notification(
                db, tenant.id, hub_user.id,
                title=f"Shipment en route: {ext}",
                body=f"Driver is delivering shipment {ext} to the hub. Confirm arrival when it arrives.",
                resource_id=shipment.id,
            )

    # Step 4: hub confirms arrival → status = delivered → notify managers
    if old_status != "delivered" and new_status == "delivered":
        mgr_result = await db.execute(
            select(User).where(
                User.tenant_id == tenant.id,
                User.role.in_(["manager", "admin"]),
                User.is_active == True,
            )
        )
        for mgr in mgr_result.scalars().all():
            await _create_notification(
                db, tenant.id, mgr.id,
                title=f"Shipment delivered: {ext}",
                body=f"Shipment {ext} has been confirmed at the hub.",
                resource_id=shipment.id,
            )

    await db.flush()
    return ShipmentRead.model_validate(shipment)


@router.post("/{shipment_id}/assign-driver", response_model=ShipmentRead)
async def assign_driver(
    shipment_id: uuid.UUID,
    body: AssignDriverBody,
    tenant: CurrentTenant,
    db: DBSession,
    current_user: CurrentUser,
):
    """Step 1: Manager assigns a driver to a shipment and notifies the driver."""
    result = await db.execute(
        select(Shipment).where(Shipment.id == shipment_id, Shipment.tenant_id == tenant.id)
    )
    shipment = result.scalar_one_or_none()
    if not shipment:
        raise HTTPException(status_code=404, detail="Shipment not found")

    # Validate driver exists in this tenant
    drv_result = await db.execute(
        select(User).where(
            User.id == body.driver_id,
            User.tenant_id == tenant.id,
            User.role == "driver",
            User.is_active == True,
        )
    )
    driver = drv_result.scalar_one_or_none()
    if not driver:
        raise HTTPException(status_code=404, detail="Driver not found")

    shipment.assigned_driver_id = body.driver_id
    ext = shipment.external_id or str(shipment_id)[:8]

    await _create_notification(
        db, tenant.id, body.driver_id,
        title=f"New order assigned: {ext}",
        body=f"You have been assigned shipment {ext}. Region: {shipment.region or 'N/A'}, Priority: {shipment.priority}.",
        resource_id=shipment.id,
    )
    await db.flush()
    return ShipmentRead.model_validate(shipment)


@router.delete("/{shipment_id}", status_code=status.HTTP_204_NO_CONTENT,
               dependencies=[require_min_role("admin")])
async def delete_shipment(
    shipment_id: uuid.UUID, tenant: CurrentTenant, db: DBSession
):
    result = await db.execute(
        select(Shipment).where(Shipment.id == shipment_id, Shipment.tenant_id == tenant.id)
    )
    shipment = result.scalar_one_or_none()
    if not shipment:
        raise HTTPException(status_code=404, detail="Shipment not found")
    await db.delete(shipment)


@router.get("/{shipment_id}/events", response_model=list[ShipmentEventRead])
async def get_events(
    shipment_id: uuid.UUID, tenant: CurrentTenant, db: DBSession, _: CurrentUser
):
    result = await db.execute(
        select(ShipmentEvent)
        .where(ShipmentEvent.shipment_id == shipment_id, ShipmentEvent.tenant_id == tenant.id)
        .order_by(ShipmentEvent.occurred_at)
    )
    return [ShipmentEventRead.model_validate(e) for e in result.scalars().all()]


@router.post("/{shipment_id}/events", response_model=ShipmentEventRead,
             status_code=status.HTTP_201_CREATED)
async def add_event(
    shipment_id: uuid.UUID,
    body: ShipmentEventCreate,
    tenant: CurrentTenant,
    current_user: CurrentUser,
    db: DBSession,
):
    event = ShipmentEvent(
        shipment_id=shipment_id,
        tenant_id=tenant.id,
        recorded_by=current_user.id,
        occurred_at=body.occurred_at or datetime.now(timezone.utc),
        **body.model_dump(exclude={"occurred_at"}, exclude_unset=True),
    )
    db.add(event)
    await db.flush()
    return ShipmentEventRead.model_validate(event)
