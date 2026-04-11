"""add sustainability benchmarks table

Revision ID: 0006
Revises: 0005
Create Date: 2026-04-03
"""
from __future__ import annotations

from alembic import op
import sqlalchemy as sa

revision = "0006"
down_revision = "0005"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.create_table(
        "sustainability_benchmarks",
        sa.Column("id", sa.UUID(), nullable=False, server_default=sa.text("gen_random_uuid()")),
        sa.Column("tenant_id", sa.UUID(), nullable=False),
        sa.Column(
            "benchmark_type",
            sa.String(50),
            nullable=False,
            comment="ewaste_generation | ewaste_recyclers | msw_generation",
        ),
        sa.Column("financial_year", sa.String(20), nullable=True),
        sa.Column("state_ut", sa.String(100), nullable=True),
        sa.Column("metric_name", sa.String(100), nullable=False),
        sa.Column("metric_value", sa.Numeric(precision=18, scale=4), nullable=True),
        sa.Column("unit", sa.String(50), nullable=True),
        sa.Column("source", sa.String(200), nullable=True),
        sa.Column(
            "created_at",
            sa.TIMESTAMP(timezone=True),
            nullable=False,
            server_default=sa.text("NOW()"),
        ),
        sa.PrimaryKeyConstraint("id"),
    )
    op.create_index(
        "ix_sustainability_benchmarks_tenant_type",
        "sustainability_benchmarks",
        ["tenant_id", "benchmark_type"],
    )
    op.create_index(
        "ix_sustainability_benchmarks_state",
        "sustainability_benchmarks",
        ["tenant_id", "state_ut"],
    )


def downgrade() -> None:
    op.drop_index("ix_sustainability_benchmarks_state", table_name="sustainability_benchmarks")
    op.drop_index("ix_sustainability_benchmarks_tenant_type", table_name="sustainability_benchmarks")
    op.drop_table("sustainability_benchmarks")
