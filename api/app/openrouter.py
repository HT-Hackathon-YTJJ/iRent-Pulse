"""Thin OpenRouter client: one JSON-returning chat call, with retries.

Everything the layers need from a VLM is "look at these images, fill in this
schema", so that is the only shape exposed. `temperature=0` and a strict JSON
schema are hallucination suppression per spec §L2 and apply just as well to L1.
"""

import asyncio
import base64
import io
import json
import time
from typing import Any, Dict, List, Optional, Tuple

import httpx
from PIL import Image, ImageOps

from . import config


class VlmError(RuntimeError):
    """Raised once every attempt has failed; callers fail-open to 停用."""


def encode_image(data: bytes) -> str:
    """Downscale to a data URL. Image tokens are where the money goes."""
    with Image.open(io.BytesIO(data)) as im:
        im = ImageOps.exif_transpose(im)
        im = im.convert("RGB")
        longest = max(im.size)
        if longest > config.MAX_IMAGE_EDGE:
            scale = config.MAX_IMAGE_EDGE / longest
            im = im.resize(
                (max(1, round(im.width * scale)), max(1, round(im.height * scale))),
                Image.LANCZOS,
            )
        buf = io.BytesIO()
        im.save(buf, format="JPEG", quality=config.JPEG_QUALITY, optimize=True)
    b64 = base64.b64encode(buf.getvalue()).decode("ascii")
    return "data:image/jpeg;base64," + b64


def _content(text: str, images: List[Tuple[str, str]]) -> List[Dict[str, Any]]:
    """Label each image before it, so the model can refer to them by name."""
    parts: List[Dict[str, Any]] = [{"type": "text", "text": text}]
    for label, data_url in images:
        parts.append({"type": "text", "text": f"[{label}]"})
        parts.append({"type": "image_url", "image_url": {"url": data_url}})
    return parts


def _extract_json(raw: str) -> Dict[str, Any]:
    raw = raw.strip()
    if raw.startswith("```"):
        raw = raw.split("```")[1]
        raw = raw.split("\n", 1)[1] if raw.lower().startswith("json") else raw
    start, end = raw.find("{"), raw.rfind("}")
    if start == -1 or end <= start:
        raise ValueError("no JSON object in response")
    return json.loads(raw[start : end + 1])


async def chat_json(
    *,
    model: str,
    system: str,
    user: str,
    images: List[Tuple[str, str]],
    schema: Dict[str, Any],
    schema_name: str,
    temperature: float = 0.0,
    attempts: Optional[int] = None,
) -> Tuple[Dict[str, Any], Dict[str, Any]]:
    """Return (parsed_json, meta). Raises [VlmError] once retries run out."""
    if not config.OPENROUTER_API_KEY:
        raise VlmError("OPENROUTER_API_KEY is not set (see .env at the repo root)")

    body: Dict[str, Any] = {
        "model": model,
        "temperature": temperature,
        "messages": [
            {"role": "system", "content": system},
            {"role": "user", "content": _content(user, images)},
        ],
        "response_format": {
            "type": "json_schema",
            "json_schema": {"name": schema_name, "strict": True, "schema": schema},
        },
        "usage": {"include": True},
    }
    headers = {
        "Authorization": f"Bearer {config.OPENROUTER_API_KEY}",
        "Content-Type": "application/json",
        "HTTP-Referer": "https://github.com/ncchen99/iRent-Pulse",
        "X-Title": "iRent Pulse Vehicle Condition Steward",  # headers must be ASCII
    }

    limit = attempts or config.MAX_ATTEMPTS
    started = time.perf_counter()
    last: Optional[Exception] = None

    async with httpx.AsyncClient(timeout=config.REQUEST_TIMEOUT_S) as client:
        for attempt in range(limit):
            try:
                resp = await client.post(
                    f"{config.OPENROUTER_BASE_URL}/chat/completions",
                    headers=headers,
                    json=body,
                )
                if resp.status_code == 400 and "response_format" in resp.text:
                    # Some upstream providers reject strict schemas. Ask for JSON
                    # in prose instead and parse it out; the schema is still
                    # enforced by pydantic downstream.
                    body.pop("response_format", None)
                    body["messages"][0]["content"] = (
                        system + "\n\n只輸出一個 JSON 物件，不要加任何說明文字或程式碼框。"
                    )
                    raise ValueError("schema rejected; retrying without response_format")
                resp.raise_for_status()
                payload = resp.json()
                text = payload["choices"][0]["message"]["content"]
                parsed = _extract_json(text if isinstance(text, str) else text[0]["text"])
                usage = payload.get("usage") or {}
                meta = {
                    "model": payload.get("model", model),
                    "latency_ms": int((time.perf_counter() - started) * 1000),
                    "cost_usd": float(usage.get("cost") or 0.0),
                    "attempts": attempt + 1,
                }
                return parsed, meta
            except Exception as exc:  # noqa: BLE001 — every failure retries alike
                last = exc
                if attempt < limit - 1:
                    await asyncio.sleep(0.6 * (attempt + 1))

    raise VlmError(f"{model} failed after {limit} attempts: {last}")
