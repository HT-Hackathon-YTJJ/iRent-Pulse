"""留言板 — parsing free text, and what L2 is allowed to do with it.

The rule the whole feature hangs on is one-directional: a note may move a
finding towards 既有, never towards 新增. Everything here is a way of checking
that a sentence somebody typed cannot be turned into a charge.
"""

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from app import board  # noqa: E402
from app.l2 import _diff  # noqa: E402
from app.models import BoardNote  # noqa: E402


def _note(text: str, **kw) -> BoardNote:
    base = dict(note_id="n1", car_no="RDS-6583", created_at="2026-08-01T09:00:00+00:00")
    base.update(kw)
    return board.resolve(BoardNote(text=text, **base))


def _damage(part: str, dtype: str, severity: int = 2, desc: str = "") -> dict:
    return {
        "part": part,
        "type": dtype,
        "severity": severity,
        "desc": desc or dtype,
        "confidence": 0.8,
    }


def _ret(*damages: dict) -> dict:
    return {"assessable": True, "visible_parts": [], "damages": list(damages)}


def _base(*damages: dict, visible=(), assessable=True) -> dict:
    return {
        "assessable": assessable,
        "visible_parts": list(visible),
        "damages": list(damages),
    }


# ------------------------------------------------------------------ parsing --


def test_a_plain_sentence_names_the_part_and_the_damage():
    part, dtype = board.parse("後保險桿有一個洞，還車時已回報")
    assert part == "後保險桿中央"
    assert dtype == "破裂"


def test_the_apps_own_board_entry_parses():
    # The exact string in lib/data/vehicle.dart, which ReturnSession uploads
    # when a live return opens. If the copy is reworded, this is what notices.
    part, dtype = board.parse("取車時後保險桿右側就有一個洞，已拍照回報")
    assert part == "後保險桿右側"
    assert dtype == "破裂"


def test_the_rest_of_the_apps_board_is_inert():
    for text in [
        "空間真的很大，搬家超方便，下次還會再租",
        "一上車就有濃濃的煙味，座椅上感覺還有煙灰",
        "車內很乾淨也沒有異味，還車拍照還會送點數，太好了",
        "油電很省油，開一整天只加了半桶",
    ]:
        assert board.parse(text) == (None, None), text


def test_an_exact_part_name_wins_over_the_loose_hint():
    part, _ = board.parse("後保險桿右側有刮痕")
    assert part == "後保險桿右側"


def test_a_note_about_nothing_in_particular_parses_to_nothing():
    # 「車子很乾淨，謝謝」 is not evidence, and turning it into a finding would be
    # worse than ignoring it.
    assert board.parse("車子很乾淨，謝謝") == (None, None)
    assert board.parse("") == (None, None)


def test_an_unparseable_note_is_inert_rather_than_wrong():
    note = _note("開起來很順，冷氣有點小聲")
    assert note.part is None
    assert note.severity == 0
    assert not board.PriorDamage([note])


def test_a_tagged_note_is_left_alone():
    # A UI that lets the driver pick the panel sends part/type itself; the
    # parser is only ever the fallback for the free-text box beside it.
    note = _note("撞到柱子", part="左前車門", type="凹陷")
    assert (note.part, note.type) == ("左前車門", "凹陷")


def test_a_note_covers_the_whole_panel_it_names():
    prior = board.PriorDamage([_note("後保險桿有一個洞")])
    assert prior.exact("後保險桿右側", "破裂") is not None
    assert prior.exact("後保險桿左側", "破裂") is not None
    assert prior.exact("引擎蓋", "破裂") is None


# -------------------------------------------------- L2, with no pickup photo --


def test_without_a_baseline_a_matching_note_settles_it_as_既有():
    # The case the board exists for. Before it, this was 無法判定 → rule 5 → the
    # car off the road and the driver waiting on 客服 for a hole the previous
    # driver had already written down.
    prior = board.PriorDamage([_note("後保險桿有一個洞")])
    findings = _diff(_ret(_damage("後保險桿中央", "破裂")), None, prior)

    assert [f.verdict for f in findings] == ["既有"]
    assert findings[0].note_id == "n1"
    assert "留言" in findings[0].reason


def test_without_a_baseline_and_without_a_note_it_stays_無法判定():
    findings = _diff(_ret(_damage("後保險桿中央", "破裂")), None, board.PriorDamage([]))
    assert [f.verdict for f in findings] == ["無法判定"]
    assert findings[0].note_id is None


def test_a_note_about_the_same_panel_but_a_different_damage_asks_a_human():
    # 「後保險桿有刮痕」 does not account for a hole. Not this driver's fault is
    # not established, but it is close enough that a person should read it.
    prior = board.PriorDamage([_note("後保險桿有刮痕")])
    findings = _diff(_ret(_damage("後保險桿中央", "破裂")), None, prior)

    assert findings[0].verdict == "無法判定"
    assert findings[0].note_id == "n1"


# ------------------------------------------------------ L2, with the photo ---


def test_the_pickup_photo_outranks_an_unconfirmed_note():
    # A photograph of a clean panel beats somebody's recollection. This is the
    # direction the rule must hold in, or a note becomes a way to launder
    # damage onto the previous driver.
    prior = board.PriorDamage([_note("左前車門有凹陷")])
    findings = _diff(
        _ret(_damage("左前車門", "凹陷")),
        _base(visible=["左前車門"]),
        prior,
    )
    assert findings[0].verdict == "新增"
    assert findings[0].note_id is None


def test_a_confirmed_note_contradicting_the_photo_goes_to_a_human():
    # Two records disagree and one of them was checked by staff. The driver
    # standing in front of us is not the right person to lose that argument.
    prior = board.PriorDamage([_note("左前車門有凹陷", confirmed=True)])
    findings = _diff(
        _ret(_damage("左前車門", "凹陷")),
        _base(visible=["左前車門"]),
        prior,
    )
    assert findings[0].verdict == "無法判定"
    assert findings[0].note_id == "n1"


def test_a_note_cannot_invent_a_finding():
    # Nothing in the return photo, plenty on the board. No findings.
    prior = board.PriorDamage([_note("後保險桿有一個洞")])
    assert _diff(_ret(), None, prior) == []


def test_a_part_the_pickup_photo_missed_is_settled_by_a_note():
    prior = board.PriorDamage([_note("右後葉子板有刮痕")])
    findings = _diff(
        _ret(_damage("右後葉子板", "刮痕")),
        _base(visible=["左前車門"]),
        prior,
    )
    assert findings[0].verdict == "既有"
    assert findings[0].note_id == "n1"
