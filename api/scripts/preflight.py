"""Demo 圖庫預檢 — run every candidate photo through L1 several times and report
whether L1 says the same thing each time, and whether what it says is what the
demo needs it to say.

Two questions, and they are different questions:

* **穩定性** — does the same image get the same verdict on every run? An image
  that flips between 有損傷 and 完好 will flip in front of the judges, and no
  amount of rehearsal changes that. TODO §4.
* **正確性** — is that verdict the one the script expects? A photo of an
  undamaged car that L1 reliably calls damaged is stable and useless.

Both have to pass before a photo goes in the demo library.

    # the default sweep: demo/return_photos/, three runs each
    api/.venv/bin/python api/scripts/preflight.py

    # the real gate before a demo — 10/10 or it does not ship
    api/.venv/bin/python api/scripts/preflight.py --runs 10

    # 翻拍 A/B (TODO §2): the same shot list re-photographed off a screen,
    # scored against the straight file upload
    api/.venv/bin/python api/scripts/preflight.py --compare demo/rephoto

Exits non-zero if any photo is unstable or fails its expectation, so this can
sit in front of a demo as a gate rather than as a thing somebody remembers to
read.

Costs real money: one L1 call per run per photo, ~$0.0034 each. The default
sweep of 9 photos x 3 runs is about ten cents.
"""

import argparse
import asyncio
import json
import sys
from collections import Counter
from pathlib import Path
from typing import Any, Dict, List, Optional, Tuple

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from app import l1  # noqa: E402
from app.main import slot_kind  # noqa: E402
from app.models import L1Result, SlotKind, Stage  # noqa: E402

#: The demo car. Every body shot in the library carries this plate.
CAR_NO = "REN-0000"
ORDER_ID = "preflight"

#: Filename stem → the `slot` string the app would send, and what the demo
#: needs L1 to conclude about it.
#:
#: Keyed on the stem rather than on an index so the two 情境 variants sit
#: beside the clean version of the same slot: `左後` and `左後被撞擊` are the
#: same shot of the same corner, and the only thing that may differ between
#: their two verdicts is the damage.
SHOTS: Dict[str, Tuple[str, str]] = {
    "加油卡和停車卡": ("加油卡/停車卡", "cards"),
    "前座": ("前座", "clean"),
    "後座": ("後座", "clean"),
    "後座有垃圾": ("後座", "dirty"),
    "左前": ("左前", "undamaged"),
    "右前": ("右前", "undamaged"),
    "右後": ("右後", "undamaged"),
    "左後": ("左後", "undamaged"),
    "左後被撞擊": ("左後", "damaged"),
}


def fingerprint(result: L1Result, kind: SlotKind) -> str:
    """The part of a verdict that has to be identical between runs.

    Deliberately not the whole result. `assessable_reason` is free prose and
    will never repeat word for word; latency and cost never repeat at all.
    What the demo actually shows the judges is the badge, the retake prompt and
    the damage list, so that is what has to be stable.
    """
    if result.error:
        return f"error:{result.error[:60]}"
    head = f"assessable={result.assessable} retake={result.retake_required}"
    if kind is SlotKind.card:
        return (
            f"{head} 停車卡={result.parking_card_present} "
            f"加油卡={result.fuel_card_present}"
        )
    if kind is SlotKind.interior:
        return f"{head} clean={result.cleanliness}"
    damages = sorted(
        f"{d.part}/{d.type}/{d.severity.value}" for d in (result.observed_damages or [])
    )
    return f"{head} damage=[{','.join(damages)}]"


def check(result: L1Result, kind: SlotKind, expect: str) -> Optional[str]:
    """None if the result is what the demo needs, else why not."""
    if result.error:
        return f"L1 錯誤：{result.error[:80]}"
    if not result.assessable:
        return f"不可判讀：{result.assessable_reason}"

    if expect == "cards":
        # Ground truth for this photo: the 加油卡 pocket holds two cards, the
        # 停車卡 pocket is empty. Both halves matter — a model that answers
        # "present" for everything passes the first half and is worthless.
        if result.fuel_card_present is not True:
            return f"加油卡沒被認出來（回 {result.fuel_card_present!r}）"
        if result.parking_card_present is not False:
            return f"空的停車卡插袋被當成有卡（回 {result.parking_card_present!r}）"
        return None

    if expect == "clean":
        return None if result.cleanliness in ("乾淨", "普通") else f"整潔度 {result.cleanliness}"
    if expect == "dirty":
        return None if result.cleanliness == "髒汙" else f"整潔度 {result.cleanliness}，垃圾沒被看到"

    damages = result.observed_damages or []
    if expect == "undamaged":
        if damages:
            found = "、".join(f"{d.part}{d.type}" for d in damages)
            return f"乾淨的角被判有損傷：{found}"
        return None
    if expect == "damaged":
        return None if damages else "撞擊沒被看到"
    raise ValueError(f"unknown expectation {expect!r}")


async def run_once(path: Path, slot: str, kind: SlotKind, index: int) -> L1Result:
    return await l1.screen(
        image=path.read_bytes(),
        photo_id=f"pf_{path.stem}_{index}",
        order_id=ORDER_ID,
        car_no=CAR_NO,
        stage=Stage.ret,
        slot=slot,
        kind=kind,
        # L0 does not run here. The exterior prompt takes an l0 note and an
        # empty one reads as "the handset said nothing", which is honest: this
        # is scoring the image, not the handset.
        l0={},
    )


async def sweep(directory: Path, runs: int) -> List[Dict[str, Any]]:
    """Every photo in `directory` that is on the shot list, `runs` times each.

    All of it concurrently. L1 is one blocking call per photo in production
    too, and running the sweep serially turns a ten-second check into a
    five-minute one for no extra signal.
    """
    jobs: List[Tuple[str, Path, str, SlotKind, int]] = []
    for stem, (slot, _expect) in SHOTS.items():
        matches = sorted(
            p for p in directory.iterdir()
            if p.stem == stem and p.suffix.lower() in {".webp", ".png", ".jpg", ".jpeg"}
        )
        if not matches:
            continue
        path = matches[0]
        kind = slot_kind(slot)
        jobs.extend((stem, path, slot, kind, i) for i in range(runs))

    results = await asyncio.gather(
        *(run_once(path, slot, kind, i) for _stem, path, slot, kind, i in jobs),
        return_exceptions=True,
    )

    by_stem: Dict[str, Dict[str, Any]] = {}
    for (stem, path, slot, kind, _i), result in zip(jobs, results):
        row = by_stem.setdefault(
            stem,
            {"stem": stem, "path": path, "slot": slot, "kind": kind,
             "expect": SHOTS[stem][1], "results": [], "crashes": []},
        )
        if isinstance(result, BaseException):
            row["crashes"].append(repr(result))
        else:
            row["results"].append(result)
    return [by_stem[s] for s in SHOTS if s in by_stem]


def report(rows: List[Dict[str, Any]], runs: int) -> bool:
    """Print the table. True if every photo is fit to demo."""
    print(f"\n{'照片':<14}{'slot':<14}{'一致':<8}{'判定':<52}結果")
    print("-" * 110)
    ok = True
    cost = 0.0
    for row in rows:
        results, kind = row["results"], row["kind"]
        cost += sum(r.cost_usd for r in results)
        prints = Counter(fingerprint(r, kind) for r in results)
        top, agree = prints.most_common(1)[0] if prints else ("(無結果)", 0)
        stable = agree == runs and not row["crashes"]

        failures = [check(r, kind, row["expect"]) for r in results]
        wrong = [f for f in failures if f]
        verdict_ok = not wrong

        status = "通過" if stable and verdict_ok else "不可用"
        if not stable:
            status += f"（{len(prints)} 種判定）"
        if wrong:
            status += f"：{wrong[0]}"
        ok = ok and stable and verdict_ok

        print(f"{row['stem']:<14}{row['slot']:<12}{agree}/{runs:<6}{top[:50]:<52}{status}")
        if len(prints) > 1:
            for text, count in prints.most_common()[1:]:
                print(f"{'':<14}{'':<12}{count}/{runs:<6}{text[:50]}")
        for crash in row["crashes"]:
            print(f"{'':<14}{'':<12}{'crash':<8}{crash[:50]}")

    print("-" * 110)
    print(f"{len(rows)} 張、每張 {runs} 次、共 ${cost:.4f}")
    return ok


def compare(base: List[Dict[str, Any]], other: List[Dict[str, Any]]) -> None:
    """翻拍 A/B — TODO §2.

    The question is narrow: does L1 still read the photo once it has been
    through a phone camera pointed at a screen. The comparison is only
    meaningful for photos the file upload already passed, so a row where the
    original failed prints as `—` rather than as evidence about 翻拍.
    """
    by_stem = {row["stem"]: row for row in other}
    print(f"\n翻拍 A/B\n{'照片':<14}{'(a) 檔案':<24}{'(b) 翻拍':<24}結論")
    print("-" * 90)
    for row in base:
        b = by_stem.get(row["stem"])
        a_fail = next((f for f in (check(r, row["kind"], row["expect"]) for r in row["results"]) if f), None)
        a_txt = "通過" if not a_fail else a_fail[:22]
        if b is None:
            print(f"{row['stem']:<14}{a_txt:<24}{'（缺）':<24}—")
            continue
        b_fail = next((f for f in (check(r, b["kind"], b["expect"]) for r in b["results"]) if f), None)
        b_txt = "通過" if not b_fail else b_fail[:22]
        if a_fail:
            note = "— 原檔本來就沒過，這張說不了翻拍的事"
        elif b_fail:
            note = "翻拍被擋下 ← 這就是 TODO §2 要找的證據"
        else:
            note = "翻拍不是問題"
        print(f"{row['stem']:<14}{a_txt:<24}{b_txt:<24}{note}")


async def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "directory", nargs="?", type=Path, default=Path("demo/return_photos")
    )
    parser.add_argument("--runs", type=int, default=3,
                        help="calls per photo (10 is the pre-demo gate)")
    parser.add_argument("--compare", type=Path, default=None,
                        help="a second directory of the same shot list, "
                             "re-photographed off a screen (TODO §2)")
    parser.add_argument("--json", type=Path, default=None,
                        help="also write every raw L1 result here")
    args = parser.parse_args()

    if not args.directory.is_dir():
        print(f"沒有這個資料夾：{args.directory}", file=sys.stderr)
        return 2

    rows = await sweep(args.directory, args.runs)
    if not rows:
        print(f"{args.directory} 裡沒有任何在 SHOTS 清單上的檔案", file=sys.stderr)
        return 2
    print(f"=== (a) {args.directory} ===")
    ok = report(rows, args.runs)

    other: List[Dict[str, Any]] = []
    if args.compare:
        print(f"\n=== (b) {args.compare} ===")
        other = await sweep(args.compare, args.runs)
        report(other, args.runs)
        compare(rows, other)

    if args.json:
        payload = {
            f"{tag}/{row['stem']}": [r.model_dump(mode="json") for r in row["results"]]
            for tag, group in (("a", rows), ("b", other))
            for row in group
        }
        args.json.write_text(json.dumps(payload, ensure_ascii=False, indent=2))
        print(f"\n原始結果寫到 {args.json}")

    return 0 if ok else 1


sys.exit(asyncio.run(main()))
