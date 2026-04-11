from __future__ import annotations

import uuid

from sqlalchemy import Float, ForeignKey, String, UniqueConstraint
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.models.base import Base, TimestampMixin, UUIDPKMixin


class DriverLocation(Base, UUIDPKMixin, TimestampMixin):
    """Last-known GPS position of a driver. One row per driver (upserted on update).
    Hub operators and managers can query this table to see live fleet positions.
    """
    __tablename__ = "driver_locations"
    __table_args__ = (
        UniqueConstraint("driver_id", name="uq_driver_locations_driver"),
    )

    tenant_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("tenants.id", ondelete="CASCADE"),
        nullable=False,
        index=True,
    )
    driver_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("users.id", ondelete="CASCADE"),
        nullable=False,
        index=True,
    )
    lat: Mapped[float] = mapped_column(Float, nullable=False)
    lon: Mapped[float] = mapped_column(Float, nullable=False)
    speed_kmh: Mapped[float | None] = mapped_column(Float)
    # Human-readable label ("En Route", "At Hub", "Idle")
    status: Mapped[str] = mapped_column(String(30), nullable=False, server_default="active")
    # Derived custom ID shown in UI: DRV-OD-TRUCK-XXXX
    custom_id: Mapped[str | None] = mapped_column(String(40))

    driver: Mapped["User"] = relationship("User", foreign_keys=[driver_id])  # noqa: F821
