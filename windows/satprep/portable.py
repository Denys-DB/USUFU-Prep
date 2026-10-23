from __future__ import annotations

import json
import os
import time
import uuid

from . import i18n
from .i18n import Lp
from .core import SETTINGS_KEYS

MAGIC = "usufu-sat-profile"
VERSION = 1
FILE_EXTENSION = "satprofile"


def fingerprint(question_ids):
    h = 0xcbf29ce484222325
    mask = 0xFFFFFFFFFFFFFFFF
    for qid in sorted(question_ids):
        for byte in qid.encode("utf-8"):
            h = ((h ^ byte) * 0x100000001b3) & mask
        h = ((h ^ 0x2f) * 0x100000001b3) & mask
    return "%016x" % h


def _iso(seconds):
    return float(seconds) if seconds else None


def _epoch(value):
    try:
        return float(value) if value else None
    except (TypeError, ValueError):
        return None


_SUBJECT_OUT = {"reading_writing": "readingWriting", "math": "math"}
_SUBJECT_IN = {v: k for k, v in _SUBJECT_OUT.items()}


def _record_out(qid, r):
    return {"questionID": qid,
            "timesSeen": int(r.get("times_seen", 0)),
            "timesCorrect": int(r.get("times_correct", 0)),
            "lastSeen": _iso(r.get("last_seen")),
            "lastCorrect": bool(r.get("last_correct", False))}


def _record_in(d):
    return {"times_seen": int(d.get("timesSeen", 0)),
            "times_correct": int(d.get("timesCorrect", 0)),
            "last_seen": _epoch(d.get("lastSeen")),
            "last_correct": bool(d.get("lastCorrect", False))}


def _history_out(row):
    return {"id": row.get("id") or str(uuid.uuid4()),
            "questionID": row.get("question_id", ""),
            "correct": bool(row.get("correct", False)),
            "at": _iso(row.get("at")) or _iso(time.time()),
            "secondsSpent": float(row.get("seconds", 0.0)),
            "skill": row.get("skill", ""),
            "domain": row.get("domain", ""),
            "difficulty": row.get("difficulty", ""),
            "subject": _SUBJECT_OUT.get(row.get("subject", "math"), "math"),
            "backfilled": bool(row.get("backfilled", False))}


def _history_in(d):
    return {"question_id": d.get("questionID", ""),
            "correct": bool(d.get("correct", False)),
            "at": _epoch(d.get("at")) or time.time(),
            "seconds": float(d.get("secondsSpent", 0.0)),
            "skill": d.get("skill", ""),
            "domain": d.get("domain", ""),
            "difficulty": d.get("difficulty", ""),
            "subject": _SUBJECT_IN.get(d.get("subject", "math"), "math"),
            "backfilled": bool(d.get("backfilled", False))}


def portable_id(value):
    try:
        return str(uuid.UUID(str(value)))
    except (ValueError, TypeError, AttributeError):
        return str(uuid.uuid4())


def same_id(value):
    try:
        return uuid.UUID(str(value)).hex
    except (ValueError, TypeError, AttributeError):
        return str(value)


_PLAN_KEYS = {"bank_id": "bankID", "count": "questionCount", "sitting_name": "sittingName",
              "full_test": "fullTest", "skill_filter": "skillFilter"}
_PLAN_VALUES = {
    "grading": {"at_end": "atEnd"},
    "mix": {"pdf_order": "pdfOrder", "shuffled_in_section": "shuffledInSection"},
    "selection": {"new_first": "newFirst", "unseen_only": "unseenOnly",
                  "due_for_review": "dueForReview", "weakest_skills": "weakestSkills",
                  "review_missed": "reviewMissed", "set_aside": "setAside"},
    "subjects": {"reading_writing": "readingWriting"},
}


def _config_out(config):
    out = {}
    for key, value in (config or {}).items():
        values = _PLAN_VALUES.get(key, {})
        if isinstance(value, list):
            value = [values.get(v, v) for v in value]
        elif isinstance(value, str):
            value = values.get(value, value)
        out[_PLAN_KEYS.get(key, key)] = value
    return out


def _config_in(config):
    keys = {v: k for k, v in _PLAN_KEYS.items()}
    out = {}
    for key, value in (config or {}).items():
        key = keys.get(key, key)
        values = {v: k for k, v in _PLAN_VALUES.get(key, {}).items()}
        if isinstance(value, list):
            value = [values.get(v, v) for v in value]
        elif isinstance(value, str):
            value = values.get(value, value)
        out[key] = value
    return out


def _plan_out(p):
    return {"id": portable_id(p.get("id")), "name": p.get("name", ""),
            "config": _config_out(p.get("config")),
            "createdAt": float(p.get("created_at") or time.time())}


def _plan_in(d):
    return {"id": d.get("id") or uuid.uuid4().hex, "name": d.get("name", ""),
            "config": _config_in(d.get("config")),
            "created_at": float(d.get("createdAt") or d.get("created_at") or time.time())}


def _note_out(a):
    out = {"id": portable_id(a.get("id") or uuid.uuid4().hex),
           "questionID": a.get("question_id", ""),
           "field": a.get("field", "stimulus"),
           "blockIndex": int(a.get("block", 0)),
           "start": int(a.get("start", 0)),
           "end": int(a.get("end", 0)),
           "note": a.get("note", ""),
           "colorIndex": int(a.get("color", 0))}
    if a.get("marked"):
        out["marked"] = a["marked"]
    return out


def _note_in(d):
    out = {"id": d.get("id", uuid.uuid4().hex),
           "question_id": d.get("questionID", ""),
           "field": d.get("field", "stimulus"),
           "block": int(d.get("blockIndex", 0)),
           "start": int(d.get("start", 0)),
           "end": int(d.get("end", 0)),
           "note": d.get("note", ""),
           "color": int(d.get("colorIndex", 0))}
    if isinstance(d.get("marked"), str) and d["marked"]:
        out["marked"] = d["marked"]
    return out


def export_profile(store):
    banks = []
    for bank in store.banks:
        ids = [q.id for q in bank.questions]
        records = store.progress.get(bank.id, {})
        banks.append({
            "name": bank.name,
            "questionCount": len(ids),
            "fingerprint": fingerprint(ids),
            "questionIDs": ids,
            "records": {qid: _record_out(qid, r) for qid, r in records.items()},
            "setAside": sorted(qid for qid, r in records.items() if r.get("set_aside")),
            "history": [_history_out(r) for r in store.history.get(bank.id, [])],
            "notes": [_note_out(a) for a in store.notes.get(bank.id, [])],
        })

    return {
        "format": MAGIC,
        "version": VERSION,
        "exportedAt": _iso(time.time()),
        "profileName": store.profile.get("name", ""),
        "accent": int(store.profile.get("accent", 0)),
        "banks": banks,
        "decks": [d.to_dict() for d in store.decks.decks],
        "plans": [_plan_out(p) for p in store.presets],
        "settings": {k: v for k, v in store.settings.items() if k in SETTINGS_KEYS},
    }


def write_profile(store, path):
    from . import safeio
    data = export_profile(store)
    safeio.write_json(path, data, indent=2, sort_keys=True)
    store.record_backup()
    return os.path.getsize(path)


def read_profile(path):
    try:
        with open(path, encoding="utf-8") as f:
            data = json.load(f)
    except Exception:
        return None
    if not isinstance(data, dict) or data.get("format") != MAGIC:
        return None
    return data


def plan_for(data, banks):
    local = [(b, set(q.id for q in b.questions)) for b in banks]
    claimed = set()
    matches = []

    for block in data.get("banks", []):
        exported = set(block.get("questionIDs", []))
        chosen = None

        for bank, ids in local:
            if bank.id in claimed:
                continue
            if fingerprint(ids) == block.get("fingerprint"):
                chosen = (bank, len(ids & exported), "fingerprint")
                break
        if chosen is None:
            for bank, ids in local:
                if bank.id in claimed:
                    continue
                if bank.name == block.get("name"):
                    chosen = (bank, len(ids & exported), "name")
                    break
        if chosen is None:
            best, best_n = None, 0
            for bank, ids in local:
                if bank.id in claimed:
                    continue
                n = len(ids & exported)
                if n > best_n:
                    best, best_n = bank, n
            if best is not None and best_n * 4 >= max(1, len(exported)):
                chosen = (best, best_n, "overlap")

        if chosen:
            claimed.add(chosen[0].id)
        matches.append({
            "exportedName": block.get("name", ""),
            "exportedCount": int(block.get("questionCount", 0)),
            "localBankID": chosen[0].id if chosen else None,
            "localName": chosen[0].name if chosen else None,
            "overlap": chosen[1] if chosen else 0,
            "records": len(block.get("records", {})),
            "notes": len(block.get("notes", [])),
            "how": chosen[2] if chosen else "none",
        })
    return {"profileName": data.get("profileName", ""),
            "exportedAt": data.get("exportedAt"),
            "matches": matches,
            "deckCount": len(data.get("decks", [])),
            "planCount": len(data.get("plans", []))}


def better(a, b):
    if a.get("times_seen", 0) != b.get("times_seen", 0):
        return a if a.get("times_seen", 0) > b.get("times_seen", 0) else b
    if a.get("times_correct", 0) != b.get("times_correct", 0):
        return a if a.get("times_correct", 0) > b.get("times_correct", 0) else b
    return a if (a.get("last_seen") or 0) >= (b.get("last_seen") or 0) else b


def merge_bank(store, bank, block):
    known = set(q.id for q in bank.questions)
    records = store.progress.setdefault(bank.id, {})
    before = len(records)

    for qid, incoming in block.get("records", {}).items():
        if qid not in known:
            continue
        row = _record_in(incoming)
        if qid in records:
            merged = better(records[qid], row)
            merged = dict(merged)
            merged["set_aside"] = records[qid].get("set_aside", False)
            records[qid] = merged
        else:
            records[qid] = row

    for qid in block.get("setAside", []):
        if qid in known:
            records.setdefault(qid, {"times_seen": 0, "times_correct": 0,
                                     "last_correct": False})["set_aside"] = True

    rows = store.history.setdefault(bank.id, [])
    seen = {(r.get("question_id"), round(float(r.get("at", 0)), 3)) for r in rows}
    for d in block.get("history", []):
        row = _history_in(d)
        if row["question_id"] not in known:
            continue
        key = (row["question_id"], round(row["at"], 3))
        if key in seen:
            continue
        seen.add(key)
        rows.append(row)
    rows.sort(key=lambda r: r.get("at", 0))

    notes = store.notes.setdefault(bank.id, [])
    have = {same_id(a.get("id")) for a in notes}
    added_notes = 0
    for d in block.get("notes", []):
        note = _note_in(d)
        if note["question_id"] not in known or same_id(note["id"]) in have:
            continue
        have.add(same_id(note["id"]))
        notes.append(note)
        added_notes += 1

    store.save_progress(bank.id)
    store.save_history(bank.id)
    store.save_notes(bank.id)
    return {"records": max(0, len(records) - before), "notes": added_notes}


def summary(report):
    lines = []
    if report["sets"]:
        lines.append(" · ".join((
            Lp(report["sets"], "%d question set updated", "%d question sets updated"),
            Lp(report["records"], "%d question record", "%d question records"),
            Lp(report["notes"], "%d highlight", "%d highlights"))))
    if report["decks"]:
        lines.append(Lp(report["decks"], "%d deck", "%d decks"))
    if report["plans"]:
        lines.append(Lp(report["plans"], "%d study plan", "%d study plans"))
    if report["waiting"]:
        lines.append(Lp(report["waiting"],
                        "%d set is waiting for its question PDF.",
                        "%d sets are waiting for their question PDFs."))
    return lines


def import_profile(store, data, plan, mode="merge"):
    report = {"sets": 0, "records": 0, "notes": 0, "decks": 0, "plans": 0,
              "waiting": 0, "settings": False}

    if mode == "new":
        name = data.get("profileName") or store.profiles.unused_name()
        made = store.add_profile(name)
        store.profiles.set_accent(made["id"], int(data.get("accent", 0)))
        store.use_profile(made)
        if isinstance(data.get("settings"), dict):
            store.settings.update({k: v for k, v in data["settings"].items()
                                   if k in SETTINGS_KEYS})
            store.save_settings()
            i18n.use(store.settings.get("language") or "en")
            report["settings"] = True

    by_name = {b.get("name", ""): b for b in data.get("banks", [])}
    for match in plan["matches"]:
        block = by_name.get(match["exportedName"])
        if block is None:
            continue
        bank = store.bank(match["localBankID"]) if match["localBankID"] else None
        if bank is None:
            store.pending = [b for b in store.pending
                             if not (b.get("name") == block.get("name")
                                     and b.get("fingerprint") == block.get("fingerprint"))]
            store.pending.append(block)
            report["waiting"] += 1
            continue
        counts = merge_bank(store, bank, block)
        report["sets"] += 1
        report["records"] += counts["records"]
        report["notes"] += counts["notes"]

    report["decks"] = _merge_decks(store, data.get("decks", []))
    report["plans"] = _merge_plans(store, [_plan_in(d) for d in data.get("plans", [])
                                           if isinstance(d, dict)])
    save_pending(store)
    return report


def _merge_decks(store, incoming):
    from . import vocab
    touched = 0
    for d in incoming:
        deck = vocab.Deck.from_dict(d)
        mine = store.decks.deck(deck.id)
        if mine:
            have = {vocab.key(c.term) for c in mine.cards}
            new = [c for c in deck.cards if vocab.key(c.term) not in have]
            if not new:
                continue
            mine.cards.extend(new)
            store.decks.save(mine)
        else:
            store.decks.save(deck)
        touched += 1
    if touched:
        store.decks.load()
    return touched


def _merge_plans(store, incoming):
    have = {p.get("name") for p in store.presets}
    new = [p for p in incoming if p.get("name") not in have]
    if not new:
        return 0
    store.presets.extend(new)
    store.save_presets()
    return len(new)


def pending_path(store):
    return os.path.join(store.profile_root, "Pending.json")


def load_pending(store):
    from . import safeio
    store.pending = safeio.read_json(pending_path(store), [],
                                     getattr(store, "note_damaged", None), expect=list)


def save_pending(store):
    path = pending_path(store)
    if not store.pending:
        if os.path.exists(path):
            os.remove(path)
        return
    from . import safeio
    safeio.write_json(path, store.pending, indent=2, sort_keys=True)


def apply_pending(store):
    if not store.pending:
        return 0
    seen, unique = set(), []
    for b in store.pending:
        k = (b.get("name"), b.get("fingerprint"))
        if k not in seen:
            seen.add(k)
            unique.append(b)
    store.pending = unique
    plan = plan_for({"banks": store.pending}, store.banks)
    by_name = {b.get("name", ""): b for b in store.pending}
    landed, waiting = 0, []
    for match in plan["matches"]:
        block = by_name.get(match["exportedName"])
        if block is None:
            continue
        bank = store.bank(match["localBankID"]) if match["localBankID"] else None
        if bank is None:
            waiting.append(block)
            continue
        merge_bank(store, bank, block)
        landed += 1
    store.pending = waiting
    save_pending(store)
    return landed
