"""Add assigned_driver_id, hub_operator_id, employment_type to shipments.

These columns exist in the SQLAlchemy model since the driver/hub workflow
was implemented but were never included in a migration.

Revision ID: 0010
Revises: 0009
Create Date: 2026-04-13
"""
from __future__ import annotations

import sqlalchemy as sa
from alembic import op
from sqlalchemy.dialects import postgresql

revision = "0010"
down_revision = "0009"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.add_column(
        "shipments",
        sa.Column(
            "assigned_driver_id",
            postgresql.UUID(as_uuid=True),
            sa.ForeignKey("users.id", ondelete="SET NULL"),
            nullable=True,
        ),
    )
    op.add_column(
        "shipments",
        sa.Column(
            "hub_operator_id",
            postgresql.UUID(as_uuid=True),
            sa.ForeignKey("users.id", ondelete="SET NULL"),
            nullable=True,
        ),
    )
    op.add_column(
        "shipments",
        sa.Column(
            "employment_type",
            sa.String(20),
            nullable=False,
            server_default="company",
        ),
    )
    op.create_index("ix_shipments_assigned_driver_id", "shipments", ["assigned_driver_id"])


def downgrade() -> None:
    op.drop_index("ix_shipments_assigned_driver_id", table_name="shipments")
    op.drop_column("shipments", "employment_type")
    op.drop_column("shipments", "hub_operator_id")
    op.drop_column("shipments", "assigned_driver_id")
