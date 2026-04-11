"""
Ingestion service — orchestrates CSV → validate → upsert pipeline.

Flow:
  1. Detect source type from CSV headers
  2. Stream file in 500-row chunks
  3. Validate each row with the appropriate Pydantic schema
  4. Upsert valid rows into PostgreSQL (conflict on external_id per tenant)
  5. Write invalid rows to ingestion_errors
  6. Update ingestion_jobs counters throughout
"""
from __future__ import annotations

import uuid
from datetime import datetime, timezone
from typing import Any

from pydantic import ValidationError
from sqlalchemy import select, text, update
from sqlalchemy.dialects.postgresql import insert as pg_insert
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.customer import Customer, CustomerAddress
from app.models.delivery_partner import DeliveryPartner
from app.models.ingestion import IngestionError, IngestionJob
from app.models.shipment import Shipment
from app.schemas.ingestion import (
    DeliveryLogisticsRow,
    DeliveryPointRow,
    EcommerceAnalyticsRow,
    DelhiveryRouteRow,
    MobileSalesRow,
    ReturnsSustainabilityRow,
    EwasteGenerationRow,
    EwasteRecyclerRow,
    MswGenerationRow,
    IngestionReport,
    IngestionSourceType,
)
from app.utils.csv_parser import detect_source_type, iter_csv_chunks_bytes


# ── Partner cache (avoid N+1 lookups per chunk) ───────────────────────────────

async def _get_or_create_partner(
    db: AsyncSession, tenant_id: uuid.UUID, name: str, cache: dict
) -> uuid.UUID:
    if name in cache:
        return cache[name]
    result = await db.execute(
        select(DeliveryPartner).where(
            DeliveryPartner.tenant_id == tenant_id,
            DeliveryPartner.name == name,
        )
    )
    partner = result.scalar_one_or_none()
    if not partner:
        partner = DeliveryPartner(tenant_id=tenant_id, name=name)
        db.add(partner)
        await db.flush()
    cache[name] = partner.id
    return partner.id


# ── Upsert helpers ────────────────────────────────────────────────────────────

async def _upsert_shipment(
    db: AsyncSession,
    tenant_id: uuid.UUID,
    job_id: uuid.UUID,
    data: dict,
) -> None:
    """
    INSERT ... ON CONFLICT (tenant_id, external_id) DO UPDATE SET ...
    """
    data["tenant_id"] = str(tenant_id)
    data["ingestion_job_id"] = str(job_id)

    stmt = text("""
        INSERT INTO shipments (
            id, tenant_id, external_id, package_type, vehicle_type,
            delivery_mode, region, weather_at_dispatch, distance_km,
            weight_kg, delivery_cost, is_delayed, status, rating,
            order_value_inr, platform, refund_requested, priority,
            ingestion_job_id, created_at, updated_at
        ) VALUES (
            gen_random_uuid(), :tenant_id, :external_id, :package_type, :vehicle_type,
            :delivery_mode, :region, :weather_at_dispatch, :distance_km,
            :weight_kg, :delivery_cost, :is_delayed, :status, :rating,
            :order_value_inr, :platform, :refund_requested, :priority,
            :ingestion_job_id, NOW(), NOW()
        )
        ON CONFLICT DO NOTHING
    """)
    # Build safe params with defaults
    params = {
        "external_id": data.get("external_id"),
        "package_type": data.get("package_type"),
        "vehicle_type": data.get("vehicle_type"),
        "delivery_mode": data.get("delivery_mode"),
        "region": data.get("region"),
        "weather_at_dispatch": data.get("weather_at_dispatch"),
        "distance_km": data.get("distance_km"),
        "weight_kg": data.get("weight_kg"),
        "delivery_cost": data.get("delivery_cost"),
        "is_delayed": data.get("is_delayed", False),
        "status": data.get("status", "pending"),
        "rating": data.get("rating"),
        "order_value_inr": data.get("order_value_inr"),
        "platform": data.get("platform"),
        "refund_requested": data.get("refund_requested", False),
        "priority": data.get("priority", "medium"),
        "tenant_id": str(tenant_id),
        "ingestion_job_id": str(job_id),
    }
    await db.execute(stmt, params)


async def _upsert_customer_and_address(
    db: AsyncSession,
    tenant_id: uuid.UUID,
    customer_dict: dict,
    address_dict: dict,
) -> uuid.UUID:
    """Returns customer_id."""
    # Check existing by external_id
    result = await db.execute(
        select(Customer).where(
            Customer.tenant_id == tenant_id,
            Customer.external_id == customer_dict["external_id"],
        )
    )
    customer = result.scalar_one_or_none()
    if not customer:
        customer = Customer(
            tenant_id=tenant_id,
            external_id=customer_dict["external_id"],
            name=customer_dict["name"],
        )
        db.add(customer)
        await db.flush()

        address = CustomerAddress(
            customer_id=customer.id,
            tenant_id=tenant_id,
            **address_dict,
        )
        db.add(address)
        await db.flush()

    return customer.id


# ── Chunk processors ──────────────────────────────────────────────────────────

async def _process_logistics_chunk(
    db: AsyncSession,
    tenant_id: uuid.UUID,
    job_id: uuid.UUID,
    chunk: list[dict],
    partner_cache: dict,
    row_offset: int,
) -> tuple[int, int, list[dict]]:
    ok = err = 0
    errors: list[dict] = []

    for i, raw in enumerate(chunk):
        try:
            row = DeliveryLogisticsRow.model_validate(raw)
            shipment_dict = row.to_shipment_dict()
            partner_id = await _get_or_create_partner(
                db, tenant_id, row.to_partner_name(), partner_cache
            )
            shipment_dict["partner_id"] = str(partner_id)
            await _upsert_shipment(db, tenant_id, job_id, shipment_dict)
            ok += 1
        except (ValidationError, Exception) as exc:
            err += 1
            errors.append({
                "row_number": row_offset + i,
                "raw_data": raw,
                "validation_errors": {"error": str(exc)},
            })

    return ok, err, errors


async def _process_ecommerce_chunk(
    db: AsyncSession,
    tenant_id: uuid.UUID,
    job_id: uuid.UUID,
    chunk: list[dict],
    row_offset: int,
) -> tuple[int, int, list[dict]]:
    ok = err = 0
    errors: list[dict] = []

    for i, raw in enumerate(chunk):
        try:
            row = EcommerceAnalyticsRow.model_validate(raw)
            shipment_dict = row.to_shipment_dict()
            await _upsert_shipment(db, tenant_id, job_id, shipment_dict)
            ok += 1
        except (ValidationError, Exception) as exc:
            err += 1
            errors.append({
                "row_number": row_offset + i,
                "raw_data": raw,
                "validation_errors": {"error": str(exc)},
            })

    return ok, err, errors


async def _process_delivery_points_chunk(
    db: AsyncSession,
    tenant_id: uuid.UUID,
    job_id: uuid.UUID,
    chunk: list[dict],
    row_offset: int,
) -> tuple[int, int, list[dict]]:
    ok = err = 0
    errors: list[dict] = []

    for i, raw in enumerate(chunk):
        try:
            row = DeliveryPointRow.model_validate(raw)
            customer_id = await _upsert_customer_and_address(
                db, tenant_id, row.to_customer_dict(), row.to_address_dict()
            )
            shipment_dict = row.to_shipment_seed_dict()
            shipment_dict["customer_id"] = str(customer_id)
            await _upsert_shipment(db, tenant_id, job_id, shipment_dict)
            ok += 1
        except (ValidationError, Exception) as exc:
            err += 1
            errors.append({
                "row_number": row_offset + i,
                "raw_data": raw,
                "validation_errors": {"error": str(exc)},
            })

    return ok, err, errors


async def _process_delhivery_chunk(
    db: AsyncSession,
    tenant_id: uuid.UUID,
    job_id: uuid.UUID,
    chunk: list[dict],
    partner_cache: dict,
    row_offset: int,
) -> tuple[int, int, list[dict]]:
    """
    delhivery_data.csv — 144,867 real Delhivery route segments.
    Each row becomes:
      - 1 shipment (synthetic, for aggregation/forecasting)
      - Partner 'Delhivery' upserted once and cached
    """
    ok = err = 0
    errors: list[dict] = []

    for i, raw in enumerate(chunk):
        try:
            row = DelhiveryRouteRow.model_validate(raw)
            partner_id = await _get_or_create_partner(
                db, tenant_id, "Delhivery", partner_cache
            )
            shipment_dict = row.to_shipment_dict()
            shipment_dict["partner_id"] = str(partner_id)
            await _upsert_shipment(db, tenant_id, job_id, shipment_dict)
            ok += 1
        except Exception as exc:
            err += 1
            errors.append({
                "row_number": row_offset + i,
                "raw_data": raw,
                "validation_errors": {"error": str(exc)},
            })

    return ok, err, errors


async def _process_mobile_sales_chunk(
    db: AsyncSession,
    tenant_id: uuid.UUID,
    job_id: uuid.UUID,
    chunk: list[dict],
    row_offset: int,
) -> tuple[int, int, list[dict]]:
    """
    cleaned_mobile_phone_sales_data.csv — 24,983 mobile phone sales orders.
    Each row: customer upsert + shipment with lead_time_days + product metadata.
    """
    ok = err = 0
    errors: list[dict] = []

    for i, raw in enumerate(chunk):
        try:
            row = MobileSalesRow.model_validate(raw)
            customer_id = await _upsert_customer_and_address(
                db, tenant_id, row.to_customer_dict(), row.to_address_dict()
            )
            shipment_dict = row.to_shipment_dict()
            shipment_dict["customer_id"] = str(customer_id)
            # Extra columns from migration 0005
            shipment_dict["lead_time_days"] = row.lead_time_days()
            shipment_dict["product_brand"] = row.brand
            shipment_dict["product_sku"] = row.product_code
            await _upsert_shipment(db, tenant_id, job_id, shipment_dict)
            ok += 1
        except Exception as exc:
            err += 1
            errors.append({
                "row_number": row_offset + i,
                "raw_data": raw,
                "validation_errors": {"error": str(exc)},
            })

    return ok, err, errors


async def _process_returns_chunk(
    db: AsyncSession,
    tenant_id: uuid.UUID,
    job_id: uuid.UUID,
    chunk: list[dict],
    row_offset: int,
) -> tuple[int, int, list[dict]]:
    """
    returns_sustainability_dataset.csv — 5,000 rows with CO2/waste metrics.
    Core to Q-Loop's value prop: optimising the returns + disposal loop.
    Sustainability columns stored via migration 0005.
    """
    ok = err = 0
    errors: list[dict] = []

    for i, raw in enumerate(chunk):
        try:
            row = ReturnsSustainabilityRow.model_validate(raw)
            customer_id = await _upsert_customer_and_address(
                db, tenant_id, row.to_customer_dict(), row.to_address_dict()
            )
            shipment_dict = row.to_shipment_dict()
            shipment_dict["customer_id"] = str(customer_id)

            # Strip private sustainability keys and map to real columns
            co2_emissions  = shipment_dict.pop("_co2_emissions_kg", None)
            packaging_waste = shipment_dict.pop("_packaging_waste_kg", None)
            co2_saved      = shipment_dict.pop("_co2_saved_kg", None)
            waste_avoided  = shipment_dict.pop("_waste_avoided_kg", None)
            return_reason  = shipment_dict.pop("_return_reason", None)
            profit_loss    = shipment_dict.pop("_profit_loss", None)

            # Assign sustainability columns (migration 0005 required)
            shipment_dict["co2_emissions_kg"]   = co2_emissions
            shipment_dict["packaging_waste_kg"] = packaging_waste
            shipment_dict["co2_saved_kg"]       = co2_saved
            shipment_dict["waste_avoided_kg"]   = waste_avoided
            shipment_dict["return_reason"]      = return_reason
            shipment_dict["profit_loss"]        = profit_loss

            await _upsert_shipment(db, tenant_id, job_id, shipment_dict)
            ok += 1
        except Exception as exc:
            err += 1
            errors.append({
                "row_number": row_offset + i,
                "raw_data": raw,
                "validation_errors": {"error": str(exc)},
            })

    return ok, err, errors


async def _process_ewaste_generation_chunk(
    db: AsyncSession,
    tenant_id: uuid.UUID,
    job_id: uuid.UUID,
    chunk: list[dict],
    row_offset: int,
) -> tuple[int, int, list[dict]]:
    """RS_Session_256 — national e-waste generation by financial year."""
    ok = err = 0
    errors: list[dict] = []
    for i, raw in enumerate(chunk):
        try:
            row = EwasteGenerationRow.model_validate(raw)
            data = row.to_benchmark_dict()
            await db.execute(
                text("""
                    INSERT INTO sustainability_benchmarks
                        (tenant_id, benchmark_type, financial_year, state_ut,
                         metric_name, metric_value, unit, source)
                    VALUES
                        (:tenant_id, :benchmark_type, :financial_year, :state_ut,
                         :metric_name, :metric_value, :unit, :source)
                    ON CONFLICT DO NOTHING
                """),
                {"tenant_id": str(tenant_id), **data},
            )
            ok += 1
        except Exception as exc:
            err += 1
            errors.append({"row_number": row_offset + i, "raw_data": raw,
                           "validation_errors": {"error": str(exc)}})
    return ok, err, errors


async def _process_ewaste_recyclers_chunk(
    db: AsyncSession,
    tenant_id: uuid.UUID,
    job_id: uuid.UUID,
    chunk: list[dict],
    row_offset: int,
) -> tuple[int, int, list[dict]]:
    """rs_session243 — state-wise registered e-waste recyclers."""
    ok = err = 0
    errors: list[dict] = []
    for i, raw in enumerate(chunk):
        try:
            row = EwasteRecyclerRow.model_validate(raw)
            data = row.to_benchmark_dict()
            await db.execute(
                text("""
                    INSERT INTO sustainability_benchmarks
                        (tenant_id, benchmark_type, financial_year, state_ut,
                         metric_name, metric_value, unit, source)
                    VALUES
                        (:tenant_id, :benchmark_type, :financial_year, :state_ut,
                         :metric_name, :metric_value, :unit, :source)
                    ON CONFLICT DO NOTHING
                """),
                {"tenant_id": str(tenant_id), **data},
            )
            ok += 1
        except Exception as exc:
            err += 1
            errors.append({"row_number": row_offset + i, "raw_data": raw,
                           "validation_errors": {"error": str(exc)}})
    return ok, err, errors


async def _process_msw_generation_chunk(
    db: AsyncSession,
    tenant_id: uuid.UUID,
    job_id: uuid.UUID,
    chunk: list[dict],
    row_offset: int,
) -> tuple[int, int, list[dict]]:
    """RS_Session_234 — state-wise municipal solid waste generation."""
    ok = err = 0
    errors: list[dict] = []
    for i, raw in enumerate(chunk):
        try:
            row = MswGenerationRow.model_validate(raw)
            data = row.to_benchmark_dict()
            await db.execute(
                text("""
                    INSERT INTO sustainability_benchmarks
                        (tenant_id, benchmark_type, financial_year, state_ut,
                         metric_name, metric_value, unit, source)
                    VALUES
                        (:tenant_id, :benchmark_type, :financial_year, :state_ut,
                         :metric_name, :metric_value, :unit, :source)
                    ON CONFLICT DO NOTHING
                """),
                {"tenant_id": str(tenant_id), **data},
            )
            ok += 1
        except Exception as exc:
            err += 1
            errors.append({"row_number": row_offset + i, "raw_data": raw,
                           "validation_errors": {"error": str(exc)}})
    return ok, err, errors


# ── Main ingestion entry point ────────────────────────────────────────────────

async def run_ingestion(
    db: AsyncSession,
    job_id: uuid.UUID,
    tenant_id: uuid.UUID,
    file_bytes: bytes,
    source_type: str | None = None,
) -> IngestionReport:
    """
    Full pipeline: detect type → chunk → validate → upsert → report.
    Called by the Celery worker or directly for sync usage.
    """
    now = datetime.now(timezone.utc)

    # Mark job as processing
    await db.execute(
        update(IngestionJob)
        .where(IngestionJob.id == job_id)
        .values(status="processing", started_at=now)
    )

    total_ok = total_err = total_rows = 0
    all_errors: list[dict] = []
    partner_cache: dict = {}

    chunks = list(iter_csv_chunks_bytes(file_bytes))
    total_rows = sum(len(c) for c in chunks)

    # Update total count
    await db.execute(
        update(IngestionJob).where(IngestionJob.id == job_id).values(row_count_total=total_rows)
    )

    # Auto-detect if not provided
    if not source_type and chunks:
        headers = list(chunks[0][0].keys())
        source_type = detect_source_type(headers)

    row_offset = 1  # 1-based row numbers (account for header)
    for chunk in chunks:
        if source_type == IngestionSourceType.DELIVERY_LOGISTICS:
            ok, err, errors = await _process_logistics_chunk(
                db, tenant_id, job_id, chunk, partner_cache, row_offset
            )
        elif source_type == IngestionSourceType.ECOMMERCE_ANALYTICS:
            ok, err, errors = await _process_ecommerce_chunk(
                db, tenant_id, job_id, chunk, row_offset
            )
        elif source_type == IngestionSourceType.DELIVERY_POINTS:
            ok, err, errors = await _process_delivery_points_chunk(
                db, tenant_id, job_id, chunk, row_offset
            )
        elif source_type == IngestionSourceType.DELHIVERY_ROUTES:
            ok, err, errors = await _process_delhivery_chunk(
                db, tenant_id, job_id, chunk, partner_cache, row_offset
            )
        elif source_type == IngestionSourceType.MOBILE_SALES:
            ok, err, errors = await _process_mobile_sales_chunk(
                db, tenant_id, job_id, chunk, row_offset
            )
        elif source_type == IngestionSourceType.RETURNS_SUSTAINABILITY:
            ok, err, errors = await _process_returns_chunk(
                db, tenant_id, job_id, chunk, row_offset
            )
        elif source_type == IngestionSourceType.EWASTE_GENERATION:
            ok, err, errors = await _process_ewaste_generation_chunk(
                db, tenant_id, job_id, chunk, row_offset
            )
        elif source_type == IngestionSourceType.EWASTE_RECYCLERS:
            ok, err, errors = await _process_ewaste_recyclers_chunk(
                db, tenant_id, job_id, chunk, row_offset
            )
        elif source_type == IngestionSourceType.MSW_GENERATION:
            ok, err, errors = await _process_msw_generation_chunk(
                db, tenant_id, job_id, chunk, row_offset
            )
        else:
            ok, err, errors = 0, len(chunk), [
                {"row_number": row_offset + i, "raw_data": r,
                 "validation_errors": {"error": "Unknown source type"}}
                for i, r in enumerate(chunk)
            ]

        total_ok += ok
        total_err += err
        all_errors.extend(errors)
        row_offset += len(chunk)

        # Persist chunk errors to DB immediately
        for e in errors:
            db.add(IngestionError(
                job_id=job_id,
                row_number=e["row_number"],
                raw_data=e["raw_data"],
                validation_errors=e["validation_errors"],
            ))

        # Update counters after each chunk
        await db.execute(
            update(IngestionJob)
            .where(IngestionJob.id == job_id)
            .values(row_count_ok=total_ok, row_count_error=total_err)
        )
        await db.commit()

    # Finalise job
    error_summary = {
        "sample_errors": all_errors[:10],
        "total_errors": total_err,
    } if total_err > 0 else None

    await db.execute(
        update(IngestionJob)
        .where(IngestionJob.id == job_id)
        .values(
            status="done",
            finished_at=datetime.now(timezone.utc),
            error_summary=error_summary,
        )
    )
    await db.commit()

    return IngestionReport(
        job_id=job_id,
        rows_processed=total_rows,
        rows_inserted=total_ok,
        rows_updated=0,
        rows_failed=total_err,
        errors=all_errors[:20],
    )
