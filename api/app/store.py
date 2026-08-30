"""In-memory order state plus on-disk photos.

A real deployment puts this in Postgres + object storage. What matters for the
layer design is only that L2 can find **this trip's pickup photo for the same
角度**, and that 客服 can pull both frames back up later — so the shape here is
the shape the queries need, not a demo shortcut that would have to be redesigned.
"""

import threading
import uuid
from dataclasses import dataclass, field
from typing import Dict, List, Optional

from . import config
from .models import L1Result, L2Result, L3Decision


@dataclass
class Photo:
    photo_id: str
    order_id: str
    car_no: str
    stage: str
    slot: str
    path: str
    content_type: str = "image/jpeg"


@dataclass
class Order:
    order_id: str
    car_no: str
    photos: Dict[str, Photo] = field(default_factory=dict)
    l1: Dict[str, L1Result] = field(default_factory=dict)
    l2: Dict[str, L2Result] = field(default_factory=dict)
    decision: Optional[L3Decision] = None
    #: slot -> how many times this trip has already asked for a retake.
    retakes: Dict[str, int] = field(default_factory=dict)


class Store:
    def __init__(self) -> None:
        self._lock = threading.Lock()
        self._orders: Dict[str, Order] = {}
        #: car_no -> the most recent pickup L1 per slot, i.e. the baseline L2
        #: compares against. Keyed by car rather than order because the pickup
        #: and the return are the same trip but arrive as separate requests.
        self._baseline: Dict[str, Dict[str, str]] = {}

    def order(self, order_id: str, car_no: str) -> Order:
        with self._lock:
            found = self._orders.get(order_id)
            if found is None:
                found = Order(order_id=order_id, car_no=car_no)
                self._orders[order_id] = found
            return found

    def get_order(self, order_id: str) -> Optional[Order]:
        return self._orders.get(order_id)

    def orders(self) -> List[Order]:
        return list(self._orders.values())

    def save_photo(
        self, *, order_id: str, car_no: str, stage: str, slot: str, data: bytes
    ) -> Photo:
        photo_id = "p_" + uuid.uuid4().hex[:12]
        path = config.PHOTO_DIR / f"{photo_id}.jpg"
        path.write_bytes(data)
        photo = Photo(
            photo_id=photo_id,
            order_id=order_id,
            car_no=car_no,
            stage=stage,
            slot=slot,
            path=str(path),
        )
        order = self.order(order_id, car_no)
        with self._lock:
            order.photos[photo_id] = photo
            if stage == "pickup":
                self._baseline.setdefault(car_no, {})[slot] = photo_id
        return photo

    def photo(self, photo_id: str) -> Optional[Photo]:
        for order in self._orders.values():
            found = order.photos.get(photo_id)
            if found is not None:
                return found
        return None

    def baseline_photo(self, car_no: str, slot: str) -> Optional[Photo]:
        photo_id = self._baseline.get(car_no, {}).get(slot)
        return self.photo(photo_id) if photo_id else None

    def record_l1(self, result: L1Result) -> None:
        order = self.order(result.order_id, result.car_no)
        with self._lock:
            order.l1[result.photo_id] = result

    def record_l2(self, order_id: str, result: L2Result) -> None:
        order = self._orders.get(order_id)
        if order is not None:
            with self._lock:
                order.l2[result.photo_id] = result

    def bump_retake(self, order_id: str, slot: str) -> int:
        order = self._orders.get(order_id)
        if order is None:
            return 0
        with self._lock:
            order.retakes[slot] = order.retakes.get(slot, 0) + 1
            return order.retakes[slot]

    def retake_count(self, order_id: str, slot: str) -> int:
        order = self._orders.get(order_id)
        return order.retakes.get(slot, 0) if order else 0


STORE = Store()
