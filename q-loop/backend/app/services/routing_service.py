"""
Simulated Annealing route optimizer for multi-tenant fleet routing.

Algorithm:
  - Initial solution: nearest-neighbour greedy tour
  - Perturbation: 2-opt swap (reverse sub-segment)
  - Acceptance: Boltzmann criterion — accept worse solutions with probability e^(-ΔC/T)
  - Cooling: geometric schedule T(k) = T0 * alpha^k
  - Termination: max_iterations OR temperature < 1e-8

Distance metric: Haversine (spherical earth, returns km).
"""
from __future__ import annotations

import math
import random
import uuid
from dataclasses import dataclass, field
from datetime import datetime, timezone

from sqlalchemy import select, update
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.config import settings
from app.models.route import Route, RouteStop


# ── Geo helpers ───────────────────────────────────────────────────────────────

_EARTH_R_KM = 6371.0


def haversine(lat1: float, lon1: float, lat2: float, lon2: float) -> float:
    """Returns great-circle distance in km."""
    φ1, φ2 = math.radians(lat1), math.radians(lat2)
    dφ = math.radians(lat2 - lat1)
    dλ = math.radians(lon2 - lon1)
    a = math.sin(dφ / 2) ** 2 + math.cos(φ1) * math.cos(φ2) * math.sin(dλ / 2) ** 2
    return 2 * _EARTH_R_KM * math.asin(math.sqrt(a))


@dataclass
class Stop:
    index: int
    lat: float
    lon: float
    shipment_id: uuid.UUID | None = None
    route_stop_id: uuid.UUID | None = None


@dataclass
class SAResult:
    ordered_indices: list[int]
    total_distance_km: float
    iterations_run: int
    final_temperature: float
    initial_distance_km: float
    improvement_pct: float


# ── Distance matrix ───────────────────────────────────────────────────────────

def build_distance_matrix(stops: list[Stop]) -> list[list[float]]:
    n = len(stops)
    matrix: list[list[float]] = [[0.0] * n for _ in range(n)]
    for i in range(n):
        for j in range(i + 1, n):
            d = haversine(stops[i].lat, stops[i].lon, stops[j].lat, stops[j].lon)
            matrix[i][j] = d
            matrix[j][i] = d
    return matrix


def tour_distance(order: list[int], matrix: list[list[float]]) -> float:
    total = sum(matrix[order[i]][order[i + 1]] for i in range(len(order) - 1))
    total += matrix[order[-1]][order[0]]  # return to depot
    return total


# ── Nearest-neighbour initial solution ───────────────────────────────────────

def nearest_neighbour_tour(matrix: list[list[float]]) -> list[int]:
    n = len(matrix)
    if n == 0:
        return []
    visited = [False] * n
    tour = [0]
    visited[0] = True
    for _ in range(n - 1):
        last = tour[-1]
        nearest = min(
            (j for j in range(n) if not visited[j]),
            key=lambda j: matrix[last][j],
        )
        tour.append(nearest)
        visited[nearest] = True
    return tour


# ── 2-opt swap ────────────────────────────────────────────────────────────────

def two_opt_swap(tour: list[int], i: int, k: int) -> list[int]:
    """Reverse the segment between positions i and k (inclusive)."""
    return tour[:i] + tour[i : k + 1][::-1] + tour[k + 1 :]


# ── Simulated Annealing ───────────────────────────────────────────────────────

def simulated_annealing(
    stops: list[Stop],
    initial_temp: float | None = None,
    cooling_rate: float | None = None,
    max_iterations: int | None = None,
    seed: int | None = None,
) -> SAResult:
    T0 = initial_temp or settings.SA_INITIAL_TEMP
    alpha = cooling_rate or settings.SA_COOLING_RATE
    max_iter = max_iterations or settings.SA_MAX_ITERATIONS

    if seed is not None:
        random.seed(seed)

    n = len(stops)
    if n <= 1:
        return SAResult(
            ordered_indices=list(range(n)),
            total_distance_km=0.0,
            iterations_run=0,
            final_temperature=T0,
            initial_distance_km=0.0,
            improvement_pct=0.0,
        )

    matrix = build_distance_matrix(stops)
    current = nearest_neighbour_tour(matrix)
    current_cost = tour_distance(current, matrix)
    best = current[:]
    best_cost = current_cost
    initial_cost = current_cost

    T = T0
    iterations = 0

    for iterations in range(1, max_iter + 1):
        # Random 2-opt move
        i = random.randint(0, n - 2)
        k = random.randint(i + 1, n - 1)
        candidate = two_opt_swap(current, i, k)
        candidate_cost = tour_distance(candidate, matrix)

        delta = candidate_cost - current_cost
        if delta < 0 or random.random() < math.exp(-delta / T):
            current = candidate
            current_cost = candidate_cost
            if current_cost < best_cost:
                best = current[:]
                best_cost = current_cost

        T *= alpha
        if T < 1e-8:
            break

    improvement = (initial_cost - best_cost) / initial_cost * 100 if initial_cost > 0 else 0.0

    return SAResult(
        ordered_indices=best,
        total_distance_km=round(best_cost, 4),
        iterations_run=iterations,
        final_temperature=round(T, 8),
        initial_distance_km=round(initial_cost, 4),
        improvement_pct=round(improvement, 2),
    )


# ── DB-integrated optimizer ───────────────────────────────────────────────────

async def optimize_route(
    db: AsyncSession,
    route_id: uuid.UUID,
    initial_temp: float | None = None,
    cooling_rate: float | None = None,
    max_iterations: int | None = None,
) -> dict:
    """
    Load route stops from DB, run SA, write optimized sequences back.
    Returns a summary dict suitable for the API response.
    """
    # Load stops
    result = await db.execute(
        select(RouteStop)
        .where(RouteStop.route_id == route_id)
        .order_by(RouteStop.stop_sequence)
    )
    db_stops = result.scalars().all()

    if not db_stops:
        return {"error": "No stops found for this route"}

    stops = [
        Stop(
            index=i,
            lat=float(s.latitude),
            lon=float(s.longitude),
            shipment_id=s.shipment_id,
            route_stop_id=s.id,
        )
        for i, s in enumerate(db_stops)
    ]

    sa_result = simulated_annealing(
        stops,
        initial_temp=initial_temp,
        cooling_rate=cooling_rate,
        max_iterations=max_iterations,
    )

    # Write optimized sequences back to DB
    for new_seq, original_idx in enumerate(sa_result.ordered_indices):
        stop = db_stops[original_idx]
        await db.execute(
            update(RouteStop)
            .where(RouteStop.id == stop.id)
            .values(stop_sequence=new_seq)
        )

    # Update route metadata
    await db.execute(
        update(Route)
        .where(Route.id == route_id)
        .values(
            total_distance_km=sa_result.total_distance_km,
            sa_iterations=sa_result.iterations_run,
            sa_temperature=sa_result.final_temperature,
            sa_final_cost=sa_result.total_distance_km,
            status="active",
        )
    )

    return {
        "route_id": str(route_id),
        "total_distance_km": sa_result.total_distance_km,
        "iterations_run": sa_result.iterations_run,
        "improvement_pct": sa_result.improvement_pct,
        "initial_distance_km": sa_result.initial_distance_km,
        "stop_count": len(stops),
    }
