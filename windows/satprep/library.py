from __future__ import annotations

import uuid
from dataclasses import dataclass, field

from .i18n import L

MANUAL = "manual"
NAME = "name"
NEWEST = "newest"
LARGEST = "largest"
LEAST_PRACTISED = "leastPractised"

ORDERS = (MANUAL, NAME, NEWEST, LARGEST, LEAST_PRACTISED)


def order_title(order: str) -> str:
    return {
        MANUAL: L("The order I put them in"),
        NAME: L("Name, A to Z"),
        NEWEST: L("Newest first"),
        LARGEST: L("Most questions first"),
        LEAST_PRACTISED: L("Least practiced first"),
    }.get(order, L("The order I put them in"))


@dataclass
class Shelf:

    name: str
    bank_ids: list = field(default_factory=list)
    collapsed: bool = False
    id: str = field(default_factory=lambda: str(uuid.uuid4()))

    def to_dict(self):
        return {"id": self.id, "name": self.name,
                "bankIDs": list(self.bank_ids), "collapsed": self.collapsed}

    @classmethod
    def from_dict(cls, raw):
        raw = raw or {}
        return cls(name=raw.get("name") or "Shelf",
                   bank_ids=list(raw.get("bankIDs") or []),
                   collapsed=bool(raw.get("collapsed", False)),
                   id=raw.get("id") or str(uuid.uuid4()))


@dataclass
class LibraryLayout:
    shelves: list = field(default_factory=list)
    unshelved: list = field(default_factory=list)
    order: str = MANUAL

    def to_dict(self):
        return {"shelves": [s.to_dict() for s in self.shelves],
                "unshelved": list(self.unshelved),
                "order": self.order}

    @classmethod
    def from_dict(cls, raw):
        raw = raw or {}
        order = raw.get("order")
        return cls(shelves=[Shelf.from_dict(s) for s in raw.get("shelves") or []],
                   unshelved=list(raw.get("unshelved") or []),
                   order=order if order in ORDERS else MANUAL)

    def reconcile(self, banks):
        known = {b.id for b in banks}
        placed = set()

        def keep(ids):
            out = []
            for bank_id in ids:
                if bank_id in known and bank_id not in placed:
                    placed.add(bank_id)
                    out.append(bank_id)
            return out

        for shelf in self.shelves:
            shelf.bank_ids = keep(shelf.bank_ids)
        self.unshelved = keep(self.unshelved)

        missing = [b.id for b in banks if b.id not in placed]
        self.unshelved = missing + self.unshelved

    def shelf_of(self, bank_id):
        for shelf in self.shelves:
            if bank_id in shelf.bank_ids:
                return shelf
        return None

    def remove(self, bank_id):
        for shelf in self.shelves:
            shelf.bank_ids = [b for b in shelf.bank_ids if b != bank_id]
        self.unshelved = [b for b in self.unshelved if b != bank_id]

    def move(self, bank_id, shelf_id=None, position=None):
        self.remove(bank_id)
        target = next((s for s in self.shelves if s.id == shelf_id), None) \
            if shelf_id else None
        into = target.bank_ids if target is not None else self.unshelved
        at = len(into) if position is None else min(max(0, position), len(into))
        into.insert(at, bank_id)

    def add_shelf(self, name):
        shelf = Shelf(name=name)
        self.shelves.append(shelf)
        return shelf

    def remove_shelf(self, shelf_id):
        shelf = next((s for s in self.shelves if s.id == shelf_id), None)
        if shelf is None:
            return
        self.unshelved.extend(shelf.bank_ids)
        self.shelves.remove(shelf)

    def move_shelf(self, shelf_id, delta):
        index = next((i for i, s in enumerate(self.shelves) if s.id == shelf_id),
                     None)
        if index is None:
            return
        target = min(max(0, index + delta), len(self.shelves) - 1)
        if target == index:
            return
        self.shelves.insert(target, self.shelves.pop(index))

    def fresh_shelf_name(self, base=None):
        base = base or L("New shelf")
        taken = {s.name.lower() for s in self.shelves}
        if base.lower() not in taken:
            return base
        for n in range(2, 100):
            candidate = "%s %d" % (base, n)
            if candidate.lower() not in taken:
                return candidate
        return base


def arrange(ids, order, banks, seen_counts):
    resolved = [banks[i] for i in ids if i in banks]
    if order == NAME:
        return sorted(resolved, key=lambda b: b.name.casefold())
    if order == NEWEST:
        return sorted(resolved, key=lambda b: b.created_at, reverse=True)
    if order == LARGEST:
        return sorted(resolved, key=lambda b: len(b.questions), reverse=True)
    if order == LEAST_PRACTISED:
        def fraction(bank):
            if not bank.questions:
                return 1.0
            return seen_counts.get(bank.id, 0) / len(bank.questions)

        return sorted(resolved, key=lambda b: (fraction(b), b.name.casefold()))
    return resolved
