from __future__ import annotations

import uuid
from datetime import datetime

from sqlalchemy import (
    Boolean, DateTime, ForeignKey, Integer, Numeric,
    SmallInteger, String, Text,
)
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.models.base import Base, TimestampMixin, UUIDPKMixin


class Shipment(Base, UUIDPKMixin, TimestampMixin):
    __tablename__ = "shipments"

    tenant_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), ForeignKey("tenants.id", ondelete="CASCADE"), nullable=False, index=True
    )
    external_id: Mapped[str | None] = mapped_column(String(100), index=True)
    customer_id: Mapped[uuid.UUID | None] = mapped_column(
        UUID(as_uuid=True), ForeignKey("customers.id", ondelete="SET NULL")
    )
    partner_id: Mapped[uuid.UUID | None] = mapped_column(
        UUID(as_uuid=True), ForeignKey("delivery_partners.id", ondelete="SET NULL")
    )
    origin_address_id: Mapped[uuid.UUID | None] = mapped_column(
        UUID(as_uuid=True), ForeignKey("customer_addresses.id", ondelete="SET NULL")
    )
    dest_address_id: Mapped[uuid.UUID | None] = mapped_column(
        UUID(as_uuid=True), ForeignKey("customer_addresses.id", ondelete="SET NULL")
    )
    ingestion_job_id: Mapped[uuid.UUID | None] = mapped_column(
        UUID(as_uuid=True), ForeignKey("ingestion_jobs.id", ondelete="SET NULL"), index=True
    )

    # Logistics attributes
    package_type: Mapped[str | None] = mapped_column(String(100))
    vehicle_type: Mapped[str | None] = mapped_column(String(50))
    delivery_mode: Mapped[str | None] = mapped_column(String(50))
    region: Mapped[str | None] = mapped_column(String(100), index=True)
    weather_at_dispatch: Mapped[str | None] = mapped_column(String(100))
    distance_km: Mapped[float | None] = mapped_column(Numeric(8, 2))
    weight_kg: Mapped[float | None] = mapped_column(Numeric(8, 3))
    order_value_inr: Mapped[float | None] = mapped_column(Numeric(12, 2))
    delivery_cost: Mapped[float | None] = mapped_column(Numeric(10, 2))
    priority: Mapped[str] = mapped_column(String(20), nullable=False, server_default="medium")
    platform: Mapped[str | None] = mapped_column(String(100))

    # Status
    status: Mapped[str] = mapped_column(String(30), nullable=False, server_default="pending", index=True)
    is_delayed: Mapped[bool] = mapped_column(Boolean, nullable=False, server_default="false")
    refund_requested: Mapped[bool] = mapped_column(Boolean, nullable=False, server_default="false")
    rating: Mapped[int | None] = mapped_column(SmallInteger)
    expected_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    delivered_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))

    # Relationships
    tenant: Mapped["Tenant"] = relationship("Tenant", back_populates="shipments")  # noqa: F821
    customer: Mapped["Customer | None"] = relationship("Customer", back_populates="shipments")
    partner: Mapped["DeliveryPartner | None"] = relationship(
        "DeliveryPartner", back_populates="shipments"
    )
    events: Mapped[list["ShipmentEvent"]] = relationship(
        "ShipmentEvent", back_populates="shipment", cascade="all, delete-orphan",
        order_by="ShipmentEvent.occurred_at",
    )
    qr_tokens: Mapped[list["QRToken"]] = relationship(  # noqa: F821
        "QRToken", back_populates="shipment", cascade="all, delete-orphan"
    )
    route_stops: Mapped[list["RouteStop"]] = relationship(  # noqa: F821
        "RouteStop", back_populates="shipment", lazy="noload"
    )

    def __repr__(self) -> str:
        return f"<Shipment id={self.id} status={self.status!r}>"


class ShipmentEvent(Base, UUIDPKMixin):
    __tablename__ = "shipment_events"

    shipment_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), ForeignKey("shipments.id", ondelete="CASCADE"), nullable=False, index=True
    )
    tenant_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), ForeignKey("tenants.id", ondelete="CASCADE"), nullable=False, index=True
    )
    event_type: Mapped[str] = mapped_column(String(50), nullable=False)
    location_lat: Mapped[float | None] = mapped_column(Numeric(10, 7))
    location_lon: Mapped[float | None] = mapped_column(Numeric(10, 7))
    note: Mapped[str | None] = mapped_column(Text)
    recorded_by: Mapped[uuid.UUID | None] = mapped_column(
        UUID(as_uuid=True), ForeignKey("users.id", ondelete="SET NULL")
    )
    occurred_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), nullable=False
    )

    shipment: Mapped["Shipment"] = relationship("Shipment", back_populates="events")


class Package(Base, UUIDPKMixin):
    """Optional package-level detail inside a shipment."""
    __tablename__ = "packages"

    shipment_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), ForeignKey("shipments.id", ondelete="CASCADE"), nullable=False, index=True
    )
    tenant_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), ForeignKey("tenants.id", ondelete="CASCADE"), nullable=False
    )
    sku: Mapped[str | None] = mapped_column(String(100))
    description: Mapped[str | None] = mapped_column(String(500))
    weight_kg: Mapped[float | None] = mapped_column(Numeric(8, 3))
    length_cm: Mapped[float | None] = mapped_column(Numeric(6, 2))
    width_cm: Mapped[float | None] = mapped_column(Numeric(6, 2))
    height_cm: Mapped[float | None] = mapped_column(Numeric(6, 2))
    quantity: Mapped[int] = mapped_column(Integer, nullable=False, server_default="1")


class QRToken(Base, UUIDPKMixin):
    __tablename__ = "qr_tokens"

    tenant_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), ForeignKey("tenants.id", ondelete="CASCADE"), nullable=False, index=True
    )
    shipment_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), ForeignKey("shipments.id", ondelete="CASCADE"), nullable=False, index=True
    )
    issued_to: Mapped[uuid.UUID | None] = mapped_column(
        UUID(as_uuid=True), ForeignKey("users.id", ondelete="SET NULL")
    )
    token_hash: Mapped[str] = mapped_column(String(128), nullable=False, unique=True, index=True)
    expires_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False)
    scanned_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    scanned_by: Mapped[uuid.UUID | None] = mapped_column(
        UUID(as_uuid=True), ForeignKey("users.id", ondelete="SET NULL")
    )
    scan_lat: Mapped[float | None] = mapped_column(Numeric(10, 7))
    scan_lon: Mapped[float | None] = mapped_column(Numeric(10, 7))
    is_valid: Mapped[bool] = mapped_column(Boolean, nullable=False, server_default="true")

    shipment: Mapped["Shipment"] = relationship("Shipment", back_populates="qr_tokens")
