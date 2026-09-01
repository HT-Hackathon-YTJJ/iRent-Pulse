"""L3 is the layer that decides whether a car can be rented and whether a human
gets involved, so it is the layer worth pinning down. No network, no model."""

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from app.l3 import Q_CLEAN, Q_CS, Q_FIX, decide  # noqa: E402
from app.models import (  # noqa: E402
    BoardNote,
    L1Result,
    L2Finding,
    L2Result,
    ObservedDamage,
    Severity,
    Stage,
    VehicleStatus,
)


def _l1(**kw) -> L1Result:
    base = dict(
        photo_id="p1",
        order_id="o1",
        car_no="RDS-6583",
        stage=Stage.ret,
        slot="左前",
        assessable=True,
    )
    base.update(kw)
    return L1Result(**base)


def _l2(*findings: L2Finding, **kw) -> L2Result:
    return L2Result(photo_id="p1", car_no="RDS-6583", findings=list(findings), **kw)


def _finding(verdict: str, severity: int = 3) -> L2Finding:
    return L2Finding(
        part="前保險桿左側", type="破裂", verdict=verdict, severity=severity
    )


def _decide(l1, l2=None):
    return decide(order_id="o1", car_no="RDS-6583", l1=l1, l2=l2 or [])


def test_rule_8_all_clear_returns_the_car_to_service():
    out = _decide([_l1(), _l1(slot="後座", cleanliness="乾淨")])
    assert out.rule == 8
    assert out.status is VehicleStatus.rentable
    assert out.queues == []


def test_rule_1_dirty_cabin_beats_everything_else():
    # 髒汙 outranks damage on purpose: it hits the next driver in 30 minutes.
    out = _decide(
        [_l1(slot="後座", cleanliness="髒汙", items=["飲料杯"])],
        [_l2(_finding("新增", 4))],
    )
    assert out.rule == 1
    assert out.status is VehicleStatus.needs_cleaning
    assert out.queues == [Q_CLEAN]


def test_rule_2_damage_at_pickup_is_not_the_drivers_fault():
    out = _decide(
        [
            _l1(
                stage=Stage.pickup,
                observed_damages=[
                    ObservedDamage(
                        part="左前葉子板", type="刮痕", severity=Severity.minor
                    )
                ],
            ),
            _l1(),
        ]
    )
    assert out.rule == 2
    assert out.reason == "idle_anomaly"
    assert out.queues == [Q_FIX]
    assert out.notify_user is None  # nothing is said to a driver who did nothing


def test_rule_3_serious_new_damage_pulls_the_car_and_opens_a_claim_review():
    out = _decide([_l1()], [_l2(_finding("新增", 3))])
    assert out.rule == 3
    assert out.status is VehicleStatus.out_of_service
    assert out.reason == "new_damage"
    # Vehicle action and money action are decoupled — two queues, both human.
    assert set(out.queues) == {Q_FIX, Q_CS}


def test_rule_4_minor_new_damage_is_recorded_but_never_billed():
    out = _decide([_l1()], [_l2(_finding("新增", 1))])
    assert out.rule == 4
    assert out.status is VehicleStatus.rentable
    assert out.queues == []
    assert out.history_entries  # still goes on the car's record


def test_rule_4_does_not_short_circuit_the_conservative_rules():
    # A minor new scratch on one panel plus an undetermined finding on another
    # must still take the car off the road.
    out = _decide(
        [_l1()],
        [_l2(_finding("新增", 1)), _l2(_finding("無法判定", 2))],
    )
    assert out.rule == 5
    assert out.status is VehicleStatus.out_of_service
    assert out.reason == "undetermined"


def test_rule_6_hitting_the_retake_cap_never_traps_the_driver():
    out = _decide([_l1(assessable=False, quality_forced=True, retake_count=3)])
    assert out.rule == 6
    assert out.reason == "unassessable"
    assert out.status is VehicleStatus.out_of_service


def test_rule_7_a_failed_layer_means_the_car_was_never_checked():
    out = _decide([_l1(error="gemini timeout")])
    assert out.rule == 7
    assert out.reason == "system_error"
    assert out.status is VehicleStatus.out_of_service
    assert out.notify_user  # the driver is told the check is still running


def test_existing_damage_is_never_charged_to_this_trip():
    out = _decide([_l1()], [_l2(_finding("既有", 4))])
    assert out.rule == 8
    assert out.status is VehicleStatus.rentable
    assert out.history_entries[0]["verdict"] == "既有"


# ------------------------------------------------------------------ 留言板 ---
#
# The board is not a rule here — L2 already resolved every finding against it.
# What L3 owes it is carriage: 客服 opening a withheld claim has to land on the
# sentence that withheld it, not on a foreign key.


def _note(text: str = "後保險桿有一個洞") -> BoardNote:
    return BoardNote(
        note_id="n1",
        car_no="RDS-6583",
        created_at="2026-08-01T09:00:00+00:00",
        text=text,
        part="後保險桿中央",
        type="破裂",
    )


def test_a_finding_that_leaned_on_a_note_carries_it_into_車況履歷():
    finding = L2Finding(
        part="後保險桿中央",
        type="破裂",
        verdict="既有",
        severity=2,
        note_id="n1",
    )
    out = decide(
        order_id="o1",
        car_no="RDS-6583",
        l1=[_l1()],
        l2=[_l2(finding)],
        notes=[_note()],
    )

    # 既有 is not a reason to hold the car, so this is still a clean return.
    assert out.rule == 8
    assert out.status is VehicleStatus.rentable
    entry = out.history_entries[0]
    assert entry["note_id"] == "n1"
    assert entry["note_text"] == "後保險桿有一個洞"


def test_rule_5_says_when_there_is_a_note_to_read():
    finding = L2Finding(
        part="後保險桿中央",
        type="破裂",
        verdict="無法判定",
        severity=3,
        note_id="n1",
    )
    out = decide(
        order_id="o1",
        car_no="RDS-6583",
        l1=[_l1()],
        l2=[_l2(finding)],
        notes=[_note()],
    )

    assert out.rule == 5
    assert out.status is VehicleStatus.out_of_service
    assert "留言板" in out.explain


def test_an_unattributed_undetermined_finding_reads_as_it_always_did():
    out = decide(
        order_id="o1",
        car_no="RDS-6583",
        l1=[_l1()],
        l2=[_l2(_finding("無法判定"))],
    )
    assert out.rule == 5
    assert "留言板" not in out.explain
