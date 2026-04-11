"""
Pydantic schema for cleaned_mobile_phone_sales_data.csv (24,983 rows).

Mobile phone retail sales data:
  - Inward Date / Dispatch Date: warehouse receipt → customer dispatch
  - Product Code: SKU-level tracking
  - Customer Location / Region: maps to customer_addresses + regional analytics

Maps to:
  - customers table (Customer Name + Customer Location)
  - shipments table (Dispatch Date, Price * Quantity Sold = order_value_inr)
  - packages table (Product, Brand, RAM, ROM as package metadata)
"""
from __future__ import annotations

from datetime import date, datetime
from decimal import Decimal

from pydantic import BaseModel, Field, field_validator


class MobileSalesRow(BaseModel):
    """Maps one row from cleaned_mobile_phone_sales_data.csv."""

    product: str = Field(alias="Product")
    brand: str = Field(alias="Brand")
    product_code: str = Field(alias="Product Code")
    product_spec: str | None = Field(default=None, alias="Product Specification")
    price: Decimal = Field(alias="Price")
    inward_date: str = Field(alias="Inward Date")
    dispatch_date: str = Field(alias="Dispatch Date")
    quantity_sold: int = Field(alias="Quantity Sold", ge=0)
    customer_name: str = Field(alias="Customer Name")
    customer_location: str = Field(alias="Customer Location")
    region: str = Field(alias="Region")
    processor_spec: str | None = Field(default=None, alias="Processor Specification")
    ram: str | None = Field(default=None, alias="RAM")
    rom: str | None = Field(default=None, alias="ROM")

    model_config = {"populate_by_name": True}

    @field_validator("price", mode="before")
    @classmethod
    def coerce_decimal(cls, v: object) -> Decimal:
        s = str(v).strip().replace(",", "")
        return Decimal(s) if s not in ("", "nan", "None") else Decimal("0")

    @field_validator("quantity_sold", mode="before")
    @classmethod
    def coerce_int(cls, v: object) -> int:
        return max(0, int(float(str(v))))

    @field_validator(
        "product", "brand", "product_code", "customer_name",
        "customer_location", "region",
        mode="before",
    )
    @classmethod
    def normalise_str(cls, v: object) -> str:
        return str(v).strip()

    @field_validator("product_spec", "processor_spec", "ram", "rom", mode="before")
    @classmethod
    def optional_str(cls, v: object) -> str | None:
        s = str(v).strip() if v else ""
        return s if s not in ("", "nan", "None") else None

    # ── Computed helpers ──────────────────────────────────────────────────────

    def order_value_inr(self) -> Decimal:
        return self.price * self.quantity_sold

    def parse_dispatch_date(self) -> date | None:
        for fmt in ("%Y-%m-%d", "%d/%m/%Y", "%m/%d/%Y"):
            try:
                return datetime.strptime(self.dispatch_date, fmt).date()
            except ValueError:
                continue
        return None

    def parse_inward_date(self) -> date | None:
        for fmt in ("%Y-%m-%d", "%d/%m/%Y", "%m/%d/%Y"):
            try:
                return datetime.strptime(self.inward_date, fmt).date()
            except ValueError:
                continue
        return None

    def lead_time_days(self) -> int | None:
        """Days from inward to dispatch — warehouse dwell time."""
        inward = self.parse_inward_date()
        dispatch = self.parse_dispatch_date()
        if inward and dispatch:
            return max(0, (dispatch - inward).days)
        return None

    # ── Output mappings ───────────────────────────────────────────────────────

    def to_customer_dict(self) -> dict:
        return {
            "external_id": f"MOBI_{self.product_code}_{self.customer_name[:8]}",
            "name": self.customer_name,
        }

    def to_address_dict(self) -> dict:
        return {
            "address_text": self.customer_location,
            "area": self.customer_location,
            "is_default": True,
        }

    def to_shipment_dict(self) -> dict:
        dispatch = self.parse_dispatch_date()
        return {
            "external_id": self.product_code,
            "package_type": f"{self.brand} {self.product}".lower(),
            "delivery_mode": "express",
            "region": self.region.lower(),
            "order_value_inr": float(self.order_value_inr()),
            "status": "delivered",  # dispatch date implies sold/shipped
            "priority": "medium",
            "platform": "retail",
        }

    def to_package_metadata(self) -> dict:
        return {
            "sku": self.product_code,
            "description": (
                f"{self.brand} {self.product} | {self.ram or ''} RAM | "
                f"{self.rom or ''} ROM | {self.processor_spec or ''}"
            ).strip(" |"),
            "quantity": self.quantity_sold,
        }
