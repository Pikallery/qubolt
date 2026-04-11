"""
Pydantic schemas for three Rajya Sabha sustainability reference CSVs:

  RS_Session_256_AU_1006_A.i.csv   (3 rows)
    Financial Year, Estimated Generation in Tonnes
    → EwasteGenerationRow  (EWASTE_GENERATION)

  rs_session243_au1646_1.1.csv     (15 rows)
    Sl. No., States/ UTs, Number of registered Dismantler and Recycler,
    Registered Capacity in tonne per Annum
    → EwasteRecyclerRow    (EWASTE_RECYCLERS)

  Rajya_Sabha_Session_234_AU2536_1.csv  (35 rows)
    Sr. No., Name of the State / UT,
    MSW MT/ day 1999-2000 Class I/II/Total, MSW MT/ day (2012)
    → MswGenerationRow     (MSW_GENERATION)

All rows land in the `sustainability_benchmarks` table (migration 0006).
"""
from __future__ import annotations

from decimal import Decimal, InvalidOperation

from pydantic import BaseModel, Field, field_validator


def _safe_decimal(v: object) -> Decimal | None:
    s = str(v).strip().replace(",", "")
    if s.upper() in ("", "NA", "N/A", "NAN", "NONE", "NULL", "-"):
        return None
    try:
        return Decimal(s)
    except InvalidOperation:
        return None


# ── E-Waste Generation ─────────────────────────────────────────────────────────

class EwasteGenerationRow(BaseModel):
    """RS_Session_256_AU_1006_A.i.csv — national e-waste generation by FY."""

    financial_year: str = Field(alias="Financial Year")
    estimated_tonnes: Decimal | None = Field(
        default=None, alias="Estimated Generation in Tonnes"
    )

    model_config = {"populate_by_name": True}

    @field_validator("financial_year", mode="before")
    @classmethod
    def strip_str(cls, v: object) -> str:
        return str(v).strip()

    @field_validator("estimated_tonnes", mode="before")
    @classmethod
    def coerce_decimal(cls, v: object) -> Decimal | None:
        return _safe_decimal(v)

    def to_benchmark_dict(self) -> dict:
        return {
            "benchmark_type": "ewaste_generation",
            "financial_year": self.financial_year,
            "state_ut": "India",
            "metric_name": "estimated_generation_tonnes",
            "metric_value": float(self.estimated_tonnes) if self.estimated_tonnes is not None else None,
            "unit": "tonnes",
            "source": "RS_Session_256_AU_1006",
        }


# ── E-Waste Recyclers ──────────────────────────────────────────────────────────

class EwasteRecyclerRow(BaseModel):
    """rs_session243_au1646_1.1.csv — state-wise registered e-waste recyclers."""

    sl_no: str | None = Field(default=None, alias="Sl. No.")
    state_ut: str = Field(alias="States/ UTs")
    recycler_count: int | None = Field(
        default=None, alias="Number of registered Dismantler and Recycler"
    )
    registered_capacity_tpa: Decimal | None = Field(
        default=None, alias="Registered Capacity in tonne per Annum"
    )

    model_config = {"populate_by_name": True}

    @field_validator("state_ut", mode="before")
    @classmethod
    def strip_str(cls, v: object) -> str:
        return str(v).strip()

    @field_validator("recycler_count", mode="before")
    @classmethod
    def coerce_int(cls, v: object) -> int | None:
        s = str(v).strip().replace(",", "")
        if s.upper() in ("", "NA", "NONE", "NULL", "-"):
            return None
        try:
            return int(float(s))
        except (ValueError, TypeError):
            return None

    @field_validator("registered_capacity_tpa", mode="before")
    @classmethod
    def coerce_decimal(cls, v: object) -> Decimal | None:
        return _safe_decimal(v)

    def to_benchmark_dict(self) -> dict:
        return {
            "benchmark_type": "ewaste_recyclers",
            "financial_year": None,
            "state_ut": self.state_ut,
            "metric_name": "registered_recycler_count",
            "metric_value": float(self.recycler_count) if self.recycler_count is not None else None,
            "unit": "count",
            "source": "RS_Session_243_AU1646",
        }


# ── Municipal Solid Waste ──────────────────────────────────────────────────────

class MswGenerationRow(BaseModel):
    """Rajya_Sabha_Session_234_AU2536_1.csv — state-wise MSW generation."""

    sr_no: str | None = Field(default=None, alias="Sr. No.")
    state_ut: str = Field(alias="Name of the State / UT")
    msw_class1_1999: Decimal | None = Field(
        default=None,
        alias="MSW MT/ day 1999-2000 - Class \ufffd I (cities)",
    )
    msw_class2_1999: Decimal | None = Field(
        default=None,
        alias="MSW MT/ day 1999-2000 - Class \ufffd II (Towns)",
    )
    msw_total_1999: Decimal | None = Field(
        default=None,
        alias="MSW MT/ day 1999-2000 - Total",
    )
    msw_2012: Decimal | None = Field(
        default=None, alias="MSW MT/ day (2012)"
    )

    model_config = {"populate_by_name": True}

    @field_validator("state_ut", mode="before")
    @classmethod
    def strip_str(cls, v: object) -> str:
        return str(v).strip()

    @field_validator(
        "msw_class1_1999", "msw_class2_1999", "msw_total_1999", "msw_2012",
        mode="before",
    )
    @classmethod
    def coerce_decimal(cls, v: object) -> Decimal | None:
        return _safe_decimal(v)

    def to_benchmark_dict(self) -> dict:
        return {
            "benchmark_type": "msw_generation",
            "financial_year": "2012",
            "state_ut": self.state_ut,
            "metric_name": "msw_mt_per_day_2012",
            "metric_value": float(self.msw_2012) if self.msw_2012 is not None else None,
            "unit": "MT/day",
            "source": "RS_Session_234_AU2536",
        }
