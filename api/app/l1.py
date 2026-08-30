"""L1 — 伺服器端快篩（阻塞）.

One VLM call per photo answers: can this be read, and is there damage on it.
It never decides whether damage is new or old — that has no answer from a
single frame, and pretending otherwise is what makes systems bill the wrong
driver.

Tuning direction is **high recall**: anything L1 misses is never looked at
again, while a false positive only costs one L2 call.
"""

from typing import Any, Dict, Optional

from . import prompts
from .models import L1Result, ObservedDamage, Severity, Stage
from .openrouter import VlmError, chat_json, encode_image
from . import config

#: The retake loop has to have an exit. Without one, a driver who cannot get a
#: passing photo is trapped in the return flow — a worse failure than missing
#: damage, because it blocks revenue and becomes a complaint every single time.
MAX_RETAKES = 3

#: Below this the angle answer is noise; flag it but never block on it.
ANGLE_CONF_FLOOR = 0.6


async def screen(
    *,
    image: bytes,
    photo_id: str,
    order_id: str,
    car_no: str,
    stage: Stage,
    slot: str,
    interior: bool,
    l0: Optional[Dict[str, Any]] = None,
    retake_count: int = 0,
) -> L1Result:
    base = L1Result(
        photo_id=photo_id,
        order_id=order_id,
        car_no=car_no,
        stage=stage,
        slot=slot,
        assessable=True,
        retake_count=retake_count,
    )

    try:
        data_url = encode_image(image)
    except Exception as exc:  # noqa: BLE001 — a corrupt upload is a system error
        base.error = f"image decode failed: {exc}"
        return base

    try:
        if interior:
            parsed, meta = await chat_json(
                model=config.L1_MODEL,
                system=prompts.L1_INTERIOR_SYSTEM,
                user=prompts.L1_INTERIOR_USER,
                images=[("照片", data_url)],
                schema=prompts.L1_INTERIOR_SCHEMA,
                schema_name="l1_interior",
            )
        else:
            parsed, meta = await chat_json(
                model=config.L1_MODEL,
                system=prompts.L1_EXTERIOR_SYSTEM,
                user=prompts.l1_exterior_user(slot, stage.value, prompts.l0_note(l0 or {})),
                images=[("照片", data_url)],
                schema=prompts.L1_EXTERIOR_SCHEMA,
                schema_name="l1_exterior",
            )
    except VlmError as exc:
        # fail-open to the driver, fail-closed on the car: the caller releases
        # the user and L3 puts the vehicle into 停用(system_error).
        base.error = str(exc)
        return base

    base.model = meta["model"]
    base.latency_ms = meta["latency_ms"]
    base.cost_usd = meta["cost_usd"]

    base.assessable = bool(parsed.get("assessable", True))
    base.assessable_reason = parsed.get("assessable_reason")
    base.retake_hint = parsed.get("retake_hint")

    if not base.assessable:
        if retake_count >= MAX_RETAKES:
            # Out of retries. Accept the photo, mark it, and let L3 route the
            # car to 停用(unassessable) rather than trapping the driver.
            base.quality_forced = True
            base.retake_required = False
        else:
            base.retake_required = True
            base.retake_hint = base.retake_hint or "請換一個角度避開光源，或退後一步"

    if interior:
        base.cleanliness = parsed.get("cleanliness")
        base.cleanliness_conf = parsed.get("cleanliness_conf")
        base.items = parsed.get("items") or []
        if not base.assessable:
            base.cleanliness = None
            base.items = None
        return base

    base.coverage_adequate = bool(parsed.get("coverage_adequate", True))
    base.coverage_hint = parsed.get("coverage_hint")
    base.angle_verified = parsed.get("angle_verified")
    base.angle_conf = float(parsed.get("angle_conf") or 0.0)
    base.angle_uncertain = base.angle_conf < ANGLE_CONF_FLOOR
    base.angle_mismatch = (
        not base.angle_uncertain
        and base.angle_verified not in (None, "不確定", slot)
    )

    if not base.assessable:
        # Unreadable means unknown, not clean. Anything the model said about
        # damage here is discarded rather than recorded.
        base.observed_damages = None
        return base

    damages = [
        ObservedDamage(
            part=d["part"], type=d["type"], severity=Severity(d["severity"])
        )
        for d in parsed.get("observed_damages") or []
    ]
    base.observed_damages = damages
    base.max_severity = max(
        (d.severity for d in damages), key=lambda s: s.rank, default=Severity.none
    )
    # High recall: *any* observed damage on a return frame is worth one L2 call.
    # The severity threshold lives in L2/L3, not here.
    base.escalate_to_l2 = stage is Stage.ret and bool(damages)
    return base
