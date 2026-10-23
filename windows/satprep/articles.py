from __future__ import annotations

import json
import os

from .i18n import current as current_language

HERE = os.path.dirname(os.path.abspath(__file__))
ARTICLES_DIR = os.path.join(HERE, "assets", "articles")

_cache = {}


def _read(language):
    path = os.path.join(ARTICLES_DIR, "articles-%s.json" % language)
    try:
        with open(path, encoding="utf-8") as f:
            return json.load(f).get("articles", [])
    except Exception:
        return []


def load(language):
    if language not in _cache:
        _cache[language] = _read(language)
    return _cache[language]


def current():
    english = load("en")
    language = current_language()
    if language == "en":
        return english
    translated = {a.get("id"): a for a in load(language)}
    if not translated:
        return english
    return [translated.get(a.get("id"), a) for a in english]


def minutes(article):
    words = 0
    for block in article.get("blocks", []):
        words += len(block.get("text", "").split())
        for item in block.get("items", []):
            words += len(item.split())
    return max(1, round(words / 180.0))


def for_skill(skill, articles=None):
    wanted = (skill or "").lower()
    for a in (articles if articles is not None else current()):
        if any(s.lower() == wanted for s in a.get("skills", [])):
            return a
    return None


def grouped(articles=None):
    all_ = articles if articles is not None else current()
    out = []
    for subject in ("readingWriting", "math"):
        here = [a for a in all_ if a.get("subject") == subject]
        seen = []
        for a in here:
            if a.get("domain") not in seen:
                seen.append(a.get("domain"))
        for domain in seen:
            out.append((subject, domain, [a for a in here if a.get("domain") == domain]))
    return out


def search(query, articles=None):
    all_ = articles if articles is not None else current()
    q = (query or "").strip().lower()
    if not q:
        return all_
    def hit(a):
        if q in a.get("title", "").lower() or q in a.get("summary", "").lower():
            return True
        if any(q in s.lower() for s in a.get("skills", [])):
            return True
        for b in a.get("blocks", []):
            if q in b.get("text", "").lower():
                return True
            if any(q in i.lower() for i in b.get("items", [])):
                return True
        return False
    return [a for a in all_ if hit(a)]


def missing(skills, articles=None):
    all_ = articles if articles is not None else current()
    return [s for s in skills if for_skill(s, all_) is None]
