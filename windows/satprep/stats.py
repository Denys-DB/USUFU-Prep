from __future__ import annotations

import os

from PySide6 import QtCore, QtGui, QtWidgets

from . import brand
from . import fulltest
from .core import CONFIDENT_AT, StatisticsFilter
from .ui import (ElidedLabel, BORDER, BRASS, BRASS_TEXT, BRASS_SOFT, CARD, CORRECT, HAIRLINE, INK, MUTED,
                 NAVY, PAPER, PAPER_DEEP, SERIF, NUMERALS, SUBTLE, WRONG, leading)
from .i18n import L, Lf, Lp


def _pace(seconds):
    s = max(0, int(round(seconds)))
    if s < 60:
        return Lf("%d s", s)
    return Lf("%1$dm %2$@s", s // 60, "%02d" % (s % 60))


def _accuracy_colour(v):
    if v >= 0.85:
        return CORRECT
    if v >= 0.65:
        return BRASS
    return WRONG


class AccuracyBar(QtWidgets.QWidget):

    def __init__(self, value, tint, parent=None):
        super().__init__(parent)
        from .home import ANIMATIONS_ON, FILL_MS
        self.target = max(0.0, min(1.0, value))
        self.value = 0.0 if ANIMATIONS_ON else self.target
        self.tint = tint
        self.setFixedHeight(8)
        self.setSizePolicy(QtWidgets.QSizePolicy.Expanding, QtWidgets.QSizePolicy.Fixed)
        if ANIMATIONS_ON:
            anim = QtCore.QVariantAnimation(self)
            anim.setDuration(FILL_MS)
            anim.setStartValue(0.0)
            anim.setEndValue(self.target)
            anim.setEasingCurve(QtCore.QEasingCurve.OutCubic)
            anim.valueChanged.connect(self._grow)
            anim.start(QtCore.QAbstractAnimation.DeleteWhenStopped)

    def _grow(self, v):
        self.value = float(v)
        self.update()

    def paintEvent(self, event):
        p = QtGui.QPainter(self)
        p.setRenderHint(QtGui.QPainter.Antialiasing)
        w, h = self.width(), self.height()
        p.fillRect(0, 0, w, h, QtGui.QColor(SUBTLE))
        colour = QtGui.QColor(self.tint)
        colour.setAlphaF(0.8)
        p.fillRect(0, 0, int(w * self.value), h, colour)
        p.fillRect(int(w * 0.85), 0, 1, h, QtGui.QColor(BORDER))
        p.end()


class GrowingColumn(QtWidgets.QFrame):

    def __init__(self, value, tint, parent=None):
        super().__init__(parent)
        from .home import ANIMATIONS_ON, FILL_MS
        self._full = max(4, int(90 * value))
        self._tint = tint
        self.setFixedWidth(46)
        self.setFixedHeight(self._full if not ANIMATIONS_ON else 4)
        self.setStyleSheet(f"background:{tint};")
        if ANIMATIONS_ON:
            anim = QtCore.QVariantAnimation(self)
            anim.setDuration(FILL_MS)
            anim.setStartValue(4)
            anim.setEndValue(self._full)
            anim.setEasingCurve(QtCore.QEasingCurve.OutCubic)
            anim.valueChanged.connect(lambda v: self.setFixedHeight(int(v)))
            anim.start(QtCore.QAbstractAnimation.DeleteWhenStopped)


class TrendChart(QtWidgets.QWidget):

    def __init__(self, points, parent=None):
        super().__init__(parent)
        self.points = points
        self.setMinimumHeight(150)

    def paintEvent(self, event):
        if len(self.points) < 2:
            return
        p = QtGui.QPainter(self)
        p.setRenderHint(QtGui.QPainter.Antialiasing)
        inset = 22
        w = self.width() - inset * 2
        h = self.height() - inset * 2

        for fraction in (0.0, 0.5, 1.0):
            y = inset + h * (1 - fraction)
            pen = QtGui.QPen(QtGui.QColor(HAIRLINE), 1)
            if fraction:
                pen.setStyle(QtCore.Qt.DashLine)
            p.setPen(pen)
            p.drawLine(QtCore.QPointF(inset, y), QtCore.QPointF(inset + w, y))

        def at(i):
            x = inset + w * (i / (len(self.points) - 1))
            return QtCore.QPointF(x, inset + h * (1 - self.points[i]["accuracy"]))

        p.setPen(QtGui.QPen(QtGui.QColor(NAVY), 2,
                            QtCore.Qt.SolidLine, QtCore.Qt.RoundCap, QtCore.Qt.RoundJoin))
        path = QtGui.QPainterPath(at(0))
        for i in range(1, len(self.points)):
            path.lineTo(at(i))
        p.drawPath(path)

        p.setBrush(QtGui.QColor(CARD))
        for i in range(len(self.points)):
            p.drawEllipse(at(i), 3.5, 3.5)

        p.setPen(QtGui.QColor(MUTED))
        f = QtGui.QFont(); f.setPointSize(8); p.setFont(f)
        p.drawText(QtCore.QRectF(0, 2, 40, 14), QtCore.Qt.AlignLeft, "100%")
        p.drawText(QtCore.QRectF(0, self.height() - 16, 40, 14), QtCore.Qt.AlignLeft, "0%")
        p.drawText(QtCore.QRectF(self.width() - 50, self.height() - 16, 46, 14),
                   QtCore.Qt.AlignRight, L("latest"))
        p.end()


_SORTS = ("weakest", "most_answered", "least_covered", "slowest", "alphabetical")


def _sort_title(key):
    return {"weakest": L("Worst first"), "most_answered": L("Most answered"),
            "least_covered": L("Least covered"), "slowest": L("Slowest"),
            "alphabetical": L("A–Z")}[key]


class StatisticsScreen(QtWidgets.QWidget):
    practise_skill = QtCore.Signal(str, int)
    practise_section = QtCore.Signal(str, int)
    article_requested = QtCore.Signal(str)
    set_chosen = QtCore.Signal(str)

    def __init__(self, store, bank, parent=None, opens_on=None):
        super().__init__(parent)
        self.store = store
        self.bank = bank
        self.filter = opens_on if opens_on is not None else StatisticsFilter()
        self.sort = "weakest"
        self.setObjectName("statsScreen")
        self.setStyleSheet(f"QWidget#statsScreen{{background:{PAPER};}}")

        root = QtWidgets.QVBoxLayout(self)
        root.setContentsMargins(0, 0, 0, 0)
        self.area = QtWidgets.QScrollArea()
        self.area.setWidgetResizable(True)
        self.area.setFrameShape(QtWidgets.QFrame.NoFrame)
        root.addWidget(self.area)
        self.rebuild()

    def _footer_action(self, title, detail, slot):
        box = self._transparent()
        lay = QtWidgets.QVBoxLayout(box)
        lay.setContentsMargins(0, 0, 0, 0)
        lay.setSpacing(3)
        button = QtWidgets.QPushButton(title)
        button.setFlat(True)
        button.setCursor(QtCore.Qt.PointingHandCursor)
        button.setStyleSheet(
            f"QPushButton{{border:none; color:{WRONG}; font-size:11px;"
            "text-align:left; background:transparent;}")
        button.clicked.connect(slot)
        lay.addWidget(button, 0, QtCore.Qt.AlignLeft)
        note = QtWidgets.QLabel(detail)
        note.setWordWrap(True)
        leading(note)
        note.setStyleSheet(f"color:{MUTED}; font-size:10px; border:none;"
                           "background:transparent;")
        lay.addWidget(note)
        return box

    def _other_sets(self):
        out = []
        for bank in self.store.banks:
            if bank.id == self.bank.id:
                continue
            stats = self.store.statistics(bank.id)
            if stats.get("total_attempts"):
                out.append((bank, stats))
        return out

    def _other_sets_panel(self, others):
        panel, lay = self._panel(L("Your other sets"))
        blurb = QtWidgets.QLabel(
            L("You have answered questions in these. Statistics are kept per "
              "set, so choose one to see how it is going."))
        blurb.setWordWrap(True)
        leading(blurb)
        blurb.setStyleSheet(f"color:{MUTED}; font-size:11.5px; border:none;"
                            "background:transparent;")
        lay.addWidget(blurb)

        for bank, stats in others:
            row = QtWidgets.QPushButton()
            row.setCursor(QtCore.Qt.PointingHandCursor)
            row.setStyleSheet(
                "QPushButton{border:none; text-align:left; padding:6px 0;"
                "background:transparent;}"
                f"QPushButton:hover{{color:{BRASS_TEXT};}}")
            inner = QtWidgets.QHBoxLayout(row)
            inner.setContentsMargins(0, 6, 0, 6)
            inner.setSpacing(10)

            name = QtWidgets.QLabel(bank.name)
            name.setStyleSheet(f"color:{NAVY}; font-size:12px; font-weight:600;"
                               "border:none; background:transparent;")
            inner.addWidget(name)
            inner.addStretch(1)
            score = QtWidgets.QLabel(
                Lf("%1$d/%2$d correct", stats.get("total_correct", 0),
                   stats.get("total_attempts", 0)))
            score.setStyleSheet(f"color:{MUTED}; font-size:11px; border:none;"
                                "background:transparent;")
            inner.addWidget(score)
            arrow = QtWidgets.QLabel(brand.ICONS["shut"])
            arrow.setFont(QtGui.QFont(brand.ICON_FONT, 7))
            arrow.setStyleSheet(f"color:{MUTED}; border:none; background:transparent;")
            inner.addWidget(arrow)

            row.clicked.connect(lambda _=False, b=bank.id: self.set_chosen.emit(b))
            lay.addWidget(row)
        return panel

    def _start_over(self):
        seen, answers = self.store.reset_cost(self.bank.id)
        if not brand.ask(
                self, L("Practice this set from the beginning?"),
                Lf("All %1$d questions in \"%2$@\" go back to unseen, and the "
                   "%3$d answers behind these charts are forgotten. Your "
                   "highlights, your notes and the questions you set aside are "
                   "all kept.",
                   len(self.bank.questions), self.bank.name, answers),
                accept=L("Start over"), destructive=True):
            return
        self.store.reset_progress(self.bank.id)
        self.rebuild()

    def _panel(self, title):
        from .home import _card
        return _card(title)

    def _transparent(self):
        w = QtWidgets.QWidget()
        w.setStyleSheet("background:transparent;")
        return w

    def rebuild(self):
        from .home import SCROLLBAR, _label, _rule
        self.area.setStyleSheet(SCROLLBAR)
        stats = self.store.statistics(self.bank.id, filter=self.filter)
        whole = self.store.statistics(self.bank.id)
        sections = [b for b in whole["by_section"] if b["attempts"]]

        page = QtWidgets.QWidget()
        page.setObjectName("statsPage")
        page.setStyleSheet(f"QWidget#statsPage{{background:{PAPER};}}")
        lay = QtWidgets.QVBoxLayout(page)
        lay.setContentsMargins(32, 28, 32, 28)
        lay.setSpacing(22)

        title = QtWidgets.QLabel(L("Statistics"))
        title.setStyleSheet(
            f"color:{NAVY}; font-size:27px; font-weight:600; font-family:{SERIF};")
        lay.addWidget(title)
        lay.addWidget(_rule(brass=True, width=46))

        if not stats["has_data"] and not self.filter.narrows_anything:
            empty = QtWidgets.QLabel(
                f"<div style='font-size:16px; font-weight:600; color:{NAVY};"
                f"font-family:{SERIF}'>" + L("Nothing to show yet") + "</div>"
                f"<div style='font-size:12px; color:{MUTED}'>"
                + L("Finish a practice section and this fills in: which skills you "
                    "are strongest and weakest at, how you do by difficulty, and "
                    "whether you are improving.")
                + "</div>")
            empty.setWordWrap(True)
            leading(empty)
            empty.setAlignment(QtCore.Qt.AlignCenter)
            lay.addSpacing(40)
            lay.addWidget(empty)
            lay.addStretch(1)
            self.area.setWidget(page)
            return

        from .home import entrance
        self._arrived = 0

        def arrive(widget):
            lay.addWidget(entrance(widget, self._arrived))
            self._arrived += 1

        if not stats["has_data"]:
            arrive(self._cover_panel(stats))
            arrive(self._empty_slice(stats))
            if len(sections) > 1:
                arrive(self._section_panel(whole))
            lay.addStretch(1)
            self.area.setWidget(page)
            return

        sections_in_bank = [s for s in ("reading_writing", "math")
                            if any(q.subject == s for q in self.bank.questions)]
        if len(sections_in_bank) > 1 or self.filter.narrows_anything:
            arrive(self._cover_panel(stats))
        if len(sections) > 1:
            arrive(self._section_panel(whole))

        arrive(self._totals(stats))
        arrive(self._weakest(stats))
        arrive(self._by_domain(stats))
        if len([b for b in stats["by_difficulty"] if b["attempts"]]) >= 2:
            arrive(self._by_difficulty(stats))
        arrive(self._coverage(stats))
        if len(stats["trend"]) >= 2:
            arrive(self._trend(stats))
        arrive(self._pace(stats))
        if self.store.settings.get("showParentSummary", True):
            arrive(self._parent_panel())

        others = self._other_sets()
        if others:
            arrive(self._other_sets_panel(others))

        row = self._transparent()
        rl = QtWidgets.QHBoxLayout(row)
        rl.setContentsMargins(0, 0, 0, 0)
        rl.setSpacing(24)
        rl.addWidget(self._footer_action(
            L("Clear statistics"),
            L("Forgets every answer behind these charts. Which questions you "
              "have seen is kept, so your place in the set does not move."),
            self._clear), 1)
        rl.addWidget(self._footer_action(
            L("Practice this set from the beginning"),
            L("Puts all of it back to unseen so you can work through the same "
              "questions again. Highlights, notes and set-aside are kept."),
            self._start_over), 1)
        lay.addWidget(row)
        lay.addStretch(1)
        self.area.setWidget(page)

    def _set_sort(self, key):
        self.sort = key
        self.rebuild()

    def _chip_flow(self):
        from .home import FlowLayout
        holder = self._transparent()
        FlowLayout(holder, spacing=6)
        return holder

    def _filter_chip(self, label, selected, slot):
        b = QtWidgets.QPushButton(label)
        b.setCursor(QtCore.Qt.PointingHandCursor)
        ink = brand.readable_ink(BRASS)
        b.setStyleSheet(
            f"QPushButton{{background:{BRASS if selected else SUBTLE};"
            f"color:{ink if selected else INK}; border:1px solid "
            f"{BRASS if selected else HAIRLINE}; border-radius:3px;"
            f"padding:5px 12px; font-size:11px;"
            f"font-weight:{'600' if selected else '400'};}}"
            f"QPushButton:hover{{background:{BRASS if selected else PAPER_DEEP};}}")
        b.clicked.connect(lambda: slot())
        return b

    def _narrow(self, change):
        f = StatisticsFilter(self.filter.subjects, self.filter.domain,
                             self.filter.skill)
        change(f)
        if f.domain is not None and not any(
                (f.subjects is None or q.subject in f.subjects)
                and q.domain == f.domain for q in self.bank.questions):
            f.domain = None
        if f.skill is not None and not any(
                (f.subjects is None or q.subject in f.subjects)
                and (f.domain is None or q.domain == f.domain)
                and q.skill == f.skill for q in self.bank.questions):
            f.skill = None
        self.filter = f
        self.rebuild()

    def _filter_row(self, title, chips):
        box = self._transparent()
        bl = QtWidgets.QVBoxLayout(box)
        bl.setContentsMargins(0, 0, 0, 0)
        bl.setSpacing(7)
        head = QtWidgets.QLabel(title)
        head.setStyleSheet(f"color:{INK}; font-size:11px; font-weight:600;"
                           "border:none; background:transparent;")
        bl.addWidget(head)
        flow = self._chip_flow()
        for chip in chips:
            flow.layout().addWidget(chip)
        bl.addWidget(flow)
        return box

    def _cover_panel(self, s):
        card, lay = self._panel(L("What these figures cover"))
        f = self.filter
        sections = [x for x in ("reading_writing", "math")
                    if any(q.subject == x for q in self.bank.questions)]
        section_chips = [self._filter_chip(
            L("Both"), f.subjects is None,
            lambda: self._narrow(lambda g: setattr(g, "subjects", None)))]
        for subj in sections:
            section_chips.append(self._filter_chip(
                fulltest.section_label(subj),
                f.subjects is not None and f.subjects == {subj},
                lambda x=subj: self._narrow(lambda g: setattr(g, "subjects", {x}))))
        lay.addWidget(self._filter_row(L("Section"), section_chips))

        domains = sorted({q.domain for q in self.bank.questions
                          if q.domain and (f.subjects is None
                                           or q.subject in f.subjects)})
        domain_chips = [self._filter_chip(
            L("All domains"), f.domain is None,
            lambda: self._narrow(lambda g: setattr(g, "domain", None)))]
        for dom in domains:
            domain_chips.append(self._filter_chip(
                dom, f.domain == dom,
                lambda x=dom: self._narrow(lambda g: setattr(g, "domain", x))))
        lay.addWidget(self._filter_row(L("Domain"), domain_chips))

        skills = sorted({q.skill for q in self.bank.questions
                         if q.skill and (f.subjects is None or q.subject in f.subjects)
                         and (f.domain is None or q.domain == f.domain)})
        skill_chips = [self._filter_chip(
            L("All skills"), f.skill is None,
            lambda: self._narrow(lambda g: setattr(g, "skill", None)))]
        for sk in skills:
            skill_chips.append(self._filter_chip(
                sk, f.skill == sk,
                lambda x=sk: self._narrow(lambda g: setattr(g, "skill", x))))
        lay.addWidget(self._filter_row(L("Skill"), skill_chips))

        if f.narrows_anything:
            foot = self._transparent()
            fl = QtWidgets.QHBoxLayout(foot)
            fl.setContentsMargins(0, 4, 0, 0)
            fl.setSpacing(10)
            show_all = QtWidgets.QPushButton(L("Show everything"))
            show_all.setFlat(True)
            show_all.setCursor(QtCore.Qt.PointingHandCursor)
            show_all.setStyleSheet(f"QPushButton{{border:none; color:{BRASS_TEXT};"
                                   "font-size:11px; font-weight:600;"
                                   "background:transparent;}")
            show_all.clicked.connect(self._show_everything)
            fl.addWidget(show_all)
            count = QtWidgets.QLabel(
                Lp(s["total_attempts"], "%d answer in this slice",
                   "%d answers in this slice") if s["has_data"]
                else L("Nothing answered in this slice yet."))
            count.setStyleSheet(f"color:{MUTED}; font-size:10.5px; border:none;"
                                "background:transparent;")
            fl.addWidget(count)
            fl.addStretch(1)
            lay.addWidget(foot)
        return card

    def _show_everything(self):
        self.filter = StatisticsFilter()
        self.rebuild()

    def _section_panel(self, whole):
        from .home import _Clickable
        card, lay = self._panel(L("By section"))
        for row in [b for b in whole["by_section"] if b["attempts"]]:
            button = _Clickable()
            button.setCursor(QtCore.Qt.PointingHandCursor)
            button.setToolTip(L("Show only this section"))
            button.setStyleSheet("background:transparent;")
            rl = QtWidgets.QHBoxLayout(button)
            rl.setContentsMargins(0, 6, 0, 6)
            rl.setSpacing(12)
            name = ElidedLabel(row["label"])
            name.setFixedWidth(190)
            name.setStyleSheet(f"color:{INK}; font-size:12px; font-weight:600;"
                               "border:none; background:transparent;")
            rl.addWidget(name)
            rl.addWidget(AccuracyBar(row["accuracy"],
                                     _accuracy_colour(row["accuracy"])), 1)
            counts = QtWidgets.QLabel(f"{row['correct']}/{row['attempts']}")
            counts.setFixedWidth(54)
            counts.setAlignment(QtCore.Qt.AlignRight)
            counts.setStyleSheet(f"color:{MUTED}; font-size:11px; border:none;"
                                 "background:transparent;")
            rl.addWidget(counts)
            pct = QtWidgets.QLabel(f"{round(row['accuracy'] * 100)}%")
            pct.setFixedWidth(44)
            pct.setAlignment(QtCore.Qt.AlignRight)
            pct.setStyleSheet(
                f"color:{_accuracy_colour(row['accuracy'])}; font-size:12px;"
                "font-weight:600; border:none; background:transparent;")
            rl.addWidget(pct)
            subj = row["label_key"]
            button.clicked.connect(
                lambda _=False, x=subj: self._narrow(
                    lambda g: setattr(g, "subjects", {x})))
            lay.addWidget(button)
        gap = self._section_gap(whole)
        if gap:
            note = QtWidgets.QLabel(gap)
            note.setWordWrap(True)
            leading(note)
            note.setStyleSheet(f"color:{MUTED}; font-size:11px; border:none;"
                               "background:transparent;")
            lay.addWidget(note)
        return card

    def _section_gap(self, whole):
        rows = [b for b in whole["by_section"] if b["confident"]]
        if len(rows) != 2:
            return None
        low, high = sorted(rows, key=lambda b: b["accuracy"])
        gap = high["accuracy"] - low["accuracy"]
        if gap < 0.08:
            return L("The two sections are running at about the same accuracy.")
        return Lf("%1$@ is %2$d points behind %3$@ — that is where the marks are going.",
                  low["label"], round(gap * 100), high["label"])

    def _narrowed_to(self):
        parts = []
        if self.filter.subjects is not None:
            parts += [fulltest.section_label(s) for s in ("reading_writing", "math")
                      if s in self.filter.subjects]
        if self.filter.domain is not None:
            parts.append(self.filter.domain)
        if self.filter.skill is not None:
            parts.append(self.filter.skill)
        if not parts:
            return L("Nothing has been answered here yet.")
        return Lf("You have not answered anything in %@ in this set yet. Widen it "
                  "above, or practice some.", " · ".join(parts))

    def _only_subject(self):
        if self.filter.subjects is not None and len(self.filter.subjects) == 1:
            return next(iter(self.filter.subjects))
        return None

    def _empty_slice(self, s):
        box = self._transparent()
        bl = QtWidgets.QVBoxLayout(box)
        bl.setContentsMargins(0, 24, 0, 24)
        bl.setSpacing(10)
        heading = QtWidgets.QLabel(L("Nothing answered in this slice yet"))
        heading.setAlignment(QtCore.Qt.AlignCenter)
        heading.setStyleSheet(f"color:{NAVY}; font-size:16px; font-weight:600;"
                              f"font-family:{SERIF}; border:none;")
        bl.addWidget(heading)
        note = QtWidgets.QLabel(self._narrowed_to())
        note.setWordWrap(True)
        note.setAlignment(QtCore.Qt.AlignCenter)
        leading(note)
        note.setStyleSheet(f"color:{MUTED}; font-size:12px; border:none;")
        bl.addWidget(note)
        actions = self._transparent()
        al = QtWidgets.QHBoxLayout(actions)
        al.setContentsMargins(0, 0, 0, 0)
        al.setSpacing(10)
        al.setAlignment(QtCore.Qt.AlignHCenter)
        outline = (f"QPushButton{{border:1px solid {BORDER}; border-radius:3px;"
                   f"padding:7px 14px; font-size:11px; font-weight:600;"
                   f"color:{NAVY}; background:transparent;}}")
        show_all = QtWidgets.QPushButton(L("Show everything"))
        show_all.setCursor(QtCore.Qt.PointingHandCursor)
        show_all.setStyleSheet(outline)
        show_all.clicked.connect(self._show_everything)
        al.addWidget(show_all)
        subj = self._only_subject()
        if subj is not None:
            practise = QtWidgets.QPushButton(
                Lf("Practice %@", fulltest.section_label(subj)))
            practise.setCursor(QtCore.Qt.PointingHandCursor)
            practise.setStyleSheet(outline)
            practise.clicked.connect(
                lambda _=False, x=subj: self.practise_section.emit(x, 10))
            al.addWidget(practise)
        bl.addWidget(actions, 0, QtCore.Qt.AlignHCenter)
        return box

    def _totals(self, s):
        row = self._transparent()
        lay = QtWidgets.QHBoxLayout(row)
        lay.setContentsMargins(0, 0, 0, 0)
        lay.setSpacing(30)
        cells = [("%", L("overall"), s["accuracy"] * 100),
                 (f"{s['total_correct']}/{s['total_attempts']}", L("answered"), None),
                 ("", Lf("of %d seen", s["questions_available"]), s["questions_seen"])]
        if s["median_seconds"]:
            cells.append((_pace(s["median_seconds"]), L("typical question"), None))
        from .home import CountingLabel
        for value, label, counting in cells:
            tile = self._transparent()
            tl = QtWidgets.QVBoxLayout(tile)
            tl.setContentsMargins(0, 0, 0, 0)
            tl.setSpacing(0)
            big = (f"<div style='font-size:22px; font-weight:600; color:{NAVY};"
                   f"font-family:{NUMERALS}'>{{}}</div>")
            if counting is None:
                head = QtWidgets.QLabel(big.format(value))
                head.setStyleSheet("border:none; background:transparent;")
            else:
                head = CountingLabel(counting, big.replace("{}", "{}" + value))
            tl.addWidget(head)
            cap = QtWidgets.QLabel(
                f"<div style='font-size:9px; color:{MUTED}; letter-spacing:1px'>"
                f"{label.upper()}</div>")
            cap.setStyleSheet("border:none; background:transparent;")
            tl.addWidget(cap)
            lay.addWidget(tile)
        lay.addStretch(1)
        return row

    def _parent_panel(self):
        from . import parent as parent_summary
        summary = parent_summary.summary(self.store)
        card, lay = self._panel(L("For a parent"))

        blurb = QtWidgets.QLabel(
            L("A plain-language page about how this is going, in whichever "
              "language you have the app set to. Print it or send it."))
        blurb.setWordWrap(True)
        leading(blurb)
        blurb.setStyleSheet(f"color:{MUTED}; font-size:11px; border:none;")
        lay.addWidget(blurb)

        if summary["tiles"]:
            row = QtWidgets.QHBoxLayout()
            row.setSpacing(28)
            for value, label in summary["tiles"]:
                tile = QtWidgets.QLabel(
                    f"<div style='font-size:22px; font-weight:600; color:{NAVY};"
                    f"font-family:{NUMERALS}'>{value}</div>"
                    f"<div style='font-size:10px; color:{MUTED}'>{label}</div>")
                tile.setStyleSheet("border:none;")
                row.addWidget(tile)
            row.addStretch(1)
            lay.addLayout(row)

        for line in summary["lines"]:
            label = QtWidgets.QLabel(line)
            label.setWordWrap(True)
            leading(label)
            label.setStyleSheet(f"color:{INK}; font-size:12px; border:none;")
            lay.addWidget(label)
        for caveat in summary["caveats"]:
            label = QtWidgets.QLabel(caveat)
            label.setWordWrap(True)
            leading(label)
            label.setStyleSheet(f"color:{MUTED}; font-size:10px; border:none;")
            lay.addWidget(label)

        button = QtWidgets.QPushButton(L("Save as a page…"))
        button.setCursor(QtCore.Qt.PointingHandCursor)
        button.setEnabled(bool(summary["tiles"]))
        button.setStyleSheet(
            f"QPushButton{{background:{NAVY}; color:{CARD}; border-radius:3px;"
            "padding:7px 18px; font-size:12px; font-weight:600;}"
            f"QPushButton:disabled{{background:{SUBTLE}; color:{MUTED};}}")
        button.clicked.connect(lambda: self._save_parent_page(summary))
        holder = QtWidgets.QHBoxLayout()
        holder.addWidget(button)
        holder.addStretch(1)
        lay.addLayout(holder)
        return card

    def _save_parent_page(self, summary):
        from . import parent as parent_summary
        name = Lf("Practice summary — %@", summary.get("student", "")) + ".pdf"
        path, _ = QtWidgets.QFileDialog.getSaveFileName(
            self, L("Save as a page…"), brand.dialog_path(name), "PDF (*.pdf)")
        if not path:
            return
        brand.remember_folder(path)
        parent_summary.export(summary, path)
        brand.tell(self, L("For a parent"),
                   Lf("Saved %@", os.path.basename(path)))

    def _ranked_skills(self, s):
        rows = list(s["weakest"])
        if self.sort == "most_answered":
            return sorted(rows, key=lambda b: -b["attempts"])
        if self.sort == "least_covered":
            return sorted(rows, key=lambda b: b["coverage"])
        if self.sort == "slowest":
            return sorted(rows, key=lambda b: -b["average_seconds"])
        if self.sort == "alphabetical":
            return sorted(rows, key=lambda b: b["label"])
        return rows

    def _weakest(self, s):
        from .home import _label, _rule
        card, lay = self._panel(L("Where you are losing marks"))
        ranked = self._ranked_skills(s)
        if not ranked:
            note = QtWidgets.QLabel(
                Lf("Answer at least %d questions in a skill and it will be ranked "
                   "here. Below that a percentage says more about luck than about you.",
                   CONFIDENT_AT))
            note.setWordWrap(True)
            leading(note)
            note.setStyleSheet(f"color:{MUTED}; font-size:12px; border:none;")
            lay.addWidget(note)
        else:
            if len(ranked) > 1:
                order = self._transparent()
                ol = QtWidgets.QHBoxLayout(order)
                ol.setContentsMargins(0, 0, 0, 0)
                ol.setSpacing(8)
                caption = QtWidgets.QLabel(L("Order"))
                caption.setStyleSheet(f"color:{MUTED}; font-size:10.5px; border:none;"
                                      "background:transparent;")
                ol.addWidget(caption)
                flow = self._chip_flow()
                for key in _SORTS:
                    flow.layout().addWidget(self._filter_chip(
                        _sort_title(key), self.sort == key,
                        lambda k=key: self._set_sort(k)))
                ol.addWidget(flow, 1)
                lay.addWidget(order)
                lay.addWidget(_rule())
            weakest_id = min(ranked, key=lambda b: b["accuracy"])["label"]
            for i, row in enumerate(ranked):
                if i:
                    lay.addWidget(_rule())
                lay.addWidget(self._skill_row(
                    row, worst=(row["label"] == weakest_id and row["accuracy"] < 0.85)))
        if s["untested"]:
            lay.addWidget(_rule())
            lay.addWidget(_label(L("Not enough attempts to judge")))
            thin = QtWidgets.QLabel(" · ".join(
                f"{b['label']} ({b['attempts']})" for b in s["untested"]))
            thin.setWordWrap(True)
            leading(thin)
            thin.setStyleSheet(f"color:{MUTED}; font-size:11px; border:none;")
            lay.addWidget(thin)
        return card

    def _skill_row(self, row, worst):
        w = self._transparent()
        lay = QtWidgets.QHBoxLayout(w)
        lay.setContentsMargins(0, 8, 0, 8)
        lay.setSpacing(14)

        left = self._transparent()
        ll = QtWidgets.QVBoxLayout(left)
        ll.setContentsMargins(0, 0, 0, 0)
        ll.setSpacing(6)

        head = self._transparent()
        hl = QtWidgets.QHBoxLayout(head)
        hl.setContentsMargins(0, 0, 0, 0)
        hl.setSpacing(8)
        name = ElidedLabel(row["label"])
        name.setStyleSheet(
            f"color:{INK}; font-size:13px; border:none;"
            f"font-weight:{'600' if worst else '400'};")
        hl.addWidget(name)
        if worst:
            tag = QtWidgets.QLabel(L("Weakest").upper())
            tag.setStyleSheet(
                f"background:{BRASS}; color:{CARD}; font-size:8px; font-weight:700;"
                "letter-spacing:0.8px; padding:2px 5px;")
            hl.addWidget(tag)
        hl.addStretch(1)
        counts = QtWidgets.QLabel(f"{row['correct']}/{row['attempts']}")
        counts.setStyleSheet(f"color:{MUTED}; font-size:11px; border:none;")
        hl.addWidget(counts)
        pct = QtWidgets.QLabel(f"{round(row['accuracy'] * 100)}%")
        pct.setStyleSheet(
            f"color:{_accuracy_colour(row['accuracy'])}; font-size:12px;"
            "font-weight:600; border:none;")
        pct.setFixedWidth(44)
        pct.setAlignment(QtCore.Qt.AlignRight)
        hl.addWidget(pct)
        ll.addWidget(head)
        ll.addWidget(AccuracyBar(row["accuracy"], _accuracy_colour(row["accuracy"])))
        lay.addWidget(left, 1)

        practise = QtWidgets.QPushButton(L("Practice"))
        practise.setCursor(QtCore.Qt.PointingHandCursor)
        practise.setStyleSheet(
            f"QPushButton{{border:1px solid {BORDER}; border-radius:3px;"
            f"padding:6px 12px; font-size:11px; font-weight:600; color:{NAVY};"
            "background:transparent;}")
        count = min(10, max(5, row["available"]))
        practise.clicked.connect(
            lambda _=False, s=row["label"], n=count: self.practise_skill.emit(s, n))
        from .learn import ArticleLink
        link = ArticleLink.create(row["label"], compact=True)
        if link is None:
            lay.addWidget(practise)
        else:
            link.opened.connect(self.article_requested.emit)
            column = QtWidgets.QWidget()
            column.setStyleSheet("background:transparent;")
            cl = QtWidgets.QVBoxLayout(column)
            cl.setContentsMargins(0, 0, 0, 0)
            cl.setSpacing(5)
            cl.addWidget(practise, 0, QtCore.Qt.AlignRight)
            cl.addWidget(link, 0, QtCore.Qt.AlignRight)
            lay.addWidget(column)
        return w

    def _bar_rows(self, title, rows, value_key, label_fn, tint_fn):
        card, lay = self._panel(title)
        for row in rows:
            w = self._transparent()
            rl = QtWidgets.QHBoxLayout(w)
            rl.setContentsMargins(0, 0, 0, 0)
            rl.setSpacing(12)
            name = ElidedLabel(row["label"])
            name.setFixedWidth(190)
            name.setStyleSheet(f"color:{INK}; font-size:11px; border:none;")
            rl.addWidget(name)
            rl.addWidget(AccuracyBar(row[value_key], tint_fn(row)), 1)
            tail = QtWidgets.QLabel(label_fn(row))
            tail.setFixedWidth(96)
            tail.setAlignment(QtCore.Qt.AlignRight)
            tail.setStyleSheet(f"color:{MUTED}; font-size:10px; border:none;")
            rl.addWidget(tail)
            lay.addWidget(w)
        return card

    def _by_domain(self, s):
        rows = [b for b in s["by_domain"] if b["attempts"]]
        return self._bar_rows(
            L("By domain"), rows, "accuracy",
            lambda r: f"{r['correct']}/{r['attempts']}   {round(r['accuracy'] * 100)}%",
            lambda r: _accuracy_colour(r["accuracy"]))

    def _by_difficulty(self, s):
        card, lay = self._panel(L("By difficulty"))
        row = self._transparent()
        rl = QtWidgets.QHBoxLayout(row)
        rl.setContentsMargins(0, 0, 0, 0)
        rl.setSpacing(26)
        for b in [x for x in s["by_difficulty"] if x["attempts"]]:
            col = self._transparent()
            cl = QtWidgets.QVBoxLayout(col)
            cl.setAlignment(QtCore.Qt.AlignBottom | QtCore.Qt.AlignHCenter)
            pct = QtWidgets.QLabel(f"{round(b['accuracy'] * 100)}%")
            pct.setAlignment(QtCore.Qt.AlignCenter)
            pct.setStyleSheet(
                f"color:{_accuracy_colour(b['accuracy'])}; font-size:17px;"
                f"font-weight:600; font-family:{NUMERALS}; border:none;")
            bar = GrowingColumn(b["accuracy"], _accuracy_colour(b["accuracy"]))
            name = ElidedLabel(b["label"])
            name.setAlignment(QtCore.Qt.AlignCenter)
            name.setStyleSheet(f"color:{INK}; font-size:11px; font-weight:500; border:none;")
            counts = QtWidgets.QLabel(f"{b['correct']}/{b['attempts']}")
            counts.setAlignment(QtCore.Qt.AlignCenter)
            counts.setStyleSheet(f"color:{MUTED}; font-size:10px; border:none;")
            cl.addWidget(pct)
            cl.addWidget(bar, 0, QtCore.Qt.AlignHCenter)
            cl.addWidget(name)
            cl.addWidget(counts)
            rl.addWidget(col)
        rl.addStretch(1)
        lay.addWidget(row)
        return card

    def _coverage(self, s):
        rows = sorted([b for b in s["by_skill"] if b["available"]],
                      key=lambda b: b["coverage"])
        return self._bar_rows(
            L("How much of the bank you have covered"), rows, "coverage",
            lambda r: f"{r['seen']}/{r['available']}",
            lambda r: NAVY)

    def _trend(self, s):
        card, lay = self._panel(L("Accuracy over your last sittings"))
        lay.addWidget(TrendChart(s["trend"]))
        note = QtWidgets.QLabel(L("Each point is one sitting: answers separated by "
                                "more than half an hour start a new one."))
        note.setStyleSheet(f"color:{MUTED}; font-size:10px; border:none;")
        lay.addWidget(note)
        return card

    def _pace(self, s):
        rows = sorted([b for b in s["by_skill"]
                       if b["average_seconds"] > 0 and b["confident"]],
                      key=lambda b: -b["average_seconds"])
        card, lay = self._panel(L("Pace"))
        if not rows:
            note = QtWidgets.QLabel(L("Once you have answered a few more questions "
                                    "this shows which kinds take you longest."))
            note.setWordWrap(True)
            leading(note)
            note.setStyleSheet(f"color:{MUTED}; font-size:12px; border:none;")
            lay.addWidget(note)
            return card
        slowest = rows[0]["average_seconds"]
        for b in rows:
            w = self._transparent()
            rl = QtWidgets.QHBoxLayout(w)
            rl.setContentsMargins(0, 0, 0, 0)
            rl.setSpacing(12)
            name = ElidedLabel(b["label"])
            name.setFixedWidth(190)
            name.setStyleSheet(f"color:{INK}; font-size:11px; border:none;")
            rl.addWidget(name)
            rl.addWidget(AccuracyBar(b["average_seconds"] / slowest if slowest else 0,
                                     BRASS), 1)
            tail = QtWidgets.QLabel(_pace(b["average_seconds"]))
            tail.setFixedWidth(70)
            tail.setAlignment(QtCore.Qt.AlignRight)
            tail.setStyleSheet(f"color:{MUTED}; font-size:10px; border:none;")
            rl.addWidget(tail)
            lay.addWidget(w)
        return card

    def _clear(self):
        if brand.ask(
                self, L("Clear the statistics?"),
                L("This clears the record of every answer you have given, so the "
                  "charts start over. Which questions you have seen, your set-aside "
                  "list, and your notes are all kept."),
                accept=L("Clear them"), destructive=True):
            self.store.clear_history(self.bank.id)
            self.rebuild()

brand.adopt(__name__)
