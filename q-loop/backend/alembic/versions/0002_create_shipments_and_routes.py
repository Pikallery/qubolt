"""create shipments, customers, vehicles, routes

Revision ID: 0002
Revises: 0001
Create Date: 2025-01-01 00:01:00.000000
"""
from __future__ import annotations

import sqlalchemy as sa
from sqlalchemy.dialects import postgresql

from alembic import op

revision = "0002"
down_revision = "0001"
branch_labels = None
depends_on = None


def upgrade() -> None:
    # ── customers ─────────────────────────────────────────────────────────────
    op.create_table(
        "customers",
        sa.Column("id", postgresql.UUID(as_uuid=True), primary_key=True,
                  server_default=sa.text("gen_random_uuid()")),
        sa.Column("tenant_id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column("external_id", sa.String(100)),
        sa.Column("name", sa.String(255), nullable=False),
        sa.Column("email", sa.String(320)),
        sa.Column("phone", sa.String(30)),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False,
                  server_default=sa.text("NOW()")),
        sa.Column("updated_at", sa.DateTime(timezone=True), nullable=False,
                  server_default=sa.text("NOW()")),
        sa.ForeignKeyConstraint(["tenant_id"], ["tenants.id"], ondelete="CASCADE"),
    )
    op.create_index("ix_customers_tenant_id", "customers", ["tenant_id"])
    op.create_index("ix_customers_external_id", "customers", ["external_id"])

    # ── customer_addresses ────────────────────────────────────────────────────
    op.create_table(
        "customer_addresses",
        sa.Column("id", postgresql.UUID(as_uuid=True), primary_key=True,
                  server_default=sa.text("gen_random_uuid()")),
        sa.Column("customer_id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column("tenant_id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column("label", sa.String(50)),
        sa.Column("address_text", sa.String(500)),
        sa.Column("area", sa.String(100)),
        sa.Column("pincode", sa.String(10)),
        sa.Column("latitude", sa.Numeric(10, 7)),
        sa.Column("longitude", sa.Numeric(10, 7)),
        sa.Column("is_default", sa.Boolean, nullable=False, server_default="false"),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False,
                  server_default=sa.text("NOW()")),
        sa.Column("updated_at", sa.DateTime(timezone=True), nullable=False,
                  server_default=sa.text("NOW()")),
        sa.ForeignKeyConstraint(["customer_id"], ["customers.id"], ondelete="CASCADE"),
        sa.ForeignKeyConstraint(["tenant_id"], ["tenants.id"], ondelete="CASCADE"),
    )

    # ── delivery_partners ─────────────────────────────────────────────────────
    op.create_table(
        "delivery_partners",
        sa.Column("id", postgresql.UUID(as_uuid=True), primary_key=True,
                  server_default=sa.text("gen_random_uuid()")),
        sa.Column("tenant_id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column("name", sa.String(255), nullable=False),
        sa.Column("api_endpoint", sa.String(500)),
        sa.Column("api_key_enc", sa.String(512)),
        sa.Column("contact_phone", sa.String(30)),
        sa.Column("supported_modes", postgresql.ARRAY(sa.String)),
        sa.Column("supported_vehicle_types", postgresql.ARRAY(sa.String)),
        sa.Column("active_regions", postgresql.ARRAY(sa.String)),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False,
                  server_default=sa.text("NOW()")),
        sa.Column("updated_at", sa.DateTime(timezone=True), nullable=False,
                  server_default=sa.text("NOW()")),
        sa.ForeignKeyConstraint(["tenant_id"], ["tenants.id"], ondelete="CASCADE"),
    )
    op.create_index("ix_delivery_partners_tenant_id", "delivery_partners", ["tenant_id"])

    # ── partner_performance ───────────────────────────────────────────────────
    op.create_table(
        "partner_performance",
        sa.Column("id", postgresql.UUID(as_uuid=True), primary_key=True,
                  server_default=sa.text("gen_random_uuid()")),
        sa.Column("partner_id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column("tenant_id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column("period_start", sa.Date, nullable=False),
        sa.Column("period_end", sa.Date, nullable=False),
        sa.Column("total_deliveries", sa.Integer, nullable=False, server_default="0"),
        sa.Column("on_time_count", sa.Integer, nullable=False, server_default="0"),
        sa.Column("delayed_count", sa.Integer, nullable=False, server_default="0"),
        sa.Column("avg_rating", sa.Numeric(3, 2)),
        sa.Column("avg_cost_per_km", sa.Numeric(8, 4)),
        sa.Column("avg_delivery_hrs", sa.Numeric(6, 2)),
        sa.ForeignKeyConstraint(["partner_id"], ["delivery_partners.id"], ondelete="CASCADE"),
        sa.ForeignKeyConstraint(["tenant_id"], ["tenants.id"], ondelete="CASCADE"),
        sa.UniqueConstraint("partner_id", "period_start", "period_end",
                            name="uq_partner_perf_period"),
    )

    # ── ingestion_jobs (needed before shipments FK) ───────────────────────────
    op.create_table(
        "ingestion_jobs",
        sa.Column("id", postgresql.UUID(as_uuid=True), primary_key=True,
                  server_default=sa.text("gen_random_uuid()")),
        sa.Column("tenant_id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column("uploaded_by", postgresql.UUID(as_uuid=True)),
        sa.Column("source_type", sa.String(50), nullable=False),
        sa.Column("file_name", sa.String(500), nullable=False),
        sa.Column("file_size_bytes", sa.BigInteger),
        sa.Column("row_count_total", sa.Integer),
        sa.Column("row_count_ok", sa.Integer, nullable=False, server_default="0"),
        sa.Column("row_count_error", sa.Integer, nullable=False, server_default="0"),
        sa.Column("status", sa.String(20), nullable=False, server_default="pending"),
        sa.Column("started_at", sa.DateTime(timezone=True)),
        sa.Column("finished_at", sa.DateTime(timezone=True)),
        sa.Column("error_summary", postgresql.JSONB),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False,
                  server_default=sa.text("NOW()")),
        sa.ForeignKeyConstraint(["tenant_id"], ["tenants.id"], ondelete="CASCADE"),
        sa.ForeignKeyConstraint(["uploaded_by"], ["users.id"], ondelete="SET NULL"),
    )
    op.create_index("ix_ingestion_jobs_tenant_id", "ingestion_jobs", ["tenant_id"])
    op.create_index("ix_ingestion_jobs_status", "ingestion_jobs", ["status"])

    # ── shipments ─────────────────────────────────────────────────────────────
    op.create_table(
        "shipments",
        sa.Column("id", postgresql.UUID(as_uuid=True), primary_key=True,
                  server_default=sa.text("gen_random_uuid()")),
        sa.Column("tenant_id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column("external_id", sa.String(100)),
        sa.Column("customer_id", postgresql.UUID(as_uuid=True)),
        sa.Column("partner_id", postgresql.UUID(as_uuid=True)),
        sa.Column("origin_address_id", postgresql.UUID(as_uuid=True)),
        sa.Column("dest_address_id", postgresql.UUID(as_uuid=True)),
        sa.Column("ingestion_job_id", postgresql.UUID(as_uuid=True)),
        sa.Column("package_type", sa.String(100)),
        sa.Column("vehicle_type", sa.String(50)),
        sa.Column("delivery_mode", sa.String(50)),
        sa.Column("region", sa.String(100)),
        sa.Column("weather_at_dispatch", sa.String(100)),
        sa.Column("distance_km", sa.Numeric(8, 2)),
        sa.Column("weight_kg", sa.Numeric(8, 3)),
        sa.Column("order_value_inr", sa.Numeric(12, 2)),
        sa.Column("delivery_cost", sa.Numeric(10, 2)),
        sa.Column("priority", sa.String(20), nullable=False, server_default="medium"),
        sa.Column("platform", sa.String(100)),
        sa.Column("status", sa.String(30), nullable=False, server_default="pending"),
        sa.Column("is_delayed", sa.Boolean, nullable=False, server_default="false"),
        sa.Column("refund_requested", sa.Boolean, nullable=False, server_default="false"),
        sa.Column("rating", sa.SmallInteger),
        sa.Column("expected_at", sa.DateTime(timezone=True)),
        sa.Column("delivered_at", sa.DateTime(timezone=True)),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False,
                  server_default=sa.text("NOW()")),
        sa.Column("updated_at", sa.DateTime(timezone=True), nullable=False,
                  server_default=sa.text("NOW()")),
        sa.ForeignKeyConstraint(["tenant_id"], ["tenants.id"], ondelete="CASCADE"),
        sa.ForeignKeyConstraint(["customer_id"], ["customers.id"], ondelete="SET NULL"),
        sa.ForeignKeyConstraint(["partner_id"], ["delivery_partners.id"], ondelete="SET NULL"),
        sa.ForeignKeyConstraint(["origin_address_id"], ["customer_addresses.id"], ondelete="SET NULL"),
        sa.ForeignKeyConstraint(["dest_address_id"], ["customer_addresses.id"], ondelete="SET NULL"),
        sa.ForeignKeyConstraint(["ingestion_job_id"], ["ingestion_jobs.id"], ondelete="SET NULL"),
    )
    op.create_index("ix_shipments_tenant_id", "shipments", ["tenant_id"])
    op.create_index("ix_shipments_external_id", "shipments", ["external_id"])
    op.create_index("ix_shipments_status", "shipments", ["status"])
    op.create_index("ix_shipments_region", "shipments", ["region"])

    # ── shipment_events ───────────────────────────────────────────────────────
    op.create_table(
        "shipment_events",
        sa.Column("id", postgresql.UUID(as_uuid=True), primary_key=True,
                  server_default=sa.text("gen_random_uuid()")),
        sa.Column("shipment_id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column("tenant_id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column("event_type", sa.String(50), nullable=False),
        sa.Column("location_lat", sa.Numeric(10, 7)),
        sa.Column("location_lon", sa.Numeric(10, 7)),
        sa.Column("note", sa.Text),
        sa.Column("recorded_by", postgresql.UUID(as_uuid=True)),
        sa.Column("occurred_at", sa.DateTime(timezone=True), nullable=False),
        sa.ForeignKeyConstraint(["shipment_id"], ["shipments.id"], ondelete="CASCADE"),
        sa.ForeignKeyConstraint(["tenant_id"], ["tenants.id"], ondelete="CASCADE"),
        sa.ForeignKeyConstraint(["recorded_by"], ["users.id"], ondelete="SET NULL"),
    )
    op.create_index("ix_shipment_events_shipment_id", "shipment_events", ["shipment_id"])

    # ── qr_tokens ─────────────────────────────────────────────────────────────
    op.create_table(
        "qr_tokens",
        sa.Column("id", postgresql.UUID(as_uuid=True), primary_key=True,
                  server_default=sa.text("gen_random_uuid()")),
        sa.Column("tenant_id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column("shipment_id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column("issued_to", postgresql.UUID(as_uuid=True)),
        sa.Column("token_hash", sa.String(128), nullable=False, unique=True),
        sa.Column("expires_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("scanned_at", sa.DateTime(timezone=True)),
        sa.Column("scanned_by", postgresql.UUID(as_uuid=True)),
        sa.Column("scan_lat", sa.Numeric(10, 7)),
        sa.Column("scan_lon", sa.Numeric(10, 7)),
        sa.Column("is_valid", sa.Boolean, nullable=False, server_default="true"),
        sa.ForeignKeyConstraint(["tenant_id"], ["tenants.id"], ondelete="CASCADE"),
        sa.ForeignKeyConstraint(["shipment_id"], ["shipments.id"], ondelete="CASCADE"),
        sa.ForeignKeyConstraint(["issued_to"], ["users.id"], ondelete="SET NULL"),
        sa.ForeignKeyConstraint(["scanned_by"], ["users.id"], ondelete="SET NULL"),
    )
    op.create_index("ix_qr_tokens_token_hash", "qr_tokens", ["token_hash"])
    op.create_index("ix_qr_tokens_shipment_id", "qr_tokens", ["shipment_id"])

    # ── vehicles ──────────────────────────────────────────────────────────────
    op.create_table(
        "vehicles",
        sa.Column("id", postgresql.UUID(as_uuid=True), primary_key=True,
                  server_default=sa.text("gen_random_uuid()")),
        sa.Column("tenant_id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column("registration", sa.String(30), nullable=False),
        sa.Column("type", sa.String(30), nullable=False),
        sa.Column("capacity_kg", sa.Numeric(8, 2)),
        sa.Column("is_available", sa.Boolean, nullable=False, server_default="true"),
        sa.Column("current_lat", sa.Numeric(10, 7)),
        sa.Column("current_lon", sa.Numeric(10, 7)),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False,
                  server_default=sa.text("NOW()")),
        sa.Column("updated_at", sa.DateTime(timezone=True), nullable=False,
                  server_default=sa.text("NOW()")),
        sa.ForeignKeyConstraint(["tenant_id"], ["tenants.id"], ondelete="CASCADE"),
    )

    # ── routes ────────────────────────────────────────────────────────────────
    op.create_table(
        "routes",
        sa.Column("id", postgresql.UUID(as_uuid=True), primary_key=True,
                  server_default=sa.text("gen_random_uuid()")),
        sa.Column("tenant_id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column("vehicle_id", postgresql.UUID(as_uuid=True)),
        sa.Column("optimized_by", sa.String(50), nullable=False,
                  server_default="simulated_annealing"),
        sa.Column("status", sa.String(20), nullable=False, server_default="draft"),
        sa.Column("total_distance_km", sa.Numeric(10, 2)),
        sa.Column("total_duration_min", sa.Integer),
        sa.Column("sa_iterations", sa.Integer),
        sa.Column("sa_temperature", sa.Numeric(8, 4)),
        sa.Column("sa_final_cost", sa.Numeric(10, 4)),
        sa.Column("dispatched_at", sa.DateTime(timezone=True)),
        sa.Column("completed_at", sa.DateTime(timezone=True)),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False,
                  server_default=sa.text("NOW()")),
        sa.Column("updated_at", sa.DateTime(timezone=True), nullable=False,
                  server_default=sa.text("NOW()")),
        sa.ForeignKeyConstraint(["tenant_id"], ["tenants.id"], ondelete="CASCADE"),
        sa.ForeignKeyConstraint(["vehicle_id"], ["vehicles.id"], ondelete="SET NULL"),
    )
    op.create_index("ix_routes_tenant_id", "routes", ["tenant_id"])

    # ── route_stops ───────────────────────────────────────────────────────────
    op.create_table(
        "route_stops",
        sa.Column("id", postgresql.UUID(as_uuid=True), primary_key=True,
                  server_default=sa.text("gen_random_uuid()")),
        sa.Column("route_id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column("tenant_id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column("shipment_id", postgresql.UUID(as_uuid=True)),
        sa.Column("stop_sequence", sa.Integer, nullable=False),
        sa.Column("latitude", sa.Numeric(10, 7), nullable=False),
        sa.Column("longitude", sa.Numeric(10, 7), nullable=False),
        sa.Column("estimated_arrival", sa.DateTime(timezone=True)),
        sa.Column("actual_arrival", sa.DateTime(timezone=True)),
        sa.Column("status", sa.String(20), nullable=False, server_default="pending"),
        sa.ForeignKeyConstraint(["route_id"], ["routes.id"], ondelete="CASCADE"),
        sa.ForeignKeyConstraint(["tenant_id"], ["tenants.id"], ondelete="CASCADE"),
        sa.ForeignKeyConstraint(["shipment_id"], ["shipments.id"], ondelete="SET NULL"),
    )
    op.create_index("ix_route_stops_route_id", "route_stops", ["route_id"])

    # ── packages ─────────────────────────────────────────────────────────────
    op.create_table(
        "packages",
        sa.Column("id", postgresql.UUID(as_uuid=True), primary_key=True,
                  server_default=sa.text("gen_random_uuid()")),
        sa.Column("shipment_id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column("tenant_id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column("sku", sa.String(100)),
        sa.Column("description", sa.String(500)),
        sa.Column("weight_kg", sa.Numeric(8, 3)),
        sa.Column("length_cm", sa.Numeric(6, 2)),
        sa.Column("width_cm", sa.Numeric(6, 2)),
        sa.Column("height_cm", sa.Numeric(6, 2)),
        sa.Column("quantity", sa.Integer, nullable=False, server_default="1"),
        sa.ForeignKeyConstraint(["shipment_id"], ["shipments.id"], ondelete="CASCADE"),
        sa.ForeignKeyConstraint(["tenant_id"], ["tenants.id"], ondelete="CASCADE"),
    )


def downgrade() -> None:
    op.drop_table("packages")
    op.drop_table("route_stops")
    op.drop_table("routes")
    op.drop_table("vehicles")
    op.drop_table("qr_tokens")
    op.drop_table("shipment_events")
    op.drop_table("shipments")
    op.drop_table("ingestion_jobs")
    op.drop_table("partner_performance")
    op.drop_table("delivery_partners")
    op.drop_table("customer_addresses")
    op.drop_table("customers")
