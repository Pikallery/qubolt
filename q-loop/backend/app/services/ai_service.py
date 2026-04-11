"""
DeepSeek-R1 via NVIDIA's hosted API.

Uses the OpenAI-compatible client with NVIDIA base URL.
All calls are async via httpx + asyncio.Semaphore to respect rate limits.
DeepSeek-R1 returns both reasoning_content (chain-of-thought) and content (answer).
"""
from __future__ import annotations

import asyncio
import json
import re
from datetime import datetime, timezone

from openai import AsyncOpenAI

from app.core.config import settings
from app.schemas.ai_insight import ETAPrediction, InsightResponse, RouteExplanation


def _extract_json(text: str) -> dict | None:
    """
    Robustly extract a JSON object from an LLM response.
    Handles:
      - Pure JSON
      - JSON wrapped in ```json ... ``` fences
      - JSON embedded inside prose / markdown
    Returns None if nothing parseable is found.
    """
    if not text:
        return None
    # 1) Try direct parse
    try:
        return json.loads(text)
    except json.JSONDecodeError:
        pass
    # 2) Try fenced code block
    fence = re.search(r"```(?:json)?\s*(\{.*?\})\s*```", text, re.DOTALL)
    if fence:
        try:
            return json.loads(fence.group(1))
        except json.JSONDecodeError:
            pass
    # 3) Greedy first-{ to last-}
    first = text.find("{")
    last = text.rfind("}")
    if first != -1 and last != -1 and last > first:
        candidate = text[first:last + 1]  # type: ignore[index]
        try:
            return json.loads(candidate)
        except json.JSONDecodeError:
            pass
    return None


def _strip_markdown(text: str) -> str:
    """Remove markdown headings, code fences, and extra blank lines for plain-text display."""
    if not text:
        return ""
    # Drop fenced code blocks entirely
    text = re.sub(r"```[a-zA-Z]*\n.*?```", "", text, flags=re.DOTALL)
    # Drop headings (### Foo)
    text = re.sub(r"^#{1,6}\s.*$", "", text, flags=re.MULTILINE)
    # Collapse whitespace
    text = re.sub(r"\n{3,}", "\n\n", text)
    return text.strip()

# Rate-limit concurrency to NVIDIA API tier
_semaphore = asyncio.Semaphore(settings.AI_CONCURRENCY_LIMIT)

_client = AsyncOpenAI(
    api_key=settings.NVIDIA_API_KEY,
    base_url=settings.NVIDIA_API_BASE_URL,
)


async def _chat(system: str, user: str) -> tuple[str, str | None]:
    """
    Returns (content, reasoning_content).
    reasoning_content is the chain-of-thought from DeepSeek-R1 (may be None).
    """
    async with _semaphore:
        response = await _client.chat.completions.create(
            model=settings.DEEPSEEK_MODEL,
            messages=[
                {"role": "system", "content": system},
                {"role": "user", "content": user},
            ],
            temperature=settings.DEEPSEEK_TEMPERATURE,
            top_p=settings.DEEPSEEK_TOP_P,
            max_tokens=settings.DEEPSEEK_MAX_TOKENS,
        )
    choice = response.choices[0]
    content = choice.message.content or ""
    reasoning = getattr(choice.message, "reasoning_content", None)
    return content, reasoning


async def get_supply_chain_insight(shipment_summaries: list[dict]) -> InsightResponse:
    """
    Analyse a batch of shipment summaries and return structured supply chain insights.
    """
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
        f"{json.dumps(shipment_summaries[:50], default=str)}"  # type: ignore[index] # cap at 50 for token budget
    )

    content, reasoning = await _chat(system, user)

    data = _extract_json(content) or {}
    narrative = data.get("narrative") or _strip_markdown(content) or "No insight available."

    return InsightResponse(
        narrative=narrative,
        reasoning=reasoning,
        delay_patterns=data.get("delay_patterns", []),
        partner_risks=data.get("partner_risks", []),
        cost_anomalies=data.get("cost_anomalies", []),
        generated_at=datetime.now(timezone.utc),
    )


async def get_route_explanation(route_summary: dict) -> RouteExplanation:
    """
    Generate a plain-English explanation of why the SA algorithm produced this route.
    """
    system = (
        "You are a logistics operations AI. Explain in plain English why the "
        "Simulated Annealing algorithm produced this specific route arrangement. "
        "Mention geographic clustering, load balancing, and time-window considerations. "
        "Keep your explanation under 200 words."
    )
    user = f"Route optimization result:\n{json.dumps(route_summary, default=str)}"

    content, reasoning = await _chat(system, user)

    return RouteExplanation(
        route_id=route_summary.get("route_id"),
        explanation=_strip_markdown(content),
        reasoning=reasoning,
        stop_count=route_summary.get("stop_count", 0),
        total_km=route_summary.get("total_distance_km"),
    )


async def predict_eta(shipment_summary: dict) -> ETAPrediction:
    """
    Predict delivery ETA for a shipment based on its attributes.
    Returns an ETAPrediction with a predicted datetime.
    """
    system = (
        "You are a delivery ETA prediction model. Given shipment attributes, "
        "respond ONLY with a JSON object: "
        '{"predicted_eta": "ISO8601_datetime", "confidence": 0.0_to_1.0, "reasoning": "brief explanation"}. '
        f"Base your prediction on current UTC time: {datetime.now(timezone.utc).isoformat()}."
    )
    user = f"Predict ETA for this shipment:\n{json.dumps(shipment_summary, default=str)}"

    content, reasoning = await _chat(system, user)

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
        reasoning=data.get("reasoning") or reasoning,
    )


async def smart_reply(context: str, message: str) -> str:
    """
    Generate a contextual smart-reply for driver/customer communications.
    """
    system = (
        "You are a logistics communication assistant. Generate a professional, "
        "empathetic reply to the message given the shipment context. "
        "Keep replies under 80 words."
    )
    user = f"Context:\n{context}\n\nMessage to reply to:\n{message}"
    content, _ = await _chat(system, user)
    return content
