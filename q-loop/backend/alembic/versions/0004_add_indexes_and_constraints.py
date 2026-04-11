"""add composite indexes and GIN indexes for JSONB columns

Revision ID: 0004
Revises: 0003
Create Date: 2025-01-01 00:03:00.000000
"""
from __future__ import annotations

import sqlalchemy as sa

from alembic import op

revision = "0004"
down_revision = "0003"
branch_labels = None
depends_on = None


def upgrade() -> None:
    # Composite index for dashboard queries: tenant + status + created_at
    op.create_index(
        "ix_shipments_tenant_status_created",
        "shipments",
        ["tenant_id", "status", "created_at"],
    )
    # Composite index for partner analytics
    op.create_index(
        "ix_shipments_tenant_partner",
        "shipments",
        ["tenant_id", "partner_id"],
    )
    # GIN index for JSONB error_summary on ingestion_jobs
    op.execute(
        "CREATE INDEX IF NOT EXISTS ix_ingestion_jobs_error_summary_gin "
        "ON ingestion_jobs USING GIN (error_summary)"
    )
    # GIN index for audit_log before/after state queries
    op.execute(
        "CREATE INDEX IF NOT EXISTS ix_audit_logs_after_state_gin "
        "ON audit_logs USING GIN (after_state)"
    )
    # Partial index: only valid (unexpired) QR tokens
    op.execute(
        "CREATE INDEX IF NOT EXISTS ix_qr_tokens_valid "
        "ON qr_tokens (token_hash, expires_at) WHERE is_valid = true"
    )
    # Tenant + region rollup for map clustering
    op.execute(
        "CREATE INDEX IF NOT EXISTS ix_shipments_tenant_region "
        "ON shipments (tenant_id, region) WHERE region IS NOT NULL"
    )
    # Route stop geo queries
    op.execute(
        "CREATE INDEX IF NOT EXISTS ix_route_stops_lat_lon "
        "ON route_stops (latitude, longitude)"
    )


def downgrade() -> None:
    op.execute("DROP INDEX IF EXISTS ix_route_stops_lat_lon")
    op.execute("DROP INDEX IF EXISTS ix_shipments_tenant_region")
    op.execute("DROP INDEX IF EXISTS ix_qr_tokens_valid")
    op.execute("DROP INDEX IF EXISTS ix_audit_logs_after_state_gin")
    op.execute("DROP INDEX IF EXISTS ix_ingestion_jobs_error_summary_gin")
    op.drop_index("ix_shipments_tenant_partner", "shipments")
    op.drop_index("ix_shipments_tenant_status_created", "shipments")
