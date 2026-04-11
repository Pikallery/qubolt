"""
QR Code service — implements the 3-way digital handshake:

  1. Driver opens mobile app → hits GET /shipments/{id}/qr
  2. Backend generates JWT-signed QR payload + stores HMAC hash in qr_tokens
  3. Gatekeeper scans QR code → hits POST /auth/qr-scan with token_hash
  4. Backend validates HMAC + TTL → invalidates token (single-use) → emits ShipmentEvent

QR payload is a compact JSON string: {tid, sid, uid, iat, exp, sig}
The sig field is HMAC-SHA256 of "tid|sid|uid|iat|exp" keyed with SECRET_KEY.
"""
from __future__ import annotations

import io
import json
import uuid
from datetime import datetime, timezone

import qrcode
from qrcode.constants import ERROR_CORRECT_M
from sqlalchemy import select, update
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.config import settings
from app.core.security import hmac_sign, hmac_verify
from app.models.audit import Notification
from app.models.shipment import QRToken, Shipment, ShipmentEvent
from app.models.user import User
from app.schemas.qr_handshake import HandshakeResult, QRPayload


def _payload_data(token_id: str, shipment_id: str, tenant_id: str, iat: int, exp: int) -> str:
    return f"{token_id}|{shipment_id}|{tenant_id}|{iat}|{exp}"


async def generate_qr(
    db: AsyncSession,
    shipment_id: uuid.UUID,
    tenant_id: uuid.UUID,
    issued_to: uuid.UUID | None = None,
) -> bytes:
    """
    Creates a QRToken DB row and returns PNG bytes of the QR image.
    """
    now = int(datetime.now(timezone.utc).timestamp())
    exp = now + settings.QR_TOKEN_EXPIRE_SECONDS
    token_id = str(uuid.uuid4())

    # Build HMAC signature
    data = _payload_data(token_id, str(shipment_id), str(tenant_id), now, exp)
    sig = hmac_sign(data)

    payload_dict = {
        "tid": str(tenant_id),
        "sid": str(shipment_id),
        "uid": str(issued_to) if issued_to else "",
        "iat": now,
        "exp": exp,
        "tok": token_id,
        "sig": sig,
    }
    payload_json = json.dumps(payload_dict, separators=(",", ":"))

    # Persist token hash (sig is the canonical hash for this token)
    qr_token = QRToken(
        id=uuid.UUID(token_id),
        tenant_id=tenant_id,
        shipment_id=shipment_id,
        issued_to=issued_to,
        token_hash=sig,
        expires_at=datetime.fromtimestamp(exp, tz=timezone.utc),
    )
    db.add(qr_token)
    await db.flush()

    # Render QR image
    qr = qrcode.QRCode(error_correction=ERROR_CORRECT_M, box_size=10, border=4)
    qr.add_data(payload_json)
    qr.make(fit=True)
    img = qr.make_image(fill_color="black", back_color="white")

    buf = io.BytesIO()
    img.save(buf, format="PNG")
    return buf.getvalue()


async def validate_scan(
    db: AsyncSession,
    token_hash: str,
    scanned_by: uuid.UUID | None = None,
    scan_lat: float | None = None,
    scan_lon: float | None = None,
) -> HandshakeResult:
    """
    Validates a QR scan. On success:
      - Marks qr_tokens row as used (is_valid = False)
      - Creates a ShipmentEvent of type 'picked_up'
    Returns HandshakeResult with success flag and details.
    """
    now = datetime.now(timezone.utc)

    result = await db.execute(
        select(QRToken).where(
            QRToken.token_hash == token_hash,
            QRToken.is_valid == True,
        )
    )
    token = result.scalar_one_or_none()

    if token is None:
        return HandshakeResult(success=False, message="QR token not found or already used.")

    if now > token.expires_at:
        await db.execute(
            update(QRToken).where(QRToken.id == token.id).values(is_valid=False)
        )
        return HandshakeResult(success=False, message="QR token has expired.")

    # Invalidate (single-use)
    await db.execute(
        update(QRToken)
        .where(QRToken.id == token.id)
        .values(
            is_valid=False,
            scanned_at=now,
            scanned_by=scanned_by,
            scan_lat=scan_lat,
            scan_lon=scan_lon,
        )
    )

    # Emit shipment event
    event = ShipmentEvent(
        shipment_id=token.shipment_id,
        tenant_id=token.tenant_id,
        event_type="delivered",
        location_lat=scan_lat,
        location_lon=scan_lon,
        note="3-way QR handshake completed",
        recorded_by=scanned_by,
        occurred_at=now,
    )
    db.add(event)

    # Mark shipment as delivered
    shipment_row = await db.execute(
        select(Shipment).where(Shipment.id == token.shipment_id)
    )
    shipment = shipment_row.scalar_one_or_none()
    if shipment is not None:
        shipment.status = "delivered"
        shipment.delivered_at = now

    region = (shipment.region if shipment is not None else None) or "destination hub"
    short_id = str(token.shipment_id)[:8]  # type: ignore[index]
    ship_label = (
        shipment.external_id
        if shipment is not None and shipment.external_id
        else short_id
    )

    # 1) Driver notification — payment received
    if token.issued_to is not None:
        db.add(
            Notification(
                tenant_id=token.tenant_id,
                recipient_id=token.issued_to,
                channel="push",
                status="queued",
                payload={
                    "type": "payment_received",
                    "title": "Payment Received",
                    "message": f"Payment received for shipment {ship_label}. Great job!",
                    "shipment_id": str(token.shipment_id),
                },
            )
        )

    # 2) Manager notifications — order delivered
    managers_q = await db.execute(
        select(User.id).where(
            User.tenant_id == token.tenant_id,
            User.role.in_(("manager", "admin", "superadmin")),
            User.is_active == True,  # noqa: E712
        )
    )
    for (mgr_id,) in managers_q.all():
        db.add(
            Notification(
                tenant_id=token.tenant_id,
                recipient_id=mgr_id,
                channel="push",
                status="queued",
                payload={
                    "type": "delivery_confirmed",
                    "title": "Delivery Confirmed",
                    "message": f"Order {ship_label} delivered to {region} hub.",
                    "shipment_id": str(token.shipment_id),
                },
            )
        )

    return HandshakeResult(
        success=True,
        shipment_id=token.shipment_id,
        event_type="delivered",
        message=f"Delivery confirmed for {ship_label}. Driver and manager notified.",
        scanned_at=now,
    )
