from __future__ import annotations

import uuid
from datetime import date

from sqlalchemy import Date, ForeignKey, Integer, Numeric, String, UniqueConstraint
from sqlalchemy.dialects.postgresql import ARRAY, UUID
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.models.base import Base, TimestampMixin, UUIDPKMixin


class DeliveryPartner(Base, UUIDPKMixin, TimestampMixin):
    __tablename__ = "delivery_partners"

    tenant_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), ForeignKey("tenants.id", ondelete="CASCADE"), nullable=False, index=True
    )
    name: Mapped[str] = mapped_column(String(255), nullable=False)
    api_endpoint: Mapped[str | None] = mapped_column(String(500))
    api_key_enc: Mapped[str | None] = mapped_column(String(512))  # AES-encrypted
    contact_phone: Mapped[str | None] = mapped_column(String(30))
    supported_modes: Mapped[list[str] | None] = mapped_column(ARRAY(String))
    supported_vehicle_types: Mapped[list[str] | None] = mapped_column(ARRAY(String))
    active_regions: Mapped[list[str] | None] = mapped_column(ARRAY(String))

    performance_records: Mapped[list["PartnerPerformance"]] = relationship(
        "PartnerPerformance", back_populates="partner", cascade="all, delete-orphan"
    )
    shipments: Mapped[list["Shipment"]] = relationship(  # noqa: F821
        "Shipment", back_populates="partner", lazy="noload"
    )


class PartnerPerformance(Base, UUIDPKMixin):
    __tablename__ = "partner_performance"
    __table_args__ = (
        UniqueConstraint("partner_id", "period_start", "period_end", name="uq_partner_perf_period"),
    )

    partner_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), ForeignKey("delivery_partners.id", ondelete="CASCADE"), nullable=False
    )
    tenant_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), ForeignKey("tenants.id", ondelete="CASCADE"), nullable=False, index=True
    )
    period_start: Mapped[date] = mapped_column(Date, nullable=False)
    period_end: Mapped[date] = mapped_column(Date, nullable=False)
    total_deliveries: Mapped[int] = mapped_column(Integer, nullable=False, server_default="0")
    on_time_count: Mapped[int] = mapped_column(Integer, nullable=False, server_default="0")
    delayed_count: Mapped[int] = mapped_column(Integer, nullable=False, server_default="0")
    avg_rating: Mapped[float | None] = mapped_column(Numeric(3, 2))
    avg_cost_per_km: Mapped[float | None] = mapped_column(Numeric(8, 4))
    avg_delivery_hrs: Mapped[float | None] = mapped_column(Numeric(6, 2))

    partner: Mapped["DeliveryPartner"] = relationship(
        "DeliveryPartner", back_populates="performance_records"
    )
