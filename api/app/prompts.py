"""Prompts and JSON schemas for L1 and L2.

Two findings from the benchmark shape every prompt here:

* `retake_required` fired 0 times in 200 calls when assessability was asked as
  an afterthought of the damage question (spec §L1). So assessability is asked
  **first**, given a concrete list of failure modes, and the model is told in
  as many words that an unassessable photo must report no damage.
* VLMs answer whatever they are asked. Asking "where is the damage" invents
  damage, so the question is always "is there damage — if none, say so".
"""

from typing import Any, Dict, List

from .models import ANGLES, CLEANLINESS, DAMAGE_TYPES, PART_NAMES

_PARTS_LIST = "、".join(PART_NAMES)
_TYPES_LIST = "、".join(DAMAGE_TYPES)

_SEVERITY_RUBRIC = """嚴重度分四級：
- none：車身完好，或只有洗得掉的髒污、水漬
- minor：刮痕擦傷，漆面有痕跡但鈑件未變形
- moderate：凹陷、明顯破損、鈑件變形
- severe：結構性損壞、零件脫落、必須進廠"""

_NOT_DAMAGE = """以下一律**不算**損傷，不得列入：水漬、雨滴、灰塵、泥沙、
鳥糞、反光亮點、陰影、地面倒影、車窗中的倒影、貼紙、既有的接縫線與模具線、
輪胎正常磨耗、車內物品。看到這些請當作車身完好。"""

# ---------------------------------------------------------------------------
# L1 — 車外
# ---------------------------------------------------------------------------

L1_EXTERIOR_SYSTEM = f"""你是租車還車照片的車況快篩系統。你只看**這一張**照片，
不知道這台車以前的狀況，也**不要**猜測損傷是新的還是舊的——那是下一層的工作。

請依序回答兩個問題，順序不可顛倒：

**問題一：這張照片能不能用來判斷車損？（可判讀性）**
「可判讀」的定義是：照片中車身表面的漆面狀況看得出來。
不可判讀的情形（符合任一項即為不可判讀）：
- 整片反光或強光源，漆面被洗白
- 過暗、落在深陰影裡，看不出表面
- 對焦失敗或晃動導致模糊
- 車身被雨水、厚灰、泥污覆蓋，看不到漆面
- 車體在畫面中太小（明顯小於畫面的三分之一），細節無法分辨
- 主要被其他車輛、柱子、人遮擋
- 根本沒有拍到車

**可判讀性與覆蓋範圍是兩件事，不要混為一談。**
一張只拍到左前保險桿的特寫，若那塊保險桿清清楚楚，就是「可判讀」但「覆蓋不足」。
它看到的裂痕**必須**照常回報，只是 coverage_adequate 要標 false。
「距離過近／裁切」屬於覆蓋不足，不是不可判讀。

**若 assessable 為 false，observed_damages 必須是空陣列。** 不可判讀就是看不出來，
看不出來就不能宣稱有損傷，也不能宣稱沒有損傷。

**問題二：這張照片上看得到損傷嗎？**
中性回答：有就列出，沒有就回空陣列。不要為了「有交代」而編造。
{_NOT_DAMAGE}

損傷類型只能用：{_TYPES_LIST}
部位只能用下列名稱：{_PARTS_LIST}
（若損傷落在清單以外的部位，選最接近的一個。）

{_SEVERITY_RUBRIC}

這一層的調校方向是**寧可錯殺**：只要你認為「有點像損傷」就列出來，
後面還有一層昂貴的模型會逐項確認。漏掉的損傷永遠不會再被看到。
但「寧可錯殺」不適用於上面那份不算損傷的清單——水漬與反光就是水漬與反光。"""


def l1_exterior_user(slot: str, stage: str, l0_note: str) -> str:
    when = "取車前" if stage == "pickup" else "還車時"
    return (
        f"這是{when}拍攝的車外照片，預期角度是「{slot}」。\n"
        f"{l0_note}\n"
        "請先判斷可判讀性，再回報看到的損傷。"
        "angle_verified 請填你實際看到的角度，與預期不符也照實填。"
    )


L1_EXTERIOR_SCHEMA: Dict[str, Any] = {
    "type": "object",
    "additionalProperties": False,
    "required": [
        "assessable",
        "assessable_reason",
        "retake_hint",
        "coverage_adequate",
        "coverage_hint",
        "angle_verified",
        "angle_conf",
        "observed_damages",
    ],
    "properties": {
        "assessable": {
            "type": "boolean",
            "description": "車身漆面狀況是否看得出來",
        },
        "assessable_reason": {
            "type": ["string", "null"],
            "description": "不可判讀時，一句話說明原因；可判讀時為 null",
        },
        "retake_hint": {
            "type": ["string", "null"],
            "description": "給使用者的重拍指示，例如「請換一個角度避開光源」；不需重拍時為 null",
        },
        "coverage_adequate": {
            "type": "boolean",
            "description": "該角度的主要部位是否都入鏡（與可判讀性無關）",
        },
        "coverage_hint": {
            "type": ["string", "null"],
            "description": "覆蓋不足時的提示，例如「請退後一步」",
        },
        "angle_verified": {
            "type": "string",
            "enum": ANGLES + ["不確定"],
            "description": "照片實際拍到的角度",
        },
        "angle_conf": {"type": "number", "minimum": 0, "maximum": 1},
        "observed_damages": {
            "type": "array",
            "description": "看得到的損傷；沒有就是空陣列。assessable 為 false 時必須為空陣列。",
            "items": {
                "type": "object",
                "additionalProperties": False,
                "required": ["part", "type", "severity", "desc"],
                "properties": {
                    "part": {"type": "string", "enum": PART_NAMES},
                    "type": {"type": "string", "enum": DAMAGE_TYPES},
                    "severity": {
                        "type": "string",
                        "enum": ["minor", "moderate", "severe"],
                    },
                    "desc": {"type": "string", "description": "一句話描述所見"},
                },
            },
        },
    },
}

# ---------------------------------------------------------------------------
# L1 — 車內
# ---------------------------------------------------------------------------

L1_INTERIOR_SYSTEM = f"""你是租車還車照片的車內整潔度檢查系統。你只看這一張照片。

請依序回答：

**問題一：這張照片能不能判讀？** 太暗、模糊、根本沒拍到車內（例如拍到天空、
地面、人臉特寫）都算不可判讀。不可判讀時 cleanliness 請填「普通」並把
assessable 設為 false。

**問題二：車內整潔度。** 三級：
- 乾淨：沒有明顯垃圾或髒污
- 普通：有些微灰塵或使用痕跡，不需要清潔派工
- 髒汙：有垃圾、食物殘渣、液體潑灑、明顯污漬

items 請列出你看到的具體垃圾（例如「飲料杯」「食物包裝」「面紙」）；
沒有就回空陣列。

原廠配件（腳踏墊、面紙盒、遮陽板、兒童安全座椅、椅套）**不是垃圾**。
光影、深色椅套的紋理、皮革折痕也不是髒污。

這一層的判定會直接讓車輛進入「待清潔」，是否派人由人工確認，
所以寧可標出來讓人看一眼，也不要放過真正的髒汙。"""

L1_INTERIOR_USER = "這是還車時拍攝的車內照片。請判斷可判讀性與整潔度。"

L1_INTERIOR_SCHEMA: Dict[str, Any] = {
    "type": "object",
    "additionalProperties": False,
    "required": [
        "assessable",
        "assessable_reason",
        "retake_hint",
        "cleanliness",
        "cleanliness_conf",
        "items",
    ],
    "properties": {
        "assessable": {"type": "boolean"},
        "assessable_reason": {"type": ["string", "null"]},
        "retake_hint": {"type": ["string", "null"]},
        "cleanliness": {"type": "string", "enum": CLEANLINESS},
        "cleanliness_conf": {"type": "number", "minimum": 0, "maximum": 1},
        "items": {"type": "array", "items": {"type": "string"}},
    },
}

# ---------------------------------------------------------------------------
# L2 — Stage A：分別描述，**不做比較**
# ---------------------------------------------------------------------------

L2_DESCRIBE_SYSTEM = f"""你是車損鑑定系統的影像描述階段。

你的工作**不是**比較兩張照片。你只描述**這一張**照片，以「車輛部位」為索引，
回報兩件事：

1. **visible_parts**：這張照片中**清晰可見、足以判斷有無損傷**的部位。
   只有你真的看得清楚漆面的部位才列進來。被遮擋、模糊、反光、太暗、
   在畫面邊緣被裁切、根本沒入鏡的部位，一律不要列。
   這份清單決定了下游能不能說「這道傷是新的」，寧缺勿濫。

2. **damages**：看得到的損傷。沒有就回空陣列。

{_NOT_DAMAGE}

損傷類型只能用：{_TYPES_LIST}
部位只能用下列名稱：{_PARTS_LIST}

嚴重度用 1–4 的整數：
1 = 輕微刮擦，漆面有痕跡但鈑件未變形
2 = 明顯刮痕或小凹陷
3 = 凹陷、破損、鈑件變形，需要進廠
4 = 結構性損壞、零件脫落

這一層的調校方向是**寧可保留**：不確定就不要列成損傷，也不要把不確定的部位
列進 visible_parts。誤判有車損會導致誤扣押金，代價遠高於漏判。"""


def l2_describe_user(label: str, slot: str) -> str:
    return (
        f"這是同一台車「{slot}」角度的{label}照片。\n"
        "請列出清晰可見的部位，以及看得到的損傷。不要提到任何其他照片。"
    )


L2_DESCRIBE_SCHEMA: Dict[str, Any] = {
    "type": "object",
    "additionalProperties": False,
    "required": ["assessable", "visible_parts", "damages"],
    "properties": {
        "assessable": {"type": "boolean"},
        "visible_parts": {
            "type": "array",
            "items": {"type": "string", "enum": PART_NAMES},
        },
        "damages": {
            "type": "array",
            "items": {
                "type": "object",
                "additionalProperties": False,
                "required": ["part", "type", "severity", "desc", "confidence"],
                "properties": {
                    "part": {"type": "string", "enum": PART_NAMES},
                    "type": {"type": "string", "enum": DAMAGE_TYPES},
                    "severity": {"type": "integer", "minimum": 1, "maximum": 4},
                    "desc": {"type": "string"},
                    "confidence": {"type": "number", "minimum": 0, "maximum": 1},
                },
            },
        },
    },
}


def l0_note(l0: Dict[str, Any]) -> str:
    """One line of端上 metadata, so L1 knows a manual shutter bypassed L0."""
    if not l0:
        return ""
    if l0.get("bypassed") or l0.get("capture_mode") == "manual":
        return (
            "注意：這張是使用者手動快門拍的，端上品質檢查被略過，"
            "請對可判讀性從嚴檢查。"
        )
    bits: List[str] = []
    if l0.get("car_coverage") is not None:
        bits.append(f"端上量到車體佔畫面 {l0['car_coverage']:.0%}")
    if l0.get("blur_score") is not None:
        bits.append(f"清晰度分數 {l0['blur_score']:.0f}")
    return ("參考：" + "、".join(bits) + "。") if bits else ""
