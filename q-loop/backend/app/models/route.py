from __future__ import annotations

import uuid
from datetime import datetime

from sqlalchemy import Boolean, DateTime, ForeignKey, Integer, Numeric, String
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.models.base import Base, TimestampMixin, UUIDPKMixin


class Vehicle(Base, UUIDPKMixin, TimestampMixin):
    __tablename__ = "vehicles"

    tenant_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), ForeignKey("tenants.id", ondelete="CASCADE"), nullable=False, index=True
    )
    registration: Mapped[str] = mapped_column(String(30), nullable=False)
    type: Mapped[str] = mapped_column(String(30), nullable=False)  # bike|truck|ev_van|car
    capacity_kg: Mapped[float | None] = mapped_column(Numeric(8, 2))
    is_available: Mapped[bool] = mapped_column(Boolean, nullable=False, server_default="true")
    current_lat: Mapped[float | None] = mapped_column(Numeric(10, 7))
    current_lon: Mapped[float | None] = mapped_column(Numeric(10, 7))

    routes: Mapped[list["Route"]] = relationship("Route", back_populates="vehicle", lazy="noload")


class Route(Base, UUIDPKMixin, TimestampMixin):
    __tablename__ = "routes"

    tenant_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), ForeignKey("tenants.id", ondelete="CASCADE"), nullable=False, index=True
    )
    vehicle_id: Mapped[uuid.UUID | None] = mapped_column(
        UUID(as_uuid=True), ForeignKey("vehicles.id", ondelete="SET NULL")
    )
    optimized_by: Mapped[str] = mapped_column(
        String(50), nullable=False, server_default="simulated_annealing"
    )
    status: Mapped[str] = mapped_column(String(20), nullable=False, server_default="draft")
    total_distance_km: Mapped[float | None] = mapped_column(Numeric(10, 2))
    total_duration_min: Mapped[int | None] = mapped_column(Integer)
    # SA metadata
    sa_iterations: Mapped[int | None] = mapped_column(Integer)
    sa_temperature: Mapped[float | None] = mapped_column(Numeric(8, 4))
    sa_final_cost: Mapped[float | None] = mapped_column(Numeric(10, 4))

    dispatched_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    completed_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))

    tenant: Mapped["Tenant"] = relationship("Tenant", back_populates="routes")  # noqa: F821
    vehicle: Mapped["Vehicle | None"] = relationship("Vehicle", back_populates="routes")
    stops: Mapped[list["RouteStop"]] = relationship(
        "RouteStop", back_populates="route",
        cascade="all, delete-orphan",
        order_by="RouteStop.stop_sequence",
    )


class RouteStop(Base, UUIDPKMixin):
    __tablename__ = "route_stops"

    route_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), ForeignKey("routes.id", ondelete="CASCADE"), nullable=False, index=True
    )
    tenant_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), ForeignKey("tenants.id", ondelete="CASCADE"), nullable=False, index=True
    )
    shipment_id: Mapped[uuid.UUID | None] = mapped_column(
        UUID(as_uuid=True), ForeignKey("shipments.id", ondelete="SET NULL")
    )
    stop_sequence: Mapped[int] = mapped_column(Integer, nullable=False)
    latitude: Mapped[float] = mapped_column(Numeric(10, 7), nullable=False)
    longitude: Mapped[float] = mapped_column(Numeric(10, 7), nullable=False)
    estimated_arrival: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    actual_arrival: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    status: Mapped[str] = mapped_column(String(20), nullable=False, server_default="pending")

    route: Mapped["Route"] = relationship("Route", back_populates="stops")
    shipment: Mapped["Shipment | None"] = relationship("Shipment", back_populates="route_stops")
