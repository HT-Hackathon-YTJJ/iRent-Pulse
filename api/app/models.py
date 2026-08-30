"""Wire types for L0 → L1 → L2 → L3.

Field names follow 分層規格書_v1.md so the JSON on the wire can be read next to
the spec. Severity is carried as an English enum internally and rendered into
the spec's 無／輕微／中度／嚴重 only at the display edge; damage *types* stay in
Chinese because that is what the VLM is asked to emit and what 客服 reads.
"""

from enum import Enum
from typing import Dict, List, Optional

from pydantic import BaseModel, Field


class Stage(str, Enum):
    pickup = "pickup"
    ret = "return"


class Severity(str, Enum):
    none = "none"
    minor = "minor"
    moderate = "moderate"
    severe = "severe"

    @property
    def rank(self) -> int:
        return {"none": 0, "minor": 1, "moderate": 2, "severe": 3}[self.value]

    @property
    def zh(self) -> str:
        return {"none": "無", "minor": "輕微", "moderate": "中度", "severe": "嚴重"}[
            self.value
        ]


#: The three SOCAR-validated classes plus 破裂 and 缺件 (spec §L1).
DAMAGE_TYPES = ["刮痕", "凹陷", "板件間隙", "破裂", "缺件"]

#: Closed vocabulary for the part index. L2's set difference is done on these
#: strings, so both stages have to draw from the same list or nothing matches.
PART_NAMES = [
    "前保險桿左側", "前保險桿中央", "前保險桿右側",
    "左前葉子板", "右前葉子板",
    "左前車門", "右前車門", "左後車門", "右後車門",
    "左側裙板", "右側裙板",
    "左後葉子板", "右後葉子板",
    "後保險桿左側", "後保險桿中央", "後保險桿右側",
    "引擎蓋", "行李廂蓋", "車頂",
    "左前大燈", "右前大燈", "左後燈", "右後燈",
    "左後視鏡", "右後視鏡",
    "前擋風玻璃", "後擋風玻璃",
    "左前輪圈", "右前輪圈", "左後輪圈", "右後輪圈",
]

ANGLES = ["左前", "右前", "左後", "右後", "正前", "正後", "左側", "右側", "車內"]

CLEANLINESS = ["乾淨", "普通", "髒汙"]


# The `l0` block that rides along with each photo is passed through as a plain
# dict rather than modelled here: it is diagnostic metadata produced by the
# handset, and rejecting a photo because a future L0 added a field would be the
# wrong trade. `prompts.l0_note` reads the two keys it actually uses.


class ObservedDamage(BaseModel):
    part: str
    type: str
    severity: Severity


class L1Result(BaseModel):
    photo_id: str
    order_id: str
    car_no: str
    stage: Stage
    slot: str

    assessable: bool
    assessable_reason: Optional[str] = None
    retake_required: bool = False
    retake_hint: Optional[str] = None

    # 覆蓋範圍 is deliberately separate from 可判讀性: a close-up of one cracked
    # bumper is assessable *and* under-covered, and its damage must still count.
    coverage_adequate: bool = True
    coverage_hint: Optional[str] = None

    angle_verified: Optional[str] = None
    angle_conf: float = 0.0
    angle_mismatch: bool = False
    angle_uncertain: bool = False

    observed_damages: Optional[List[ObservedDamage]] = None
    max_severity: Severity = Severity.none
    escalate_to_l2: bool = False

    # Interior frames only.
    cleanliness: Optional[str] = None
    cleanliness_conf: Optional[float] = None
    items: Optional[List[str]] = None

    quality_forced: bool = False
    retake_count: int = 0

    model: str = ""
    latency_ms: int = 0
    cost_usd: float = 0.0
    error: Optional[str] = None


class L2Finding(BaseModel):
    part: str
    type: str
    verdict: str  # 新增 / 既有 / 無法判定
    severity: int = Field(ge=1, le=4)
    confidence: float = 0.0
    reason: str = ""


class L2Result(BaseModel):
    photo_id: str
    car_no: str
    baseline_photo_id: Optional[str] = None
    baseline_available: bool = False
    findings: List[L2Finding] = []
    max_new_severity: int = 0
    unclear_parts: List[str] = []
    model: str = ""
    latency_ms: int = 0
    cost_usd: float = 0.0
    error: Optional[str] = None


class VehicleStatus(str, Enum):
    rentable = "可租用"
    needs_cleaning = "待清潔"
    out_of_service = "停用"


class L3Decision(BaseModel):
    order_id: str
    car_no: str
    status: VehicleStatus
    reason: Optional[str] = None
    rule: int = 0
    queues: List[str] = []
    explain: str = ""
    history_entries: List[Dict[str, str]] = []
    notify_user: Optional[str] = None
