"""L3 — 決策與派工. Deterministic rules, no model.

This layer must be auditable (客訴 needs an explanation), adjustable without
retraining, and explainable because money hangs off it. So it is a table, in
the same order as 分層規格書 §L3, and every decision carries the rule number
that produced it.

Two invariants from the spec:

* **狀態自動，行動經人.** L3 may make a car unrentable — protective, reversible,
  protects the next driver. It may never dispatch a person, spend money, or
  charge a customer. Those are queue entries for a human.
* **AI 只能把車移出「可租用」.** The one automatic path back is rule 8, a return
  where every check passed.

The 留言板 does **not** appear as a rule here, deliberately. L2 already resolved
每一筆 finding against it and wrote the note into `reason`; adding a rule that
reads notes again would mean two layers deciding the same thing, and the rule
table would stop being the whole story. What L3 does with the board is carry it:
the note id travels into 車況履歷 so 客服 can open the sentence that stopped a
claim, and rule 5's explanation says when one is attached.
"""

from typing import Dict, List, Optional

from .models import BoardNote, L1Result, L2Result, L3Decision, Stage, VehicleStatus

Q_CLEAN = "清潔確認"
Q_CS = "客服複核"
Q_FIX = "維修／營運"


def decide(
    *,
    order_id: str,
    car_no: str,
    l1: List[L1Result],
    l2: Optional[List[L2Result]] = None,
    notes: Optional[List[BoardNote]] = None,
) -> L3Decision:
    l2 = l2 or []
    notes_by_id = {n.note_id: n for n in (notes or []) if n.note_id}
    ret = [r for r in l1 if r.stage is Stage.ret]
    pickup = [r for r in l1 if r.stage is Stage.pickup]

    def out(
        rule: int,
        status: VehicleStatus,
        reason: Optional[str],
        queues: List[str],
        explain: str,
        notify: Optional[str] = None,
    ) -> L3Decision:
        return L3Decision(
            order_id=order_id,
            car_no=car_no,
            status=status,
            reason=reason,
            rule=rule,
            queues=queues,
            explain=explain,
            history_entries=_history(l2, notes_by_id),
            notify_user=notify,
        )

    # 1 — 髒汙 first, and that ordering is deliberate: dirt lands on the next
    # driver in 30 minutes, while a damage claim can be negotiated slowly.
    dirty = [r for r in ret if r.cleanliness == "髒汙"]
    if dirty:
        items = sorted({i for r in dirty for i in (r.items or [])})
        detail = "、".join(items) if items else "車內髒汙"
        return out(
            1,
            VehicleStatus.needs_cleaning,
            None,
            [Q_CLEAN],
            f"車內偵測到{detail}，需人工確認後派清潔。",
            "已收到您的還車，車內狀態確認中。",
        )

    # 7 — any layer that errored means the car was never actually checked.
    errored = [r for r in l1 if r.error] + [r for r in l2 if r.error]
    if errored:
        return out(
            7,
            VehicleStatus.out_of_service,
            "system_error",
            [Q_CS],
            f"檢查流程有 {len(errored)} 項未完成（{errored[0].error}），車輛不進下一單。",
            "本次還車檢查仍在進行，若有異常我們會主動與您聯繫。",
        )

    # 2 — damage already present at pickup happened while the car sat idle. This
    # must be tested before any 新增 rule, or 客服 will treat an operations
    # problem as a customer dispute.
    idle = [r for r in pickup if r.observed_damages]
    if idle:
        parts = sorted({d.part for r in idle for d in (r.observed_damages or [])})
        return out(
            2,
            VehicleStatus.out_of_service,
            "idle_anomaly",
            [Q_FIX],
            f"取車時即偵測到損傷（{ '、'.join(parts) }），發生於閒置期間，非本次租用者責任。",
        )

    new_findings = [f for r in l2 for f in r.findings if f.verdict == "新增"]
    severe = [f for f in new_findings if f.severity >= 3]

    # 3 — pull the car *and* open a claim review. Two queues on purpose: the
    # vehicle action and the money action are orthogonal. Confidence decides
    # whether to move the car, never whether to charge.
    if severe:
        parts = "、".join(f"{f.part}{f.type}" for f in severe)
        return out(
            3,
            VehicleStatus.out_of_service,
            "new_damage",
            [Q_FIX, Q_CS],
            f"本趟新增損傷（{parts}），嚴重度 ≥ 3，車輛停用並送客服複核。",
            "本次還車偵測到需進一步確認之車況，客服人員複核中，將於 24 小時內與您聯繫。",
        )

    # 5 — 無法判定 is honest uncertainty, and it goes to a human rather than a
    # guess in either direction.
    unclear = [f for r in l2 for f in r.findings if f.verdict == "無法判定"]
    if unclear:
        parts = "、".join(sorted({f.part for f in unclear}))
        # A note attached to one of these is the difference between 客服 opening
        # a blank case and 客服 opening a case with the previous driver's own
        # words in it. Say so, or nobody will look.
        cited = [f.note_id for f in unclear if f.note_id]
        board = f"（其中 {len(cited)} 項有留言板紀錄可對照）" if cited else ""
        return out(
            5,
            VehicleStatus.out_of_service,
            "undetermined",
            [Q_CS],
            f"{parts} 在取車照中未清晰入鏡，無法判定是否為本趟新增{board}。",
            "本次還車檢查已完成，如有異常我們會主動與您聯繫。",
        )

    # 6 — includes quality_forced, i.e. the driver hit the retake cap.
    unreadable = [r for r in ret if not r.assessable or r.quality_forced]
    if unreadable:
        slots = "、".join(sorted({r.slot for r in unreadable}))
        return out(
            6,
            VehicleStatus.out_of_service,
            "unassessable",
            [Q_CS],
            f"{slots} 照片無法判讀且已達重拍上限，車況未經確認。",
            "本次還車檢查已完成，如有異常我們會主動與您聯繫。",
        )

    # 4 — minor new damage: recorded, never billed. Deliberately *not* a
    # terminating rule; it shares its status with rule 8, so letting it
    # short-circuit the checks below would trade safety for nothing. Every
    # false positive in the benchmark was `minor`, which is why the claim
    # threshold sits at moderate and is an operations-tunable parameter.
    minor = [f for f in new_findings if f.severity < 3]
    if minor:
        parts = "、".join(f"{f.part}{f.type}" for f in minor)
        return out(
            4,
            VehicleStatus.rentable,
            None,
            [],
            f"本趟新增輕微損傷（{parts}），僅記入車況履歷，不求償、不通知使用者。",
            "本次還車深度分析已完成，您無需負擔任何費用。感謝愛惜車輛。",
        )

    return out(8, VehicleStatus.rentable, None, [], "所有檢查通過，車輛自動回到可租用。")


def _history(
    l2: List[L2Result], notes: Optional[Dict[str, BoardNote]] = None
) -> List[Dict[str, str]]:
    """Everything a human confirmed or has to confirm goes on the car's record.

    「確認求償」與「記入車況履歷」必須在同一個 transaction 內完成，否則同一道傷
    會重複向不同用戶求償 — so the entries travel with the decision, not after it.

    An entry that leaned on a board note carries the note's id and its text.
    The id alone would be enough to join on, but this record is what 客服 reads
    during a dispute, and a claim withheld on somebody's testimony should show
    the testimony next to it rather than a foreign key.
    """
    notes = notes or {}
    entries: List[Dict[str, str]] = []
    for r in l2:
        for f in r.findings:
            entry = {
                "part": f.part,
                "type": f.type,
                "verdict": f.verdict,
                "severity": str(f.severity),
                "photo_id": r.photo_id,
                "reason": f.reason,
            }
            if f.note_id:
                entry["note_id"] = f.note_id
                note = notes.get(f.note_id)
                if note is not None:
                    entry["note_text"] = note.text
            entries.append(entry)
    return entries
