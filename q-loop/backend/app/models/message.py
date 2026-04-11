from __future__ import annotations

import uuid
from datetime import datetime

from sqlalchemy import DateTime, ForeignKey, String, Text
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.models.base import Base, TimestampMixin, UUIDPKMixin


class Message(Base, UUIDPKMixin, TimestampMixin):
    """In-app message between two users (driver↔hub, hub↔manager, driver↔manager).
    Optionally also dispatched via Twilio SMS when sender initiates a send.
    """
    __tablename__ = "messages"

    tenant_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("tenants.id", ondelete="CASCADE"),
        nullable=False,
        index=True,
    )
    sender_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("users.id", ondelete="CASCADE"),
        nullable=False,
        index=True,
    )
    recipient_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("users.id", ondelete="CASCADE"),
        nullable=False,
        index=True,
    )
    body: Mapped[str] = mapped_column(Text, nullable=False)
    # "in_app" | "sms" | "voip"
    channel: Mapped[str] = mapped_column(String(20), nullable=False, server_default="in_app")
    twilio_sid: Mapped[str | None] = mapped_column(String(64))
    read_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))

    sender: Mapped["User"] = relationship(  # noqa: F821
        "User", foreign_keys=[sender_id]
    )
    recipient: Mapped["User"] = relationship(  # noqa: F821
        "User", foreign_keys=[recipient_id]
    )
