from __future__ import annotations

import uuid
from datetime import datetime

from fastapi import APIRouter, HTTPException, status
from pydantic import BaseModel, ConfigDict
from sqlalchemy import select

from app.dependencies import CurrentTenant, CurrentUser, DBSession, require_min_role
from app.models.shipment import Shipment

router = APIRouter(prefix="/returns", tags=["returns"])


# ── Schemas ──────────────────────────────────────────────────────────────────

class ReturnRequest(BaseModel):
    shipment_id: uuid.UUID
    reason: str
    pickup_address: str | None = None
    notes: str | None = None


class ReturnRead(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: uuid.UUID
    tenant_id: uuid.UUID
    external_id: str | None
    status: str
    region: str | None
    distance_km: float | None
    priority: str
    created_at: datetime

    # Extra fields carried via the Shipment model columns
    original_shipment_id: uuid.UUID | None = None
    reason: str | None = None
    pickup_address: str | None = None
    notes: str | None = None


# ── Helpers ──────────────────────────────────────────────────────────────────

def _return_read(shipment: Shipment) -> ReturnRead:
    """Build a ReturnRead from a return-type Shipment.

    We encode original_shipment_id, reason, pickup_address, notes in the
    Shipment's external_id and region fields for simplicity since there's no
    dedicated returns table. The external_id is 'return:<original_id>' and we
    store reason/pickup/notes in the package_type, vehicle_type, delivery_mode
    columns (repurposed for returns).
    """
    original_id = None
    if shipment.external_id and shipment.external_id.startswith("return:"):
        try:
            original_id = uuid.UUID(shipment.external_id.split(":", 1)[1])
        except (ValueError, IndexError):
            pass

    return ReturnRead(
        id=shipment.id,
        tenant_id=shipment.tenant_id,
        external_id=shipment.external_id,
        status=shipment.status,
        region=shipment.region,
        distance_km=float(shipment.distance_km) if shipment.distance_km else None,
        priority=shipment.priority,
        created_at=shipment.created_at,
        original_shipment_id=original_id,
        reason=shipment.package_type,        # repurposed for return reason
        pickup_address=shipment.vehicle_type, # repurposed for pickup address
        notes=shipment.delivery_mode,         # repurposed for notes
    )


# ── Endpoints ────────────────────────────────────────────────────────────────

@router.post("/request", response_model=ReturnRead, status_code=status.HTTP_201_CREATED)
async def create_return(
    body: ReturnRequest,
    tenant: CurrentTenant,
    db: DBSession,
    _: CurrentUser,
):
    # Validate original shipment
    result = await db.execute(
        select(Shipment).where(
            Shipment.id == body.shipment_id,
            Shipment.tenant_id == tenant.id,
        )
    )
    original = result.scalar_one_or_none()
    if not original:
        raise HTTPException(status_code=404, detail="Original shipment not found")
    if original.status != "delivered":
        raise HTTPException(status_code=400, detail="Only delivered shipments can be returned")

    return_shipment = Shipment(
        tenant_id=tenant.id,
        external_id=f"return:{original.id}",
        customer_id=original.customer_id,
        partner_id=original.partner_id,
        region=original.region,
        distance_km=original.distance_km,
        weight_kg=original.weight_kg,
        priority="high",
        status="return_pending",
        # Repurpose fields for return metadata
        package_type=body.reason,
        vehicle_type=body.pickup_address,
        delivery_mode=body.notes,
    )
    db.add(return_shipment)
    await db.flush()
    return _return_read(return_shipment)


@router.get("", response_model=list[ReturnRead])
async def list_returns(
    tenant: CurrentTenant,
    db: DBSession,
    _: CurrentUser,
):
    result = await db.execute(
        select(Shipment)
        .where(
            Shipment.tenant_id == tenant.id,
            Shipment.status.like("return_%"),
        )
        .order_by(Shipment.created_at.desc())
    )
    return [_return_read(s) for s in result.scalars().all()]


@router.put("/{shipment_id}/assign", response_model=ReturnRead,
            dependencies=[require_min_role("operator")])
async def assign_return(
    shipment_id: uuid.UUID,
    tenant: CurrentTenant,
    db: DBSession,
):
    result = await db.execute(
        select(Shipment).where(
            Shipment.id == shipment_id,
            Shipment.tenant_id == tenant.id,
            Shipment.status == "return_pending",
        )
    )
    shipment = result.scalar_one_or_none()
    if not shipment:
        raise HTTPException(status_code=404, detail="Return shipment not found or not in pending status")

    shipment.status = "return_assigned"
    await db.flush()
    return _return_read(shipment)


@router.put("/{shipment_id}/pickup", response_model=ReturnRead)
async def pickup_return(
    shipment_id: uuid.UUID,
    tenant: CurrentTenant,
    db: DBSession,
    _: CurrentUser,
):
    result = await db.execute(
        select(Shipment).where(
            Shipment.id == shipment_id,
            Shipment.tenant_id == tenant.id,
            Shipment.status == "return_assigned",
        )
    )
    shipment = result.scalar_one_or_none()
    if not shipment:
        raise HTTPException(status_code=404, detail="Return shipment not found or not in assigned status")

    shipment.status = "return_in_transit"
    await db.flush()
    return _return_read(shipment)


@router.put("/{shipment_id}/received", response_model=ReturnRead)
async def receive_return(
    shipment_id: uuid.UUID,
    tenant: CurrentTenant,
    db: DBSession,
    _: CurrentUser,
):
    result = await db.execute(
        select(Shipment).where(
            Shipment.id == shipment_id,
            Shipment.tenant_id == tenant.id,
            Shipment.status == "return_in_transit",
        )
    )
    shipment = result.scalar_one_or_none()
    if not shipment:
        raise HTTPException(status_code=404, detail="Return shipment not found or not in transit")

    shipment.status = "return_completed"
    await db.flush()
    return _return_read(shipment)
