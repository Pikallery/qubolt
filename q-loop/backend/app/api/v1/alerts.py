from __future__ import annotations

import uuid
from datetime import datetime, timedelta, timezone

from fastapi import APIRouter, HTTPException
from pydantic import BaseModel, ConfigDict
from sqlalchemy import func, select

from app.dependencies import CurrentTenant, CurrentUser, DBSession
from app.models.audit import Notification
from app.models.shipment import Shipment, ShipmentEvent

router = APIRouter(prefix="/alerts", tags=["alerts"])


# ── Schemas ──────────────────────────────────────────────────────────────────

class AlertItem(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: uuid.UUID
    alert_type: str           # "notification" | "new_assignment" | "status_change"
    title: str
    detail: str | None = None
    resource_id: uuid.UUID | None = None
    created_at: datetime


class AlertCountResponse(BaseModel):
    unread_count: int


# ── Endpoints ────────────────────────────────────────────────────────────────

@router.get("/pending", response_model=list[AlertItem])
async def get_pending_alerts(
    tenant: CurrentTenant,
    current_user: CurrentUser,
    db: DBSession,
):
    alerts: list[AlertItem] = []
    now = datetime.now(timezone.utc)

    # 1. Unread notifications for this user
    notif_result = await db.execute(
        select(Notification)
        .where(
            Notification.tenant_id == tenant.id,
            Notification.recipient_id == current_user.id,
            Notification.status != "read",
        )
        .order_by(Notification.created_at.desc())
        .limit(50)
    )
    for n in notif_result.scalars().all():
        payload = n.payload or {}
        alerts.append(AlertItem(
            id=n.id,
            alert_type="notification",
            title=payload.get("title", f"Notification via {n.channel}"),
            detail=payload.get("body"),
            resource_id=None,
            created_at=n.created_at,
        ))

    if current_user.role == "driver":
        # 2. New shipment assignments in the last hour
        one_hour_ago = now - timedelta(hours=1)
        event_result = await db.execute(
            select(ShipmentEvent.shipment_id)
            .where(
                ShipmentEvent.tenant_id == tenant.id,
                ShipmentEvent.recorded_by == current_user.id,
                ShipmentEvent.occurred_at >= one_hour_ago,
            )
            .distinct()
        )
        recent_shipment_ids = [row[0] for row in event_result.all()]

        if recent_shipment_ids:
            shipment_result = await db.execute(
                select(Shipment)
                .where(
                    Shipment.id.in_(recent_shipment_ids),
                    Shipment.tenant_id == tenant.id,
                    Shipment.status == "pending",
                )
            )
            for s in shipment_result.scalars().all():
                alerts.append(AlertItem(
                    id=s.id,
                    alert_type="new_assignment",
                    title=f"New shipment assignment: {s.external_id or str(s.id)[:8]}",
                    detail=f"Region: {s.region or 'N/A'}, Priority: {s.priority}",
                    resource_id=s.id,
                    created_at=s.created_at,
                ))

    elif current_user.role in ("admin", "manager", "operator", "superadmin"):
        # 3. Recent shipment status changes (last hour)
        one_hour_ago = now - timedelta(hours=1)
        event_result = await db.execute(
            select(ShipmentEvent)
            .where(
                ShipmentEvent.tenant_id == tenant.id,
                ShipmentEvent.event_type.in_(["status_change", "delivered", "delayed", "auto_assigned"]),
                ShipmentEvent.occurred_at >= one_hour_ago,
            )
            .order_by(ShipmentEvent.occurred_at.desc())
            .limit(50)
        )
        for evt in event_result.scalars().all():
            alerts.append(AlertItem(
                id=evt.id,
                alert_type="status_change",
                title=f"Shipment event: {evt.event_type}",
                detail=evt.note,
                resource_id=evt.shipment_id,
                created_at=evt.occurred_at,
            ))

    return alerts


@router.put("/{notification_id}/dismiss")
async def dismiss_alert(
    notification_id: uuid.UUID,
    tenant: CurrentTenant,
    current_user: CurrentUser,
    db: DBSession,
):
    result = await db.execute(
        select(Notification).where(
            Notification.id == notification_id,
            Notification.tenant_id == tenant.id,
            Notification.recipient_id == current_user.id,
        )
    )
    notif = result.scalar_one_or_none()
    if not notif:
        raise HTTPException(status_code=404, detail="Notification not found")

    notif.status = "read"
    await db.flush()
    return {"ok": True}


@router.get("/count", response_model=AlertCountResponse)
async def get_alert_count(
    tenant: CurrentTenant,
    current_user: CurrentUser,
    db: DBSession,
):
    result = await db.execute(
        select(func.count(Notification.id)).where(
            Notification.tenant_id == tenant.id,
            Notification.recipient_id == current_user.id,
            Notification.status != "read",
        )
    )
    count = result.scalar() or 0
    return AlertCountResponse(unread_count=count)
