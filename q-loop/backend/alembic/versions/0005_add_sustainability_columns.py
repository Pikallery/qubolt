"""add sustainability + returns columns to shipments

Revision ID: 0005
Revises: 0004
Create Date: 2025-01-01 00:04:00.000000

Adds environmental impact columns sourced from returns_sustainability_dataset.csv:
  - co2_emissions_kg   : kg CO2 emitted by this delivery
  - packaging_waste_kg : kg packaging material used
  - co2_saved_kg       : kg CO2 avoided via optimised routing
  - waste_avoided_kg   : kg packaging waste avoided
  - return_reason      : free-text reason for return
  - profit_loss        : order profit/loss after discounts + returns

Also adds delhivery_routes support columns to route_stops:
  - source_center_code : Delhivery hub code (source)
  - dest_center_code   : Delhivery hub code (destination)
  - osrm_distance_km   : OSRM road distance benchmark
  - osrm_time_min      : OSRM time benchmark (minutes)
  - actual_time_min    : Real transit time (minutes)
  - delay_factor       : actual_time / osrm_time ratio
  - route_type         : FTL | Carting
"""
from __future__ import annotations

import sqlalchemy as sa

from alembic import op

revision = "0005"
down_revision = "0004"
branch_labels = None
depends_on = None


def upgrade() -> None:
    # ── Shipments: sustainability + returns columns ────────────────────────────
    op.add_column("shipments", sa.Column("co2_emissions_kg", sa.Numeric(8, 4), nullable=True))
    op.add_column("shipments", sa.Column("packaging_waste_kg", sa.Numeric(8, 4), nullable=True))
    op.add_column("shipments", sa.Column("co2_saved_kg", sa.Numeric(8, 4), nullable=True))
    op.add_column("shipments", sa.Column("waste_avoided_kg", sa.Numeric(8, 4), nullable=True))
    op.add_column("shipments", sa.Column("return_reason", sa.String(255), nullable=True))
    op.add_column("shipments", sa.Column("profit_loss", sa.Numeric(14, 4), nullable=True))

    # Index for sustainability analytics queries
    op.execute(
        "CREATE INDEX IF NOT EXISTS ix_shipments_tenant_co2 "
        "ON shipments (tenant_id, co2_emissions_kg) "
        "WHERE co2_emissions_kg IS NOT NULL"
    )

    # ── Route stops: Delhivery real-world route data columns ──────────────────
    op.add_column("route_stops", sa.Column("source_center_code", sa.String(50), nullable=True))
    op.add_column("route_stops", sa.Column("dest_center_code", sa.String(50), nullable=True))
    op.add_column("route_stops", sa.Column("osrm_distance_km", sa.Numeric(10, 4), nullable=True))
    op.add_column("route_stops", sa.Column("osrm_time_min", sa.Numeric(8, 2), nullable=True))
    op.add_column("route_stops", sa.Column("actual_time_min", sa.Numeric(8, 2), nullable=True))
    op.add_column("route_stops", sa.Column("delay_factor", sa.Numeric(6, 4), nullable=True))
    op.add_column("route_stops", sa.Column("route_type", sa.String(20), nullable=True))

    # ── Routes: external_route_id for delhivery schedule UUID ────────────────
    op.add_column("routes", sa.Column("external_route_id", sa.String(200), nullable=True))
    op.create_index(
        "ix_routes_external_route_id",
        "routes",
        ["tenant_id", "external_route_id"],
        postgresql_where=sa.text("external_route_id IS NOT NULL"),
    )

    # ── Shipments: mobile sales lead-time column ──────────────────────────────
    op.add_column("shipments", sa.Column("lead_time_days", sa.Integer, nullable=True))
    op.add_column("shipments", sa.Column("product_brand", sa.String(100), nullable=True))
    op.add_column("shipments", sa.Column("product_sku", sa.String(100), nullable=True))


def downgrade() -> None:
    op.drop_column("shipments", "product_sku")
    op.drop_column("shipments", "product_brand")
    op.drop_column("shipments", "lead_time_days")
    op.drop_index("ix_routes_external_route_id", "routes")
    op.drop_column("routes", "external_route_id")
    op.drop_column("route_stops", "route_type")
    op.drop_column("route_stops", "delay_factor")
    op.drop_column("route_stops", "actual_time_min")
    op.drop_column("route_stops", "osrm_time_min")
    op.drop_column("route_stops", "osrm_distance_km")
    op.drop_column("route_stops", "dest_center_code")
    op.drop_column("route_stops", "source_center_code")
    op.execute("DROP INDEX IF EXISTS ix_shipments_tenant_co2")
    op.drop_column("shipments", "profit_loss")
    op.drop_column("shipments", "return_reason")
    op.drop_column("shipments", "waste_avoided_kg")
    op.drop_column("shipments", "co2_saved_kg")
    op.drop_column("shipments", "packaging_waste_kg")
    op.drop_column("shipments", "co2_emissions_kg")
