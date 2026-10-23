from __future__ import annotations

import random
import uuid
from dataclasses import dataclass, field

from .i18n import L, Lf

READING_WRITING = "reading_writing"
MATH = "math"
SUBJECTS = (READING_WRITING, MATH)

DIFFICULTIES = ("Easy", "Medium", "Hard")

MIXED = "mixed"
LOWER = "lower"
UPPER = "upper"


def form_label(form: str) -> str:
    return {MIXED: L("Mixed"),
            LOWER: L("Easier form"),
            UPPER: L("Harder form")}.get(form, L("Mixed"))


def section_label(subject: str) -> str:
    return L("Math") if subject == MATH else L("Reading and Writing")


@dataclass
class ExamModule:

    subject: str
    number: int
    start: int
    count: int
    minutes: int
    seconds_remaining: float = 0.0
    submitted: bool = False
    form: str = MIXED
    break_after: int = 0
    id: str = field(default_factory=lambda: str(uuid.uuid4()))

    @property
    def end(self) -> int:
        return self.start + self.count

    def contains(self, index: int) -> bool:
        return self.start <= index < self.end

    def __post_init__(self):
        if not self.seconds_remaining:
            self.seconds_remaining = float(self.minutes * 60)

    @property
    def title(self) -> str:
        return Lf("Section %1$d, Module %2$d: %3$@",
                  1 if self.subject == READING_WRITING else 2,
                  self.number, section_label(self.subject))

    def to_dict(self) -> dict:
        return {"id": self.id, "subject": self.subject, "number": self.number,
                "start": self.start, "count": self.count,
                "minutes": self.minutes,
                "secondsRemaining": self.seconds_remaining,
                "submitted": self.submitted, "form": self.form,
                "breakAfter": self.break_after}

    @classmethod
    def from_dict(cls, raw: dict) -> "ExamModule":
        return cls(subject=raw.get("subject", READING_WRITING),
                   number=int(raw.get("number", 1)),
                   start=int(raw.get("start", 0)),
                   count=int(raw.get("count", 0)),
                   minutes=int(raw.get("minutes", 0)),
                   seconds_remaining=float(raw.get("secondsRemaining", 0)),
                   submitted=bool(raw.get("submitted", False)),
                   form=raw.get("form", MIXED),
                   break_after=int(raw.get("breakAfter", 0)),
                   id=raw.get("id") or str(uuid.uuid4()))


@dataclass
class Part:
    subject: str
    questions: int
    minutes: int
    break_after: int


DIGITAL = (
    Part(READING_WRITING, 27, 32, 0),
    Part(READING_WRITING, 27, 32, 10),
    Part(MATH, 22, 35, 0),
    Part(MATH, 22, 35, 0),
)

READING_WRITING_NEEDED = sum(p.questions for p in DIGITAL
                             if p.subject == READING_WRITING)
MATH_NEEDED = sum(p.questions for p in DIGITAL if p.subject == MATH)
TOTAL_QUESTIONS = READING_WRITING_NEEDED + MATH_NEEDED
TOTAL_MINUTES = sum(p.minutes for p in DIGITAL)
BREAK_MINUTES = sum(p.break_after for p in DIGITAL)


@dataclass
class Readiness:

    reading_writing: int
    math: int

    @property
    def is_ready(self) -> bool:
        return (self.reading_writing >= READING_WRITING_NEEDED
                and self.math >= MATH_NEEDED)

    @property
    def shortfall(self):
        if self.is_ready:
            return None
        short_rw = READING_WRITING_NEEDED - self.reading_writing
        short_math = MATH_NEEDED - self.math
        if short_rw > 0 and short_math > 0:
            return Lf("A full test needs %1$d Reading and Writing questions and "
                      "%2$d Math. You need %3$d more Reading and Writing and "
                      "%4$d more Math.",
                      READING_WRITING_NEEDED, MATH_NEEDED, short_rw, short_math)
        if short_rw > 0:
            return Lf("A full test needs %1$d Reading and Writing questions and "
                      "%2$d Math. You need %3$d more Reading and Writing.",
                      READING_WRITING_NEEDED, MATH_NEEDED, short_rw)
        return Lf("A full test needs %1$d Reading and Writing questions and "
                  "%2$d Math. You need %3$d more Math.",
                  READING_WRITING_NEEDED, MATH_NEEDED, short_math)


def modules(reading_writing: list, math: list):
    if (len(reading_writing) < READING_WRITING_NEEDED
            or len(math) < MATH_NEEDED):
        return None

    questions = []
    built = []
    taken = {READING_WRITING: 0, MATH: 0}
    numbered = {READING_WRITING: 0, MATH: 0}

    for part in DIGITAL:
        source = reading_writing if part.subject == READING_WRITING else math
        start = taken[part.subject]
        chunk = source[start:start + part.questions]
        taken[part.subject] = start + part.questions
        numbered[part.subject] += 1

        built.append(ExamModule(subject=part.subject,
                                number=numbered[part.subject],
                                start=len(questions),
                                count=len(chunk),
                                minutes=part.minutes,
                                break_after=part.break_after))
        questions.extend(chunk)
    return questions, built


def is_full_test(session) -> bool:
    return bool(getattr(session, "modules", None))


def current_module(session):
    mods = getattr(session, "modules", None) or []
    for module in mods:
        if module.contains(session.index):
            return module
    return mods[-1] if mods else None


def offers_reference(session):
    module = current_module(session)
    if module is not None:
        return module.subject == MATH
    return any(q.subject == MATH for q in session.questions)


def current_module_index(session):
    for i, module in enumerate(getattr(session, "modules", None) or []):
        if module.contains(session.index):
            return i
    return None


def module_progress_line(session):
    module = current_module(session)
    index = current_module_index(session)
    if module is None or index is None:
        return None
    within = session.index - module.start + 1
    return Lf("Question %1$d of %2$d · module %3$d of %4$d",
              within, module.count, index + 1, len(session.modules))


def module_title(session):
    module = current_module(session)
    return module.title if module is not None else None


def can_move(session, index: int) -> bool:
    if not is_full_test(session):
        return 0 <= index < len(session.questions)
    module = current_module(session)
    if module is None:
        return False
    return module.contains(index)


def score(session, module) -> tuple:
    from .core import is_correct
    correct = answered = 0
    for i in range(module.start, module.end):
        if i >= len(session.attempts) or i >= len(session.questions):
            continue
        attempt = session.attempts[i]
        if attempt.response:
            answered += 1
            if is_correct(session.questions[i], attempt.response):
                correct += 1
    return correct, answered


def mix(form: str, total: int) -> dict:
    weights = {MIXED: (0.34, 0.33, 0.33),
               LOWER: (0.52, 0.33, 0.15),
               UPPER: (0.11, 0.33, 0.56)}.get(form, (0.34, 0.33, 0.33))
    counts = {}
    assigned = 0
    for i, label in enumerate(DIFFICULTIES):
        if i == len(DIFFICULTIES) - 1:
            n = total - assigned
        else:
            n = int(_round_half_up(total * weights[i]))
        counts[label] = n
        assigned += n
    return counts


def _round_half_up(value: float) -> int:
    import math
    return int(math.floor(value + 0.5))


def adaptive_module_size(subject: str) -> int:
    return 22 if subject == MATH else 27


def adaptive_needed(subject: str, label: str) -> int:
    size = adaptive_module_size(subject)
    return sum(mix(form, size)[label] for form in (MIXED, LOWER, UPPER))


@dataclass
class AdaptiveReadiness:

    counts: dict

    @property
    def is_ready(self) -> bool:
        return all(self.counts.get(subject, {}).get(label, 0)
                   >= adaptive_needed(subject, label)
                   for subject in SUBJECTS for label in DIFFICULTIES)

    @property
    def shortfall(self):
        if self.is_ready:
            return None
        lines = []
        for subject in (READING_WRITING, MATH):
            missing = [label for label in DIFFICULTIES
                       if self.counts.get(subject, {}).get(label, 0)
                       < adaptive_needed(subject, label)]
            if not missing:
                continue
            detail = ", ".join(
                "%s (%d of %d)" % (label.lower(),
                                   self.counts.get(subject, {}).get(label, 0),
                                   adaptive_needed(subject, label))
                for label in missing)
            lines.append("%s: %s" % (section_label(subject), detail))
        return (L("An adaptive test draws module 1 and both forms of module 2 "
                  "from the set, so each section needs enough questions at "
                  "every difficulty. Still short —")
                + " " + "; ".join(lines) + ".")


UPPER_THRESHOLD = 0.65


def route(correct: int, out_of: int) -> str:
    if out_of <= 0:
        return LOWER
    return UPPER if correct / out_of >= UPPER_THRESHOLD else LOWER


def draw(form: str, total: int, pools: dict, rng=None):
    out = []
    for label, n in sorted(mix(form, total).items()):
        if n <= 0:
            continue
        pool = pools.get(label) or []
        if len(pool) < n:
            return None
        out.extend(pool[:n])
        pools[label] = pool[n:]
    (rng or random).shuffle(out)
    return out


@dataclass
class AdaptiveOption:

    module_id: str
    lower: list = field(default_factory=list)
    upper: list = field(default_factory=list)
