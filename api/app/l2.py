"""L2 — 影像確認層.

Only runs when L1 saw damage on a return frame. Answers one question:
**是這趟造成的嗎？**

The two photos are never handed to the model together with "compare these".
Light, angle, background and ground differ between a pickup and a return, and a
VLM asked to compare will narrate those differences as damage. Instead:

    Stage A (VLM)   describe each photo on its own, indexed by 車輛部位
    Stage B (code)  set difference: damages(還) - damages(取)

車輛部位 is the coordinate system precisely because pixels cannot be aligned but
「左前葉子板」means the same thing in both frames.
"""

import asyncio
from collections import Counter
from typing import Any, Dict, List, Optional, Tuple

from . import config, prompts
from .models import L2Finding, L2Result
from .openrouter import VlmError, chat_json, encode_image

#: severity ≥ this is what L3 pulls a car off the road for, so these are the
#: findings that get run three times and decided by majority (spec §L2 幻覺抑制).
SELF_CONSISTENCY_SEVERITY = 3
SELF_CONSISTENCY_RUNS = 3


async def _describe(data_url: str, label: str, slot: str) -> Tuple[Dict[str, Any], Dict[str, Any]]:
    return await chat_json(
        model=config.L2_MODEL,
        system=prompts.L2_DESCRIBE_SYSTEM,
        user=prompts.l2_describe_user(label, slot),
        images=[(f"{label}照片", data_url)],
        schema=prompts.L2_DESCRIBE_SCHEMA,
        schema_name="l2_describe",
    )


def _key(damage: Dict[str, Any]) -> Tuple[str, str]:
    return damage["part"], damage["type"]


def _diff(
    ret: Dict[str, Any], base: Optional[Dict[str, Any]]
) -> List[L2Finding]:
    """Stage B. Pure code — no model sees both photos."""
    base_damages = {_key(d): d for d in (base or {}).get("damages", [])}
    base_parts_with_damage = {p for p, _ in base_damages}
    base_visible = set((base or {}).get("visible_parts", []))
    baseline_usable = base is not None and base.get("assessable", False)

    findings: List[L2Finding] = []
    for d in ret.get("damages", []):
        part, dtype = _key(d)
        severity = int(d.get("severity", 1))
        confidence = float(d.get("confidence") or 0.0)

        if not baseline_usable:
            verdict = "無法判定"
            reason = "取車照缺失或不可判讀，無法確認此損傷是否為本趟新增。"
        elif (part, dtype) in base_damages:
            verdict = "既有"
            reason = f"取車照同部位已見相同類型損傷（{base_damages[(part, dtype)].get('desc', '')}）。"
        elif part in base_parts_with_damage and severity < SELF_CONSISTENCY_SEVERITY:
            # Same panel already carried damage and this one is not serious
            # enough to pull the car. Lean to 既有 — 漏報 costs a claim, 誤報
            # costs a wrongly-charged customer.
            verdict = "既有"
            reason = "取車照同部位已有損傷，本次差異未達拉車門檻，保守視為既有。"
        elif part in base_visible:
            verdict = "新增"
            reason = f"還車照見{d.get('desc', dtype)}；取車照同部位清晰可見且無此損傷。"
        else:
            verdict = "無法判定"
            reason = "該部位在取車照中未清晰入鏡，無法確認是否為本趟新增。"

        findings.append(
            L2Finding(
                part=part,
                type=dtype,
                verdict=verdict,
                severity=max(1, min(4, severity)),
                confidence=confidence,
                reason=reason,
            )
        )
    return findings


def _majority(runs: List[Dict[str, Any]]) -> Dict[str, Any]:
    """Keep only damages a majority of runs agreed on; union the visible parts."""
    votes = Counter()
    sample: Dict[Tuple[str, str], Dict[str, Any]] = {}
    for run in runs:
        for d in run.get("damages", []):
            votes[_key(d)] += 1
            sample.setdefault(_key(d), d)
    threshold = len(runs) // 2 + 1
    kept = [sample[k] for k, n in votes.items() if n >= threshold]

    visible: set = set()
    for run in runs:
        visible |= set(run.get("visible_parts", []))
    return {
        "assessable": any(r.get("assessable", False) for r in runs),
        "visible_parts": sorted(visible),
        "damages": kept,
    }


async def confirm(
    *,
    return_image: bytes,
    baseline_image: Optional[bytes],
    photo_id: str,
    car_no: str,
    slot: str,
    baseline_photo_id: Optional[str] = None,
) -> L2Result:
    result = L2Result(
        photo_id=photo_id,
        car_no=car_no,
        baseline_photo_id=baseline_photo_id,
        baseline_available=baseline_image is not None,
        model=config.L2_MODEL,
    )

    try:
        ret_url = encode_image(return_image)
        base_url = encode_image(baseline_image) if baseline_image else None
    except Exception as exc:  # noqa: BLE001
        result.error = f"image decode failed: {exc}"
        return result

    try:
        calls = [_describe(ret_url, "還車", slot)]
        if base_url:
            calls.append(_describe(base_url, "取車", slot))
        answers = await asyncio.gather(*calls)
    except VlmError as exc:
        result.error = str(exc)
        return result

    ret_desc, ret_meta = answers[0]
    cost = ret_meta["cost_usd"]
    latency = ret_meta["latency_ms"]
    base_desc = None
    if len(answers) > 1:
        base_desc, base_meta = answers[1]
        cost += base_meta["cost_usd"]
        latency = max(latency, base_meta["latency_ms"])

    # Self-consistency, only for the findings that would take a car off the road.
    if any(
        int(d.get("severity", 1)) >= SELF_CONSISTENCY_SEVERITY
        for d in ret_desc.get("damages", [])
    ):
        try:
            extra = await asyncio.gather(
                *[_describe(ret_url, "還車", slot) for _ in range(SELF_CONSISTENCY_RUNS - 1)]
            )
            for _, meta in extra:
                cost += meta["cost_usd"]
            ret_desc = _majority([ret_desc] + [d for d, _ in extra])
        except VlmError:
            # A failed re-run is not a reason to drop a serious finding; the
            # single-pass answer stands and 客服 sees it either way.
            pass

    result.findings = _diff(ret_desc, base_desc)
    result.max_new_severity = max(
        (f.severity for f in result.findings if f.verdict == "新增"), default=0
    )
    result.unclear_parts = sorted(
        {f.part for f in result.findings if f.verdict == "無法判定"}
    )
    result.latency_ms = latency
    result.cost_usd = cost
    if not base_desc:
        result.baseline_available = False
    return result
