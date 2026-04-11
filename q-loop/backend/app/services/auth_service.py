from __future__ import annotations

import random
import time
import uuid
from datetime import datetime, timezone

from jose import JWTError
from sqlalchemy import select, update
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.security import (
    create_access_token,
    create_refresh_token,
    decode_access_token,
    hash_password,
    hash_refresh_token,
    verify_password,
)
from app.models.user import User
from app.models.user_profile import UserProfile
from app.schemas.common import TokenResponse
from app.core.config import settings

# ── In-memory OTP store ────────────────────────────────────────────────────────
# {phone: {"code": "123456", "expires": float_timestamp}}
_otp_store: dict[str, dict] = {}
_OTP_TTL = 300  # 5 minutes


def _gen_otp() -> str:
    return f"{random.randint(100_000, 999_999)}"


async def send_otp(phone: str) -> dict:
    """
    Generate and dispatch a 6-digit OTP to *phone* (E.164).

    If Twilio credentials are configured, sends a real SMS.
    Otherwise returns {"mock": True, "code": "<otp>"} for dev/testing.
    """
    code = _gen_otp()
    _otp_store[phone] = {"code": code, "expires": time.monotonic() + _OTP_TTL}

    if settings.TWILIO_ACCOUNT_SID and settings.TWILIO_AUTH_TOKEN and settings.TWILIO_PHONE_NUMBER:
        try:
            from twilio.rest import Client  # type: ignore[import]
            client = Client(settings.TWILIO_ACCOUNT_SID, settings.TWILIO_AUTH_TOKEN)
            client.messages.create(
                to=phone,
                from_=settings.TWILIO_PHONE_NUMBER,
                body=f"Your Q-Loop verification code is: {code}. Valid for 5 minutes.",
            )
            return {"mock": False, "message": "OTP sent via SMS"}
        except Exception as exc:  # noqa: BLE001
            # Fall through to mock on Twilio failure
            pass

    return {"mock": True, "code": code, "message": "Dev mode — use this code to verify"}


def verify_otp(phone: str, code: str) -> bool:
    """Return True and consume the OTP if valid; False otherwise."""
    record = _otp_store.get(phone)
    if not record:
        return False
    if time.monotonic() > record["expires"]:
        _otp_store.pop(phone, None)
        return False
    if record["code"] != code:
        return False
    _otp_store.pop(phone, None)
    return True


class AuthError(Exception):
    def __init__(self, detail: str, status_code: int = 401):
        self.detail = detail
        self.status_code = status_code
        super().__init__(detail)


async def authenticate_user(
    db: AsyncSession, tenant_id: uuid.UUID, email: str, password: str
) -> User:
    result = await db.execute(
        select(User).where(User.tenant_id == tenant_id, User.email == email, User.is_active == True)
    )
    user = result.scalar_one_or_none()
    if not user or not verify_password(password, user.hashed_password):
        raise AuthError("Invalid credentials")
    return user


async def login(db: AsyncSession, tenant_id: uuid.UUID, email: str, password: str) -> TokenResponse:
    user = await authenticate_user(db, tenant_id, email, password)

    access = create_access_token(str(user.id), str(user.tenant_id), user.role)
    raw_refresh, hashed_refresh = create_refresh_token()

    # Store hashed refresh token and update last_login_at
    await db.execute(
        update(User)
        .where(User.id == user.id)
        .values(
            refresh_token_hash=hashed_refresh,
            last_login_at=datetime.now(timezone.utc),
        )
    )

    return TokenResponse(
        access_token=access,
        refresh_token=raw_refresh,
        expires_in=settings.ACCESS_TOKEN_EXPIRE_MINUTES * 60,
    )


async def refresh_tokens(db: AsyncSession, raw_refresh: str) -> TokenResponse:
    hashed = hash_refresh_token(raw_refresh)
    result = await db.execute(
        select(User).where(User.refresh_token_hash == hashed, User.is_active == True)
    )
    user = result.scalar_one_or_none()
    if not user:
        raise AuthError("Invalid or expired refresh token")

    access = create_access_token(str(user.id), str(user.tenant_id), user.role)
    raw_new, hashed_new = create_refresh_token()

    await db.execute(
        update(User).where(User.id == user.id).values(refresh_token_hash=hashed_new)
    )

    return TokenResponse(
        access_token=access,
        refresh_token=raw_new,
        expires_in=settings.ACCESS_TOKEN_EXPIRE_MINUTES * 60,
    )


async def logout(db: AsyncSession, user_id: uuid.UUID) -> None:
    await db.execute(
        update(User).where(User.id == user_id).values(refresh_token_hash=None)
    )


def decode_token_claims(token: str) -> dict:
    try:
        return decode_access_token(token)
    except JWTError as e:
        raise AuthError(str(e))


async def create_user(
    db: AsyncSession,
    tenant_id: uuid.UUID,
    email: str,
    password: str,
    full_name: str | None = None,
    phone: str | None = None,
    role: str = "operator",
) -> User:
    user = User(
        tenant_id=tenant_id,
        email=email,
        hashed_password=hash_password(password),
        full_name=full_name,
        phone=phone,
        role=role,
    )
    db.add(user)
    await db.flush()
    return user


async def signup_user(
    db: AsyncSession,
    tenant_id: uuid.UUID,
    email: str,
    password: str,
    full_name: str,
    phone: str,
    role: str,
    # Driver
    license_number: str | None = None,
    vehicle_type: str | None = None,
    # Gatekeeper
    assigned_hub_id: str | None = None,
    hub_name: str | None = None,
    # Manager
    organization_name: str | None = None,
) -> User:
    """Create a user + role-specific profile in one transaction."""
    # Check for duplicate email within tenant
    existing = await db.execute(
        select(User).where(User.tenant_id == tenant_id, User.email == email)
    )
    if existing.scalar_one_or_none():
        raise AuthError("Email already registered", status_code=409)

    user = User(
        tenant_id=tenant_id,
        email=email,
        hashed_password=hash_password(password),
        full_name=full_name,
        phone=phone,
        role=role,
    )
    db.add(user)
    await db.flush()  # get user.id

    profile = UserProfile(
        user_id=user.id,
        license_number=license_number,
        vehicle_type=vehicle_type,
        assigned_hub_id=assigned_hub_id,
        hub_name=hub_name,
        organization_name=organization_name,
    )
    db.add(profile)
    await db.flush()
    return user
