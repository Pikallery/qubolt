"""add user_profiles table for role-specific metadata

Revision ID: 0007
Revises: 0006
Create Date: 2025-01-01 00:06:00.000000

Adds user_profiles table storing driver/gatekeeper/manager-specific fields
linked 1-to-1 to users.
"""
from __future__ import annotations

import sqlalchemy as sa
from sqlalchemy.dialects import postgresql

from alembic import op

revision = "0007"
down_revision = "0006"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.create_table(
        "user_profiles",
        sa.Column("id", postgresql.UUID(as_uuid=True), server_default=sa.text("gen_random_uuid()"), primary_key=True),
        sa.Column("user_id", postgresql.UUID(as_uuid=True), sa.ForeignKey("users.id", ondelete="CASCADE"), nullable=False),
        # Driver
        sa.Column("license_number", sa.String(50), nullable=True),
        sa.Column("vehicle_type", sa.String(30), nullable=True),
        # Gatekeeper
        sa.Column("assigned_hub_id", sa.String(10), nullable=True),
        sa.Column("hub_name", sa.String(100), nullable=True),
        # Manager
        sa.Column("organization_name", sa.String(255), nullable=True),
        # Timestamps
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
    )
    op.create_index("ix_user_profiles_user_id", "user_profiles", ["user_id"], unique=True)


def downgrade() -> None:
    op.drop_index("ix_user_profiles_user_id", "user_profiles")
    op.drop_table("user_profiles")
