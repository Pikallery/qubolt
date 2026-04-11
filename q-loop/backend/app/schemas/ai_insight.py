from __future__ import annotations

import uuid
from datetime import datetime

from pydantic import BaseModel


class InsightRequest(BaseModel):
    shipment_ids: list[uuid.UUID] = []
    context: str | None = None   # extra context prompt injection
    query: str | None = None     # free-form query (no shipment IDs needed)


class InsightResponse(BaseModel):
    narrative: str
    reasoning: str | None = None   # DeepSeek-R1 reasoning_content
    delay_patterns: list[str] = []
    partner_risks: list[str] = []
    cost_anomalies: list[str] = []
    generated_at: datetime


class ETAPrediction(BaseModel):
    shipment_id: uuid.UUID
    predicted_eta: datetime
    confidence: float | None = None
    reasoning: str | None = None


class RouteExplanation(BaseModel):
    route_id: uuid.UUID
    explanation: str
    reasoning: str | None = None
    stop_count: int
    total_km: float | None
