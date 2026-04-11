"""
Chunked CSV parser — streams large files in configurable chunk sizes,
returns dicts with string keys matching the CSV header exactly.
"""
from __future__ import annotations

import csv
import io
from collections.abc import Iterator
from pathlib import Path
from typing import Any

CHUNK_SIZE = 500  # rows per chunk


def iter_csv_chunks(
    path: str | Path,
    chunk_size: int = CHUNK_SIZE,
    encoding: str = "utf-8",
) -> Iterator[list[dict[str, Any]]]:
    """
    Yields lists of row dicts from a CSV file, chunk_size rows at a time.
    Handles BOM (utf-8-sig) and strips whitespace from headers.
    """
    path = Path(path)
    with path.open(encoding=encoding, errors="replace", newline="") as f:
        # Strip BOM
        sample = f.read(3)
        if sample[:3] == "\ufeff\ufeff\ufeff" or sample.startswith("\ufeff"):
            f.seek(0)
            content = f.read().lstrip("\ufeff")
            reader = csv.DictReader(io.StringIO(content))
        else:
            f.seek(0)
            reader = csv.DictReader(f)

        # Normalise header keys: strip whitespace
        if reader.fieldnames:
            reader.fieldnames = [h.strip() for h in reader.fieldnames]

        chunk: list[dict[str, Any]] = []
        for row in reader:
            # Strip values too
            cleaned = {k: (v.strip() if isinstance(v, str) else v) for k, v in row.items()}
            chunk.append(cleaned)
            if len(chunk) >= chunk_size:
                yield chunk
                chunk = []
        if chunk:
            yield chunk


def iter_csv_chunks_bytes(
    data: bytes,
    chunk_size: int = CHUNK_SIZE,
    encoding: str = "utf-8",
) -> Iterator[list[dict[str, Any]]]:
    """Same as iter_csv_chunks but from in-memory bytes (uploaded file)."""
    text = data.decode(encoding, errors="replace").lstrip("\ufeff")
    reader = csv.DictReader(io.StringIO(text))
    if reader.fieldnames:
        reader.fieldnames = [h.strip() for h in reader.fieldnames]

    chunk: list[dict[str, Any]] = []
    for row in reader:
        cleaned = {k: (v.strip() if isinstance(v, str) else v) for k, v in row.items()}
        chunk.append(cleaned)
        if len(chunk) >= chunk_size:
            yield chunk
            chunk = []
    if chunk:
        yield chunk


def detect_source_type(headers: list[str]) -> str:
    """
    Heuristic: identify dataset type from CSV headers.
    Returns one of the IngestionSourceType string values.

    Detection order matters — more specific checks first.
    """
    h = {col.strip().lower() for col in headers}

    # Delivery_Logistics.csv
    if "delivery_id" in h and "delivery_partner" in h and "package_weight_kg" in h:
        return "delivery_logistics"

    # delhivery_data.csv — has route_schedule_uuid and osrm_time
    if "route_schedule_uuid" in h and "osrm_time" in h:
        return "delhivery_routes"

    # returns_sustainability_dataset.csv — has CO2/sustainability columns
    if "co2_emissions" in h and "return_status" in h and "waste_avoided" in h:
        return "returns_sustainability"

    # cleaned_mobile_phone_sales_data.csv — has Brand + RAM + ROM
    if "brand" in h and "ram" in h and "rom" in h and "inward date" in h:
        return "mobile_sales"

    # Ecommerce_Delivery_Analytics_New.csv
    if "order id" in h and "platform" in h and "product category" in h:
        return "ecommerce_analytics"

    # delivery_points_rourkela.csv
    if "delivery_id" in h and "latitude" in h and "longitude" in h and "area" in h:
        return "delivery_points"

    # RS_Session_256 — e-waste national generation (Financial Year + Estimated Generation)
    if "financial year" in h and "estimated generation in tonnes" in h:
        return "ewaste_generation"

    # rs_session243 — state-wise registered e-waste recyclers
    if "states/ uts" in h and "number of registered dismantler and recycler" in h:
        return "ewaste_recyclers"

    # RS_Session_234 — municipal solid waste by state
    if "name of the state / ut" in h and any("msw mt" in col for col in h):
        return "msw_generation"

    return "custom"


def count_rows(path: str | Path, encoding: str = "utf-8") -> int:
    """Fast row count (excludes header)."""
    path = Path(path)
    with path.open(encoding=encoding, errors="replace") as f:
        return sum(1 for _ in f) - 1  # subtract header
