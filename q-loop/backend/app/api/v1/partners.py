from __future__ import annotations

import uuid
from datetime import date, datetime

from fastapi import APIRouter, HTTPException, status
from pydantic import BaseModel, ConfigDict
from sqlalchemy import select
from sqlalchemy.orm import selectinload

from app.dependencies import CurrentTenant, CurrentUser, DBSession, require_role
from app.models.delivery_partner import DeliveryPartner, PartnerPerformance

router = APIRouter(prefix="/partners", tags=["partners"])


# ── Schemas ──────────────────────────────────────────────────────────────────

class PartnerCreate(BaseModel):
    name: str
    api_endpoint: str | None = None
    contact_phone: str | None = None
    supported_modes: list[str] | None = None
    supported_vehicle_types: list[str] | None = None
    active_regions: list[str] | None = None


class PartnerUpdate(BaseModel):
    name: str | None = None
    api_endpoint: str | None = None
    contact_phone: str | None = None
    supported_modes: list[str] | None = None
    supported_vehicle_types: list[str] | None = None
    active_regions: list[str] | None = None


class PartnerPerformanceRead(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: uuid.UUID
    partner_id: uuid.UUID
    period_start: date
    period_end: date
    total_deliveries: int
    on_time_count: int
    delayed_count: int
    avg_rating: float | None
    avg_cost_per_km: float | None
    avg_delivery_hrs: float | None


class PartnerRead(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: uuid.UUID
    tenant_id: uuid.UUID
    name: str
    api_endpoint: str | None
    contact_phone: str | None
    supported_modes: list[str] | None
    supported_vehicle_types: list[str] | None
    active_regions: list[str] | None
    created_at: datetime
    updated_at: datetime


class PartnerDetailRead(PartnerRead):
    latest_performance: PartnerPerformanceRead | None = None


# ── Endpoints ────────────────────────────────────────────────────────────────

@router.get("", response_model=list[PartnerDetailRead])
async def list_partners(
    tenant: CurrentTenant,
    db: DBSession,
    _: CurrentUser,
):
    result = await db.execute(
        select(DeliveryPartner)
        .where(DeliveryPartner.tenant_id == tenant.id)
        .options(selectinload(DeliveryPartner.performance_records))
        .order_by(DeliveryPartner.name)
    )
    partners = result.scalars().all()

    output: list[PartnerDetailRead] = []
    for p in partners:
        latest = None
        if p.performance_records:
            # Sort by period_end descending, take the latest
            sorted_perf = sorted(p.performance_records, key=lambda r: r.period_end, reverse=True)
            latest = PartnerPerformanceRead.model_validate(sorted_perf[0])

        detail = PartnerDetailRead(
            **PartnerRead.model_validate(p).model_dump(),
            latest_performance=latest,
        )
        output.append(detail)

    return output


@router.post("", response_model=PartnerRead, status_code=status.HTTP_201_CREATED,
             dependencies=[require_role("admin", "superadmin")])
async def create_partner(
    body: PartnerCreate,
    tenant: CurrentTenant,
    db: DBSession,
):
    partner = DeliveryPartner(tenant_id=tenant.id, **body.model_dump(exclude_unset=True))
    db.add(partner)
    await db.flush()
    return PartnerRead.model_validate(partner)


@router.get("/{partner_id}", response_model=PartnerDetailRead)
async def get_partner(
    partner_id: uuid.UUID,
    tenant: CurrentTenant,
    db: DBSession,
    _: CurrentUser,
):
    result = await db.execute(
        select(DeliveryPartner)
        .where(DeliveryPartner.id == partner_id, DeliveryPartner.tenant_id == tenant.id)
        .options(selectinload(DeliveryPartner.performance_records))
    )
    partner = result.scalar_one_or_none()
    if not partner:
        raise HTTPException(status_code=404, detail="Partner not found")

    latest = None
    if partner.performance_records:
        sorted_perf = sorted(partner.performance_records, key=lambda r: r.period_end, reverse=True)
        latest = PartnerPerformanceRead.model_validate(sorted_perf[0])

    return PartnerDetailRead(
        **PartnerRead.model_validate(partner).model_dump(),
        latest_performance=latest,
    )


@router.put("/{partner_id}", response_model=PartnerRead)
async def update_partner(
    partner_id: uuid.UUID,
    body: PartnerUpdate,
    tenant: CurrentTenant,
    db: DBSession,
    _: CurrentUser,
):
    result = await db.execute(
        select(DeliveryPartner).where(
            DeliveryPartner.id == partner_id,
            DeliveryPartner.tenant_id == tenant.id,
        )
    )
    partner = result.scalar_one_or_none()
    if not partner:
        raise HTTPException(status_code=404, detail="Partner not found")

    for field, value in body.model_dump(exclude_unset=True).items():
        setattr(partner, field, value)
    await db.flush()
    return PartnerRead.model_validate(partner)


@router.get("/{partner_id}/performance", response_model=list[PartnerPerformanceRead])
async def get_partner_performance(
    partner_id: uuid.UUID,
    tenant: CurrentTenant,
    db: DBSession,
    _: CurrentUser,
):
    # Verify partner exists
    partner_result = await db.execute(
        select(DeliveryPartner).where(
            DeliveryPartner.id == partner_id,
            DeliveryPartner.tenant_id == tenant.id,
        )
    )
    if not partner_result.scalar_one_or_none():
        raise HTTPException(status_code=404, detail="Partner not found")

    result = await db.execute(
        select(PartnerPerformance)
        .where(
            PartnerPerformance.partner_id == partner_id,
            PartnerPerformance.tenant_id == tenant.id,
        )
        .order_by(PartnerPerformance.period_end.desc())
    )
    return [PartnerPerformanceRead.model_validate(r) for r in result.scalars().all()]
