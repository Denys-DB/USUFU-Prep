from __future__ import annotations

import os
import random
import textwrap

from PySide6 import QtCore, QtGui, QtWidgets

from . import brand
from . import vocab
from .ui import (BORDER, BRASS, BRASS_TEXT, BRASS_SOFT, CARD, CORRECT, HAIRLINE, INK,
                 MUTED, NAVY, ON_BRAND, PAPER, PAPER_DEEP, SERIF, NUMERALS, SUBTLE,
                 WRONG, WRONG_SOFT, ElidedLabel, framed_spin, leading)
from .i18n import L, Lf, Lp

ANIMATIONS_ON = not os.environ.get("SATPREP_NO_ANIMATION")

def _scrollbar_style():
    return f"""
QScrollBar:vertical {{ background: transparent; width: 10px; margin: 0; }}
QScrollBar::handle:vertical {{ background: {BORDER}; border-radius: 5px; min-height: 36px; }}
QScrollBar::handle:vertical:hover {{ background: {BRASS}; }}
QScrollBar::add-line:vertical, QScrollBar::sub-line:vertical {{ height: 0; }}
QScrollBar::add-page:vertical, QScrollBar::sub-page:vertical {{ background: transparent; }}
"""


SCROLLBAR = _scrollbar_style()


def rebuild_derived():
    global SCROLLBAR
    SCROLLBAR = _scrollbar_style()



def _rule(brass=False):
    line = QtWidgets.QFrame()
    line.setFixedHeight(1)
    line.setStyleSheet(f"background:{BRASS if brass else HAIRLINE}; border:none;")
    return line


def _label(text):
    lbl = QtWidgets.QLabel(text.upper())
    lbl.setStyleSheet(
        f"color:{MUTED}; font-size:10px; font-weight:600; letter-spacing:1.5px; border:none;")
    return lbl


def _primary(text):
    b = QtWidgets.QPushButton(text.replace("&", "&&"))
    b.setCursor(QtCore.Qt.PointingHandCursor)
    b.setStyleSheet(
        f"QPushButton{{background:{NAVY}; color:{CARD}; border:none; border-radius:3px;"
        "padding:9px 20px; font-size:12px; font-weight:600;}"
        f"QPushButton:hover{{background:{NAVY};}}"
        f"QPushButton:disabled{{background:{SUBTLE}; color:{MUTED};}}")
    return b


def _secondary(text):
    b = QtWidgets.QPushButton(text.replace("&", "&&"))
    b.setCursor(QtCore.Qt.PointingHandCursor)
    b.setStyleSheet(
        f"QPushButton{{background:transparent; color:{NAVY}; border:1px solid {BORDER};"
        "border-radius:3px; padding:9px 18px; font-size:12px; font-weight:600;}"
        f"QPushButton:hover{{background:{BRASS_SOFT};}}"
        f"QPushButton:disabled{{color:{MUTED}; border-color:{HAIRLINE};}}")
    return b


def _room_for_bold(button):
    button.ensurePolished()
    regular = QtGui.QFontMetrics(button.font())
    heavy = QtGui.QFont(button.font())
    heavy.setWeight(QtGui.QFont.DemiBold)
    extra = (QtGui.QFontMetrics(heavy).horizontalAdvance(button.text())
             - regular.horizontalAdvance(button.text()))
    if extra > 0:
        button.setMinimumWidth(button.sizeHint().width() + extra)
    return button


def _chip(text, checked, count=None):
    b = QtWidgets.QPushButton(text.replace("&", "&&") if count is None
                              else f"{text}  {count}")
    b.setCheckable(True)
    b.setChecked(checked)
    b.setCursor(QtCore.Qt.PointingHandCursor)
    b.setStyleSheet(
        f"QPushButton{{background:{SUBTLE}; color:{INK}; border:1px solid {HAIRLINE};"
        "border-radius:3px; padding:6px 14px; font-size:12px;}"
        f"QPushButton:hover{{background:{PAPER_DEEP};}}"
        f"QPushButton:checked{{background:{BRASS}; color:{CARD}; font-weight:600;"
        "border:1px solid transparent;}"
        f"QPushButton:disabled{{color:{MUTED};}}")
    return _room_for_bold(b)


def _icon_button(glyph, tip, checked=False):
    b = QtWidgets.QPushButton(glyph)
    if glyph and 0xE000 <= ord(glyph[0]) <= 0xF8FF:
        b.setFont(QtGui.QFont(brand.ICON_FONT, 9))
    b.setCheckable(True)
    b.setChecked(checked)
    b.setCursor(QtCore.Qt.PointingHandCursor)
    b.setToolTip(tip)
    b.setAccessibleName(tip)
    b.setFixedSize(34, 34)
    b.setStyleSheet(
        f"QPushButton{{background:{SUBTLE}; color:{INK}; border:1px solid {HAIRLINE};"
        "border-radius:17px; font-size:13px;}"
        f"QPushButton:hover{{background:{PAPER_DEEP};}}"
        f"QPushButton:checked{{background:{NAVY}; color:{CARD}; border:1px solid transparent;}}")
    return b


class _ForwardsZoom:

    def zoom_by(self, delta):
        for name in ("body", "pane"):
            zoom = getattr(getattr(self, name, None), "zoom_by", None)
            if callable(zoom):
                zoom(delta)
                return


class DeckFocusScreen(_ForwardsZoom, QtWidgets.QWidget):

    closed = QtCore.Signal()

    def __init__(self, store, deck_id, mode="cards", parent=None):
        super().__init__(parent)
        self.store = store
        self.deck_id = deck_id
        self.mode = mode
        self.setObjectName("deckFocus")
        self.setStyleSheet(f"QWidget#deckFocus{{background:{PAPER};}}")
        self.setFocusPolicy(QtCore.Qt.StrongFocus)

        lay = QtWidgets.QVBoxLayout(self)
        lay.setContentsMargins(0, 0, 0, 0)
        lay.setSpacing(0)
        lay.addWidget(self._header())
        rule = QtWidgets.QFrame()
        rule.setFixedHeight(1)
        rule.setStyleSheet(f"background:{HAIRLINE}; border:none;")
        lay.addWidget(rule)

        pane = (TestPane(store, deck_id, self._changed) if mode == "test"
                else FlashcardsPane(store, deck_id, self._changed))
        lay.addWidget(pane, 1)
        self.pane = pane

    def _changed(self):
        pass

    def _header(self):
        bar = QtWidgets.QWidget()
        bar.setObjectName("focusHeader")
        bar.setStyleSheet(f"QWidget#focusHeader{{background:{CARD};}}")
        lay = QtWidgets.QHBoxLayout(bar)
        lay.setContentsMargins(24, 14, 24, 12)
        lay.setSpacing(14)

        back = brand.IconButton("shut_left", L("Library"), MUTED, NAVY, size=11)
        back.setToolTip(L("Back to the library — nothing is lost"))
        back.setStyleSheet(
            f"QPushButton{{border:none; color:{MUTED}; font-size:12px;"
            "background:transparent;}"
            f"QPushButton:hover{{color:{NAVY};}}")
        back.clicked.connect(self.closed.emit)
        lay.addWidget(back)

        divider = QtWidgets.QFrame()
        divider.setFixedSize(1, 22)
        divider.setStyleSheet(f"background:{HAIRLINE}; border:none;")
        lay.addWidget(divider)

        deck = self.store.decks.deck(self.deck_id)
        names = QtWidgets.QVBoxLayout()
        names.setSpacing(2)
        title = ElidedLabel(deck.name if deck else "")
        title.setStyleSheet(
            f"color:{NAVY}; font-size:16px; font-weight:600; font-family:{SERIF};"
            "border:none; background:transparent;")
        names.addWidget(title)
        sub = QtWidgets.QLabel(
            L("Test") if self.mode == "test"
            else Lp(len(deck.cards) if deck else 0, "%d card", "%d cards"))
        sub.setStyleSheet(f"color:{MUTED}; font-size:10.5px; border:none;"
                          "background:transparent;")
        names.addWidget(sub)
        lay.addLayout(names, 1)

        leave = QtWidgets.QLabel(L("Esc to leave"))
        leave.setStyleSheet(f"color:{MUTED}; font-size:10px; border:none;"
                            "background:transparent;")
        lay.addWidget(leave)
        return bar

    def keyPressEvent(self, event):
        if event.key() == QtCore.Qt.Key_Escape:
            self.closed.emit()
            return
        super().keyPressEvent(event)


class DeckScreen(_ForwardsZoom, QtWidgets.QWidget):

    focus_requested = QtCore.Signal(str, str)

    changed = QtCore.Signal()

    def __init__(self, store, deck_id, parent=None):
        super().__init__(parent)
        self.store = store
        self.deck_id = deck_id
        self.tab = "flashcards"
        self.setObjectName("deckScreen")
        self.setStyleSheet(f"QWidget#deckScreen{{background:{PAPER};}}")

        root = QtWidgets.QVBoxLayout(self)
        root.setContentsMargins(0, 0, 0, 0)
        root.setSpacing(0)
        self.header = QtWidgets.QWidget()
        root.addWidget(self.header)
        root.addWidget(_rule())
        self.body = QtWidgets.QWidget()
        QtWidgets.QVBoxLayout(self.body).setContentsMargins(0, 0, 0, 0)
        root.addWidget(self.body, 1)
        self.rebuild()

    @property
    def deck(self):
        return self.store.decks.deck(self.deck_id)

    def rebuild(self):
        self._build_header()
        self._build_body()

    def _build_header(self):
        old = self.header
        bar = QtWidgets.QWidget()
        bar.setObjectName("deckHeader")
        bar.setStyleSheet(f"QWidget#deckHeader{{background:{CARD};}}")
        rows = QtWidgets.QVBoxLayout(bar)
        rows.setContentsMargins(24, 12, 24, 12)
        rows.setSpacing(10)
        lay = QtWidgets.QHBoxLayout()
        lay.setSpacing(12)
        rows.addLayout(lay)
        self._tab_holder = QtWidgets.QWidget()
        self._tab_row = QtWidgets.QHBoxLayout(self._tab_holder)
        self._tab_row.setContentsMargins(0, 0, 0, 0)
        self._tab_row.setSpacing(0)
        self._tab_row.addStretch(1)
        rows.addWidget(self._tab_holder)

        deck = self.deck
        names = QtWidgets.QVBoxLayout()
        names.setSpacing(2)
        title = ElidedLabel(deck.name if deck else "")
        title.setStyleSheet(
            f"color:{NAVY}; font-size:19px; font-weight:600; font-family:{SERIF}; border:none;")
        sub = QtWidgets.QLabel(self._subtitle())
        sub.setStyleSheet(f"color:{MUTED}; font-size:11px; border:none;")
        names.addWidget(title)
        names.addWidget(sub)
        lay.addLayout(names, 1)

        deck_cards = deck.cards if deck else []
        self._study_box = QtWidgets.QWidget()
        study = QtWidgets.QHBoxLayout(self._study_box)
        study.setContentsMargins(0, 0, 0, 0)
        study.setSpacing(12)
        for text, key, strong, ready in (
                (L("Practice with cards"), "flashcards", True, bool(deck_cards)),
                (L("Start the test"), "test", False,
                 vocab.available_count(deck_cards) >= vocab.MINIMUM_CARDS)):
            b = QtWidgets.QPushButton(text)
            b.setEnabled(ready)
            b.setCursor(QtCore.Qt.PointingHandCursor)
            if strong:
                b.setStyleSheet(
                    f"QPushButton{{background:{NAVY}; color:{CARD}; border:none;"
                    "border-radius:4px; padding:9px 18px; font-size:12.5px;"
                    "font-weight:600;}"
                    f"QPushButton:disabled{{background:{SUBTLE}; color:{MUTED};}}")
            else:
                b.setStyleSheet(
                    f"QPushButton{{background:{CARD}; color:{NAVY};"
                    f"border:1px solid {BORDER}; border-radius:4px;"
                    "padding:9px 18px; font-size:12.5px; font-weight:600;}"
                    f"QPushButton:hover{{background:{SUBTLE};}}"
                    f"QPushButton:disabled{{color:{MUTED}; border:1px solid {HAIRLINE};}}")
            b.clicked.connect(lambda _=False, k=key: self.focus_requested.emit(
                self.deck_id, "test" if k == "test" else "cards"))
            b.setMinimumWidth(b.sizeHint().width())
            study.addWidget(b)
        lay.addWidget(self._study_box)

        self._tabs_box = QtWidgets.QWidget()
        tabs = QtWidgets.QHBoxLayout(self._tabs_box)
        tabs.setContentsMargins(14, 0, 0, 0)
        tabs.setSpacing(12)
        self._tab_buttons = {}
        for key, text in (("daily", L("Daily/Statistics")),
                          ("flashcards", L("Flashcards")), ("test", L("Test")),
                          ("cards", L("Cards"))):
            b = QtWidgets.QPushButton(text)
            b.setCheckable(True)
            b.setChecked(key == self.tab)
            b.setCursor(QtCore.Qt.PointingHandCursor)
            b.setStyleSheet(
                f"QPushButton{{background:{SUBTLE}; color:{INK}; border:1px solid {HAIRLINE};"
                "border-radius:4px; padding:8px 16px; font-size:12px;}"
                f"QPushButton:hover{{background:{PAPER_DEEP};}}"
                f"QPushButton:checked{{background:{NAVY}; color:{CARD}; font-weight:600;"
                "border:1px solid transparent;}")
            _room_for_bold(b)
            b.clicked.connect(lambda _=False, k=key: self._select(k))
            b.setMinimumWidth(b.sizeHint().width())
            tabs.addWidget(b)
            self._tab_buttons[key] = b
        self._header_row = lay
        lay.addWidget(self._tabs_box)

        self.layout().replaceWidget(old, bar)
        old.deleteLater()
        self.header = bar
        self._fit_tabs()

    NAME_ROOM = 140

    def _fit_tabs(self):
        box = getattr(self, "_tabs_box", None)
        if box is None or self.width() <= 0:
            return
        need = (48 + self.NAME_ROOM + 12 + self._study_box.sizeHint().width()
                + 12 + box.sizeHint().width())
        one_row = self.width() >= need
        if one_row and self._header_row.indexOf(box) < 0:
            self._header_row.addWidget(box)
        elif not one_row and self._tab_row.indexOf(box) < 0:
            self._tab_row.addWidget(box)
        self._tab_holder.setVisible(not one_row)

    def resizeEvent(self, event):
        super().resizeEvent(event)
        self._fit_tabs()

    def _subtitle(self):
        deck = self.deck
        if deck is None:
            return ""
        n = len(deck.cards)
        parts = [Lp(n, "%d card", "%d cards")]
        if deck.starred_count:
            parts.append(Lf("%d starred", deck.starred_count))
        if deck.undefined_count:
            parts.append(Lf("%d without a definition", deck.undefined_count))
        return " · ".join(parts)

    def _select(self, key):
        self.tab = key
        self.rebuild()

    def _build_body(self):
        old = self.body
        deck = self.deck
        if deck is None:
            page = QtWidgets.QWidget()
        elif self.tab == "cards":
            page = CardsPane(self.store, self.deck_id, self._after_change)
        elif not deck.cards:
            page = EmptyDeck(self.store, self.deck_id, self._after_change, self.rebuild)
        elif self.tab == "daily":
            page = DailyPane(self.store, self.deck_id, self._after_change)
        elif self.tab == "flashcards":
            page = FlashcardsPane(self.store, self.deck_id, self._after_change)
            wanted = getattr(self, "scope_wanted", None)
            if wanted:
                self.scope_wanted = None
                page._set_scope(wanted)
        else:
            page = TestPane(self.store, self.deck_id, self._after_change)
        self.layout().replaceWidget(old, page)
        old.deleteLater()
        self.body = page

    def _after_change(self):
        self._build_header()
        self.changed.emit()

    def reload(self):
        self.rebuild()


class EmptyDeck(QtWidgets.QWidget):
    def __init__(self, store, deck_id, on_change, on_filled, parent=None):
        super().__init__(parent)
        self.store = store
        self.deck_id = deck_id
        self.on_change = on_change
        self.on_filled = on_filled
        self.setObjectName("emptyDeck")
        self.setStyleSheet(f"QWidget#emptyDeck{{background:{PAPER};}}")
        lay = QtWidgets.QVBoxLayout(self)
        lay.setContentsMargins(40, 40, 40, 40)
        lay.setSpacing(14)
        lay.addStretch(1)

        title = QtWidgets.QLabel(L("This deck is empty"))
        title.setAlignment(QtCore.Qt.AlignCenter)
        title.setStyleSheet(
            f"color:{NAVY}; font-size:19px; font-weight:600; font-family:{SERIF}; border:none;")
        blurb = QtWidgets.QLabel(
            L("Take the words out of a question set you have already imported, or type "
            "your own in. The Words-in-Context questions carry their own definitions, "
            "so most words arrive with one already written."))
        blurb.setWordWrap(True)
        leading(blurb)
        blurb.setAlignment(QtCore.Qt.AlignCenter)
        blurb.setMaximumWidth(460)
        blurb.setSizePolicy(QtWidgets.QSizePolicy.Expanding, QtWidgets.QSizePolicy.Preferred)
        blurb.setStyleSheet(f"color:{MUTED}; font-size:12px; border:none;")
        lay.addWidget(title)
        middle = QtWidgets.QHBoxLayout()
        middle.addStretch(1)
        middle.addWidget(blurb, 100)
        middle.addStretch(1)
        lay.addLayout(middle)

        row = QtWidgets.QHBoxLayout()
        row.addStretch(1)
        take = _primary(L("Take words from a question set…"))
        take.setEnabled(bool(store.banks))
        take.clicked.connect(self._mine)
        row.addWidget(take)
        row.addStretch(1)
        lay.addLayout(row)

        note = QtWidgets.QLabel(
            L("Import a question bank PDF first, or write your own cards on the Cards tab.")
            if not store.banks else L("Or write your own on the Cards tab."))
        note.setAlignment(QtCore.Qt.AlignCenter)
        note.setStyleSheet(f"color:{MUTED}; font-size:11px; border:none;")
        lay.addWidget(note)
        lay.addStretch(1)

    def _mine(self):
        if MiningDialog(self.store, self.deck_id, self).exec():
            self.on_change()
            self.on_filled()


class Turner(QtWidgets.QWidget):

    def __init__(self, front, back, parent=None):
        super().__init__(parent)
        self.front = front
        self.back = back
        self._angle = 0.0
        self.setAttribute(QtCore.Qt.WA_TransparentForMouseEvents, True)

    def _get_angle(self):
        return self._angle

    def _set_angle(self, value):
        self._angle = float(value)
        self.update()

    angle = QtCore.Property(float, _get_angle, _set_angle)

    def paintEvent(self, event):
        import math
        painter = QtGui.QPainter(self)
        painter.setRenderHint(QtGui.QPainter.SmoothPixmapTransform, True)
        painter.fillRect(self.rect(), QtGui.QColor(PAPER))
        radians = math.radians(self._angle)
        face = self.front if self._angle < 90 else self.back
        squash = abs(math.cos(radians))
        ratio = self.devicePixelRatioF()
        width = face.width() / ratio
        height = face.height() / ratio
        painter.translate(width / 2.0, height / 2.0)
        painter.scale(max(squash, 0.001), 1.0)
        painter.translate(-width / 2.0, -height / 2.0)
        painter.drawPixmap(QtCore.QRectF(0, 0, width, height), face,
                           QtCore.QRectF(face.rect()))
        painter.end()


class _CardFoot(QtWidgets.QWidget):

    GAP = 12

    def __init__(self, parent=None):
        super().__init__(parent)
        self.setStyleSheet("background:transparent;")
        self.record = QtWidgets.QLabel("", self)
        self.record.setStyleSheet(f"color:{MUTED}; font-size:10px; border:none;")
        self.hint = QtWidgets.QLabel(L("Click, or press space, to turn the card over"), self)
        self.hint.setStyleSheet(f"color:{MUTED}; font-size:10px; border:none;")
        self.setSizePolicy(QtWidgets.QSizePolicy.Preferred, QtWidgets.QSizePolicy.Fixed)
        self._stacked = False

    def set_record(self, text):
        self.record.setText(text)
        self._arrange()

    def _widths(self):
        r = self.record.sizeHint().width() if self.record.text() else 0
        return r, self.hint.sizeHint().width()

    def _line(self):
        return max(self.record.sizeHint().height(), self.hint.sizeHint().height())

    def sizeHint(self):
        r, h = self._widths()
        stacked = self.width() > 0 and r + self.GAP + h > self.width()
        return QtCore.QSize(max(r, h), self._line() * (2 if stacked else 1) + (3 if stacked else 0))

    def minimumSizeHint(self):
        return QtCore.QSize(0, self.sizeHint().height())

    def resizeEvent(self, event):
        super().resizeEvent(event)
        self._arrange()

    def _arrange(self):
        w, line = self.width(), self._line()
        r, h = self._widths()
        stacked = r + self.GAP + h > w
        if not stacked and 2 * r + 2 * self.GAP + h <= w:
            self.hint.setGeometry((w - h) // 2, 0, h, line)
            self.record.setGeometry(0, 0, r, line)
        elif not stacked:
            self.record.setGeometry(0, 0, r, line)
            self.hint.setGeometry(w - h, 0, h, line)
        else:
            self.hint.setGeometry(max(0, (w - h) // 2), 0, min(h, w), line)
            self.record.setGeometry(max(0, (w - r) // 2), line + 3, min(r, w), line)
        if stacked != self._stacked:
            self._stacked = stacked
            self.updateGeometry()


class CardFace(QtWidgets.QFrame):

    flipped = QtCore.Signal()

    def __init__(self, parent=None, compact=False):
        super().__init__(parent)
        self.scale = 1.0
        self.compact = compact
        self._turner = None
        self._turn = None
        self.setObjectName("cardFace")
        self.setStyleSheet(
            f"QFrame#cardFace{{background:{CARD}; border:1px solid {HAIRLINE};"
            "border-radius:6px;}")
        self.setCursor(QtCore.Qt.PointingHandCursor)
        self.card = None
        self.showing_back = False
        self.hinting = False

        lay = QtWidgets.QVBoxLayout(self)
        lay.setContentsMargins(18, 16, 18, 16)
        lay.setSpacing(0)

        top = QtWidgets.QHBoxLayout()
        top.addStretch(1)
        self.hint_button = QtWidgets.QPushButton(L("Get a hint"))
        self.hint_button.setCheckable(True)
        self.hint_button.setCursor(QtCore.Qt.PointingHandCursor)
        self.hint_button.setStyleSheet(
            f"QPushButton{{background:transparent; border:none; color:{MUTED};"
            "font-size:12px; padding:4px 8px;}"
            f"QPushButton:hover{{color:{NAVY};}}"
            f"QPushButton:checked{{color:{BRASS_TEXT}; font-weight:600;}}")
        _room_for_bold(self.hint_button)
        self.hint_button.clicked.connect(self._toggle_hint)
        self.star_button = QtWidgets.QPushButton()
        self.star_button.setAccessibleName(L("Star"))
        self.star_button.setIcon(brand.icon("star", 15, MUTED))
        self.star_button.setIconSize(QtCore.QSize(15, 15))
        self.star_button.setCursor(QtCore.Qt.PointingHandCursor)
        self.star_button.setStyleSheet(
            "QPushButton{background:transparent; border:none; padding:2px 6px;}")
        top.addWidget(self.hint_button)
        top.addWidget(self.star_button)
        lay.addLayout(top)

        lay.addStretch(1)
        self.main = QtWidgets.QLabel("")
        self.main.setAlignment(QtCore.Qt.AlignCenter)
        self.main.setWordWrap(True)
        leading(self.main)
        self.main.setTextFormat(QtCore.Qt.RichText)
        lay.addWidget(self.main)
        self.extra = QtWidgets.QLabel("")
        self.extra.setAlignment(QtCore.Qt.AlignCenter)
        self.extra.setWordWrap(True)
        leading(self.extra)
        self.extra.setTextFormat(QtCore.Qt.RichText)
        self.extra.setContentsMargins(40, 12, 40, 0)
        lay.addWidget(self.extra)
        lay.addStretch(1)

        self.grades = QtWidgets.QWidget()
        grade_row = QtWidgets.QHBoxLayout(self.grades)
        grade_row.setContentsMargins(0, 0, 0, 8)
        grade_row.setSpacing(10)
        grade_row.addStretch(1)
        self.missed_button = self._grade_button("cross", L("Missed it") + "  1", WRONG)
        self.got_button = self._grade_button("tick", L("Got it") + "  2", CORRECT)
        grade_row.addWidget(self.missed_button)
        grade_row.addWidget(self.got_button)
        grade_row.addStretch(1)
        lay.addWidget(self.grades)

        self.foot = _CardFoot()
        self.record = self.foot.record
        lay.addWidget(self.foot)

    def _grade_button(self, mark, text, tint):
        b = brand.IconButton(mark, text, tint, tint, size=11)
        b.setStyleSheet(
            f"QPushButton{{background:transparent; color:{tint};"
            f"border:1px solid {tint}; border-radius:4px; padding:8px 16px;"
            "font-size:12px; font-weight:600;}"
            f"QPushButton:hover{{background:{BRASS_SOFT};}}")
        return b

    def show_card(self, card, showing_back=False, hinting=False, scale=1.0):
        self.card = card
        self.showing_back = showing_back
        self.hinting = hinting
        self.scale = scale
        self.grades.setVisible(bool(card) and showing_back)
        self.foot.set_record(card.record_line if card else "")
        self.hint_button.setChecked(hinting)
        self.hint_button.setVisible(bool(card) and not showing_back and card.has_definition)
        starred = bool(card and card.starred)
        self.star_button.setIcon(brand.icon("star_on" if starred else "star", 15,
                                            BRASS if starred else MUTED))
        self.star_button.setAccessibleName(L("Starred") if starred else L("Star"))
        if card is None:
            self.main.setText("")
            self.extra.setText("")
            return
        if showing_back:
            if card.has_definition:
                self.main.setText(vocab.to_html(card.definition))
            else:
                self.main.setText(L("No definition yet — open Cards to write one."))
            self.extra.setText(vocab.to_html(card.example))
            self.extra.setVisible(bool(card.example))
        else:
            self.main.setText(vocab.to_html(card.term))
            self.extra.setText(vocab.hint_for(card) if hinting else "")
            self.extra.setVisible(hinting)
        self._fit_text()

    def _style_text(self, factor):
        card, scale = self.card, self.scale * factor
        term_size = max(8, round((62 if self.compact else 52) * scale))
        body_size = max(8, round((30 if self.compact else 26) * scale))
        example_size = max(8, round((17 if self.compact else 15) * scale))
        if self.showing_back:
            self.main.setStyleSheet(
                f"color:{INK if card.has_definition else MUTED};"
                f"font-size:{body_size}px; border:none;")
            self.extra.setStyleSheet(
                f"color:{MUTED}; font-size:{example_size}px; font-style:italic; border:none;")
        else:
            self.main.setStyleSheet(
                f"color:{NAVY}; font-size:{term_size}px; font-family:{SERIF}; border:none;")
            self.extra.setStyleSheet(
                f"color:{MUTED}; font-size:{body_size}px; border:none;")

    def _fit_text(self):
        if self.card is None:
            return
        rect = self.contentsRect()
        margins = self.layout().contentsMargins() if self.layout() else QtCore.QMargins()
        width = rect.width() - margins.left() - margins.right()
        others = (max(self.hint_button.sizeHint().height(), self.star_button.sizeHint().height())
                  + (self.grades.sizeHint().height() if self.showing_back else 0)
                  + self.foot.sizeHint().height())
        room = rect.height() - margins.top() - margins.bottom() - others
        factor = 1.0
        while True:
            self._style_text(factor)
            if width <= 0 or room <= 0 or factor <= 0.3:
                break
            need = self.main.heightForWidth(width)
            if self.extra.isVisibleTo(self) and self.extra.text():
                need += self.extra.heightForWidth(width)
            if need <= room:
                break
            factor = round(factor - 0.1, 2)

    def turn_to(self, card, showing_back, hinting=False, scale=1.0):
        if not ANIMATIONS_ON or self.width() < 2 or self.height() < 2:
            self.show_card(card, showing_back, hinting, scale)
            return
        front = self.grab()
        self.show_card(card, showing_back, hinting, scale)
        layout = self.layout()
        if layout is not None:
            layout.activate()
        back = self.grab()

        if self._turn is not None:
            self._turn.stop()
        if self._turner is not None:
            self._turner.deleteLater()
        turner = Turner(front, back, self)
        turner.setGeometry(self.rect())
        turner.show()
        turner.raise_()
        self._turner = turner

        anim = QtCore.QPropertyAnimation(turner, b"angle", turner)
        anim.setDuration(260)
        anim.setStartValue(0.0)
        anim.setEndValue(180.0)
        anim.setEasingCurve(QtCore.QEasingCurve.OutCubic)
        anim.finished.connect(self._turn_finished)
        self._turn = anim
        anim.start(QtCore.QAbstractAnimation.DeleteWhenStopped)

    def _turn_finished(self):
        if self._turner is not None:
            self._turner.hide()
            self._turner.deleteLater()
            self._turner = None
        self._turn = None

    def resizeEvent(self, event):
        if self._turner is not None:
            if self._turn is not None:
                self._turn.stop()
            self._turn_finished()
        super().resizeEvent(event)
        self._fit_text()

    def _toggle_hint(self):
        self.hinting = self.hint_button.isChecked()
        self.show_card(self.card, self.showing_back, self.hinting, self.scale)

    def mousePressEvent(self, event):
        self.flipped.emit()


class DayStrip(QtWidgets.QWidget):

    def __init__(self, days, parent=None):
        super().__init__(parent)
        self.days = days
        self.setFixedHeight(7 * 11 + 6)
        self.setAttribute(QtCore.Qt.WA_TransparentForMouseEvents)

    def paintEvent(self, event):
        painter = QtGui.QPainter(self)
        painter.setRenderHint(QtGui.QPainter.Antialiasing)
        painter.setPen(QtCore.Qt.NoPen)
        done = QtGui.QColor(BRASS)
        missed = QtGui.QColor(HAIRLINE)
        for i, (_day, was_done) in enumerate(self.days):
            column, row = divmod(i, 7)
            painter.setBrush(done if was_done else missed)
            painter.drawRoundedRect(
                QtCore.QRectF(column * 11, row * 11, 8, 8), 2, 2)
        painter.end()


class DailyPane(QtWidgets.QWidget):

    MEASURE = 760
    SECTION_GAP = 22

    def __init__(self, store, deck_id, on_change, parent=None):
        super().__init__(parent)
        self.store = store
        self.deck_id = deck_id
        self.on_change = on_change
        self.setObjectName("dailyPane")
        self.setStyleSheet(f"QWidget#dailyPane{{background:{PAPER};}}")
        QtWidgets.QVBoxLayout(self).setContentsMargins(0, 0, 0, 0)
        self._build()

    def _build(self):
        old = self.layout().takeAt(0)
        if old is not None and old.widget() is not None:
            old.widget().deleteLater()

        scroll = QtWidgets.QScrollArea()
        scroll.setWidgetResizable(True)
        scroll.setFrameShape(QtWidgets.QFrame.NoFrame)
        scroll.setHorizontalScrollBarPolicy(QtCore.Qt.ScrollBarAlwaysOff)
        scroll.setStyleSheet(f"QScrollArea{{background:{PAPER}; border:none;}}"
                             + SCROLLBAR)
        page = QtWidgets.QWidget()
        page.setObjectName("dailyPage")
        page.setStyleSheet(f"QWidget#dailyPage{{background:{PAPER};}}")
        outer = QtWidgets.QHBoxLayout(page)
        outer.setContentsMargins(26, 22, 26, 26)
        outer.addStretch(1)
        column = QtWidgets.QWidget()
        column.setObjectName("dailyColumn")
        column.setStyleSheet("QWidget#dailyColumn{background:transparent;}")
        column.setMaximumWidth(self.MEASURE)
        outer.addWidget(column, 1000)
        outer.addStretch(1)
        lay = QtWidgets.QVBoxLayout(column)
        lay.setContentsMargins(0, 0, 0, 0)
        lay.setSpacing(self.SECTION_GAP)

        deck = self.store.decks.deck(self.deck_id)
        if deck is None:
            scroll.setWidget(page)
            self.layout().addWidget(scroll)
            return

        plan = self.store.daily_plan()
        if not plan["enabled"]:
            lay.addWidget(self._offer())
        else:
            lay.addWidget(self._today(deck, plan))
            lay.addWidget(self._run(plan))
            lay.addWidget(self._calendar(plan))

        lay.addWidget(self._deck_statistics(deck))
        lay.addWidget(self._plan_controls(plan))
        lay.addStretch(1)

        scroll.setWidget(page)
        self.layout().addWidget(scroll)

    def _refresh(self):
        self._build()
        if self.on_change:
            self.on_change()

    def _heading(self, text):
        label = QtWidgets.QLabel(text)
        label.setStyleSheet(
            f"color:{NAVY}; font-size:15px; font-weight:600; font-family:{SERIF};"
            "border:none; background:transparent;")
        return label

    def _quiet(self, text, tint=None, size=11):
        label = QtWidgets.QLabel(text)
        label.setWordWrap(True)
        leading(label)
        label.setStyleSheet(f"color:{tint or MUTED}; font-size:{size}px;"
                            "border:none; background:transparent;")
        return label

    def _button(self, text, slot, strong=False):
        button = QtWidgets.QPushButton(text)
        button.setCursor(QtCore.Qt.PointingHandCursor)
        if strong:
            button.setStyleSheet(
                f"QPushButton{{background:{NAVY}; color:{CARD}; border:none;"
                "border-radius:3px; padding:9px 20px; font-size:12.5px;"
                "font-weight:600;}")
        else:
            button.setStyleSheet(
                f"QPushButton{{background:transparent; color:{NAVY};"
                f"border:1px solid {BORDER}; border-radius:3px;"
                "padding:7px 15px; font-size:11.5px;}"
                f"QPushButton:hover{{background:{SUBTLE};}}")
        button.clicked.connect(slot)
        return button

    def _offer(self):
        box = QtWidgets.QWidget()
        box.setStyleSheet("background:transparent;")
        lay = QtWidgets.QVBoxLayout(box)
        lay.setContentsMargins(0, 0, 0, 0)
        lay.setSpacing(8)
        lay.addWidget(self._heading(L("A few words a day")))
        lay.addWidget(self._quiet(
            L("Ten new words a day, with everything that has come back round "
              "for review, is about a quarter of an hour and adds up to more "
              "than any amount of cramming the week before. Words you get "
              "wrong come back tomorrow; words you keep getting right come "
              "back at widening gaps."), size=12))
        lay.addSpacing(6)
        lay.addWidget(self._button(L("Start a daily set"),
                                   self._turn_on, strong=True),
                      0, QtCore.Qt.AlignLeft)
        return box

    def _today(self, deck, plan):
        box = QtWidgets.QWidget()
        box.setStyleSheet("background:transparent;")
        lay = QtWidgets.QVBoxLayout(box)
        lay.setContentsMargins(0, 0, 0, 0)
        lay.setSpacing(8)
        lay.addWidget(self._heading(L("Today")))

        today = self.store.daily_set(self.deck_id)
        if not today.total:
            if today.remaining_in_deck:
                lay.addWidget(self._quiet(L("Nothing due, and nothing new dealt yet.")))
                lay.addWidget(self._button(L("Start today's words"),
                                           self._deal, strong=True),
                              0, QtCore.Qt.AlignLeft)
            else:
                lay.addWidget(self._quiet(
                    L("Nothing due today. Every word in this deck is resting.")))
            return box

        answered = today.answered_count()
        headline = (L("Today's words are done.") if answered == today.total
                    else Lf("%1$d of %2$d words to go today.",
                            today.total - answered, today.total))
        lay.addWidget(self._quiet(headline, tint=NAVY, size=13))

        breakdown = []
        if today.due:
            breakdown.append(Lp(len(today.due), "%d to review", "%d to review"))
        if today.fresh:
            breakdown.append(Lp(len(today.fresh), "%d new", "%d new"))
        if breakdown:
            lay.addWidget(self._quiet(" · ".join(breakdown), size=12))

        if today.held_back:
            lay.addWidget(self._quiet(
                Lf("No new words today: %d are already waiting to be reviewed. "
                   "They come back as soon as you have cleared some — this is "
                   "deliberate, and it is the thing that keeps a daily set from "
                   "turning into a backlog nobody finishes.", len(today.due)),
                tint=BRASS, size=10.5))

        row = QtWidgets.QHBoxLayout()
        row.setSpacing(10)
        if today.is_complete():
            row.addWidget(self._button(L("Go through them again"), self._practise))
        else:
            row.addWidget(self._button(L("Start today's words"),
                                       self._practise, strong=True))
        row.addWidget(self._button(L("Put them back"), self._put_back))
        row.addStretch(1)
        lay.addLayout(row)
        return box

    def _run(self, plan):
        box = QtWidgets.QWidget()
        box.setStyleSheet("background:transparent;")
        lay = QtWidgets.QVBoxLayout(box)
        lay.setContentsMargins(0, 0, 0, 0)
        lay.setSpacing(8)
        on = bool(self.store.settings.get("showVocabularyStreak", True))
        lay.addWidget(self._heading(L("Your run") if on else L("Days you have practiced")))

        current, best, at_risk, done_today = vocab.daily_streak(plan["completedDays"])
        row = QtWidgets.QHBoxLayout()
        row.setSpacing(26)
        figures = []
        if on:
            figures += [(current, Lp(current, "day in a row", "days in a row")),
                        (best, L("best run"))]
        figures.append((len(plan["completedDays"]), L("days done in all")))
        for value, label in figures:
            row.addWidget(self._figure(str(value), label))
        row.addStretch(1)
        lay.addLayout(row)
        if on:
            if at_risk and self.store.daily_set(self.deck_id).total > 0:
                lay.addWidget(self._quiet(
                    Lp(current + 1, "Finish today's words to make it %d day.",
                       "Finish today's words to make it %d days.") if current > 0
                    else L("Finish today's words to start a run."),
                    tint=BRASS, size=10.5))
            elif done_today:
                lay.addWidget(self._quiet(
                    L("Today is done. Come back tomorrow — the gap is the part "
                      "that does the work."), tint=CORRECT, size=10.5))
        if plan["completedDays"]:
            lay.addWidget(self._button(L("Clear your run"), self._clear_run),
                          0, QtCore.Qt.AlignLeft)
        return box

    def _figure(self, value, label):
        box = QtWidgets.QWidget()
        box.setStyleSheet("background:transparent;")
        lay = QtWidgets.QVBoxLayout(box)
        lay.setContentsMargins(0, 0, 0, 0)
        lay.setSpacing(1)
        big = QtWidgets.QLabel(value)
        big.setStyleSheet(
            f"color:{NAVY}; font-size:23px; font-weight:600; font-family:{NUMERALS};"
            "border:none; background:transparent;")
        lay.addWidget(big)
        small = QtWidgets.QLabel(label.upper())
        small.setStyleSheet(
            f"color:{MUTED}; font-size:9px; font-weight:600; letter-spacing:1.1px;"
            "border:none; background:transparent;")
        lay.addWidget(small)
        return box

    def _calendar(self, plan):
        box = QtWidgets.QWidget()
        box.setStyleSheet("background:transparent;")
        lay = QtWidgets.QVBoxLayout(box)
        lay.setContentsMargins(0, 0, 0, 0)
        lay.setSpacing(8)
        lay.addWidget(self._heading(L("Turning up")))
        lay.addWidget(DayStrip(vocab.recent_days(plan["completedDays"])))
        return box

    def _deck_statistics(self, deck):
        box = QtWidgets.QWidget()
        box.setStyleSheet("background:transparent;")
        lay = QtWidgets.QVBoxLayout(box)
        lay.setContentsMargins(0, 0, 0, 0)
        lay.setSpacing(10)
        lay.addWidget(self._heading(L("This deck")))

        stats = vocab.deck_statistics(deck.cards)
        if not stats.total:
            lay.addWidget(self._quiet(L("Nothing to show yet")))
            return box

        grid = QtWidgets.QGridLayout()
        grid.setHorizontalSpacing(40)
        grid.setVerticalSpacing(22)
        cells = [
            ("%d%%" % round(stats.known_fraction * 100), L("known")),
            (str(stats.due_today), L("due now")),
            (str(stats.due_this_week), L("due this week")),
            (str(stats.starred), L("starred")),
            (str(stats.without_definition), L("no definition")),
        ]
        if stats.accuracy is not None:
            cells.insert(1, ("%d%%" % round(stats.accuracy * 100),
                             L("answered right")))
        for i, (value, label) in enumerate(cells):
            grid.addWidget(self._figure(value, label), i // 3, i % 3)
        for c in range(3):
            grid.setColumnStretch(c, 1)
        lay.addLayout(grid)

        lay.addSpacing(6)
        lay.addWidget(self._button(L("Start this deck over"), self._start_over),
                      0, QtCore.Qt.AlignLeft)
        return box

    def _plan_controls(self, plan):
        box = QtWidgets.QWidget()
        box.setObjectName("dailyPlanControls")
        box.setStyleSheet("QWidget#dailyPlanControls{background:transparent;}")
        lay = QtWidgets.QVBoxLayout(box)
        lay.setContentsMargins(0, 0, 0, 0)
        lay.setSpacing(8)
        lay.addWidget(self._heading(L("How many new words a day")))

        row = QtWidgets.QHBoxLayout()
        row.setSpacing(8)
        for count in vocab.DAILY_PRESETS:
            chosen = count == plan["wordsPerDay"]
            chip = QtWidgets.QPushButton(str(count))
            chip.setCursor(QtCore.Qt.PointingHandCursor)
            chip.setStyleSheet(
                f"QPushButton{{border:1px solid {NAVY if chosen else HAIRLINE};"
                f"border-radius:3px; background:{NAVY if chosen else SUBTLE};"
                f"color:{CARD if chosen else INK}; padding:6px 16px;"
                "font-size:12px;"
                + ("font-weight:600;" if chosen else "") + "}")
            chip.clicked.connect(lambda _=False, n=count: self._set_per_day(n))
            row.addWidget(chip)

        typed = QtWidgets.QSpinBox()
        typed.setAccessibleName(L("How many new words a day"))
        low, high = vocab.DAILY_RANGE
        typed.setRange(low, high)
        typed.setValue(plan["wordsPerDay"])
        typed.setMinimumHeight(30)
        typed.valueChanged.connect(self._set_per_day)
        row.addWidget(framed_spin(typed))
        row.addStretch(1)
        lay.addLayout(row)

        if plan["enabled"]:
            lay.addSpacing(6)
            lay.addWidget(self._button(L("Stop daily practice"), self._turn_off),
                          0, QtCore.Qt.AlignLeft)
        return box

    def _turn_on(self):
        self.store.set_daily_enabled(True)
        self.store.deal_daily(self.deck_id)
        self._refresh()

    def _turn_off(self):
        self.store.set_daily_enabled(False)
        self._refresh()

    def _set_per_day(self, count):
        self.store.set_words_per_day(int(count))
        self._refresh()

    def _deal(self):
        self.store.deal_daily(self.deck_id)
        self._refresh()

    def _practise(self):
        self.store.deal_daily(self.deck_id)
        window = self.window()
        screen = getattr(window, "deck_screen", None) or self.parent()
        while screen is not None and not hasattr(screen, "_select"):
            screen = screen.parent()
        if screen is not None:
            screen.scope_wanted = "today"
            screen._select("flashcards")

    def _put_back(self):
        if not brand.ask(
                self, L("Put today's new words back?"),
                L("Today's set is dealt again from the top of the deck. "
                  "Nothing you have already answered is lost — those words "
                  "keep their record."),
                accept=L("Deal them again")):
            return
        self.store.clear_todays_deal(self.deck_id)
        self._refresh()

    def _clear_run(self):
        if not brand.ask(
                self, L("Clear your run?"),
                L("The streak and the list of days you finished are forgotten. "
                  "The words themselves keep everything they know."),
                accept=L("Clear it"), destructive=True):
            return
        self.store.clear_daily_history()
        self._refresh()

    def _start_over(self):
        deck = self.store.decks.deck(self.deck_id)
        name = deck.name if deck else ""
        if not brand.ask(
                self, L("Start this deck over?"),
                Lf("Every word in \"%@\" goes back to never having been seen: "
                   "the times right, the times skipped, the review dates and "
                   "your run. The words, their meanings and your stars are "
                   "kept.", name),
                accept=L("Start over"), destructive=True):
            return
        self.store.clear_all_vocabulary_progress(self.deck_id)
        self._refresh()


class FocusOverlay(QtWidgets.QWidget):

    def __init__(self, pane):
        super().__init__(pane)
        self.pane = pane
        self.setObjectName("cardFocus")
        self.setAttribute(QtCore.Qt.WA_StyledBackground, True)
        self.setStyleSheet(f"QWidget#cardFocus{{background:{PAPER};}}")
        self.setAutoFillBackground(True)
        self.setFocusPolicy(QtCore.Qt.StrongFocus)

        lay = QtWidgets.QVBoxLayout(self)
        lay.setContentsMargins(0, 0, 0, 0)
        lay.setSpacing(0)

        bar = QtWidgets.QHBoxLayout()
        bar.setContentsMargins(26, 14, 26, 14)
        deck = pane.store.decks.deck(pane.deck_id)
        name = ElidedLabel(deck.name if deck else "")
        name.setStyleSheet(
            f"color:{NAVY}; font-size:15px; font-weight:600; font-family:{SERIF};"
            "border:none; background:transparent;")
        bar.addWidget(name, 1)
        shut = brand.IconButton("shrink_window", L("Close"), MUTED, NAVY, size=11)
        shut.setToolTip(L("Esc to leave"))
        shut.setStyleSheet(
            f"QPushButton{{border:none; background:transparent; color:{MUTED};"
            "font-size:12px;}"
            f"QPushButton:hover{{color:{NAVY};}}")
        shut.clicked.connect(pane.close_focus)
        bar.addWidget(shut)
        lay.addLayout(bar)

        self.face = CardFace(compact=True)
        self.face.flipped.connect(pane.flip)
        self.face.star_button.clicked.connect(pane._star)
        self.face.missed_button.clicked.connect(lambda: pane.grade(False))
        self.face.got_button.clicked.connect(lambda: pane.grade(True))
        holder = QtWidgets.QHBoxLayout()
        holder.setContentsMargins(34, 0, 34, 0)
        holder.addWidget(self.face)
        lay.addLayout(holder, 1)

        feet = QtWidgets.QHBoxLayout()
        feet.setContentsMargins(0, 18, 0, 18)
        feet.setSpacing(18)
        feet.addStretch(1)
        self.back_button = QtWidgets.QPushButton("←")
        self.next_button = QtWidgets.QPushButton("→")
        self.back_button.setAccessibleName(L("Back"))
        self.next_button.setAccessibleName(L("Next"))
        for b in (self.back_button, self.next_button):
            b.setCursor(QtCore.Qt.PointingHandCursor)
            b.setFlat(True)
            b.setFixedWidth(34)
            b.setStyleSheet(
                f"QPushButton{{border:none; background:transparent; color:{INK};"
                "font-size:17px;}"
                f"QPushButton:hover{{color:{NAVY};}}"
                f"QPushButton:disabled{{color:{MUTED};}}")
        self.back_button.clicked.connect(pane.previous)
        self.next_button.clicked.connect(pane.next)
        self.counter = QtWidgets.QLabel("")
        self.counter.setAlignment(QtCore.Qt.AlignCenter)
        self.counter.setMinimumWidth(84)
        self.counter.setStyleSheet(f"color:{INK}; font-size:13px; border:none;"
                                   "background:transparent;")
        feet.addWidget(self.back_button)
        feet.addWidget(self.counter)
        feet.addWidget(self.next_button)
        feet.addStretch(1)
        lay.addLayout(feet)

    def refresh(self):
        total = len(self.pane.order)
        self.counter.setText(f"{min(self.pane.position + 1, total)} / {total}")
        self.back_button.setEnabled(self.pane.position > 0)
        self.next_button.setEnabled(self.pane.position < total - 1)

    def keyPressEvent(self, event):
        if event.key() == QtCore.Qt.Key_Escape:
            self.pane.close_focus()
            return
        self.pane.keyPressEvent(event)
class FlashcardsPane(QtWidgets.QWidget):

    def __init__(self, store, deck_id, on_change, parent=None):
        super().__init__(parent)
        self.store = store
        self.deck_id = deck_id
        self.on_change = on_change
        self._focus = None
        self.scope = "all"
        self.shuffled = False
        self.position = 0
        self.showing_back = False
        self.turned_this_card = False
        self.order = []
        self.setObjectName("flashPane")
        self.setStyleSheet(f"QWidget#flashPane{{background:{PAPER};}}")
        self.setFocusPolicy(QtCore.Qt.StrongFocus)

        lay = QtWidgets.QVBoxLayout(self)
        lay.setContentsMargins(26, 16, 26, 20)
        lay.setSpacing(12)

        from .home import FlowLayout
        scopes = QtWidgets.QWidget()
        scopes.setObjectName("scopeChips")
        scopes.setStyleSheet("QWidget#scopeChips{background:transparent;}")
        self.scope_row = FlowLayout(scopes, spacing=8)
        lay.addWidget(scopes)

        self.face = CardFace()
        self.face.flipped.connect(self.flip)
        self.face.star_button.clicked.connect(self._star)
        self.face.missed_button.clicked.connect(lambda: self.grade(False))
        self.face.got_button.clicked.connect(lambda: self.grade(True))
        lay.addWidget(self.face, 1)

        saved = dict(getattr(self.store, "deck_sessions", {}).get(self.deck_id) or {})
        lay.addLayout(self._controls())
        self._build_scopes()
        self._leave_keys_with_card()
        self._rebuild(reset=True)
        self._resume(saved)

        self.held = 0.0
        self.timer = QtCore.QTimer(self)
        self.timer.setInterval(500)
        self.timer.timeout.connect(self._tick)
        self.timer.start()

    def _flip_switch(self):
        from .home import Switch
        box = QtWidgets.QFrame()
        box.setObjectName("flipSwitch")
        box.setStyleSheet(
            f"QFrame#flipSwitch{{background:{SUBTLE}; border:1px solid {HAIRLINE};"
            "border-radius:15px;}")
        lay = QtWidgets.QHBoxLayout(box)
        lay.setContentsMargins(11, 3, 7, 3)
        lay.setSpacing(7)
        word = QtWidgets.QLabel(L("Turn"))
        word.setStyleSheet(f"color:{MUTED}; font-size:10.5px; font-weight:500;"
                           "border:none; background:transparent;")
        lay.addWidget(word)
        switch = Switch(self.turns_with_animation())
        switch.setAccessibleName(L("Turn the card with an animation"))
        switch.setFixedSize(30, 18)
        switch.toggled.connect(self._set_flip_animation)
        lay.addWidget(switch)
        self.flip_switch = switch
        box.setToolTip(L("Turn without the animation") if self.turns_with_animation()
                       else L("Turn with the animation"))
        self._flip_box = box
        return box

    def _set_flip_animation(self, on):
        self.store.set_setting("flashcard_flip_animation", bool(on))
        self._flip_box.setToolTip(L("Turn without the animation") if on
                                  else L("Turn with the animation"))

    def open_focus(self):
        if self._focus is not None:
            return
        self._focus = FocusOverlay(self)
        self._focus.setGeometry(self.rect())
        self._focus.show()
        self._focus.raise_()
        self._focus.setFocus(QtCore.Qt.OtherFocusReason)
        self._redraw()

    def close_focus(self):
        if self._focus is None:
            return
        self._focus.hide()
        self._focus.deleteLater()
        self._focus = None
        self.setFocus(QtCore.Qt.OtherFocusReason)
        self._redraw()

    def resizeEvent(self, event):
        if self._focus is not None:
            self._focus.setGeometry(self.rect())
        super().resizeEvent(event)

    def showEvent(self, event):
        super().showEvent(event)
        QtCore.QTimer.singleShot(0, self, self._take_keys)

    def _leave_keys_with_card(self):
        for button in self.findChildren(QtWidgets.QAbstractButton):
            button.setFocusPolicy(QtCore.Qt.TabFocus)

    def _take_keys(self):
        if self.isVisible() and self._focus is None:
            self.setFocus(QtCore.Qt.OtherFocusReason)

    def _build_scopes(self):
        while self.scope_row.count():
            item = self.scope_row.takeAt(0)
            if item.widget():
                item.widget().deleteLater()
        deck = self.store.decks.deck(self.deck_id)
        tracking = self.store.settings.get("track_skipped_cards", True)
        dealing = bool(self.store.daily_plan().get("enabled"))

        def offered(key):
            if key == "skimmed":
                return tracking
            if key == "today":
                return dealing
            return True

        for key in (k for k in vocab.SCOPES if offered(k)):
            n = len(vocab.in_scope(deck.cards, key))
            chip = _chip(vocab.scope_title(key), key == self.scope, n)
            chip.setEnabled(n > 0 or key == "all")
            chip.clicked.connect(lambda _=False, k=key: self._set_scope(k))
            self.scope_row.addWidget(chip)
        self._leave_keys_with_card()

    def _controls(self):
        row = QtWidgets.QHBoxLayout()
        row.setSpacing(10)
        left = QtWidgets.QWidget()
        left_row = QtWidgets.QHBoxLayout(left)
        left_row.setContentsMargins(0, 0, 0, 0)
        left_row.setSpacing(8)
        self.play = _icon_button(
            brand.ICONS["play"], Lf("Play the cards, %d seconds a side",
                    int(self.store.settings.get("flashcard_seconds", 5))))
        self.play.clicked.connect(self._toggle_play)
        self.shuffle = _icon_button(brand.ICONS["shuffle"], L("Shuffle the order"))
        self.shuffle.clicked.connect(self._toggle_shuffle)
        self.speed = _icon_button(self._speed_text(),
                                  L("How long autoplay holds each side"))
        self.speed.setCheckable(False)
        self.speed.clicked.connect(self._pick_speed)
        self.fill = _icon_button(brand.ICONS["fill_window"], L("Fill the window"))
        self.fill.setCheckable(False)
        self.fill.clicked.connect(self.open_focus)
        for b in (self.play, self.shuffle, self.fill, self.speed):
            left_row.addWidget(b)

        left_row.addSpacing(4)
        smaller = QtWidgets.QPushButton("A−")
        self.scale_label = QtWidgets.QLabel("")
        self.scale_label.setAlignment(QtCore.Qt.AlignCenter)
        self.scale_label.setFixedWidth(38)
        self.scale_label.setToolTip(L("Back to the normal size"))
        self.scale_label.setCursor(QtCore.Qt.PointingHandCursor)
        self.scale_label.setStyleSheet(f"color:{MUTED}; font-size:10px; border:none;")
        self.scale_label.mousePressEvent = lambda _event: self._reset_scale()
        bigger = QtWidgets.QPushButton("A+")
        for b, delta, tip in ((smaller, -0.1, L("Smaller")), (bigger, 0.1, L("Bigger"))):
            b.setCursor(QtCore.Qt.PointingHandCursor)
            b.setToolTip(tip)
            b.setFixedSize(30, 26)
            b.setStyleSheet(
                f"QPushButton{{background:{SUBTLE}; color:{INK};"
                f"border:1px solid {HAIRLINE}; border-radius:3px; font-size:12px;}}"
                f"QPushButton:hover{{background:{PAPER_DEEP};}}"
                f"QPushButton:disabled{{color:{MUTED};}}")
            b.clicked.connect(lambda _=False, d=delta: self._step_scale(d))
        self.smaller_button, self.bigger_button = smaller, bigger
        left_row.addWidget(smaller)
        left_row.addWidget(self.scale_label)
        left_row.addWidget(bigger)

        left_row.addSpacing(4)
        left_row.addWidget(self._flip_switch())
        row.addWidget(left)
        row.addStretch(1)

        self.back_button = QtWidgets.QPushButton("←")
        self.next_button = QtWidgets.QPushButton("→")
        self.back_button.setAccessibleName(L("Back"))
        self.next_button.setAccessibleName(L("Next"))
        for b in (self.back_button, self.next_button):
            b.setCursor(QtCore.Qt.PointingHandCursor)
            b.setFlat(True)
            b.setFixedWidth(34)
            b.setStyleSheet(
                f"QPushButton{{border:none; background:transparent; color:{INK};"
                "font-size:17px;}"
                f"QPushButton:hover{{color:{NAVY};}}"
                f"QPushButton:disabled{{color:{MUTED};}}")
        self.counter = QtWidgets.QLabel("")
        self.counter.setAlignment(QtCore.Qt.AlignCenter)
        self.counter.setMinimumWidth(84)
        self.counter.setStyleSheet(f"color:{INK}; font-size:13px; border:none;")
        self.back_button.clicked.connect(self.previous)
        self.next_button.clicked.connect(self.next)
        row.addWidget(self.back_button)
        row.addWidget(self.counter)
        row.addWidget(self.next_button)
        row.addStretch(1)
        width = left.sizeHint().width()
        left.setMinimumWidth(width)
        row.addSpacerItem(QtWidgets.QSpacerItem(
            width, 0, QtWidgets.QSizePolicy.Maximum, QtWidgets.QSizePolicy.Minimum))
        return row

    @property
    def pool(self):
        deck = self.store.decks.deck(self.deck_id)
        return vocab.in_scope(deck.cards, self.scope) if deck else []

    @property
    def card(self):
        if not (0 <= self.position < len(self.order)):
            return None
        wanted = self.order[self.position]
        deck = self.store.decks.deck(self.deck_id)
        for c in (deck.cards if deck else []):
            if c.id == wanted:
                return c
        return None

    def _set_scope(self, key):
        self.scope = key
        self._build_scopes()
        self._rebuild(reset=True)

    def _remember(self):
        self.store.deck_sessions[self.deck_id] = {
            "scope": self.scope, "shuffled": self.shuffled,
            "order": list(self.order), "position": self.position}

    def _resume(self, saved):
        if not saved:
            return
        deck = self.store.decks.deck(self.deck_id)
        alive = {c.id for c in (deck.cards if deck else [])}
        order = [i for i in saved.get("order", []) if i in alive]
        if not order:
            return
        self.scope = saved.get("scope", "all")
        self.shuffled = bool(saved.get("shuffled"))
        self.order = order
        self.position = min(int(saved.get("position", 0)), len(order) - 1)
        if hasattr(self, "shuffle"):
            self.shuffle.setChecked(self.shuffled)
        self._build_scopes()
        self._redraw()

    def _rebuild(self, reset):
        ids = [c.id for c in self.pool]
        if self.shuffled:
            random.shuffle(ids)
        self.order = ids
        if reset or self.position >= len(self.order):
            self.position = 0
        self.showing_back = False
        self.turned_this_card = False
        self._redraw()

    def _prune_deleted(self):
        deck = self.store.decks.deck(self.deck_id)
        alive = {c.id for c in (deck.cards if deck else [])}
        if all(i in alive for i in self.order):
            return
        here = self.order[self.position] if self.position < len(self.order) else None
        self.order = [i for i in self.order if i in alive]
        if here in self.order:
            self.position = self.order.index(here)
        else:
            self.position = min(self.position, max(0, len(self.order) - 1))

    def _scale(self):
        return float(self.store.settings.get("flashcard_scale", 1.0))

    def _step_scale(self, delta):
        value = max(0.6, min(2.5, round(self._scale() + delta, 2)))
        self.store.set_setting("flashcard_scale", value)
        self._redraw()

    def _reset_scale(self):
        self.store.set_setting("flashcard_scale", 1.0)
        self._redraw()

    def zoom_by(self, delta):
        if delta == 0:
            self._reset_scale()
        else:
            self._step_scale(0.1 * delta)

        self._build_scopes()

    def _redraw(self, turning=False):
        self._prune_deleted()
        for face in (self.face, self._focus.face if self._focus else None):
            if face is None:
                continue
            if turning:
                face.turn_to(self.card, self.showing_back, False, self._scale())
            else:
                face.show_card(self.card, self.showing_back, False, self._scale())
        if self._focus is not None:
            self._focus.refresh()
        self.counter.setText(f"{min(self.position + 1, len(self.order))} / {len(self.order)}")
        self._remember()
        self.scale_label.setText(f"{round(self._scale() * 100)}%")
        self.smaller_button.setEnabled(self._scale() > 0.6 + 0.001)
        self.bigger_button.setEnabled(self._scale() < 2.5 - 0.001)
        self.back_button.setEnabled(self.position > 0)
        self.next_button.setEnabled(self.position < len(self.order) - 1)

    def turns_with_animation(self):
        return bool(self.store.settings.get("flashcard_flip_animation", True))

    def flip(self):
        was_skimmed = bool(self.card and self.card.is_skimmed)
        opened = False
        if not self.showing_back and not self.turned_this_card and self.card:
            self.turned_this_card = True
            self.store.decks.record_turn(self.card.id, self.deck_id)
            opened = True
        self.showing_back = not self.showing_back
        self.held = 0
        self._redraw(turning=self.turns_with_animation())
        if opened and was_skimmed:
            self._build_scopes()

    def grade(self, correct):
        card = self.card
        if card is None:
            return
        self.store.decks.record_self_grade(card.id, correct, self.deck_id)
        self.store.note_daily_progress(self.deck_id)
        self.turned_this_card = True
        if self.position < len(self.order) - 1:
            self._move(self.position + 1)
        else:
            self._redraw()
        self._build_scopes()
        self.on_change()

    def _record_skip_if_unturned(self):
        if (self.store.settings.get("track_skipped_cards", True)
                and not self.turned_this_card and self.card):
            self.store.decks.record_skip(self.card.id, self.deck_id)
            return True
        return False

    def _move(self, index):
        counted = self._record_skip_if_unturned()
        self.position = index
        self.showing_back = False
        self.turned_this_card = False
        self._redraw()
        if counted:
            self._build_scopes()
            self.on_change()

    def previous(self):
        if self.position > 0:
            self._move(self.position - 1)

    def next(self):
        if self.position < len(self.order) - 1:
            self._move(self.position + 1)

    def _star(self):
        card = self.card
        if card is None:
            return
        self.store.decks.toggle_star(card.id, self.deck_id)
        self._build_scopes()
        self._redraw()
        self.on_change()

    def _toggle_shuffle(self):
        self.shuffled = self.shuffle.isChecked()
        self.shuffle.setToolTip(L("Back to the deck's own order") if self.shuffled
                                else L("Shuffle the order"))
        self._rebuild(reset=True)

    def _toggle_play(self):
        self.held = 0
        self.play.setText(brand.ICONS["pause" if self.play.isChecked() else "play"])

    def _speed_text(self):
        return Lf("%d s", int(self.store.settings.get('flashcard_seconds', 5)))

    def _pick_speed(self):
        current = int(self.store.settings.get("flashcard_seconds", 5))
        value, ok = QtWidgets.QInputDialog.getInt(
            self, L("Autoplay"),
            L("A card is held on its front for this long, then on its back, "
              "then the next one arrives."), current, 1, 20, 1)
        if ok:
            self.store.set_setting("flashcard_seconds", value)
            self.speed.setText(self._speed_text())

    def _tick(self):
        if not self.play.isChecked():
            self.held = 0
            return
        self.held += 0.5
        if self.held < max(1, int(self.store.settings.get("flashcard_seconds", 5))):
            return
        self.held = 0
        if not self.showing_back:
            self.flip()
        elif self.position < len(self.order) - 1:
            self.next()
        else:
            self.play.setChecked(False)
            self.play.setText(brand.ICONS["play"])

    def keyPressEvent(self, event):
        if event.key() == QtCore.Qt.Key_Space:
            self.flip()
        elif event.key() == QtCore.Qt.Key_Left:
            self.previous()
        elif event.key() == QtCore.Qt.Key_Right:
            self.next()
        elif event.key() == QtCore.Qt.Key_1:
            self.grade(False)
        elif event.key() == QtCore.Qt.Key_2:
            self.grade(True)
        else:
            super().keyPressEvent(event)


class TestPane(QtWidgets.QWidget):
    def __init__(self, store, deck_id, on_change, parent=None):
        super().__init__(parent)
        self.store = store
        self.deck_id = deck_id
        self.on_change = on_change
        self.side = "definitions"
        self.scope = "all"
        self.count = 20
        self.minutes = None
        self.seconds_left = None
        self.questions = []
        self.answers = []
        self.index = 0
        self.finished = False
        self.setObjectName("testPane")
        self.setStyleSheet(f"QWidget#testPane{{background:{PAPER};}}")
        QtWidgets.QVBoxLayout(self).setContentsMargins(0, 0, 0, 0)
        self.page = QtWidgets.QWidget()
        self.layout().addWidget(self.page)
        self._show_setup()

    @property
    def pool(self):
        deck = self.store.decks.deck(self.deck_id)
        return vocab.in_scope(deck.cards, self.scope) if deck else []

    def _swap(self, widget):
        self.layout().replaceWidget(self.page, widget)
        self.page.deleteLater()
        self.page = widget

    @staticmethod
    def _chip_row():
        from .home import FlowLayout
        holder = QtWidgets.QWidget()
        holder.setStyleSheet("background:transparent;")
        return holder, FlowLayout(holder, spacing=8)

    def _show_setup(self):
        deck = self.store.decks.deck(self.deck_id)
        available = vocab.available_count(self.pool)
        if available and self.count > available:
            self.count = available

        area = QtWidgets.QScrollArea()
        area.setWidgetResizable(True)
        area.setFrameShape(QtWidgets.QFrame.NoFrame)
        area.setHorizontalScrollBarPolicy(QtCore.Qt.ScrollBarAlwaysOff)
        area.setStyleSheet(SCROLLBAR)
        inner = QtWidgets.QWidget()
        inner.setObjectName("testSetup")
        inner.setStyleSheet(f"QWidget#testSetup{{background:{PAPER};}}")
        lay = QtWidgets.QVBoxLayout(inner)
        lay.setContentsMargins(24, 22, 24, 24)
        lay.setSpacing(16)

        box, bl = _panel(L("What the four answers are"))
        for key in vocab.ANSWER_SIDES:
            b = QtWidgets.QPushButton()
            b.setCheckable(True)
            b.setChecked(key == self.side)
            b.setCursor(QtCore.Qt.PointingHandCursor)
            detail = "\n".join(textwrap.wrap(vocab.side_detail(key), 96))
            b.setText(f"{vocab.side_title(key)}\n{detail}")
            b.setStyleSheet(
                f"QPushButton{{text-align:left; padding:9px 12px; border:none;"
                f"border-left:2px solid transparent; color:{INK}; font-size:12px;"
                "background:transparent;}"
                f"QPushButton:hover{{background:{PAPER_DEEP};}}"
                f"QPushButton:checked{{background:{BRASS_SOFT};"
                f"border-left:2px solid {BRASS}; font-weight:600;}}")
            b.clicked.connect(lambda _=False, k=key: self._set_side(k))
            bl.addWidget(b)
        lay.addWidget(box)

        box, bl = _panel(L("Which words"))
        holder, row = self._chip_row()
        for key in vocab.SCOPES:
            n = vocab.available_count(vocab.in_scope(deck.cards, key))
            chip = _chip(vocab.scope_title(key), key == self.scope, n)
            chip.setEnabled(n >= vocab.MINIMUM_CARDS)
            chip.clicked.connect(lambda _=False, k=key: self._set_scope(k))
            row.addWidget(chip)
        bl.addWidget(holder)
        note = QtWidgets.QLabel(
            L("A word needs a definition before it can be tested — a card with only a "
            "word on it has no right answer to offer."))
        note.setWordWrap(True)
        leading(note)
        note.setStyleSheet(f"color:{MUTED}; font-size:11px; border:none;")
        bl.addWidget(note)
        lay.addWidget(box)

        box, bl = _panel(L("How many questions"))
        holder, row = self._chip_row()
        for n in (10, 20, 30, 50):
            chip = _chip(str(n), self.count == n)
            chip.setEnabled(n <= available)
            chip.clicked.connect(lambda _=False, v=n: self._set_count(v))
            row.addWidget(chip)
        chip = _chip(L("All"), self.count == available and available > 0)
        chip.setEnabled(available > 0)
        chip.clicked.connect(lambda _=False: self._set_count(available))
        row.addWidget(chip)
        typed = QtWidgets.QLineEdit()
        typed.setPlaceholderText(L("or type a number"))
        typed.setAccessibleName(L("or type a number"))
        typed.setFixedWidth(130)
        typed.setAlignment(QtCore.Qt.AlignCenter)
        typed.setValidator(QtGui.QIntValidator(1, 999, typed))
        typed.setStyleSheet(
            f"background:{SUBTLE}; border:1px solid {HAIRLINE}; border-radius:3px;"
            f"padding:4px; font-size:12px; color:{INK};")
        typed.editingFinished.connect(
            lambda: self._set_count(max(1, min(int(typed.text() or 0) or self.count,
                                               max(1, available)))))
        row.addWidget(typed)
        bl.addWidget(holder)
        lay.addWidget(box)

        box, bl = _panel(L("A clock, if you want one"))
        holder, row = self._chip_row()
        chip = _chip(L("No clock"), self.minutes is None)
        chip.clicked.connect(lambda _=False: self._set_minutes(None))
        row.addWidget(chip)
        for m in (2, 5, 10, 20):
            chip = _chip(Lf("%d min", m), self.minutes == m)
            chip.clicked.connect(lambda _=False, v=m: self._set_minutes(v))
            row.addWidget(chip)
        typed_minutes = QtWidgets.QLineEdit()
        typed_minutes.setPlaceholderText(L("or type minutes"))
        typed_minutes.setAccessibleName(L("or type minutes"))
        typed_minutes.setFixedWidth(130)
        typed_minutes.setAlignment(QtCore.Qt.AlignCenter)
        typed_minutes.setValidator(QtGui.QIntValidator(1, 180, typed_minutes))
        typed_minutes.setStyleSheet(
            f"background:{SUBTLE}; border:1px solid {HAIRLINE}; border-radius:3px;"
            f"padding:4px; font-size:12px; color:{INK};")
        typed_minutes.editingFinished.connect(
            lambda: self._set_minutes(max(1, min(int(typed_minutes.text() or 0) or 1, 180)))
            if typed_minutes.text() else None)
        row.addWidget(typed_minutes)
        bl.addWidget(holder)
        note = QtWidgets.QLabel(
            L("Vocabulary has no official pace — the SAT does not test words on their "
            "own. A clock here is for making yourself answer from memory instead of "
            "working it out."))
        note.setWordWrap(True)
        leading(note)
        note.setStyleSheet(f"color:{MUTED}; font-size:10px; border:none;")
        bl.addWidget(note)
        lay.addWidget(box)

        if available < vocab.MINIMUM_CARDS:
            warn = QtWidgets.QLabel(
                Lf("A test needs at least %d words with definitions. This selection has %d.",
                   vocab.MINIMUM_CARDS, available))
            warn.setWordWrap(True)
            leading(warn)
            warn.setStyleSheet(f"color:{WRONG}; font-size:12px; border:none;")
            lay.addWidget(warn)

        start = _primary(L("Start the test"))
        start.setEnabled(available >= vocab.MINIMUM_CARDS)
        start.clicked.connect(self._start)
        row = QtWidgets.QHBoxLayout()
        row.addWidget(start)
        row.addStretch(1)
        lay.addLayout(row)
        lay.addStretch(1)

        area.setWidget(inner)
        self._swap(area)

    def _set_side(self, key):
        self.side = key
        self._show_setup()

    def _set_scope(self, key):
        self.scope = key
        self._show_setup()

    def _set_count(self, n):
        self.count = n
        self._show_setup()

    def _set_minutes(self, m):
        self.minutes = m
        self._show_setup()

    def _start(self):
        self.questions = vocab.build_test(self.pool, self.side, self.count)
        self.answers = [None] * len(self.questions)
        self.index = 0
        self.finished = False
        self.seconds_left = self.minutes * 60 if self.minutes else None
        if self.questions:
            self._show_question()
            self._run_clock()

    def _run_clock(self):
        if not hasattr(self, "_timer"):
            self._timer = QtCore.QTimer(self)
            self._timer.setInterval(1000)
            self._timer.timeout.connect(self._tick)
        if self.seconds_left is None:
            self._timer.stop()
        else:
            self._timer.start()

    def _tick(self):
        if self.seconds_left is None or self.finished:
            self._timer.stop()
            return
        self.seconds_left -= 1
        if self.seconds_left <= 0:
            self.seconds_left = None
            self._timer.stop()
            self._submit()
        else:
            self._show_question()

    def _show_question(self):
        q = self.questions[self.index]
        page = QtWidgets.QWidget()
        page.setObjectName("testRun")
        page.setStyleSheet(f"QWidget#testRun{{background:{PAPER};}}")
        outer = QtWidgets.QVBoxLayout(page)
        outer.setContentsMargins(0, 0, 0, 0)
        outer.setSpacing(0)

        head = QtWidgets.QWidget()
        head.setObjectName("testHead")
        head.setStyleSheet(f"QWidget#testHead{{background:{CARD};}}")
        hl = QtWidgets.QHBoxLayout(head)
        hl.setContentsMargins(24, 12, 24, 12)
        progress = QtWidgets.QLabel(
            Lf("Question %1$d of %2$d", self.index + 1, len(self.questions)))
        progress.setStyleSheet(f"color:{INK}; font-size:12px; font-weight:600; border:none;")
        answered = QtWidgets.QLabel(
            Lf("%d answered", sum(1 for a in self.answers if a is not None)))
        answered.setStyleSheet(f"color:{MUTED}; font-size:11px; border:none;")
        hl.addWidget(progress)
        hl.addStretch(1)
        hl.addWidget(answered)
        if self.seconds_left is not None:
            left = int(self.seconds_left)
            urgent = left <= 60
            clock = QtWidgets.QLabel(f"{left // 60}:{left % 60:02d}")
            clock.setStyleSheet(
                f"color:{WRONG if urgent else NAVY}; font-size:12px; font-weight:600;"
                f"background:{WRONG_SOFT if urgent else SUBTLE};"
                "border-radius:9px; padding:2px 9px;")
            hl.addWidget(clock)
        outer.addWidget(head)
        outer.addWidget(_rule())

        body = QtWidgets.QWidget()
        bl = QtWidgets.QVBoxLayout(body)
        bl.setContentsMargins(24, 24, 24, 24)
        bl.setSpacing(18)
        ask = QtWidgets.QLabel(L("What does this word mean?") if q.asks_for_definition
                               else L("Which word means this?"))
        ask.setStyleSheet(
            f"color:{MUTED}; font-size:11px; font-weight:600; letter-spacing:1.2px; border:none;")
        prompt = QtWidgets.QLabel(q.prompt)
        prompt.setWordWrap(True)
        leading(prompt)
        prompt.setStyleSheet(
            f"color:{NAVY}; border:none;"
            + (f"font-size:30px; font-family:{SERIF};" if q.asks_for_definition
               else "font-size:19px;"))
        bl.addWidget(ask)
        bl.addWidget(prompt)
        for i, option in enumerate(q.options):
            b = QtWidgets.QPushButton(f"{'ABCD'[i]}    {option}".replace("&", "&&"))
            b.setCheckable(True)
            b.setChecked(self.answers[self.index] == i)
            b.setCursor(QtCore.Qt.PointingHandCursor)
            b.setStyleSheet(
                f"QPushButton{{text-align:left; padding:11px 14px; font-size:13px;"
                f"background:{CARD}; color:{INK}; border:1px solid {HAIRLINE};"
                "border-radius:4px;}"
                f"QPushButton:hover{{background:{PAPER_DEEP};}}"
                f"QPushButton:checked{{background:{BRASS_SOFT};"
                f"border:2px solid {BRASS}; font-weight:600;}}")
            b.clicked.connect(lambda _=False, v=i: self._choose(v))
            bl.addWidget(b)
        bl.addStretch(1)
        outer.addWidget(body, 1)

        outer.addWidget(_rule())
        foot = QtWidgets.QWidget()
        foot.setObjectName("testFoot")
        foot.setStyleSheet(f"QWidget#testFoot{{background:{CARD};}}")
        fl = QtWidgets.QHBoxLayout(foot)
        fl.setContentsMargins(24, 12, 24, 12)
        fl.setSpacing(10)
        back = _secondary(L("Back"))
        back.setEnabled(self.index > 0)
        back.clicked.connect(self._back)
        fl.addWidget(back)
        fl.addStretch(1)
        stop = QtWidgets.QPushButton(L("Stop this test"))
        stop.setFlat(True)
        stop.setCursor(QtCore.Qt.PointingHandCursor)
        stop.setStyleSheet(
            f"QPushButton{{border:none; background:transparent; color:{MUTED};"
            "font-size:11px;}"
            f"QPushButton:hover{{color:{NAVY};}}")
        stop.clicked.connect(self._show_setup)
        fl.addWidget(stop)
        if self.index == len(self.questions) - 1:
            submit = _primary(L("Submit"))
            submit.clicked.connect(self._submit)
            fl.addWidget(submit)
        else:
            nxt = _primary(L("Next"))
            nxt.clicked.connect(self._next)
            fl.addWidget(nxt)
        outer.addWidget(foot)
        self._swap(page)

    def _choose(self, i):
        self.answers[self.index] = i
        self._show_question()

    def _back(self):
        self.index -= 1
        self._show_question()

    def _next(self):
        self.index += 1
        self._show_question()

    def _submit(self):
        results = {q.card_id: (a == q.answer_index)
                   for q, a in zip(self.questions, self.answers)}
        self.store.decks.record_test(results, self.deck_id)
        self.store.note_daily_progress(self.deck_id)
        self.on_change()
        self._show_results()

    def _missed(self):
        return [q.card_id for q, a in zip(self.questions, self.answers)
                if a != q.answer_index]

    def _show_results(self):
        right = sum(1 for q, a in zip(self.questions, self.answers) if a == q.answer_index)
        total = len(self.questions)
        area = QtWidgets.QScrollArea()
        area.setWidgetResizable(True)
        area.setFrameShape(QtWidgets.QFrame.NoFrame)
        area.setHorizontalScrollBarPolicy(QtCore.Qt.ScrollBarAlwaysOff)
        area.setStyleSheet(SCROLLBAR)
        inner = QtWidgets.QWidget()
        inner.setObjectName("testResults")
        inner.setStyleSheet(f"QWidget#testResults{{background:{PAPER};}}")
        lay = QtWidgets.QVBoxLayout(inner)
        lay.setContentsMargins(24, 22, 24, 24)
        lay.setSpacing(14)

        score = QtWidgets.QLabel(Lf("%1$d of %2$d", right, total))
        score.setStyleSheet(
            f"color:{NAVY}; font-size:36px; font-weight:600; font-family:{NUMERALS}; border:none;")
        lay.addWidget(score)
        rule = _rule(brass=True)
        rule.setFixedWidth(44)
        lay.addWidget(rule)
        pct = QtWidgets.QLabel(Lf("%d%% right", round(100 * right / total) if total else 0))
        pct.setStyleSheet(f"color:{MUTED}; font-size:13px; border:none;")
        lay.addWidget(pct)

        row = QtWidgets.QHBoxLayout()
        row.setSpacing(10)
        again = _primary(L("Test again"))
        again.clicked.connect(self._start)
        row.addWidget(again)
        missed = self._missed()
        if len(missed) >= vocab.MINIMUM_CARDS:
            retry = _secondary(L("Test only what I missed"))
            retry.clicked.connect(self._retry_missed)
            row.addWidget(retry)
        if missed:
            star = _secondary(L("Star what I missed"))
            star.clicked.connect(self._star_missed)
            row.addWidget(star)
        back = _secondary(L("Back to setup"))
        back.clicked.connect(self._show_setup)
        row.addWidget(back)
        row.addStretch(1)
        lay.addLayout(row)
        lay.addWidget(_rule())

        for i, (q, a) in enumerate(zip(self.questions, self.answers), start=1):
            ok = a == q.answer_index
            box = QtWidgets.QWidget()
            bl = QtWidgets.QVBoxLayout(box)
            bl.setContentsMargins(0, 8, 0, 8)
            bl.setSpacing(3)
            head = QtWidgets.QLabel(q.prompt)
            head.setWordWrap(True)
            leading(head)
            head.setStyleSheet(
                f"color:{CORRECT if ok else WRONG}; font-size:13px; font-weight:600;"
                "border:none;")
            mark = QtWidgets.QLabel()
            mark.setPixmap(brand.icon("tick" if ok else "cross", 13,
                                      CORRECT if ok else WRONG).pixmap(13, 13))
            mark.setAlignment(QtCore.Qt.AlignTop)
            mark.setStyleSheet("border:none; background:transparent;")
            head_row = QtWidgets.QWidget()
            head_row.setStyleSheet("background:transparent;")
            hr = QtWidgets.QHBoxLayout(head_row)
            hr.setContentsMargins(0, 0, 0, 0)
            hr.setSpacing(8)
            hr.addWidget(mark, 0, QtCore.Qt.AlignTop)
            hr.addWidget(head, 1)
            answer = QtWidgets.QLabel(Lf("Answer: %@", q.answer))
            answer.setWordWrap(True)
            leading(answer)
            answer.setStyleSheet(f"color:{INK}; font-size:12px; border:none;")
            bl.addWidget(head_row)
            bl.addWidget(answer)
            if not ok:
                chosen = QtWidgets.QLabel(L("You left this one blank.") if a is None
                                          else Lf("You chose: %@", q.options[a]))
                chosen.setWordWrap(True)
                leading(chosen)
                chosen.setStyleSheet(f"color:{WRONG}; font-size:11px; border:none;")
                bl.addWidget(chosen)
            lay.addWidget(box)
            lay.addWidget(_rule())
        lay.addStretch(1)
        area.setWidget(inner)
        self._swap(area)

    def _star_missed(self):
        missed = set(self._missed())
        deck = self.store.decks.deck(self.deck_id)
        for card in deck.cards:
            if card.id in missed:
                card.starred = True
        self.store.decks.save(deck)
        self.on_change()
        self._show_results()

    def _retry_missed(self):
        missed = set(self._missed())
        deck = self.store.decks.deck(self.deck_id)
        cards = [c for c in deck.cards if c.id in missed]
        if not cards:
            return
        built = vocab.build_test(deck.cards, self.side, len(cards), asking=cards)
        if not built:
            return
        self.questions = built
        self.answers = [None] * len(built)
        self.index = 0
        self._show_question()


def _panel(title):
    box = QtWidgets.QFrame()
    box.setObjectName("panel")
    box.setStyleSheet(
        f"QFrame#panel{{background:{CARD}; border:1px solid {HAIRLINE}; border-radius:4px;}}")
    lay = QtWidgets.QVBoxLayout(box)
    lay.setContentsMargins(22, 20, 22, 20)
    lay.setSpacing(12)
    lay.addWidget(_label(title))
    rule = _rule(brass=True)
    rule.setFixedWidth(34)
    lay.addWidget(rule)
    return box, lay


class CardsPane(QtWidgets.QWidget):
    def __init__(self, store, deck_id, on_change, parent=None):
        super().__init__(parent)
        self.store = store
        self.deck_id = deck_id
        self.on_change = on_change
        self.search = ""
        self.sort = "deckOrder"
        self.selected = set()
        self.setObjectName("cardsPane")
        self.setStyleSheet(f"QWidget#cardsPane{{background:{PAPER};}}")
        lay = QtWidgets.QVBoxLayout(self)
        lay.setContentsMargins(0, 0, 0, 0)
        lay.setSpacing(0)

        bar = QtWidgets.QWidget()
        bar.setObjectName("cardsBar")
        bar.setStyleSheet(f"QWidget#cardsBar{{background:{CARD};}}")
        bl = QtWidgets.QVBoxLayout(bar)
        bl.setContentsMargins(22, 12, 22, 12)
        bl.setSpacing(10)

        top = QtWidgets.QHBoxLayout()
        top.setSpacing(10)
        self.search_box = QtWidgets.QLineEdit()
        self.search_box.setPlaceholderText(L("Search this deck"))
        self.search_box.setAccessibleName(L("Search this deck"))
        self.search_box.setMaximumWidth(280)
        self.search_box.setStyleSheet(
            f"QLineEdit{{background:{SUBTLE}; border:1px solid {HAIRLINE}; border-radius:3px;"
            f"padding:6px 10px; font-size:12px; color:{INK};}}")
        self.search_box.textChanged.connect(self._search_changed)
        top.addWidget(self.search_box)
        top.addStretch(1)
        self.note = QtWidgets.QLabel("")
        self.note.setStyleSheet(f"color:{BRASS_TEXT}; font-size:11px; border:none;")
        top.addWidget(self.note)
        self.sort_button = _secondary("")
        self.sort_button.clicked.connect(self._pick_sort)
        self._label_sort()
        top.addWidget(self.sort_button)
        take = _secondary(L("Take words from a question set…"))
        take.setEnabled(bool(store.banks))
        take.clicked.connect(self._mine)
        top.addWidget(take)
        bl.addLayout(top)

        add = QtWidgets.QHBoxLayout()
        add.setSpacing(8)
        self.term_box = QtWidgets.QLineEdit()
        self.term_box.setPlaceholderText(L("Word"))
        self.term_box.setAccessibleName(L("Word"))
        self.term_box.setFixedWidth(190)
        self.definition_box = QtWidgets.QLineEdit()
        self.definition_box.setPlaceholderText(L("What it means"))
        self.definition_box.setAccessibleName(L("What it means"))
        for box in (self.term_box, self.definition_box):
            box.setStyleSheet(
                f"QLineEdit{{background:{PAPER}; border:1px solid {HAIRLINE};"
                f"border-radius:3px; padding:6px 10px; font-size:12px; color:{INK};}}")
            box.returnPressed.connect(self._commit)
        add_button = _primary(L("Add"))
        add_button.clicked.connect(self._commit)
        add.addWidget(self.term_box)
        add.addWidget(self.definition_box, 1)
        add.addWidget(add_button)
        bl.addLayout(add)

        self.selection_bar = QtWidgets.QWidget()
        sel = QtWidgets.QHBoxLayout(self.selection_bar)
        sel.setContentsMargins(0, 0, 0, 0)
        sel.setSpacing(12)
        self.selection_label = QtWidgets.QLabel("")
        self.selection_label.setStyleSheet(f"color:{BRASS_TEXT}; font-size:11px; border:none;")
        sel.addWidget(self.selection_label)
        for text, slot in ((L("Select all"), self._select_all),
                           (L("Select none"), self._select_none),
                           (L("Star them"), lambda: self._star_selected(True)),
                           (L("Remove their stars"), lambda: self._star_selected(False))):
            b = QtWidgets.QPushButton(text)
            b.setFlat(True)
            b.setCursor(QtCore.Qt.PointingHandCursor)
            b.setStyleSheet(
                f"QPushButton{{border:none; background:transparent; color:{MUTED};"
                "font-size:11px;}"
                f"QPushButton:hover{{color:{NAVY};}}")
            b.clicked.connect(slot)
            sel.addWidget(b)
        sel.addStretch(1)
        delete_selected = _secondary(L("Delete selected"))
        delete_selected.clicked.connect(self._delete_selected)
        sel.addWidget(delete_selected)
        self.selection_bar.setVisible(False)
        bl.addWidget(self.selection_bar)

        lay.addWidget(bar)
        lay.addWidget(_rule())

        self.area = QtWidgets.QScrollArea()
        self.area.setWidgetResizable(True)
        self.area.setFrameShape(QtWidgets.QFrame.NoFrame)
        self.area.setHorizontalScrollBarPolicy(QtCore.Qt.ScrollBarAlwaysOff)
        self.area.setStyleSheet(SCROLLBAR)
        lay.addWidget(self.area, 1)
        self._fill()

    def _search_changed(self, text):
        self.search = text
        self._fill()

    def _shown(self):
        deck = self.store.decks.deck(self.deck_id)
        if deck is None:
            return []
        needle = self.search.strip().lower()
        cards = deck.cards
        if needle:
            cards = [c for c in cards
                     if needle in vocab.plain(c.term).lower()
                     or needle in vocab.plain(c.definition).lower()]
        return vocab.sort_cards(cards, self.sort)

    def _label_sort(self):
        self.sort_button.setText(
            L("Sort") if self.sort == "deckOrder"
            else vocab.card_sort_title(self.sort))

    def _pick_sort(self):
        menu = QtWidgets.QMenu(self)
        brand.dress_menu(menu)
        for key in ("deckOrder", "definitionsMissing", "alphabetical",
                    "hardestFirst", "skippedMost", "newestFirst"):
            action = menu.addAction(vocab.card_sort_title(key))
            action.setCheckable(True)
            action.setChecked(key == self.sort)
            action.triggered.connect(lambda _=False, k=key: self._set_sort(k))
        menu.exec(QtGui.QCursor.pos())

    def _set_sort(self, key):
        self.sort = key
        self._label_sort()
        self._fill()

    def _selected_shown(self):
        return [c for c in self._shown() if c.id in self.selected]

    def _refresh_selection_bar(self):
        rows = self._selected_shown()
        self.selection_bar.setVisible(bool(rows))
        self.selection_label.setText(Lf("%d selected", len(rows)))

    def _toggle_selected(self, card, on):
        if on:
            self.selected.add(card.id)
        else:
            self.selected.discard(card.id)
        self._refresh_selection_bar()

    def _select_all(self):
        self.selected = {c.id for c in self._shown()}
        self._fill()

    def _select_none(self):
        self.selected = set()
        self._fill()

    def _star_selected(self, starred):
        self.store.decks.set_starred(starred, {c.id for c in self._selected_shown()},
                                     self.deck_id)
        self._fill()
        self.on_change()

    def _delete_selected(self):
        rows = self._selected_shown()
        if not rows:
            return
        if not brand.ask(
                self, L("Delete these cards?"),
                Lp(len(rows), "%d card will be removed from this deck.",
                   "%d cards will be removed from this deck."),
                accept=L("Delete"), destructive=True):
            return
        self.store.decks.delete_cards({c.id for c in rows}, self.deck_id)
        self.note.setText(Lp(len(rows), "%d deleted", "%d deleted"))
        self.selected = set()
        self._fill()
        self.on_change()

    def _fill(self):
        inner = QtWidgets.QWidget()
        inner.setObjectName("cardList")
        inner.setStyleSheet(f"QWidget#cardList{{background:{PAPER};}}")
        lay = QtWidgets.QVBoxLayout(inner)
        lay.setContentsMargins(0, 0, 0, 0)
        lay.setSpacing(0)
        rows = self._shown()
        for card in rows:
            lay.addWidget(self._row(card))
            lay.addWidget(_rule())
        deck = self.store.decks.deck(self.deck_id)
        if not rows:
            empty = QtWidgets.QLabel(
                L("Nothing here yet. Type a word and what it means above, or take a set "
                "of words out of a question bank.")
                if deck is not None and not deck.cards else L("No card here matches that."))
            empty.setWordWrap(True)
            leading(empty)
            empty.setMaximumWidth(400)
            empty.setAlignment(QtCore.Qt.AlignCenter)
            empty.setContentsMargins(0, 40, 0, 40)
            empty.setSizePolicy(QtWidgets.QSizePolicy.Expanding,
                                QtWidgets.QSizePolicy.Preferred)
            empty.setStyleSheet(f"color:{MUTED}; font-size:12px; border:none;")
            middle = QtWidgets.QHBoxLayout()
            middle.addStretch(1)
            middle.addWidget(empty, 100)
            middle.addStretch(1)
            lay.addLayout(middle)
        lay.addStretch(1)
        self.area.setWidget(inner)
        self._refresh_selection_bar()

    def _row(self, card):
        row = QtWidgets.QWidget()
        lay = QtWidgets.QHBoxLayout(row)
        lay.setContentsMargins(22, 10, 22, 10)
        lay.setSpacing(12)

        tick = QtWidgets.QCheckBox()
        tick.setChecked(card.id in self.selected)
        tick.setToolTip(L("Select this card"))
        tick.setAccessibleName(L("Select this card"))
        tick.toggled.connect(lambda on, c=card: self._toggle_selected(c, on))
        lay.addWidget(tick, 0, QtCore.Qt.AlignTop)

        star = QtWidgets.QPushButton()
        star.setIcon(brand.icon("star_on" if card.starred else "star", 13,
                                BRASS if card.starred else MUTED))
        star.setIconSize(QtCore.QSize(13, 13))
        star.setAccessibleName(L("Remove the star") if card.starred else L("Star this word"))
        star.setFixedWidth(22)
        star.setFlat(True)
        star.setCursor(QtCore.Qt.PointingHandCursor)
        star.setStyleSheet("QPushButton{border:none; background:transparent;}")
        star.clicked.connect(lambda _=False, c=card: self._star(c))
        lay.addWidget(star, 0, QtCore.Qt.AlignTop)

        term = QtWidgets.QLabel(vocab.to_html(card.term))
        term.setTextFormat(QtCore.Qt.RichText)
        term.setFixedWidth(170)
        term.setWordWrap(True)
        leading(term)
        term.setStyleSheet(f"color:{NAVY}; font-size:13px; font-weight:600; border:none;")
        lay.addWidget(term, 0, QtCore.Qt.AlignTop)

        column = QtWidgets.QVBoxLayout()
        column.setSpacing(3)
        meaning = QtWidgets.QLabel(vocab.to_html(card.definition) if card.has_definition
                                   else L("No definition yet"))
        meaning.setTextFormat(QtCore.Qt.RichText)
        meaning.setWordWrap(True)
        leading(meaning)
        meaning.setStyleSheet(
            f"color:{INK if card.has_definition else MUTED}; font-size:12px;"
            + ("" if card.has_definition else "font-style:italic;") + "border:none;")
        column.addWidget(meaning)
        if card.example:
            example = QtWidgets.QLabel(vocab.to_html(card.example))
            example.setTextFormat(QtCore.Qt.RichText)
            example.setWordWrap(True)
            leading(example)
            example.setStyleSheet(
                f"color:{MUTED}; font-size:11px; font-style:italic; border:none;")
            column.addWidget(example)
        if card.record_line:
            record = QtWidgets.QLabel(card.record_line)
            record.setStyleSheet(f"color:{MUTED}; font-size:10px; border:none;")
            column.addWidget(record)
        if card.source_bank_name:
            source = QtWidgets.QLabel(Lf("from %@", card.source_bank_name))
            source.setStyleSheet(f"color:{MUTED}; font-size:10px; border:none;")
            column.addWidget(source)
        lay.addLayout(column, 1)

        if card.accuracy is not None:
            score = QtWidgets.QLabel(f"{round(card.accuracy * 100)}%")
            score.setToolTip(Lf("Right %1$d of %2$d in tests",
                                card.times_correct, card.times_seen))
            score.setStyleSheet(
                f"color:{WRONG if card.is_trouble else MUTED}; font-size:11px; border:none;")
            lay.addWidget(score, 0, QtCore.Qt.AlignTop)

        for glyph, tip, slot in ((L("Edit"), L("Edit this card"), self._edit),
                                 (L("Delete"), L("Delete this card"), self._delete)):
            b = QtWidgets.QPushButton(glyph)
            b.setFlat(True)
            b.setCursor(QtCore.Qt.PointingHandCursor)
            b.setToolTip(tip)
            b.setStyleSheet(
                f"QPushButton{{border:none; background:transparent; color:{MUTED};"
                "font-size:11px;}"
                f"QPushButton:hover{{color:{NAVY};}}")
            b.clicked.connect(lambda _=False, c=card, s=slot: s(c))
            lay.addWidget(b, 0, QtCore.Qt.AlignTop)
        return row

    def _star(self, card):
        self.store.decks.toggle_star(card.id, self.deck_id)
        self._fill()
        self.on_change()

    def _edit(self, card):
        if CardDialog(self.store, self.deck_id, card, self).exec():
            self._fill()
            self.on_change()

    def _delete(self, card):
        if brand.ask(
                self, L("Delete this card?"),
                Lf("“%@” will be removed from this deck.", card.term),
                accept=L("Delete"), destructive=True):
            self.store.decks.delete_card(card.id, self.deck_id)
            self._fill()
            self.on_change()

    def _commit(self):
        term = self.term_box.text().strip()
        if not term:
            return
        added = self.store.decks.add_card(
            vocab.Flashcard(term=term, definition=self.definition_box.text().strip()),
            self.deck_id)
        self.note.setText(Lf('Added "%@"', term) if added
                          else Lf('"%@" is already in this deck', term))
        self.term_box.clear()
        self.definition_box.clear()
        self.term_box.setFocus()
        self._fill()
        self.on_change()

    def _mine(self):
        dialog = MiningDialog(self.store, self.deck_id, self)
        if dialog.exec():
            self.note.setText(Lp(dialog.added, "%d word added", "%d words added"))
            self._fill()
            self.on_change()


class CardDialog(QtWidgets.QDialog):
    def __init__(self, store, deck_id, card, parent=None):
        super().__init__(parent)
        brand.as_sheet(self, parent)
        self.store = store
        self.deck_id = deck_id
        self.card = card
        self.setWindowTitle(L("Edit card"))
        self.setMinimumWidth(540)
        self.setStyleSheet(f"QDialog{{background:{PAPER};}}")
        lay = QtWidgets.QVBoxLayout(self)
        lay.setContentsMargins(22, 20, 22, 20)
        lay.setSpacing(12)
        _title = QtWidgets.QLabel(L("Edit card"))
        _title.setStyleSheet(
            f"color:{INK}; font-size:15px; font-weight:600;"
            f"font-family:{SERIF}; background:transparent; border:none;")
        lay.addWidget(_title)
        lay.addSpacing(10)

        self.term = QtWidgets.QTextEdit(card.term)
        self.term.setFixedHeight(34)
        self.term.setVerticalScrollBarPolicy(QtCore.Qt.ScrollBarAlwaysOff)
        self.term.setHorizontalScrollBarPolicy(QtCore.Qt.ScrollBarAlwaysOff)
        self.definition = QtWidgets.QTextEdit(card.definition)
        self.definition.setFixedHeight(64)
        self.example = QtWidgets.QTextEdit(card.example)
        self.example.setFixedHeight(64)
        self.definition.verticalScrollBar().setStyleSheet(SCROLLBAR)
        self.example.verticalScrollBar().setStyleSheet(SCROLLBAR)
        self.hint = QtWidgets.QLineEdit(card.hint)
        self.hint.setPlaceholderText(L("Leave empty and half the definition is used"))
        self.hint.setAccessibleName(L("Hint"))
        self.term.setAccessibleName(L("Word"))
        self.definition.setAccessibleName(L("What it means"))
        self.example.setAccessibleName(L("A sentence using it"))
        for label, widget in ((L("Word"), self.term), (L("What it means"), self.definition),
                              (L("A sentence using it"), self.example)):
            head = QtWidgets.QHBoxLayout()
            head.addWidget(_label(label))
            head.addStretch(1)
            head.addWidget(self._toolbar(widget))
            lay.addLayout(head)
            widget.setAcceptRichText(False)
            widget.setStyleSheet(
                f"background:{CARD}; border:1px solid {HAIRLINE}; border-radius:3px;"
                f"padding:5px; font-size:12px; color:{INK};")
            lay.addWidget(widget)
        lay.addWidget(_label(L("Hint")))
        self.hint.setStyleSheet(
            f"background:{CARD}; border:1px solid {HAIRLINE}; border-radius:3px;"
            f"padding:5px; font-size:12px; color:{INK};")
        lay.addWidget(self.hint)

        self.preview = QtWidgets.QLabel("")
        self.preview.setWordWrap(True)
        leading(self.preview)
        self.preview.setStyleSheet(f"color:{MUTED}; font-size:11px; border:none;")
        lay.addWidget(self.preview)

        lay.addWidget(_label(L("How the card will read")))
        self.rendered = QtWidgets.QLabel("")
        self.rendered.setWordWrap(True)
        leading(self.rendered)
        self.rendered.setTextFormat(QtCore.Qt.RichText)
        self.rendered.setStyleSheet(
            f"background:{CARD}; border:1px solid {HAIRLINE}; border-radius:3px;"
            f"padding:8px; font-size:14px; color:{INK};")
        lay.addWidget(self.rendered)

        self.definition.textChanged.connect(self._update_preview)
        self.term.textChanged.connect(self._update_preview)
        self.hint.textChanged.connect(self._update_preview)
        self._update_preview()

        row = QtWidgets.QHBoxLayout()
        row.addStretch(1)
        cancel = _secondary(L("Cancel"))
        cancel.clicked.connect(self.reject)
        save = _primary(L("Save"))
        save.clicked.connect(self._save)
        row.addWidget(cancel)
        row.addWidget(save)
        lay.addLayout(row)

        self.term.setFocus()

    def _toolbar(self, widget):
        box = QtWidgets.QWidget()
        row = QtWidgets.QHBoxLayout(box)
        row.setContentsMargins(0, 0, 0, 0)
        row.setSpacing(2)
        for style, glyph in (("bold", "B"), ("italic", "I"),
                             ("underline", "U"), ("highlight", "\u25a0")):
            b = QtWidgets.QPushButton(glyph)
            b.setFixedSize(24, 20)
            b.setCursor(QtCore.Qt.PointingHandCursor)
            name = L({"bold": "Bold", "italic": "Italic", "underline": "Underline",
                      "highlight": "Highlight"}[style])
            b.setToolTip(name)
            b.setAccessibleName(name)
            b.setStyleSheet(
                f"QPushButton{{background:{SUBTLE}; color:{INK};"
                f"border:1px solid {HAIRLINE}; border-radius:2px; font-size:11px;}}"
                f"QPushButton:hover{{background:{PAPER_DEEP};}}")
            b.clicked.connect(lambda _=False, w=widget, st=style: self._apply(w, st))
            row.addWidget(b)
        return box

    def _apply(self, widget, style):
        cursor = widget.textCursor()
        start, end = cursor.selectionStart(), cursor.selectionEnd()
        if start == end:
            return
        text, (lo, hi) = vocab.toggle(style, widget.toPlainText(), start, end)
        widget.blockSignals(True)
        widget.setPlainText(text)
        widget.blockSignals(False)
        cursor = widget.textCursor()
        cursor.setPosition(lo)
        cursor.setPosition(hi, QtGui.QTextCursor.KeepAnchor)
        widget.setTextCursor(cursor)
        widget.setFocus()
        self._update_preview()

    def _update_preview(self):
        preview = vocab.Flashcard(term=self.term.toPlainText(),
                                  definition=self.definition.toPlainText(),
                                  hint=self.hint.text())
        text = vocab.hint_for(preview)
        self.preview.setText(
            Lf("Shown as: %@", text or L("nothing yet — write a definition first")))
        body = preview.definition or preview.term
        self.rendered.setText(vocab.to_html(body))

    def _save(self):
        if not self.term.toPlainText().strip():
            return
        self.card.term = self.term.toPlainText().strip()
        self.card.definition = self.definition.toPlainText().strip()
        self.card.example = self.example.toPlainText().strip()
        self.card.hint = self.hint.text().strip()
        self.store.decks.update_card(self.card, self.deck_id)
        self.accept()


class MiningDialog(QtWidgets.QDialog):

    def __init__(self, store, deck_id, parent=None):
        super().__init__(parent)
        brand.as_sheet(self, parent)
        self.store = store
        self.deck_id = deck_id
        self.found = []
        self.chosen = set()
        self.added = 0
        self.setWindowTitle(L("Take words from a question set"))
        self.resize(660, 560)
        self.setStyleSheet(f"QDialog{{background:{PAPER};}}")
        lay = QtWidgets.QVBoxLayout(self)
        lay.setContentsMargins(22, 20, 22, 16)
        lay.setSpacing(12)

        title = QtWidgets.QLabel(L("Take words from a question set"))
        title.setStyleSheet(
            f"color:{NAVY}; font-size:17px; font-weight:600; font-family:{SERIF}; border:none;")
        blurb = QtWidgets.QLabel(
            L("The explanations in a College Board export define the words they test, so "
            "the words come with their meanings already written. Anything the reader "
            "could not define is still offered — you can write that one in."))
        blurb.setWordWrap(True)
        leading(blurb)
        blurb.setStyleSheet(f"color:{MUTED}; font-size:11px; border:none;")
        lay.addWidget(title)
        lay.addWidget(blurb)

        row = QtWidgets.QHBoxLayout()
        row.setSpacing(10)
        self.picker = QtWidgets.QComboBox()
        self.picker.setAccessibleName(L("Take words from a question set"))
        for bank in store.banks:
            self.picker.addItem(bank.name, bank.id)
        self.picker.setStyleSheet(f"QComboBox{{font-size:12px; padding:5px;}}")
        find = _primary(L("Find words"))
        find.clicked.connect(self._search)
        row.addWidget(self.picker, 1)
        row.addWidget(find)
        lay.addLayout(row)

        self.list = QtWidgets.QListWidget()
        self.list.setWordWrap(True)
        self.list.setHorizontalScrollBarPolicy(QtCore.Qt.ScrollBarAlwaysOff)
        self.list.setResizeMode(QtWidgets.QListView.Adjust)
        self.list.setStyleSheet(
            f"QListWidget{{background:{CARD}; border:1px solid {HAIRLINE}; font-size:12px;}}"
            f"QListWidget::item{{padding:6px 0px; color:{INK};}}" + SCROLLBAR)
        lay.addWidget(self.list, 1)

        self.hidden_note = QtWidgets.QLabel("")
        self.hidden_note.setWordWrap(True)
        leading(self.hidden_note)
        self.hidden_note.setStyleSheet(f"color:{MUTED}; font-size:11px; border:none;")
        self.hidden_note.hide()
        lay.addWidget(self.hidden_note)

        foot = QtWidgets.QHBoxLayout()
        foot.setSpacing(10)
        self.only_defined = QtWidgets.QCheckBox(L("Only words with a definition"))
        self.only_defined.setChecked(True)
        self.only_defined.setStyleSheet(f"color:{INK}; font-size:11px;")
        self.only_defined.stateChanged.connect(self._fill)
        foot.addWidget(self.only_defined)
        for text, slot in ((L("Select all"), self._all), (L("Select none"), self._none)):
            b = QtWidgets.QPushButton(text)
            b.setFlat(True)
            b.setCursor(QtCore.Qt.PointingHandCursor)
            b.setStyleSheet(
                f"QPushButton{{border:none; background:transparent; color:{MUTED};"
                "font-size:11px;}"
                f"QPushButton:hover{{color:{NAVY};}}")
            b.clicked.connect(slot)
            foot.addWidget(b)
        foot.addStretch(1)
        cancel = _secondary(L("Cancel"))
        cancel.clicked.connect(self.reject)
        self.add_button = _primary(Lf("Add %d", 0))
        self.add_button.setEnabled(False)
        self.add_button.clicked.connect(self._add)
        self.list.itemChanged.connect(lambda _item: self._count_chosen())
        foot.addWidget(cancel)
        foot.addWidget(self.add_button)
        lay.addLayout(foot)

    def _search(self):
        bank = self.store.bank(self.picker.currentData())
        if bank is None:
            return
        QtWidgets.QApplication.setOverrideCursor(QtCore.Qt.WaitCursor)
        try:
            self.found = vocab.mine(bank)
        finally:
            QtWidgets.QApplication.restoreOverrideCursor()
        deck = self.store.decks.deck(self.deck_id)
        only, self.chosen = vocab.opening(
            self.found, lambda c: deck.holds(c.term) if deck else False)
        self.only_defined.blockSignals(True)
        self.only_defined.setChecked(only)
        self.only_defined.blockSignals(False)
        self._fill()

    def _listed(self):
        if self.only_defined.isChecked():
            return [c for c in self.found if c.has_definition]
        return self.found

    def _fill(self):
        deck = self.store.decks.deck(self.deck_id)
        self.list.clear()
        for card in self._listed():
            here = deck.holds(card.term) if deck else False
            meaning = card.definition if card.has_definition \
                else L("No definition found — you can write one")
            text = f"{card.term} — {meaning}"
            if here:
                text += "   (%s)" % L("already here")
            item = QtWidgets.QListWidgetItem(text)
            item.setData(QtCore.Qt.UserRole, card.id)
            item.setFlags(item.flags() | QtCore.Qt.ItemIsUserCheckable)
            if here:
                item.setFlags(item.flags() & ~QtCore.Qt.ItemIsEnabled)
                item.setCheckState(QtCore.Qt.Unchecked)
            else:
                item.setCheckState(QtCore.Qt.Checked if card.id in self.chosen
                                   else QtCore.Qt.Unchecked)
            self.list.addItem(item)
        self._count_chosen()
        hidden = vocab.hidden(self.found, self.only_defined.isChecked())
        self.hidden_note.setText(
            Lp(hidden, "%d word without a definition is hidden",
               "%d words without a definition are hidden") if hidden else "")
        self.hidden_note.setVisible(bool(hidden))

    def _ticked(self):
        return [self.list.item(i) for i in range(self.list.count())
                if self.list.item(i).checkState() == QtCore.Qt.Checked]

    def _count_chosen(self):
        n = len(self._ticked())
        self.add_button.setText(Lf("Add %d", n))
        self.add_button.setEnabled(n > 0)

    def _all(self):
        for i in range(self.list.count()):
            item = self.list.item(i)
            if item.flags() & QtCore.Qt.ItemIsEnabled:
                item.setCheckState(QtCore.Qt.Checked)

    def _none(self):
        for i in range(self.list.count()):
            self.list.item(i).setCheckState(QtCore.Qt.Unchecked)

    def _add(self):
        bank = self.store.bank(self.picker.currentData())
        if bank is None:
            return
        chosen = {item.data(QtCore.Qt.UserRole) for item in self._ticked()}
        cards = [vocab.card_from(c, bank) for c in self.found if c.id in chosen]
        self.added = self.store.decks.add_cards(cards, self.deck_id)
        self.accept()

brand.adopt(__name__)
