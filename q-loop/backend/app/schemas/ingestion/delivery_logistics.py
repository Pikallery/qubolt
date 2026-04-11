"""
Pydantic schema for Delivery_Logistics.csv (25,000 rows).

Known quirks from the dataset:
- delivery_id is stored as a float (e.g. 250.99) — treated as an opaque external ref string.
- delivery_time_hours and expected_time_hours are nanosecond-epoch datetime strings
  in the form  '1970-01-01 00:00:00.000000008', where the fractional nanoseconds
  encode the actual value in nanoseconds (e.g. 8 ns → 8 / 1e9 = ~0 seconds).
  We parse fractional nanos and convert to float seconds.
- weather_condition, delivery_status, vehicle_type, delivery_mode are free-text enums
  with minor casing inconsistencies (normalised to lowercase + underscore).
"""
from __future__ import annotations

from decimal import Decimal

from pydantic import BaseModel, Field, field_validator


class DeliveryLogisticsRow(BaseModel):
    """
    Maps one row from Delivery_Logistics.csv.
    Use model_validate(row_dict, strict=False) for each CSV dict row.
    """

    # ── Fields (aliases match CSV headers exactly) ────────────────────────────
    delivery_id_raw: str = Field(alias="delivery_id")
    delivery_partner: str = Field(alias="delivery_partner")
    package_type: str = Field(alias="package_type")
    vehicle_type: str = Field(alias="vehicle_type")
    delivery_mode: str = Field(alias="delivery_mode")
    region: str = Field(alias="region")
    weather_condition: str = Field(alias="weather_condition")
    distance_km: Decimal = Field(alias="distance_km")
    package_weight_kg: Decimal = Field(alias="package_weight_kg")
    delivery_time_raw: str = Field(alias="delivery_time_hours")
    expected_time_raw: str = Field(alias="expected_time_hours")
    delayed: str = Field(alias="delayed")
    delivery_status: str = Field(alias="delivery_status")
    delivery_rating: int = Field(alias="delivery_rating", ge=1, le=5)
    delivery_cost: Decimal = Field(alias="delivery_cost")

    model_config = {"populate_by_name": True}

    # ── Validators ────────────────────────────────────────────────────────────

    @field_validator("delivery_id_raw", mode="before")
    @classmethod
    def coerce_id(cls, v: object) -> str:
        """Float 250.99 → string '250.99'"""
        return str(v).strip()

    @field_validator("distance_km", "package_weight_kg", "delivery_cost", mode="before")
    @classmethod
    def coerce_decimal(cls, v: object) -> Decimal:
        s = str(v).strip()
        if s in ("", "nan", "NaN", "null", "None"):
            return Decimal("0")
        return Decimal(s)

    @field_validator("delivery_rating", mode="before")
    @classmethod
    def coerce_rating(cls, v: object) -> int:
        return max(1, min(5, int(float(str(v)))))

    @field_validator("delayed", mode="before")
    @classmethod
    def normalise_delayed(cls, v: object) -> str:
        return str(v).strip().lower()

    @field_validator(
        "delivery_partner", "package_type", "vehicle_type",
        "delivery_mode", "region", "weather_condition", "delivery_status",
        mode="before",
    )
    @classmethod
    def normalise_str(cls, v: object) -> str:
        return str(v).strip()

    # ── Computed helpers ──────────────────────────────────────────────────────

    def is_delayed_bool(self) -> bool:
        return self.delayed in ("yes", "true", "1")

    def _parse_nanos(self, raw: str) -> float | None:
        """
        Parse a nanosecond-epoch datetime string like '1970-01-01 00:00:00.000000008'.
        Returns the value as fractional seconds (float).
        """
        try:
            # The fractional part after the last '.' is nanoseconds since epoch
            frac = raw.split(".")[-1]
            ns = int(frac)
            return ns / 1_000_000_000.0
        except (IndexError, ValueError):
            return None

    def delivery_time_seconds(self) -> float | None:
        return self._parse_nanos(self.delivery_time_raw)

    def expected_time_seconds(self) -> float | None:
        return self._parse_nanos(self.expected_time_raw)

    def normalised_vehicle_type(self) -> str:
        return self.vehicle_type.lower().replace(" ", "_")

    def normalised_delivery_mode(self) -> str:
        return self.delivery_mode.lower().replace(" ", "_")

    # ── Output mapping ────────────────────────────────────────────────────────

    def to_shipment_dict(self) -> dict:
        return {
            "external_id": self.delivery_id_raw,
            "package_type": self.package_type.lower(),
            "vehicle_type": self.normalised_vehicle_type(),
            "delivery_mode": self.normalised_delivery_mode(),
            "region": self.region,
            "weather_at_dispatch": self.weather_condition,
            "distance_km": float(self.distance_km),
            "weight_kg": float(self.package_weight_kg),
            "delivery_cost": float(self.delivery_cost),
            "is_delayed": self.is_delayed_bool(),
            "status": self.delivery_status.lower(),
            "rating": self.delivery_rating,
        }

    def to_partner_name(self) -> str:
        return self.delivery_partner.strip()
