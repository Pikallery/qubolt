from __future__ import annotations

from typing import Any

from fastapi import Query
from sqlalchemy import Select, func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.schemas.common import PaginatedResponse


async def paginate(
    db: AsyncSession,
    stmt: Select,
    page: int,
    page_size: int,
    schema_class: type,
) -> PaginatedResponse:
    # Count total
    count_stmt = select(func.count()).select_from(stmt.subquery())
    total = (await db.execute(count_stmt)).scalar_one()

    # Fetch page
    offset = (page - 1) * page_size
    items_result = await db.execute(stmt.offset(offset).limit(page_size))
    rows = items_result.scalars().all()

    return PaginatedResponse(
        items=[schema_class.model_validate(r) for r in rows],
        total=total,
        page=page,
        page_size=page_size,
        has_next=(offset + len(rows)) < total,
    )
