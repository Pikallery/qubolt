"""
Celery task: run CSV ingestion in the background.

The API endpoint saves the file to disk, creates an IngestionJob row,
then enqueues this task. The task opens the file, runs the pipeline,
and updates the job record on completion.
"""
from __future__ import annotations

import asyncio
import uuid
from pathlib import Path

from app.workers.celery_app import celery_app


@celery_app.task(name="app.workers.ingestion_worker.ingest_file", bind=True, max_retries=2)
def ingest_file(self, job_id: str, tenant_id: str, file_path: str, source_type: str | None = None):
    """
    Background CSV ingestion task.

    Args:
        job_id: UUID string of the IngestionJob row
        tenant_id: UUID string of the tenant
        file_path: Absolute path to the uploaded CSV file
        source_type: Optional override; auto-detected if None
    """
    try:
        asyncio.run(_run_async(job_id, tenant_id, file_path, source_type))
    except Exception as exc:
        # Retry with exponential backoff
        raise self.retry(exc=exc, countdown=30 * (self.request.retries + 1))


async def _run_async(
    job_id: str,
    tenant_id: str,
    file_path: str,
    source_type: str | None,
) -> None:
    from app.core.database import AsyncSessionLocal
    from app.services.ingestion_service import run_ingestion
    from sqlalchemy import update
    from app.models.ingestion import IngestionJob

    path = Path(file_path)
    if not path.exists():
        async with AsyncSessionLocal() as db:
            await db.execute(
                update(IngestionJob)
                .where(IngestionJob.id == uuid.UUID(job_id))
                .values(status="failed", error_summary={"error": f"File not found: {file_path}"})
            )
            await db.commit()
        return

    file_bytes = path.read_bytes()

    async with AsyncSessionLocal() as db:
        await run_ingestion(
            db=db,
            job_id=uuid.UUID(job_id),
            tenant_id=uuid.UUID(tenant_id),
            file_bytes=file_bytes,
            source_type=source_type,
        )

    # Clean up temp file
    try:
        path.unlink()
    except OSError:
        pass
