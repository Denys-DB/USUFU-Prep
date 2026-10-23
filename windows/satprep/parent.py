from __future__ import annotations

import datetime
import time

from .core import build_statistics, CONFIDENT_AT
from . import i18n
from .i18n import L, Lf, Lp

WINDOW_DAYS = 30


def summary(store, days=WINDOW_DAYS, now=None):
    now = time.time() if now is None else now
    since = now - days * 86400
    out = {"student": store.profile.get("name", ""), "at": now, "days": days,
           "tiles": [], "lines": [], "strengths": [], "struggles": [], "caveats": []}

    rows = [r for rows in store.history.values() for r in rows
            if not r.get("backfilled") and r.get("at", 0) >= since]
    if not rows:
        out["lines"] = [L("There is no practice recorded in this period yet.")]
        return out

    answered = len(rows)
    correct = sum(1 for r in rows if r.get("correct"))
    practised = len({datetime.date.fromtimestamp(r["at"]) for r in rows})
    accuracy = int(round(correct / answered * 100))

    out["tiles"] = [
        (str(answered), Lp(answered, "question answered", "questions answered")),
        (str(practised), Lp(practised, "day practiced", "days practiced")),
        ("%d%%" % accuracy, L("answered correctly")),
    ]
    out["lines"].append(
        Lf("%1$@ practiced on %2$d of the last %3$d days and answered %4$d questions.",
           out["student"], practised, days, answered))
    out["lines"].append(Lf("Of those, %1$d answered correctly — %2$d%%.", correct, accuracy))

    strong, weak = [], []
    judged = 0
    for bank in store.banks:
        stats = build_statistics(store.history.get(bank.id, []), bank)
        for row in stats.get("by_skill", []):
            if row.get("attempts", 0) < CONFIDENT_AT:
                continue
            judged += 1
            if row.get("accuracy", 0) >= 0.8:
                strong.append(row)
            elif row.get("accuracy", 0) < 0.6:
                weak.append(row)
    out["strengths"] = [r["label"] for r in
                        sorted(strong, key=lambda r: -r["accuracy"])[:3]]
    out["struggles"] = [r["label"] for r in
                        sorted(weak, key=lambda r: r["accuracy"])[:3]]

    if out["strengths"]:
        out["lines"].append(Lf("Going well: %@.", ", ".join(out["strengths"])))
    if out["struggles"]:
        out["lines"].append(Lf("Finding harder: %@.", ", ".join(out["struggles"])))
        out["lines"].append(
            L("These are the topics where help would make the most difference right now."))
    if not out["strengths"] and not out["struggles"]:
        if judged:
            out["lines"].append(Lf(
                "%@ is working at about the same level across every topic there "
                "is enough practice to judge — nothing yet stands out as either "
                "a strength or a difficulty.", out["student"]))
        else:
            out["lines"].append(
                L("There is not yet enough practice in any one topic to say which are "
                  "going well and which are not."))

    rhythm = store.rhythm(now=now)
    run = rhythm.get("streak", 0) if isinstance(rhythm, dict) else 0
    if run >= 2:
        out["lines"].append(Lp(run, "%d day in a row so far.", "%d days in a row so far."))

    out["caveats"] = [
        L("These figures come from practice in this app only. They are not a "
          "predicted SAT score, and this app cannot produce one — a question bank "
          "is not a scored test."),
        L("Nothing here is compared with other students. Everything stays on this "
          "computer."),
    ]
    return out


def export(summary_dict, out_path):
    import pymupdf as fitz
    from .export import _Writer, MUTED, _save
    from . import brand

    doc = fitz.open()
    w = _Writer(doc)
    student = summary_dict.get("student", "")
    w.text(Lf("Practice summary — %@", student), size=20, bold=True)
    w.text(Lf("The last %1$d days · %2$@", summary_dict.get("days", WINDOW_DAYS),
              i18n.stamp(summary_dict.get("at", time.time()))), size=10, color=MUTED)
    w.space(4)
    w.rule()
    w.space(10)

    for value, label in summary_dict.get("tiles", []):
        w.text(value, size=22, bold=True)
        w.text(label, size=9.5, color=MUTED)
        w.space(6)
    w.rule()
    w.space(10)

    for line in summary_dict.get("lines", []):
        w.text(line, size=12)
        w.space(4)

    if summary_dict.get("caveats"):
        w.space(8)
        w.rule()
        w.space(8)
        for caveat in summary_dict["caveats"]:
            w.text(caveat, size=9, color=MUTED)
            w.space(3)

    w.space(6)
    w.text(brand.APP_NAME + " · " + brand.ORGANISATION, size=8.5, color=MUTED)
    _save(doc, out_path)
    doc.close()
