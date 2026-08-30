"""HTTP surface for the 還車照片 pipeline.

    POST /v1/l1/screen              一張照片，阻塞，使用者在等這個
    POST /v1/returns/{id}/finalize  L2 + L3，使用者已經走了
    POST /v1/l3/decide              純規則，可離線重放
    GET  /v1/orders/{id}            客服複核要看的東西
    GET  /v1/photos/{photo_id}      取車／還車照片並排對照用

L1 is the only blocking call. Everything after it runs once the driver has left,
which is why finalize is a separate request rather than a longer L1.
"""

import json
from typing import Any, Dict, List, Optional

from fastapi import FastAPI, File, Form, HTTPException, UploadFile
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import FileResponse
from pydantic import BaseModel

from . import config, l1 as l1_layer, l2 as l2_layer, l3 as l3_layer
from .models import L1Result, L2Result, L3Decision, Stage
from .store import STORE

app = FastAPI(
    title="iRent Pulse — 車況分層檢測 API",
    version="1.0.0",
    description="L1 快篩（阻塞）／L2 影像確認／L3 決策派工。分層規格書 v2。",
)

# The Flutter client runs from a phone, a simulator and `flutter run -d chrome`;
# this service is only ever reachable on a demo LAN.
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)

INTERIOR_SLOTS = {"車內", "後座", "前座", "駕駛座", "副駕"}


@app.get("/healthz")
async def healthz() -> Dict[str, Any]:
    return {
        "ok": True,
        "l1_model": config.L1_MODEL,
        "l2_model": config.L2_MODEL,
        "openrouter_key": bool(config.OPENROUTER_API_KEY),
        "max_retakes": l1_layer.MAX_RETAKES,
    }


@app.post("/v1/l1/screen", response_model=L1Result)
async def l1_screen(
    file: UploadFile = File(...),
    order_id: str = Form(...),
    car_no: str = Form(...),
    stage: str = Form("return"),
    slot: str = Form(...),
    l0: str = Form("{}"),
    retake: bool = Form(False),
) -> L1Result:
    """一張照片的阻塞快篩。逐張呼叫，前端並行送出、逐張回報。"""
    data = await file.read()
    if not data:
        raise HTTPException(400, "empty upload")

    try:
        l0_report: Dict[str, Any] = json.loads(l0) if l0 else {}
    except json.JSONDecodeError:
        l0_report = {}

    stage_enum = Stage(stage)
    photo = STORE.save_photo(
        order_id=order_id, car_no=car_no, stage=stage, slot=slot, data=data
    )
    count = STORE.bump_retake(order_id, slot) if retake else STORE.retake_count(order_id, slot)

    result = await l1_layer.screen(
        image=data,
        photo_id=photo.photo_id,
        order_id=order_id,
        car_no=car_no,
        stage=stage_enum,
        slot=slot,
        interior=slot in INTERIOR_SLOTS,
        l0=l0_report,
        retake_count=count,
    )
    STORE.record_l1(result)
    return result


class FinalizeRequest(BaseModel):
    order_id: str
    car_no: str


class FinalizeResponse(BaseModel):
    decision: L3Decision
    l2: List[L2Result]
    l1: List[L1Result]
    cost_usd: float


@app.post("/v1/returns/finalize", response_model=FinalizeResponse)
async def finalize(req: FinalizeRequest) -> FinalizeResponse:
    """非同步段：對每張升級的照片跑 L2，再跑 L3。使用者不等這個。"""
    order = STORE.get_order(req.order_id)
    if order is None:
        raise HTTPException(404, f"unknown order {req.order_id}")

    l1_results = list(order.l1.values())
    l2_results: List[L2Result] = []

    for result in l1_results:
        if not result.escalate_to_l2:
            continue
        photo = order.photos.get(result.photo_id)
        if photo is None:
            continue
        baseline = STORE.baseline_photo(req.car_no, result.slot)
        baseline_bytes = None
        if baseline is not None:
            with open(baseline.path, "rb") as fh:
                baseline_bytes = fh.read()
        with open(photo.path, "rb") as fh:
            return_bytes = fh.read()

        confirmed = await l2_layer.confirm(
            return_image=return_bytes,
            baseline_image=baseline_bytes,
            photo_id=result.photo_id,
            car_no=req.car_no,
            slot=result.slot,
            baseline_photo_id=baseline.photo_id if baseline else None,
        )
        STORE.record_l2(req.order_id, confirmed)
        l2_results.append(confirmed)

    decision = l3_layer.decide(
        order_id=req.order_id, car_no=req.car_no, l1=l1_results, l2=l2_results
    )
    order.decision = decision

    return FinalizeResponse(
        decision=decision,
        l2=l2_results,
        l1=l1_results,
        cost_usd=round(
            sum(r.cost_usd for r in l1_results) + sum(r.cost_usd for r in l2_results), 6
        ),
    )


class DecideRequest(BaseModel):
    order_id: str
    car_no: str
    l1: List[L1Result] = []
    l2: List[L2Result] = []


@app.post("/v1/l3/decide", response_model=L3Decision)
async def decide(req: DecideRequest) -> L3Decision:
    """純規則引擎，不呼叫任何模型。給測試與營運重放用。"""
    return l3_layer.decide(
        order_id=req.order_id, car_no=req.car_no, l1=req.l1, l2=req.l2
    )


@app.get("/v1/orders/{order_id}")
async def get_order(order_id: str) -> Dict[str, Any]:
    """客服複核介面的資料來源：取車／還車照片、AI 判定、reason 說明。"""
    order = STORE.get_order(order_id)
    if order is None:
        raise HTTPException(404, f"unknown order {order_id}")
    return {
        "order_id": order.order_id,
        "car_no": order.car_no,
        "photos": [
            {
                "photo_id": p.photo_id,
                "stage": p.stage,
                "slot": p.slot,
                "url": f"/v1/photos/{p.photo_id}",
                "baseline_url": _baseline_url(order.car_no, p.slot),
            }
            for p in order.photos.values()
        ],
        "l1": [r.model_dump(mode="json") for r in order.l1.values()],
        "l2": [r.model_dump(mode="json") for r in order.l2.values()],
        "decision": order.decision.model_dump(mode="json") if order.decision else None,
    }


def _baseline_url(car_no: str, slot: str) -> Optional[str]:
    baseline = STORE.baseline_photo(car_no, slot)
    return f"/v1/photos/{baseline.photo_id}" if baseline else None


@app.get("/v1/photos/{photo_id}")
async def get_photo(photo_id: str) -> FileResponse:
    photo = STORE.photo(photo_id)
    if photo is None:
        raise HTTPException(404, f"unknown photo {photo_id}")
    return FileResponse(photo.path, media_type=photo.content_type)
