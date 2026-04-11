from __future__ import annotations

import uuid
from datetime import datetime
from pathlib import Path

from fastapi import APIRouter, File, Form, HTTPException, UploadFile, status
from fastapi.responses import FileResponse
from pydantic import BaseModel, ConfigDict
from sqlalchemy import select

from app.core.config import settings
from app.dependencies import CurrentTenant, CurrentUser, DBSession
from app.models.delivery_photo import DeliveryPhoto
from app.models.shipment import Shipment

router = APIRouter(prefix="/photos", tags=["photos"])

ALLOWED_EXTENSIONS = {"jpg", "jpeg", "png", "webp", "heic"}
VALID_PHOTO_TYPES = {"pickup", "delivery", "damage", "return"}


# ── Schemas ──────────────────────────────────────────────────────────────────

class DeliveryPhotoRead(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: uuid.UUID
    tenant_id: uuid.UUID
    shipment_id: uuid.UUID
    uploaded_by: uuid.UUID
    photo_url: str
    photo_type: str
    file_size_bytes: int | None
    lat: float | None
    lon: float | None
    notes: str | None
    created_at: datetime


# ── Endpoints ────────────────────────────────────────────────────────────────

@router.post("/upload", response_model=DeliveryPhotoRead, status_code=status.HTTP_201_CREATED)
async def upload_photo(
    tenant: CurrentTenant,
    current_user: CurrentUser,
    db: DBSession,
    file: UploadFile = File(...),
    shipment_id: uuid.UUID = Form(...),
    photo_type: str = Form(...),
    lat: float | None = Form(None),
    lon: float | None = Form(None),
    notes: str | None = Form(None),
):
    # Validate photo type
    if photo_type not in VALID_PHOTO_TYPES:
        raise HTTPException(
            status_code=400,
            detail=f"Invalid photo_type. Must be one of: {', '.join(VALID_PHOTO_TYPES)}",
        )

    # Validate shipment exists
    result = await db.execute(
        select(Shipment).where(Shipment.id == shipment_id, Shipment.tenant_id == tenant.id)
    )
    if not result.scalar_one_or_none():
        raise HTTPException(status_code=404, detail="Shipment not found")

    # Validate file extension
    if not file.filename:
        raise HTTPException(status_code=400, detail="No filename provided")
    ext = file.filename.rsplit(".", 1)[-1].lower() if "." in file.filename else ""
    if ext not in ALLOWED_EXTENSIONS:
        raise HTTPException(
            status_code=400,
            detail=f"File type not allowed. Accepted: {', '.join(ALLOWED_EXTENSIONS)}",
        )

    # Read file content
    content = await file.read()
    file_size = len(content)
    max_bytes = settings.MAX_UPLOAD_SIZE_MB * 1024 * 1024
    if file_size > max_bytes:
        raise HTTPException(
            status_code=400,
            detail=f"File size exceeds {settings.MAX_UPLOAD_SIZE_MB} MB limit",
        )

    # Save to disk
    file_uuid = uuid.uuid4()
    save_dir = settings.UPLOAD_DIR / str(tenant.id) / str(shipment_id)
    save_dir.mkdir(parents=True, exist_ok=True)
    filename = f"{file_uuid}.{ext}"
    file_path = save_dir / filename

    file_path.write_bytes(content)

    # Store relative URL for serving
    photo_url = f"{tenant.id}/{shipment_id}/{filename}"

    photo = DeliveryPhoto(
        tenant_id=tenant.id,
        shipment_id=shipment_id,
        uploaded_by=current_user.id,
        photo_url=photo_url,
        photo_type=photo_type,
        file_size_bytes=file_size,
        lat=lat,
        lon=lon,
        notes=notes,
    )
    db.add(photo)
    await db.flush()
    return DeliveryPhotoRead.model_validate(photo)


@router.get("/{shipment_id}", response_model=list[DeliveryPhotoRead])
async def list_photos(
    shipment_id: uuid.UUID,
    tenant: CurrentTenant,
    db: DBSession,
    _: CurrentUser,
):
    result = await db.execute(
        select(DeliveryPhoto)
        .where(
            DeliveryPhoto.shipment_id == shipment_id,
            DeliveryPhoto.tenant_id == tenant.id,
        )
        .order_by(DeliveryPhoto.created_at.desc())
    )
    return [DeliveryPhotoRead.model_validate(p) for p in result.scalars().all()]


@router.get("/file/{photo_id}")
async def serve_photo(
    photo_id: uuid.UUID,
    tenant: CurrentTenant,
    db: DBSession,
    _: CurrentUser,
):
    result = await db.execute(
        select(DeliveryPhoto).where(
            DeliveryPhoto.id == photo_id,
            DeliveryPhoto.tenant_id == tenant.id,
        )
    )
    photo = result.scalar_one_or_none()
    if not photo:
        raise HTTPException(status_code=404, detail="Photo not found")

    file_path = settings.UPLOAD_DIR / photo.photo_url
    if not file_path.exists():
        raise HTTPException(status_code=404, detail="Photo file not found on disk")

    return FileResponse(path=str(file_path))
