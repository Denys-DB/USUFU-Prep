from __future__ import annotations

import json
import os
import random
import re
import time
import uuid
from dataclasses import dataclass, field

from .i18n import L, Lf, Lp


REVIEW_DAYS = [1, 3, 7, 16, 35]


def _day_start(stamp):
    t = time.localtime(stamp)
    return time.mktime((t.tm_year, t.tm_mon, t.tm_mday, 0, 0, 0, 0, 0, -1))


@dataclass
class Flashcard:
    term: str = ""
    definition: str = ""
    example: str = ""
    hint: str = ""
    starred: bool = False
    id: str = field(default_factory=lambda: str(uuid.uuid4()))
    source_question_id: str = ""
    source_bank_id: str = ""
    source_bank_name: str = ""
    created_at: float = field(default_factory=time.time)
    times_seen: int = 0
    times_correct: int = 0
    last_seen: float = 0.0
    times_turned: int = 0
    times_glanced: int = 0
    last_answer_correct: bool = False
    introduced_on: float = 0.0

    @staticmethod
    def from_dict(d):
        def get(*names, default=None):
            for n in names:
                if n in d and d[n] is not None:
                    return d[n]
            return default
        return Flashcard(
            term=get("term", default="") or "",
            definition=get("definition", default="") or "",
            example=get("example", default="") or "",
            hint=get("hint", default="") or "",
            starred=bool(get("starred", default=False)),
            id=str(get("id", default=None) or uuid.uuid4()),
            source_question_id=get("sourceQuestionID", "source_question_id", default="") or "",
            source_bank_id=get("sourceBankID", "source_bank_id", default="") or "",
            source_bank_name=get("sourceBankName", "source_bank_name", default="") or "",
            created_at=float(get("createdAt", "created_at", default=0) or 0),
            times_seen=int(get("timesSeen", "times_seen", default=0) or 0),
            times_correct=int(get("timesCorrect", "times_correct", default=0) or 0),
            last_seen=float(get("lastSeen", "last_seen", default=0) or 0),
            times_turned=int(get("timesTurned", "times_turned", default=0) or 0),
            times_glanced=int(get("timesGlanced", "times_glanced", default=0) or 0),
            last_answer_correct=bool(get("lastAnswerCorrect", "last_answer_correct",
                                         default=False)),
            introduced_on=float(get("introducedOn", "introduced_on", default=0) or 0),
        )

    def to_dict(self):
        return {
            "id": self.id, "term": self.term, "definition": self.definition,
            "example": self.example, "hint": self.hint, "starred": self.starred,
            "sourceQuestionID": self.source_question_id,
            "sourceBankID": self.source_bank_id,
            "sourceBankName": self.source_bank_name,
            "createdAt": self.created_at,
            "timesSeen": self.times_seen, "timesCorrect": self.times_correct,
            "lastSeen": self.last_seen,
            "timesTurned": self.times_turned, "timesGlanced": self.times_glanced,
            "lastAnswerCorrect": self.last_answer_correct,
            "introducedOn": self.introduced_on,
        }

    @property
    def has_definition(self):
        return bool(self.definition.strip())

    @property
    def accuracy(self):
        return self.times_correct / self.times_seen if self.times_seen else None

    @property
    def is_trouble(self):
        return (self.times_seen >= 1
                and self.last_answer_correct is False
                and self.times_correct * 2 <= self.times_seen)

    @property
    def is_skimmed(self):
        return self.times_glanced >= 1 and self.times_turned == 0

    def is_due(self, now=None):
        if self.times_seen <= 0 or not self.last_seen:
            return False
        now = time.time() if now is None else now
        rung = min(max(self.times_correct, 1), len(REVIEW_DAYS)) \
            if self.last_answer_correct else 1
        return now - self.last_seen >= REVIEW_DAYS[rung - 1] * 86400

    @property
    def is_new(self):
        return self.times_seen == 0 and self.times_turned == 0

    def was_answered_on(self, day):
        if not self.last_seen:
            return False
        return _day_start(self.last_seen) == _day_start(day)

    @property
    def record_line(self):
        parts = []
        if self.times_seen:
            parts.append(Lf("right %1$d of %2$d", self.times_correct, self.times_seen))
        if self.times_turned:
            parts.append(Lf("turned over %d×", self.times_turned))
        if self.times_glanced:
            parts.append(Lf("skipped %d×", self.times_glanced))
        return " \u00b7 ".join(parts)


def safe_file_stem(value, fallback=None):
    text = str(value or "")
    ok = (text
          and text == os.path.basename(text)
          and "/" not in text and "\\" not in text
          and "\x00" not in text
          and not text.startswith(".")
          and ":" not in text
          and text not in (".", ".."))
    if ok:
        return text
    return fallback() if fallback else uuid.uuid4().hex


def _valid_id(raw):
    try:
        return str(uuid.UUID(str(raw)))
    except (ValueError, AttributeError, TypeError):
        return str(uuid.uuid4())


@dataclass
class Deck:
    name: str = ""
    cards: list = field(default_factory=list)
    id: str = field(default_factory=lambda: str(uuid.uuid4()))
    created_at: float = field(default_factory=time.time)

    @staticmethod
    def from_dict(d):
        return Deck(
            name=d.get("name") or "Deck",
            cards=[Flashcard.from_dict(c) for c in (d.get("cards") or [])],
            id=_valid_id(d.get("id")),
            created_at=float(d.get("createdAt", d.get("created_at", 0)) or 0),
        )

    def to_dict(self):
        return {"id": self.id, "name": self.name, "createdAt": self.created_at,
                "cards": [c.to_dict() for c in self.cards]}

    @property
    def starred_count(self):
        return sum(1 for c in self.cards if c.starred)

    @property
    def trouble_count(self):
        return sum(1 for c in self.cards if c.is_trouble)

    @property
    def skimmed_count(self):
        return sum(1 for c in self.cards if c.is_skimmed)

    @property
    def undefined_first(self):
        return sort_cards(self.cards, "definitionsMissing")

    @property
    def undefined_count(self):
        return sum(1 for c in self.cards if not c.has_definition)

    def holds(self, term):
        k = key(term)
        return any(key(c.term) == k for c in self.cards)

    def card(self, card_id):
        return next((c for c in self.cards if c.id == card_id), None)


def key(text):
    return " ".join(plain(text).lower().strip(" \t\n.,;:\"'“”‘’()").split())


STYLES = ("bold", "italic", "underline", "highlight")
MARKERS = {"bold": "**", "italic": "*", "underline": "++", "highlight": "=="}
BY_LENGTH = ("bold", "underline", "highlight", "italic")
HTML = {"bold": ("<b>", "</b>"), "italic": ("<i>", "</i>"),
        "underline": ("<u>", "</u>"),
        "highlight": ('<span style="background-color:#FFEE8C;">', "</span>")}


def _opens_here(i, chars):
    return i < len(chars) and not chars[i].isspace()


def _closes_here(i, chars):
    return i > 0 and not chars[i - 1].isspace()


def _closes(style, start, chars):
    m = MARKERS[style]
    n = len(m)
    i = start
    while i + n <= len(chars):
        if "".join(chars[i:i + n]) == m:
            if style == "italic" and i + 1 < len(chars) and chars[i + 1] == "*":
                i += 1
                continue
            if i > start and _closes_here(i, chars):
                return True
        i += 1
    return False


def _marker_at(i, chars, active):
    for style in BY_LENGTH:
        m = MARKERS[style]
        n = len(m)
        if i + n > len(chars) or "".join(chars[i:i + n]) != m:
            continue
        if style == "italic" and i + 1 < len(chars) and chars[i + 1] == "*":
            continue
        if style in active:
            return style if _closes_here(i, chars) else None
        if not _opens_here(i + n, chars):
            return None
        return style if _closes(style, i + n, chars) else None
    return None


def _runs(text):
    chars = list(text or "")
    active, buffer, i = set(), [], 0
    while i < len(chars):
        style = _marker_at(i, chars, active)
        if style:
            if buffer:
                yield "".join(buffer), frozenset(active)
                buffer = []
            active.symmetric_difference_update({style})
            i += len(MARKERS[style])
            continue
        buffer.append(chars[i])
        i += 1
    if buffer:
        yield "".join(buffer), frozenset(active)


def plain(text):
    return "".join(piece for piece, _ in _runs(text))


def is_formatted(text):
    return plain(text) != text


def to_html(text, escape=True):
    out = []
    for piece, styles in _runs(text):
        if escape:
            piece = (piece.replace("&", "&amp;").replace("<", "&lt;")
                          .replace(">", "&gt;"))
        for style in STYLES:
            if style in styles:
                piece = HTML[style][0] + piece + HTML[style][1]
        out.append(piece)
    return "".join(out)


def _run(chars, at, step):
    count = 0
    while 0 <= at < len(chars) and chars[at] == "*" and count < 3:
        count += 1
        at += step
    return count


def _starred(style, left, right):
    if style not in ("bold", "italic"):
        return True
    run = min(left, right)
    return run in (1, 3) if style == "italic" else run >= 2


def toggle(style, text, start, end):
    chars = list(text or "")
    lower = max(0, min(start, len(chars)))
    upper = max(lower, min(end, len(chars)))
    if upper <= lower:
        return text, (start, end)
    m = list(MARKERS[style])
    n = len(m)
    if (lower >= n and upper + n <= len(chars)
            and chars[lower - n:lower] == m and chars[upper:upper + n] == m
            and _starred(style, _run(chars, lower - 1, -1), _run(chars, upper, 1))):
        rest = chars[:lower - n] + chars[lower:upper] + chars[upper + n:]
        return "".join(rest), (lower - n, upper - n)
    if (upper - lower >= 2 * n
            and chars[lower:lower + n] == m and chars[upper - n:upper] == m
            and _starred(style, _run(chars, lower, 1), _run(chars, upper - 1, -1))):
        rest = chars[:lower] + chars[lower + n:upper - n] + chars[upper:]
        return "".join(rest), (lower, upper - 2 * n)
    out = chars[:lower] + m + chars[lower:upper] + m + chars[upper:]
    return "".join(out), (lower + n, upper + n)


CARD_SORTS = ("deckOrder", "definitionsMissing", "alphabetical",
              "hardestFirst", "skippedMost", "newestFirst")
def card_sort_title(key):
    return {"deckOrder": L("The order they were added"),
            "definitionsMissing": L("Without a definition first"),
            "alphabetical": L("A to Z"),
            "hardestFirst": L("Worst answered first"),
            "skippedMost": L("Skipped most first"),
            "newestFirst": L("Newest first")}.get(key, key)


def sort_cards(cards, order):
    if order == "definitionsMissing":
        return sorted(cards, key=lambda c: (c.has_definition, key(c.term)))
    if order == "alphabetical":
        return sorted(cards, key=lambda c: key(c.term))
    if order == "hardestFirst":
        return sorted(cards, key=lambda c: (c.accuracy if c.accuracy is not None else 2,
                                            key(c.term)))
    if order == "skippedMost":
        return sorted(cards, key=lambda c: (-c.times_glanced, key(c.term)))
    if order == "newestFirst":
        return sorted(cards, key=lambda c: (-c.created_at, key(c.term)))
    return list(cards)


DAILY_RANGE = (3, 30)
DAILY_PRESETS = [5, 10, 15, 20]


def review_ceiling(words_per_day):
    return max(15, words_per_day * 3)


@dataclass
class DailySet:
    fresh: list = field(default_factory=list)
    due: list = field(default_factory=list)
    held_back: int = 0
    remaining_in_deck: int = 0

    @property
    def cards(self):
        return self.due + self.fresh

    @property
    def total(self):
        return len(self.cards)

    def answered_count(self, day=None):
        day = time.time() if day is None else day
        return sum(1 for c in self.cards if c.was_answered_on(day))

    def is_complete(self, day=None):
        return bool(self.cards) and self.answered_count(day) == len(self.cards)


def daily_set(cards, words_per_day, now=None):
    now = time.time() if now is None else now
    today = _day_start(now)
    out = DailySet()
    out.fresh = [c for c in cards
                 if c.introduced_on and _day_start(c.introduced_on) == today]
    fresh_ids = {c.id for c in out.fresh}
    out.due = [c for c in cards if c.id not in fresh_ids and c.is_due(now)]
    never = [c for c in cards if not c.introduced_on and c.is_new]
    out.remaining_in_deck = len(never)
    room = max(0, words_per_day - len(out.fresh))
    if room > 0 and len(out.due) >= review_ceiling(words_per_day):
        out.held_back = min(room, len(never))
    return out


def to_introduce(cards, words_per_day, now=None):
    now = time.time() if now is None else now
    today = daily_set(cards, words_per_day, now)
    if today.held_back:
        return []
    room = max(0, words_per_day - len(today.fresh))
    if room <= 0:
        return []
    return [c.id for c in cards if not c.introduced_on and c.is_new][:room]


def daily_streak(days, now=None):
    now = time.time() if now is None else now
    today = _day_start(now)
    starts = sorted({_day_start(d) for d in days})
    if not starts:
        return 0, 0, True, False

    done_today = today in starts
    cursor = today if done_today else today - 86400
    cursor = _day_start(cursor)
    run = 0
    marks = set(starts)
    while cursor in marks:
        run += 1
        cursor = _day_start(cursor - 86400)

    best, length, previous = 0, 0, None
    for day in starts:
        if previous is not None and _day_start(previous + 86400) == day:
            length += 1
        else:
            length = 1
        best = max(best, length)
        previous = day
    return run, max(best, run), not done_today, done_today


@dataclass
class DeckStatistics:
    total: int = 0
    with_definition: int = 0
    without_definition: int = 0
    new: int = 0
    learning: int = 0
    known: int = 0
    answered: int = 0
    correct: int = 0
    starred: int = 0
    skipped: int = 0
    due_today: int = 0
    due_this_week: int = 0

    @property
    def accuracy(self):
        return self.correct / self.answered if self.answered else None

    @property
    def known_fraction(self):
        return self.known / self.with_definition if self.with_definition else 0.0


def deck_statistics(cards, now=None):
    now = time.time() if now is None else now
    week = now + 7 * 86400
    out = DeckStatistics(total=len(cards))
    for c in cards:
        if c.has_definition:
            out.with_definition += 1
        else:
            out.without_definition += 1
        if c.starred:
            out.starred += 1
        if c.times_glanced:
            out.skipped += 1
        out.answered += c.times_seen
        out.correct += c.times_correct
        if c.times_seen == 0:
            out.new += 1
        elif c.last_answer_correct and c.times_correct >= 4:
            out.known += 1
        else:
            out.learning += 1
        if c.is_due(now):
            out.due_today += 1
        elif c.is_due(week):
            out.due_this_week += 1
    return out


def recent_days(completed, weeks=8, now=None):
    now = time.time() if now is None else now
    today = _day_start(now)
    marks = {_day_start(d) for d in completed}
    out = []
    for back in range(weeks * 7 - 1, -1, -1):
        day = _day_start(today - back * 86400)
        out.append((day, day in marks))
    return out


BLANK = "____"


def half_of(definition):
    trimmed = (definition or "").strip()
    if not trimmed:
        return ""
    words = trimmed.split()
    if len(words) == 1:
        keep = max(1, min(len(trimmed) - 1, (len(trimmed) + 1) // 2))
        return trimmed[:keep] + BLANK
    keep = max(1, (len(words) + 1) // 2)
    return " ".join(words[:keep]) + " " + BLANK


def hint_for(card: Flashcard):
    own = plain(card.hint).strip()
    return own if own else half_of(plain(card.definition))


SCOPES = ("all", "today", "starred", "trouble", "skimmed")
def scope_title(key):
    return {"all": L("All cards"), "today": L("Today"), "starred": L("Starred"),
            "trouble": L("Words I keep missing"),
            "skimmed": L("Words I skipped past")}.get(key, key)


def in_scope(cards, scope, words_per_day=10):
    if scope == "today":
        chosen = {c.id for c in daily_set(cards, words_per_day).cards}
        return [c for c in cards if c.id in chosen]
    if scope == "starred":
        return [c for c in cards if c.starred]
    if scope == "trouble":
        return [c for c in cards if c.is_trouble]
    if scope == "skimmed":
        return [c for c in cards if c.is_skimmed]
    return list(cards)


MINIMUM_CARDS = 4
ANSWER_SIDES = ("definitions", "terms", "mixed")
def side_title(key):
    return {"definitions": L("Definitions"), "terms": L("The words themselves"),
            "mixed": L("A mix of both")}.get(key, key)


def side_detail(key):
    return {"definitions": L("You are shown the word and pick what it means."),
            "terms": L("You are shown the meaning and pick the word."),
            "mixed": L("Some questions each way, decided per question.")}.get(key, "")


@dataclass
class VocabQuestion:
    card_id: str
    asks_for_definition: bool
    prompt: str
    options: list
    answer_index: int

    @property
    def answer(self):
        return self.options[self.answer_index] if 0 <= self.answer_index < len(self.options) else ""


def testable(cards):
    return [c for c in cards if c.term.strip() and c.has_definition]


def available_count(cards):
    usable = testable(cards)
    return len(usable) if len(usable) >= MINIMUM_CARDS else 0


def build_test(cards, side="definitions", count=20, rng=None, asking=None):
    rng = rng or random.Random()
    usable = testable(cards)
    if len(usable) < MINIMUM_CARDS:
        return []
    subject = testable(asking) if asking is not None else usable
    if not subject:
        return []
    wanted = max(1, min(count, len(subject)))
    asked = rng.sample(subject, wanted)

    out = []
    for card in asked:
        if side == "mixed":
            asks_for_definition = rng.random() < 0.5
        else:
            asks_for_definition = side == "definitions"

        face = (lambda c: plain(c.definition).strip()) if asks_for_definition \
            else (lambda c: plain(c.term).strip())
        back = (lambda c: plain(c.term).strip()) if asks_for_definition \
            else (lambda c: plain(c.definition).strip())

        correct = face(card)
        if not correct:
            continue
        used = {key(correct)}
        options = [correct]
        pool = usable[:]
        rng.shuffle(pool)
        for other in pool:
            if len(options) >= 4:
                break
            if other.id == card.id:
                continue
            text = face(other)
            if not text or key(text) in used:
                continue
            used.add(key(text))
            options.append(text)
        if len(options) != 4:
            continue
        rng.shuffle(options)
        out.append(VocabQuestion(card_id=card.id,
                                 asks_for_definition=asks_for_definition,
                                 prompt=back(card), options=options,
                                 answer_index=options.index(correct)))
    return out


@dataclass
class MinedCard:
    term: str
    definition: str = ""
    example: str = ""
    question_id: str = ""
    source: str = "choice"

    @property
    def id(self):
        return key(self.term)

    @property
    def has_definition(self):
        return bool(self.definition.strip())


_ADVERBS = (r"(?:can |could |would |will |generally |typically |usually |here |also "
            r"|literally |simply |both |most nearly |nearly )*")
_VERBS = r"(?:means?|refers? to|is used to mean|is defined as|denotes?|describes?)"

_TAILS = [re.compile(p, re.IGNORECASE) for p in (
    r"^[ ]*,?[ ]*(?:which|that)[ ]+" + _ADVERBS + _VERBS + r"[ ]+(.+)$",
    r"^[ ]*,?[ ]*" + _ADVERBS + _VERBS + r"[ ]+(.+)$",
    r"^[ ]*[,\-]?[ ]*meaning[ ]+(.+)$",
    r"^[ ]*,?[ ]*or[ ]+(.+)$",
    r"^[ ]*\(([^)]{3,90})\)",
)]

_FREE_FORM = re.compile(
    r"\"([A-Za-z][A-Za-z' \-]{2,28}),?\"[ ]*,?[ ]*(?:which |that )?"
    + _ADVERBS + _VERBS + r"[ ]+([^.]{3,110})[.,]", re.IGNORECASE)

_NOT_A_DEFINITION = ("the text", "there is", "there are", "it's", "it is", "this ",
                     "that the", "nothing", "he ", "she ", "they ", "we ", "in this",
                     "however")


def normalise(text):
    return (text.replace("“", '"').replace("”", '"')
                .replace("‘", "'").replace("’", "'")
                .replace("—", " - ").replace("–", " - "))


def sentences(text):
    out, current, in_quote, depth = [], [], False, 0
    i = 0
    while i < len(text):
        ch = text[i]
        current.append(ch)
        if ch == '"':
            in_quote = not in_quote
        elif ch == "(":
            depth += 1
        elif ch == ")":
            depth = max(0, depth - 1)
        elif ch in ".!?\n" and not in_quote and depth == 0:
            while i + 1 < len(text) and text[i + 1] in "\"'":
                i += 1
                current.append(text[i])
                if text[i] == '"':
                    in_quote = not in_quote
            done = "".join(current).strip()
            if done:
                out.append(done)
            current = []
        i += 1
    last = "".join(current).strip()
    if last:
        out.append(last)
    return out


def tidy(gloss):
    d = " ".join((gloss or "").split())
    if " - " in d:
        d = d.split(" - ")[0]
    if "," in d:
        d = d.split(",")[0]
    d = d.strip(" \"\t.;:")
    for prefix in ("that ", "to be ", "being "):
        if d.lower().startswith(prefix):
            d = d[len(prefix):]
    for suffix in (" in this context", " for this context"):
        if d.lower().endswith(suffix):
            d = d[: -len(suffix)]
    return d.strip()


def acceptable(gloss):
    words = gloss.split()
    if not words or len(words) > 14 or len(gloss) <= 2 or len(gloss) > 110:
        return False
    low = gloss.lower()
    return not any(low.startswith(p) for p in _NOT_A_DEFINITION)


def _split_quoted_list(text):
    t = text.strip()
    if not t.startswith('"'):
        return [t]
    parts = [p.strip() for p in t.split('"')]
    parts = [p for p in parts if len(p) > 1 and p not in ("or", "and")]
    return parts or [t]


def _after_quoted(term, sentence):
    low = sentence.lower()
    for opener in ('"' + term.lower() + ',"', '"' + term.lower() + '"'):
        at = low.find(opener)
        if at >= 0:
            return sentence[at + len(opener):]
    return None


def definition_of(term, rationale):
    term = (term or "").strip()
    if not term:
        return None
    text = normalise(rationale or "")
    needle = '"' + term.lower()
    for sentence in sentences(text):
        if needle not in sentence.lower():
            continue
        after = _after_quoted(term, sentence)
        if after is None:
            continue
        for pattern in _TAILS:
            m = pattern.match(after)
            if not m:
                continue
            for gloss in _split_quoted_list(m.group(1)):
                candidate = tidy(gloss)
                if acceptable(candidate):
                    return candidate
    return None


def _plain(blocks):
    return "\n".join(b.text for b in blocks if b.kind == "text")


def usable_term(raw):
    t = " ".join((raw or "").split()).strip(".,;:\"'“”‘’")
    for article in ("a ", "an ", "the ", "to "):
        if t.lower().startswith(article):
            t = t[len(article):]
            break
    if not t or len(t) > 40:
        return None
    words = t.split()
    if not 1 <= len(words) <= 3:
        return None
    if not all(c.isalpha() or c in " -'" for c in t):
        return None
    if not any(c.isalpha() for c in t):
        return None
    return t


def teaches_words(q):
    if q.kind != "multiple_choice" or len(q.choices) != 4:
        return False
    prompt = _plain(q.prompt).lower()
    if "most nearly mean" in prompt:
        return False
    if (q.skill or "").strip().lower() == "words in context":
        return True
    return "most logical and precise word or phrase" in prompt


def _blank_sentence(stimulus):
    if "_" not in stimulus:
        return ""
    for s in sentences(normalise(stimulus)):
        if "__" in s:
            return " ".join(s.split())
    return ""


def _sentence_containing(term, text):
    needle = term.lower()
    for s in sentences(normalise(text)):
        if needle in s.lower():
            return " ".join(s.split())
    return ""


def _first_quoted(text):
    t = normalise(text)
    a = t.find('"')
    if a < 0:
        return None
    b = t.find('"', a + 1)
    if b < 0:
        return None
    inner = t[a + 1:b].strip()
    return inner or None


def _choice_text(choice):
    return " ".join(b.text for b in choice.blocks if b.kind == "text").strip()


def from_choices(q):
    if not teaches_words(q):
        return []
    rationale = _plain(q.rationale)
    if not rationale:
        return []
    blanked = _blank_sentence(_plain(q.stimulus))
    out = []
    for choice in q.choices:
        raw = _choice_text(choice)
        term = usable_term(raw)
        if not term:
            continue
        meaning = definition_of(raw, rationale) or definition_of(term, rationale) or ""
        is_answer = choice.letter.strip().upper() == (q.correct_answer or "").strip().upper()
        out.append(MinedCard(term=term, definition=meaning,
                             example=blanked if is_answer else "",
                             question_id=q.id, source="choice"))
    return out


def _lowercased_first(s):
    if not s or not s[0].isupper():
        return s
    if any(c.isupper() for c in s[1:]):
        return s
    return s[0].lower() + s[1:]


def from_prompt(q):
    prompt = _plain(q.prompt)
    if "most nearly mean" not in prompt.lower():
        return []
    quoted = _first_quoted(prompt)
    term = usable_term(quoted) if quoted else None
    if not term:
        return []
    answer = next((c for c in q.choices
                   if c.letter.strip().upper() == (q.correct_answer or "").strip().upper()), None)
    if answer is None:
        return []
    meaning = _choice_text(answer)
    if not meaning or len(meaning.split()) > 10:
        return []
    return [MinedCard(term=term, definition=_lowercased_first(meaning),
                      example=_sentence_containing(term, _plain(q.stimulus)),
                      question_id=q.id, source="prompt")]


def _about_words(q):
    if (q.skill or "").strip().lower() == "words in context":
        return True
    prompt = _plain(q.prompt).lower()
    return "most nearly mean" in prompt or "most logical and precise word" in prompt


def from_rationale(q):
    if not _about_words(q):
        return []
    text = normalise(_plain(q.rationale))
    if not text:
        return []
    out = []
    for m in _FREE_FORM.finditer(text):
        term = usable_term(m.group(1))
        if not term:
            continue
        gloss = tidy(m.group(2))
        if not acceptable(gloss):
            continue
        out.append(MinedCard(term=term, definition=gloss,
                             question_id=q.id, source="rationale"))
    return out


def opening(found, already):
    any_defined = any(c.has_definition for c in found)
    chosen = {c.id for c in found
              if not already(c) and (c.has_definition or not any_defined)}
    return (any_defined or not found), chosen


def hidden(found, only_defined):
    return sum(1 for c in found if not c.has_definition) if only_defined else 0


def mine(bank):
    found = {}

    def offer(card):
        if not card.id:
            return
        existing = found.get(card.id)
        if existing is None:
            found[card.id] = card
            return
        better = (2 if card.has_definition else 0) + (0 if not card.example else 1)
        current = (2 if existing.has_definition else 0) + (0 if not existing.example else 1)
        if better > current:
            found[card.id] = card

    for q in bank.questions:
        for c in from_choices(q):
            offer(c)
        for c in from_prompt(q):
            offer(c)
        for c in from_rationale(q):
            offer(c)

    glossary = {c.id: c.definition for c in found.values() if c.has_definition}
    for k, card in found.items():
        if not card.has_definition and k in glossary:
            card.definition = glossary[k]

    return sorted(found.values(), key=lambda c: c.term.lower())


def card_from(mined: MinedCard, bank) -> Flashcard:
    return Flashcard(term=mined.term, definition=mined.definition,
                     example=mined.example, source_question_id=mined.question_id,
                     source_bank_id=bank.id, source_bank_name=bank.name)


class DeckStore:

    def __init__(self, root, damaged=None):
        self.dir = os.path.join(root, "Decks")
        os.makedirs(self.dir, exist_ok=True)
        self.decks = []
        self._damaged = damaged
        self.load()

    def load(self):
        from . import safeio
        self.decks = []
        for name in sorted(os.listdir(self.dir)):
            if not name.endswith(".json"):
                continue
            path = os.path.join(self.dir, name)
            d = safeio.read_json(path, None, self._damaged, expect=dict)
            if d is None:
                continue
            try:
                self.decks.append(Deck.from_dict(d))
            except Exception:
                moved = safeio.set_aside(path)
                if self._damaged:
                    self._damaged(moved or path)
        self.decks.sort(key=lambda d: d.created_at)

    def _path(self, deck_id):
        return os.path.join(self.dir, safe_file_stem(deck_id) + ".json")

    def save(self, deck):
        from . import safeio
        safeio.write_json(self._path(deck.id), deck.to_dict(), ensure_ascii=False)

    def deck(self, deck_id):
        return next((d for d in self.decks if d.id == deck_id), None)

    def add_deck(self, name=None, cards=None):
        deck = Deck(name=(name or "").strip() or self._default_name(), cards=cards or [])
        self.decks.append(deck)
        self.save(deck)
        return deck

    def _default_name(self):
        base = L("Vocabulary")
        if not any(d.name == base for d in self.decks):
            return base
        n = 2
        while any(d.name == f"{base} {n}" for d in self.decks):
            n += 1
        return f"{base} {n}"

    def rename_source_bank(self, bank_id, name):
        if not bank_id:
            return 0
        changed = 0
        for deck in self.decks:
            touched = False
            for card in deck.cards:
                if card.source_bank_id == bank_id and card.source_bank_name != name:
                    card.source_bank_name = name
                    touched = True
                    changed += 1
            if touched:
                self.save(deck)
        return changed

    def rename_deck(self, deck_id, name):
        deck = self.deck(deck_id)
        if deck and name.strip():
            deck.name = name.strip()
            self.save(deck)

    def delete_deck(self, deck_id):
        self.decks = [d for d in self.decks if d.id != deck_id]
        try:
            os.remove(self._path(deck_id))
        except OSError:
            pass

    def add_card(self, card, deck_id):
        deck = self.deck(deck_id)
        if deck is None or not card.term.strip() or deck.holds(card.term):
            return False
        deck.cards.append(card)
        self.save(deck)
        return True

    def add_cards(self, cards, deck_id):
        deck = self.deck(deck_id)
        if deck is None:
            return 0
        added = 0
        for card in cards:
            if not card.term.strip() or deck.holds(card.term):
                continue
            deck.cards.append(card)
            added += 1
        if added:
            self.save(deck)
        return added

    def update_card(self, card, deck_id):
        deck = self.deck(deck_id)
        if deck is None:
            return
        for i, existing in enumerate(deck.cards):
            if existing.id == card.id:
                deck.cards[i] = card
                self.save(deck)
                return

    def delete_card(self, card_id, deck_id):
        deck = self.deck(deck_id)
        if deck is None:
            return
        deck.cards = [c for c in deck.cards if c.id != card_id]
        self.save(deck)

    def toggle_star(self, card_id, deck_id):
        deck = self.deck(deck_id)
        card = deck.card(card_id) if deck else None
        if card:
            card.starred = not card.starred
            self.save(deck)

    def record_self_grade(self, card_id, correct, deck_id):
        self.record_test({card_id: correct}, deck_id)

    def record_turn(self, card_id, deck_id):
        deck = self.deck(deck_id)
        card = deck.card(card_id) if deck else None
        if card:
            card.times_turned += 1
            self.save(deck)

    def record_skip(self, card_id, deck_id):
        deck = self.deck(deck_id)
        card = deck.card(card_id) if deck else None
        if card:
            card.times_glanced += 1
            self.save(deck)

    def delete_cards(self, card_ids, deck_id):
        deck = self.deck(deck_id)
        if deck is None or not card_ids:
            return
        deck.cards = [c for c in deck.cards if c.id not in card_ids]
        self.save(deck)

    def set_starred(self, starred, card_ids, deck_id):
        deck = self.deck(deck_id)
        if deck is None or not card_ids:
            return
        for card in deck.cards:
            if card.id in card_ids:
                card.starred = starred
        self.save(deck)

    def clear_todays_deal(self, deck_id, now=None):
        deck = self.deck(deck_id)
        if deck is None:
            return
        today = _day_start(time.time() if now is None else now)
        for card in deck.cards:
            if card.introduced_on and _day_start(card.introduced_on) == today:
                card.introduced_on = 0.0
        self.save(deck)

    def clear_all_progress(self, deck_id):
        deck = self.deck(deck_id)
        if deck is None:
            return
        for card in deck.cards:
            card.introduced_on = 0.0
            card.times_seen = 0
            card.times_correct = 0
            card.times_turned = 0
            card.times_glanced = 0
            card.last_answer_correct = False
            card.last_seen = 0.0
        self.save(deck)

    def record_test(self, results, deck_id):
        deck = self.deck(deck_id)
        if deck is None or not results:
            return
        now = time.time()
        for card_id, correct in results.items():
            card = deck.card(card_id)
            if card is None:
                continue
            card.times_seen += 1
            if correct:
                card.times_correct += 1
            card.last_answer_correct = bool(correct)
            card.last_seen = now
        self.save(deck)
