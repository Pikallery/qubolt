from celery import Celery
from app.core.config import settings

celery_app = Celery(
    "q_loop",
    broker=settings.CELERY_BROKER_URL,
    backend=settings.CELERY_RESULT_BACKEND,
    include=[
        "app.workers.ingestion_worker",
        "app.workers.route_optimizer",
    ],
)

celery_app.conf.update(
    task_serializer="json",
    result_serializer="json",
    accept_content=["json"],
    timezone="UTC",
    enable_utc=True,
    task_track_started=True,
    task_acks_late=True,
    worker_prefetch_multiplier=1,
    task_routes={
        "app.workers.ingestion_worker.*": {"queue": "ingestion"},
        "app.workers.route_optimizer.*": {"queue": "routing"},
    },
)
