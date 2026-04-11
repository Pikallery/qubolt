"""
Pydantic schema for returns_sustainability_dataset.csv (5,000 rows).

Returns + environmental impact data — directly feeds Q-Loop's core value prop:
optimizing the RETURNS and DISPOSAL loop to reduce empty runs.

Key sustainability fields:
  - CO2_Emissions: kg CO2 from this order's delivery
  - Packaging_Waste: kg of packaging material used
  - CO2_Saved: kg CO2 avoided (e.g. consolidated return routing)
  - Waste_Avoided: kg packaging waste avoided via optimized routing
  - Return_Status: 'Returned' | 'Not Returned'
  - Return_Reason: reason for return (maps to risk patterns)

Maps to:
  - shipments table (+ sustainability columns via migration 0005)
  - customers table
"""
from __future__ import annotations

from datetime import date, datetime
from decimal import Decimal

from pydantic import BaseModel, Field, field_validator


class ReturnsSustainabilityRow(BaseModel):
    """Maps one row from returns_sustainability_dataset.csv."""

    order_id: str = Field(alias="Order_ID")
    product_id: str = Field(alias="Product_ID")
    user_id: str = Field(alias="User_ID")
    order_date: str = Field(alias="Order_Date")
    product_category: str = Field(alias="Product_Category")
    product_price: Decimal = Field(alias="Product_Price")
    order_quantity: int = Field(alias="Order_Quantity", ge=1)
    discount_applied: Decimal = Field(alias="Discount_Applied")
    shipping_method: str = Field(alias="Shipping_Method")    # Standard|Express|Next-Day
    payment_method: str = Field(alias="Payment_Method")
    user_age: int | None = Field(default=None, alias="User_Age")
    user_gender: str | None = Field(default=None, alias="User_Gender")
    user_location: str = Field(alias="User_Location")
    return_status: str = Field(alias="Return_Status")        # Returned|Not Returned
    return_reason: str | None = Field(default=None, alias="Return_Reason")
    days_to_return: int = Field(alias="Days_to_Return", ge=0)
    order_value: Decimal = Field(alias="Order_Value")
    return_cost: Decimal = Field(alias="Return_Cost")
    profit_loss: Decimal = Field(alias="Profit_Loss")
    co2_emissions: Decimal = Field(alias="CO2_Emissions")    # kg CO2 emitted
    packaging_waste: Decimal = Field(alias="Packaging_Waste") # kg waste
    co2_saved: Decimal = Field(alias="CO2_Saved")            # kg CO2 avoided
    waste_avoided: Decimal = Field(alias="Waste_Avoided")    # kg waste avoided

    model_config = {"populate_by_name": True}

    @field_validator(
        "product_price", "discount_applied", "order_value",
        "return_cost", "profit_loss", "co2_emissions",
        "packaging_waste", "co2_saved", "waste_avoided",
        mode="before",
    )
    @classmethod
    def coerce_decimal(cls, v: object) -> Decimal:
        s = str(v).strip()
        if s in ("", "nan", "NaN", "null", "None"):
            return Decimal("0")
        return Decimal(s)

    @field_validator("order_quantity", "days_to_return", mode="before")
    @classmethod
    def coerce_int(cls, v: object) -> int:
        return max(0, int(float(str(v))))

    @field_validator("user_age", mode="before")
    @classmethod
    def coerce_optional_int(cls, v: object) -> int | None:
        try:
            return int(float(str(v)))
        except (ValueError, TypeError):
            return None

    @field_validator(
        "order_id", "product_id", "user_id", "product_category",
        "shipping_method", "payment_method", "user_location", "return_status",
        mode="before",
    )
    @classmethod
    def normalise_str(cls, v: object) -> str:
        return str(v).strip()

    @field_validator("return_reason", "user_gender", mode="before")
    @classmethod
    def optional_str(cls, v: object) -> str | None:
        s = str(v).strip() if v else ""
        return s if s not in ("", "nan", "None", "No Return") else None

    # ── Computed helpers ──────────────────────────────────────────────────────

    def is_returned(self) -> bool:
        return self.return_status.lower() == "returned"

    def delivery_mode(self) -> str:
        mapping = {
            "next-day": "same_day",
            "express": "express",
            "standard": "two_day",
        }
        return mapping.get(self.shipping_method.lower(), "standard")

    def parse_order_date(self) -> date | None:
        for fmt in ("%Y-%m-%d", "%d/%m/%Y", "%m/%d/%Y"):
            try:
                return datetime.strptime(self.order_date, fmt).date()
            except ValueError:
                continue
        return None

    def net_co2_impact(self) -> Decimal:
        """Net CO2 = emissions - saved. Negative = net positive for environment."""
        return self.co2_emissions - self.co2_saved

    # ── Output mappings ───────────────────────────────────────────────────────

    def to_customer_dict(self) -> dict:
        return {
            "external_id": self.user_id,
            "name": f"Customer {self.user_id}",
        }

    def to_address_dict(self) -> dict:
        return {
            "address_text": self.user_location,
            "area": self.user_location,
            "is_default": True,
        }

    def to_shipment_dict(self) -> dict:
        """
        Maps to shipments table.
        Sustainability columns (co2_emissions, packaging_waste, etc.)
        are stored via migration 0005.
        """
        return {
            "external_id": self.order_id,
            "package_type": self.product_category.lower(),
            "delivery_mode": self.delivery_mode(),
            "order_value_inr": float(self.order_value),
            "delivery_cost": float(self.return_cost) if self.is_returned() else None,
            "is_delayed": False,
            "refund_requested": self.is_returned(),
            "status": "returned" if self.is_returned() else "delivered",
            "priority": "high" if self.shipping_method == "Next-Day" else "medium",
            # Sustainability fields (stored if migration 0005 applied)
            "_co2_emissions_kg": float(self.co2_emissions),
            "_packaging_waste_kg": float(self.packaging_waste),
            "_co2_saved_kg": float(self.co2_saved),
            "_waste_avoided_kg": float(self.waste_avoided),
            "_return_reason": self.return_reason,
            "_profit_loss": float(self.profit_loss),
        }
