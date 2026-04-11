"""
Pydantic schema for Ecommerce_Delivery_Analytics_New.csv (100,000 rows).

Known quirks:
- 'Order Date & Time' is stored as 'MM:SS.f' (e.g. '19:29.5'), NOT a proper datetime.
  There is no date component.  We store it raw and optionally parse minutes/seconds.
- Order ID follows the pattern 'ORD-XXXXXXXX'.
- Customer ID follows the pattern 'CUST-XXXXXXXX'.
- Platform values include 'Blinkit', 'JioMart', 'Swiggy Instamart', etc.
- Delivery Delay and Refund Requested are 'Yes'/'No' strings.
"""
from __future__ import annotations

from decimal import Decimal

from pydantic import BaseModel, Field, field_validator


class EcommerceAnalyticsRow(BaseModel):
    """
    Maps one row from Ecommerce_Delivery_Analytics_New.csv.
    Use model_validate(row_dict, strict=False).
    """

    order_id: str = Field(alias="Order ID")
    customer_id: str = Field(alias="Customer ID")
    platform: str = Field(alias="Platform")
    order_time_raw: str = Field(alias="Order Date & Time")
    delivery_time_minutes: int = Field(alias="Delivery Time (Minutes)", ge=0)
    product_category: str = Field(alias="Product Category")
    order_value_inr: Decimal = Field(alias="Order Value (INR)")
    customer_feedback: str | None = Field(default=None, alias="Customer Feedback")
    service_rating: int = Field(alias="Service Rating", ge=1, le=5)
    delivery_delay: str = Field(alias="Delivery Delay")
    refund_requested: str = Field(alias="Refund Requested")

    model_config = {"populate_by_name": True}

    # ── Validators ─────────────────────────────────────────────────────────────

    @field_validator("order_value_inr", mode="before")
    @classmethod
    def coerce_decimal(cls, v: object) -> Decimal:
        s = str(v).strip()
        if s in ("", "nan", "NaN", "null", "None"):
            return Decimal("0")
        return Decimal(s)

    @field_validator("service_rating", mode="before")
    @classmethod
    def coerce_rating(cls, v: object) -> int:
        return max(1, min(5, int(float(str(v)))))

    @field_validator("delivery_time_minutes", mode="before")
    @classmethod
    def coerce_int(cls, v: object) -> int:
        return max(0, int(float(str(v))))

    @field_validator("delivery_delay", "refund_requested", mode="before")
    @classmethod
    def normalise_yes_no(cls, v: object) -> str:
        return str(v).strip().lower()

    @field_validator("order_id", "customer_id", "platform", "product_category", mode="before")
    @classmethod
    def normalise_str(cls, v: object) -> str:
        return str(v).strip()

    @field_validator("customer_feedback", mode="before")
    @classmethod
    def optional_str(cls, v: object) -> str | None:
        s = str(v).strip() if v is not None else ""
        return s if s not in ("", "nan", "NaN", "None") else None

    # ── Computed helpers ──────────────────────────────────────────────────────

    def is_delayed(self) -> bool:
        return self.delivery_delay in ("yes", "true", "1")

    def is_refunded(self) -> bool:
        return self.refund_requested in ("yes", "true", "1")

    def order_time_minutes(self) -> int | None:
        """
        Parse 'MM:SS.f' as total minutes offset (ignoring sub-minute precision).
        Returns None if the format is unexpected.
        """
        try:
            parts = self.order_time_raw.split(":")
            return int(parts[0])
        except (IndexError, ValueError):
            return None

    # ── Output mapping ────────────────────────────────────────────────────────

    def to_shipment_dict(self) -> dict:
        return {
            "external_id": self.order_id,
            "platform": self.platform,
            "order_value_inr": float(self.order_value_inr),
            "is_delayed": self.is_delayed(),
            "refund_requested": self.is_refunded(),
            "rating": self.service_rating,
            "package_type": self.product_category.lower(),
            "delivery_mode": "express",  # no mode column in this dataset
        }

    def to_customer_external_id(self) -> str:
        return self.customer_id
