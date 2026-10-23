from __future__ import annotations

import os

from PySide6 import QtCore, QtGui, QtWidgets

from . import articles as art
from . import brand
from .i18n import L, Lf, Lp
from .ui import (BRASS, BRASS_TEXT, CARD, HAIRLINE, INK, MUTED, NAVY, PAPER, SCROLLBAR,
                 SERIF, SUBTLE, discard_layout, leading)


MEASURE = 720
GUTTER = 28

PROSE_LEADING = 1.50
LIST_LEADING = 1.40


class _Measured(QtWidgets.QWidget):

    def __init__(self, inner, parent=None):
        super().__init__(parent)
        self.setObjectName("measured")
        self.setAttribute(QtCore.Qt.WA_StyledBackground, True)
        self.setStyleSheet(f"QWidget#measured{{background:{PAPER};}}")
        self._inner = inner
        inner.setParent(self)
        inner.show()

    def _column(self, width):
        return max(200, min(MEASURE, width - 2 * GUTTER))

    def hasHeightForWidth(self):
        return True

    def heightForWidth(self, width):
        column = self._column(width)
        layout = self._inner.layout()
        if layout is not None and layout.hasHeightForWidth():
            return layout.heightForWidth(column)
        return self._inner.sizeHint().height()

    def sizeHint(self):
        return QtCore.QSize(MEASURE + 2 * GUTTER,
                            self.heightForWidth(MEASURE + 2 * GUTTER))

    def minimumSizeHint(self):
        return QtCore.QSize(200 + 2 * GUTTER, 0)

    def resizeEvent(self, event):
        column = self._column(self.width())
        wanted = self.heightForWidth(self.width())
        if wanted != self.minimumHeight():
            self.setMinimumHeight(wanted)
        self._inner.setGeometry((self.width() - column) // 2, 0,
                                column, max(wanted, self.height()))
        super().resizeEvent(event)


def _measured(inner):
    return _Measured(inner)


def _flows(widget):
    policy = widget.sizePolicy()
    policy.setHeightForWidth(True)
    policy.setVerticalPolicy(QtWidgets.QSizePolicy.Preferred)
    widget.setSizePolicy(policy)
    return widget


def _stack(spacing=0, margins=(0, 0, 0, 0)):
    box = _flows(QtWidgets.QWidget())
    box.setStyleSheet("background:transparent;")
    lay = QtWidgets.QVBoxLayout(box)
    lay.setContentsMargins(*margins)
    lay.setSpacing(spacing)
    return box, lay


def _hanging(mark, body, spacing=9):
    row = _flows(QtWidgets.QWidget())
    row.setStyleSheet("background:transparent;")
    lay = QtWidgets.QHBoxLayout(row)
    lay.setContentsMargins(0, 0, 0, 0)
    lay.setSpacing(spacing)
    lay.addWidget(mark, 0, QtCore.Qt.AlignTop)
    lay.addWidget(body, 1)
    return row


def _prose(text, size=13.5, colour=None, ratio=PROSE_LEADING, weight=None,
           rich=False):
    label = QtWidgets.QLabel(text)
    label.setWordWrap(True)
    label.setStyleSheet(
        f"color:{colour or INK}; font-size:{size}px; border:none;"
        "background:transparent;"
        + (f"font-weight:{weight};" if weight else ""))
    return leading(label, ratio, rich=rich)


def _rule(width=None, brass=True):
    line = QtWidgets.QFrame()
    line.setFrameShape(QtWidgets.QFrame.HLine)
    line.setFixedHeight(1)
    line.setStyleSheet(f"background:{BRASS if brass else HAIRLINE}; border:none;"
                       "max-height:1px;")
    if width:
        line.setFixedWidth(width)
    return line


def _disclaimer():
    box = _flows(QtWidgets.QFrame())
    box.setObjectName("articleNote")
    box.setStyleSheet(f"QFrame#articleNote{{border:none; border-left:2px solid {BRASS};}}")
    lay = QtWidgets.QHBoxLayout(box)
    lay.setContentsMargins(10, 2, 0, 2)
    lay.setSpacing(0)
    lay.addWidget(_prose(
        L("These articles cover the basics of each skill and nothing more. They "
          "are a place to start, not a course, and they will not on their own get "
          "you any particular score. Real preparation means working through "
          "questions, and reading properly about the topics you find hard — this "
          "is only meant to help you begin."),
        size=10.5, colour=MUTED, ratio=1.35), 1)
    return box


def _leave_bar(label, slot, tip=None, back_icon="shut_left", trailing=None,
               on_card=False):
    bar = QtWidgets.QWidget()
    bar.setObjectName("leaveBar")
    bar.setAttribute(QtCore.Qt.WA_StyledBackground, True)
    bar.setStyleSheet(f"QWidget#leaveBar{{background:{CARD if on_card else PAPER};}}")
    lay = QtWidgets.QHBoxLayout(bar)
    lay.setContentsMargins(GUTTER, 16, GUTTER, 12)
    lay.setSpacing(14)

    back = brand.IconButton(back_icon, label, MUTED, NAVY, size=11)
    if tip:
        back.setToolTip(tip)
    back.setStyleSheet(
        f"QPushButton{{border:none; color:{MUTED}; font-size:12px;"
        "background:transparent; text-align:left;}"
        f"QPushButton:hover{{color:{NAVY};}}")
    back.clicked.connect(slot)
    lay.addWidget(back)
    lay.addStretch(1)

    leave = QtWidgets.QLabel(L("Esc to leave"))
    leave.setStyleSheet(f"color:{MUTED}; font-size:10px; background:transparent;")
    lay.addWidget(leave)
    if trailing:
        dot = QtWidgets.QLabel("·")
        dot.setStyleSheet(f"color:{HAIRLINE}; font-size:10px; background:transparent;")
        lay.addWidget(dot)
        what = QtWidgets.QLabel(trailing)
        what.setStyleSheet(f"color:{MUTED}; font-size:10.5px; background:transparent;")
        lay.addWidget(what)
    return bar


class ArticleLink(QtWidgets.QPushButton):

    opened = QtCore.Signal(str)

    @classmethod
    def create(cls, skill, compact=False, parent=None):
        article = art.for_skill(skill)
        if article is None:
            return None
        return cls(article, skill, compact=compact, parent=parent)

    def __init__(self, article, skill, compact=False, parent=None):
        size = 10.5 if compact else 11.5
        super().__init__(Lf("Read about %@", skill), parent)
        self.article = article
        self.setIcon(brand.icon("learn", 9 if compact else 10, BRASS))
        self.setIconSize(QtCore.QSize(9 if compact else 10, 9 if compact else 10))
        self.setCursor(QtCore.Qt.PointingHandCursor)
        self.setToolTip(article.get("summary", ""))
        self.setStyleSheet(
            f"QPushButton{{border:none; background:transparent; color:{BRASS_TEXT};"
            f"font-size:{size}px; font-weight:500; text-align:left; padding:2px 0;}}"
            f"QPushButton:hover{{color:{NAVY};}}")
        self.clicked.connect(
            lambda: self.opened.emit(self.article.get("id", "")))
        self._full = self.text()
        self.setAccessibleName(self._full)

    def minimumSizeHint(self):
        hint = super().minimumSizeHint()
        return QtCore.QSize(min(hint.width(), self.iconSize().width() + 120), hint.height())

    def resizeEvent(self, event):
        super().resizeEvent(event)
        room = self.width() - self.iconSize().width() - 14
        shown = self.fontMetrics().elidedText(self._full, QtCore.Qt.ElideRight, max(60, room))
        if shown != self.text():
            self.setText(shown)


class LearnScreen(QtWidgets.QWidget):

    opened = QtCore.Signal(str)
    closed = QtCore.Signal()

    def __init__(self, store, parent=None, scroll_to=None):
        super().__init__(parent)
        self.store = store
        self.query = ""
        self._scroll_to = scroll_to
        self._rows = {}
        self.setStyleSheet(f"background:{PAPER};")
        self.setFocusPolicy(QtCore.Qt.StrongFocus)
        self._build()

    def keyPressEvent(self, event):
        if event.key() == QtCore.Qt.Key_Escape:
            self.closed.emit()
            return
        super().keyPressEvent(event)

    def _build(self, fade=True):
        from .home import entrance
        discard_layout(self)
        outer = QtWidgets.QVBoxLayout(self)
        outer.setContentsMargins(0, 0, 0, 0)
        outer.setSpacing(0)
        outer.addWidget(_leave_bar(L("Library"), self.closed.emit,
                                   L("Back to the library"), on_card=True))
        outer.addWidget(_rule(brass=False))

        scroll = QtWidgets.QScrollArea()
        scroll.setWidgetResizable(True)
        scroll.setFrameShape(QtWidgets.QFrame.NoFrame)
        scroll.setHorizontalScrollBarPolicy(QtCore.Qt.ScrollBarAlwaysOff)
        scroll.setStyleSheet(SCROLLBAR + f"QScrollArea{{background:{PAPER};}}")

        column = _flows(QtWidgets.QWidget())
        column.setStyleSheet("background:transparent;")
        lay = QtWidgets.QVBoxLayout(column)
        lay.setContentsMargins(0, 26, 0, 24)
        lay.setSpacing(26)

        lay.addWidget(entrance(self._header(), 0) if fade else self._header())

        sections = self._sections()
        if not sections:
            empty = QtWidgets.QLabel(L("Nothing matches that."))
            empty.setContentsMargins(0, 30, 0, 0)
            empty.setStyleSheet(f"color:{MUTED}; font-size:12px;")
            lay.addWidget(empty)
        for index, (subject, groups) in enumerate(sections):
            section = self._subject_section(subject, groups)
            lay.addWidget(entrance(section, 1 + index) if fade else section)

        lay.addStretch(1)
        scroll.setWidget(_measured(column))
        outer.addWidget(scroll)
        self._scroll = scroll
        if self._scroll_to and self._scroll_to in self._rows:
            row = self._rows[self._scroll_to]
            QtCore.QTimer.singleShot(
                0, lambda: scroll.ensureWidgetVisible(row, 0, scroll.height() // 3))
        if self.query:
            self._search_box.setFocus()
            self._search_box.setCursorPosition(len(self.query))

    def _sections(self):
        groups = art.grouped(art.search(self.query))
        out = []
        for subject in ("readingWriting", "math"):
            mine = [(domain, items) for s, domain, items in groups if s == subject]
            if mine:
                out.append((subject, mine))
        return out

    def _header(self):
        header = _flows(QtWidgets.QWidget())
        header.setStyleSheet("background:transparent;")
        head_lay = QtWidgets.QVBoxLayout(header)
        head_lay.setContentsMargins(0, 0, 0, 0)
        head_lay.setSpacing(10)

        title = QtWidgets.QLabel(L("Learn"))
        title.setStyleSheet(
            f"color:{NAVY}; font-size:26px; font-weight:600; font-family:{SERIF};")
        head_lay.addWidget(title)
        head_lay.addWidget(_rule(60))

        head_lay.addWidget(_prose(
            L("Short explanations of what each skill is actually about, written "
              "for a student who wants the idea rather than another question. "
              "They work offline like everything else here."),
            size=12, colour=MUTED, ratio=1.40))

        box = QtWidgets.QLineEdit(self.query)
        box.setPlaceholderText(L("Search the articles"))
        box.setAccessibleName(L("Search the articles"))
        box.setMaximumWidth(320)
        box.setStyleSheet(
            f"QLineEdit{{background:{CARD}; border:1px solid {HAIRLINE};"
            f"border-radius:3px; padding:6px 8px; color:{INK}; font-size:12px;}}")
        box.textChanged.connect(self._search)
        self._search_box = box
        head_lay.addWidget(box)
        head_lay.addSpacing(4)
        head_lay.addWidget(_disclaimer())
        return header

    def _subject_section(self, subject, groups):
        box = _flows(QtWidgets.QWidget())
        box.setStyleSheet("background:transparent;")
        lay = QtWidgets.QVBoxLayout(box)
        lay.setContentsMargins(0, 0, 0, 0)
        lay.setSpacing(16)

        head = QtWidgets.QWidget()
        head.setStyleSheet("background:transparent;")
        head_row = QtWidgets.QHBoxLayout(head)
        head_row.setContentsMargins(0, 0, 0, 0)
        head_row.setSpacing(10)
        name = QtWidgets.QLabel(
            L("Math") if subject == "math" else L("Reading and Writing"))
        name.setStyleSheet(
            f"color:{NAVY}; font-size:19px; font-weight:600; font-family:{SERIF};"
            "background:transparent;")
        head_row.addWidget(name)
        head_row.addWidget(_rule(brass=False), 1)
        lay.addWidget(head)

        for domain, items in groups:
            group = _flows(QtWidgets.QWidget())
            group.setStyleSheet("background:transparent;")
            glay = QtWidgets.QVBoxLayout(group)
            glay.setContentsMargins(0, 0, 0, 0)
            glay.setSpacing(8)
            label = QtWidgets.QLabel(domain.upper())
            label.setStyleSheet(
                f"color:{MUTED}; font-size:10px; font-weight:600;"
                "letter-spacing:1.5px; background:transparent;")
            glay.addWidget(label)
            for article in items:
                glay.addWidget(self._row(article))
            lay.addWidget(group)
        return box

    def _search(self, text):
        self.query = text
        self._build(fade=False)

    def _row(self, article):
        card = _flows(_CardRow())
        card.setObjectName("articleRow")
        card.setCursor(QtCore.Qt.PointingHandCursor)
        card.setStyleSheet(
            f"QWidget#articleRow{{background:{CARD}; border:1px solid {HAIRLINE};"
            "border-radius:4px;}"
            f"QWidget#articleRow:hover{{border:1px solid {BRASS};}}")
        lay = QtWidgets.QVBoxLayout(card)
        lay.setContentsMargins(14, 14, 14, 14)
        lay.setSpacing(3)

        title = QtWidgets.QLabel(article.get("title", ""))
        title.setWordWrap(True)
        leading(title)
        title.setStyleSheet(
            f"color:{NAVY}; font-size:14px; font-weight:600; font-family:{SERIF};"
            "border:none; background:transparent;")
        lay.addWidget(title)

        summary = QtWidgets.QLabel(article.get("summary", ""))
        summary.setWordWrap(True)
        leading(summary)
        summary.setStyleSheet(
            f"color:{INK}; font-size:11.5px; border:none; background:transparent;")
        lay.addWidget(summary)

        card.clicked.connect(lambda i=article.get("id"): self.opened.emit(i))
        self._rows[article.get("id")] = card
        return card


class _CardRow(QtWidgets.QWidget):

    clicked = QtCore.Signal()

    def __init__(self, parent=None):
        super().__init__(parent)
        self.setAttribute(QtCore.Qt.WA_StyledBackground, True)

    def mousePressEvent(self, event):
        if event.button() == QtCore.Qt.LeftButton:
            self.clicked.emit()
            return
        super().mousePressEvent(event)
class ArticleScreen(QtWidgets.QWidget):

    back = QtCore.Signal()

    def __init__(self, article, parent=None):
        super().__init__(parent)
        self.article = article
        self.setStyleSheet(f"background:{PAPER};")
        self.setFocusPolicy(QtCore.Qt.StrongFocus)
        self._build()

    def keyPressEvent(self, event):
        if event.key() == QtCore.Qt.Key_Escape:
            self.back.emit()
            return
        super().keyPressEvent(event)

    def _build(self):
        outer = QtWidgets.QVBoxLayout(self)
        outer.setContentsMargins(0, 0, 0, 0)
        outer.setSpacing(0)
        outer.addWidget(_leave_bar(
            L("Learn"), self.back.emit,
            trailing=self.article.get("domain", "")))
        outer.addWidget(_rule(brass=False))

        scroll = QtWidgets.QScrollArea()
        scroll.setWidgetResizable(True)
        scroll.setFrameShape(QtWidgets.QFrame.NoFrame)
        scroll.setHorizontalScrollBarPolicy(QtCore.Qt.ScrollBarAlwaysOff)
        scroll.setStyleSheet(SCROLLBAR + f"QScrollArea{{background:{PAPER};}}")

        column = _flows(QtWidgets.QWidget())
        column.setStyleSheet("background:transparent;")
        lay = QtWidgets.QVBoxLayout(column)
        lay.setContentsMargins(0, 30, 0, 30)
        lay.setSpacing(16)

        head = _flows(QtWidgets.QWidget())
        head.setStyleSheet("background:transparent;")
        head_lay = QtWidgets.QVBoxLayout(head)
        head_lay.setContentsMargins(0, 0, 0, 4)
        head_lay.setSpacing(8)
        title = QtWidgets.QLabel(self.article.get("title", ""))
        title.setWordWrap(True)
        leading(title)
        title.setStyleSheet(
            f"color:{NAVY}; font-size:24px; font-weight:600; font-family:{SERIF};"
            "background:transparent;")
        head_lay.addWidget(title)
        head_lay.addWidget(_prose(self.article.get("summary", ""),
                                  size=13, colour=MUTED, ratio=1.40))
        lay.addWidget(head)

        for block in self.article.get("blocks", []):
            widget = self._block(block)
            if widget is not None:
                lay.addWidget(widget)

        lay.addSpacing(10)
        lay.addWidget(_rule(brass=False))
        lay.addWidget(_disclaimer())
        lay.addStretch(1)

        scroll.setWidget(_measured(column))
        outer.addWidget(scroll)

    def _block(self, block):
        kind = block.get("kind", "paragraph")
        if kind == "heading":
            w = QtWidgets.QLabel(block.get("text", ""))
            w.setWordWrap(True)
            leading(w)
            w.setContentsMargins(0, 8, 0, 0)
            w.setStyleSheet(
                f"color:{NAVY}; font-size:16px; font-weight:600; font-family:{SERIF};"
                "background:transparent;")
            return w

        if kind == "paragraph":
            return _prose(self._inline(block.get("text", "")), rich=True)

        if kind == "list":
            box, lay = _stack(spacing=7, margins=(2, 0, 0, 0))
            for i, item in enumerate(block.get("items", [])):
                mark = QtWidgets.QLabel(
                    ("%d." % (i + 1)) if block.get("ordered") else "•")
                mark.setFixedWidth(16)
                mark.setAlignment(QtCore.Qt.AlignRight | QtCore.Qt.AlignTop)
                mark.setStyleSheet(
                    f"color:{BRASS_TEXT}; font-size:12px; font-weight:600;"
                    "border:none; background:transparent;")
                lay.addWidget(_hanging(mark, _prose(self._inline(item), rich=True, size=13,
                                                    ratio=LIST_LEADING)))
            return box

        if kind == "rule":
            box = _flows(QtWidgets.QFrame())
            box.setObjectName("articleRule")
            box.setStyleSheet(
                f"QFrame#articleRule{{border:none; border-left:2px solid {BRASS};}}")
            bl = QtWidgets.QHBoxLayout(box)
            bl.setContentsMargins(12, 4, 0, 4)
            bl.setSpacing(0)
            bl.addWidget(_prose(self._inline(block.get("text", "")), rich=True,
                                colour=NAVY, weight=500), 1)
            return box

        if kind == "diagram":
            if block.get("text") == "reference-sheet":
                return self._reference_sheet(block.get("answer", ""))
            supplied = self._supplied_figure(block.get("text", ""),
                                             block.get("answer", ""))
            if supplied is not None:
                return supplied
            return None

        box = _flows(QtWidgets.QFrame())
        box.setObjectName("articleExample")
        box.setStyleSheet(
            f"QFrame#articleExample{{background:{SUBTLE}; border:1px solid {HAIRLINE};"
            "border-radius:4px;}")
        bl = QtWidgets.QVBoxLayout(box)
        bl.setContentsMargins(14, 14, 14, 14)
        bl.setSpacing(7)
        prompt = QtWidgets.QLabel(block.get("text", ""))
        prompt.setWordWrap(True)
        leading(prompt)
        prompt.setStyleSheet(
            f"color:{NAVY}; font-size:13px; font-weight:600; border:none;"
            "background:transparent;")
        bl.addWidget(prompt)
        for step in block.get("items", []):
            arrow = QtWidgets.QLabel("→")
            arrow.setAlignment(QtCore.Qt.AlignTop)
            arrow.setStyleSheet(f"color:{MUTED}; font-size:11px; border:none;"
                                "background:transparent;")
            text = QtWidgets.QLabel(step)
            text.setWordWrap(True)
            leading(text)
            text.setStyleSheet(f"color:{INK}; font-size:12.5px; border:none;"
                               "background:transparent;")
            bl.addWidget(_hanging(arrow, text, spacing=8))
        if block.get("answer"):
            answer = QtWidgets.QLabel(block["answer"])
            answer.setWordWrap(True)
            leading(answer)
            answer.setContentsMargins(0, 2, 0, 0)
            answer.setStyleSheet(
                f"color:{BRASS_TEXT}; font-size:13px; font-weight:600; border:none;"
                "background:transparent;")
            bl.addWidget(answer)
        return box
    def _supplied_figure(self, name, caption):
        base = brand.artwork(os.path.join("figures", name))
        if base is None:
            return None
        accent = brand.artwork(os.path.join("figures", name + "-accent"))

        width = min(560, 720 - 40)
        height = int(width * base.height() / max(1, base.width()))
        canvas = QtGui.QPixmap(width, height)
        canvas.fill(QtCore.Qt.transparent)
        painter = QtGui.QPainter(canvas)
        painter.setRenderHint(QtGui.QPainter.SmoothPixmapTransform, True)
        rect = QtCore.QRectF(0, 0, width, height)
        brand.paint_artwork(painter, rect, base, QtGui.QColor(INK))
        if accent is not None:
            brand.paint_artwork(painter, rect, accent, QtGui.QColor(BRASS))
        painter.end()

        box = QtWidgets.QWidget()
        lay = QtWidgets.QVBoxLayout(box)
        lay.setContentsMargins(0, 0, 0, 0)
        lay.setSpacing(6)
        holder = QtWidgets.QLabel()
        holder.setPixmap(canvas)
        holder.setAlignment(QtCore.Qt.AlignCenter)
        holder.setStyleSheet(
            f"background:{SUBTLE}; border:1px solid {HAIRLINE}; border-radius:4px;"
            "padding:10px;")
        lay.addWidget(holder)
        if caption:
            cap = QtWidgets.QLabel(caption)
            cap.setWordWrap(True)
            leading(cap)
            cap.setStyleSheet(f"color:{MUTED}; font-size:11px; border:none;")
            lay.addWidget(cap)
        return box

    def _reference_sheet(self, caption):
        from .reference import _Sheet
        box = QtWidgets.QWidget()
        lay = QtWidgets.QVBoxLayout(box)
        lay.setContentsMargins(0, 0, 0, 0)
        lay.setSpacing(6)

        sheet = _Sheet()
        sheet.resize(1010, 445)
        image = QtGui.QPixmap(sheet.size())
        from . import reference
        image.fill(QtGui.QColor(reference.CARD))
        sheet.render(image)
        holder = QtWidgets.QLabel()
        holder.setPixmap(image.scaledToWidth(660, QtCore.Qt.SmoothTransformation))
        holder.setAlignment(QtCore.Qt.AlignCenter)
        holder.setStyleSheet(
            f"background:{reference.CARD}; border:1px solid {HAIRLINE};"
            "border-radius:4px; padding:8px;")
        lay.addWidget(holder)

        if caption:
            cap = QtWidgets.QLabel(caption)
            cap.setWordWrap(True)
            leading(cap)
            cap.setStyleSheet(f"color:{MUTED}; font-size:11px; border:none;")
            lay.addWidget(cap)
        return box

    @staticmethod
    def _inline(text):
        from html import escape
        parts = escape(text).split("**")
        return "".join(p if i % 2 == 0 else "<b>%s</b>" % p
                       for i, p in enumerate(parts))

brand.adopt(__name__)
