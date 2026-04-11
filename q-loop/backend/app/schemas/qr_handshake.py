from __future__ import annotations

import uuid
from datetime import datetime

from pydantic import BaseModel, ConfigDict


class QRPayload(BaseModel):
    """Payload embedded in the QR code (signed via HMAC-SHA256)."""
    token_id: str         # UUID of qr_tokens row
    shipment_id: str
    tenant_id: str
    issued_at: int        # Unix timestamp
    expires_at: int       # Unix timestamp
    signature: str        # HMAC of the above fields


class QRScanEvent(BaseModel):
    """Sent by mobile client when scanning a QR code."""
    token_hash: str       # HMAC from the QR payload
    scan_lat: float | None = None
    scan_lon: float | None = None


class HandshakeResult(BaseModel):
    success: bool
    shipment_id: uuid.UUID | None = None
    event_type: str | None = None   # picked_up | delivered | exception
    message: str = ""
    scanned_at: datetime | None = None


class QRTokenRead(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: uuid.UUID
    shipment_id: uuid.UUID
    expires_at: datetime
    scanned_at: datetime | None
    is_valid: bool
