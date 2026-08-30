"""Walk one whole trip through the service: 取車 → 還車 → finalize.

Needs the server up (`api/run.sh`). Prints what every layer decided, which is
the fastest way to see the pipeline end to end without a handset.

    api/.venv/bin/python api/scripts/demo_trip.py \
        --pickup 左前=pickup_fl.jpg --return 左前=return_fl.jpg \
        --return 後座=cabin.jpg

Slots: 左前 右前 左後 右後（車外）、後座（車內）。
Uploading the 取車 side matters more than it looks: without a baseline every
finding L2 makes is 無法判定, because it cannot tell a new scratch from one the
car already had.
"""

import argparse
import json
import sys
from pathlib import Path

import httpx


def upload(client, base, stage, slot, path, order_id, car_no):
    with open(path, "rb") as fh:
        response = client.post(
            f"{base}/v1/l1/screen",
            data={
                "order_id": order_id,
                "car_no": car_no,
                "stage": stage,
                "slot": slot,
                "l0": json.dumps(
                    {"passed": True, "car_coverage": 0.6, "blur_score": 140}
                ),
            },
            files={"file": (Path(path).name, fh, "image/jpeg")},
        )
    response.raise_for_status()
    return response.json()


def show(stage, slot, r):
    flag = "✓" if r["assessable"] else "✗"
    line = f"  {flag} [{stage}] {slot}"
    if not r["assessable"]:
        line += f" — {r['assessable_reason']}"
    elif r.get("cleanliness"):
        line += f" — 整潔度 {r['cleanliness']} {r.get('items') or ''}"
    else:
        damages = r.get("observed_damages") or []
        line += f" — {len(damages)} 處疑似損傷" if damages else " — 未見損傷"
    print(f"{line}   ({r['latency_ms']}ms, ${r['cost_usd']:.4f})")


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--base", default="http://127.0.0.1:8000")
    ap.add_argument("--order-id", default="demo-47352776")
    ap.add_argument("--car-no", default="RDS-6583")
    ap.add_argument("--pickup", action="append", default=[], metavar="角度=路徑")
    ap.add_argument("--return", dest="ret", action="append", default=[], metavar="角度=路徑")
    args = ap.parse_args()

    if not args.ret:
        ap.error("至少要有一張還車照片")

    with httpx.Client(timeout=180) as client:
        print("L1（取車，建立比對基準）")
        for pair in args.pickup:
            slot, _, path = pair.partition("=")
            show("取車", slot, upload(client, args.base, "pickup", slot, path, args.order_id, args.car_no))
        if not args.pickup:
            print("  （無取車照，L2 的判定會全部落在「無法判定」）")

        print("\nL1（還車，阻塞，使用者在等）")
        for pair in args.ret:
            slot, _, path = pair.partition("=")
            show("還車", slot, upload(client, args.base, "return", slot, path, args.order_id, args.car_no))

        print("\nL2 + L3（使用者已離開）")
        response = client.post(
            f"{args.base}/v1/returns/finalize",
            json={"order_id": args.order_id, "car_no": args.car_no},
        )
        response.raise_for_status()
        payload = response.json()

    for result in payload["l2"]:
        for f in result["findings"]:
            print(f"  L2 {f['verdict']}：{f['part']}{f['type']}（severity {f['severity']}）— {f['reason']}")
    if not payload["l2"]:
        print("  L2 未觸發（L1 沒有在還車照上看到損傷）")

    d = payload["decision"]
    print(f"\nL3 規則 {d['rule']} → {d['status']}" + (f"（{d['reason']}）" if d["reason"] else ""))
    print(f"  {d['explain']}")
    print(f"  佇列：{d['queues'] or '無'}")
    print(f"  通知使用者：{d['notify_user'] or '不通知'}")
    print(f"\n本趟總成本 ${payload['cost_usd']:.4f}")
    return 0


sys.exit(main())
