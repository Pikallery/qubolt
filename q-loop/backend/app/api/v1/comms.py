"""Communications API — in-app messaging, Twilio SMS/call, and live fleet positions."""
from __future__ import annotations

import uuid
from datetime import datetime, timezone

from fastapi import APIRouter, HTTPException, Query
from pydantic import BaseModel, Field
from sqlalchemy import and_, or_, select, update
from sqlalchemy.dialects.postgresql import insert as pg_insert

from app.dependencies import CurrentTenant, CurrentUser, DBSession
from app.models.audit import Notification
from app.models.driver_location import DriverLocation
from app.models.message import Message
from app.models.user import User
from app.models.user_profile import UserProfile
from app.schemas.common import PaginatedResponse
from app.services import twilio_service
from app.utils.pagination import paginate

router = APIRouter(prefix="/comms", tags=["communications"])


# ── Schemas ───────────────────────────────────────────────────────────────────

class SendMessageRequest(BaseModel):
    recipient_id: uuid.UUID
    body: str = Field(..., min_length=1, max_length=2000)
    also_send_sms: bool = False


class MessageRead(BaseModel):
    id: uuid.UUID
    sender_id: uuid.UUID
    recipient_id: uuid.UUID
    body: str
    channel: str
    twilio_sid: str | None
    read_at: str | None
    created_at: str
    sender_name: str | None = None
    sender_role: str | None = None


class UpdateLocationRequest(BaseModel):
    lat: float = Field(..., ge=-90, le=90)
    lon: float = Field(..., ge=-180, le=180)
    speed_kmh: float | None = None
    status: str = "en_route"
    custom_id: str | None = None


class FleetPositionRead(BaseModel):
    driver_id: str
    driver_name: str | None
    driver_email: str | None
    lat: float
    lon: float
    speed_kmh: float | None
    status: str
    custom_id: str | None
    updated_at: str


class CallRequest(BaseModel):
    recipient_user_id: uuid.UUID | None = None
    shipment_id: uuid.UUID | None = None
    message_template: str | None = None
    use_voip: bool = True


class NotifyRequest(BaseModel):
    shipment_id: uuid.UUID | None = None
    recipient_user_id: uuid.UUID | None = None
    channel: str = "sms"
    message: str


class NotificationRead(BaseModel):
    id: uuid.UUID
    channel: str
    status: str
    twilio_sid: str | None
    sent_at: str | None

    class Config:
        from_attributes = True


# ── Messaging ─────────────────────────────────────────────────────────────────

@router.post("/message", response_model=MessageRead)
async def send_message(
    body: SendMessageRequest,
    tenant: CurrentTenant,
    current_user: CurrentUser,
    db: DBSession,
):
    """Store in-app message. Optionally also sends via Twilio SMS if recipient has phone."""
    result = await db.execute(
        select(User).where(
            User.id == body.recipient_id,
            User.tenant_id == tenant.id,
            User.is_active == True,
        )
    )
    recipient = result.scalar_one_or_none()
    if not recipient:
        raise HTTPException(status_code=404, detail="Recipient not found")

    twilio_sid: str | None = None
    channel = "in_app"

    if body.also_send_sms and recipient.phone:
        try:
            twilio_sid = await twilio_service.send_sms(
                db=db,
                tenant_id=tenant.id,
                to_phone=recipient.phone,
                message=f"[Q-Loop from {current_user.full_name or current_user.email}] {body.body}",
                recipient_id=recipient.id,
            )
            channel = "sms"
        except Exception:
            pass

    msg = Message(
        tenant_id=tenant.id,
        sender_id=current_user.id,
        recipient_id=body.recipient_id,
        body=body.body,
        channel=channel,
        twilio_sid=twilio_sid,
    )
    db.add(msg)
    await db.commit()
    await db.refresh(msg)

    return MessageRead(
        id=msg.id,
        sender_id=msg.sender_id,
        recipient_id=msg.recipient_id,
        body=msg.body,
        channel=msg.channel,
        twilio_sid=msg.twilio_sid,
        read_at=None,
        created_at=msg.created_at.isoformat(),
        sender_name=current_user.full_name or current_user.email,
        sender_role=current_user.role,
    )


@router.get("/conversation/{other_user_id}", response_model=list[MessageRead])
async def get_conversation(
    other_user_id: uuid.UUID,
    tenant: CurrentTenant,
    current_user: CurrentUser,
    db: DBSession,
    page_size: int = Query(100, ge=1, le=200),
):
    """Ordered message thread between current user and another user. Marks received as read."""
    stmt = (
        select(Message)
        .where(
            Message.tenant_id == tenant.id,
            or_(
                and_(Message.sender_id == current_user.id, Message.recipient_id == other_user_id),
                and_(Message.sender_id == other_user_id, Message.recipient_id == current_user.id),
            ),
        )
        .order_by(Message.created_at.asc())
        .limit(page_size)
    )
    result = await db.execute(stmt)
    messages = result.scalars().all()

    user_ids = {m.sender_id for m in messages}
    ur = await db.execute(select(User).where(User.id.in_(user_ids)))
    user_map: dict[uuid.UUID, User] = {u.id: u for u in ur.scalars().all()}

    unread = [m.id for m in messages if m.recipient_id == current_user.id and not m.read_at]
    if unread:
        await db.execute(
            update(Message)
            .where(Message.id.in_(unread))
            .values(read_at=datetime.now(timezone.utc))
        )
        await db.commit()

    return [
        MessageRead(
            id=m.id,
            sender_id=m.sender_id,
            recipient_id=m.recipient_id,
            body=m.body,
            channel=m.channel,
            twilio_sid=m.twilio_sid,
            read_at=m.read_at.isoformat() if m.read_at else None,
            created_at=m.created_at.isoformat(),
            sender_name=user_map.get(m.sender_id, User()).full_name
                        or user_map.get(m.sender_id, User()).email,
            sender_role=user_map.get(m.sender_id, User()).role,
        )
        for m in messages
    ]


@router.get("/messages", response_model=list[MessageRead])
async def get_inbox(
    tenant: CurrentTenant,
    current_user: CurrentUser,
    db: DBSession,
    page_size: int = Query(50, ge=1, le=100),
):
    stmt = (
        select(Message)
        .where(
            Message.tenant_id == tenant.id,
            or_(
                Message.sender_id == current_user.id,
                Message.recipient_id == current_user.id,
            ),
        )
        .order_by(Message.created_at.desc())
        .limit(page_size)
    )
    result = await db.execute(stmt)
    messages = result.scalars().all()

    user_ids = {m.sender_id for m in messages}
    ur = await db.execute(select(User).where(User.id.in_(user_ids)))
    user_map = {u.id: u for u in ur.scalars().all()}

    return [
        MessageRead(
            id=m.id,
            sender_id=m.sender_id,
            recipient_id=m.recipient_id,
            body=m.body,
            channel=m.channel,
            twilio_sid=m.twilio_sid,
            read_at=m.read_at.isoformat() if m.read_at else None,
            created_at=m.created_at.isoformat(),
            sender_name=user_map.get(m.sender_id, User()).full_name
                        or user_map.get(m.sender_id, User()).email,
            sender_role=user_map.get(m.sender_id, User()).role,
        )
        for m in messages
    ]


@router.put("/messages/{message_id}/read")
async def mark_read(
    message_id: uuid.UUID,
    tenant: CurrentTenant,
    current_user: CurrentUser,
    db: DBSession,
):
    await db.execute(
        update(Message)
        .where(
            Message.id == message_id,
            Message.recipient_id == current_user.id,
            Message.tenant_id == tenant.id,
        )
        .values(read_at=datetime.now(timezone.utc))
    )
    await db.commit()
    return {"status": "ok"}


# ── Fleet location ────────────────────────────────────────────────────────────

@router.post("/location")
async def update_location(
    body: UpdateLocationRequest,
    tenant: CurrentTenant,
    current_user: CurrentUser,
    db: DBSession,
):
    """Driver pushes GPS position — upserts one row per driver."""
    if current_user.role not in ("driver", "admin", "superadmin"):
        raise HTTPException(status_code=403, detail="Only drivers may update location")

    stmt = (
        pg_insert(DriverLocation)
        .values(
            tenant_id=tenant.id,
            driver_id=current_user.id,
            lat=body.lat,
            lon=body.lon,
            speed_kmh=body.speed_kmh,
            status=body.status,
            custom_id=body.custom_id,
        )
        .on_conflict_do_update(
            constraint="uq_driver_locations_driver",
            set_={
                "lat": body.lat,
                "lon": body.lon,
                "speed_kmh": body.speed_kmh,
                "status": body.status,
                "custom_id": body.custom_id,
                "updated_at": datetime.now(timezone.utc),
            },
        )
    )
    await db.execute(stmt)
    await db.commit()
    return {"status": "ok", "lat": body.lat, "lon": body.lon}


@router.get("/fleet-positions", response_model=list[FleetPositionRead])
async def get_fleet_positions(
    tenant: CurrentTenant,
    current_user: CurrentUser,
    db: DBSession,
):
    """Hub operators and managers see all active driver GPS positions."""
    if current_user.role not in ("admin", "superadmin", "manager", "operator", "gatekeeper"):
        raise HTTPException(status_code=403, detail="Insufficient permissions")

    stmt = (
        select(DriverLocation, User)
        .join(User, DriverLocation.driver_id == User.id)
        .where(DriverLocation.tenant_id == tenant.id)
        .order_by(DriverLocation.updated_at.desc())
    )
    result = await db.execute(stmt)
    rows = result.all()

    return [
        FleetPositionRead(
            driver_id=str(row.DriverLocation.driver_id),
            driver_name=row.User.full_name or row.User.email,
            driver_email=row.User.email,
            lat=row.DriverLocation.lat,
            lon=row.DriverLocation.lon,
            speed_kmh=row.DriverLocation.speed_kmh,
            status=row.DriverLocation.status,
            custom_id=row.DriverLocation.custom_id,
            updated_at=row.DriverLocation.updated_at.isoformat(),
        )
        for row in rows
    ]


@router.get("/users-for-chat", response_model=list[dict])
async def users_for_chat(
    tenant: CurrentTenant,
    current_user: CurrentUser,
    db: DBSession,
):
    """Return contactable users based on RBAC role rules."""
    allowed: dict[str, list[str]] = {
        "driver":     ["manager", "admin", "superadmin", "gatekeeper"],
        "gatekeeper": ["driver", "manager", "admin", "superadmin"],
        "manager":    ["driver", "gatekeeper", "operator", "admin", "superadmin"],
        "admin":      ["driver", "gatekeeper", "operator", "manager", "superadmin"],
        "superadmin": ["driver", "gatekeeper", "operator", "manager", "admin"],
    }
    target_roles = allowed.get(current_user.role, [])
    if not target_roles:
        return []

    result = await db.execute(
        select(User, UserProfile)
        .outerjoin(UserProfile, User.id == UserProfile.user_id)
        .where(
            User.tenant_id == tenant.id,
            User.is_active == True,
            User.id != current_user.id,
            User.role.in_(target_roles),
        )
    )
    rows = result.all()

    def _custom_id(u: User) -> str:
        h = abs(hash(str(u.id))) % 9000 + 1000
        if u.role == "driver":               return f"DRV-OD-TRUCK-{h}"
        if u.role == "gatekeeper":           return f"HUB-751001-{h % 90 + 10:02d}"
        if u.role in ("manager", "admin"):   return f"MGR-QLOOP-L2-{h}"
        return f"USR-{h}"

    return [
        {
            "id": str(row.User.id),
            "name": row.User.full_name or row.User.email,
            "email": row.User.email,
            "role": row.User.role,
            "custom_id": _custom_id(row.User),
            "organization_name": row.UserProfile.organization_name if row.UserProfile else None,
        }
        for row in rows
    ]


# ── Legacy endpoints (backward-compatible) ────────────────────────────────────

@router.post("/call")
async def initiate_call(
    body: CallRequest,
    tenant: CurrentTenant,
    current_user: CurrentUser,
    db: DBSession,
):
    phone: str | None = None
    if body.recipient_user_id:
        r = await db.execute(
            select(User).where(User.id == body.recipient_user_id, User.tenant_id == tenant.id)
        )
        u = r.scalar_one_or_none()
        if u:
            phone = u.phone

    if not phone:
        return {"status": "simulated", "message": "No phone on file — call simulated."}

    try:
        sid = await twilio_service.make_masked_call(
            db=db, tenant_id=tenant.id, to_phone=phone,
            twiml_message=body.message_template or "Q-Loop logistics call.",
            recipient_id=body.recipient_user_id or current_user.id,
        )
        return {"call_sid": sid, "status": "initiated"}
    except Exception as e:
        return {"status": "simulated", "message": str(e)}


@router.post("/notify")
async def send_notification(
    body: NotifyRequest,
    tenant: CurrentTenant,
    current_user: CurrentUser,
    db: DBSession,
):
    phone = "+10000000000"
    if body.recipient_user_id:
        r = await db.execute(
            select(User).where(User.id == body.recipient_user_id, User.tenant_id == tenant.id)
        )
        u = r.scalar_one_or_none()
        if u and u.phone:
            phone = u.phone
    try:
        if body.channel == "voip":
            sid = await twilio_service.make_masked_call(
                db, tenant.id, phone, body.message,
                body.recipient_user_id or current_user.id)
        else:
            sid = await twilio_service.send_sms(
                db, tenant.id, phone, body.message,
                body.recipient_user_id or current_user.id)
        return {"twilio_sid": sid, "channel": body.channel,
                "status": "sent" if sid else "simulated"}
    except Exception:
        return {"status": "simulated", "channel": body.channel}


@router.get("/notifications", response_model=PaginatedResponse)
async def list_notifications(
    tenant: CurrentTenant,
    db: DBSession,
    _: CurrentUser,
    page: int = Query(1, ge=1),
    page_size: int = Query(20, ge=1, le=100),
):
    stmt = (
        select(Notification)
        .where(Notification.tenant_id == tenant.id)
        .order_by(Notification.created_at.desc())
    )
    return await paginate(db, stmt, page, page_size, NotificationRead)
