"""
Pydantic schema for delivery_points_rourkela.csv (500 rows).

Maps geo-tagged delivery points in Rourkela to:
  - customers table  (customer name, external_id)
  - customer_addresses table  (lat/lon, address, area, pincode)
  - shipments table seed (order_type → package_type, order_value_inr, priority)
"""
from __future__ import annotations

from decimal import Decimal
from typing import Literal

from pydantic import BaseModel, Field, field_validator

PriorityLiteral = Literal["low", "medium", "high"]

# Rourkela bounding box (approx) for coordinate sanity check
_LAT_MIN, _LAT_MAX = 21.0, 23.0
_LON_MIN, _LON_MAX = 83.0, 85.0


class DeliveryPointRow(BaseModel):
    """
    Maps one row from delivery_points_rourkela.csv.
    """

    delivery_id: str = Field(alias="delivery_id")
    customer_name: str = Field(alias="customer_name")
    address: str = Field(alias="address")
    area: str = Field(alias="area")
    pincode: str = Field(alias="pincode")
    latitude: Decimal = Field(alias="latitude")
    longitude: Decimal = Field(alias="longitude")
    order_type: str = Field(alias="order_type")
    order_value_inr: Decimal = Field(alias="order_value_inr")
    priority: str = Field(default="medium", alias="priority")

    model_config = {"populate_by_name": True}

    # ── Validators ─────────────────────────────────────────────────────────────

    @field_validator("latitude", "longitude", mode="before")
    @classmethod
    def coerce_coords(cls, v: object) -> Decimal:
        s = str(v).strip()
        if s in ("", "nan", "NaN", "null", "None"):
            raise ValueError(f"Invalid coordinate value: {v!r}")
        return Decimal(s)

    @field_validator("order_value_inr", mode="before")
    @classmethod
    def coerce_value(cls, v: object) -> Decimal:
        s = str(v).strip()
        if s in ("", "nan", "NaN", "null", "None"):
            return Decimal("0")
        return Decimal(s)

    @field_validator("pincode", mode="before")
    @classmethod
    def normalise_pincode(cls, v: object) -> str:
        return str(v).strip().split(".")[0].zfill(6)  # strip .0 from float pincode

    @field_validator("priority", mode="before")
    @classmethod
    def normalise_priority(cls, v: object) -> str:
        p = str(v).strip().lower()
        return p if p in ("low", "medium", "high") else "medium"

    @field_validator(
        "delivery_id", "customer_name", "address", "area", "order_type", mode="before"
    )
    @classmethod
    def normalise_str(cls, v: object) -> str:
        return str(v).strip()

    # ── Coordinate validation ─────────────────────────────────────────────────

    def validate_coords_in_region(self) -> bool:
        lat = float(self.latitude)
        lon = float(self.longitude)
        return _LAT_MIN <= lat <= _LAT_MAX and _LON_MIN <= lon <= _LON_MAX

    # ── Output mappings ───────────────────────────────────────────────────────

    def to_customer_dict(self) -> dict:
        return {
            "external_id": self.delivery_id,
            "name": self.customer_name,
        }

    def to_address_dict(self) -> dict:
        return {
            "address_text": self.address,
            "area": self.area,
            "pincode": self.pincode,
            "latitude": float(self.latitude),
            "longitude": float(self.longitude),
            "is_default": True,
        }

    def to_shipment_seed_dict(self) -> dict:
        return {
            "external_id": self.delivery_id,
            "package_type": self.order_type.lower(),
            "order_value_inr": float(self.order_value_inr),
            "priority": self.priority,
            "status": "pending",
        }
