"""
FastAPI dependency injection: DB session, JWT auth, tenant resolution, role guards.
"""
from __future__ import annotations

import uuid
from collections.abc import AsyncGenerator
from typing import Annotated

from fastapi import Depends, Header, HTTPException, Security, status
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from jose import JWTError
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.database import get_db
from app.core.security import decode_access_token
from app.models.tenant import Tenant
from app.models.user import User

bearer = HTTPBearer(auto_error=False)

# Re-export for convenience
DBSession = Annotated[AsyncSession, Depends(get_db)]


# ── Token claims ──────────────────────────────────────────────────────────────

async def get_current_claims(
    credentials: Annotated[HTTPAuthorizationCredentials | None, Depends(bearer)],
) -> dict:
    if not credentials:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Not authenticated")
    try:
        return decode_access_token(credentials.credentials)
    except JWTError as e:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail=str(e))


ClaimsDepend = Annotated[dict, Depends(get_current_claims)]


# ── Current user ──────────────────────────────────────────────────────────────

async def get_current_user(
    claims: ClaimsDepend,
    db: DBSession,
) -> User:
    user_id = claims.get("sub")
    if not user_id:
        raise HTTPException(status_code=401, detail="Invalid token payload")

    result = await db.execute(
        select(User).where(User.id == uuid.UUID(user_id), User.is_active == True)
    )
    user = result.scalar_one_or_none()
    if not user:
        raise HTTPException(status_code=401, detail="User not found or deactivated")
    return user


CurrentUser = Annotated[User, Depends(get_current_user)]


# ── Tenant ────────────────────────────────────────────────────────────────────

async def get_current_tenant(
    current_user: CurrentUser,
    db: DBSession,
) -> Tenant:
    result = await db.execute(
        select(Tenant).where(Tenant.id == current_user.tenant_id, Tenant.is_active == True)
    )
    tenant = result.scalar_one_or_none()
    if not tenant:
        raise HTTPException(status_code=404, detail="Tenant not found or deactivated")
    return tenant


CurrentTenant = Annotated[Tenant, Depends(get_current_tenant)]


async def get_tenant_for_login(
    db: DBSession,
    x_tenant_id: str | None = Header(default=None, alias="X-Tenant-ID"),
) -> Tenant:
    """
    Resolve tenant WITHOUT requiring a JWT — used only by the /login endpoint.
    Clients must pass their Tenant UUID in the X-Tenant-ID header.
    """
    if not x_tenant_id:
        raise HTTPException(
            status_code=400,
            detail="X-Tenant-ID header is required for login.",
        )
    try:
        tid = uuid.UUID(x_tenant_id)
    except ValueError:
        raise HTTPException(status_code=400, detail="X-Tenant-ID must be a valid UUID.")

    result = await db.execute(
        select(Tenant).where(Tenant.id == tid, Tenant.is_active == True)
    )
    tenant = result.scalar_one_or_none()
    if not tenant:
        raise HTTPException(status_code=404, detail="Tenant not found.")
    return tenant


LoginTenant = Annotated[Tenant, Depends(get_tenant_for_login)]


# ── Role guards ───────────────────────────────────────────────────────────────

ROLE_HIERARCHY = {
    "superadmin": 100,
    "admin": 80,
    "operator": 60,
    "gatekeeper": 40,
    "driver": 40,
    "viewer": 20,
}


def require_role(*roles: str):
    """Returns a dependency that enforces the user has one of the given roles."""
    async def _check(current_user: CurrentUser) -> User:
        if current_user.role not in roles and current_user.role != "superadmin":
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail=f"Role '{current_user.role}' not permitted. Required: {roles}",
            )
        return current_user
    return Depends(_check)


def require_min_role(min_role: str):
    """Returns a dependency enforcing user role >= min_role in hierarchy."""
    min_level = ROLE_HIERARCHY.get(min_role, 0)

    async def _check(current_user: CurrentUser) -> User:
        user_level = ROLE_HIERARCHY.get(current_user.role, 0)
        if user_level < min_level:
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail=f"Insufficient permissions. Required minimum role: {min_role}",
            )
        return current_user
    return Depends(_check)
