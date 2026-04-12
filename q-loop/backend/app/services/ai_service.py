"""
Google Gemini AI service — powers supply chain insights, route explanations,
ETA predictions, and smart chat replies.

Uses the google-genai SDK (google-generativeai) via the REST API.
All calls are async with a concurrency limiter to respect Gemini rate limits.
"""
from __future__ import annotations

import asyncio
import json
import re
from datetime import datetime, timezone

import google.generativeai as genai

from app.core.config import settings
from app.schemas.ai_insight import ETAPrediction, InsightResponse, RouteExplanation

# ── Helpers ───────────────────────────────────────────────────────────────────

def _extract_json(text: str) -> dict | None:
    """Robustly extract a JSON object from an LLM response."""
    if not text:
        return None
    try:
        return json.loads(text)
    except json.JSONDecodeError:
        pass
    fence = re.search(r"```(?:json)?\s*(\{.*?\})\s*```", text, re.DOTALL)
    if fence:
        try:
            return json.loads(fence.group(1))
        except json.JSONDecodeError:
            pass
    first = text.find("{")
    last = text.rfind("}")
    if first != -1 and last != -1 and last > first:
        try:
            return json.loads(text[first:last + 1])
        except json.JSONDecodeError:
            pass
    return None


def _strip_markdown(text: str) -> str:
    """Remove markdown formatting for plain-text display."""
    if not text:
        return ""
    text = re.sub(r"```[a-zA-Z]*\n.*?```", "", text, flags=re.DOTALL)
    text = re.sub(r"^#{1,6}\s.*$", "", text, flags=re.MULTILINE)
    text = re.sub(r"\n{3,}", "\n\n", text)
    return text.strip()


# ── Gemini client setup ───────────────────────────────────────────────────────

genai.configure(api_key=settings.GEMINI_API_KEY)

_semaphore = asyncio.Semaphore(settings.AI_CONCURRENCY_LIMIT)


async def _chat(system: str, user: str) -> str:
    """
    Send a prompt to Gemini and return the text response.
    System instruction + user message are combined as Gemini uses a single prompt.
    """
    model = genai.GenerativeModel(
        model_name=settings.GEMINI_MODEL,
        system_instruction=system,
        generation_config=genai.GenerationConfig(
            temperature=settings.GEMINI_TEMPERATURE,
            top_p=settings.GEMINI_TOP_P,
            max_output_tokens=settings.GEMINI_MAX_TOKENS,
        ),
    )
    async with _semaphore:
        response = await asyncio.to_thread(model.generate_content, user)
    return response.text or ""


# ── Public functions ──────────────────────────────────────────────────────────

async def get_supply_chain_insight(shipment_summaries: list[dict]) -> InsightResponse:
    """Analyse a batch of shipments and return structured supply chain insights."""
    system = (
        "You are a senior supply chain analyst for an Indian logistics platform. "
        "Analyse the shipment data and respond with ONLY a single JSON object — "
        "no markdown, no code fences, no headings, no preamble, no commentary outside the JSON. "
        "Required schema: "
        '{"narrative": "<2-4 sentence executive summary in plain prose>", '
        '"delay_patterns": ["<finding>", ...], '
        '"partner_risks": ["<finding>", ...], '
        '"cost_anomalies": ["<finding>", ...]}. '
        "Each list should have 2-4 concise, data-driven, actionable findings. "
        "Do NOT wrap the JSON in ```json fences."
    )
    user = (
        f"Analyse these {len(shipment_summaries)} shipment records and identify "
        f"supply chain inefficiencies, delay patterns, partner risks, and cost anomalies:\n\n"
        f"{json.dumps(shipment_summaries[:50], default=str)}"
    )

    content = await _chat(system, user)
    data = _extract_json(content) or {}
    narrative = data.get("narrative") or _strip_markdown(content) or "No insight available."

    return InsightResponse(
        narrative=narrative,
        reasoning=None,  # Gemini doesn't expose chain-of-thought separately
        delay_patterns=data.get("delay_patterns", []),
        partner_risks=data.get("partner_risks", []),
        cost_anomalies=data.get("cost_anomalies", []),
        generated_at=datetime.now(timezone.utc),
    )


async def get_route_explanation(route_summary: dict) -> RouteExplanation:
    """Generate a plain-English explanation of the SA-optimised route."""
    system = (
        "You are a logistics operations AI. Explain in plain English why the "
        "Simulated Annealing algorithm produced this specific route arrangement. "
        "Mention geographic clustering, load balancing, and time-window considerations. "
        "Keep your explanation under 200 words."
    )
    user = f"Route optimization result:\n{json.dumps(route_summary, default=str)}"
    content = await _chat(system, user)

    return RouteExplanation(
        route_id=route_summary.get("route_id"),
        explanation=_strip_markdown(content),
        reasoning=None,
        stop_count=route_summary.get("stop_count", 0),
        total_km=route_summary.get("total_distance_km"),
    )


async def predict_eta(shipment_summary: dict) -> ETAPrediction:
    """Predict delivery ETA for a shipment based on its attributes."""
    system = (
        "You are a delivery ETA prediction model. Given shipment attributes, "
        "respond ONLY with a JSON object: "
        '{"predicted_eta": "ISO8601_datetime", "confidence": 0.0_to_1.0, "reasoning": "brief explanation"}. '
        f"Base your prediction on current UTC time: {datetime.now(timezone.utc).isoformat()}."
    )
    user = f"Predict ETA for this shipment:\n{json.dumps(shipment_summary, default=str)}"
    content = await _chat(system, user)

    data = _extract_json(content) or {}
    try:
        predicted_eta = datetime.fromisoformat(data["predicted_eta"])
    except (KeyError, ValueError, TypeError):
        from datetime import timedelta
        predicted_eta = datetime.now(timezone.utc) + timedelta(hours=24)

    return ETAPrediction(
        shipment_id=shipment_summary.get("id"),
        predicted_eta=predicted_eta,
        confidence=data.get("confidence"),
        reasoning=data.get("reasoning"),
    )


async def smart_reply(context: str, message: str) -> str:
    """Generate a contextual smart-reply for driver/customer communications."""
    system = (
        "You are a logistics communication assistant. Generate a professional, "
        "empathetic reply to the message given the shipment context. "
        "Keep replies under 80 words."
    )
    user = f"Context:\n{context}\n\nMessage to reply to:\n{message}"
    return _strip_markdown(await _chat(system, user))
