"""The board's storage, and the one cut-off that keeps it honest."""

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from app.models import BoardNote  # noqa: E402
from app.store import Store  # noqa: E402


def _note(store: Store, text: str, created_at: str) -> BoardNote:
    return store.add_note(
        BoardNote(car_no="RDS-6583", text=text, created_at=created_at)
    )


def test_a_note_gets_an_id_and_a_timestamp():
    store = Store()
    note = store.add_note(BoardNote(car_no="RDS-6583", text="後保險桿有一個洞"))
    assert note.note_id.startswith("n_")
    assert note.created_at


def test_the_board_is_per_car():
    store = Store()
    store.add_note(BoardNote(car_no="RDS-6583", text="a"))
    store.add_note(BoardNote(car_no="OTHER-1", text="b"))
    assert [n.text for n in store.notes("RDS-6583")] == ["a"]


def test_only_notes_older_than_the_trip_count_as_prior():
    # The note this driver is about to write describes what *they* left behind.
    # Letting it answer questions about their own trip would close the loop on
    # itself — so L2 is only ever handed what the board said beforehand.
    store = Store()
    _note(store, "上一趟：後保險桿有一個洞", "2026-08-01T09:00:00+00:00")
    _note(store, "這一趟：我也看到那個洞", "2026-08-20T18:00:00+00:00")

    started = "2026-08-20T17:00:00+00:00"
    prior = store.notes("RDS-6583", before=started)
    assert [n.text for n in prior] == ["上一趟：後保險桿有一個洞"]
    assert len(store.notes("RDS-6583")) == 2


def test_an_order_records_when_it_started():
    store = Store()
    order = store.order("o1", "RDS-6583")
    assert order.started_at
    assert store.order("o1", "RDS-6583").started_at == order.started_at
