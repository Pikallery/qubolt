from __future__ import annotations

import uuid

from sqlalchemy import ForeignKey, String
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.models.base import Base, TimestampMixin, UUIDPKMixin

VEHICLE_TYPES = ("bike", "three_wheeler", "van", "truck")

# Major Odisha distribution hubs (pincode → hub name)
ODISHA_HUBS: dict[str, str] = {
    "751001": "Bhubaneswar HQ",
    "753001": "Cuttack Central",
    "769001": "Rourkela North",
    "768001": "Sambalpur Depot",
    "760001": "Berhampur South",
    "756001": "Balasore East",
    "757001": "Baripada Hub",
    "768201": "Jharsuguda Industrial",
    "759001": "Angul Hub",
    "754211": "Kendrapara Depot",
    "764020": "Koraput Tribal",
    "752001": "Puri Coastal",
    "765001": "Rayagada Hub",
    "770001": "Sundargarh Steel Belt",
    "761001": "Phulbani Hub",
    "766001": "Bhawanipatna Hub",
}


class UserProfile(Base, UUIDPKMixin, TimestampMixin):
    """Role-specific profile metadata attached 1-to-1 to a User."""

    __tablename__ = "user_profiles"

    user_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("users.id", ondelete="CASCADE"),
        nullable=False,
        unique=True,
        index=True,
    )

    # ── DRIVER fields ──────────────────────────────────────────────────────────
    license_number: Mapped[str | None] = mapped_column(String(50))
    vehicle_type: Mapped[str | None] = mapped_column(String(30))  # bike|three_wheeler|van|truck

    # ── GATEKEEPER fields ──────────────────────────────────────────────────────
    assigned_hub_id: Mapped[str | None] = mapped_column(String(10))  # Odisha pincode
    hub_name: Mapped[str | None] = mapped_column(String(100))

    # ── MANAGER fields ─────────────────────────────────────────────────────────
    organization_name: Mapped[str | None] = mapped_column(String(255))

    # ── Relationship ───────────────────────────────────────────────────────────
    user: Mapped["User"] = relationship("User", back_populates="profile")  # noqa: F821
