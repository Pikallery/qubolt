from __future__ import annotations

import re
import uuid
from typing import Literal

from fastapi import APIRouter, HTTPException, Request, Response, status
from pydantic import BaseModel, field_validator

from app.dependencies import CurrentTenant, CurrentUser, DBSession, LoginTenant
from app.schemas.common import MessageResponse, TokenResponse
from app.schemas.qr_handshake import HandshakeResult, QRScanEvent
from app.services import auth_service, qr_service

router = APIRouter(prefix="/auth", tags=["auth"])

_E164_RE = re.compile(r"^\+[1-9]\d{7,14}$")


class LoginRequest(BaseModel):
    email: str
    password: str


class RefreshRequest(BaseModel):
    refresh_token: str


class SendOtpRequest(BaseModel):
    phone: str

    @field_validator("phone")
    @classmethod
    def validate_phone(cls, v: str) -> str:
        if not _E164_RE.match(v):
            raise ValueError("Phone must be E.164 format, e.g. +919876543210")
        return v


class SignupRequest(BaseModel):
    email: str
    password: str
    full_name: str
    phone: str
    role: Literal["driver", "gatekeeper", "manager"]
    otp_code: str

    # Driver
    license_number: str | None = None
    vehicle_type: Literal["bike", "three_wheeler", "van", "truck"] | None = None

    # Gatekeeper
    assigned_hub_id: str | None = None  # Odisha pincode
    hub_name: str | None = None

    # Manager
    organization_name: str | None = None

    @field_validator("password")
    @classmethod
    def password_strength(cls, v: str) -> str:
        if len(v) < 8:
            raise ValueError("Password must be at least 8 characters")
        return v

    @field_validator("phone")
    @classmethod
    def validate_phone(cls, v: str) -> str:
        if not _E164_RE.match(v):
            raise ValueError("Phone must be E.164 format, e.g. +919876543210")
        return v


# ── Endpoints ──────────────────────────────────────────────────────────────────

@router.post("/login", response_model=TokenResponse)
async def login(body: LoginRequest, tenant: LoginTenant, db: DBSession):
    """Login with email + password. Returns access + refresh tokens."""
    try:
        return await auth_service.login(db, tenant.id, body.email, body.password)
    except auth_service.AuthError as e:
        raise HTTPException(status_code=e.status_code, detail=e.detail)


@router.post("/send-otp", response_model=dict)
async def send_otp(body: SendOtpRequest, tenant: LoginTenant):
    """
    Send a 6-digit OTP to *phone* for signup verification.

    Returns `{"mock": true, "code": "..."}` when Twilio is not configured
    (development mode). In production the code is sent via SMS only.
    """
    return await auth_service.send_otp(body.phone)


@router.post("/signup", response_model=TokenResponse, status_code=status.HTTP_201_CREATED)
async def signup(body: SignupRequest, tenant: LoginTenant, db: DBSession):
    """
    Register a new user with role-specific profile.
    The phone number must be verified via /auth/send-otp before calling this.

    Roles:
    - driver     → requires license_number, vehicle_type
    - gatekeeper → requires assigned_hub_id (Odisha pincode)
    - manager    → requires organization_name
    """
    # Validate OTP
    if not auth_service.verify_otp(body.phone, body.otp_code):
        raise HTTPException(status_code=422, detail="Invalid or expired OTP")

    # Role-specific field validation
    if body.role == "driver":
        if not body.license_number or not body.vehicle_type:
            raise HTTPException(status_code=422, detail="Drivers must provide license_number and vehicle_type")
    elif body.role == "gatekeeper":
        if not body.assigned_hub_id:
            raise HTTPException(status_code=422, detail="Gatekeepers must provide assigned_hub_id (Odisha pincode)")
    elif body.role == "manager":
        if not body.organization_name:
            raise HTTPException(status_code=422, detail="Managers must provide organization_name")

    try:
        user = await auth_service.signup_user(
            db=db,
            tenant_id=tenant.id,
            email=body.email,
            password=body.password,
            full_name=body.full_name,
            phone=body.phone,
            role=body.role,
            license_number=body.license_number,
            vehicle_type=body.vehicle_type,
            assigned_hub_id=body.assigned_hub_id,
            hub_name=body.hub_name,
            organization_name=body.organization_name,
        )
    except auth_service.AuthError as e:
        raise HTTPException(status_code=e.status_code, detail=e.detail)

    # Auto-login after signup
    return await auth_service.login(db, tenant.id, body.email, body.password)


@router.post("/refresh", response_model=TokenResponse)
async def refresh(body: RefreshRequest, db: DBSession):
    """Rotate refresh token. Returns new access + refresh pair."""
    try:
        return await auth_service.refresh_tokens(db, body.refresh_token)
    except auth_service.AuthError as e:
        raise HTTPException(status_code=e.status_code, detail=e.detail)


@router.post("/logout", response_model=MessageResponse)
async def logout(current_user: CurrentUser, db: DBSession):
    """Invalidate the current refresh token."""
    await auth_service.logout(db, current_user.id)
    return MessageResponse(message="Logged out successfully")


@router.post("/qr-scan", response_model=HandshakeResult)
async def qr_scan(body: QRScanEvent, current_user: CurrentUser, db: DBSession):
    """
    3-way handshake: Gatekeeper/Driver scans a QR code.
    Validates token, marks shipment as picked_up, emits ShipmentEvent.
    """
    result = await qr_service.validate_scan(
        db=db,
        token_hash=body.token_hash,
        scanned_by=current_user.id,
        scan_lat=body.scan_lat,
        scan_lon=body.scan_lon,
    )
    return result


@router.get("/qr-generate/{shipment_id}", response_class=Response)
async def generate_qr(
    shipment_id: uuid.UUID,
    current_user: CurrentUser,
    tenant: CurrentTenant,
    db: DBSession,
):
    """Generate a QR code PNG for a shipment handshake. Expires in 5 minutes."""
    png_bytes = await qr_service.generate_qr(
        db=db,
        shipment_id=shipment_id,
        tenant_id=tenant.id,
        issued_to=current_user.id,
    )
    return Response(content=png_bytes, media_type="image/png")
