"""
Twilio masked VoIP + SMS service.

All phone numbers are masked — drivers and customers never see each other's
real numbers. Twilio proxies the call through a Q-Loop owned number.
Calls are logged to the notifications table for audit.
"""
from __future__ import annotations

import uuid
from datetime import datetime, timezone

from sqlalchemy.ext.asyncio import AsyncSession
from twilio.rest import Client

from app.core.config import settings
from app.models.audit import Notification

_client: Client | None = None


def _get_client() -> Client:
    global _client
    if _client is None:
        if not settings.TWILIO_ACCOUNT_SID or not settings.TWILIO_AUTH_TOKEN:
            raise RuntimeError("Twilio credentials not configured.")
        _client = Client(settings.TWILIO_ACCOUNT_SID, settings.TWILIO_AUTH_TOKEN)
    return _client


async def _log_notification(
    db: AsyncSession,
    tenant_id: uuid.UUID,
    recipient_id: uuid.UUID | None,
    channel: str,
    payload: dict,
    twilio_sid: str | None,
    status: str,
) -> None:
    notif = Notification(
        tenant_id=tenant_id,
        recipient_id=recipient_id,
        channel=channel,
        payload=payload,
        twilio_sid=twilio_sid,
        status=status,
        sent_at=datetime.now(timezone.utc) if status == "sent" else None,
    )
    db.add(notif)
    await db.flush()


async def make_masked_call(
    db: AsyncSession,
    tenant_id: uuid.UUID,
    to_phone: str,
    twiml_message: str = "Your delivery driver is on the way. Press 1 to connect.",
    recipient_id: uuid.UUID | None = None,
) -> str | None:
    """
    Initiates a masked VoIP call via Twilio.
    Returns call_sid on success, None if Twilio is not configured.
    """
    if not settings.TWILIO_ACCOUNT_SID:
        # Dev fallback: log without actually calling
        await _log_notification(
            db, tenant_id, recipient_id, "voip",
            {"to": to_phone, "message": twiml_message},
            None, "simulated"
        )
        return None

    try:
        client = _get_client()
        twiml = f"<Response><Say>{twiml_message}</Say></Response>"
        call = client.calls.create(
            to=to_phone,
            from_=settings.TWILIO_PHONE_NUMBER,
            twiml=twiml,
        )
        await _log_notification(
            db, tenant_id, recipient_id, "voip",
            {"to": to_phone, "call_sid": call.sid},
            call.sid, "sent"
        )
        return call.sid
    except Exception as exc:
        await _log_notification(
            db, tenant_id, recipient_id, "voip",
            {"to": to_phone, "error": str(exc)},
            None, "failed"
        )
        # Fallback to SMS
        return await send_sms(db, tenant_id, to_phone, twiml_message, recipient_id)


async def send_sms(
    db: AsyncSession,
    tenant_id: uuid.UUID,
    to_phone: str,
    body: str,
    recipient_id: uuid.UUID | None = None,
) -> str | None:
    """
    Sends an SMS via Twilio. Returns message_sid on success.
    """
    if not settings.TWILIO_ACCOUNT_SID:
        await _log_notification(
            db, tenant_id, recipient_id, "sms",
            {"to": to_phone, "body": body},
            None, "simulated"
        )
        return None

    try:
        client = _get_client()
        msg = client.messages.create(
            to=to_phone,
            from_=settings.TWILIO_PHONE_NUMBER,
            body=body,
        )
        await _log_notification(
            db, tenant_id, recipient_id, "sms",
            {"to": to_phone, "body": body, "message_sid": msg.sid},
            msg.sid, "sent"
        )
        return msg.sid
    except Exception as exc:
        await _log_notification(
            db, tenant_id, recipient_id, "sms",
            {"to": to_phone, "error": str(exc)},
            None, "failed"
        )
        return None


async def notify_delivery_event(
    db: AsyncSession,
    tenant_id: uuid.UUID,
    to_phone: str,
    event_type: str,
    shipment_id: uuid.UUID,
    recipient_id: uuid.UUID | None = None,
    use_voip: bool = False,
) -> None:
    """
    High-level helper: notifies customer/driver of a shipment event.
    Selects VoIP or SMS based on use_voip flag.
    """
    messages = {
        "picked_up": "Your order has been picked up and is on its way.",
        "in_transit": "Your delivery is in transit and will arrive soon.",
        "delivered": "Your order has been delivered. Thank you for choosing Q-Loop.",
        "failed": "We were unable to deliver your order. Our team will contact you shortly.",
        "exception": "There is an update regarding your delivery. Please check your Q-Loop app.",
    }
    body = messages.get(event_type, f"Update on shipment {shipment_id}: {event_type}")

    if use_voip:
        await make_masked_call(db, tenant_id, to_phone, body, recipient_id)
    else:
        await send_sms(db, tenant_id, to_phone, body, recipient_id)
