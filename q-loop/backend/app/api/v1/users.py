from __future__ import annotations

import uuid

from fastapi import APIRouter, HTTPException, Query, status
from sqlalchemy import select

from app.dependencies import CurrentTenant, CurrentUser, DBSession, require_min_role
from app.schemas.common import PaginatedResponse
from app.schemas.user import UserCreate, UserRead, UserUpdate
from app.services.auth_service import create_user
from app.utils.pagination import paginate
from app.models.user import User

router = APIRouter(prefix="/users", tags=["users"])


@router.get("", response_model=PaginatedResponse, dependencies=[require_min_role("admin")])
async def list_users(
    tenant: CurrentTenant,
    db: DBSession,
    page: int = Query(1, ge=1),
    page_size: int = Query(20, ge=1, le=100),
):
    stmt = select(User).where(User.tenant_id == tenant.id).order_by(User.created_at.desc())
    return await paginate(db, stmt, page, page_size, UserRead)


@router.post("", response_model=UserRead, status_code=status.HTTP_201_CREATED,
             dependencies=[require_min_role("admin")])
async def create(body: UserCreate, tenant: CurrentTenant, db: DBSession):
    user = await create_user(
        db, tenant.id, body.email, body.password, body.full_name, body.phone, body.role
    )
    return UserRead.model_validate(user)


@router.get("/me", response_model=UserRead)
async def get_me(current_user: CurrentUser):
    return UserRead.model_validate(current_user)


@router.get("/{user_id}", response_model=UserRead, dependencies=[require_min_role("admin")])
async def get_user(user_id: uuid.UUID, tenant: CurrentTenant, db: DBSession):
    result = await db.execute(
        select(User).where(User.id == user_id, User.tenant_id == tenant.id)
    )
    user = result.scalar_one_or_none()
    if not user:
        raise HTTPException(status_code=404, detail="User not found")
    return UserRead.model_validate(user)


@router.patch("/{user_id}", response_model=UserRead, dependencies=[require_min_role("admin")])
async def update_user(user_id: uuid.UUID, body: UserUpdate, tenant: CurrentTenant, db: DBSession):
    result = await db.execute(
        select(User).where(User.id == user_id, User.tenant_id == tenant.id)
    )
    user = result.scalar_one_or_none()
    if not user:
        raise HTTPException(status_code=404, detail="User not found")
    for field, value in body.model_dump(exclude_unset=True).items():
        setattr(user, field, value)
    await db.flush()
    return UserRead.model_validate(user)
