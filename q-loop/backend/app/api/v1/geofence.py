from __future__ import annotations

import math
import uuid

from fastapi import APIRouter, Query, status
from pydantic import BaseModel, ConfigDict
from sqlalchemy import select

from app.dependencies import CurrentTenant, CurrentUser, DBSession, require_min_role, require_role
from app.models.driver_location import DriverLocation
from app.models.geofence import GeoZone
from app.models.shipment import Shipment
from app.models.user import User
from app.models.user_profile import ODISHA_HUBS

router = APIRouter(prefix="/geofence", tags=["geofencing"])

# Approximate lat/lon for each Odisha hub pincode
HUB_COORDS: dict[str, tuple[float, float]] = {
    "751001": (20.2961, 85.8315),   # Bhubaneswar
    "753001": (20.4625, 85.8830),   # Cuttack
    "769001": (22.2270, 84.8536),   # Rourkela
    "768001": (21.4669, 83.9717),   # Sambalpur
    "760001": (19.3150, 84.7941),   # Berhampur
    "756001": (21.4942, 86.9355),   # Balasore
    "757001": (21.9322, 86.7285),   # Baripada
    "768201": (21.8553, 84.0064),   # Jharsuguda
    "759001": (20.8380, 85.1010),   # Angul
    "754211": (20.5012, 86.4211),   # Kendrapara
    "764020": (18.8135, 82.7123),   # Koraput
    "752001": (19.8106, 85.8315),   # Puri
    "765001": (19.1710, 83.4166),   # Rayagada
    "770001": (22.1168, 84.0308),   # Sundargarh
    "761001": (20.4667, 84.2333),   # Phulbani
    "766001": (19.8563, 83.1614),   # Bhawanipatna
}


# ── Schemas ──────────────────────────────────────────────────────────────────

class GeoZoneCreate(BaseModel):
    name: str
    center_lat: float
    center_lon: float
    radius_km: float = 15.0
    pincode: str | None = None
    hub_name: str | None = None


class GeoZoneRead(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: uuid.UUID
    tenant_id: uuid.UUID
    name: str
    center_lat: float
    center_lon: float
    radius_km: float
    pincode: str | None
    hub_name: str | None
    is_active: bool


class ZoneCheckResult(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    zone: GeoZoneRead | None
    distance_km: float | None


class AutoAssignResult(BaseModel):
    assigned: int
    unmatched: int
    details: list[dict]


# ── Helpers ──────────────────────────────────────────────────────────────────

def haversine_km(lat1: float, lon1: float, lat2: float, lon2: float) -> float:
    """Return the great-circle distance in km between two GPS points."""
    R = 6371.0
    dlat = math.radians(lat2 - lat1)
    dlon = math.radians(lon2 - lon1)
    a = math.sin(dlat / 2) ** 2 + math.cos(math.radians(lat1)) * math.cos(math.radians(lat2)) * math.sin(dlon / 2) ** 2
    return R * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a))


# ── Endpoints ────────────────────────────────────────────────────────────────

@router.post("/zones", response_model=GeoZoneRead, status_code=status.HTTP_201_CREATED,
             dependencies=[require_min_role("admin")])
async def create_zone(
    body: GeoZoneCreate,
    tenant: CurrentTenant,
    db: DBSession,
):
    zone = GeoZone(tenant_id=tenant.id, **body.model_dump())
    db.add(zone)
    await db.flush()
    return GeoZoneRead.model_validate(zone)


@router.get("/zones", response_model=list[GeoZoneRead])
async def list_zones(
    tenant: CurrentTenant,
    db: DBSession,
    _: CurrentUser,
):
    result = await db.execute(
        select(GeoZone).where(GeoZone.tenant_id == tenant.id).order_by(GeoZone.name)
    )
    return [GeoZoneRead.model_validate(z) for z in result.scalars().all()]


@router.get("/check", response_model=ZoneCheckResult)
async def check_zone(
    tenant: CurrentTenant,
    db: DBSession,
    _: CurrentUser,
    lat: float = Query(...),
    lon: float = Query(...),
):
    result = await db.execute(
        select(GeoZone).where(GeoZone.tenant_id == tenant.id, GeoZone.is_active == True)
    )
    zones = result.scalars().all()

    best_zone = None
    best_dist = float("inf")
    for z in zones:
        dist = haversine_km(lat, lon, z.center_lat, z.center_lon)
        if dist <= z.radius_km and dist < best_dist:
            best_zone = z
            best_dist = dist

    if best_zone:
        return ZoneCheckResult(zone=GeoZoneRead.model_validate(best_zone), distance_km=round(best_dist, 2))
    return ZoneCheckResult(zone=None, distance_km=None)


@router.post("/seed-odisha", response_model=list[GeoZoneRead], status_code=status.HTTP_201_CREATED,
             dependencies=[require_role("admin", "superadmin", "manager")])
async def seed_odisha_zones(
    tenant: CurrentTenant,
    db: DBSession,
):
    created: list[GeoZone] = []
    for pincode, hub_name in ODISHA_HUBS.items():
        coords = HUB_COORDS.get(pincode)
        if not coords:
            continue
        zone = GeoZone(
            tenant_id=tenant.id,
            name=hub_name,
            center_lat=coords[0],
            center_lon=coords[1],
            radius_km=15.0,
            pincode=pincode,
            hub_name=hub_name,
            is_active=True,
        )
        db.add(zone)
        created.append(zone)
    await db.flush()
    return [GeoZoneRead.model_validate(z) for z in created]


@router.post("/auto-assign", response_model=AutoAssignResult)
async def auto_assign_bulk(
    tenant: CurrentTenant,
    current_user: CurrentUser,
    db: DBSession,
    limit: int = Query(default=100, ge=1, le=500),
):
    """
    Bulk auto-assign pending shipments to zones based on their most recent
    location event. No shipment_id required — processes up to `limit` shipments.
    """
    from datetime import datetime, timezone
    from app.models.shipment import ShipmentEvent

    # Load all active zones once
    zone_result = await db.execute(
        select(GeoZone).where(GeoZone.tenant_id == tenant.id, GeoZone.is_active == True)
    )
    zones = zone_result.scalars().all()

    if not zones:
        return AutoAssignResult(assigned=0, unmatched=0, details=[])

    # Load all drivers with known locations once
    driver_result = await db.execute(
        select(DriverLocation, User)
        .join(User, DriverLocation.driver_id == User.id)
        .where(
            DriverLocation.tenant_id == tenant.id,
            User.role == "driver",
            User.is_active == True,
        )
    )
    driver_rows = driver_result.all()

    # Fetch pending/in_transit shipments that have location events
    shipment_result = await db.execute(
        select(Shipment)
        .where(
            Shipment.tenant_id == tenant.id,
            Shipment.status.in_(["pending", "in_transit", "picked_up"]),
        )
        .limit(limit)
    )
    shipments = shipment_result.scalars().all()

    assigned_count = 0
    unmatched_count = 0
    details: list[dict] = []

    for shipment in shipments:
        # Get most recent location event
        evt_result = await db.execute(
            select(ShipmentEvent)
            .where(
                ShipmentEvent.shipment_id == shipment.id,
                ShipmentEvent.location_lat.is_not(None),
            )
            .order_by(ShipmentEvent.occurred_at.desc())
            .limit(1)
        )
        event = evt_result.scalar_one_or_none()

        if not event:
            unmatched_count += 1
            continue

        lat, lon = float(event.location_lat), float(event.location_lon)

        # Find nearest zone
        matched_zone = None
        min_dist = float("inf")
        for z in zones:
            dist = haversine_km(lat, lon, z.center_lat, z.center_lon)
            if dist <= z.radius_km and dist < min_dist:
                matched_zone = z
                min_dist = dist

        if not matched_zone:
            unmatched_count += 1
            continue

        # Find nearest driver in zone
        nearest_driver = None
        nearest_dist = float("inf")
        for dl, user in driver_rows:
            d = haversine_km(lat, lon, dl.lat, dl.lon)
            if d <= matched_zone.radius_km and d < nearest_dist:
                nearest_driver = user
                nearest_dist = d

        if nearest_driver:
            db.add(ShipmentEvent(
                shipment_id=shipment.id,
                tenant_id=tenant.id,
                event_type="auto_assigned",
                location_lat=lat,
                location_lon=lon,
                note=f"Auto-assigned to {nearest_driver.full_name} in zone {matched_zone.name}",
                recorded_by=current_user.id,
                occurred_at=datetime.now(timezone.utc),
            ))

        assigned_count += 1
        details.append({
            "shipment_id": str(shipment.id),
            "zone_id": str(matched_zone.id),
            "zone_name": matched_zone.name,
            "driver": nearest_driver.full_name if nearest_driver else None,
        })

    await db.flush()
    return AutoAssignResult(assigned=assigned_count, unmatched=unmatched_count, details=details)
