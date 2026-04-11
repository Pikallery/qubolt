from __future__ import annotations

import uuid
from datetime import datetime, timezone

from fastapi import APIRouter, HTTPException, Query, status
from sqlalchemy import select

from app.dependencies import CurrentTenant, CurrentUser, DBSession, require_min_role
from app.models.shipment import Shipment, ShipmentEvent
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
):
    stmt = select(Shipment).where(Shipment.tenant_id == tenant.id)
    if status_filter:
        stmt = stmt.where(Shipment.status == status_filter)
    if region:
        stmt = stmt.where(Shipment.region == region)
    if partner_id:
        stmt = stmt.where(Shipment.partner_id == partner_id)
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
    _: CurrentUser,
):
    result = await db.execute(
        select(Shipment).where(Shipment.id == shipment_id, Shipment.tenant_id == tenant.id)
    )
    shipment = result.scalar_one_or_none()
    if not shipment:
        raise HTTPException(status_code=404, detail="Shipment not found")

    for field, value in body.model_dump(exclude_unset=True).items():
        setattr(shipment, field, value)
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
