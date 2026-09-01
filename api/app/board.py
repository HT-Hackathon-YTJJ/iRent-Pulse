"""留言板 — the car's own history, written by the people who drove it.

Why a layer that is otherwise all vision has a text input in it
---------------------------------------------------------------

L2 answers one question: **是這趟造成的嗎？** Until now it could only answer it
from pixels — the same angle photographed at pickup and again at return, with a
set difference between the two. That works, and it is the strongest evidence
there is, but it fails in exactly the case that costs a customer money:

    上一位使用者還車時車尾已經有一個凹洞。取車照沒拍到那個角度（或那趟根本
    沒拍取車照）。下一位使用者拍到了洞，L2 找不到基準線，只能說「無法判定」，
    L3 依規則 5 把車停用並送客服 — 而客服看到的是一張有洞的照片和一個沒有
    任何說明的訂單。

The hole was already documented. Somebody typed it into the board when they
handed the car back. That sentence is the missing evidence, and it is free.

So a note is treated as **testimony**: weaker than a photograph, never allowed
to overrule one, and conclusive only when there is no photograph to weigh it
against. The precedence L2 applies is, in order:

1. the pickup photo of the same angle (evidence),
2. a note written before this rental started (testimony),
3. 無法判定 (a human looks).

A note can only ever move a finding *towards* 既有 — towards not charging this
driver. It can never create a 新增, because "somebody said so" is not a standard
anybody should be billed against.

Free text, and what to do about it
----------------------------------

The board is free text: 「後保險桿有一個洞」, not a form. Matching it against a
finding means turning that sentence into the same `(部位, 類型)` pair the vision
layers speak, so this module does the only kind of matching that is defensible
at this size — literal substrings of the closed vocabularies in `models.py`,
plus a small table of the words people actually type for each damage class.

That is deliberately dumb, and it is dumb in the safe direction: a note it
fails to parse simply does not help the driver, exactly as if it had never been
written. Nothing about a mis-parse can charge somebody. When there is a real
board behind this, the parse stops being a guess — the UI tags the part as the
note is written, so `part` and `type` arrive already filled in and this function
is only ever the fallback for the free-text field beside them.
"""

from __future__ import annotations

from typing import Dict, List, Optional, Set, Tuple

from .models import BoardNote

#: What people type, and which of the five damage classes it means. Matched
#: longest-first, so 「板件間隙」 is not shadowed by 「縫隙」.
_TYPE_SYNONYMS: Dict[str, str] = {
    "刮痕": "刮痕",
    "刮傷": "刮痕",
    "刮到": "刮痕",
    "擦傷": "刮痕",
    "擦撞": "刮痕",
    "掉漆": "刮痕",
    "凹陷": "凹陷",
    "凹痕": "凹陷",
    "凹了": "凹陷",
    "撞凹": "凹陷",
    "一個洞": "破裂",
    "破洞": "破裂",
    "破裂": "破裂",
    "裂痕": "破裂",
    "龜裂": "破裂",
    "破損": "破裂",
    "缺件": "缺件",
    "掉了": "缺件",
    "脫落": "缺件",
    "不見": "缺件",
    "板件間隙": "板件間隙",
    "縫隙": "板件間隙",
}

#: Loose part words mapped onto the closed part list, used only when no exact
#: part name appears in the text. Where a word does not say which side —
#: 「保險桿」, 「後視鏡」 — it resolves to the centre or to one side, and the
#: matcher below also accepts any part sharing that panel, so a note that is
#: vague about the side still covers the finding.
_PART_HINTS: Dict[str, str] = {
    "前保險桿": "前保險桿中央",
    "後保險桿": "後保險桿中央",
    "保險桿": "前保險桿中央",
    "引擎蓋": "引擎蓋",
    "行李廂": "行李廂蓋",
    "後車廂": "行李廂蓋",
    "車頂": "車頂",
    "後照鏡": "左後視鏡",
    "後視鏡": "左後視鏡",
    "前擋": "前擋風玻璃",
    "後擋": "後擋風玻璃",
    "大燈": "左前大燈",
    "尾燈": "左後燈",
    "輪圈": "左前輪圈",
    "鋼圈": "左前輪圈",
    "車門": "左前車門",
    "葉子板": "左前葉子板",
    "裙板": "左側裙板",
}

#: Severity a note is allowed to assert on its own. A note is testimony, so it
#: never reaches the ≥3 that pulls a car off the road — that stays a decision
#: made from photographs by L2 and L3.
NOTE_SEVERITY = 2


def parse(text: str) -> Tuple[Optional[str], Optional[str]]:
    """Best-effort `(部位, 類型)` for one free-text note.

    Returns ``(None, None)`` for anything that does not clearly name both, which
    is most notes — 「車子很乾淨，謝謝」 is not evidence of anything and must not
    become a finding.
    """
    if not text:
        return None, None
    return _match_part(text), _match_type(text)


def _match_part(text: str) -> Optional[str]:
    from .models import PART_NAMES

    # Exact vocabulary first: those are the strings L1 and L2 emit, so a note
    # written through a tagging UI matches without going near the guesswork.
    for name in sorted(PART_NAMES, key=len, reverse=True):
        if name in text:
            return name
    for word in sorted(_PART_HINTS, key=len, reverse=True):
        if word in text:
            return _PART_HINTS[word]
    return None


def _match_type(text: str) -> Optional[str]:
    for word in sorted(_TYPE_SYNONYMS, key=len, reverse=True):
        if word in text:
            return _TYPE_SYNONYMS[word]
    return None


def resolve(note: BoardNote) -> BoardNote:
    """Fill in `part`/`type` from the note's text when the writer did not tag it."""
    if note.part and note.type:
        return note
    part, dtype = parse(note.text)
    return note.model_copy(
        update={
            "part": note.part or part,
            "type": note.type or dtype,
            "severity": note.severity or (NOTE_SEVERITY if dtype else 0),
        }
    )


class PriorDamage:
    """What the board says was already wrong with this car before this trip.

    Two indexes, because a note can be more or less specific than the finding it
    has to answer:

    * [pairs] — the note named both a part and a damage type. Matching a finding
      on both is the strong case, and the one that is allowed to settle 既有 on
      its own.
    * [parts] — the note named a panel. A finding on that panel is *related* to
      something already recorded, which is enough to hold a claim back for a
      human to read the note, but not enough to close the question.
    """

    def __init__(self, notes: List[BoardNote]) -> None:
        self.notes = [resolve(n) for n in notes]
        self.pairs: Dict[Tuple[str, str], BoardNote] = {}
        self.parts: Dict[str, BoardNote] = {}
        for note in self.notes:
            if not note.part:
                continue
            self.parts.setdefault(note.part, note)
            if note.type:
                self.pairs.setdefault((note.part, note.type), note)

    def __bool__(self) -> bool:
        return bool(self.pairs or self.parts)

    #: Panels that are really the same place under two names, so a note about
    #: 「後保險桿」 covers a finding on 後保險桿左側.
    @staticmethod
    def _panel(part: str) -> str:
        for stem in ("前保險桿", "後保險桿", "後視鏡", "輪圈", "車門", "葉子板", "裙板"):
            if part.startswith(stem) or part.endswith(stem):
                return stem
        return part

    def exact(self, part: str, dtype: str) -> Optional[BoardNote]:
        """A note naming this damage, on this part or anywhere on its panel."""
        found = self.pairs.get((part, dtype))
        if found is not None:
            return found
        panel = self._panel(part)
        for (noted_part, noted_type), note in self.pairs.items():
            if noted_type == dtype and self._panel(noted_part) == panel:
                return note
        return None

    def panel(self, part: str) -> Optional[BoardNote]:
        """A note about this panel, whatever kind of damage it described."""
        found = self.parts.get(part)
        if found is not None:
            return found
        panel = self._panel(part)
        for noted_part, note in self.parts.items():
            if self._panel(noted_part) == panel:
                return note
        return None

    def cited(self) -> Set[str]:
        return {n.note_id for n in self.notes if n.note_id}


def quote(note: BoardNote) -> str:
    """One line of a note, short enough to sit inside a `reason` string."""
    text = note.text.strip().replace("\n", " ")
    if len(text) > 40:
        text = text[:39] + "…"
    when = note.created_at[:10] if note.created_at else "先前"
    who = {"user": "使用者", "staff": "門市", "system": "系統"}.get(
        note.author, note.author
    )
    return f"{when} {who}留言「{text}」"
