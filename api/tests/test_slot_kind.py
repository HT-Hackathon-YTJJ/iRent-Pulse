"""Which of L1's three prompts each slot lands in.

`加油卡/停車卡` is the one worth pinning: it used to fall through to `exterior`,
whose first question is whether the car's paintwork is legible, and the answer
for a photograph of a sun visor was reliably "根本沒有拍到車" — a retake demand
the driver could never satisfy.
"""

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from app.main import slot_kind  # noqa: E402
from app.models import SlotKind  # noqa: E402


def test_slot_kind_routes_the_three_questions():
    # The bug this was written for: 加油卡/停車卡 used to fall through to
    # `exterior`, whose first question is whether the paintwork is legible.
    assert slot_kind("加油卡/停車卡") is SlotKind.card
    assert slot_kind("後座") is SlotKind.interior
    assert slot_kind("前座") is SlotKind.interior
    for corner in ("左前", "右前", "左後", "右後"):
        assert slot_kind(corner) is SlotKind.exterior
