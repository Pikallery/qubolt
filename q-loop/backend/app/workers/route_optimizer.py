"""
Celery task: run Simulated Annealing route optimization in the background.
"""
from __future__ import annotations

import asyncio
import uuid

from app.workers.celery_app import celery_app


@celery_app.task(name="app.workers.route_optimizer.optimize_route_task", bind=True, max_retries=1)
def optimize_route_task(
    self,
    route_id: str,
    tenant_id: str,
    initial_temp: float | None = None,
    cooling_rate: float | None = None,
    max_iterations: int | None = None,
) -> dict:
    """
    Run SA optimization for a route. Returns result dict.
    """
    try:
        return asyncio.run(_run_async(route_id, tenant_id, initial_temp, cooling_rate, max_iterations))
    except Exception as exc:
        raise self.retry(exc=exc, countdown=10)


async def _run_async(
    route_id: str,
    tenant_id: str,
    initial_temp: float | None,
    cooling_rate: float | None,
    max_iterations: int | None,
) -> dict:
    from app.core.database import AsyncSessionLocal
    from app.services.routing_service import optimize_route

    async with AsyncSessionLocal() as db:
        result = await optimize_route(
            db=db,
            route_id=uuid.UUID(route_id),
            initial_temp=initial_temp,
            cooling_rate=cooling_rate,
            max_iterations=max_iterations,
        )
        await db.commit()
        return result
