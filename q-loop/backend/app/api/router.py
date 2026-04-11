from fastapi import APIRouter

from app.api.v1 import (
    analytics, auth, ai, comms, ingestion, routes, shipments, users,
    geofence, drivers, returns, photos, alerts, partners,
)

api_router = APIRouter(prefix="/api/v1")

api_router.include_router(auth.router)
api_router.include_router(users.router)
api_router.include_router(shipments.router)
api_router.include_router(routes.router)
api_router.include_router(ingestion.router)
api_router.include_router(ai.router)
api_router.include_router(comms.router)
api_router.include_router(analytics.router)
api_router.include_router(geofence.router)
api_router.include_router(drivers.router)
api_router.include_router(returns.router)
api_router.include_router(photos.router)
api_router.include_router(alerts.router)
api_router.include_router(partners.router)
