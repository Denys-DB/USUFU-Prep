from __future__ import annotations

import base64
import datetime
import json
import math
import os
import random
import re
import shutil
import stat
import sys
import time
import uuid
from dataclasses import dataclass, field, asdict, fields
from fractions import Fraction

import pymupdf as fitz

from . import fulltest
from . import library
from . import pdfparse
from . import safeio
from . import vocab
from .vocab import DeckStore, safe_file_stem
from . import i18n
from .i18n import L, Lf, Lp

def remove_tree(path):
    def clear(func, target, _error):
        try:
            os.chmod(target, stat.S_IWRITE | stat.S_IREAD)
            func(target)
        except OSError:
            pass
    if sys.version_info >= (3, 12):
        shutil.rmtree(path, onexc=clear)
    else:
        shutil.rmtree(path, onerror=clear)


def data_root() -> str:
    appdata = os.environ.get("APPDATA")
    if appdata:
        return os.path.join(appdata, "SAT Prep")
    xdg = os.environ.get("XDG_DATA_HOME")
    if xdg:
        return os.path.join(xdg, "SAT Prep")
    return os.path.join(os.path.expanduser("~"), ".satprep")


PERSONAL_FOLDERS = ("Progress", "Sessions", "Notes", "Decks", "History")  # data, not copy: folder names
PERSONAL_FILES = ("Plans.json", "Settings.json", "Library.json")

SETTINGS_KEYS = frozenset((
    "dailyGoal", "appearance", "language", "reduceMotion", "schedule",
    "flashcardSeconds", "flashcardTextScale", "flashcardFlipAnimation",
    "trackSkippedCards", "vocabDaily", "showLearnInSidebar", "showImportButton",
    "showQuestionStreak", "showVocabularyStreak", "showDoubleMode", "showBackupCard",
    "showParentSummary", "stealthMode", "excusedDays", "welcomeBackFor",
    "restoreOfferedFor", "lastBackupAt", "backupNudgeFor", "showQuestionSets",
    "showFlashcards", "libraryPaneHeight",
    "daily_goal", "flashcard_seconds", "flashcard_scale", "flashcard_flip_animation",
    "track_skipped_cards", "lastPartnerProfileID", "libraryLayout",
    "practiceTimed", "practiceMinutes",
))
PROFILE_ACCENTS = 6


def _suggested_name():
    import getpass
    try:
        login = getpass.getuser() or ""
    except Exception:
        return L("Student")
    first = re.split(r"[._\- ]", login)[0]
    return first.capitalize() if first else L("Student")


class ProfileStore:

    def __init__(self, shared_root, default_name=None):
        self.shared_root = shared_root
        self.profiles = []
        self.last_used_id = None
        self.swept_legacy = False
        self.recovered_from = None
        self._load()
        if not self.profiles:
            self.profiles = [self._migrate_single_student(default_name or L("Student"))]
            self.last_used_id = self.profiles[0]["id"]
            self.save()
        else:
            self.heal_duplicates()
            self.sweep_legacy_folders()

    @property
    def book_path(self):
        return os.path.join(self.shared_root, "Profiles.json")

    @property
    def profiles_dir(self):
        return os.path.join(self.shared_root, "Profiles")

    def directory(self, profile_id):
        return os.path.join(self.profiles_dir, profile_id)

    def _load(self):
        if not os.path.exists(self.book_path):
            self.profiles, self.last_used_id = [], None
            return
        try:
            with open(self.book_path, encoding="utf-8") as f:
                d = json.load(f)
            self.profiles = [self._clean(p) for p in d.get("profiles", [])]
            self.last_used_id = d.get("lastUsedID")
            self.swept_legacy = bool(d.get("sweptLegacy", False))
            return
        except Exception:
            pass
        try:
            with open(self.book_path, "rb") as f:
                raw = f.read().decode("utf-8", "replace")
        except OSError:
            raw = ""
        self.recovered_from = safeio.set_aside(self.book_path) or self.book_path
        self.profiles, self.last_used_id = self._rebuilt(raw)
        self.swept_legacy = True
        if self.profiles:
            self.save()

    _UUID = re.compile(r"[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}")

    def _rebuilt(self, damaged_text):
        salvaged = {}
        for m in re.finditer(r'\{[^{}]*?"id"\s*:\s*"([0-9A-Fa-f-]{36})"[^{}]*', damaged_text):
            obj, pid = m.group(0), m.group(1)
            name = ""
            nm = re.search(r'"name"\s*:\s*("(?:[^"\\]|\\.)*")', obj)
            if nm:
                try:
                    name = json.loads(nm.group(1))
                except Exception:
                    name = ""
            ac = re.search(r'"accent"\s*:\s*(-?\d+)', obj)
            salvaged[pid.lower()] = (name, int(ac.group(1)) if ac else None)
        lu = re.search(r'"lastUsedID"\s*:\s*"([0-9A-Fa-f-]{36})"', damaged_text)

        folders = []
        if os.path.isdir(self.profiles_dir):
            for entry in os.listdir(self.profiles_dir):
                path = os.path.join(self.profiles_dir, entry)
                if os.path.isdir(path) and self._UUID.fullmatch(entry):
                    folders.append((os.path.getmtime(path), entry))
        folders.sort()
        profiles, used = [], set()
        for mtime, pid in folders:
            name, accent = salvaged.get(pid.lower(), ("", None))
            name = (name or "").strip() or L("Student")
            unique, n = name, 2
            while unique in used:
                unique = f"{name} {n}"
                n += 1
            used.add(unique)
            profiles.append({"id": pid, "name": unique,
                             "accent": accent if accent is not None else len(profiles) % PROFILE_ACCENTS,
                             "createdAt": mtime, "lastUsedAt": mtime})
        ids = {p["id"] for p in profiles}
        last = lu.group(1) if lu and lu.group(1) in ids else None
        if last is None and profiles:
            last = max(profiles, key=lambda p: p["lastUsedAt"])["id"]
        return profiles, last

    @staticmethod
    def _clean(d):
        return {"id": d.get("id") or str(uuid.uuid4()),
                "name": d.get("name", ""),
                "accent": int(d.get("accent", 0)),
                "createdAt": float(d.get("createdAt", time.time())),
                "lastUsedAt": float(d.get("lastUsedAt", time.time()))}

    @property
    def current(self):
        for p in self.profiles:
            if p["id"] == self.last_used_id:
                return p
        return self.profiles[0]

    def _migrate_single_student(self, name):
        profile = self._clean({"name": name})
        target = self.directory(profile["id"])
        os.makedirs(target, exist_ok=True)
        for folder in PERSONAL_FOLDERS:
            src = os.path.join(self.shared_root, folder)
            if os.path.isdir(src):
                shutil.copytree(src, os.path.join(target, folder), dirs_exist_ok=True)
        for name_ in PERSONAL_FILES:
            src = os.path.join(self.shared_root, name_)
            if os.path.isfile(src):
                shutil.copy2(src, os.path.join(target, name_))
        return profile

    def distinct(self, name, excluding=None):
        taken = {p["name"] for p in self.profiles if p["id"] != excluding}
        if name not in taken:
            return name
        n = 2
        while f"{name} {n}" in taken:
            n += 1
        return f"{name} {n}"

    def sweep_legacy_folders(self):
        if self.swept_legacy or not self.profiles:
            return False

        def contents(directory):
            out = set()
            for base, _dirs, files in os.walk(directory):
                out.update(files)
            return out

        legacy = {}
        for folder in PERSONAL_FOLDERS:
            path = os.path.join(self.shared_root, folder)
            if os.path.isdir(path):
                legacy[path] = contents(path)
        for name_ in PERSONAL_FILES:
            path = os.path.join(self.shared_root, name_)
            if os.path.isfile(path):
                legacy[path] = {name_}
        if not legacy:
            self.swept_legacy = True
            self.save()
            return False

        held = set()
        for p in self.profiles:
            held |= contents(self.directory(p["id"]))
        if any(not names <= held for names in legacy.values()):
            return False

        for path in legacy:
            if os.path.isdir(path):
                remove_tree(path)
            else:
                try:
                    os.remove(path)
                except OSError:
                    return False
        self.swept_legacy = True
        self.save()
        return True

    def heal_duplicates(self):
        seen, changed = set(), False
        for p in self.profiles:
            if p["name"] in seen:
                n = 2
                while f"{p['name']} {n}" in seen:
                    n += 1
                p["name"] = f"{p['name']} {n}"
                changed = True
            seen.add(p["name"])
        used = set()
        for i, p in enumerate(self.profiles):
            if p["accent"] in used and len(self.profiles) <= PROFILE_ACCENTS:
                p["accent"] = self.least_used_accent(excluding=i)
                changed = True
            used.add(p["accent"])
        if changed:
            self.save()

    def least_used_accent(self, excluding=None):
        counts = [0] * PROFILE_ACCENTS
        for i, p in enumerate(self.profiles):
            if i != excluding:
                counts[int(p.get("accent", 0)) % PROFILE_ACCENTS] += 1
        return min(range(PROFILE_ACCENTS), key=lambda i: (counts[i], i))

    def add(self, name=""):
        name = (name or "").strip()
        name = self.distinct(name) if name else self.unused_name()
        profile = self._clean({"name": name, "accent": self.least_used_accent()})
        os.makedirs(self.directory(profile["id"]), exist_ok=True)
        self.profiles.append(profile)
        self.save()
        return profile

    def rename(self, profile_id, name):
        name = (name or "").strip()
        if not name:
            return
        for p in self.profiles:
            if p["id"] == profile_id:
                p["name"] = self.distinct(name, excluding=profile_id)
        self.save()

    def set_accent(self, profile_id, accent):
        for p in self.profiles:
            if p["id"] == profile_id:
                p["accent"] = accent % PROFILE_ACCENTS
        self.save()

    def remove(self, profile_id):
        if len(self.profiles) <= 1:
            return False
        if not any(p["id"] == profile_id for p in self.profiles):
            return False
        remove_tree(self.directory(profile_id))
        self.profiles = [p for p in self.profiles if p["id"] != profile_id]
        if self.last_used_id == profile_id:
            self.last_used_id = self.profiles[0]["id"]
        self.save()
        return True

    def mark_used(self, profile_id):
        for p in self.profiles:
            if p["id"] == profile_id:
                p["lastUsedAt"] = time.time()
        self.last_used_id = profile_id
        self.save()

    def unused_name(self, base=None):
        base = base or L("Student")
        taken = {p["name"] for p in self.profiles}
        if base not in taken:
            return base
        n = 2
        while f"{base} {n}" in taken:
            n += 1
        return f"{base} {n}"

    def save(self):
        os.makedirs(self.profiles_dir, exist_ok=True)
        safeio.write_json(self.book_path,
                          {"profiles": self.profiles, "lastUsedID": self.last_used_id,
                           "sweptLegacy": self.swept_legacy},
                          indent=2, sort_keys=True)


def profile_initials(profile):
    words = [w for w in str(profile.get("name", "")).split() if w[0].isalpha()][:2]
    letters = "".join(w[0] for w in words if w)
    return letters.upper() if letters else "?"


NAME_SHOWN_LIMIT = 22


def profile_display_name(profile):
    name = str(profile.get("name", "")).strip()
    if not name:
        from .i18n import L
        return L("Student")
    if len(name) <= NAME_SHOWN_LIMIT:
        return name
    return name[:NAME_SHOWN_LIMIT - 1] + "…"


@dataclass
class ContentBlock:
    kind: str = "text"
    text: str = ""
    image_name: str = ""
    pixel_width: float = 0
    pixel_height: float = 0
    point_width: float = 0
    underlines: list = field(default_factory=list)
    rows: list = field(default_factory=list)
    centred: bool = False
    inline: list = field(default_factory=list)
    x_height: float = 0

    @staticmethod
    def from_dict(d):
        base = ContentBlock()
        b = ContentBlock(**{name: d.get(name, getattr(base, name)) for name in _BLOCK_FIELDS})
        b.underlines = [tuple(r) for r in (b.underlines or [])]
        b.rows = [list(r) for r in (b.rows or [])]
        return b


_BLOCK_FIELDS = tuple(f.name for f in fields(ContentBlock))


@dataclass
class Choice:
    letter: str
    blocks: list = field(default_factory=list)

    @staticmethod
    def from_dict(d):
        return Choice(letter=d["letter"],
                      blocks=[ContentBlock.from_dict(b) for b in d.get("blocks", [])])


@dataclass
class Question:
    id: str
    subject: str = "math"
    assessment: str = "SAT"
    test: str = ""
    domain: str = ""
    skill: str = ""
    difficulty: str = ""
    kind: str = "multiple_choice"
    stimulus: list = field(default_factory=list)
    prompt: list = field(default_factory=list)
    choices: list = field(default_factory=list)
    correct_answer: str = ""
    rationale: list = field(default_factory=list)
    source_name: str = ""

    def to_dict(self):
        d = asdict(self)
        return d

    @staticmethod
    def from_dict(d):
        q = Question(id=d["id"])
        for k in ("subject", "assessment", "test", "domain", "skill", "difficulty",
                  "kind", "correct_answer", "source_name"):
            setattr(q, k, d.get(k, getattr(q, k)))
        q.stimulus = [ContentBlock.from_dict(b) for b in d.get("stimulus", [])]
        q.prompt = [ContentBlock.from_dict(b) for b in d.get("prompt", [])]
        q.rationale = [ContentBlock.from_dict(b) for b in d.get("rationale", [])]
        q.choices = [Choice.from_dict(c) for c in d.get("choices", [])]
        return q

    @property
    def all_blocks(self):
        out = list(self.stimulus) + list(self.prompt) + list(self.rationale)
        for c in self.choices:
            out += c.blocks
        return out

    @property
    def subject_label(self):
        return L("Math") if self.subject == "math" else L("Reading and Writing")

    @property
    def accepted_answers(self):
        return [p.strip() for p in re.split(r"[,;]", self.correct_answer) if p.strip()]


def _normalise(s: str) -> str:
    return s.lower().replace(",", "").replace(" ", "").replace("$", "").replace("%", "")


def numeric_value(s: str):
    t = _normalise(s)
    if not t:
        return None
    if "/" in t:
        parts = t.split("/")
        if len(parts) != 2:
            return None
        try:
            n, d = float(parts[0]), float(parts[1])
        except ValueError:
            return None
        if d == 0:
            return None
        return n / d
    try:
        return float(t)
    except ValueError:
        return None


def _matches(given: str, accepted: str) -> bool:
    if _normalise(given) == _normalise(accepted):
        return True
    a, b = numeric_value(given), numeric_value(accepted)
    if a is not None and b is not None and abs(a - b) <= max(1e-6, abs(b) * 1e-6):
        return True
    return _cut_short(given, accepted)


_FILLED_DECIMAL = re.compile(r"-?\d*\.\d+")


def _exact(s: str):
    t = _normalise(s)
    try:
        if "/" in t:
            n, d = t.split("/")
            return Fraction(n) / Fraction(d)
        return Fraction(t)
    except (ValueError, ZeroDivisionError):
        return None


def _cut_short(given: str, accepted: str) -> bool:
    g = given.strip()
    if not _FILLED_DECIMAL.fullmatch(g) or len(g) != (6 if g.startswith("-") else 5):
        return False
    exact = _exact(accepted)
    if exact is None:
        return False
    scale = 10 ** len(g.split(".")[1])
    typed = Fraction(g) * scale
    stopped = math.trunc(exact * scale)
    rounded = math.floor(abs(exact) * scale + Fraction(1, 2)) * (1 if exact >= 0 else -1)
    return typed in (stopped, rounded)


def is_correct(question: Question, response: str) -> bool:
    given = (response or "").strip()
    if not given:
        return False
    if question.kind == "multiple_choice":
        return given.upper() == question.correct_answer.strip().upper()

    accepted = question.accepted_answers
    if any(_matches(given, a) for a in accepted):
        return True

    parts = [p.strip() for p in given.replace(";", ",").split(",") if p.strip()]
    if len(parts) < 2:
        return False
    return all(any(_matches(p, a) for a in accepted) for p in parts)


DEFAULT_SCHEDULE = {
    "enabled": False,
    "days": [2, 3, 4, 5, 6],
    "daily_target": 20,
    "reminders_on": False,
    "reminder_hour": 17,
    "reminder_minute": 0,
    "warns_when_streak_at_risk": True,
    "warning_hour": 20,
}

WEEKDAY_NAMES = {1: "S", 2: "M", 3: "T", 4: "W", 5: "T", 6: "F", 7: "S"}


# These seven are the keys themselves: data, not copy.
WEEKDAY_KEYS = {1: "Sunday initial", 2: "Monday initial", 3: "Tuesday initial",
                4: "Wednesday initial", 5: "Thursday initial",
                6: "Friday initial", 7: "Saturday initial"}
WEEKDAY_LETTERS = {1: "S", 2: "M", 3: "T", 4: "W", 5: "T", 6: "F", 7: "S"}


def weekday_initial(day):
    spoken = {1: L("Sunday initial"), 2: L("Monday initial"),
              3: L("Tuesday initial"), 4: L("Wednesday initial"),
              5: L("Thursday initial"), 6: L("Friday initial"),
              7: L("Saturday initial")}[day]
    return WEEKDAY_LETTERS[day] if spoken == WEEKDAY_KEYS[day] else spoken
WEEKDAY_ORDER = [2, 3, 4, 5, 6, 7, 1]


def schedule_defaults(raw=None):
    plan = dict(DEFAULT_SCHEDULE)
    plan.update(raw or {})
    plan["days"] = sorted({int(d) for d in plan.get("days", []) if 1 <= int(d) <= 7})
    return plan


def schedule_is_active(plan):
    return bool(plan.get("enabled")) and bool(plan.get("days")) \
        and int(plan.get("daily_target", 0)) > 0


def _weekday(date):
    return (date.weekday() + 1) % 7 + 1


def schedule_target(plan, date):
    if not schedule_is_active(plan):
        return int(plan.get("daily_target", 0))
    return int(plan["daily_target"]) if _weekday(date) in plan["days"] else 0


def schedule_summary(plan):
    if not schedule_is_active(plan):
        target = int(plan.get("daily_target", 0) or 0)
        return (Lf("No plan — %d a day, every day", target) if target > 0
                else L("No plan — every day counts"))
    target = int(plan["daily_target"])
    if len(plan["days"]) == 7:
        return Lf("%d a day, every day", target)
    names = " ".join(weekday_initial(d) for d in WEEKDAY_ORDER if d in plan["days"])
    return Lf("%1$d a day on %2$@", target, names)


def evaluate_streak(answers_by_day, plan, now=None, excused=()):
    now = now or datetime.datetime.now()
    today = now.date() if isinstance(now, datetime.datetime) else now
    counts = {d: int(n) for d, n in answers_by_day.items()}
    excused_days = {_as_day(d) for d in (excused or ())}

    def kept(day):
        target = schedule_target(plan, day)
        if target == 0:
            return None
        if counts.get(day, 0) >= target:
            return True
        return None if day in excused_days else False

    target_today = schedule_target(plan, today)
    answered_today = counts.get(today, 0)
    met_today = target_today > 0 and answered_today >= target_today

    streak = 1 if kept(today) else 0
    run_started_on = today if kept(today) else None
    cursor = today
    for _ in range(400):
        cursor = cursor - datetime.timedelta(days=1)
        state = kept(cursor)
        if state is None:
            continue
        if state:
            streak += 1
            run_started_on = cursor
        else:
            break

    best, run = streak, 0
    if counts:
        cursor = min(counts)
        while cursor <= today:
            state = kept(cursor)
            if state is True:
                run += 1
                best = max(best, run)
            elif state is False and cursor < today:
                run = 0
            cursor = cursor + datetime.timedelta(days=1)

    week_start = today - datetime.timedelta(days=today.weekday())
    planned = held = 0
    for offset in range(7):
        day = week_start + datetime.timedelta(days=offset)
        if schedule_target(plan, day) > 0:
            planned += 1
            if kept(day):
                held += 1

    return {
        "current": streak,
        "best": best,
        "answered_today": answered_today,
        "target_today": target_today,
        "is_rest_day": target_today == 0,
        "met_today": met_today,
        "remaining_today": max(0, target_today - answered_today),
        "at_risk": target_today > 0 and not met_today and streak > 0,
        "kept_this_week": held,
        "planned_this_week": planned,
        "run_started_on": run_started_on,
    }


def longest_word(rows):
    longest = ""
    for row in rows or ():
        for cell in row:
            for word in str(cell).split():
                if len(word) > len(longest):
                    longest = word
    return longest


def fit_table_size(rows, columns, available, measure, base):
    word = longest_word(rows)
    if not word or columns <= 0 or available <= 0:
        return base
    size = base
    while size > 8:
        if measure(word, size) <= available:
            return size
        size -= 1
    return 8


def _as_day(value):
    if isinstance(value, datetime.datetime):
        return value.date()
    if isinstance(value, datetime.date):
        return value
    return datetime.date.fromtimestamp(float(value))


def _day_stamp(day):
    return datetime.datetime.combine(_as_day(day), datetime.time()).timestamp()


def _same_day(stored, day):
    if stored in (None, ""):
        return False
    try:
        return _as_day(stored) == day
    except (ValueError, OSError, TypeError):
        try:
            return datetime.date.fromisoformat(str(stored)[:10]) == day
        except ValueError:
            return False


LONGEST_GAP = 31
RESTORE_AFTER = 3
WELCOME_AFTER = 7


def mercy_gap(answers_by_day, plan, excused=(), now=None):
    now = now or datetime.datetime.now()
    today = now.date() if isinstance(now, datetime.datetime) else now
    counts = {d: int(n) for d, n in answers_by_day.items() if int(n) > 0}
    if not counts:
        return None
    last_active = max(counts)
    if last_active >= today:
        return None

    days_away = (today - last_active).days
    excused_days = {_as_day(d) for d in (excused or ())}

    missed = []
    cursor = last_active + datetime.timedelta(days=1)
    while cursor < today:
        if schedule_target(plan, cursor) > 0 and counts.get(cursor, 0) == 0 \
                and cursor not in excused_days:
            missed.append(cursor)
        cursor = cursor + datetime.timedelta(days=1)

    before = evaluate_streak(answers_by_day, plan, now=last_active,
                             excused=excused)["current"]
    return {
        "last_active": last_active,
        "days_away": days_away,
        "missed": missed,
        "streak_before": before,
        "restorable": before > 0 and bool(missed) and days_away <= LONGEST_GAP,
    }


CONFIDENT_AT = 5

SITTING_GAP = 30 * 60

_DIFFICULTY_ORDER = {"Easy": 0, "Medium": 1, "Hard": 2}


def _breakdown(label, rows, available):
    times = [r.get("seconds", 0) for r in rows
             if r.get("seconds", 0) > 0 and not r.get("backfilled")]
    attempts = len(rows)
    correct = sum(1 for r in rows if r.get("correct"))
    return {
        "label": label,
        "attempts": attempts,
        "correct": correct,
        "available": available,
        "seen": len({r["question_id"] for r in rows}),
        "accuracy": (correct / attempts) if attempts else 0.0,
        "coverage": (len({r["question_id"] for r in rows}) / available) if available else 0.0,
        "average_seconds": (sum(times) / len(times)) if times else 0.0,
        "confident": attempts >= CONFIDENT_AT,
    }


def _group(records, questions, key):
    rows = {}
    for r in records:
        label = r.get(key) or ""
        if label:
            rows.setdefault(label, []).append(r)
    available = {}
    for q in questions:
        label = getattr(q, key, "") or ""
        if label:
            available[label] = available.get(label, 0) + 1
    labels = set(rows) | set(available)
    return [_breakdown(l, rows.get(l, []), available.get(l, 0)) for l in labels]


def _group_by_subject(records, questions):
    rows = {}
    for r in records:
        subject = r.get("subject")
        if subject:
            rows.setdefault(subject, []).append(r)
    available = {}
    for q in questions:
        available[q.subject] = available.get(q.subject, 0) + 1
    out = []
    for subject in set(rows) | set(available):
        b = _breakdown(fulltest.section_label(subject),
                       rows.get(subject, []), available.get(subject, 0))
        b["label_key"] = subject
        out.append(b)
    return out


def sittings(records):
    rows = sorted(records, key=lambda r: r.get("at", 0))
    if not rows:
        return []
    out, current, previous = [], {"index": 0, "attempts": 0, "correct": 0,
                                  "at": rows[0].get("at", 0)}, rows[0].get("at", 0)
    for r in rows:
        if r.get("at", 0) - previous > SITTING_GAP:
            out.append(current)
            current = {"index": len(out), "attempts": 0, "correct": 0,
                       "at": r.get("at", 0)}
        current["attempts"] += 1
        if r.get("correct"):
            current["correct"] += 1
        previous = r.get("at", 0)
    out.append(current)
    for s in out:
        s["accuracy"] = (s["correct"] / s["attempts"]) if s["attempts"] else 0.0
    return out


class StatisticsFilter:

    def __init__(self, subjects=None, domain=None, skill=None):
        self.subjects = set(subjects) if subjects is not None else None
        self.domain = domain
        self.skill = skill

    def __eq__(self, other):
        return (isinstance(other, StatisticsFilter)
                and self.subjects == other.subjects
                and self.domain == other.domain
                and self.skill == other.skill)

    def __hash__(self):
        return hash((frozenset(self.subjects) if self.subjects is not None else None,
                     self.domain, self.skill))

    @property
    def narrows_anything(self):
        return (self.subjects is not None or self.domain is not None
                or self.skill is not None)

    def admits(self, subject, domain, skill):
        if self.subjects is not None and subject not in self.subjects:
            return False
        if self.domain is not None and LabelCase.key(self.domain) != LabelCase.key(domain):
            return False
        if self.skill is not None and LabelCase.key(self.skill) != LabelCase.key(skill):
            return False
        return True


StatisticsFilter.everything = StatisticsFilter()


def _respelled(records, questions):
    def spellings(attr):
        out = {}
        for q in questions:
            v = getattr(q, attr, "")
            if v:
                out[LabelCase.key(v)] = v
        return out
    maps = {attr: spellings(attr) for attr in ("skill", "domain", "difficulty")}
    def _one(attr, r):
        return maps[attr].get(LabelCase.key(r.get(attr, "")))
    needed = any(
        any(_one(attr, r) not in (None, r.get(attr, "")) for attr in maps)
        for r in records)
    if not needed:
        return records
    out = []
    for r in records:
        r = dict(r)
        for attr in maps:
            one = _one(attr, r)
            if one is not None:
                r[attr] = one
        out.append(r)
    return out


_SECTION_ORDER = ("reading_writing", "math")


def build_statistics(history, bank, subjects=None, filter=None):
    if filter is None:
        filter = StatisticsFilter(subjects=set(subjects) if subjects is not None
                                  else None)
    all_questions = bank.questions if bank else []
    questions = [q for q in all_questions
                 if filter.admits(q.subject, q.domain, q.skill)]
    records = _respelled(
        [r for r in history
         if filter.admits(r.get("subject"), r.get("domain", ""), r.get("skill", ""))],
        questions)

    section_records = _respelled(list(history), all_questions)
    by_section_rows = {b["label_key"]: b for b in
                       _group_by_subject(section_records, all_questions)}
    by_section = [by_section_rows[s] for s in _SECTION_ORDER if s in by_section_rows]

    by_skill = sorted(_group(records, questions, "skill"), key=lambda b: b["label"])
    by_domain = sorted(_group(records, questions, "domain"), key=lambda b: b["label"])
    by_difficulty = sorted(_group(records, questions, "difficulty"),
                           key=lambda b: _DIFFICULTY_ORDER.get(b["label"], 9))
    times = sorted(r.get("seconds", 0) for r in records
                   if r.get("seconds", 0) > 0 and not r.get("backfilled"))
    attempts = len(records)
    correct = sum(1 for r in records if r.get("correct"))

    return {
        "total_attempts": attempts,
        "total_correct": correct,
        "accuracy": (correct / attempts) if attempts else 0.0,
        "questions_seen": len({r["question_id"] for r in records}),
        "questions_available": len(questions),
        "by_skill": by_skill,
        "by_domain": by_domain,
        "by_difficulty": by_difficulty,
        "by_section": by_section,
        "trend": sittings([r for r in records if not r.get("backfilled")]),
        "median_seconds": times[len(times) // 2] if times else 0.0,
        "has_data": attempts > 0,
        "weakest": sorted([b for b in by_skill if b["confident"]],
                          key=lambda b: b["accuracy"]),
        "untested": sorted([b for b in by_skill
                            if not b["confident"] and b["available"] > 0],
                           key=lambda b: b["attempts"]),
    }


TIMER_WARNING_SECONDS = 300


def should_warn(seconds_remaining, already_warned, total_seconds=None):
    if total_seconds is not None and total_seconds <= TIMER_WARNING_SECONDS:
        return False
    return seconds_remaining <= TIMER_WARNING_SECONDS and not already_warned


PARSER_VERSION = 27


class AlreadyImported(ValueError):

    def __init__(self, bank_id, message):
        super().__init__(message)
        self.bank_id = bank_id


class LabelCase:

    @staticmethod
    def key(label):
        return (label or "").lower()

    @staticmethod
    def canonical(values):
        spellings = {}
        for v in values:
            if not v:
                continue
            spellings.setdefault(LabelCase.key(v), {})
            forms = spellings[LabelCase.key(v)]
            forms[v] = forms.get(v, 0) + 1
        if not any(len(forms) > 1 for forms in spellings.values()):
            return None
        return {k: max(forms.items(), key=lambda kv: (kv[1], _neg_sort(kv[0])))[0]
                for k, forms in spellings.items()}

    @staticmethod
    def unified(questions):
        maps = {attr: LabelCase.canonical([getattr(q, attr, "") for q in questions])
                for attr in ("skill", "domain", "difficulty", "assessment")}
        if not any(maps.values()):
            return questions
        for q in questions:
            for attr, canon in maps.items():
                if canon:
                    one = canon.get(LabelCase.key(getattr(q, attr, "")))
                    if one is not None:
                        setattr(q, attr, one)
        return questions


class _NegSort:

    __slots__ = ("s",)

    def __init__(self, s):
        self.s = s

    def __lt__(self, other):
        return self.s > other.s

    def __eq__(self, other):
        return self.s == other.s


def _neg_sort(s):
    return _NegSort(s)


@dataclass
class Bank:
    id: str
    name: str
    created_at: float
    questions: list = field(default_factory=list)
    parser_version: int = 0

    @property
    def math_count(self):
        return sum(1 for q in self.questions if q.subject == "math")

    @property
    def reading_count(self):
        return sum(1 for q in self.questions if q.subject == "reading_writing")

    def tally(self, attr, subjects=None):
        counts = {}
        for q in self.questions:
            if subjects is not None and q.subject not in subjects:
                continue
            label = getattr(q, attr, "")
            if label:
                counts[label] = counts.get(label, 0) + 1
        return sorted(counts.items())

    def difficulties(self, subjects=None):
        order = {"Easy": 0, "Medium": 1, "Hard": 2}
        return sorted(self.tally("difficulty", subjects),
                      key=lambda t: (order.get(t[0], 9), t[0]))

    def assessments(self, subjects=None):
        return self.tally("assessment", subjects)

    def domains(self, subjects=None):
        return self.tally("domain", subjects)

    def skills(self, subjects=None):
        return self.tally("skill", subjects)


PACE_READING_WRITING = 32 * 60 / 27
PACE_MATH = 35 * 60 / 22


def pace_minutes(reading_writing, math):
    seconds = reading_writing * PACE_READING_WRITING + math * PACE_MATH
    return max(1, int(round(seconds / 60)))


def has_section_split(config):
    return (len(config.get("subjects") or []) > 1
            and bool(config.get("sectionCounts")))


def section_count(config, subject):
    return int((config.get("sectionCounts") or {}).get(subject, 0))


def set_section_count(config, subject, n):
    counts = dict(config.get("sectionCounts") or {})
    counts[subject] = max(0, int(n))
    config["sectionCounts"] = counts
    config["count"] = max(1, sum(counts.values()))


def clear_section_split(config):
    config["sectionCounts"] = {}


def file_size(byte_count):
    mb = byte_count / 1_000_000
    if mb >= 1000:
        return "%.1f GB" % (mb / 1000)
    if mb >= 10:
        return "%.0f MB" % mb
    if mb >= 1:
        return "%.1f MB" % mb
    return "%.0f KB" % max(1, byte_count / 1000)


def describe_pace(seconds):
    s = int(round(seconds))
    return Lf("%d s", s) if s < 60 else f"{s // 60}:{s % 60:02d}"


REVIEW_DAYS = [1, 3, 7, 16, 35]


def review_interval(times_correct, last_correct):
    rung = min(max(times_correct, 1), len(REVIEW_DAYS)) if last_correct else 1
    return REVIEW_DAYS[rung - 1] * 24 * 60 * 60


def is_due(record, now=None):
    if not record or record.get("times_seen", 0) <= 0:
        return False
    last = record.get("last_seen")
    if not last:
        return False
    now = time.time() if now is None else now
    return now - last >= review_interval(record.get("times_correct", 0),
                                         record.get("last_correct", False))


def overdue_by(record, now=None):
    last = record.get("last_seen") or 0
    now = time.time() if now is None else now
    return (now - last) - review_interval(record.get("times_correct", 0),
                                          record.get("last_correct", False))


def next_due(records, now=None):
    now = time.time() if now is None else now
    times = []
    for r in records:
        if r.get("times_seen", 0) <= 0 or not r.get("last_seen"):
            continue
        due = r["last_seen"] + review_interval(r.get("times_correct", 0),
                                               r.get("last_correct", False))
        if due > now:
            times.append(due)
    return min(times) if times else None


def _attempt_from(d):
    known = {f.name for f in fields(Attempt)}
    return Attempt(**{k: v for k, v in d.items() if k in known})


@dataclass
class Attempt:
    question_id: str
    response: str = ""
    marked: bool = False
    eliminated: list = field(default_factory=list)
    revealed: bool = False
    seconds_spent: float = 0.0

    @property
    def answered(self):
        return bool(self.response.strip())


@dataclass
class Session:
    bank_id: str
    bank_name: str
    config: dict
    questions: list
    attempts: list
    index: int = 0
    started_at: float = field(default_factory=time.time)
    last_saved_at: float = field(default_factory=time.time)
    finished: bool = False
    seconds_remaining: float = 0

    modules: list = field(default_factory=list)
    adaptive: dict = field(default_factory=dict)

    partner_id: str = ""
    turn_names: list = field(default_factory=list)
    turn_accents: list = field(default_factory=list)
    partner_index: int = 1
    seats_finished: list = field(default_factory=list)

    def turn(self, index):
        return index % 2

    @property
    def is_double(self):
        return bool(self.partner_id) and len(self.turn_names) == 2

    def repair_indices(self):
        last = max(0, len(self.questions) - 1)
        for attr, seat in (("index", 0), ("partner_index", 1)):
            value = getattr(self, attr, 0) or 0
            if value < 0 or value > last:
                if value > last and seat not in self.seats_finished:
                    self.seats_finished.append(seat)
                setattr(self, attr, min(max(0, value), last))

    def is_finished_seat(self, seat):
        return seat in self.seats_finished

    @property
    def both_seats_finished(self):
        return (self.is_double and self.is_finished_seat(0)
                and self.is_finished_seat(1))

    @property
    def is_side_by_side(self):
        return self.is_double and self.config.get("doubleLayout") == "side_by_side"

    def positions(self, seat):
        return [i for i in range(len(self.questions)) if self.turn(i) == seat]

    def index_for(self, seat):
        return self.index if seat == 0 else self.partner_index

    def turn_name(self, index):
        seat = self.turn(index)
        return self.turn_names[seat] if seat < len(self.turn_names) else ""

    def double_scores(self):
        if not self.is_double:
            return []
        out = []
        for seat in (0, 1):
            correct = answered = 0
            for i, attempt in enumerate(self.attempts):
                if self.turn(i) != seat or not attempt.answered:
                    continue
                answered += 1
                if is_correct(self.questions[i], attempt.response):
                    correct += 1
            out.append({"name": self.turn_names[seat] if seat < len(self.turn_names) else "",
                        "correct": correct, "answered": answered})
        return out

    @property
    def is_module_shaped(self):
        subjects = {q.subject for q in self.questions}
        if len(subjects) != 1 or not self.config.get("timed"):
            return False
        count, minutes = (22, 35) if "math" in subjects else (27, 32)
        return len(self.questions) == count and int(self.config.get("minutes", 0)) == minutes

    @property
    def display_title(self):
        named = str(self.config.get("sitting_name", "")).strip()
        if named:
            return named
        subjects = {q.subject for q in self.questions}
        if len(subjects) != 1:
            return L("Mixed practice")
        label = L("Math") if "math" in subjects else L("Reading and Writing")
        return Lf("Module 1: %@", label) if self.is_module_shaped \
            else Lf("%@ practice", label)

    @property
    def subtitle_line(self):
        n = len(self.questions)
        parts = [Lp(n, "%d question", "%d questions")]
        subjects = {q.subject for q in self.questions}
        if len(subjects) > 1:
            rw = sum(1 for q in self.questions if q.subject == "reading_writing")
            parts = [Lf("%1$d Reading and Writing · %2$d Math", rw, n - rw)]
        minutes = int(self.config.get("minutes", 0))
        parts.append(Lp(minutes, "%d minute", "%d minutes")
                     if self.config.get("timed") else L("untimed"))
        return " · ".join(parts)

    @property
    def resume_position(self):
        safe = min(max(0, self.index), max(0, len(self.questions) - 1))
        module = fulltest.current_module(self)
        if module is not None:
            answered = fulltest.score(self, module)[1]
            return Lf("Question %1$d of %2$d · %3$d answered",
                      max(1, safe - module.start + 1), module.count, answered)
        return Lf("Question %1$d of %2$d · %3$d answered",
                  safe + 1, len(self.questions), self.answered_count)

    @property
    def resume_clock(self):
        module = fulltest.current_module(self)
        left = module.seconds_remaining if module is not None \
            else self.seconds_remaining
        if (module is None and not self.config.get("timed")) or left <= 0:
            return None
        minutes = int(left) // 60
        if minutes < 1:
            return L("under a minute left")
        return Lp(minutes, "%d minute left", "%d minutes left")

    def resume_age(self, now=None):
        now = time.time() if now is None else now
        start = datetime.date.fromtimestamp(self.last_saved_at)
        days = (datetime.date.fromtimestamp(now) - start).days
        if days <= 0:
            return L("left off today")
        if days == 1:
            return L("left off yesterday")
        return Lp(days, "left off %d day ago", "left off %d days ago")

    def resume_detail(self, now=None):
        parts = [self.resume_position]
        clock = self.resume_clock
        if clock:
            parts.append(clock)
        parts.append(self.resume_age(now))
        return " · ".join(parts)

    @property
    def correct_count(self):
        return sum(1 for q, a in zip(self.questions, self.attempts) if is_correct(q, a.response))

    @property
    def answered_count(self):
        return sum(1 for a in self.attempts if a.answered)

    @property
    def missed(self):
        return [q for q, a in zip(self.questions, self.attempts)
                if a.answered and not is_correct(q, a.response)]

    @property
    def unanswered(self):
        return [q for q, a in zip(self.questions, self.attempts) if not a.answered]


class Store:

    def __init__(self, root=None):
        self.root = root or data_root()
        os.makedirs(self.root, exist_ok=True)
        self.damaged = []
        self.load_failures = []
        self.practice_config = None
        self.selected_deck_id = None
        self.deck_sessions = {}
        self.profiles = ProfileStore(self.root, default_name=_suggested_name())
        if self.profiles.recovered_from:
            self.note_damaged(self.profiles.recovered_from)
        self.profile = self.profiles.current
        self._point_at_profile()
        self.banks_dir = os.path.join(self.root, "Banks")
        os.makedirs(self.banks_dir, exist_ok=True)
        self.banks = []
        self.progress = {}
        self.notes = {}
        self.highlights_taken_off = 0
        self.history = {}
        self.settings = {"daily_goal": 20, "appearance": "light"}
        self.presets = []
        self.decks = DeckStore(self.profile_root, damaged=self.note_damaged)
        self.pending = []
        self.load()
        self._load_settings()
        from . import portable
        portable.load_pending(self)
        portable.apply_pending(self)

    def note_damaged(self, path):
        try:
            shown = os.path.relpath(path, self.root)
        except ValueError:
            shown = os.path.basename(path)
        if shown.startswith(".."):
            shown = os.path.basename(path)
        shown = shown.replace("\\", "/")
        if shown not in self.damaged:
            self.damaged.append(shown)

    def _point_at_profile(self):
        self.profile_root = self.profiles.directory(self.profile["id"])
        self.progress_dir = os.path.join(self.profile_root, "Progress")
        self.sessions_dir = os.path.join(self.profile_root, "Sessions")
        self.notes_dir = os.path.join(self.profile_root, "Notes")
        self.history_dir = os.path.join(self.profile_root, "History")  # data, not copy: a folder
        for d in (self.profile_root, self.progress_dir, self.sessions_dir,
                  self.notes_dir, self.history_dir):
            os.makedirs(d, exist_ok=True)

    def use_profile(self, profile):
        if profile["id"] == self.profile["id"]:
            return
        self.profiles.mark_used(profile["id"])
        self.profile = profile
        self._point_at_profile()
        self.banks = []
        self.progress = {}
        self.notes = {}
        self.history = {}
        self.presets = []
        self.practice_config = None
        self.selected_deck_id = None
        self.deck_sessions = {}
        self.settings = {"daily_goal": 20, "appearance": "light"}
        self.decks = DeckStore(self.profile_root, damaged=self.note_damaged)
        self.load()
        self._load_settings()
        from . import portable
        portable.load_pending(self)
        portable.apply_pending(self)

    def add_profile(self, name=""):
        return self.profiles.add(name)

    def delete_profile(self, profile_id):
        was_current = profile_id == self.profile["id"]
        if not self.profiles.remove(profile_id):
            return False
        if was_current:
            self.profile = self.profiles.profiles[0]
            self.profiles.mark_used(self.profile["id"])
            self._point_at_profile()
            self.practice_config = None
            self.selected_deck_id = None
            self.deck_sessions = {}
            self.decks = DeckStore(self.profile_root, damaged=self.note_damaged)
            self.load()
            self._load_settings()
        return True

    def bank_dir(self, bank_id):
        return os.path.join(self.banks_dir, bank_id)

    def size_on_disk(self, bank_id=None):
        root = self.bank_dir(bank_id) if bank_id else self.root
        total = 0
        for base, _dirs, names in os.walk(root):
            for name in names:
                try:
                    total += os.path.getsize(os.path.join(base, name))
                except OSError:
                    pass
        return total

    def size_breakdown(self, bank_id):
        images = self.size_on_disk_at(self.images_dir(bank_id))
        sources = self.size_on_disk_at(self.sources_dir(bank_id))
        exports = self.size_on_disk_at(self.exports_dir(bank_id))
        total = self.size_on_disk(bank_id)
        return {"images": images, "sources": sources, "exports": exports,
                "questions": max(0, total - images - sources - exports),
                "total": total}

    def size_on_disk_at(self, path):
        total = 0
        for base, _dirs, names in os.walk(path):
            for name in names:
                try:
                    total += os.path.getsize(os.path.join(base, name))
                except OSError:
                    pass
        return total

    def images_dir(self, bank_id):
        return os.path.join(self.bank_dir(bank_id), "images")

    def sources_dir(self, bank_id):
        return os.path.join(self.bank_dir(bank_id), "sources")

    def exports_dir(self, bank_id):
        return os.path.join(self.bank_dir(bank_id), "exports")

    def load(self):
        self.banks = []
        self.load_failures = []
        pending = os.path.join(self.profile_root, TAKEN_OFF_FILE)
        try:
            with open(pending, encoding="utf-8") as f:
                self.highlights_taken_off = int(f.read().strip() or 0)
        except (OSError, ValueError):
            self.highlights_taken_off = 0
        try:
            os.remove(pending)
        except OSError:
            pass
        for name in sorted(os.listdir(self.banks_dir)):
            path = os.path.join(self.banks_dir, name, "bank.json")
            if not os.path.exists(path):
                if self._holds_set_aside(os.path.join(self.banks_dir, name)):
                    self.load_failures.append(name)
                continue
            try:
                with open(path, encoding="utf-8") as f:
                    d = json.load(f)
                self.banks.append(Bank(
                    id=d["id"], name=d["name"], created_at=d.get("created_at", 0),
                    questions=LabelCase.unified(
                        [Question.from_dict(q) for q in d.get("questions", [])]),
                    parser_version=d.get("parser_version", 0)))
            except Exception:
                self.load_failures.append(name)
                self.note_damaged(safeio.set_aside(path) or path)
                continue
        self._remove_abandoned_imports()
        self.banks.sort(key=lambda b: b.created_at, reverse=True)
        for b in self.banks:
            self.progress[b.id] = self._load_progress(b.id)
            self.notes[b.id] = self._load_notes(b.id)
            self.history[b.id] = self._load_history(b.id)
            safeio.read_json(self.session_path(b.id), None, self.note_damaged, expect=dict)

    @staticmethod
    def _holds_set_aside(folder):
        try:
            return any(safeio.is_set_aside(n) for n in os.listdir(folder))
        except OSError:
            return False

    def _remove_abandoned_imports(self):
        for name in os.listdir(self.banks_dir):
            path = os.path.join(self.banks_dir, name)
            if (not os.path.isdir(path) or os.path.exists(os.path.join(path, "bank.json"))
                    or self._holds_set_aside(path)):
                continue
            sources = os.path.join(path, "sources")
            if os.path.isdir(sources) and os.listdir(sources):
                continue
            remove_tree(path)

    def bank(self, bank_id):
        return next((b for b in self.banks if b.id == bank_id), None)

    def _settings_path(self):
        return os.path.join(self.profile_root, "Settings.json")

    def _presets_path(self):
        return os.path.join(self.profile_root, "Plans.json")

    def _load_settings(self):
        for path, attr, default in ((self._settings_path(), "settings",
                                     {"daily_goal": 20, "appearance": "light"}),
                                    (self._presets_path(), "presets", [])):
            value = safeio.read_json(path, default, self.note_damaged,
                                     expect=type(default))
            setattr(self, attr, value)
        self.settings.setdefault("daily_goal", 20)
        self.settings.setdefault("appearance", "light")
        for key in ("showLearnInSidebar", "showImportButton",
                    "showQuestionStreak", "showVocabularyStreak",
                    "showDoubleMode", "showBackupCard", "showParentSummary",
                    "showQuestionSets", "showFlashcards"):
            self.settings.setdefault(key, True)
        self.settings.setdefault("stealthMode", False)
        self.settings.setdefault("excusedDays", [])
        from .i18n import system_default, use as use_language
        self.settings.setdefault("language", system_default())
        use_language(self.settings["language"])
        self.settings["schedule"] = schedule_defaults(self.settings.get("schedule"))

    def set_setting(self, key, value):
        self.settings[key] = value
        self.save_settings()

    def save_settings(self):
        safeio.write_json(self._settings_path(), self.settings)

    def save_presets(self):
        safeio.write_json(self._presets_path(), self.presets)

    def save_preset(self, name, config):
        name = (name or "").strip()
        if not name:
            return
        stored = dict(config)
        stored.pop("bank_id", None)
        for existing in self.presets:
            if existing["name"].lower() == name.lower():
                existing["config"] = stored
                break
        else:
            self.presets.append({"id": uuid.uuid4().hex, "name": name,
                                 "config": stored, "created_at": time.time()})
        self.save_presets()

    def delete_preset(self, preset_id):
        self.presets = [p for p in self.presets if p.get("id") != preset_id]
        self.save_presets()

    @staticmethod
    def normalised(config):
        out = dict(config)
        for key in ("subjects", "difficulties", "assessments", "domains", "skills"):
            out[key] = sorted(out.get(key) or ())
        return out

    def resolved_preset(self, preset, config):
        out = self.normalised(config)
        out.update(preset.get("config", {}))
        out["bank_id"] = config.get("bank_id", "")
        bank = self.bank(out["bank_id"])
        if bank:
            subjects = {q.subject for q in bank.questions}
            out["subjects"] = [s for s in out.get("subjects", []) if s in subjects] \
                or sorted(subjects) or ["reading_writing", "math"]
            for key, attr in (("difficulties", "difficulty"), ("domains", "domain"),
                              ("skills", "skill"), ("assessments", "assessment")):
                present = [getattr(q, attr) for q in bank.questions]
                known = {p for p in present if p}
                spelling = {LabelCase.key(p): p for p in present if p}
                chosen = {spelling.get(LabelCase.key(v), v)
                          for v in (out.get(key) or ())}
                out[key] = sorted(chosen & known)
        return self.normalised(out)

    def answers_by_day(self):
        out = {}
        for rows in self.history.values():
            for row in rows:
                if row.get("backfilled"):
                    continue
                day = datetime.datetime.fromtimestamp(row.get("at", 0)).date()
                out[day] = out.get(day, 0) + 1
        return out

    def schedule(self):
        return schedule_defaults(self.settings.get("schedule"))

    def streak(self, now=None):
        return evaluate_streak(self.answers_by_day(), self.schedule(), now=now,
                               excused=self.excused_days())

    def excused_days(self):
        out = []
        for value in self.settings.get("excusedDays", []) or []:
            try:
                out.append(_as_day(value))
            except (ValueError, OSError, TypeError):
                try:
                    out.append(datetime.date.fromisoformat(str(value)[:10]))
                except ValueError:
                    continue
        return out

    def return_gap(self, now=None):
        return mercy_gap(self.answers_by_day(), self.schedule(),
                         excused=self.excused_days(), now=now)

    def restorable_gap(self, now=None):
        if not self.settings.get("showQuestionStreak", True):
            return None
        gap = self.return_gap(now=now)
        if not gap or not gap["restorable"] or gap["days_away"] < RESTORE_AFTER:
            return None
        if _same_day(self.settings.get("restoreOfferedFor"), gap["last_active"]):
            return None
        return gap

    def restore_streak(self, gap):
        known = set(self.excused_days())
        added = [d for d in gap["missed"] if d not in known]
        days = sorted(known | set(added))
        if len(days) > 600:
            days = days[-600:]
        self.settings["excusedDays"] = [_day_stamp(d) for d in days]
        self.settings["restoreOfferedFor"] = _day_stamp(gap["last_active"])
        self.save_settings()
        return len(added)

    def decline_restore(self, gap):
        self.settings["restoreOfferedFor"] = _day_stamp(gap["last_active"])
        self.save_settings()

    DAILY_DEFAULTS = {"enabled": False, "wordsPerDay": 10, "completedDays": []}

    def daily_plan(self):
        plan = dict(self.DAILY_DEFAULTS)
        plan.update(self.settings.get("vocabDaily") or {})
        low, high = vocab.DAILY_RANGE
        plan["wordsPerDay"] = max(low, min(high, int(plan.get("wordsPerDay", 10))))
        plan["completedDays"] = list(plan.get("completedDays") or [])
        return plan

    def _write_daily_plan(self, plan):
        self.set_setting("vocabDaily", plan)

    def set_daily_enabled(self, on):
        plan = self.daily_plan()
        plan["enabled"] = bool(on)
        self._write_daily_plan(plan)

    def set_words_per_day(self, count):
        plan = self.daily_plan()
        low, high = vocab.DAILY_RANGE
        plan["wordsPerDay"] = max(low, min(high, int(count)))
        self._write_daily_plan(plan)

    def daily_set(self, deck_id, now=None):
        deck = self.decks.deck(deck_id)
        if deck is None:
            return vocab.DailySet()
        return vocab.daily_set(deck.cards, self.daily_plan()["wordsPerDay"], now)

    def deal_daily(self, deck_id, now=None):
        deck = self.decks.deck(deck_id)
        if deck is None:
            return vocab.DailySet()
        words_per_day = self.daily_plan()["wordsPerDay"]
        wanted = set(vocab.to_introduce(deck.cards, words_per_day, now))
        if wanted:
            stamp = _day_stamp(time.time() if now is None else now)
            for card in deck.cards:
                if card.id in wanted:
                    card.introduced_on = stamp
            self.decks.save(deck)
        today = self.daily_set(deck_id, now)
        self.record_daily_if_complete(today, now)
        return today

    def record_daily_if_complete(self, day_set, now=None):
        if not day_set.is_complete(time.time() if now is None else now):
            return
        today = _as_day(time.time() if now is None else now)
        plan = self.daily_plan()
        if any(_as_day(d) == today for d in plan["completedDays"]):
            return
        plan["completedDays"] = sorted(plan["completedDays"] + [_day_stamp(today)])
        self._write_daily_plan(plan)

    def note_daily_progress(self, deck_id, now=None):
        if not self.daily_plan()["enabled"]:
            return
        self.record_daily_if_complete(self.daily_set(deck_id, now), now)

    def clear_todays_deal(self, deck_id, now=None):
        deck = self.decks.deck(deck_id)
        if deck is None:
            return
        today = _as_day(time.time() if now is None else now)
        for card in deck.cards:
            if card.introduced_on and _as_day(card.introduced_on) == today:
                card.introduced_on = 0
        self.decks.save(deck)

    def clear_daily_history(self):
        plan = self.daily_plan()
        plan["completedDays"] = []
        self._write_daily_plan(plan)

    def clear_all_vocabulary_progress(self, deck_id):
        self.clear_daily_history()
        deck = self.decks.deck(deck_id)
        if deck is None:
            return
        for card in deck.cards:
            card.introduced_on = 0
            card.times_seen = 0
            card.times_correct = 0
            card.times_glanced = 0
            card.times_turned = 0
            card.last_seen = 0
            card.last_answer_correct = False
        self.decks.save(deck)

    def last_active_day(self):
        days = [d for d, n in self.answers_by_day().items() if n > 0]
        for value in (self.settings.get("vocabDaily", {}) or {}).get("completedDays", []) or []:
            try:
                days.append(_as_day(value))
            except (ValueError, OSError, TypeError):
                continue
        graded = [c.last_seen for deck in self.decks.decks for c in deck.cards
                  if getattr(c, "last_seen", 0)]
        if graded:
            try:
                days.append(_as_day(max(graded)))
            except (ValueError, OSError, TypeError):
                pass
        return max(days) if days else None

    def welcome_back(self, now=None):
        last = self.last_active_day()
        if last is None:
            return None
        now = now or datetime.datetime.now()
        today = now.date() if isinstance(now, datetime.datetime) else now
        away = (today - last).days
        if away < WELCOME_AFTER:
            return None
        if _same_day(self.settings.get("welcomeBackFor"), last):
            return None

        worst = []
        for bank in self.banks:
            for row in self.statistics(bank.id).get("weakest", []):
                if row.get("attempts", 0) >= 3:
                    worst.append((row.get("label", ""), row.get("accuracy", 1.0)))
        worst.sort(key=lambda pair: pair[1])
        skills, seen = [], set()
        for label, _ in worst:
            if label and label not in seen:
                seen.add(label)
                skills.append(label)
            if len(skills) == 2:
                break
        return {"last_active": last, "days_away": away, "skills": skills}

    def dismiss_welcome_back(self, welcome):
        self.settings["welcomeBackFor"] = _day_stamp(welcome["last_active"])
        self.save_settings()

    BACKUP_NUDGE_AFTER_ANSWERS = 25
    BACKUP_NUDGE_AFTER_DAYS = 30

    def record_backup(self):
        self.settings["lastBackupAt"] = time.time()
        self.settings["backupNudgeFor"] = None
        self.save_settings()

    def days_since_backup(self, now=None):
        last = self.settings.get("lastBackupAt")
        if not last:
            return None
        now = time.time() if now is None else now
        return max(0, int((now - float(last)) // 86400))

    def backup_is_worth_mentioning(self, now=None):
        now = time.time() if now is None else now
        rows = [r for rows in self.history.values() for r in rows]
        if len(rows) < self.BACKUP_NUDGE_AFTER_ANSWERS:
            return False
        dismissed = self.settings.get("backupNudgeFor")
        if dismissed and (now - float(dismissed)) < 14 * 86400:
            return False
        last = self.settings.get("lastBackupAt")
        if not last:
            return True
        if (now - float(last)) < self.BACKUP_NUDGE_AFTER_DAYS * 86400:
            return False
        newest = max((float(r.get("at", 0)) for r in rows), default=0)
        return newest > float(last)

    def dismiss_backup_nudge(self):
        self.settings["backupNudgeFor"] = time.time()
        self.save_settings()

    def rhythm(self, now=None):
        now = time.time() if now is None else now
        rows = [r for rows in self.history.values() for r in rows
                if not r.get("backfilled")]
        out = {"today": 0, "streak": 0, "best_streak": 0, "week": 0}
        if not rows:
            return out

        def day(ts):
            return datetime.date.fromtimestamp(ts)

        today = day(now)
        out["today"] = sum(1 for r in rows if day(r.get("at", 0)) == today)
        out["week"] = sum(1 for r in rows
                          if (today - day(r.get("at", 0))).days <= 6)

        days = sorted({day(r.get("at", 0)) for r in rows})
        run = best = 1
        for a, b in zip(days, days[1:]):
            run = run + 1 if (b - a).days == 1 else 1
            best = max(best, run)
        out["best_streak"] = best

        if (today - days[-1]).days > 1:
            return out
        streak, cursor = 1, days[-1]
        for d in reversed(days[:-1]):
            if (cursor - d).days == 1:
                streak += 1
                cursor = d
            else:
                break
        out["streak"] = streak
        return out

    def save_bank(self, bank: Bank):
        os.makedirs(self.bank_dir(bank.id), exist_ok=True)
        safeio.write_json(os.path.join(self.bank_dir(bank.id), "bank.json"),
                          {"id": bank.id, "name": bank.name, "created_at": bank.created_at,
                           "parser_version": getattr(bank, "parser_version", 0),
                           "questions": [q.to_dict() for q in bank.questions]})

    def delete_bank(self, bank: Bank):
        self.banks = [b for b in self.banks if b.id != bank.id]
        self.progress.pop(bank.id, None)
        remove_tree(self.bank_dir(bank.id))
        for p in (os.path.join(self.progress_dir, bank.id + ".json"),
                  os.path.join(self.notes_dir, bank.id + ".json"),
                  os.path.join(self.history_dir, bank.id + ".json"),
                  os.path.join(self.sessions_dir, bank.id + ".json")):
            if os.path.exists(p):
                os.remove(p)

    def rename_bank(self, bank: Bank, name):
        bank.name = name
        self.save_bank(bank)

        saved = self.saved_session(bank.id)
        if saved is not None and saved.bank_name != name:
            saved.bank_name = name
            self.save_session(saved)

        self.decks.rename_source_bank(bank.id, name)

    def _load_progress(self, bank_id):
        path = os.path.join(self.progress_dir, safe_file_stem(bank_id) + ".json")
        return safeio.read_json(path, {}, self.note_damaged, expect=dict)

    def save_progress(self, bank_id):
        safeio.write_json(os.path.join(self.progress_dir, safe_file_stem(bank_id) + ".json"),
                          self.progress.get(bank_id, {}))

    def seen(self, bank_id, qid):
        return self.progress.get(bank_id, {}).get(qid, {}).get("times_seen", 0) > 0

    def last_wrong(self, bank_id, qid):
        r = self.progress.get(bank_id, {}).get(qid)
        return bool(r) and r.get("times_seen", 0) > 0 and not r.get("last_correct", False)

    def seen_count(self, bank_id):
        return sum(1 for r in self.progress.get(bank_id, {}).values() if r.get("times_seen", 0) > 0)

    def _history_path(self, bank_id):
        return os.path.join(self.history_dir, safe_file_stem(bank_id) + ".json")

    def _load_history(self, bank_id):
        return safeio.read_json(self._history_path(bank_id), [], self.note_damaged, expect=list)

    def save_history(self, bank_id):
        os.makedirs(self.history_dir, exist_ok=True)
        safeio.write_json(self._history_path(bank_id), self.history.get(bank_id, []))

    def backfill_history(self, bank_id):
        bank = self.bank(bank_id)
        records = self.progress.get(bank_id, {})
        if not bank or self.history.get(bank_id) or not records \
                or os.path.exists(self._history_path(bank_id)):
            return
        by_id = {q.id: q for q in bank.questions}
        rows = []
        for qid, r in records.items():
            q = by_id.get(qid)
            if not q or r.get("times_seen", 0) <= 0:
                continue
            when = r.get("last_seen", time.time())
            for i in range(r.get("times_seen", 0)):
                rows.append({"question_id": qid,
                             "correct": i < r.get("times_correct", 0),
                             "at": when, "seconds": 0.0, "skill": q.skill,
                             "domain": q.domain, "difficulty": q.difficulty,
                             "subject": q.subject, "backfilled": True})
        if not rows:
            return
        self.history[bank_id] = sorted(rows, key=lambda r: r["at"])
        self.save_history(bank_id)

    def statistics(self, bank_id, subjects=None, filter=None):
        self.backfill_history(bank_id)
        bank = self.bank(bank_id)
        if not bank:
            return build_statistics([], None, subjects, filter)
        return build_statistics(self.history.get(bank_id, []), bank, subjects, filter)

    def reset_cost(self, bank_id):
        records = self.progress.get(bank_id, {})
        seen = sum(1 for r in records.values() if r.get("times_seen"))
        answers = sum(int(r.get("times_seen", 0)) for r in records.values())
        return seen, answers

    def reset_progress(self, bank_id):
        records = self.progress.get(bank_id, {})
        for qid, record in list(records.items()):
            if record.get("set_aside"):
                records[qid] = {"set_aside": True}
            else:
                records.pop(qid, None)
        self.save_progress(bank_id)
        self.clear_history(bank_id)

    def clear_history(self, bank_id):
        self.history[bank_id] = []
        self.save_history(bank_id)

    def reread_stale_banks(self, progress=None):
        done = []
        for bank in list(self.banks):
            if self.needs_reread(bank):
                updated, _ = self.reread(bank.id, progress=progress)
                if updated:
                    done.append(updated)
        return done

    def needs_reread(self, bank):
        return (getattr(bank, "parser_version", 0) < PARSER_VERSION
                and bool(self.archived_sources(bank.id)))

    def archived_sources(self, bank_id):
        d = self.sources_dir(bank_id)
        if not os.path.isdir(d):
            return []
        return sorted(os.path.join(d, f) for f in os.listdir(d)
                      if f.lower().endswith(".pdf"))

    def reread(self, bank_id, progress=None):
        bank = self.bank(bank_id)
        sources = self.archived_sources(bank_id)
        if not bank or not sources:
            return None, [L("Nothing stored to read again.")]

        images = self.images_dir(bank_id)
        collected, warnings, seen = [], [], set()
        for i, path in enumerate(sources):
            share = 1.0 / len(sources)
            def sub(p, msg, i=i, s=share):
                if progress:
                    progress(i * s + p * s, msg)

            try:
                restore_embedded_images(path, images)
                questions, warns = import_one(path, images, sub)
            except Exception as e:
                warnings.append(f"{os.path.basename(path)}: {e}")
                continue
            warnings += warns
            for q in questions:
                if q.id not in seen:
                    seen.add(q.id)
                    collected.append(q)

        if not collected:
            return None, [L("Could not read that set again; it has been left as it was.")]
        if self.notes.get(bank_id):
            self.notes[bank_id], taken_off = rehome_annotations(
                self.notes[bank_id], bank.questions, collected)
            self.highlights_taken_off += taken_off
            self.save_notes(bank_id)
        self._rehome_other_profiles(bank_id, bank.questions, collected)
        bank.questions = collected
        bank.parser_version = PARSER_VERSION
        self.save_bank(bank)
        return bank, warnings

    def _rehome_other_profiles(self, bank_id, old_questions, new_questions):
        for other in self.profiles.profiles:
            if other["id"] == self.profile["id"]:
                continue
            folder = self.profiles.directory(other["id"])
            path = os.path.join(folder, "Notes", safe_file_stem(bank_id) + ".json")
            try:
                with open(path, encoding="utf-8") as f:
                    notes = json.load(f)
            except (OSError, ValueError):
                continue
            if not isinstance(notes, list) or not notes:
                continue
            carried, taken_off = rehome_annotations(notes, old_questions, new_questions)
            safeio.write_json(path, carried)
            if taken_off:
                pending = os.path.join(folder, TAKEN_OFF_FILE)
                try:
                    with open(pending, encoding="utf-8") as f:
                        was = int(f.read().strip() or 0)
                except (OSError, ValueError):
                    was = 0
                safeio.atomic_write_text(pending, str(was + taken_off))

    def _notes_path(self, bank_id):
        return os.path.join(self.notes_dir, safe_file_stem(bank_id) + ".json")

    def _load_notes(self, bank_id):
        return safeio.read_json(self._notes_path(bank_id), [], self.note_damaged, expect=list)

    def save_notes(self, bank_id):
        os.makedirs(self.notes_dir, exist_ok=True)
        safeio.write_json(self._notes_path(bank_id), self.notes.get(bank_id, []))

    def annotations(self, bank_id, qid):
        return sorted((a for a in self.notes.get(bank_id, []) if a["question_id"] == qid),
                      key=lambda a: (a.get("block", 0), a.get("start", 0)))

    def annotation_count(self, bank_id, qid):
        return sum(1 for a in self.notes.get(bank_id, []) if a["question_id"] == qid)

    def add_annotation(self, bank_id, qid, field, block, start, end,
                       note="", color=0):
        items = self.notes.setdefault(bank_id, [])
        merged = {"id": uuid.uuid4().hex, "question_id": qid, "field": field,
                  "block": block, "start": start, "end": end,
                  "note": note, "color": color}
        keep = []
        for a in items:
            if (a["question_id"] == qid and a.get("field") == field
                    and a.get("block", 0) == block
                    and a["start"] <= merged["end"] and a["end"] >= merged["start"]):
                merged["start"] = min(merged["start"], a["start"])
                merged["end"] = max(merged["end"], a["end"])
                if not merged["note"]:
                    merged["note"] = a.get("note", "")
                continue
            keep.append(a)
        bank = self.bank(bank_id)
        q = next((q for q in bank.questions if q.id == qid), None) if bank else None
        words = marked_words(merged, q) if q else None
        if words is not None:
            merged["marked"] = words
        keep.append(merged)
        self.notes[bank_id] = keep
        self.save_notes(bank_id)
        return merged

    def update_annotation(self, bank_id, ann_id, note=None, color=None):
        for a in self.notes.get(bank_id, []):
            if a["id"] == ann_id:
                if note is not None:
                    a["note"] = note
                if color is not None:
                    a["color"] = color
                self.save_notes(bank_id)
                return

    def remove_annotation(self, bank_id, ann_id):
        items = self.notes.get(bank_id, [])
        self.notes[bank_id] = [a for a in items if a["id"] != ann_id]
        self.save_notes(bank_id)

    def clear_annotations(self, bank_id, qid):
        items = self.notes.get(bank_id, [])
        self.notes[bank_id] = [a for a in items if a["question_id"] != qid]
        self.save_notes(bank_id)

    def is_set_aside(self, bank_id, qid):
        return bool(self.progress.get(bank_id, {}).get(qid, {}).get("set_aside"))

    def toggle_set_aside(self, bank_id, qid):
        recs = self.progress.setdefault(bank_id, {})
        r = recs.setdefault(qid, {"times_seen": 0, "times_correct": 0, "last_correct": False})
        r["set_aside"] = not r.get("set_aside", False)
        self.save_progress(bank_id)

    def set_aside_count(self, bank_id):
        bank = self.bank(bank_id)
        if not bank:
            return 0
        return sum(1 for q in bank.questions if self.is_set_aside(bank_id, q.id))

    def set_aside_questions(self, bank_id):
        bank = self.bank(bank_id)
        if not bank:
            return []
        return [q for q in bank.questions if self.is_set_aside(bank_id, q.id)]

    def clear_set_aside(self, bank_id):
        for r in self.progress.get(bank_id, {}).values():
            r.pop("set_aside", None)
        self.save_progress(bank_id)

    def record(self, bank_id, qid, correct):
        recs = self.progress.setdefault(bank_id, {})
        r = recs.setdefault(qid, {"times_seen": 0, "times_correct": 0, "last_correct": False})
        r["times_seen"] += 1
        if correct:
            r["times_correct"] += 1
        r["last_correct"] = bool(correct)
        r["last_seen"] = time.time()

    def stored_files(self, bank_id):
        out = []
        for d, kind in ((self.sources_dir(bank_id), "source"),
                        (self.exports_dir(bank_id), "export")):
            if not os.path.isdir(d):
                continue
            for name in os.listdir(d):
                if not name.lower().endswith(".pdf"):
                    continue
                p = os.path.join(d, name)
                out.append({"path": p, "name": name, "kind": kind,
                            "bytes": os.path.getsize(p), "modified": os.path.getmtime(p)})
        out.sort(key=lambda f: f["modified"], reverse=True)
        return out

    def archive_source(self, path, bank_id):
        d = self.sources_dir(bank_id)
        os.makedirs(d, exist_ok=True)
        dest = os.path.join(d, os.path.basename(path))
        if os.path.exists(dest):
            if os.path.getsize(dest) == os.path.getsize(path):
                return
            stem = os.path.splitext(os.path.basename(path))[0]
            dest = os.path.join(d, f"{stem}-{int(time.time())}.pdf")
        try:
            shutil.copy2(path, dest)
            os.chmod(dest, os.stat(dest).st_mode | stat.S_IWRITE)
        except OSError:
            pass

    def session_path(self, bank_id):
        return os.path.join(self.sessions_dir, safe_file_stem(bank_id) + ".json")

    def save_session(self, s: Session):
        if s.finished:
            return
        d = self._session_fields(s)
        d["question_ids"] = [q.id for q in s.questions]
        safeio.write_json(self.session_path(s.bank_id), d)

    @staticmethod
    def _session_fields(s):
        return {
                "bank_id": s.bank_id, "bank_name": s.bank_name, "config": s.config,
                "attempts": [asdict(a) for a in s.attempts],
                "index": s.index, "started_at": s.started_at,
                "last_saved_at": time.time(),
                "seconds_remaining": s.seconds_remaining,
                "partner_id": s.partner_id,
                "turn_names": list(s.turn_names),
                "turn_accents": list(s.turn_accents),
                "partner_index": s.partner_index,
                "seats_finished": list(s.seats_finished),
                "modules": [m.to_dict() for m in s.modules],
                "adaptive": {k: {"lower": [q.id for q in v.lower],
                                 "upper": [q.id for q in v.upper]}
                             for k, v in s.adaptive.items()},
            }

    def saved_session(self, bank_id):
        path = self.session_path(bank_id)
        if not os.path.exists(path):
            return None
        d = safeio.read_json(path, None, self.note_damaged, expect=dict)
        if d is None:
            return None
        try:
            bank = self.bank(bank_id)
            if not bank:
                return None
            by_id = {q.id: q for q in bank.questions}
            return self._rebuild_session(d, by_id, d["question_ids"])
        except Exception:
            return None

    @staticmethod
    def _rebuild_session(d, by_id, question_ids):
        bank_id = d["bank_id"]
        questions = [by_id[i] for i in question_ids if i in by_id]
        if len(questions) != len(question_ids):
            return None
        started = d.get("started_at", time.time())
        session = Session(bank_id=bank_id, bank_name=d["bank_name"], config=d["config"],
                       questions=questions,
                       attempts=[_attempt_from(a) for a in d["attempts"]],
                       index=d.get("index", 0), started_at=started,
                       last_saved_at=d.get("last_saved_at", started),
                       seconds_remaining=d.get("seconds_remaining", 0))
        session.partner_id = d.get("partner_id", "")
        session.turn_names = list(d.get("turn_names", []))
        session.turn_accents = list(d.get("turn_accents", []))
        session.partner_index = d.get("partner_index", 1)
        session.seats_finished = list(d.get("seats_finished", []))
        from .fulltest import ExamModule as _Module
        session.modules = [_Module.from_dict(m) for m in d.get("modules", [])]
        from .fulltest import AdaptiveOption as _Option
        session.adaptive = {}
        for key, forms in (d.get("adaptive") or {}).items():
            lower = [by_id[i] for i in forms.get("lower", []) if i in by_id]
            upper = [by_id[i] for i in forms.get("upper", []) if i in by_id]
            if len(lower) == len(forms.get("lower", [])) and \
                    len(upper) == len(forms.get("upper", [])):
                session.adaptive[key] = _Option(key, lower, upper)
        session.repair_indices()
        return session

    SITTINGS_KEPT = 300

    @property
    def sittings_dir(self):
        return os.path.join(self.profile_root, "Sittings")

    def record_sitting(self, s: Session):
        try:
            os.makedirs(self.sittings_dir, exist_ok=True)
            d = self._session_fields(s)
            d["questions"] = [q.to_dict() for q in s.questions]
            d["finished_at"] = time.time()
            d["id"] = uuid.uuid4().hex
            stamp = time.strftime("%Y%m%d-%H%M%S", time.gmtime(d["finished_at"]))
            safeio.write_json(os.path.join(self.sittings_dir, f"{stamp}-{d['id']}.json"), d)
            for old in self._sitting_files()[self.SITTINGS_KEPT:]:
                os.remove(old)
        except OSError:
            pass

    def _sitting_files(self):
        try:
            names = [n for n in os.listdir(self.sittings_dir) if n.endswith(".json")]
        except OSError:
            return []
        return [os.path.join(self.sittings_dir, n) for n in sorted(names, reverse=True)]

    def load_sitting(self, path):
        d = safeio.read_json(path, None, self.note_damaged, expect=dict)
        if d is None:
            return None
        try:
            questions = [Question.from_dict(q) for q in d["questions"]]
            s = self._rebuild_session(d, {q.id: q for q in questions}, [q.id for q in questions])
        except Exception:
            return None
        if s is not None:
            s.finished = True
            s.finished_at = d.get("finished_at", s.started_at)
        return s

    def sittings(self, bank_id):
        out = []
        for path in self._sitting_files():
            s = self.load_sitting(path)
            if s is None or s.bank_id != bank_id:
                continue
            out.append({"path": path, "title": s.display_title,
                        "started_at": s.started_at, "finished_at": s.finished_at,
                        "correct": sum(1 for q, a in zip(s.questions, s.attempts)
                                       if is_correct(q, a.response)),
                        "total": len(s.questions)})
        return out

    def sets_with_saved_sittings(self):
        waiting = [(b, s) for b in self.banks
                   for s in (self.saved_session(b.id),) if s is not None]
        waiting.sort(key=lambda pair: pair[1].last_saved_at, reverse=True)
        return waiting

    def discard_session(self, bank_id):
        p = self.session_path(bank_id)
        if os.path.exists(p):
            os.remove(p)

    def finish_session(self, s: Session):
        s.finished = True
        now = time.time()
        rows = self.history.setdefault(s.bank_id, [])
        partner_rows = []
        for i, (q, a) in enumerate(zip(s.questions, s.attempts)):
            if not a.answered:
                continue
            correct = is_correct(q, a.response)
            row = {"question_id": q.id, "correct": correct, "at": now,
                   "seconds": getattr(a, "seconds_spent", 0.0),
                   "skill": q.skill, "domain": q.domain,
                   "difficulty": q.difficulty, "subject": q.subject}
            if s.is_double and s.turn(i) == 1:
                partner_rows.append(row)
                continue
            self.record(s.bank_id, q.id, correct)
            rows.append(row)
        self.save_progress(s.bank_id)
        self.save_history(s.bank_id)
        if s.is_double and partner_rows:
            self._record_for_partner(s.partner_id, s.bank_id, partner_rows)
        self.discard_session(s.bank_id)
        self.record_sitting(s)

    def _record_for_partner(self, profile_id, bank_id, rows):
        root = self.profiles.directory(profile_id)
        stem = safe_file_stem(bank_id)
        progress_path = os.path.join(root, "Progress", stem + ".json")
        history_path = os.path.join(root, "History", stem + ".json")  # data, not copy: a folder
        os.makedirs(os.path.dirname(progress_path), exist_ok=True)
        os.makedirs(os.path.dirname(history_path), exist_ok=True)

        def read(path, empty):
            return safeio.read_json(path, empty, self.note_damaged, expect=type(empty))

        records = read(progress_path, {})
        history = read(history_path, [])
        for row in rows:
            rec = records.setdefault(row["question_id"], {
                "times_seen": 0, "times_correct": 0, "last_correct": False})
            rec["times_seen"] = int(rec.get("times_seen", 0)) + 1
            if row["correct"]:
                rec["times_correct"] = int(rec.get("times_correct", 0)) + 1
            rec["last_correct"] = bool(row["correct"])
            rec["last_seen"] = row["at"]
            history.append(row)
        safeio.write_json(progress_path, records)
        safeio.write_json(history_path, history)

    def _eligible(self, config):
        bank = self.bank(config["bank_id"])
        if not bank:
            return None, []
        subjects = set(config.get("subjects", ["math", "reading_writing"]))
        difficulties = set(config.get("difficulties") or ())
        assessments = set(config.get("assessments") or ())
        domains = set(config.get("domains") or ())
        skills = set(config.get("skills") or ())
        one = config.get("skill_filter")
        if one and not skills:
            skills = {one}
        pool = [q for q in bank.questions
                if q.subject in subjects
                and (not difficulties or q.difficulty in difficulties)
                and (not assessments or q.assessment in assessments)
                and (not domains or q.domain in domains)
                and (not skills or q.skill in skills)]
        return bank, pool

    def _tiers(self, config):
        bank, pool = self._eligible(config)
        if bank is None:
            return []
        return self._tiers_of(bank, pool, config)

    def _tiers_of(self, bank, pool, config):
        sel = config.get("selection", "new_first")
        if sel == "all":
            return [pool]
        if sel == "review_missed":
            return [[q for q in pool if self.last_wrong(bank.id, q.id)]]
        if sel == "set_aside":
            return [[q for q in pool if self.is_set_aside(bank.id, q.id)]]
        if sel == "unseen_only":
            return [[q for q in pool if not self.seen(bank.id, q.id)
                     and not self.is_set_aside(bank.id, q.id)]]
        if sel == "due_for_review":
            now = time.time()
            records = self.progress.get(bank.id, {})
            due = [(q, overdue_by(records[q.id], now)) for q in pool
                   if q.id in records and is_due(records[q.id], now)]
            due.sort(key=lambda pair: pair[1], reverse=True)
            return [[q for q, _ in due]]
        if sel == "weakest_skills":
            weak = set(self.weakest_skills(bank.id))
            if not weak:
                return []
            narrowed = [q for q in pool if q.skill in weak]
            missed = [q for q in narrowed if self.last_wrong(bank.id, q.id)]
            unseen = [q for q in narrowed if not self.seen(bank.id, q.id)]
            rest = [q for q in narrowed
                    if self.seen(bank.id, q.id) and not self.last_wrong(bank.id, q.id)]
            return [missed, unseen, rest]

        unseen = [q for q in pool if not self.seen(bank.id, q.id)]
        missed = [q for q in pool if self.seen(bank.id, q.id) and self.last_wrong(bank.id, q.id)]
        rest = [q for q in pool if self.seen(bank.id, q.id) and not self.last_wrong(bank.id, q.id)]
        return [unseen, missed, rest]

    def weakest_skills(self, bank_id, limit=3, below=0.9):
        bank = self.bank(bank_id)
        if not bank:
            return []
        stats = build_statistics(self.history.get(bank_id, []), bank)
        return [row["label"] for row in stats["weakest"] if row["accuracy"] < below][:limit]

    def next_review_due(self, bank_id):
        bank = self.bank(bank_id)
        if not bank:
            return None
        ids = {q.id for q in bank.questions}
        records = [r for qid, r in self.progress.get(bank_id, {}).items() if qid in ids]
        return next_due(records)

    def available_count(self, config):
        return sum(len(t) for t in self._tiers(config))

    def available_in(self, config, subject):
        one = dict(config)
        one["subjects"] = [subject]
        one["sectionCounts"] = {}
        return self.available_count(one)

    def _draw_split(self, config, shuffled):
        out = []
        for subject in ("reading_writing", "math"):
            if subject not in (config.get("subjects") or []):
                continue
            want = section_count(config, subject)
            if want <= 0:
                continue
            one = dict(config)
            one["subjects"] = [subject]
            tiers = self._tiers(one)
            if shuffled:
                tiers = [random.sample(t, len(t)) for t in tiers]
            pool = [q for t in tiers for q in t]
            out += pool[:want]
        return out

    def split_draw(self, config):
        return len(self._draw_split(config, shuffled=False))

    def selection_counts(self, config, modes):
        bank, pool = self._eligible(config)
        if bank is None:
            return {mode: 0 for mode in modes}
        counts = {}
        for mode in modes:
            probe = dict(config)
            probe["selection"] = mode
            counts[mode] = sum(len(t) for t in self._tiers_of(bank, pool, probe))
        return counts

    def planned_sitting(self, config):
        if has_section_split(config):
            drawn = self._draw_split(config, shuffled=False)
        else:
            pool = [q for t in self._tiers(config) for q in t]
            n = max(1, min(int(config.get("count", 20)), len(pool))) if pool else 0
            drawn = pool[:n]
        rw = sum(1 for q in drawn if q.subject == "reading_writing")
        math = sum(1 for q in drawn if q.subject == "math")
        return rw, math, pace_minutes(rw, math)

    def start_session(self, config):
        bank = self.bank(config["bank_id"])
        if not bank:
            return None
        partner = None
        if config.get("partnerProfileID"):
            partner = self.partner(config["partnerProfileID"])
            if partner is None:
                return None
            config = dict(config)
            config["full_test"] = False
            config["adaptive"] = False
        if config.get("full_test"):
            built = self._build_full_test(config, bank)
            if built is None:
                return None
            questions, modules, adaptive = built
            timed_config = dict(config)
            timed_config["timed"] = True
            timed_config["grading"] = "at_end"
            s = Session(bank_id=bank.id, bank_name=bank.name,
                        config=timed_config, questions=questions,
                        attempts=[Attempt(q.id) for q in questions])
            s.modules = modules
            s.adaptive = adaptive
            self.save_session(s)
            return s

        mix = config.get("mix", "pdf_order")
        shuffling = mix in ("mixed", "shuffled_in_section")

        if has_section_split(config):
            chosen = self._draw_split(config, shuffled=shuffling)
            if not chosen:
                return None
            return self._start_sitting(config, bank, chosen, partner)

        tiers = self._tiers(config)
        if shuffling:
            tiers = [random.sample(t, len(t)) for t in tiers]
        pool = [q for t in tiers for q in t]
        if not pool:
            return None
        n = max(1, min(int(config.get("count", 20)), len(pool)))
        return self._start_sitting(config, bank, pool[:n], partner)

    def _start_sitting(self, config, bank, chosen, partner):
        chosen = list(chosen)
        mix = config.get("mix", "pdf_order")
        order = {q.id: i for i, q in enumerate(bank.questions)}
        if mix == "pdf_order":
            chosen.sort(key=lambda q: order.get(q.id, 0))
        elif mix == "sequential":
            chosen.sort(key=lambda q: (0 if q.subject == "reading_writing" else 1,
                                       order.get(q.id, 0)))
        elif mix == "shuffled_in_section":
            random.shuffle(chosen)
            chosen.sort(key=lambda q: 0 if q.subject == "reading_writing" else 1)
        else:
            random.shuffle(chosen)

        s = Session(bank_id=bank.id, bank_name=bank.name, config=dict(config),
                    questions=chosen, attempts=[Attempt(q.id) for q in chosen])
        s.seconds_remaining = float(config.get("minutes", 32)) * 60 if config.get("timed") else 0
        if partner is not None:
            s.partner_id = partner["id"]
            s.turn_names = [profile_display_name(self.profile),
                            profile_display_name(partner)]
            s.turn_accents = [int(self.profile.get("accent", 0)),
                              int(partner.get("accent", 0))]
            positions = s.positions(1)
            s.partner_index = positions[0] if positions else 1
        self.save_session(s)
        return s

    def _section_pool(self, config, subject):
        narrowed = dict(config)
        narrowed.update(subjects=[subject], selection="new_first", difficulties=[],
                        assessments=[], domains=[], skills=[], skill_filter=None)
        tiers = self._tiers(narrowed)
        return [q for tier in tiers for q in random.sample(tier, len(tier))]

    def library_layout(self):
        layout = library.LibraryLayout.from_dict(
            self.settings.get("libraryLayout"))
        layout.reconcile(self.banks)
        return layout

    def save_library_layout(self, layout):
        self.set_setting("libraryLayout", layout.to_dict())

    def shelved_banks(self):
        layout = self.library_layout()
        by_id = {b.id: b for b in self.banks}
        seen = {b.id: self.seen_count(b.id) for b in self.banks}
        out = [(shelf, library.arrange(shelf.bank_ids, layout.order, by_id, seen))
               for shelf in layout.shelves]
        loose = library.arrange(layout.unshelved, layout.order, by_id, seen)
        if loose or not layout.shelves:
            out.append((None, loose))
        return out

    def full_test_readiness(self, config):
        return fulltest.Readiness(
            len(self._section_pool(config, "reading_writing")),
            len(self._section_pool(config, "math")))

    def adaptive_readiness(self, config):
        counts = {}
        for subject in fulltest.SUBJECTS:
            tally = {label: 0 for label in fulltest.DIFFICULTIES}
            for question in self._section_pool(config, subject):
                if question.difficulty in tally:
                    tally[question.difficulty] += 1
            counts[subject] = tally
        return fulltest.AdaptiveReadiness(counts)

    def _difficulty_pools(self, config, subject):
        pools = {label: [] for label in fulltest.DIFFICULTIES}
        for question in self._section_pool(config, subject):
            if question.difficulty in pools:
                pools[question.difficulty].append(question)
        return pools

    def _build_full_test(self, config, bank):
        if config.get("adaptive"):
            firsts, options = {}, {}
            for subject in ("reading_writing", "math"):
                pools = self._difficulty_pools(config, subject)
                size = fulltest.adaptive_module_size(subject)
                one = fulltest.draw(fulltest.MIXED, size, pools)
                lower = fulltest.draw(fulltest.LOWER, size, pools)
                upper = fulltest.draw(fulltest.UPPER, size, pools)
                if one is None or lower is None or upper is None:
                    return None
                firsts[subject] = one
                options[subject] = (lower, upper)
            laid = fulltest.modules(
                firsts["reading_writing"] + options["reading_writing"][0],
                firsts["math"] + options["math"][0])
            if laid is None:
                return None
            questions, modules = laid
            adaptive = {}
            for module in modules:
                if module.number != 2:
                    continue
                lower, upper = options[module.subject]
                adaptive[module.id] = fulltest.AdaptiveOption(
                    module.id, list(lower), list(upper))
            return questions, modules, adaptive

        laid = fulltest.modules(self._section_pool(config, "reading_writing"),
                                self._section_pool(config, "math"))
        if laid is None:
            return None
        questions, modules = laid
        return questions, modules, {}

    def partner(self, profile_id):
        if not profile_id or profile_id == self.profile.get("id"):
            return None
        return next((p for p in self.profiles.profiles
                     if p.get("id") == profile_id), None)

    def import_pdfs(self, paths, into=None, progress=None):
        bank_id = into or uuid.uuid4().hex
        images = self.images_dir(bank_id)
        collected, warnings = [], []

        for i, path in enumerate(paths):
            share = 1.0 / len(paths)

            def sub(p, msg, i=i, share=share):
                if progress:
                    progress(i * share + p * share, msg)

            try:
                restore_embedded_images(path, images)
                qs, warns = import_one(path, images, sub)
                collected += qs
                warnings += warns
                self.archive_source(path, bank_id)
            except Exception as e:
                warnings.append(str(e))

        if not collected:
            if not into:
                remove_tree(self.bank_dir(bank_id))
            raise ValueError(warnings[0] if warnings else "No questions could be read.")

        bank = self.bank(bank_id) if into else None
        if bank:
            known = {q.id for q in bank.questions}
            bank.questions += [q for q in collected if q.id not in known]
            bank.parser_version = PARSER_VERSION
        else:
            seen, unique = set(), []
            for q in collected:
                if q.id not in seen:
                    seen.add(q.id)
                    unique.append(q)
            twin = next((b for b in self.banks if seen == {q.id for q in b.questions}), None)
            if twin is not None:
                remove_tree(self.bank_dir(bank_id))
                raise AlreadyImported(twin.id, Lf(
                    "Every question in that file is already in “%@”, so no new set was made.",
                    twin.name))
            name = (os.path.splitext(os.path.basename(paths[0]))[0] if len(paths) == 1
                    else "%s — %s" % (Lp(len(paths), "%d file", "%d files"),
                                      i18n.short_date()))
            bank = Bank(id=bank_id, name=name, created_at=time.time(), questions=unique,
                        parser_version=PARSER_VERSION)
            self.banks.insert(0, bank)

        self.save_bank(bank)
        bank.questions = LabelCase.unified(bank.questions)
        self.progress.setdefault(bank.id, {})
        from . import portable
        portable.apply_pending(self)
        return bank, warnings


def import_one(path, images_dir, progress=None):
    name = os.path.splitext(os.path.basename(path))[0]

    embedded = read_embedded_bank(path)
    if embedded is not None:
        if progress:
            progress(1.0, Lf("Loaded %d saved questions", len(embedded)))
        return embedded, []

    try:
        doc = fitz.open(path)
    except Exception:
        raise ValueError(
            Lf("“%@” could not be read as a PDF.", name) + "\n\n"
            + L("This app reads the PDF that the College Board Question Bank "
                "produces when you choose Export. Make sure the file still has "
                "its “Question ID” headers and has not been re-saved or "
                "printed to a new PDF."))
    if doc.needs_pass:
        raise ValueError(Lf("“%@” is locked with a password or encryption, so this app "
                            "cannot read it. Export the questions again from the College "
                            "Board Question Bank and import the new file.", name))
    if doc.page_count == 0:
        raise ValueError(Lf("“%@” has no pages.", name))

    raws = pdfparse.parse(doc, progress)
    if not raws:
        raise ValueError(
            Lf("No questions were found in “%@”.", name) + "\n\n"
            + L("This app reads the PDF that the College Board Question Bank "
                "produces when you choose Export. Make sure the file still has "
                "its “Question ID” headers and has not been re-saved or "
                "printed to a new PDF."))

    questions, warnings = [], []
    cache = {}
    counter = [0]

    def convert(blocks, tag, qid):
        out = []
        for b in blocks:
            if b.kind == "table":
                if b.rows:
                    out.append(ContentBlock(kind="table", rows=[list(r) for r in b.rows]))
                continue
            if b.kind == "text":
                if b.text.strip():
                    lead = len(b.text) - len(b.text.lstrip())
                    text = b.text.strip()
                    marks = []
                    for s0, e0 in getattr(b, "underlines", ()):
                        s0, e0 = s0 - lead, e0 - lead
                        s0, e0 = max(0, s0), min(e0, len(text))
                        if e0 > s0:
                            marks.append((s0, e0))
                    out.append(ContentBlock(kind="text", text=text, underlines=marks))
                continue
            key = (b.page, b.rect)
            if key in cache:
                out.append(cache[key])
                continue
            counter[0] += 1
            safe = re.sub(r"[^A-Za-z0-9_-]", "-", f"{qid}-{tag}-{counter[0]}")
            dest = os.path.join(images_dir, safe + ".png")
            res = pdfparse.render_region(doc, b.page, b.rect, dest)
            if not res:
                continue
            px_w, px_h, pt_w = res
            block = ContentBlock(kind="image", image_name=safe + ".png",
                                 pixel_width=px_w, pixel_height=px_h,
                                 point_width=pt_w, centred=bool(b.centred),
                                 inline=_islands(doc, b, images_dir, safe),
                                 x_height=pdfparse.PROSE_X_HEIGHT if b.inline else 0)
            cache[key] = block
            out.append(block)
        return out

    for index, raw in enumerate(raws):
        if progress:
            progress(0.7 + 0.3 * (index + 1) / max(1, len(raws)),
                     Lf("Drawing the figures · %1$d of %2$d",
                        index + 1, len(raws)))
        subject = "math" if "math" in raw.test.lower() else "reading_writing"
        counter[0] = 0
        q = Question(
            id=raw.id or uuid.uuid4().hex,
            subject=subject,
            assessment=raw.assessment or "SAT",
            # data, not copy: what the export calls this test, kept as it
            test=raw.test or ("Math" if subject == "math" else "Reading and Writing"),
            domain=raw.domain, skill=raw.skill, difficulty=raw.difficulty,
            kind=raw.kind,
            stimulus=convert(raw.stimulus, "stim", raw.id),
            prompt=convert(raw.prompt, "prompt", raw.id),
            choices=[Choice(letter=l, blocks=convert(b, "ch" + l, raw.id))
                     for l, b in raw.choices],
            correct_answer=raw.correct_answer,
            rationale=convert(raw.rationale, "rat", raw.id),
            source_name=name,
        )
        if not q.correct_answer:
            warnings.append(Lf("Question %@: no correct answer found — skipped.", q.id))
            continue
        if not q.prompt and not q.stimulus:
            warnings.append(Lf("Question %@: no question text found — skipped.", q.id))
            continue
        if q.kind == "multiple_choice" and len(q.choices) < 2:
            q.kind = "student_response"
            q.choices = []
        questions.append(q)

    if not questions:
        raise ValueError(Lf("No usable questions were found in “%@”.", name))
    return questions, warnings


PAYLOAD_MARKER = b"%%SATPREP-BANK-V1"
MAX_EMBEDDED_IMAGE_BYTES = 16 * 1024 * 1024
PAYLOAD_END = b"%%SATPREP-END"


def _payload(path):
    try:
        with open(path, "rb") as f:
            data = f.read()
    except OSError:
        return None
    start = data.find(PAYLOAD_MARKER)
    if start < 0:
        return None
    body = start + len(PAYLOAD_MARKER)
    end = data.find(PAYLOAD_END, body)
    if end < 0:
        return None
    try:
        raw = base64.b64decode(data[body:end], validate=False)
        return json.loads(raw.decode("utf-8"))
    except Exception:
        return None


def read_embedded_bank(path):
    p = _payload(path)
    if not p:
        return None
    try:
        return [_sanitised(Question.from_dict(_from_swift(q))) for q in p.get("questions", [])]
    except Exception:
        return None


_SAFE_IMAGE_NAME = re.compile(r"[A-Za-z0-9._-]+\.png")
_RESERVED_NAMES = ({"CON", "PRN", "AUX", "NUL"}
                   | {f"COM{n}" for n in range(1, 10)} | {f"LPT{n}" for n in range(1, 10)})


def is_safe_image_name(name):
    if not isinstance(name, str) or not _SAFE_IMAGE_NAME.fullmatch(name):
        return False
    if ".." in name or name.startswith("."):
        return False
    return name.upper().split(".")[0] not in _RESERVED_NAMES


def safe_image_path(images_dir, name):
    if not is_safe_image_name(name):
        return None
    base = os.path.realpath(images_dir)
    path = os.path.realpath(os.path.join(base, name))
    return path if os.path.dirname(path) == base else None


_ISLAND_LIMIT = 800.0
_SHEET_LIMIT = 200000


def _finite(v, low, high):
    return isinstance(v, (int, float)) and not isinstance(v, bool) \
        and math.isfinite(v) and low <= v <= high


def valid_inline(inline):
    if not isinstance(inline, list):
        return False
    for para in inline:
        if not isinstance(para, dict) or not isinstance(para.get("display", False), bool):
            return False
        runs = para.get("runs")
        if not isinstance(runs, list) or not runs:
            return False
        for r in runs:
            if not isinstance(r, dict):
                return False
            if "text" in r:
                if not isinstance(r["text"], str):
                    return False
            elif not (is_safe_image_name(r.get("image"))
                      and all(isinstance(r.get(k), int) and not isinstance(r.get(k), bool)
                              and 0 <= r[k] <= _SHEET_LIMIT for k in ("x", "y", "w", "h"))
                      and r["w"] > 0 and r["h"] > 0
                      and _finite(r.get("width"), 0.1, _ISLAND_LIMIT)
                      and _finite(r.get("height"), 0.1, _ISLAND_LIMIT)
                      and _finite(r.get("depth"), -_ISLAND_LIMIT, _ISLAND_LIMIT)):
                return False
    return True


def inline_images(block):
    return sorted({r["image"] for para in (block.inline or ()) for r in para["runs"]
                   if "image" in r})


def _sanitised(q):
    for b in q.all_blocks:
        if b.kind == "image" and not is_safe_image_name(b.image_name):
            b.image_name = ""
        if b.inline and not (b.kind == "image" and valid_inline(b.inline)
                             and _finite(b.x_height, 0.5, 100)):
            b.inline, b.x_height = [], 0
    return q


def restore_embedded_images(path, images_dir):
    p = _payload(path)
    if not p:
        return
    os.makedirs(images_dir, exist_ok=True)
    longest = (MAX_EMBEDDED_IMAGE_BYTES // 3 + 1) * 4 + 4096
    images = p.get("images") or {}
    if not isinstance(images, dict):
        return
    for name, b64 in images.items():
        dest = safe_image_path(images_dir, name)
        if dest is None or not isinstance(b64, str) or len(b64) > longest:
            continue
        try:
            data = base64.b64decode(b64)
        except Exception:
            continue
        if len(data) > MAX_EMBEDDED_IMAGE_BYTES:
            continue
        try:
            safeio.atomic_write_bytes(dest, data)
        except OSError:
            continue


_SWIFT_KEYS = {
    "correctAnswer": "correct_answer", "sourceName": "source_name",
    "imageName": "image_name", "pixelWidth": "pixel_width",
    "pixelHeight": "pixel_height", "pointWidth": "point_width",
    "xHeight": "x_height",
}
_SWIFT_VALUES = {
    "readingWriting": "reading_writing", "multipleChoice": "multiple_choice",
    "studentResponse": "student_response",
}


def _blocks(q, field):
    return q.stimulus if field == "stimulus" else q.prompt


def marked_words(a, q):
    bl = _blocks(q, a.get("field"))
    i, lo, hi = a.get("block", 0), a.get("start", 0), a.get("end", 0)
    if not (0 <= i < len(bl)) or bl[i].kind != "text":
        return None
    if not (0 <= lo < hi <= len(bl[i].text)):
        return None
    return bl[i].text[lo:hi]


TAKEN_OFF_FILE = "HighlightsTakenOff.txt"


def rehome_annotations(notes, old_questions, new_questions):
    before = {}
    for q in old_questions:
        before.setdefault(q.id, q)
    after = {}
    for q in new_questions:
        after.setdefault(q.id, q)

    out, taken_off = [], 0
    for a in notes:
        was, now = before.get(a.get("question_id")), after.get(a.get("question_id"))
        marked = None
        if a.get("start", 0) < a.get("end", 0) and now is not None:
            marked = a.get("marked") or (marked_words(a, was) if was else None)
        if marked is None:
            out.append(a)
            continue
        fresh = _blocks(now, a.get("field"))
        kept = dict(a, marked=marked)
        if marked_words(a, now) == marked:
            out.append(kept)
            continue
        places = []
        for i, b in enumerate(fresh):
            if b.kind != "text":
                continue
            at = b.text.find(marked)
            while at >= 0:
                places.append((i, at))
                at = b.text.find(marked, at + 1)
        if len(places) == 1:
            kept["block"], kept["start"] = places[0]
            kept["end"] = places[0][1] + len(marked)
            out.append(kept)
            continue
        taken_off += 1
        if (a.get("note") or "").strip():
            kept["block"], kept["start"], kept["end"] = len(fresh), 0, 0
            kept.pop("marked", None)
            out.append(kept)
    return out, taken_off


def _islands(doc, b, images_dir, stem):
    rects = [r["rect"] for para in (b.inline or ()) for r in para["runs"] if "rect" in r]
    if not rects:
        return []
    name = f"{stem}-maths.png"
    cuts = pdfparse.render_islands(doc, b.page, rects, os.path.join(images_dir, name))
    if not cuts:
        return []
    out, n = [], 0
    for para in b.inline:
        runs = []
        for r in para["runs"]:
            if "text" in r:
                runs.append({"text": r["text"]})
                continue
            y, w, h, pt_w, pt_h, off = cuts[n]
            n += 1
            runs.append({"image": name, "x": 0, "y": y, "w": w, "h": h,
                         "width": round(pt_w, 2), "height": round(pt_h, 2),
                         "depth": round(r["depth"] - off, 2)})
        out.append({"display": bool(para["display"]), "runs": runs})
    return out


def _from_swift(d):
    if isinstance(d, dict):
        out = {}
        for k, v in d.items():
            out[_SWIFT_KEYS.get(k, k)] = _from_swift(v)
        return out
    if isinstance(d, list):
        return [_from_swift(x) for x in d]
    if isinstance(d, str):
        return _SWIFT_VALUES.get(d, d)
    return d


def _to_swift_question(q: Question):
    inv_v = {v: k for k, v in _SWIFT_VALUES.items()}

    def block(b: ContentBlock):
        return {"kind": b.kind, "text": b.text, "imageName": b.image_name,
                "pixelWidth": b.pixel_width, "pixelHeight": b.pixel_height,
                "pointWidth": b.point_width,
                "underlines": [[s0, e0] for s0, e0 in (b.underlines or [])],
                "rows": [list(r) for r in (b.rows or [])],
                "centred": b.centred,
                "inline": b.inline or [], "xHeight": b.x_height}

    return {
        "id": q.id, "subject": inv_v.get(q.subject, q.subject),
        "assessment": q.assessment, "test": q.test, "domain": q.domain,
        "skill": q.skill, "difficulty": q.difficulty,
        "kind": inv_v.get(q.kind, q.kind),
        "stimulus": [block(b) for b in q.stimulus],
        "prompt": [block(b) for b in q.prompt],
        "choices": [{"letter": c.letter, "blocks": [block(b) for b in c.blocks]}
                    for c in q.choices],
        "correctAnswer": q.correct_answer,
        "rationale": [block(b) for b in q.rationale],
        "sourceName": q.source_name,
    }
