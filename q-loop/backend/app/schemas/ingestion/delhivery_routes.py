"""
Pydantic schema for delhivery_data.csv (144,867 rows).

Real Delhivery logistics network data. Each row is a route SEGMENT:
  - route_type: 'FTL' (Full Truck Load, long-haul) or 'Carting' (last-mile)
  - od_start_time / od_end_time: origin-destination actual scan timestamps
  - actual_distance_to_destination: GPS distance in km
  - osrm_time / osrm_distance: OSRM road-routing benchmark (time in min, dist in km)
  - factor: actual_time / osrm_time — ratio > 1 means delays vs routing model
  - segment_*: per-segment values (can differ from full trip values in multi-hop routes)

Maps to:
  - delivery_partners: one partner row for 'Delhivery' (upsert)
  - routes: one row per route_schedule_uuid
  - route_stops: two rows per segment (source_center → destination_center)
  - shipments: synthetic shipment record per segment for dashboard aggregation
"""
from __future__ import annotations

from datetime import datetime
from decimal import Decimal

from pydantic import BaseModel, Field, field_validator


class DelhiveryRouteRow(BaseModel):
    """Maps one segment row from delhivery_data.csv."""

    data_split: str = Field(alias="data")                    # 'training' | 'test'
    trip_creation_time: str = Field(alias="trip_creation_time")
    route_schedule_uuid: str = Field(alias="route_schedule_uuid")
    route_type: str = Field(alias="route_type")               # FTL | Carting
    trip_uuid: str = Field(alias="trip_uuid")
    source_center: str = Field(alias="source_center")
    source_name: str = Field(alias="source_name")
    destination_center: str = Field(alias="destination_center")
    destination_name: str = Field(alias="destination_name")
    od_start_time: str = Field(alias="od_start_time")
    od_end_time: str = Field(alias="od_end_time")
    start_scan_to_end_scan: Decimal = Field(alias="start_scan_to_end_scan")  # minutes
    is_cutoff: str = Field(alias="is_cutoff")
    cutoff_factor: str | None = Field(default=None, alias="cutoff_factor")
    cutoff_timestamp: str | None = Field(default=None, alias="cutoff_timestamp")
    actual_distance_to_destination: Decimal = Field(alias="actual_distance_to_destination")
    actual_time: Decimal = Field(alias="actual_time")             # minutes
    osrm_time: Decimal = Field(alias="osrm_time")                 # minutes
    osrm_distance: Decimal = Field(alias="osrm_distance")         # km
    factor: Decimal = Field(alias="factor")                       # actual/osrm ratio
    segment_actual_time: Decimal = Field(alias="segment_actual_time")
    segment_osrm_time: Decimal = Field(alias="segment_osrm_time")
    segment_osrm_distance: Decimal = Field(alias="segment_osrm_distance")
    segment_factor: Decimal = Field(alias="segment_factor")

    model_config = {"populate_by_name": True}

    @field_validator(
        "start_scan_to_end_scan", "actual_distance_to_destination",
        "actual_time", "osrm_time", "osrm_distance", "factor",
        "segment_actual_time", "segment_osrm_time", "segment_osrm_distance",
        "segment_factor",
        mode="before",
    )
    @classmethod
    def coerce_decimal(cls, v: object) -> Decimal:
        s = str(v).strip()
        if s in ("", "nan", "NaN", "null", "None"):
            return Decimal("0")
        return Decimal(s)

    @field_validator(
        "data_split", "route_schedule_uuid", "route_type", "trip_uuid",
        "source_center", "source_name", "destination_center", "destination_name",
        mode="before",
    )
    @classmethod
    def normalise_str(cls, v: object) -> str:
        return str(v).strip()

    @field_validator("is_cutoff", mode="before")
    @classmethod
    def normalise_bool_str(cls, v: object) -> str:
        return str(v).strip().lower()

    # ── Computed helpers ──────────────────────────────────────────────────────

    def is_cutoff_bool(self) -> bool:
        return self.is_cutoff in ("true", "1", "yes")

    def is_delayed(self) -> bool:
        """Segment is delayed if actual_time > osrm_time by more than 20%."""
        if self.osrm_time == 0:
            return False
        return float(self.factor) > 1.2

    def parse_trip_creation(self) -> datetime | None:
        try:
            return datetime.fromisoformat(self.trip_creation_time)
        except ValueError:
            return None

    def delay_minutes(self) -> float:
        """Extra minutes vs OSRM estimate."""
        return max(0.0, float(self.actual_time) - float(self.osrm_time))

    # ── Output mappings ───────────────────────────────────────────────────────

    def to_route_dict(self) -> dict:
        """One route per unique route_schedule_uuid."""
        return {
            "external_id": self.route_schedule_uuid,
            "optimized_by": "delhivery_osrm",
            "status": "completed",
            "total_distance_km": float(self.osrm_distance),
        }

    def to_shipment_dict(self) -> dict:
        """Synthetic shipment per segment for aggregation / forecasting."""
        return {
            "external_id": self.trip_uuid,
            "vehicle_type": "truck" if self.route_type == "FTL" else "bike",
            "delivery_mode": "express" if self.route_type == "FTL" else "same_day",
            "region": self._extract_state(self.source_name),
            "distance_km": float(self.actual_distance_to_destination),
            "is_delayed": self.is_delayed(),
            "status": "delivered",
            "priority": "high" if self.route_type == "FTL" else "medium",
        }

    def to_source_stop_dict(self) -> dict:
        return {"external_id": self.source_center, "name": self.source_name}

    def to_dest_stop_dict(self) -> dict:
        return {"external_id": self.destination_center, "name": self.destination_name}

    @staticmethod
    def _extract_state(name: str) -> str:
        """Extract state from hub name like 'Anand_VUNagar_DC (Gujarat)'."""
        if "(" in name and ")" in name:
            return name.split("(")[-1].rstrip(")")
        return name.split("_")[0] if "_" in name else name
