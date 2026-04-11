from __future__ import annotations

from datetime import datetime

from sqlalchemy import Boolean, DateTime, Integer, String, text
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.models.base import Base, TimestampMixin, UUIDPKMixin


class Tenant(Base, UUIDPKMixin, TimestampMixin):
    __tablename__ = "tenants"

    slug: Mapped[str] = mapped_column(String(100), unique=True, nullable=False, index=True)
    name: Mapped[str] = mapped_column(String(255), nullable=False)
    plan: Mapped[str] = mapped_column(String(50), nullable=False, server_default="starter")
    max_users: Mapped[int] = mapped_column(Integer, nullable=False, server_default="5")
    max_shipments: Mapped[int] = mapped_column(Integer, nullable=False, server_default="1000")
    is_active: Mapped[bool] = mapped_column(Boolean, nullable=False, server_default="true")

    # Relationships
    users: Mapped[list["User"]] = relationship(  # noqa: F821
        "User", back_populates="tenant", lazy="noload"
    )
    shipments: Mapped[list["Shipment"]] = relationship(  # noqa: F821
        "Shipment", back_populates="tenant", lazy="noload"
    )
    routes: Mapped[list["Route"]] = relationship(  # noqa: F821
        "Route", back_populates="tenant", lazy="noload"
    )
    ingestion_jobs: Mapped[list["IngestionJob"]] = relationship(  # noqa: F821
        "IngestionJob", back_populates="tenant", lazy="noload"
    )

    def __repr__(self) -> str:
        return f"<Tenant slug={self.slug!r} plan={self.plan!r}>"
