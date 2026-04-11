from __future__ import annotations

import uuid
from pathlib import Path

from fastapi import APIRouter, HTTPException, Query, UploadFile, status
from sqlalchemy import select

from app.core.config import settings
from app.dependencies import CurrentTenant, CurrentUser, DBSession, require_min_role
from app.models.ingestion import IngestionJob
from app.schemas.common import PaginatedResponse
from app.schemas.ingestion import IngestionJobCreate, IngestionJobRead, IngestionSourceType
from app.schemas.ingestion.base import IngestionErrorRead
from app.utils.pagination import paginate

router = APIRouter(prefix="/ingestion", tags=["ingestion"])


@router.post("/upload", response_model=IngestionJobRead, status_code=status.HTTP_202_ACCEPTED)
async def upload_csv(
    file: UploadFile,
    tenant: CurrentTenant,
    current_user: CurrentUser,
    db: DBSession,
    source_type: str | None = Query(None),
):
    """
    Upload a CSV file for background ingestion.
    Returns immediately with a job_id to track progress.
    Supported source_types: delivery_logistics | ecommerce_analytics | delivery_points
    """
    if not file.filename or not file.filename.lower().endswith(".csv"):
        raise HTTPException(status_code=400, detail="Only CSV files are supported.")

    contents = await file.read()
    file_size = len(contents)

    if file_size > settings.MAX_UPLOAD_SIZE_MB * 1024 * 1024:
        raise HTTPException(
            status_code=413,
            detail=f"File too large. Max size: {settings.MAX_UPLOAD_SIZE_MB}MB",
        )

    # Persist file to disk for the worker to read
    safe_name = f"{uuid.uuid4()}_{file.filename}"
    dest = settings.UPLOAD_DIR / safe_name
    dest.write_bytes(contents)

    # Create job record
    job = IngestionJob(
        tenant_id=tenant.id,
        uploaded_by=current_user.id,
        source_type=source_type or "custom",
        file_name=file.filename,
        file_size_bytes=file_size,
        status="pending",
    )
    db.add(job)
    await db.flush()

    # Enqueue background task
    from app.workers.ingestion_worker import ingest_file
    ingest_file.delay(
        job_id=str(job.id),
        tenant_id=str(tenant.id),
        file_path=str(dest),
        source_type=source_type,
    )

    return IngestionJobRead.model_validate(job)


@router.get("/jobs", response_model=PaginatedResponse)
async def list_jobs(
    tenant: CurrentTenant,
    db: DBSession,
    _: CurrentUser,
    page: int = Query(1, ge=1),
    page_size: int = Query(20, ge=1, le=100),
):
    stmt = (
        select(IngestionJob)
        .where(IngestionJob.tenant_id == tenant.id)
        .order_by(IngestionJob.created_at.desc())
    )
    return await paginate(db, stmt, page, page_size, IngestionJobRead)


@router.get("/jobs/{job_id}", response_model=IngestionJobRead)
async def get_job(job_id: uuid.UUID, tenant: CurrentTenant, db: DBSession, _: CurrentUser):
    result = await db.execute(
        select(IngestionJob).where(
            IngestionJob.id == job_id, IngestionJob.tenant_id == tenant.id
        )
    )
    job = result.scalar_one_or_none()
    if not job:
        raise HTTPException(status_code=404, detail="Ingestion job not found")
    return IngestionJobRead.model_validate(job)


@router.get("/jobs/{job_id}/errors", response_model=PaginatedResponse)
async def get_job_errors(
    job_id: uuid.UUID,
    tenant: CurrentTenant,
    db: DBSession,
    _: CurrentUser,
    page: int = Query(1, ge=1),
    page_size: int = Query(50, ge=1, le=200),
):
    from app.models.ingestion import IngestionError
    stmt = (
        select(IngestionError)
        .where(IngestionError.job_id == job_id)
        .order_by(IngestionError.row_number)
    )
    return await paginate(db, stmt, page, page_size, IngestionErrorRead)


@router.delete("/jobs/{job_id}", status_code=status.HTTP_204_NO_CONTENT,
               dependencies=[require_min_role("admin")])
async def delete_job(job_id: uuid.UUID, tenant: CurrentTenant, db: DBSession):
    result = await db.execute(
        select(IngestionJob).where(
            IngestionJob.id == job_id, IngestionJob.tenant_id == tenant.id
        )
    )
    job = result.scalar_one_or_none()
    if not job:
        raise HTTPException(status_code=404, detail="Ingestion job not found")
    await db.delete(job)
