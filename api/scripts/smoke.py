"""Run one photo through L1 (and optionally L2) against the live models.

    api/.venv/bin/python api/scripts/smoke.py exterior 左前 assets/images/return/camera_scene.png
    api/.venv/bin/python api/scripts/smoke.py interior 後座 assets/images/return/shot_interior.jpg
    api/.venv/bin/python api/scripts/smoke.py pair 左前 return.jpg pickup.jpg
"""

import asyncio
import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from app import l1, l2  # noqa: E402
from app.models import Stage  # noqa: E402


async def main() -> None:
    mode, slot, *paths = sys.argv[1:]
    images = [Path(p).read_bytes() for p in paths]

    if mode == "pair":
        result = await l2.confirm(
            return_image=images[0],
            baseline_image=images[1] if len(images) > 1 else None,
            photo_id="p_smoke",
            car_no="RDS-6583",
            slot=slot,
            baseline_photo_id="p_base",
        )
    else:
        result = await l1.screen(
            image=images[0],
            photo_id="p_smoke",
            order_id="47352776",
            car_no="RDS-6583",
            stage=Stage.ret,
            slot=slot,
            interior=(mode == "interior"),
            l0={"passed": True, "car_coverage": 0.62, "blur_score": 128.4},
        )

    print(json.dumps(result.model_dump(mode="json"), ensure_ascii=False, indent=2))


asyncio.run(main())
