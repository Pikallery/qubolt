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
    Falls back to a structured local response if the API is unavailable or quota exceeded.
    """
    if not settings.GEMINI_API_KEY:
        raise RuntimeError("GEMINI_API_KEY not configured")
    try:
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
    except Exception as exc:
        err = str(exc).lower()
        if "quota" in err or "rate" in err or "429" in err or "resource_exhausted" in err:
            raise RuntimeError(f"QUOTA_EXCEEDED:{exc}")
        raise


# ── Public functions ──────────────────────────────────────────────────────────

def _insight_fallback(summaries: list[dict]) -> InsightResponse:
    """Rule-based insight when Gemini is unavailable."""
    total = len(summaries)
    delayed = sum(1 for s in summaries if s.get("is_delayed"))
    delay_rate = delayed / total * 100 if total else 0
    regions = list({s.get("region") for s in summaries if s.get("region")})[:3]
    vehicles = list({s.get("vehicle_type") for s in summaries if s.get("vehicle_type")})[:3]
    return InsightResponse(
        narrative=(
            f"Analysis of {total} shipments shows a delay rate of {delay_rate:.1f}%. "
            f"Operations span {len(regions)} region(s) including {', '.join(regions) or 'multiple areas'}. "
            f"Primary vehicle types in use: {', '.join(v for v in vehicles if v) or 'mixed fleet'}. "
            "Review delayed shipments to identify systemic bottlenecks."
        ),
        reasoning=None,
        delay_patterns=[
            f"{delay_rate:.1f}% of shipments are delayed",
            "High-priority shipments may need dedicated fast-lane routing",
        ],
        partner_risks=[
            "Partner SLA compliance should be reviewed for high-delay regions",
        ],
        cost_anomalies=[
            "Express delivery overuse may be inflating costs — consider route batching",
        ],
        generated_at=datetime.now(timezone.utc),
    )


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
    try:
        content = await _chat(system, user)
    except RuntimeError as exc:
        if str(exc).startswith("QUOTA_EXCEEDED"):
            return _insight_fallback(shipment_summaries)
        raise
    data = _extract_json(content) or {}
    narrative = data.get("narrative") or _strip_markdown(content) or "No insight available."

    return InsightResponse(
        narrative=narrative,
        reasoning=None,
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
    try:
        content = await _chat(system, user)
    except RuntimeError as exc:
        if str(exc).startswith("QUOTA_EXCEEDED"):
            stops = route_summary.get("stop_count", 0)
            km = route_summary.get("total_distance_km")
            iters = route_summary.get("sa_iterations", 0)
            cost = route_summary.get("sa_final_cost")
            km_str = f"{km:.1f} km" if km else "unknown distance"
            cost_str = f"{cost:.2f}" if cost else "N/A"
            explanation = (
                f"This route covers {stops} stops over {km_str}, optimised by Simulated Annealing "
                f"across {iters:,} iterations (final cost: {cost_str}). "
                "SA grouped geographically close delivery points together to reduce backtracking, "
                "accepted occasional worse solutions early on to escape local minima, "
                "then cooled to lock in the best tour found. "
                "The result minimises total travel distance while respecting the delivery sequence constraints."
            )
            return RouteExplanation(
                route_id=route_summary.get("route_id"),
                explanation=explanation,
                reasoning=None,
                stop_count=stops,
                total_km=km,
            )
        raise
    return RouteExplanation(
        route_id=route_summary.get("route_id"),
        explanation=_strip_markdown(content),
        reasoning=None,
        stop_count=route_summary.get("stop_count", 0),
        total_km=route_summary.get("total_distance_km"),
    )


async def predict_eta(shipment_summary: dict) -> ETAPrediction:
    """Predict delivery ETA for a shipment based on its attributes."""
    from datetime import timedelta
    system = (
        "You are a delivery ETA prediction model. Given shipment attributes, "
        "respond ONLY with a JSON object: "
        '{"predicted_eta": "ISO8601_datetime", "confidence": 0.0_to_1.0, "reasoning": "brief explanation"}. '
        f"Base your prediction on current UTC time: {datetime.now(timezone.utc).isoformat()}."
    )
    user = f"Predict ETA for this shipment:\n{json.dumps(shipment_summary, default=str)}"
    try:
        content = await _chat(system, user)
    except RuntimeError as exc:
        if str(exc).startswith("QUOTA_EXCEEDED"):
            # Rule-based fallback: 40 km/h average speed + 2h handling buffer
            dist = shipment_summary.get("distance_km") or 50.0
            mode = shipment_summary.get("delivery_mode") or "standard"
            speed = 50.0 if mode == "express" else 35.0
            hours = (dist / speed) + 2.0
            if shipment_summary.get("is_delayed"):
                hours += 4.0
            eta = datetime.now(timezone.utc) + timedelta(hours=hours)
            return ETAPrediction(
                shipment_id=shipment_summary.get("id"),
                predicted_eta=eta,
                confidence=0.72,
                reasoning=(
                    f"Rule-based estimate: {dist:.0f} km at {speed:.0f} km/h average "
                    f"+ 2h handling = ~{hours:.1f}h. "
                    f"{'Delay penalty applied. ' if shipment_summary.get('is_delayed') else ''}"
                    "(Gemini quota exceeded — using local model)"
                ),
            )
        raise
    data = _extract_json(content) or {}
    try:
        predicted_eta = datetime.fromisoformat(data["predicted_eta"])
    except (KeyError, ValueError, TypeError):
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
