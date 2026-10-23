from __future__ import annotations

import contextlib
import os
import re
import sys
import textwrap
import time
from html import escape

import shiboken6
from PySide6 import QtCore, QtGui, QtWidgets

from .core import (Store, AlreadyImported, is_correct, describe_pace, file_size,
                   schedule_defaults,
                   schedule_summary, weekday_initial, WEEKDAY_ORDER,
                   PACE_READING_WRITING, PACE_MATH, profile_initials,
                   profile_display_name)
from . import core
from . import export as exporter
from . import brand
from . import fulltest
from . import library
from .ui import (ACCENT, BORDER, BRAND_FILL, BRASS, BRASS_TEXT, BRASS_SOFT, Blocks, CANVAS,
                 CARD, CHROME, CORRECT, HAIRLINE, INK, MUTED, NAVY, NAVY_DEEP,
                 ON_BRAND, PAPER, PAPER_DEEP, SERIF, NUMERALS, SUBTLE, WRONG,
                 chosen_body_size as ui_chosen_body_size,
                 discard_layout, framed_spin, leading, widest_region)

REVIEW_BODY_PT = 13
from . import i18n
from .i18n import L, Lf, Lp


def _scrollbar_style():
    return f"""
QScrollBar:vertical {{ background: transparent; width: 10px; margin: 0; }}
QScrollBar::handle:vertical {{ background: {BORDER}; border-radius: 5px; min-height: 36px; }}
QScrollBar::handle:vertical:hover {{ background: {BRASS}; }}
QScrollBar::add-line:vertical, QScrollBar::sub-line:vertical {{ height: 0; }}
QScrollBar::add-page:vertical, QScrollBar::sub-page:vertical {{ background: transparent; }}
"""


SCROLLBAR = _scrollbar_style()


def _placeholder_width(text, px=12):
    font = QtGui.QFont()
    font.setPixelSize(px)
    font.setWeight(QtGui.QFont.DemiBold)
    return QtGui.QFontMetrics(font).horizontalAdvance(text) + 10


def rebuild_derived():
    global SCROLLBAR
    SCROLLBAR = _scrollbar_style()



ANIMATIONS_ON = not os.environ.get("SATPREP_NO_ANIMATION")

FILTER_KEYS = ("difficulties", "assessments", "domains", "skills")

FADE_MS = 260
FILL_MS = 700


def _reveal(path):
    import subprocess
    try:
        if sys.platform.startswith("win"):
            subprocess.Popen(["explorer", "/select,", os.path.normpath(path)])
        elif sys.platform == "darwin":
            subprocess.Popen(["open", "-R", path])
        else:
            subprocess.Popen(["xdg-open", os.path.dirname(os.path.abspath(path))])
    except Exception:
        pass


def _rule(brass=False, width=None):
    line = QtWidgets.QFrame()
    line.setFixedHeight(1)
    line.setStyleSheet(f"background:{BRASS if brass else HAIRLINE}; border:none;")
    if width:
        line.setFixedWidth(width)
    return line


def _release(widget):
    if widget is not None and widget.graphicsEffect() is not None:
        widget.setGraphicsEffect(None)


def _after(widget, delay, run):
    if not delay:
        run()
        return
    timer = QtCore.QTimer(widget)
    timer.setSingleShot(True)
    timer.timeout.connect(run)
    timer.start(delay)


def fade_in(widget, duration=FADE_MS, delay=0):
    if not ANIMATIONS_ON:
        return widget
    effect = QtWidgets.QGraphicsOpacityEffect(widget)
    effect.setOpacity(0.0)
    widget.setGraphicsEffect(effect)
    anim = QtCore.QPropertyAnimation(effect, b"opacity", widget)
    anim.setDuration(duration)
    anim.setStartValue(0.0)
    anim.setEndValue(1.0)
    anim.setEasingCurve(QtCore.QEasingCurve.OutCubic)
    anim.finished.connect(lambda w=widget: _release(w))
    _after(widget, delay,
           lambda: anim.start(QtCore.QAbstractAnimation.DeleteWhenStopped))
    return widget


ENTRANCE_MS = 420
ENTRANCE_STAGGER_MS = 50
ENTRANCE_RISE = 12


def entrance(widget, index=0):
    if not ANIMATIONS_ON:
        return widget

    holder = QtWidgets.QWidget()
    holder.setStyleSheet("background:transparent;")
    lay = QtWidgets.QVBoxLayout(holder)
    lay.setContentsMargins(0, ENTRANCE_RISE, 0, 0)
    lay.setSpacing(0)
    lay.addWidget(widget)

    effect = QtWidgets.QGraphicsOpacityEffect(widget)
    effect.setOpacity(0.0)
    widget.setGraphicsEffect(effect)

    fade = QtCore.QPropertyAnimation(effect, b"opacity", holder)
    fade.setDuration(ENTRANCE_MS)
    fade.setStartValue(0.0)
    fade.setEndValue(1.0)
    fade.setEasingCurve(QtCore.QEasingCurve.OutCubic)

    rise = QtCore.QVariantAnimation(holder)
    rise.setDuration(ENTRANCE_MS)
    rise.setStartValue(float(ENTRANCE_RISE))
    rise.setEndValue(0.0)
    rise.setEasingCurve(QtCore.QEasingCurve.OutCubic)
    rise.valueChanged.connect(
        lambda value: lay.setContentsMargins(0, int(round(value)), 0, 0))

    fade.finished.connect(lambda w=widget: _release(w))

    def start():
        fade.start(QtCore.QAbstractAnimation.DeleteWhenStopped)
        rise.start(QtCore.QAbstractAnimation.DeleteWhenStopped)

    _after(holder, index * ENTRANCE_STAGGER_MS, start)
    return holder


def _dimmed(card):
    card.setEnabled(False)
    dim = QtWidgets.QGraphicsOpacityEffect(card)
    dim.setOpacity(0.4)
    card.setGraphicsEffect(dim)
    holder = QtWidgets.QWidget()
    holder.setStyleSheet("background:transparent;")
    lay = QtWidgets.QVBoxLayout(holder)
    lay.setContentsMargins(0, 0, 0, 0)
    lay.addWidget(card)
    return holder


def _lower_first(text):
    return text[:1].lower() + text[1:]



def say_highlights_taken_off(parent, store):
    if not store.highlights_taken_off:
        return
    store.highlights_taken_off = 0
    brand.tell(parent, brand.APP_NAME, L(
        "After the update, some highlights no longer matched their words and were taken off; their notes are kept."))


def _took(seconds):
    s = max(0, round(seconds))
    if s < 60:
        return Lf("%d s", s)
    m = s // 60
    if m < 60:
        return Lf("%d min", m)
    return Lf("%1$d h %2$d min", m // 60, m % 60)

class FlowLayout(QtWidgets.QLayout):

    def __init__(self, parent=None, spacing=7):
        super().__init__(parent)
        self._items = []
        self._space = spacing
        self.setContentsMargins(0, 0, 0, 0)

    def addItem(self, item):
        self._items.append(item)

    def count(self):
        return len(self._items)

    def itemAt(self, i):
        return self._items[i] if 0 <= i < len(self._items) else None

    def takeAt(self, i):
        return self._items.pop(i) if 0 <= i < len(self._items) else None

    def expandingDirections(self):
        return QtCore.Qt.Orientations(0)

    def hasHeightForWidth(self):
        return True

    def heightForWidth(self, width):
        return self._layout(QtCore.QRect(0, 0, width, 0), apply=False)

    def setGeometry(self, rect):
        super().setGeometry(rect)
        self._layout(rect, apply=True)

    def sizeHint(self):
        return self.minimumSize()

    def minimumSize(self):
        size = QtCore.QSize()
        for item in self._items:
            size = size.expandedTo(item.minimumSize())
        return size

    def _layout(self, rect, apply):
        x, y, line_height = rect.x(), rect.y(), 0
        for item in self._items:
            hint = item.sizeHint()
            if x + hint.width() > rect.right() and line_height > 0:
                x = rect.x()
                y += line_height + self._space
                line_height = 0
            if apply:
                item.setGeometry(QtCore.QRect(QtCore.QPoint(x, y), hint))
            x += hint.width() + self._space
            line_height = max(line_height, hint.height())
        return y + line_height - rect.y()


class CountingLabel(QtWidgets.QLabel):

    def __init__(self, value, template, parent=None):
        super().__init__(parent)
        self._template = template
        self.setStyleSheet("border:none; background:transparent;")
        if not ANIMATIONS_ON:
            self.setText(template.format(0 if value is None else int(round(value))))
            return
        self.setText(template.format(0))
        anim = QtCore.QVariantAnimation(self)
        anim.setDuration(FILL_MS)
        anim.setStartValue(0.0)
        anim.setEndValue(float(value))
        anim.setEasingCurve(QtCore.QEasingCurve.OutCubic)
        anim.valueChanged.connect(lambda v: self.setText(template.format(int(round(v)))))
        anim.start(QtCore.QAbstractAnimation.DeleteWhenStopped)


class MiniBar(QtWidgets.QWidget):

    def __init__(self, value, tint, track=None, height=6, parent=None):
        super().__init__(parent)
        self._value = 0.0 if ANIMATIONS_ON else max(0.0, min(1.0, value))
        self._tint = QtGui.QColor(tint)
        self._track = QtGui.QColor(track or SUBTLE)
        self.setFixedHeight(height)
        self.setSizePolicy(QtWidgets.QSizePolicy.Expanding, QtWidgets.QSizePolicy.Fixed)
        if ANIMATIONS_ON:
            anim = QtCore.QVariantAnimation(self)
            anim.setDuration(FILL_MS)
            anim.setStartValue(0.0)
            anim.setEndValue(max(0.0, min(1.0, value)))
            anim.setEasingCurve(QtCore.QEasingCurve.OutCubic)
            anim.valueChanged.connect(self._set_value)
            anim.start(QtCore.QAbstractAnimation.DeleteWhenStopped)

    def _set_value(self, v):
        self._value = float(v)
        self.update()

    def paintEvent(self, event):
        p = QtGui.QPainter(self)
        p.fillRect(self.rect(), self._track)
        w = int(self.width() * self._value)
        if w > 0:
            p.fillRect(QtCore.QRect(0, 0, w, self.height()), self._tint)
        p.end()


class GoalRing(QtWidgets.QWidget):

    def __init__(self, fraction, done, goal, tint, parent=None):
        super().__init__(parent)
        self._fraction = 0.0 if ANIMATIONS_ON else fraction
        self._done, self._goal = done, goal
        self._tint = QtGui.QColor(tint)
        self.setFixedSize(58, 58)
        if ANIMATIONS_ON:
            anim = QtCore.QVariantAnimation(self)
            anim.setDuration(FILL_MS)
            anim.setStartValue(0.0)
            anim.setEndValue(max(0.0, min(1.0, fraction)))
            anim.setEasingCurve(QtCore.QEasingCurve.OutCubic)
            anim.valueChanged.connect(self._set_fraction)
            anim.start(QtCore.QAbstractAnimation.DeleteWhenStopped)

    def _set_fraction(self, v):
        self._fraction = float(v)
        self.update()

    def paintEvent(self, event):
        p = QtGui.QPainter(self)
        p.setRenderHint(QtGui.QPainter.Antialiasing)
        w, h = self.width(), self.height()
        stroke = 5
        box = QtCore.QRectF(stroke / 2.0 + 1, stroke / 2.0 + 1,
                            w - stroke - 2, h - stroke - 2)
        pen = QtGui.QPen(QtGui.QColor(HAIRLINE), stroke)
        pen.setCapStyle(QtCore.Qt.RoundCap)
        p.setPen(pen)
        p.drawArc(box, 0, 360 * 16)
        if self._fraction > 0:
            pen.setColor(self._tint)
            p.setPen(pen)
            p.drawArc(box, 90 * 16, -int(360 * 16 * self._fraction))

        big = QtGui.QFont(p.font())
        big.setPointSizeF(12)
        big.setBold(True)
        small = QtGui.QFont(p.font())
        small.setPointSizeF(7.5)
        small.setBold(False)
        bm, sm = QtGui.QFontMetricsF(big), QtGui.QFontMetricsF(small)
        done, goal = str(self._done), "/%d" % self._goal
        lead = -2.0
        top = (h - (bm.height() + sm.height() + lead)) / 2.0
        p.setFont(big)
        p.setPen(QtGui.QColor(NAVY))
        p.drawText(QtCore.QRectF(0, top, w, bm.height()),
                   QtCore.Qt.AlignHCenter | QtCore.Qt.AlignVCenter, done)
        p.setFont(small)
        p.setPen(QtGui.QColor(MUTED))
        p.drawText(QtCore.QRectF(0, top + bm.height() + lead, w, sm.height()),
                   QtCore.Qt.AlignHCenter | QtCore.Qt.AlignVCenter, goal)
        p.end()


def _sidebar_heading_font():
    font = QtGui.QFont()
    font.setPointSizeF(8.5)
    font.setWeight(QtGui.QFont.DemiBold)
    return font


def _label(text):
    lbl = QtWidgets.QLabel(L(text).upper())
    lbl.setStyleSheet(
        f"color:{MUTED}; font-size:10px; font-weight:600; letter-spacing:1.5px; border:none;"
        "background:transparent;")
    return lbl


def _card(title: str) -> tuple:
    box = QtWidgets.QFrame()
    box.setObjectName("panel")
    box.setStyleSheet(
        f"QFrame#panel{{background:{CARD}; border:1px solid {HAIRLINE}; border-radius:4px;}}")
    lay = QtWidgets.QVBoxLayout(box)
    lay.setContentsMargins(22, 20, 22, 20)
    lay.setSpacing(14)
    lay.addWidget(_label(title))
    lay.addWidget(_rule(brass=True, width=34))
    return box, lay


ROLE_KIND = QtCore.Qt.UserRole + 1
ROLE_ID = QtCore.Qt.UserRole + 2
ROLE_SEEN = QtCore.Qt.UserRole + 3


def breakable(text, longest=24, every=10):
    out = []
    for word in re.split(r"(\s+)", str(text)):
        if len(word) > longest and not word.isspace():
            word = "\u200b".join(word[i:i + every] for i in range(0, len(word), every))
        out.append(word)
    return "".join(out)


class LibraryList(QtWidgets.QListWidget):

    filed = QtCore.Signal(str, object, int)

    def __init__(self, parent=None):
        super().__init__(parent)
        self.setDragDropMode(QtWidgets.QAbstractItemView.InternalMove)
        self.setDefaultDropAction(QtCore.Qt.MoveAction)
        self.setDropIndicatorShown(True)
        self.setHorizontalScrollBarPolicy(QtCore.Qt.ScrollBarAlwaysOff)
        self.setTextElideMode(QtCore.Qt.ElideRight)
        self.setResizeMode(QtWidgets.QListView.Adjust)

    def startDrag(self, actions):
        item = self.currentItem()
        if item is not None and item.data(ROLE_KIND) == "bank":
            super().startDrag(actions)

    def dropEvent(self, event):
        item = self.currentItem()
        if item is None or item.data(ROLE_KIND) != "bank":
            event.ignore()
            return
        row = self.indexAt(event.position().toPoint()).row()
        if row < 0:
            row = self.count() - 1
        shelf_id, position = self._section_at(row)
        event.setDropAction(QtCore.Qt.IgnoreAction)
        event.accept()
        self.filed.emit(item.data(ROLE_ID), shelf_id, position)

    def _section_at(self, row):
        heading = None
        for above in range(row, -1, -1):
            item = self.item(above)
            if item is not None and item.data(ROLE_KIND) in ("shelf", "floor"):
                heading = item
                break
        position = 0
        if heading is not None:
            start = self.row(heading) + 1
            position = max(0, row - start + 1)
        shelf_id = heading.data(ROLE_ID) if heading is not None else None
        return shelf_id, position


class ShelfDelegate(QtWidgets.QStyledItemDelegate):

    NOTE_PAD = QtCore.QMargins(14, 10, 12, 10)

    def _note_rect(self, width):
        return QtCore.QRect(0, 0, max(1, width - self.NOTE_PAD.left() - self.NOTE_PAD.right()),
                            10000)

    def sizeHint(self, option, index):
        hint = super().sizeHint(option, index)
        view = option.widget
        if view is None or not hasattr(view, "viewport"):
            return hint
        width = view.viewport().width()
        if index.data(ROLE_KIND) == "note" and width > 0:
            text = index.data(QtCore.Qt.DisplayRole) or ""
            box = QtGui.QFontMetrics(option.font).boundingRect(
                self._note_rect(width), QtCore.Qt.TextWordWrap, text)
            return QtCore.QSize(width, max(hint.height(), box.height()
                                           + self.NOTE_PAD.top() + self.NOTE_PAD.bottom()))
        hint.setWidth(min(hint.width(), width))
        return hint

    def paint(self, painter, option, index):
        if index.data(ROLE_KIND) == "note":
            opt = QtWidgets.QStyleOptionViewItem(option)
            self.initStyleOption(opt, index)
            text, opt.text = opt.text, ""
            widget = option.widget
            style = widget.style() if widget is not None else QtWidgets.QApplication.style()
            style.drawControl(QtWidgets.QStyle.CE_ItemViewItem, opt, painter, widget)
            painter.save()
            painter.setFont(opt.font)
            ink = index.data(QtCore.Qt.ForegroundRole)
            painter.setPen(ink.color() if ink is not None else opt.palette.text().color())
            painter.drawText(option.rect.marginsRemoved(self.NOTE_PAD),
                             QtCore.Qt.TextWordWrap | QtCore.Qt.AlignVCenter, text)
            painter.restore()
            return
        super().paint(painter, option, index)
        if index.data(ROLE_KIND) != "bank":
            return
        fraction = index.data(ROLE_SEEN) or 0.0
        rect = option.rect
        painter.save()
        painter.setPen(QtCore.Qt.NoPen)
        y = rect.bottom() - 3
        painter.setBrush(QtGui.QColor(HAIRLINE))
        painter.drawRect(QtCore.QRectF(rect.left() + 12, y,
                                       rect.width() - 24, 2))
        if fraction > 0:
            painter.setBrush(QtGui.QColor(BRASS))
            full = rect.width() - 24
            painter.drawRect(QtCore.QRectF(
                rect.left() + 12, y, max(3.0, full * min(1.0, fraction)), 2))
        painter.restore()


ROLE_STARS = QtCore.Qt.UserRole + 9


class DeckDelegate(QtWidgets.QStyledItemDelegate):

    STAR = 9

    def paint(self, painter, option, index):
        super().paint(painter, option, index)
        if not index.data(ROLE_STARS):
            return
        rect = option.rect
        size = self.STAR
        top = rect.top() + max(0, (rect.height() // 2 - size) // 2 + 6)
        box = QtCore.QRect(rect.right() - size - 12, top, size, size)
        painter.save()
        brand.icon("star_on", size, BRASS).paint(painter, box)
        painter.restore()


def export_student(store, parent):
    from . import portable
    name = "%s.%s" % (store.profile.get("name", "student"),
                      portable.FILE_EXTENSION)
    path, _ = QtWidgets.QFileDialog.getSaveFileName(
        parent, L("Export student"), brand.dialog_path(name))
    if not path:
        return False
    brand.remember_folder(path)
    size = portable.write_profile(store, path)
    box = brand.alert(
        parent, L("Exported"),
        Lf("Saved %1$@ · %2$d KB", os.path.basename(path),
           max(1, size // 1024)))
    box.setInformativeText(
        L("Save it where you can send it from — a mail draft, a chat to "
          "yourself, or a USB stick."))
    show = box.addButton(L("Show me the file"), QtWidgets.QMessageBox.ActionRole)
    box.addButton(QtWidgets.QMessageBox.Ok)
    box.exec()
    if box.clickedButton() is show:
        _reveal(path)
    return True


class _Clickable(QtWidgets.QWidget):

    clicked = QtCore.Signal()

    def __init__(self, parent=None):
        super().__init__(parent)
        self.setAttribute(QtCore.Qt.WA_StyledBackground, True)

        self.setFocusPolicy(QtCore.Qt.StrongFocus)
        self._ring = False

    def mousePressEvent(self, event):
        if self.isEnabled() and event.button() == QtCore.Qt.LeftButton:
            self.clicked.emit()
        else:
            super().mousePressEvent(event)

    def keyPressEvent(self, event):
        if self.isEnabled() and event.key() in (QtCore.Qt.Key_Space, QtCore.Qt.Key_Return,
                                                 QtCore.Qt.Key_Enter):
            self.clicked.emit()
        else:
            super().keyPressEvent(event)

    def focusInEvent(self, event):
        if event.reason() not in (QtCore.Qt.ActiveWindowFocusReason, QtCore.Qt.PopupFocusReason):
            self._ring = event.reason() != QtCore.Qt.MouseFocusReason
        super().focusInEvent(event)
        self.update()

    def focusOutEvent(self, event):
        super().focusOutEvent(event)
        self.update()

    def paintEvent(self, event):
        opt = QtWidgets.QStyleOption()
        opt.initFrom(self)
        painter = QtGui.QPainter(self)
        self.style().drawPrimitive(QtWidgets.QStyle.PE_Widget, opt, painter, self)
        if self.hasFocus() and self._ring:
            pen = QtGui.QPen(QtGui.QColor(BRASS))
            pen.setWidth(1)
            pen.setStyle(QtCore.Qt.DashLine)
            painter.setPen(pen)
            painter.drawRect(self.rect().adjusted(0, 0, -1, -1))
        painter.end()

    def showEvent(self, event):
        super().showEvent(event)
        if not self.accessibleName():
            words = [QtGui.QTextDocumentFragment.fromHtml(l.text()).toPlainText().strip()
                     if "<" in l.text() and ">" in l.text() else l.text().strip()
                     for l in self.findChildren(QtWidgets.QLabel) if l.text().strip()]
            words = [w.replace(chr(0x2029), ", ").replace(chr(10), ", ") for w in words if w]
            if words:
                self.setAccessibleName(", ".join(words[:2]))


class _FocusLineEdit(QtWidgets.QLineEdit):

    focusChanged = QtCore.Signal(bool)

    def focusInEvent(self, event):
        super().focusInEvent(event)
        self.focusChanged.emit(True)

    def focusOutEvent(self, event):
        super().focusOutEvent(event)
        self.focusChanged.emit(False)


class _DeckHandle(QtWidgets.QSplitterHandle):

    def __init__(self, orientation, parent):
        super().__init__(orientation, parent)
        self.setCursor(QtCore.Qt.SizeVerCursor)
        self._hover = False

    def enterEvent(self, event):
        self._hover = True
        self._show_room()
        self.update()

    def mouseMoveEvent(self, event):
        super().mouseMoveEvent(event)
        self._show_room()

    def _show_room(self):
        splitter = self.splitter()
        if not isinstance(splitter, _DeckSplitter):
            return
        self.setCursor(QtCore.Qt.SizeVerCursor if splitter.has_room()
                       else QtCore.Qt.ArrowCursor)

    def leaveEvent(self, event):
        self._hover = False
        self.update()

    def paintEvent(self, event):
        p = QtGui.QPainter(self)
        y = self.height() // 2
        p.fillRect(0, y, self.width(), 1, QtGui.QColor(HAIRLINE))
        if self._hover:
            grab = QtGui.QColor(BORDER)
            x = (self.width() - 34) // 2
            p.fillRect(x, y - 1, 34, 3, grab)
        p.end()

    def mouseDoubleClickEvent(self, event):
        self.splitter().fit_decks()


class _DeckSplitter(QtWidgets.QSplitter):

    MIN_LIBRARY = 72
    MIN_DECKS = 86

    heightChanged = QtCore.Signal(object)

    def __init__(self, parent=None):
        super().__init__(QtCore.Qt.Vertical, parent)
        self.setChildrenCollapsible(False)
        self.setHandleWidth(14)
        self._target = None
        self._fit_fn = lambda: 120
        self._applying = False
        self.splitterMoved.connect(self._on_moved)

    def createHandle(self):
        return _DeckHandle(self.orientation(), self)

    def sizeHint(self):
        hint = super().sizeHint()
        return QtCore.QSize(hint.width(), self.minimumSizeHint().height())

    def set_fit_fn(self, fn):
        self._fit_fn = fn

    def set_target(self, value):
        self._target = None if value is None else float(value)
        self.apply_target()

    def fit_decks(self):
        self._target = None
        self.apply_target()
        self.heightChanged.emit(None)

    def span(self):
        return max(self.height() - self.handleWidth(), 0)

    def settled(self):
        span = self.span()
        want = self._target if self._target is not None else span - self._fit_fn()
        low = max(min(self.MIN_LIBRARY, span), 0)
        high = max(span - self.MIN_DECKS, low)
        return min(max(float(want), low), high)

    def has_room(self):
        above = self.settled()
        return (above - self.MIN_LIBRARY > 0.5
                or self.span() - above - self.MIN_DECKS > 0.5)

    def apply_target(self):
        if self.count() < 2 or self.height() <= 0:
            return
        above = int(self.settled())
        self._applying = True
        self.setSizes([above, self.span() - above])
        self._applying = False

    def resizeEvent(self, event):
        super().resizeEvent(event)
        self.apply_target()

    def _on_moved(self, *_):
        if self._applying:
            return
        sizes = self.sizes()
        if len(sizes) == 2:
            self._target = float(sizes[0])
            self.heightChanged.emit(self._target)


class Switch(QtWidgets.QAbstractButton):

    TRACK = QtCore.QSize(38, 22)

    def __init__(self, checked=False, parent=None):
        super().__init__(parent)
        self.setCheckable(True)
        self.setChecked(bool(checked))
        self.setCursor(QtCore.Qt.PointingHandCursor)
        self.setFixedSize(self.TRACK)
        self.setStyleSheet("background:transparent; border:none;")
        self._travel = 1.0 if checked else 0.0
        self._slide = None
        self.toggled.connect(self._run)

    def sizeHint(self):
        return self.TRACK

    def _get_travel(self):
        return self._travel

    def _set_travel(self, value):
        self._travel = float(value)
        self.update()

    travel = QtCore.Property(float, _get_travel, _set_travel)

    def _run(self, on):
        target = 1.0 if on else 0.0
        if not ANIMATIONS_ON:
            self._set_travel(target)
            return
        self._slide = QtCore.QPropertyAnimation(self, b"travel", self)
        self._slide.setDuration(130)
        self._slide.setEasingCurve(QtCore.QEasingCurve.OutCubic)
        self._slide.setStartValue(self._travel)
        self._slide.setEndValue(target)
        self._slide.start()

    def paintEvent(self, event):
        painter = QtGui.QPainter(self)
        painter.setRenderHint(QtGui.QPainter.Antialiasing)
        rect = QtCore.QRectF(self.rect()).adjusted(0.5, 0.5, -0.5, -0.5)
        radius = rect.height() / 2

        on = QtGui.QColor(BRASS)
        off = QtGui.QColor(SUBTLE)
        track = QtGui.QColor(
            int(off.red() + (on.red() - off.red()) * self._travel),
            int(off.green() + (on.green() - off.green()) * self._travel),
            int(off.blue() + (on.blue() - off.blue()) * self._travel))
        painter.setPen(QtGui.QPen(QtGui.QColor(HAIRLINE), 1))
        painter.setBrush(track)
        painter.drawRoundedRect(rect, radius, radius)

        knob = rect.height() - 6
        left = rect.left() + 3 + (rect.width() - knob - 6) * self._travel
        painter.setPen(QtCore.Qt.NoPen)
        painter.setBrush(QtGui.QColor(CARD if self._travel > 0.5 else MUTED))
        painter.drawEllipse(QtCore.QRectF(left, rect.top() + 3, knob, knob))
        painter.end()


def _switch_card(title: str, blurb: str, switch, badge: str = "") -> tuple:
    box = QtWidgets.QFrame()
    box.setObjectName("panel")
    box.setStyleSheet(
        f"QFrame#panel{{background:{CARD}; border:1px solid {HAIRLINE};"
        "border-radius:4px;}")
    outer = QtWidgets.QVBoxLayout(box)
    outer.setContentsMargins(22, 18, 22, 20)
    outer.setSpacing(12)

    head = QtWidgets.QHBoxLayout()
    head.setSpacing(12)
    words = QtWidgets.QVBoxLayout()
    words.setSpacing(4)
    titles = QtWidgets.QHBoxLayout()
    titles.setSpacing(8)
    name = QtWidgets.QLabel(title)
    name.setStyleSheet(
        f"color:{NAVY}; font-size:15px; font-weight:600; font-family:{SERIF};"
        "border:none; background:transparent;")
    titles.addWidget(name)
    if badge:
        mark = QtWidgets.QLabel(badge)
        mark.setStyleSheet(
            f"color:{MUTED}; background:{SUBTLE}; border-radius:2px;"
            "padding:2px 7px; font-size:9px; font-weight:600;"
            "letter-spacing:0.6px;")
        titles.addWidget(mark)
    titles.addStretch(1)
    words.addLayout(titles)
    note = QtWidgets.QLabel(blurb)
    note.setWordWrap(True)
    leading(note)
    note.setStyleSheet(f"color:{MUTED}; font-size:11px; border:none;"
                       "background:transparent;")
    words.addWidget(note)
    head.addLayout(words, 1)
    head.addWidget(switch, 0, QtCore.Qt.AlignTop)
    outer.addLayout(head)
    return box, outer


def _spoken(w):
    iface = QtGui.QAccessible.queryAccessibleInterface(w)
    return (iface.text(QtGui.QAccessible.Name) if iface else "") or ""


def park_focus(going, near, coming=None):
    focused = QtWidgets.QApplication.focusWidget()
    if focused is None or going is None or not going.isAncestorOf(focused):
        return
    kind, name = type(focused).__name__, _spoken(focused)
    keeper = near
    while keeper is not None and not isinstance(keeper, QtWidgets.QAbstractScrollArea):
        keeper = keeper.parentWidget()
    (keeper or near.window()).setFocus(QtCore.Qt.OtherFocusReason)
    if coming is None or not name:
        return

    def refocus():
        if not shiboken6.isValid(coming):
            return
        for w in [coming] + coming.findChildren(QtWidgets.QWidget):
            if (type(w).__name__ == kind and w.isVisible()
                    and w.focusPolicy() != QtCore.Qt.NoFocus and _spoken(w) == name):
                w.setFocus(QtCore.Qt.TabFocusReason)
                return

    QtCore.QTimer.singleShot(0, refocus)


class _Slot(QtWidgets.QWidget):

    def __init__(self, build, parent=None):
        super().__init__(parent)
        self.setStyleSheet("background:transparent;")
        lay = QtWidgets.QVBoxLayout(self)
        lay.setContentsMargins(0, 0, 0, 0)
        lay.setSpacing(0)
        self._build = build
        self._inner = None
        self.refill()

    def refill(self, **kwargs):
        lay = self.layout()
        going = self._inner
        self._inner = self._build(**kwargs)
        lay.addWidget(self._inner)
        if going is not None:
            park_focus(going, self, coming=self._inner)
            lay.removeWidget(going)
            going.setParent(None)
            going.deleteLater()


class RadioGroup(QtWidgets.QWidget):
    changed = QtCore.Signal(str)

    def __init__(self, label, options, current, parent=None, counts=None):
        super().__init__(parent)
        self.setStyleSheet("background:transparent;")
        lay = QtWidgets.QVBoxLayout(self)
        lay.setContentsMargins(0, 0, 0, 0)
        lay.setSpacing(6)
        lay.addWidget(_label(label))
        self._buttons = {}
        self._parts = {}
        for value, title, detail in options:
            chosen = value == current
            btn = _Clickable()
            btn.setCursor(QtCore.Qt.PointingHandCursor)
            btn.setObjectName("choiceRow")
            btn.setStyleSheet(
                "QWidget#choiceRow{border:none; border-left:2px solid "
                + (BRASS if chosen else "transparent") + ";"
                + (f"background:{BRASS_SOFT};" if chosen else "background:transparent;")
                + "}"
                + (f"QWidget#choiceRow:hover{{background:{PAPER_DEEP};}}"
                   if not chosen else ""))

            row = QtWidgets.QHBoxLayout(btn)
            row.setContentsMargins(12, 9, 12, 9)
            row.setSpacing(12)
            words = QtWidgets.QVBoxLayout()
            words.setSpacing(2)

            name = QtWidgets.QLabel(title)
            name.setStyleSheet(
                f"color:{INK}; font-size:12px; border:none; background:transparent;"
                + ("font-weight:600;" if chosen else ""))
            words.addWidget(name)

            note = QtWidgets.QLabel(detail)
            note.setWordWrap(True)
            leading(note)
            note.setStyleSheet(
                f"color:{MUTED}; font-size:10.5px; border:none;"
                "background:transparent;")
            words.addWidget(note)
            row.addLayout(words, 1)

            tally = None
            if counts is not None and value in counts:
                n = counts[value]
                tally = QtWidgets.QLabel(L("none") if n == 0 else str(n))
                tally.setAlignment(QtCore.Qt.AlignRight | QtCore.Qt.AlignTop)
                tally.setStyleSheet(
                    f"color:{BRASS_TEXT if chosen else MUTED}; font-size:11px;"
                    "border:none; background:transparent;"
                    + ("font-weight:600;" if chosen else ""))
                row.addWidget(tally, 0, QtCore.Qt.AlignTop)

            btn.clicked.connect(lambda v=value: self.changed.emit(v))
            lay.addWidget(btn)
            self._buttons[value] = btn
            self._parts[value] = (name, tally)
        self._current = current

    def set_current(self, value):
        if value == self._current:
            return
        for key, btn in self._buttons.items():
            chosen = key == value
            btn.setStyleSheet(
                "QWidget#choiceRow{border:none; border-left:2px solid "
                + (BRASS if chosen else "transparent") + ";"
                + (f"background:{BRASS_SOFT};" if chosen else "background:transparent;")
                + "}"
                + (f"QWidget#choiceRow:hover{{background:{PAPER_DEEP};}}"
                   if not chosen else ""))
            name, tally = self._parts[key]
            name.setStyleSheet(
                f"color:{INK}; font-size:12px; border:none; background:transparent;"
                + ("font-weight:600;" if chosen else ""))
            if tally is not None:
                tally.setStyleSheet(
                    f"color:{BRASS_TEXT if chosen else MUTED}; font-size:11px;"
                    "border:none; background:transparent;"
                    + ("font-weight:600;" if chosen else ""))
        self._current = value

    def set_counts(self, counts):
        for key, (_name, tally) in self._parts.items():
            if tally is None or key not in counts:
                continue
            n = counts[key]
            tally.setText(L("none") if n == 0 else str(n))


def profile_colour(index, grounds=None):
    colours = HomeScreen.PROFILE_ACCENTS
    index = int(index) % len(colours)
    return brand.legible_on(colours[index], grounds or (PAPER, CARD), 9.0 if index == 0 else 3.0)


class HomeScreen(QtWidgets.QWidget):

    focus_requested = QtCore.Signal(str, str)
    start_requested = QtCore.Signal(dict)

    @property
    def config(self):
        return self.store.practice_config

    @config.setter
    def config(self, value):
        self.store.practice_config = value

    @property
    def selected_deck_id(self):
        return self.store.selected_deck_id

    @selected_deck_id.setter
    def selected_deck_id(self, value):
        self.store.selected_deck_id = value
    sitting_opened = QtCore.Signal(object)
    resume_requested = QtCore.Signal(object)
    learn_requested = QtCore.Signal()
    article_requested = QtCore.Signal(str)

    def __init__(self, store: Store, parent=None):
        super().__init__(parent)
        self.store = store
        defaults = {
            "bank_id": store.banks[0].id if store.banks else "",
            "subjects": ["reading_writing", "math"],
            "selection": "new_first", "mix": "pdf_order", "grading": "at_end",
            "count": 20, "timed": bool(store.settings.get("practiceTimed") is True),
            "minutes": self._remembered_minutes(store),
            "difficulties": [], "assessments": [], "domains": [], "skills": [],
        }
        kept = getattr(store, "practice_config", None)
        if kept is None or (kept.get("bank_id") and store.bank(kept["bank_id"]) is None):
            kept = defaults
        for key, value in defaults.items():
            kept.setdefault(key, value)
        if kept.get("partnerProfileID") and store.partner(kept["partnerProfileID"]) is None:
            kept["partnerProfileID"] = ""
        self.config = kept
        self.narrowing = False
        self._selection_group = None
        self._order_group = None
        self._grading_group = None
        self._count_slot = None
        self._timer_slot = None
        self._start_slot = None
        self._narrow_slot = None
        self.deck_screen = None
        self.setAcceptDrops(True)
        self.setObjectName("homeScreen")
        self.setStyleSheet(f"QWidget#homeScreen{{background:{PAPER};}}")

        root = QtWidgets.QHBoxLayout(self)
        root.setContentsMargins(0, 0, 0, 0)
        root.setSpacing(0)

        root.addWidget(self._sidebar())

        right = QtWidgets.QWidget()
        right.setObjectName("detailSide")
        right.setStyleSheet(f"QWidget#detailSide{{background:{PAPER};}}")
        rl = QtWidgets.QVBoxLayout(right)
        rl.setContentsMargins(0, 0, 0, 0)
        rl.setSpacing(0)
        self.tab = "practise"
        self.tab_bar = self._tab_bar()
        rl.addWidget(self.tab_bar)
        self.tab_rule = _rule()
        rl.addWidget(self.tab_rule)
        self.pages = QtWidgets.QStackedWidget()
        rl.addWidget(self.pages, 1)

        self.detail_area = QtWidgets.QScrollArea()
        self.detail_area.setWidgetResizable(True)
        self.detail_area.setFrameShape(QtWidgets.QFrame.NoFrame)
        self.detail_area.setHorizontalScrollBarPolicy(QtCore.Qt.ScrollBarAlwaysOff)
        self.detail_area.setStyleSheet(SCROLLBAR)
        self.detail_area.setAccessibleName(L("Practice"))
        detail_box = QtWidgets.QWidget()
        detail_box.setStyleSheet(f"background:{PAPER};")
        box_lay = QtWidgets.QVBoxLayout(detail_box)
        box_lay.setContentsMargins(0, 0, 0, 0)
        box_lay.setSpacing(0)
        self.start_pin = QtWidgets.QWidget()
        self.start_pin.setStyleSheet("background:transparent;")
        self._start_pin_lay = QtWidgets.QVBoxLayout(self.start_pin)
        self._start_pin_lay.setContentsMargins(32, 12, 32, 12)
        box_lay.addWidget(self.start_pin)
        self.start_pin_rule = _rule()
        box_lay.addWidget(self.start_pin_rule)
        box_lay.addWidget(self.detail_area, 1)
        brand.pin_over_column(self._start_pin_lay, self.detail_area)
        self.pages.addWidget(detail_box)
        self.stats_holder = QtWidgets.QWidget()
        QtWidgets.QVBoxLayout(self.stats_holder).setContentsMargins(0, 0, 0, 0)
        self.pages.addWidget(self.stats_holder)
        self.deck_holder = QtWidgets.QWidget()
        QtWidgets.QVBoxLayout(self.deck_holder).setContentsMargins(0, 0, 0, 0)
        self.pages.addWidget(self.deck_holder)
        self.history_holder = QtWidgets.QWidget()
        QtWidgets.QVBoxLayout(self.history_holder).setContentsMargins(0, 0, 0, 0)
        self.pages.addWidget(self.history_holder)
        root.addWidget(right, 1)

        self.refresh()
        if self.selected_deck_id and hasattr(self, "deck_list")                 and self.store.decks.deck(self.selected_deck_id) is not None:
            self.bank_list.clearSelection()
            self._show_deck()
        elif self.selected_deck_id:
            self.selected_deck_id = None

    def _tab_bar(self):
        bar = QtWidgets.QWidget()
        bar.setObjectName("tabBar")
        bar.setStyleSheet(f"QWidget#tabBar{{background:{CARD};}}")
        lay = QtWidgets.QHBoxLayout(bar)
        lay.setContentsMargins(16, 0, 16, 0)
        lay.setSpacing(0)
        self._tab_buttons = {}
        for key, title in (("practise", L("Practice")), ("statistics", L("Statistics")),
                           ("history", L("History"))):
            b = QtWidgets.QPushButton(L(title))
            b.setCursor(QtCore.Qt.PointingHandCursor)
            b.setFlat(True)
            b.clicked.connect(lambda _=False, k=key: self._select_tab(k))
            lay.addWidget(b)
            self._tab_buttons[key] = b
        lay.addStretch(1)
        self._style_tabs()
        return bar

    def _style_tabs(self):
        for key, b in self._tab_buttons.items():
            on = key == self.tab
            b.setStyleSheet(
                f"QPushButton{{border:none; background:transparent; padding:14px 18px 12px;"
                f"font-size:12px; color:{NAVY if on else MUTED};"
                f"font-weight:{'600' if on else '400'};"
                f"border-bottom:2px solid {BRASS if on else 'transparent'};}}")

    def _select_tab(self, key):
        self.tab = key
        self.detail_area.setAccessibleName(
            {"statistics": L("Statistics"), "history": L("History")}.get(key, L("Practice")))
        self._style_tabs()
        if key == "statistics":
            self._build_statistics()
        if key == "history":
            self._build_history()
        self.pages.setCurrentIndex(self._TAB_PAGES[key])

    _TAB_PAGES = {"practise": 0, "statistics": 1, "history": 3}

    def _build_history(self):
        holder = self.history_holder.layout()
        while holder.count():
            item = holder.takeAt(0)
            if item.widget():
                item.widget().deleteLater()
        bank = self.store.bank(self.config.get("bank_id"))
        rows = self.store.sittings(bank.id) if bank else []
        if not rows:
            empty = QtWidgets.QLabel(L("No finished practice in this set yet. "
                                       "Each test you finish is kept here, with every answer."))
            empty.setWordWrap(True)
            leading(empty)
            empty.setAlignment(QtCore.Qt.AlignCenter)
            empty.setStyleSheet(f"color:{MUTED}; font-size:14px; padding:40px;")
            holder.addWidget(empty)
            return
        area = QtWidgets.QScrollArea()
        area.setWidgetResizable(True)
        area.setFrameShape(QtWidgets.QFrame.NoFrame)
        area.setStyleSheet(f"QScrollArea{{background:transparent;}}" + SCROLLBAR)
        inner = QtWidgets.QWidget()
        inner.setObjectName("historyList")
        inner.setStyleSheet("QWidget#historyList{background:transparent;}")
        lay = QtWidgets.QVBoxLayout(inner)
        lay.setContentsMargins(26, 20, 26, 20)
        lay.setSpacing(8)
        for row in rows:
            lay.addWidget(self._history_row(row))
        lay.addStretch(1)
        area.setWidget(inner)
        holder.addWidget(area)

    def _history_row(self, row):
        when = i18n.stamp(row["finished_at"])
        took = _took(row["finished_at"] - row["started_at"])
        percent = _percent(row["correct"], row["total"])
        b = QtWidgets.QPushButton()
        b.setCursor(QtCore.Qt.PointingHandCursor)
        score = f"{row['correct']}/{row['total']}"
        b.setAccessibleName(", ".join((row["title"], when, score)) + " " + L("correct"))
        b.setStyleSheet(
            f"QPushButton{{background:{CARD}; border:1px solid {HAIRLINE}; border-radius:10px;"
            "text-align:left; padding:0;}"
            f"QPushButton:hover{{border-color:{BRASS};}}")
        inner = QtWidgets.QHBoxLayout(b)
        inner.setContentsMargins(16, 12, 16, 12)
        left = QtWidgets.QLabel(
            f"<div style='font-size:14px; font-weight:600; color:{INK}'>{row['title']}</div>"
            f"<div style='font-size:12px; color:{MUTED}'>{when} · {took}</div>")
        left.setAttribute(QtCore.Qt.WA_TransparentForMouseEvents)
        right = QtWidgets.QLabel(
            f"<div style='font-size:20px; font-weight:600; color:{CORRECT};"
            f"font-family:{NUMERALS}' align='right'>{row['correct']}/{row['total']}</div>"
            f"<div style='font-size:9px; color:{MUTED}; letter-spacing:1px' align='right'>"
            f"{percent} {L('correct').upper()}</div>")
        right.setAttribute(QtCore.Qt.WA_TransparentForMouseEvents)
        inner.addWidget(left, 1)
        inner.addWidget(right)
        b.setMinimumHeight(max(left.sizeHint().height(), right.sizeHint().height()) + 24)
        b.clicked.connect(lambda _=False, p=row["path"]: self._open_sitting(p))
        return b

    def _open_sitting(self, path):
        s = self.store.load_sitting(path)
        if s is None:
            brand.warn(self, L("History"), L("That practice could not be opened."))
            return
        self.sitting_opened.emit(s)

    def _build_statistics(self):
        from .stats import StatisticsScreen
        holder = self.stats_holder.layout()
        while holder.count():
            item = holder.takeAt(0)
            if item.widget():
                item.widget().deleteLater()
        bank = self.store.bank(self.config["bank_id"])
        if not bank:
            return
        screen = StatisticsScreen(self.store, bank)
        screen.practise_skill.connect(self._practise_skill)
        screen.practise_section.connect(self._practise_section)
        screen.article_requested.connect(self.article_requested.emit)
        screen.set_chosen.connect(self._choose_set)
        holder.addWidget(screen)

    def _choose_set(self, bank_id):
        self.config["bank_id"] = bank_id
        self.selected_deck_id = None
        self.refresh()
        self._build_statistics()

    def _practise_skill(self, skill, count):
        cfg = dict(self.config)
        cfg["selection"] = "all"
        cfg["difficulties"] = []
        cfg["domains"] = []
        cfg["skills"] = [skill]
        cfg["subjects"] = ["math", "reading_writing"]
        cfg["count"] = count
        cfg["mix"] = "mixed"
        core.clear_section_split(cfg)
        self.start_requested.emit(cfg)

    def _practise_section(self, subject, count):
        cfg = dict(self.config)
        cfg["selection"] = "all"
        for key in FILTER_KEYS:
            cfg[key] = []
        cfg["subjects"] = [subject]
        cfg["count"] = count
        cfg["mix"] = "mixed"
        core.clear_section_split(cfg)
        self.start_requested.emit(cfg)

    def _sidebar(self):
        panel = QtWidgets.QWidget()
        panel.setObjectName("sidebar")
        panel.setStyleSheet(
            f"QWidget#sidebar{{background:{PAPER_DEEP}; border-right:1px solid {HAIRLINE};}}")
        lay = QtWidgets.QVBoxLayout(panel)
        lay.setContentsMargins(18, 20, 18, 16)
        lay.setSpacing(0)

        head = QtWidgets.QHBoxLayout()
        head.setContentsMargins(0, 0, 0, 0)
        head.setSpacing(12)
        self.masthead_seal = brand.Seal(54, NAVY)
        head.addWidget(self.masthead_seal, 0, QtCore.Qt.AlignVCenter)
        names = QtWidgets.QVBoxLayout()
        names.setContentsMargins(0, 0, 0, 0)
        names.setSpacing(4)
        title_row = QtWidgets.QHBoxLayout()
        title_row.setContentsMargins(0, 0, 0, 0)
        title_row.setSpacing(7)
        title = QtWidgets.QLabel(brand.INITIALS)
        title.setStyleSheet(
            f"color:{NAVY}; font-size:19px; font-weight:600; font-family:{SERIF};"
            "letter-spacing:1px; border:none;")
        title_row.addWidget(title)
        if getattr(brand, "STAGE", ""):
            badge = QtWidgets.QLabel(brand.STAGE)
            badge.setToolTip(L("This is a test version. Your work is kept as usual."))
            badge.setStyleSheet(
                f"color:{BRASS_TEXT}; font-size:9px; font-weight:600; letter-spacing:1px;"
                f"border:1px solid {BRASS}; border-radius:3px; padding:1px 5px;")
            title_row.addWidget(badge, 0, QtCore.Qt.AlignVCenter)
        title_row.addStretch(1)
        sub = QtWidgets.QLabel(brand.SLOGAN)
        sub.setWordWrap(True)
        leading(sub)
        sub.setStyleSheet(
            f"color:{MUTED}; font-size:10px; font-style:italic; border:none;")
        names.addLayout(title_row)
        names.addWidget(sub)
        head.addLayout(names, 1)

        masthead = _Clickable()
        masthead.setCursor(QtCore.Qt.PointingHandCursor)
        masthead.setToolTip(L("What this app does"))
        masthead.setLayout(head)
        masthead.clicked.connect(self._show_about)
        lay.addWidget(masthead)
        lay.addSpacing(16)

        welcome = self.store.welcome_back()
        if welcome:
            lay.addWidget(self._welcome_back(welcome))
            lay.addSpacing(14)

        if getattr(self.store, "damaged", None):
            lay.addWidget(self._damaged_notice())
            lay.addSpacing(14)

        self.bank_list = LibraryList()
        self.bank_list.setAccessibleName(L("Library"))
        self.bank_list.setStyleSheet(
            "QListWidget{background:transparent; border:none; font-size:12px;"
            "outline:none;}"
            f"QListWidget::item{{padding:10px 12px; color:{INK};"
            "border-left:2px solid transparent;}"
            f"QListWidget::item:hover{{background:{SUBTLE};}}"
            f"QListWidget::item:selected{{background:{CARD}; color:{INK};"
            f"border-left:2px solid {BRASS};}}"
            + SCROLLBAR)
        self.bank_list.setItemDelegate(ShelfDelegate(self.bank_list))
        self.bank_list.currentRowChanged.connect(self._bank_changed)
        self.bank_list.itemClicked.connect(self._row_clicked)
        self.bank_list.itemDoubleClicked.connect(self._row_double_clicked)
        self.bank_list.filed.connect(self._file_bank)
        self.bank_list.setContextMenuPolicy(QtCore.Qt.CustomContextMenu)
        self.bank_list.customContextMenuRequested.connect(self._bank_menu)

        sets_on = self.store.settings.get("showQuestionSets", True)
        cards_on = self.store.settings.get("showFlashcards", True)

        if sets_on:
            header = QtWidgets.QHBoxLayout()
            header.setContentsMargins(0, 0, 0, 0)
            header.setSpacing(6)
            header.addWidget(_label(L("Library")))
            header.addStretch(1)
            header.addWidget(self._shelf_tool("new_shelf", L("New shelf"),
                                              self._add_shelf))
            header.addWidget(self._shelf_tool(
                "sort",
                Lf("How the sets are ordered — currently %@",
                   _lower_first(library.order_title(self.store.library_layout().order))),
                self._pick_order))
            lay.addLayout(header)
            lay.addSpacing(6)

        if sets_on and cards_on:
            self.deck_splitter = _DeckSplitter()
            self.deck_splitter.addWidget(self.bank_list)
            self.deck_splitter.addWidget(self._deck_section())
            self.deck_splitter.setStretchFactor(0, 1)
            self.deck_splitter.setStretchFactor(1, 0)
            self.deck_splitter.set_fit_fn(self._deck_fit_height)
            self.deck_splitter.heightChanged.connect(self._deck_height_changed)
            self._deck_persist = QtCore.QTimer(self)
            self._deck_persist.setSingleShot(True)
            self._deck_persist.setInterval(350)
            self._deck_persist.timeout.connect(self._persist_deck_height)
            lay.addWidget(self.deck_splitter, 1)
        elif sets_on:
            lay.addWidget(self.bank_list, 1)
        elif cards_on:
            lay.addWidget(self._deck_section(), 1)
        else:
            lay.addWidget(self._nothing_chosen(), 1)

        if self.store.settings.get("showLearnInSidebar", True):
            lay.addSpacing(3)
            lay.addWidget(_rule())
            lay.addSpacing(3)
            lay.addWidget(self._learn_row())
            lay.addSpacing(2)

        if sets_on and (self.store.settings.get("showImportButton", True)
                        or not self.store.banks):
            lay.addSpacing(6)
            lay.addWidget(_rule())
            lay.addSpacing(9)

            add = QtWidgets.QPushButton(L("Import question bank PDF…"))
            add.setCursor(QtCore.Qt.PointingHandCursor)
            add.setStyleSheet(
                f"QPushButton{{background:{NAVY}; color:{CARD}; border-radius:3px;"
                "padding:10px; font-size:12px; font-weight:600;}"
                f"QPushButton:hover{{background:{NAVY_DEEP};}}")
            add.clicked.connect(self._choose_files)
            lay.addWidget(add)
            lay.addSpacing(7)
            hint = QtWidgets.QLabel(L("or drag PDFs into this window"))
            hint.setAlignment(QtCore.Qt.AlignCenter)
            hint.setStyleSheet(f"color:{MUTED}; font-size:10px; border:none;")
            lay.addWidget(hint)

        lay.addSpacing(12)
        if len(self.store.profiles.profiles) > 1:
            lay.addWidget(_rule())
            lay.addSpacing(8)
            lay.addWidget(self._profile_bar())
            lay.addSpacing(8)
        lay.addWidget(_rule())
        lay.addSpacing(10)
        lay.addWidget(self._colophon())

        frame = QtWidgets.QScrollArea()
        frame.setObjectName("sidebarFrame")
        frame.setFocusPolicy(QtCore.Qt.NoFocus)
        frame.setWidget(panel)
        frame.setWidgetResizable(True)
        frame.setFrameShape(QtWidgets.QFrame.NoFrame)
        frame.setHorizontalScrollBarPolicy(QtCore.Qt.ScrollBarAlwaysOff)
        frame.setFixedWidth(290)
        frame.setStyleSheet(
            f"QScrollArea#sidebarFrame{{background:{PAPER_DEEP}; border:none;}}" + SCROLLBAR)
        self.sidebar_frame = frame
        return frame

    def _learn_row(self):
        button = _Clickable()
        button.setCursor(QtCore.Qt.PointingHandCursor)
        button.setStyleSheet("background:transparent; border:none;")
        row = QtWidgets.QHBoxLayout(button)
        row.setContentsMargins(5, 4, 0, 4)
        row.setSpacing(11)

        mark = QtWidgets.QLabel()
        mark.setPixmap(brand.icon("learn", 15, INK).pixmap(15, 15))
        mark.setFixedWidth(15)
        mark.setAttribute(QtCore.Qt.WA_TransparentForMouseEvents, True)
        row.addWidget(mark, 0, QtCore.Qt.AlignVCenter)

        words = QtWidgets.QLabel(
            f"<div style='color:{INK}; font-size:12px'>" + L("Learn") + "</div>"
            f"<div style='color:{INK}; font-size:12px'>"
            + L("How each skill works") + "</div>")
        words.setStyleSheet("border:none; background:transparent;")
        words.setAttribute(QtCore.Qt.WA_TransparentForMouseEvents, True)
        row.addWidget(words, 1)

        button.clicked.connect(self.learn_requested.emit)
        return button

    PROFILE_ACCENTS = ["#1C2950", "#9E7833", "#4A6155", "#7B403D", "#455473", "#665070"]

    def _profile_bar(self):
        box = _Clickable()
        box.setCursor(QtCore.Qt.PointingHandCursor)
        box.setStyleSheet("border:none; background:transparent;")
        lay = QtWidgets.QHBoxLayout(box)
        lay.setContentsMargins(0, 0, 0, 0)
        lay.setSpacing(8)

        p = self.store.profile
        colour = profile_colour(p.get("accent", 0))
        mark = QtWidgets.QLabel(profile_initials(p))
        mark.setFixedSize(22, 22)
        mark.setAlignment(QtCore.Qt.AlignCenter)
        mark.setStyleSheet(
            f"background:{colour}; color:{brand.on_fill(colour)}; border-radius:11px;"
            "font-size:9px; font-weight:600;")
        lay.addWidget(mark)

        name = QtWidgets.QLabel(
            f"<div style='font-size:12px; font-weight:600; color:{INK}'>"
            f"{profile_display_name(p)}</div>"
            f"<div style='font-size:9px; color:{MUTED}'>" + L("Switch student")
            + "</div>")
        name.setStyleSheet("border:none; background:transparent;")
        name.setAttribute(QtCore.Qt.WA_TransparentForMouseEvents, True)
        mark.setAttribute(QtCore.Qt.WA_TransparentForMouseEvents, True)
        lay.addWidget(name, 1)

        button = QtWidgets.QPushButton(brand.ICONS["switch_student"])
        button.setAccessibleName(L("Students"))
        button.setFont(QtGui.QFont(brand.ICON_FONT, 9))
        button.setCursor(QtCore.Qt.PointingHandCursor)
        button.setStyleSheet(f"QPushButton{{border:none; color:{MUTED};}}")
        menu = QtWidgets.QMenu(button)
        brand.dress_menu(menu)
        for other in self.store.profiles.profiles:
            label = profile_display_name(other).replace("&", "&&")
            action = menu.addAction(label)
            if other["id"] == p["id"]:
                action.setIcon(brand.icon("tick", 12, NAVY))
            action.triggered.connect(
                lambda _=False, o=other: self._switch_profile(o))
        menu.addSeparator()
        menu.addAction(L("Manage students…")).triggered.connect(self._manage_profiles)
        button.setMenu(menu)
        lay.addWidget(button)
        box.clicked.connect(
            lambda: menu.exec(button.mapToGlobal(
                QtCore.QPoint(0, button.height()))))
        return box

    def _switch_profile(self, profile):
        self.store.use_profile(profile)
        window = self.window()
        if hasattr(window, "reload_theme"):
            window.reload_theme()
        else:
            self.refresh()
        say_highlights_taken_off(window, self.store)

    def _manage_profiles(self):
        self._open_modal(lambda parent: ProfilesDialog(self.store, parent))

    def _welcome_back(self, welcome):
        box = QtWidgets.QFrame()
        box.setObjectName("welcomeback")
        box.setStyleSheet(
            f"QFrame#welcomeback{{background:{BRASS_SOFT}; border:none;"
            f"border-left:2px solid {BRASS};}}")
        lay = QtWidgets.QVBoxLayout(box)
        lay.setContentsMargins(12, 9, 10, 10)
        lay.setSpacing(4)

        top = QtWidgets.QHBoxLayout()
        top.setContentsMargins(0, 0, 0, 0)
        title = QtWidgets.QLabel(L("Welcome back"))
        title.setStyleSheet(
            f"color:{NAVY}; font-size:13px; font-weight:600; font-family:{SERIF};"
            "border:none;")
        top.addWidget(title)
        top.addStretch(1)
        close = QtWidgets.QPushButton()
        close.setIcon(brand.icon("cross", 9, MUTED))
        close.setIconSize(QtCore.QSize(9, 9))
        close.setFlat(True)
        close.setFixedSize(18, 18)
        close.setCursor(QtCore.Qt.PointingHandCursor)
        close.setToolTip(L("Hide this"))
        close.setStyleSheet(
            f"QPushButton{{border:none; background:transparent; color:{MUTED};"
            "font-size:10px;}")

        def dismiss():
            self.store.dismiss_welcome_back(welcome)
            box.setParent(None)

        close.clicked.connect(dismiss)
        top.addWidget(close)
        lay.addLayout(top)

        since = Lp(welcome["days_away"],
                   "It has been %d day since you last practiced.",
                   "It has been %d days since you last practiced.")
        skills = welcome["skills"]
        if not skills:
            line = since + " " + L("Pick up anywhere — a short sitting counts.")
        else:
            named = skills[0] if len(skills) == 1 else Lf("%1$@ and %2$@", skills[0], skills[1])
            line = since + " " + Lf("Worth going back over %@ first.", named)
        body = QtWidgets.QLabel(line)
        body.setWordWrap(True)
        leading(body)
        body.setStyleSheet(f"color:{MUTED}; font-size:10px; border:none;")
        lay.addWidget(body)
        return box

    def _damaged_notice(self):
        box = QtWidgets.QFrame()
        box.setObjectName("damagednotice")
        box.setStyleSheet(
            f"QFrame#damagednotice{{background:{BRASS_SOFT}; border:none;"
            f"border-left:2px solid {BRASS};}}")
        lay = QtWidgets.QHBoxLayout(box)
        lay.setContentsMargins(12, 9, 10, 10)
        lay.setSpacing(6)
        body = QtWidgets.QLabel(
            L("Some saved work could not be read, so it was kept aside, untouched, as a “.damaged” file in the app's folder."))
        body.setWordWrap(True)
        leading(body)
        body.setToolTip("\n".join(self.store.damaged))
        body.setStyleSheet(f"color:{INK}; font-size:10px; border:none;")
        lay.addWidget(body, 1)
        close = QtWidgets.QPushButton()
        close.setIcon(brand.icon("cross", 9, MUTED))
        close.setIconSize(QtCore.QSize(9, 9))
        close.setFlat(True)
        close.setFixedSize(18, 18)
        close.setCursor(QtCore.Qt.PointingHandCursor)
        close.setToolTip(L("Hide this"))
        close.setAccessibleName(L("Hide this"))
        close.setStyleSheet(
            f"QPushButton{{border:none; background:transparent; color:{MUTED};"
            "font-size:10px;}")

        def dismiss():
            self.store.damaged = []
            box.setParent(None)

        close.clicked.connect(dismiss)
        lay.addWidget(close, 0, QtCore.Qt.AlignTop)
        return box

    def _deck_section(self):
        box = QtWidgets.QWidget()
        box.setStyleSheet("background:transparent;")
        lay = QtWidgets.QVBoxLayout(box)
        lay.setContentsMargins(0, 0, 0, 0)
        lay.setSpacing(6)

        head = QtWidgets.QHBoxLayout()
        head.addWidget(_label(L("Flashcards")))
        head.addStretch(1)
        new = QtWidgets.QPushButton("+")
        new.setFlat(True)
        new.setFixedWidth(20)
        new.setToolTip(L("New deck"))
        new.setAccessibleName(L("New deck"))
        new.setCursor(QtCore.Qt.PointingHandCursor)
        new.setStyleSheet(
            f"QPushButton{{border:none; background:transparent; color:{MUTED};"
            "font-size:15px;}"
            f"QPushButton:hover{{color:{NAVY};}}")
        new.clicked.connect(self._new_deck)
        lay.addLayout(head)
        self._deck_head_h = 22
        head.addWidget(new)

        self.deck_list = QtWidgets.QListWidget()
        self.deck_list.setAccessibleName(L("Flashcards"))
        self.deck_list.setSizePolicy(QtWidgets.QSizePolicy.Preferred,
                                     QtWidgets.QSizePolicy.Expanding)
        self.deck_list.setStyleSheet(
            "QListWidget{background:transparent; border:none; font-size:12px;"
            "outline:none;}"
            f"QListWidget::item{{padding:5px 12px; color:{INK};"
            "border-left:2px solid transparent;}"
            f"QListWidget::item:hover{{background:{SUBTLE};}}"
            f"QListWidget::item:selected{{background:{CARD}; color:{INK};"
            f"border-left:2px solid {BRASS};}}")
        self.deck_list.setHorizontalScrollBarPolicy(QtCore.Qt.ScrollBarAlwaysOff)
        self.deck_list.setTextElideMode(QtCore.Qt.ElideRight)
        self.deck_list.setItemDelegate(DeckDelegate(self.deck_list))
        self.deck_list.itemSelectionChanged.connect(self._deck_changed)
        self.deck_list.setContextMenuPolicy(QtCore.Qt.CustomContextMenu)
        self.deck_list.customContextMenuRequested.connect(self._deck_menu)
        lay.addWidget(self.deck_list, 1)
        return box

    def _nothing_chosen(self):
        box = QtWidgets.QWidget()
        lay = QtWidgets.QVBoxLayout(box)
        lay.setContentsMargins(22, 0, 22, 0)
        lay.setSpacing(10)
        lay.addStretch(1)

        title = QtWidgets.QLabel(L("Nothing to study yet"))
        title.setAlignment(QtCore.Qt.AlignCenter)
        title.setStyleSheet(
            f"color:{INK}; font-size:13px; font-weight:600; border:none;")
        lay.addWidget(title)

        body = QtWidgets.QLabel(
            L("Please choose what you want to study in Settings — SAT practice, "
              "flashcards, or both. Nothing of yours has been deleted."))
        body.setWordWrap(True)
        leading(body)
        body.setAlignment(QtCore.Qt.AlignCenter)
        body.setStyleSheet(f"color:{MUTED}; font-size:11px; border:none;")
        lay.addWidget(body)

        open_settings = QtWidgets.QPushButton(L("Open Settings"))
        open_settings.setCursor(QtCore.Qt.PointingHandCursor)
        open_settings.setStyleSheet(
            f"QPushButton{{border:none; background:transparent; color:{BRASS_TEXT};"
            "font-size:11px; font-weight:500;}")
        open_settings.clicked.connect(lambda: self._open_settings("study"))
        lay.addWidget(open_settings, 0, QtCore.Qt.AlignCenter)

        lay.addStretch(1)
        return box

    def _refresh_decks(self):
        if not hasattr(self, "deck_list"):
            return
        self.deck_list.blockSignals(True)
        self.deck_list.clear()
        for deck in self.store.decks.decks:
            n = len(deck.cards)
            item = QtWidgets.QListWidgetItem(
                deck.name + "\n" + Lp(n, "%d card", "%d cards"))
            if deck.starred_count:
                item.setData(ROLE_STARS, deck.starred_count)
                item.setToolTip(Lf("%d starred", deck.starred_count))
            self.deck_list.addItem(item)
        if self.selected_deck_id:
            ids = [d.id for d in self.store.decks.decks]
            if self.selected_deck_id in ids:
                self.deck_list.setCurrentRow(ids.index(self.selected_deck_id))
                self.deck_list.scrollToItem(self.deck_list.currentItem())
            else:
                self.selected_deck_id = None
        else:
            self.deck_list.clearSelection()
        self.deck_list.blockSignals(False)
        if hasattr(self, "deck_splitter"):
            self.deck_splitter.set_target(
                self.store.settings.get("libraryPaneHeight"))

    def _deck_fit_height(self):
        rows = sum(self.deck_list.sizeHintForRow(i)
                   for i in range(self.deck_list.count()))
        rows += 2 * self.deck_list.frameWidth()
        return self._deck_head_h + 8 + min(rows, 168)

    def _deck_height_changed(self, value):
        self._pending_deck_height = value
        if value is None:
            self._persist_deck_height()
        else:
            self._deck_persist.start()

    def _persist_deck_height(self):
        self.store.set_setting("libraryPaneHeight",
                               getattr(self, "_pending_deck_height", None))

    def _new_deck(self):
        deck = self.store.decks.add_deck()
        self.selected_deck_id = deck.id
        self._refresh_decks()
        self._show_deck()

    def _deck_changed(self):
        row = self.deck_list.currentRow()
        if not (0 <= row < len(self.store.decks.decks)):
            return
        self.selected_deck_id = self.store.decks.decks[row].id
        self.bank_list.clearSelection()
        self._show_deck()

    def _deck_menu(self, pos):
        row = self.deck_list.currentRow()
        if not (0 <= row < len(self.store.decks.decks)):
            return
        deck = self.store.decks.decks[row]
        menu = QtWidgets.QMenu(self)
        brand.dress_menu(menu)
        menu.addAction(L("Rename…"), lambda: self._rename_deck(deck))
        menu.addSeparator()
        menu.addAction(L("Delete"), lambda: self._delete_deck(deck))
        menu.exec(self.deck_list.mapToGlobal(pos))

    def _rename_deck(self, deck):
        name, ok = QtWidgets.QInputDialog.getText(self, L("Rename deck"), L("Name"),
                                                  text=deck.name)
        if ok and name.strip():
            self.store.decks.rename_deck(deck.id, name)
            self._refresh_decks()
            if self.deck_screen is not None:
                self.deck_screen.reload()

    def _delete_deck(self, deck):
        if not brand.ask(
                self, L("Delete this deck?"),
                L("The cards in it are removed. Your question sets are not "
                  "touched."),
                accept=L("Delete"), destructive=True):
            return
        self.store.decks.delete_deck(deck.id)
        if self.selected_deck_id == deck.id:
            self.selected_deck_id = None
        self._refresh_decks()
        self._show_practise()

    def _show_deck(self):
        from .decks import DeckScreen
        holder = self.deck_holder.layout()
        while holder.count():
            item = holder.takeAt(0)
            if item.widget():
                item.widget().deleteLater()
        self.deck_screen = DeckScreen(self.store, self.selected_deck_id)
        self.deck_screen.changed.connect(self._refresh_decks)
        self.deck_screen.focus_requested.connect(self.focus_requested.emit)
        holder.addWidget(self.deck_screen)
        self.tab_bar.setVisible(False)
        self.tab_rule.setVisible(False)
        self.pages.setCurrentIndex(2)

    def zoom_by(self, delta):
        screen = self.deck_screen
        if screen is not None and screen.isVisible():
            screen.zoom_by(delta)

    def _show_practise(self):
        self.selected_deck_id = None
        self.deck_screen = None
        self.tab_bar.setVisible(True)
        self.tab_rule.setVisible(True)
        self.pages.setCurrentIndex(self._TAB_PAGES.get(self.tab, 0))

    def reload_deck(self):
        if self.selected_deck_id:
            self._show_deck()

    def returned(self):
        self._refresh_decks()
        if self.deck_screen is not None:
            self.deck_screen.reload()

    def _settings_row(self):
        button = brand.IconButton("settings", L("Settings"), MUTED, NAVY, size=11)
        button.setStyleSheet(
            f"QPushButton{{border:none; color:{MUTED}; font-size:10.5px;"
            "background:transparent;}"
            f"QPushButton:hover{{color:{NAVY};}}")
        button.clicked.connect(self._open_settings)
        return button

    def _show_about(self):
        from .promo import AboutPanel
        AboutPanel(self).exec()

    def _open_modal(self, make):
        window = self.window()
        dialog = make(window if window is not None else self)
        dialog.exec()
        if not shiboken6.isValid(self):
            return
        if window is not None and hasattr(window, "reload_theme"):
            window.reload_theme()
        else:
            self.refresh()

    def _open_settings(self, tab="customisation"):
        from .settings import SettingsSheet
        self._open_modal(
            lambda parent: SettingsSheet(self.store, parent, tab=tab))

    def _colophon(self):
        box = QtWidgets.QWidget()
        box.setStyleSheet("border:none;")
        lay = QtWidgets.QVBoxLayout(box)
        lay.setContentsMargins(0, 0, 0, 0)
        lay.setSpacing(9)

        slogan = QtWidgets.QLabel(brand.SLOGAN)
        slogan.setAlignment(QtCore.Qt.AlignCenter)
        slogan.setWordWrap(True)
        leading(slogan)
        slogan.setStyleSheet(
            f"color:{MUTED}; font-size:10px; font-family:{SERIF};"
            "font-style:italic; border:none;")
        lay.addWidget(slogan)

        footprint = QtWidgets.QLabel(
            L("Not affiliated with the College Board. "
              "Everything stays on your computer."))
        footprint.setAlignment(QtCore.Qt.AlignCenter)
        footprint.setWordWrap(True)
        leading(footprint)
        footprint.setStyleSheet(f"color:{MUTED}; font-size:9px; border:none;")
        lay.addWidget(footprint)
        lay.addWidget(self._settings_row(), 0, QtCore.Qt.AlignCenter)

        return box

    def _row_clicked(self, item):
        if item.data(ROLE_KIND) == "shelf":
            self._toggle_shelf(item.data(ROLE_ID))
            return
        if item.data(ROLE_KIND) == "bank" and self.selected_deck_id is not None:
            self.deck_list.clearSelection()
            self._show_practise()
            self._build_detail(fade=True)

    def _row_id(self, row, kind="bank"):
        item = self.bank_list.item(row) if row >= 0 else None
        if item is None or item.data(ROLE_KIND) != kind:
            return None
        return item.data(ROLE_ID)

    def _bank_changed(self, row):
        bank_id = self._row_id(row)
        if bank_id is None:
            return
        self.config["bank_id"] = bank_id
        if self.selected_deck_id is not None:
            self.deck_list.clearSelection()
            self._show_practise()
        self._build_detail(fade=True)
        if self.tab == "statistics":
            self._build_statistics()

    def _shelf_tool(self, icon, tip, slot):
        button = QtWidgets.QPushButton(brand.ICONS[icon])
        button.setFont(QtGui.QFont(brand.ICON_FONT, 8))
        button.setToolTip(tip)
        button.setAccessibleName(tip)
        button.setCursor(QtCore.Qt.PointingHandCursor)
        button.setFixedSize(20, 18)
        button.setStyleSheet(
            f"QPushButton{{border:none; color:{MUTED}; background:transparent;}}"
            f"QPushButton:hover{{color:{NAVY};}}")
        button.clicked.connect(slot)
        return button

    def _add_shelf(self):
        layout = self.store.library_layout()
        name, ok = QtWidgets.QInputDialog.getText(
            self, L("New shelf"), L("Name"), text=layout.fresh_shelf_name())
        if not ok or not name.strip():
            return
        layout.add_shelf(name.strip())
        self.store.save_library_layout(layout)
        self.refresh()

    def _pick_order(self):
        layout = self.store.library_layout()
        menu = QtWidgets.QMenu(self)
        brand.dress_menu(menu)
        for order in library.ORDERS:
            action = menu.addAction(library.order_title(order))
            action.setCheckable(True)
            action.setChecked(order == layout.order)
            action.triggered.connect(
                lambda _=False, o=order: self._set_order(o))
        menu.exec(QtGui.QCursor.pos())

    def _set_order(self, order):
        layout = self.store.library_layout()
        layout.order = order
        self.store.save_library_layout(layout)
        self.refresh()

    def _toggle_shelf(self, shelf_id):
        layout = self.store.library_layout()
        shelf = next((s for s in layout.shelves if s.id == shelf_id), None)
        if shelf is None:
            return
        shelf.collapsed = not shelf.collapsed
        self.store.save_library_layout(layout)
        self.refresh()

    def _shelf_menu(self, shelf_id, pos):
        layout = self.store.library_layout()
        shelf = next((s for s in layout.shelves if s.id == shelf_id), None)
        if shelf is None:
            return
        menu = QtWidgets.QMenu(self)
        brand.dress_menu(menu)
        menu.addAction(L("Rename shelf…"), lambda: self._rename_shelf(shelf_id))
        menu.addSeparator()
        menu.addAction(L("Move up"), lambda: self._move_shelf(shelf_id, -1))
        menu.addAction(L("Move down"), lambda: self._move_shelf(shelf_id, 1))
        menu.addSeparator()
        menu.addAction(L("Remove shelf"), lambda: self._remove_shelf(shelf_id))
        note = menu.addAction(
            L("The sets on it are kept — they go back to Unshelved."))
        note.setEnabled(False)
        menu.exec(self.bank_list.mapToGlobal(pos))

    def _rename_shelf(self, shelf_id):
        layout = self.store.library_layout()
        shelf = next((s for s in layout.shelves if s.id == shelf_id), None)
        if shelf is None:
            return
        name, ok = QtWidgets.QInputDialog.getText(
            self, L("Rename shelf"), L("Name"), text=shelf.name)
        if ok and name.strip():
            shelf.name = name.strip()
            self.store.save_library_layout(layout)
            self.refresh()

    def _move_shelf(self, shelf_id, delta):
        layout = self.store.library_layout()
        layout.move_shelf(shelf_id, delta)
        self.store.save_library_layout(layout)
        self.refresh()

    def _remove_shelf(self, shelf_id):
        layout = self.store.library_layout()
        layout.remove_shelf(shelf_id)
        self.store.save_library_layout(layout)
        self.refresh()

    def _file_bank(self, bank_id, shelf_id, position):
        layout = self.store.library_layout()
        layout.move(bank_id, shelf_id, position)
        self.store.save_library_layout(layout)
        self.refresh()

    def _shelve(self, bank_id, shelf_id):
        layout = self.store.library_layout()
        layout.move(bank_id, shelf_id)
        self.store.save_library_layout(layout)
        self.refresh()

    def _bank_menu(self, pos):
        row = self.bank_list.indexAt(pos).row()
        shelf_id = self._row_id(row, "shelf")
        if shelf_id is not None:
            self._shelf_menu(shelf_id, pos)
            return
        bank_id = self._row_id(row)
        bank = self.store.bank(bank_id) if bank_id else None
        if bank is None:
            return
        layout = self.store.library_layout()
        menu = QtWidgets.QMenu(self)
        brand.dress_menu(menu)

        if layout.shelves:
            on = layout.shelf_of(bank.id)
            shelves = menu.addMenu(L("Move to shelf"))
            for shelf in layout.shelves:
                action = shelves.addAction(shelf.name)
                action.setCheckable(True)
                action.setChecked(on is not None and on.id == shelf.id)
                action.triggered.connect(
                    lambda _=False, s=shelf.id: self._shelve(bank.id, s))
            shelves.addSeparator()
            floor = shelves.addAction(L("Unshelved"))
            floor.setCheckable(True)
            floor.setChecked(on is None)
            floor.triggered.connect(lambda: self._shelve(bank.id, None))
            menu.addSeparator()

        menu.addAction(L("Rename…"), lambda: self._rename(bank))
        menu.addAction(L("Add another PDF to this set…"), lambda: self._choose_files(bank.id))
        menu.addSeparator()
        menu.addAction(L("Reset my progress"), lambda: self._reset(bank))
        menu.addAction(L("Delete"), lambda: self._delete(bank))
        menu.exec(self.bank_list.mapToGlobal(pos))

    def _row_double_clicked(self, item):
        if item is not None and item.data(ROLE_KIND) == "bank":
            bank = self.store.bank(item.data(ROLE_ID))
            if bank is not None:
                self._rename(bank)

    def _rename(self, bank):
        name, ok = QtWidgets.QInputDialog.getText(self, L("Rename question set"),
                                                  L("Name"), text=bank.name)
        if ok and name.strip():
            self.store.rename_bank(bank, name.strip())
            self.refresh()

    def _reset(self, bank):
        self.store.reset_progress(bank.id)
        self.refresh()

    def _delete(self, bank):
        if brand.ask(
                self, L("Delete this question set?"),
                L("The imported questions and your progress for this set will "
                  "be removed. Your original PDF files are not touched."),
                accept=L("Delete"), destructive=True):
            self.store.delete_bank(bank)
            self.config["bank_id"] = self.store.banks[0].id if self.store.banks else ""
            self.refresh()

    def _choose_files(self, into=None):
        paths, _ = QtWidgets.QFileDialog.getOpenFileNames(
            self, L("Choose PDFs exported from the College Board Question Bank"),
            brand.dialog_path(opening=True), "PDF files (*.pdf)")
        if paths:
            brand.remember_folder(paths)
            self._run_import(paths, into if isinstance(into, str) else None)

    def dragEnterEvent(self, e):
        if e.mimeData().hasUrls():
            e.acceptProposedAction()
            if any(u.toLocalFile().lower().endswith(".pdf") for u in e.mimeData().urls()):
                self._show_drop_outline(True)

    def dragLeaveEvent(self, e):
        self._show_drop_outline(False)
        super().dragLeaveEvent(e)

    def _show_drop_outline(self, on):
        outline = getattr(self, "_drop_outline", None)
        if outline is None:
            if not on:
                return
            outline = QtWidgets.QFrame(self)
            outline.setObjectName("dropOutline")
            outline.setAttribute(QtCore.Qt.WA_TransparentForMouseEvents, True)
            outline.setStyleSheet(f"QFrame#dropOutline{{border:2px dashed {BRASS};"
                                  "border-radius:8px; background:transparent;}")
            self._drop_outline = outline
        if on:
            outline.setGeometry(self.rect().adjusted(6, 6, -6, -6))
            outline.raise_()
        outline.setVisible(on)

    def dropEvent(self, e):
        self._show_drop_outline(False)
        paths = [u.toLocalFile() for u in e.mimeData().urls()
                 if u.toLocalFile().lower().endswith(".pdf")]
        if paths:
            self._run_import(paths, None)

    def _run_import(self, paths, into):
        dlg = QtWidgets.QProgressDialog(L("Reading…"), None, 0, 100, self.window())
        dlg.setWindowTitle(L("Importing"))
        dlg.setWindowModality(QtCore.Qt.WindowModal)
        dlg.setMinimumDuration(0)
        dlg.setValue(0)
        QtWidgets.QApplication.processEvents()

        def progress(p, msg):
            dlg.setValue(int(p * 100))
            dlg.setLabelText(msg)
            QtWidgets.QApplication.processEvents()

        try:
            with self._while_reading():
                bank, warnings = self.store.import_pdfs(paths, into=into, progress=progress)
            self.config["bank_id"] = bank.id
        except AlreadyImported as e:
            dlg.close()
            self.config["bank_id"] = e.bank_id
            self.refresh()
            brand.tell(self, L("Nothing was imported"), str(e))
            return
        except Exception as e:
            dlg.close()
            brand.warn(self, L("Could not import"), str(e))
            return
        dlg.close()
        if warnings:
            brand.tell(
                self, L("Imported with notes"),
                Lp(len(warnings), "%d question was skipped:",
                   "%d questions were skipped:")
                + "\n\n" + "\n".join(warnings[:8]))
        self.refresh()

    def refresh(self):
        self.bank_list.blockSignals(True)
        self.bank_list.clear()
        layout = self.store.library_layout()
        chosen_row = None
        sections = self.store.shelved_banks()
        has_shelves = any(shelf is not None for shelf, _ in sections)
        for shelf, banks in sections:
            if shelf is None and not has_shelves:
                pass
            elif shelf is None:
                floor = QtWidgets.QListWidgetItem(
                    "%s    %d" % (L("Unshelved"), len(banks)))
                floor.setData(ROLE_KIND, "floor")
                floor.setData(ROLE_ID, None)
                floor.setIcon(brand.icon("floor", 12, MUTED))
                floor.setFont(_sidebar_heading_font())
                floor.setForeground(QtGui.QColor(MUTED))
                floor.setFlags(QtCore.Qt.ItemIsEnabled | QtCore.Qt.ItemIsDropEnabled)
                self.bank_list.addItem(floor)
            if shelf is not None:
                head = QtWidgets.QListWidgetItem(
                    "%s    %d" % (shelf.name, len(banks)))
                head.setData(ROLE_KIND, "shelf")
                head.setData(ROLE_ID, shelf.id)
                head.setIcon(brand.icon("shut" if shelf.collapsed else "open",
                                        12, MUTED))
                head.setFont(_sidebar_heading_font())
                head.setForeground(QtGui.QColor(MUTED))
                head.setFlags(QtCore.Qt.ItemIsEnabled)
                self.bank_list.addItem(head)
                if shelf.collapsed:
                    continue
            if not banks and (shelf is not None or has_shelves):
                empty = QtWidgets.QListWidgetItem(
                    L("Empty — drag a set here, or use its menu.")
                    if shelf is not None else L("Everything is on a shelf."))
                empty.setData(ROLE_KIND, "note")
                empty.setForeground(QtGui.QColor(MUTED))
                empty.setFlags(QtCore.Qt.ItemIsEnabled)
                self.bank_list.addItem(empty)
            for b in banks:
                seen = self.store.seen_count(b.id)
                item = QtWidgets.QListWidgetItem(
                    b.name + "\n"
                    + Lf("%1$d questions · %2$d seen", len(b.questions), seen))
                item.setData(ROLE_KIND, "bank")
                item.setData(ROLE_ID, b.id)
                item.setData(ROLE_SEEN,
                             seen / len(b.questions) if b.questions else 0.0)
                self.bank_list.addItem(item)
                if b.id == self.config["bank_id"]:
                    chosen_row = self.bank_list.count() - 1

        if chosen_row is None and self.store.banks:
            for row in range(self.bank_list.count()):
                if self.bank_list.item(row).data(ROLE_KIND) == "bank":
                    chosen_row = row
                    self.config["bank_id"] = self.bank_list.item(row).data(ROLE_ID)
                    break
        if chosen_row is not None:
            self.bank_list.setCurrentRow(chosen_row)
            self.bank_list.scrollToItem(self.bank_list.item(chosen_row))
        self.bank_list.blockSignals(False)
        self._refresh_decks()
        self._build_detail(fade=True)

    def _build_detail(self, fade=False):
        bank = self.store.bank(self.config["bank_id"])
        if bank is not None and self.config.get("full_test") and not (
                self.store.full_test_readiness(self.config).is_ready
                and not self.config.get("partnerProfileID")):
            self.config["full_test"] = False
            self.config["adaptive"] = False
        page = QtWidgets.QWidget()
        page.setObjectName("detailPage")
        page.setStyleSheet(f"QWidget#detailPage{{background:{PAPER};}}")
        lay = QtWidgets.QVBoxLayout(page)
        lay.setContentsMargins(32, 28, 32, 28)
        lay.setSpacing(22)

        sets_on = self.store.settings.get("showQuestionSets", True)
        deck_open = self.deck_screen is not None
        if not deck_open:
            self.tab_bar.setVisible(sets_on)
            self.tab_rule.setVisible(sets_on)
        if not sets_on:
            if not deck_open:
                self.pages.setCurrentIndex(0)
            if self.store.settings.get("showFlashcards", True):
                words = L("Pick a deck on the left to study your words, or make a new "
                          "one. SAT practice is turned off; Settings will bring it "
                          "back whenever you want it.")
                label, action = L("New deck"), self._new_deck
            else:
                words = L("Please choose what you want to study in Settings — SAT "
                          "practice, flashcards, or both. Nothing of yours has been "
                          "deleted.")
                label, action = L("Open Settings"), lambda: self._open_settings("study")
            msg = QtWidgets.QLabel(words)
            msg.setWordWrap(True)
            leading(msg)
            msg.setAlignment(QtCore.Qt.AlignCenter)
            msg.setStyleSheet(f"color:{MUTED}; font-size:13px;")
            go = QtWidgets.QPushButton(label)
            go.setCursor(QtCore.Qt.PointingHandCursor)
            go.setStyleSheet(
                f"QPushButton{{background:{NAVY}; color:{CARD}; border:none;"
                "border-radius:4px; padding:9px 18px; font-size:12.5px; font-weight:600;}")
            go.clicked.connect(action)
            msg.setMaximumWidth(520)
            msg.setSizePolicy(QtWidgets.QSizePolicy.Expanding, QtWidgets.QSizePolicy.Preferred)
            middle = QtWidgets.QHBoxLayout()
            middle.addStretch(1)
            middle.addWidget(msg, 100)
            middle.addStretch(1)
            lay.addStretch(1)
            lay.addLayout(middle)
            lay.addWidget(go, 0, QtCore.Qt.AlignCenter)
            lay.addStretch(1)
            self._selection_group = self._order_group = self._grading_group = None
            self._count_slot = self._timer_slot = self._start_slot = None
            self._narrow_slot = None
            self._pin_start(None)
            self.detail_area.setWidget(page)
            return

        if not bank:
            msg = QtWidgets.QLabel(
                L("Import a question bank to begin.") + "\n\n"
                + L("In the College Board Question Bank — SAT or PSAT — pick the "
                    "questions you want and choose Export. Import that PDF here and "
                    "it becomes a practice test you can take as many times as you like."))
            msg.setWordWrap(True)
            leading(msg)
            msg.setAlignment(QtCore.Qt.AlignCenter)
            msg.setStyleSheet(f"color:{MUTED}; font-size:13px;")
            lay.addStretch(1)
            lay.addWidget(msg)
            lay.addStretch(1)
            self._selection_group = self._order_group = self._grading_group = None
            self._count_slot = self._timer_slot = self._start_slot = None
            self._narrow_slot = None
            self._pin_start(None)
            self.detail_area.setWidget(page)
            return

        title = QtWidgets.QLabel(breakable(bank.name))
        title.setAccessibleName(bank.name)
        title.setStyleSheet(
            f"color:{NAVY}; font-size:27px; font-weight:600; font-family:{SERIF};")
        title.setWordWrap(True)
        leading(title)
        title.setSizePolicy(QtWidgets.QSizePolicy.Ignored, QtWidgets.QSizePolicy.Preferred)
        self._arrived = 0

        def arrive(widget):
            if not fade:
                lay.addWidget(widget)
                return
            lay.addWidget(entrance(widget, self._arrived))
            self._arrived += 1

        head = QtWidgets.QWidget()
        head.setStyleSheet("background:transparent;")
        head_lay = QtWidgets.QHBoxLayout(head)
        head_lay.setContentsMargins(0, 0, 0, 0)
        head_lay.setSpacing(22)

        left = QtWidgets.QWidget()
        left.setStyleSheet("background:transparent;")
        left_lay = QtWidgets.QVBoxLayout(left)
        left_lay.setContentsMargins(0, 0, 0, 0)
        left_lay.setSpacing(22)
        left_lay.addWidget(title)
        left_lay.addWidget(_rule(brass=True, width=46))

        seen = self.store.seen_count(bank.id)
        to_review = sum(1 for q in bank.questions if self.store.last_wrong(bank.id, q.id))
        left_lay.addWidget(self._stats_row(bank, seen, to_review))
        left_lay.addStretch(1)
        head_lay.addWidget(left, 1)

        if self.store.settings.get("showQuestionStreak", True):
            head_lay.addWidget(self._rhythm_card(), 0,
                               QtCore.Qt.AlignTop | QtCore.Qt.AlignRight)
        arrive(head)

        if self.store.needs_reread(bank):
            arrive(self._reread_card(bank))

        saved = self.store.saved_session(bank.id)
        if saved:
            arrive(self._resume_card(saved))

        arrive(self._plans_bar())

        arrive(self._full_test_card(bank))

        if len(self.store.profiles.profiles) > 1 \
                and self.store.settings.get("showDoubleMode", True):
            arrive(self._double_card())

        if self.store.settings.get("showBackupCard", True) \
                and self.store.backup_is_worth_mentioning():
            arrive(self._backup_card())

        what, wlay = _card(L("What to practice"))
        wlay.addWidget(self._subject_row(bank))
        sel = RadioGroup(L("Which questions"), [
            ("new_first", L("Continue where I left off"),
             L("Unseen questions first, then ones you got wrong.")),
            ("unseen_only", L("Only questions I have never seen"),
             L("Completely fresh ones, skipping anything you set aside.")),
            ("due_for_review", L("Due for review"),
             L("Spaced practice: questions come back a day after you get one wrong, "
             "and at widening gaps while you keep getting it right.")),
            ("weakest_skills", L("Drill my weakest skills"),
             L("Drawn from the skills you are scoring lowest on, worst first.")),
            ("review_missed", L("Review my missed questions"),
             L("Only questions you have answered incorrectly before.")),
            ("set_aside", L("Questions I set aside"),
             L("The ones you kept back to look at later.")),
            ("all", L("Everything in the bank"), L("Draw from the whole bank, seen or not.")),
        ], self.config["selection"], counts=self._mode_counts())
        sel.changed.connect(lambda v: self._set("selection", v))
        wlay.addWidget(sel)
        self._selection_group = sel
        self._narrow_slot = _Slot(
            lambda b=bank, fade=False: self._narrow_row(b, fade=fade))
        wlay.addWidget(self._narrow_slot)
        self._count_slot = _Slot(self._count_row)
        wlay.addWidget(self._count_slot)
        full = bool(self.config.get("full_test"))
        arrive(_dimmed(what) if full else what)

        how, hlay = _card(L("How to practice"))
        order = RadioGroup(L("Order"), [
            ("pdf_order", L("PDF order"), L("Keep the order the questions came in.")),
            ("sequential", L("One section after the other"),
             L("All Reading and Writing, then all Math, in file order.")),
            ("shuffled_in_section", L("Shuffled inside each section"),
             L("Reading and Writing first, then Math, but shuffled within each.")),
            ("mixed", L("Mixed together"), L("Shuffle both sections together.")),
        ], self.config["mix"])
        order.changed.connect(lambda v: self._set("mix", v))
        hlay.addWidget(order)
        self._order_group = order
        grading = RadioGroup(L("Grading"), [
            ("at_end", L("Grade at the end"),
             L("Feels like the real test. You see all results after you submit.")),
            ("immediate", L("Grade each question"),
             L("Shows the answer and explanation right after you answer.")),
        ], self.config["grading"])
        grading.changed.connect(lambda v: self._set("grading", v))
        hlay.addWidget(grading)
        self._grading_group = grading
        self._timer_slot = _Slot(self._timer_row)
        hlay.addWidget(self._timer_slot)
        lay.addWidget(_dimmed(how) if full else how)

        aside = self._set_aside_card(bank)
        if aside is not None:
            lay.addWidget(aside)

        lay.addWidget(self._files_card(bank))

        lay.addWidget(self._add_files_row(bank))
        lay.addWidget(self._sitting_name_row())
        self._start_slot = _Slot(lambda b=bank: self._start_row(b))
        self._pin_start(self._start_slot)
        lay.addStretch(1)

        self._swap_detail(page, fade)

    def _pin_start(self, slot):
        while self._start_pin_lay.count():
            item = self._start_pin_lay.takeAt(0)
            if item.widget() is not None:
                item.widget().deleteLater()
        if slot is not None:
            self._start_pin_lay.addWidget(slot)
        self.start_pin.setVisible(slot is not None)
        self.start_pin_rule.setVisible(slot is not None)

    def _swap_detail(self, page, fade):
        bar = self.detail_area.verticalScrollBar()
        offset = bar.value()
        self.detail_area.setUpdatesEnabled(False)
        park_focus(self.detail_area.widget(), self.detail_area, coming=page)
        going = self.detail_area.takeWidget()
        if going is not None:
            going.setParent(None)
            going.deleteLater()
        self.detail_area.setWidget(fade_in(page, duration=180) if fade else page)
        if not fade and offset:
            QtCore.QTimer.singleShot(0, lambda: bar.setValue(offset))
        self.detail_area.setUpdatesEnabled(True)

    def _add_files_row(self, bank):
        row = QtWidgets.QWidget()
        row.setStyleSheet("background:transparent;")
        lay = QtWidgets.QHBoxLayout(row)
        lay.setContentsMargins(0, 0, 0, 0)
        lay.setSpacing(12)
        add = QtWidgets.QPushButton(L("Add another PDF to this set…"))
        add.setCursor(QtCore.Qt.PointingHandCursor)
        add.setStyleSheet(
            f"QPushButton{{background:transparent; color:{NAVY};"
            f"border:1px solid {NAVY}; border-radius:3px; padding:8px 18px;"
            "font-size:12px; font-weight:600;}"
            f"QPushButton:hover{{background:{BRASS_SOFT};}}")
        add.clicked.connect(lambda: self._choose_files(into=bank.id))
        lay.addWidget(add)
        note = QtWidgets.QLabel(
            L("Reading and Writing and Math can live in one set, and so can SAT "
            "and PSAT — you choose what to draw from above."))
        note.setWordWrap(True)
        leading(note)
        note.setStyleSheet(f"color:{MUTED}; font-size:11px; border:none;"
                           "background:transparent;")
        lay.addWidget(note, 1)
        return row

    RELIT_KEYS = ("selection", "mix", "grading", "count", "minutes", "timed")

    @staticmethod
    def _remembered_minutes(store):
        value = store.settings.get("practiceMinutes")
        if isinstance(value, int) and not isinstance(value, bool) and 1 <= value <= 360:
            return value
        return 32

    def _remember_timer(self):
        self.store.settings["practiceTimed"] = bool(self.config.get("timed"))
        self.store.settings["practiceMinutes"] = int(self.config.get("minutes") or 32)
        self.store.save_settings()

    def _set(self, key, value):
        if self.config.get(key) == value:
            return
        self.config[key] = value
        if key in ("timed", "minutes"):
            self._remember_timer()
        if key in self.RELIT_KEYS and self._count_slot is not None:
            self._relight(key)
        else:
            self._build_detail()

    def _relight(self, key):
        groups = {"selection": (self._selection_group, "selection"),
                  "mix": (self._order_group, "mix"),
                  "grading": (self._grading_group, "grading")}
        if key in groups:
            group, config_key = groups[key]
            if group is not None:
                group.set_current(self.config[config_key])
        if key in ("selection", "count"):
            self._count_slot.refill()
        if key in ("selection", "count", "minutes", "timed"):
            self._timer_slot.refill()
        self._start_slot.refill()

    def _backup_card(self):
        card, clay = _card(L("Keep a copy somewhere else"))
        days = self.store.days_since_backup()
        if days is None:
            headline = L("You have never made one.")
        elif days == 0:
            headline = L("Copied today.")
        else:
            headline = Lp(days, "The last copy you made was %d day ago.",
                          "The last copy you made was %d days ago.")
        head = QtWidgets.QLabel(headline)
        head.setWordWrap(True)
        leading(head)
        head.setStyleSheet(f"color:{MUTED}; font-size:11px; border:none;"
                           "background:transparent;")
        clay.addWidget(head)

        blurb = QtWidgets.QLabel(
            L("Everything of yours — progress, statistics, highlights, notes, "
              "flashcards and study plans — is one small file. It is not the "
              "question sets: those are your own PDFs and you can import them "
              "again. Send it to yourself and it survives this computer."))
        blurb.setWordWrap(True)
        leading(blurb)
        blurb.setStyleSheet(f"color:{MUTED}; font-size:11px; border:none;"
                            "background:transparent;")
        clay.addWidget(blurb)

        row = QtWidgets.QHBoxLayout()
        save = QtWidgets.QPushButton(L("Save a copy…"))
        save.setCursor(QtCore.Qt.PointingHandCursor)
        save.setStyleSheet(
            f"QPushButton{{background:{BRAND_FILL}; color:{ON_BRAND}; "
            "border-radius:3px; padding:7px 18px; font-size:12px; "
            "font-weight:600;}")
        save.clicked.connect(self._export_and_refresh)
        row.addWidget(save)
        later = QtWidgets.QPushButton(L("Not now"))
        later.setCursor(QtCore.Qt.PointingHandCursor)
        later.setStyleSheet(
            f"QPushButton{{background:transparent; color:{MUTED}; border:none;"
            "font-size:11px;}")
        later.clicked.connect(self._dismiss_backup)
        row.addWidget(later)
        row.addStretch(1)
        clay.addLayout(row)
        return card

    def _export_and_refresh(self):
        export_student(self.store, self)
        self._build_detail()

    def _dismiss_backup(self):
        self.store.dismiss_backup_nudge()
        self._build_detail()

    def _reread_card(self, bank):
        card = QtWidgets.QFrame()
        card.setObjectName("rereadCard")
        card.setStyleSheet(
            f"QFrame#rereadCard{{background:{BRASS_SOFT}; border:1px solid {BRASS};"
            "border-radius:4px;}")
        lay = QtWidgets.QHBoxLayout(card)
        lay.setContentsMargins(18, 15, 18, 15)
        lay.setSpacing(16)
        text = QtWidgets.QLabel(
            f"<div style='font-size:14px; font-weight:600; color:{NAVY};"
            f"font-family:{SERIF}'>" + L("This set can be read again") + "</div>"
            f"<div style='font-size:11px; color:{MUTED}'>"
            + L("It was imported before the reader learned to keep tables, "
                "underlined text, and hyphens. Reading the stored PDFs again fixes "
                "those. Your progress, notes, and set-aside list are kept.")
            + "</div>")
        text.setWordWrap(True)
        leading(text)
        text.setStyleSheet("border:none; background:transparent;")
        lay.addWidget(text, 1)
        btn = QtWidgets.QPushButton(L("Read again"))
        btn.setCursor(QtCore.Qt.PointingHandCursor)
        btn.setStyleSheet(
            f"QPushButton{{background:{NAVY}; color:{CARD}; border-radius:3px;"
            "padding:9px 22px; font-size:13px; font-weight:600;}")
        btn.clicked.connect(lambda: self._do_reread(bank))
        lay.addWidget(btn)
        return card

    @contextlib.contextmanager
    def _while_reading(self):
        self.setEnabled(False)
        try:
            yield
        finally:
            self.setEnabled(True)

    def _do_reread(self, bank):
        dlg = QtWidgets.QProgressDialog(L("Reading…"), None, 0, 100, self.window())
        dlg.setWindowTitle(L("Reading the stored PDFs"))
        dlg.setWindowModality(QtCore.Qt.WindowModal)
        dlg.setMinimumDuration(0)
        dlg.setValue(0)
        QtWidgets.QApplication.processEvents()

        def report(p, msg):
            dlg.setValue(int(p * 100))
            dlg.setLabelText(msg)
            QtWidgets.QApplication.processEvents()

        with self._while_reading():
            updated, warnings = self.store.reread(bank.id, progress=report)
        dlg.close()
        if updated is None:
            brand.warn(self, L("Could not read that set again"),
                       "\n".join(warnings) or L("Nothing was changed."))
            return
        self.refresh()
        say_highlights_taken_off(self, self.store)

    def _stats_row(self, bank, seen, to_review):
        row = QtWidgets.QWidget()
        row.setStyleSheet("background:transparent;")
        lay = FlowLayout(row, spacing=26)
        for value, label in ((len(bank.questions), L("questions")),
                             (bank.reading_count, L("reading & writing")),
                             (bank.math_count, L("math")),
                             (seen, L("seen")),
                             (to_review, L("to review"))):
            tile = QtWidgets.QWidget()
            tl = QtWidgets.QVBoxLayout(tile)
            tl.setContentsMargins(0, 0, 0, 0)
            tl.setSpacing(0)
            tl.addWidget(CountingLabel(
                value,
                f"<div style='font-size:26px; font-weight:600; color:{NAVY};"
                f"font-family:{NUMERALS}'>{{}}</div>"))
            cap = QtWidgets.QLabel(
                f"<div style='font-size:9px; color:{MUTED}; letter-spacing:1px'>"
                f"{label.upper()}</div>")
            cap.setStyleSheet("border:none; background:transparent;")
            tl.addWidget(cap)
            lay.addWidget(tile)
        return row

    def _rhythm_card(self):
        state = self.store.streak()
        plan = self.store.schedule()
        goal = max(1, state["target_today"] or int(plan.get("daily_target", 20)))
        done = min(state["answered_today"], goal)
        card = QtWidgets.QFrame()
        card.setObjectName("rhythmCard")
        card.setStyleSheet(
            f"QFrame#rhythmCard{{background:{CARD}; border:1px solid {HAIRLINE};"
            "border-radius:4px;}")
        lay = QtWidgets.QHBoxLayout(card)
        lay.setContentsMargins(14, 12, 14, 12)
        lay.setSpacing(12)
        met = state["met_today"] or state["is_rest_day"]
        lay.addWidget(GoalRing(done / goal, state["answered_today"], goal,
                               CORRECT if met else BRASS))

        right = QtWidgets.QWidget()
        right.setStyleSheet("background:transparent;")
        rl = QtWidgets.QVBoxLayout(right)
        rl.setContentsMargins(0, 0, 0, 0)
        rl.setSpacing(3)
        if state["is_rest_day"]:
            title = L("Rest day")
        elif state["met_today"]:
            title = L("Today's plan is done")
        else:
            title = L("Today")
        head = QtWidgets.QLabel(title)
        head.setStyleSheet(
            f"color:{CORRECT if met else NAVY}; font-size:12px; font-weight:600;"
            "border:none; background:transparent;")
        rl.addWidget(head)
        left = state["remaining_today"]
        if state["is_rest_day"]:
            line = (Lf("%d-day streak held · nothing planned today", state["current"])
                    if state["current"] else L("Nothing planned today"))
        elif state["current"] >= 2:
            line = (Lf("%1$d days in a row · %2$d to go today", state["current"], left)
                    if left else Lp(state["current"], "%d day in a row", "%d days in a row"))
        elif state["met_today"]:
            line = L("First day of a new streak")
        elif state["answered_today"]:
            line = Lf("%d more to keep today", left)
        else:
            line = Lp(goal, "Answer %d question to start a streak",
                      "Answer %d questions to start a streak")
        sub = QtWidgets.QLabel(line)
        sub.setStyleSheet(f"color:{MUTED}; font-size:10px; border:none; background:transparent;")
        rl.addWidget(sub)

        started = state.get("run_started_on")
        if state["current"] > 0 and started is not None:
            inside = [d for d in self.store.excused_days() if started <= d]
            if inside:
                excused = QtWidgets.QLabel(
                    Lp(len(inside), "Includes %d day you set aside",
                       "Includes %d days you set aside"))
                excused.setWordWrap(True)
                leading(excused)
                excused.setStyleSheet(
                    f"color:{BRASS_TEXT}; font-size:9px; border:none; background:transparent;")
                rl.addWidget(excused)

        summary = QtWidgets.QLabel(schedule_summary(plan))
        summary.setWordWrap(True)
        leading(summary)
        summary.setStyleSheet(
            f"color:{MUTED}; font-size:9px; border:none; background:transparent;")
        rl.addWidget(summary)

        edit = QtWidgets.QPushButton(L("Plan") + "…")
        edit.setCursor(QtCore.Qt.PointingHandCursor)
        edit.setStyleSheet(
            f"QPushButton{{background:{SUBTLE}; color:{NAVY}; border:none;"
            "border-radius:2px; font-size:10px; font-weight:600; padding:2px 8px;}"
            f"QPushButton:hover{{background:{PAPER_DEEP};}}")
        edit.clicked.connect(self._edit_plan)
        edit.setSizePolicy(QtWidgets.QSizePolicy.Fixed,
                           QtWidgets.QSizePolicy.Fixed)
        rl.addWidget(edit, 0, QtCore.Qt.AlignLeft)
        lay.addWidget(right, 1)
        return card

    def _edit_plan(self):
        dialog = PlanDialog(self.store, self)
        if dialog.exec() == QtWidgets.QDialog.Accepted:
            self._build_detail()

    def _plans_bar(self):
        box = QtWidgets.QWidget()
        box.setStyleSheet("background:transparent;")
        lay = QtWidgets.QVBoxLayout(box)
        lay.setContentsMargins(0, 0, 0, 0)
        lay.setSpacing(8)

        head = QtWidgets.QHBoxLayout()
        head.setContentsMargins(0, 0, 0, 0)
        head.addWidget(_label(L("Study plans")))
        head.addStretch(1)
        save = QtWidgets.QPushButton("+ " + L("Save these settings"))
        save.setFlat(True)
        save.setCursor(QtCore.Qt.PointingHandCursor)
        save.setStyleSheet(
            f"QPushButton{{border:none; background:transparent; color:{NAVY};"
            "font-size:11px; font-weight:600;}"
            f"QPushButton:hover{{color:{BRASS_TEXT};}}")
        save.clicked.connect(self._save_plan)
        head.addWidget(save)
        lay.addLayout(head)

        if not self.store.presets:
            hint = QtWidgets.QLabel(
                L("Save the settings you use most and they come back in one click."))
            hint.setWordWrap(True)
            leading(hint)
            hint.setStyleSheet(f"color:{MUTED}; font-size:11px; border:none;"
                               "background:transparent;")
            lay.addWidget(hint)
            return box

        holder = QtWidgets.QWidget()
        holder.setStyleSheet("background:transparent;")
        flow = FlowLayout(holder, spacing=8)
        for preset in self.store.presets:
            applied = (self.store.resolved_preset(preset, self.config)
                       == self.store.normalised(self.config))
            chip = QtWidgets.QWidget()
            chip.setStyleSheet(
                f"background:{NAVY if applied else SUBTLE};"
                f"border:1px solid {NAVY if applied else HAIRLINE}; border-radius:3px;")
            cl = QtWidgets.QHBoxLayout(chip)
            cl.setContentsMargins(12, 5, 8, 5)
            cl.setSpacing(6)
            name = QtWidgets.QPushButton(preset["name"])
            name.setFlat(True)
            name.setCursor(QtCore.Qt.PointingHandCursor)
            name.setStyleSheet(
                f"QPushButton{{border:none; background:transparent;"
                f"color:{CARD if applied else INK}; font-size:12px;"
                f"font-weight:{'600' if applied else '400'};}}")
            name.clicked.connect(lambda _=False, p=preset: self._apply_plan(p))
            cl.addWidget(name)
            drop = QtWidgets.QPushButton("×")
            drop.setFlat(True)
            drop.setCursor(QtCore.Qt.PointingHandCursor)
            drop.setToolTip(L("Forget this plan"))
            drop.setFixedWidth(14)
            drop.setStyleSheet(
                f"QPushButton{{border:none; background:transparent;"
                f"color:{CARD if applied else MUTED}; font-size:12px;}}")
            drop.clicked.connect(lambda _=False, p=preset: self._forget_plan(p))
            cl.addWidget(drop)
            flow.addWidget(chip)
        lay.addWidget(holder)
        return box

    def _save_plan(self):
        name, ok = QtWidgets.QInputDialog.getText(
            self, L("Name this plan"),
            L("These settings are saved under that name and can be applied to any "
            "question set in one click."), text=L("Morning drill"))
        if ok and name.strip():
            self.store.save_preset(name, self.config)
            self._build_detail()

    def _apply_plan(self, preset):
        self.config = self.store.resolved_preset(preset, self.config)
        self._remember_timer()
        self.narrowing = any(self.config.get(k) for k in FILTER_KEYS)
        self._build_detail()

    def _forget_plan(self, preset):
        self.store.delete_preset(preset.get("id"))
        self._build_detail()

    def _resume_card(self, saved):
        card = QtWidgets.QFrame()
        card.setObjectName("resumeCard")
        card.setStyleSheet(
            f"QFrame#resumeCard{{background:{BRASS_SOFT}; border:1px solid {BRASS};"
            "border-radius:4px;}")
        lay = QtWidgets.QHBoxLayout(card)
        lay.setContentsMargins(18, 15, 18, 15)
        text = QtWidgets.QLabel(
            f"<div style='font-size:10px; font-weight:600; color:{BRASS_TEXT};"
            "letter-spacing:0.6px'>" + L("You have a test in progress").upper()
            + "</div>"
            f"<div style='font-size:14px; font-weight:600; color:{NAVY};"
            f"font-family:{SERIF}'>{saved.display_title}</div>"
            f"<div style='font-size:11px; color:{MUTED}'>{saved.resume_detail()}</div>")
        text.setWordWrap(True)
        leading(text)
        text.setStyleSheet("border:none;")
        lay.addWidget(text, 1)
        resume = QtWidgets.QPushButton(L("Resume"))
        resume.setCursor(QtCore.Qt.PointingHandCursor)
        resume.setStyleSheet(
            f"QPushButton{{background:{NAVY}; color:{CARD}; border-radius:3px;"
            "padding:9px 22px; font-size:13px; font-weight:600;}")
        resume.clicked.connect(lambda: self.resume_requested.emit(saved))
        lay.addWidget(resume)
        discard = QtWidgets.QPushButton(L("Discard"))
        discard.setFlat(True)
        discard.setCursor(QtCore.Qt.PointingHandCursor)
        discard.setStyleSheet(f"QPushButton{{border:none; color:{MUTED}; font-size:12px;}}")
        discard.clicked.connect(lambda: self._discard_saved(saved.bank_id))
        lay.addWidget(discard)
        return card

    def _discard_saved(self, bank_id):
        if brand.ask(self, L("Discard this sitting?"),
                     L("It is deleted: where you had got to, the answers given in it and the time left. This cannot be undone."),
                     accept=L("Discard sitting"), destructive=True):
            self.store.discard_session(bank_id)
            self.refresh()

    def _subject_row(self, bank):
        row = QtWidgets.QWidget()
        row.setStyleSheet("background:transparent;")
        lay = QtWidgets.QHBoxLayout(row)
        lay.setContentsMargins(0, 0, 0, 0)
        lay.setSpacing(8)
        lay.addWidget(_label(L("Sections")))
        lay.addSpacing(4)
        for key, label, count in (("reading_writing", L("Reading and Writing"), bank.reading_count),
                                  ("math", L("Math"), bank.math_count)):
            lay.addWidget(self._section_chip(
                key, L(label), count,
                selected=key in self.config["subjects"], available=count > 0))
        lay.addStretch(1)
        return row

    def _section_chip(self, key, label, count, selected, available):
        button = _Clickable()
        button.setEnabled(available)
        if not available:
            fade = QtWidgets.QGraphicsOpacityEffect(button)
            fade.setOpacity(0.35)
            button.setGraphicsEffect(fade)
        button.setCursor(QtCore.Qt.PointingHandCursor)
        button.setObjectName("sectionChip")
        button.setStyleSheet(
            "QWidget#sectionChip{border-radius:3px;"
            f"background:{NAVY if selected else SUBTLE};"
            f"border:1px solid {NAVY if selected else HAIRLINE};}}")

        inner = QtWidgets.QHBoxLayout(button)
        inner.setContentsMargins(13, 6, 9, 6)
        inner.setSpacing(8)

        ink = brand.readable_ink(NAVY)
        q = QtGui.QColor(ink)
        rgb = f"{q.red()},{q.green()},{q.blue()}"
        name = QtWidgets.QLabel(label)
        name.setStyleSheet(
            f"color:{ink if selected else INK}; font-size:12px; border:none;"
            "background:transparent;"
            + ("font-weight:600;" if selected else ""))
        inner.addWidget(name)

        badge = QtWidgets.QLabel(str(count))
        badge.setAlignment(QtCore.Qt.AlignCenter)
        badge.setStyleSheet(
            f"color:{f'rgba({rgb},0.75)' if selected else MUTED};"
            f"background:{f'rgba({rgb},0.18)' if selected else BRASS_SOFT};"
            "border-radius:2px; padding:1px 6px; font-size:10px;")
        inner.addWidget(badge)

        button.clicked.connect(
            lambda k=key: self._toggle_subject(
                k, k not in self.config["subjects"]))
        return button

    def _toggle_subject(self, key, on):
        subs = set(self.config["subjects"])
        if on:
            subs.add(key)
        elif len(subs) > 1:
            subs.discard(key)
        self.config["subjects"] = sorted(subs)
        self._build_detail()

    SELECTION_MODES = ("new_first", "unseen_only", "due_for_review",
                       "weakest_skills", "review_missed", "set_aside", "all")

    def _mode_counts(self):
        return self.store.selection_counts(self.config, self.SELECTION_MODES)

    def _filter_summary(self, bank):
        parts = []
        chosen = self.config.get("assessments") or []
        if chosen:
            parts.append(chosen[0] if len(chosen) == 1 else f"{len(chosen)} assessments")
        if self.config.get("difficulties"):
            order = [d for d, _ in bank.difficulties()]
            parts.append("/".join(d for d in order if d in self.config["difficulties"]))
        for key, word in (("domains", "domains"), ("skills", "skills")):
            chosen = self.config.get(key) or []
            if len(chosen) == 1:
                parts.append(chosen[0])
            elif chosen:
                parts.append(f"{len(chosen)} {word}")
        return " · ".join(parts) if parts else L("everything")

    def _narrow_row(self, bank, fade=False):
        box = QtWidgets.QWidget()
        box.setStyleSheet("background:transparent;")
        lay = QtWidgets.QVBoxLayout(box)
        lay.setContentsMargins(0, 0, 0, 0)
        lay.setSpacing(9)

        head = brand.IconButton(
            "open" if self.narrowing else "shut",
            L("Narrow it down").upper() + "    " + self._filter_summary(bank),
            MUTED, NAVY, size=10)
        head.setFlat(True)
        head.setStyleSheet(
            f"QPushButton{{border:none; background:transparent; text-align:left;"
            f"color:{MUTED}; font-size:10px; font-weight:600; letter-spacing:1.2px;}}"
            f"QPushButton:hover{{color:{NAVY};}}")
        head.clicked.connect(self._toggle_narrowing)
        lay.addWidget(head)

        if not self.narrowing:
            return box

        subjects = set(self.config["subjects"])
        groups = []
        assessments = bank.assessments(subjects)
        if len(assessments) > 1:
            groups.append((L("Assessment"), "assessments", assessments))
        groups.append((L("Difficulty"), "difficulties",
                       bank.difficulties(subjects)))
        domains = bank.domains(subjects)
        if len(domains) > 1:
            groups.append((L("Domain"), "domains", domains))
        skills = bank.skills(subjects)
        if len(skills) > 1:
            groups.append((L("Skill"), "skills", skills))

        for title, key, tallies in groups:
            chosen = set(self.config.get(key) or ())
            cap = QtWidgets.QLabel(title + ("" if chosen else "   " + L("all")))
            cap.setStyleSheet(f"color:{INK}; font-size:11px; font-weight:500;"
                              "border:none; background:transparent;")
            lay.addWidget(cap)
            holder = QtWidgets.QWidget()
            holder.setStyleSheet("background:transparent;")
            flow = FlowLayout(holder, spacing=7)
            for label, count in tallies:
                flow.addWidget(self._chip(
                    f"{label}  ({count})", label in chosen,
                    lambda k=key, l=label: self._toggle_filter(k, l), accent=BRASS))
            lay.addWidget(holder)

        if any(self.config.get(k) for k in FILTER_KEYS):
            clear = QtWidgets.QPushButton(L("Clear all filters"))
            clear.setFlat(True)
            clear.setCursor(QtCore.Qt.PointingHandCursor)
            clear.setStyleSheet(
                f"QPushButton{{border:none; background:transparent; color:{NAVY};"
                "font-size:11px; text-align:left;}")
            clear.clicked.connect(self._clear_filters)
            lay.addWidget(clear)
        return fade_in(box) if fade else box

    def _choose_partner(self, profile_id):
        self._set("partnerProfileID", profile_id)
        self.store.set_setting("lastPartnerProfileID", profile_id)

    def _toggle_narrowing(self):
        self.narrowing = not self.narrowing
        if self._narrow_slot is None:
            self._build_detail()
            return
        self._narrow_slot.refill(fade=True)

    def _toggle_filter(self, key, label):
        chosen = set(self.config.get(key) or ())
        chosen.symmetric_difference_update({label})
        self.config[key] = sorted(chosen)
        self._narrowed()

    def _clear_filters(self):
        for key in FILTER_KEYS:
            self.config[key] = []
        self._narrowed()

    def _narrowed(self):
        if self._narrow_slot is None:
            self._build_detail()
            return
        self._narrow_slot.refill()
        if self._selection_group is not None:
            self._selection_group.set_counts(self._mode_counts())
        self._count_slot.refill()
        self._timer_slot.refill()
        self._start_slot.refill()

    def _empty_pool_reason(self, bank):
        sel = self.config["selection"]
        filtered = any(self.config.get(k) for k in FILTER_KEYS)
        if sel == "due_for_review":
            when = self.store.next_review_due(bank.id)
            if when:
                hours = max(1, int((when - time.time()) / 3600))
                unit = (Lp(hours, "%d hour", "%d hours") if hours < 48
                        else Lp(hours // 24, "%d day", "%d days"))
                return Lf("Nothing is due yet — the next question comes back in "
                          "about %@.", unit)
            return (L("Nothing is due for review yet. Answer some questions and they "
                    "come back on a widening schedule."))
        if sel == "weakest_skills":
            return L("Not enough attempts yet to say which skills are weakest. "
                     "Answer at least 5 questions in a skill and it can be ranked.")
        if sel == "set_aside":
            return L("You have not set any questions aside yet.")
        if sel == "review_missed":
            return L("Nothing to review — you have not got any of these wrong.")
        if sel == "unseen_only":
            return L("You have seen every question that matches. Try another way of choosing.")
        return (L("No questions match these filters.") if filtered
                else L("No questions match these settings yet."))

    COUNT_PRESETS = (10, 20, 22, 27, 40)

    def _count_row(self):
        row = QtWidgets.QWidget()
        row.setStyleSheet("background:transparent;")
        outer = QtWidgets.QVBoxLayout(row)
        outer.setContentsMargins(0, 0, 0, 0)
        outer.setSpacing(8)
        available = self.store.available_count(self.config)
        outer.addWidget(_label(
            L("How many questions") + "  ·  "
            + Lf("%1$d of %2$d available",
                 min(self.config["count"], available), available)))
        holder = QtWidgets.QWidget()
        holder.setStyleSheet("background:transparent;")
        lay = FlowLayout(holder, spacing=8)
        presets = self.COUNT_PRESETS
        for n in presets:
            label = {22: L("22 · math module"),
                     27: L("27 · R&W module")}.get(n, str(n)).replace("&", "&&")
            chip = self._chip(label, self.config["count"] == n and n <= available,
                              lambda v=n: self._set("count", v))
            chip.setEnabled(n <= available)
            lay.addWidget(chip)
        all_selected = (self.config["count"] >= max(available, 1)
                        and self.config["count"] not in
                        [p for p in presets if p <= available])
        lay.addWidget(self._chip(L("All"), all_selected,
                                 lambda: self._set("count", max(available, 1))))

        box = QtWidgets.QFrame()
        box.setObjectName("customCount")
        box.setAttribute(QtCore.Qt.WA_StyledBackground, True)
        box.setEnabled(available > 0)
        box_lay = QtWidgets.QHBoxLayout(box)
        box_lay.setContentsMargins(9, 5, 8, 5)
        box_lay.setSpacing(5)
        pencil = QtWidgets.QLabel(brand.ICONS["pencil"])
        pencil.setFont(QtGui.QFont(brand.ICON_FONT, 9))
        box_lay.addWidget(pencil)
        custom = _FocusLineEdit()
        custom.setAccessibleName(L("Custom"))
        custom.setValidator(QtGui.QIntValidator(0, 99999, custom))
        custom.setPlaceholderText(L("Custom"))
        custom.setFixedWidth(max(40, _placeholder_width(L("Custom"))))
        custom.setAlignment(QtCore.Qt.AlignCenter)
        box_lay.addWidget(custom)
        is_custom = self.config["count"] not in presets and not all_selected
        if is_custom:
            custom.setText(str(self.config["count"]))

        def _light(lit):
            box.setStyleSheet(
                f"QFrame#customCount{{border:{'2px' if lit else '1px'} solid "
                f"{BRASS if lit else HAIRLINE}; border-radius:3px;"
                f"background:{BRASS_SOFT if lit else SUBTLE};}}"
                "QFrame#customCount:disabled{background:transparent;}")
            pencil.setStyleSheet(
                f"color:{BRASS_TEXT if lit else MUTED}; background:transparent;"
                "border:none;")
            custom.setStyleSheet(
                "QLineEdit{border:none; background:transparent; font-size:12px;"
                f"color:{INK}; font-weight:{'600' if lit else '400'};}}")

        _light(is_custom)
        custom.focusChanged.connect(lambda on: _light(is_custom or on))
        custom.editingFinished.connect(
            lambda: self._set_custom_count(custom.text(), available))
        lay.addWidget(box)
        unit = QtWidgets.QLabel(L("questions"))
        unit.setStyleSheet(f"color:{MUTED}; font-size:11px; border:none;"
                           "background:transparent;")
        lay.addWidget(unit)
        outer.addWidget(holder)

        if len(self.config.get("subjects") or []) > 1:
            outer.addWidget(self._split_row())
        return row

    def _split_row(self):
        split = core.has_section_split(self.config)
        box = QtWidgets.QWidget()
        box.setStyleSheet("background:transparent;")
        outer = QtWidgets.QVBoxLayout(box)
        outer.setContentsMargins(0, 6, 0, 0)
        outer.setSpacing(7)
        outer.addWidget(_rule())

        head = QtWidgets.QWidget()
        head.setStyleSheet("background:transparent;")
        hl = QtWidgets.QHBoxLayout(head)
        hl.setContentsMargins(0, 0, 0, 0)
        hl.setSpacing(8)
        title = QtWidgets.QLabel(
            L("How many of each") if split else L("Mixed together"))
        title.setStyleSheet(f"color:{INK}; font-size:11px; font-weight:600;"
                            "border:none; background:transparent;")
        hl.addWidget(title)
        if not split:
            hint = QtWidgets.QLabel(L("the total is drawn from both sections"))
            hint.setStyleSheet(f"color:{MUTED}; font-size:10px; border:none;"
                               "background:transparent;")
            hl.addWidget(hint)
        hl.addStretch(1)
        toggle = QtWidgets.QPushButton(
            L("Mix them") if split else L("Choose how many of each"))
        toggle.setFlat(True)
        toggle.setCursor(QtCore.Qt.PointingHandCursor)
        toggle.setStyleSheet(f"QPushButton{{border:none; color:{BRASS_TEXT};"
                             "font-size:10px; font-weight:600;"
                             "background:transparent;}")
        toggle.clicked.connect(lambda: self._toggle_split(not split))
        hl.addWidget(toggle)
        outer.addWidget(head)

        if split:
            fields = QtWidgets.QWidget()
            fields.setStyleSheet("background:transparent;")
            fl = QtWidgets.QHBoxLayout(fields)
            fl.setContentsMargins(0, 0, 0, 0)
            fl.setSpacing(14)
            for subject, label in (("reading_writing", L("R&W")), ("math", L("Math"))):
                if subject in (self.config.get("subjects") or []):
                    fl.addWidget(self._section_count_field(subject, label))
            fl.addStretch(1)
            drawn = self.store.split_draw(self.config)
            self._split_total = QtWidgets.QLabel(
                Lp(drawn, "%d question in all", "%d questions in all"))
            self._split_total.setStyleSheet(f"color:{MUTED}; font-size:10px;"
                                            "border:none; background:transparent;")
            fl.addWidget(self._split_total)
            outer.addWidget(fields)
        return box

    def _section_count_field(self, subject, label):
        most = self.store.available_in(self.config, subject)
        value = core.section_count(self.config, subject)
        w = QtWidgets.QWidget()
        w.setStyleSheet("background:transparent;")
        row = QtWidgets.QHBoxLayout(w)
        row.setContentsMargins(0, 0, 0, 0)
        row.setSpacing(6)
        name = QtWidgets.QLabel(label)
        name.setStyleSheet(f"color:{INK}; font-size:11px; border:none;"
                           "background:transparent;")
        row.addWidget(name)
        spin = QtWidgets.QSpinBox()
        spin.setAccessibleName(label)
        spin.setRange(0, max(most, value, 1))
        spin.setValue(min(value, max(most, value, 1)))
        spin.setFixedWidth(58)
        spin.valueChanged.connect(
            lambda n, s=subject: self._section_count_typed(s, n))
        spin.editingFinished.connect(
            lambda: self._count_slot.refill() if self._count_slot else None)
        row.addWidget(framed_spin(spin))
        of = QtWidgets.QLabel(Lf("of %d", most))
        of.setStyleSheet(f"color:{MUTED}; font-size:10px; border:none;"
                         "background:transparent;")
        row.addWidget(of)
        return w

    def _section_count_typed(self, subject, n):
        core.set_section_count(self.config, subject, n)
        if getattr(self, "_split_total", None) is not None:
            drawn = self.store.split_draw(self.config)
            self._split_total.setText(
                Lp(drawn, "%d question in all", "%d questions in all"))

    def _toggle_split(self, on):
        if on:
            half = max(1, int(self.config.get("count", 20)) // 2)
            for subject in (self.config.get("subjects") or []):
                core.set_section_count(
                    self.config, subject,
                    min(half, self.store.available_in(self.config, subject)))
        else:
            core.clear_section_split(self.config)
        if self._count_slot is not None:
            self._count_slot.refill()
        else:
            self._build_detail()

    def _full_test_card(self, bank):
        readiness = self.store.full_test_readiness(self.config)
        on = bool(self.config.get("full_test"))
        is_double = bool(self.config.get("partnerProfileID"))
        allowed = readiness.is_ready and not is_double

        switch = Switch(on and allowed)
        switch.setAccessibleName(L("Sit a full test"))
        switch.setEnabled(allowed)

        def toggled(value):
            self.config["full_test"] = bool(value)
            if not value:
                self.config["adaptive"] = False
            self._build_detail()

        switch.toggled.connect(toggled)
        card, clay = _switch_card(
            L("Sit a full test"),
            Lf("%1$d Reading and Writing and %2$d Math, in four timed modules "
               "with a %3$d-minute break — %4$d minutes of testing.",
               fulltest.READING_WRITING_NEEDED, fulltest.MATH_NEEDED,
               fulltest.BREAK_MINUTES, fulltest.TOTAL_MINUTES),
            switch,
            badge=("" if allowed
                   else L("not while two of you are studying") if is_double
                   else L("not enough questions")))

        shortfall = readiness.shortfall
        if shortfall:
            note = QtWidgets.QLabel(shortfall)
            note.setWordWrap(True)
            leading(note)
            note.setStyleSheet(f"color:{MUTED}; font-size:11px; border:none;"
                               "background:transparent;")
            clay.addWidget(note)
        elif on and allowed:
            for part in fulltest.DIGITAL:
                clay.addWidget(self._test_part_row(part))
            clay.addWidget(self._adaptive_row())
            closing = QtWidgets.QLabel(
                L("Each module is timed on its own and cannot be reopened once "
                  "handed in, the same as on the real test."))
            closing.setWordWrap(True)
            leading(closing)
            closing.setStyleSheet(f"color:{MUTED}; font-size:10px; border:none;"
                                  "background:transparent;")
            clay.addWidget(closing)
        return card

    def _test_part_row(self, part):
        row = QtWidgets.QWidget()
        row.setStyleSheet("background:transparent;")
        lay = QtWidgets.QHBoxLayout(row)
        lay.setContentsMargins(0, 0, 0, 0)
        lay.setSpacing(8)

        tick = QtWidgets.QFrame()
        tick.setFixedSize(2, 13)
        tick.setStyleSheet(f"background:{BRASS}; border:none;")
        lay.addWidget(tick)

        label = QtWidgets.QLabel(
            Lf("%1$@ · %2$d questions · %3$d min",
               fulltest.section_label(part.subject), part.questions,
               part.minutes))
        label.setStyleSheet(f"color:{INK}; font-size:11px; border:none;"
                            "background:transparent;")
        lay.addWidget(label)
        lay.addStretch(1)

        if part.break_after > 0:
            after = QtWidgets.QLabel(Lf("then a %d min break", part.break_after))
            after.setStyleSheet(f"color:{BRASS_TEXT}; font-size:10px; border:none;"
                                "background:transparent;")
            lay.addWidget(after)
        return row

    def _adaptive_row(self):
        readiness = self.store.adaptive_readiness(self.config)
        box = QtWidgets.QWidget()
        box.setStyleSheet("background:transparent;")
        outer = QtWidgets.QVBoxLayout(box)
        outer.setContentsMargins(0, 6, 0, 0)
        outer.setSpacing(6)
        outer.addWidget(_rule())

        row = QtWidgets.QHBoxLayout()
        row.setSpacing(12)
        words = QtWidgets.QVBoxLayout()
        words.setSpacing(3)

        title = QtWidgets.QLabel(L("Adaptive second module"))
        title.setStyleSheet(f"color:{INK}; font-size:12px; font-weight:600;"
                            "border:none; background:transparent;")
        words.addWidget(title)

        detail = QtWidgets.QLabel(
            L("Module 1 is a mix of all three difficulties. How it goes decides "
              "whether module 2 is the easier or the harder form, the way the "
              "real test routes you.")
            if self.config.get("adaptive") else
            L("Module 2 is simply the next set of questions. Turn this on to be "
              "routed to an easier or harder module 2 by how module 1 goes."))
        detail.setWordWrap(True)
        leading(detail)
        detail.setStyleSheet(f"color:{MUTED}; font-size:10px; border:none;"
                             "background:transparent;")
        words.addWidget(detail)
        row.addLayout(words, 1)

        switch = Switch(bool(self.config.get("adaptive")) and readiness.is_ready)
        switch.setAccessibleName(L("Adaptive second module"))
        switch.setEnabled(readiness.is_ready)
        switch.toggled.connect(
            lambda value: (self._set("adaptive", bool(value))))
        row.addWidget(switch, 0, QtCore.Qt.AlignTop)
        outer.addLayout(row)

        shortfall = readiness.shortfall
        if shortfall:
            note = QtWidgets.QLabel(shortfall)
            note.setWordWrap(True)
            leading(note)
            note.setStyleSheet(f"color:{BRASS_TEXT}; font-size:10px; border:none;"
                               "background:transparent;")
            outer.addWidget(note)
        elif self.config.get("adaptive"):
            cut = QtWidgets.QLabel(Lf(
                "The routing cut is %d%% of module 1. The College Board does not "
                "publish theirs, so this one is ours.",
                int(fulltest.UPPER_THRESHOLD * 100)))
            cut.setWordWrap(True)
            leading(cut)
            cut.setStyleSheet(f"color:{MUTED}; font-size:10px; border:none;"
                              "background:transparent;")
            outer.addWidget(cut)
        return box

    def _double_card(self):
        others = [p for p in self.store.profiles.profiles
                  if p.get("id") != self.store.profile.get("id")]
        switch = Switch(bool(self.config.get("partnerProfileID")))
        switch.setAccessibleName(L("Study together"))

        def remembered():
            last = self.store.settings.get("lastPartnerProfileID")
            if any(o.get("id") == last for o in others):
                return last
            return others[0]["id"] if others else ""

        def toggled(on):
            if on:
                self.config["partnerProfileID"] = remembered()
                self.config.setdefault("doubleLayout", "turns")
            else:
                self.config["partnerProfileID"] = ""
            self._build_detail()

        switch.toggled.connect(toggled)
        card, clay = _switch_card(
            L("Study together"),
            L("Two of you, one computer, taking turns: you answer the first "
              "question, they answer the second, and so on to the end. Each "
              "answer goes into that student's own record, so neither of you "
              "ends up with the other's statistics."),
            switch)

        if self.config.get("partnerProfileID"):
            clay.addWidget(_label(L("Who is with you")))
            holder = QtWidgets.QWidget()
            holder.setStyleSheet("background:transparent;")
            row = FlowLayout(holder, spacing=8)
            for other in others:
                row.addWidget(self._chip(
                    profile_display_name(other),
                    self.config.get("partnerProfileID") == other.get("id"),
                    lambda v=other.get("id"): self._choose_partner(v)))
            clay.addWidget(holder)
            clay.addWidget(_label(L("How you want to work")))
            for key, title, detail in (
                ("turns", L("Turn about"),
                 L("One question on the screen at a time. You answer the first, "
                   "they answer the second. You both see every question, and "
                   "you can highlight and take notes.")),
                ("side_by_side", L("Side by side"),
                 L("The screen is split in two and you both work at the same "
                   "time, each on your own half of the questions. Faster, and "
                   "nobody is waiting — but each of you has half the screen, "
                   "and there are no highlights or notes in this one.")),
            ):
                radio = QtWidgets.QRadioButton(title)
                radio.setChecked(self.config.get("doubleLayout", "turns") == key)
                radio.setCursor(QtCore.Qt.PointingHandCursor)
                radio.setStyleSheet(
                    f"QRadioButton{{color:{INK}; font-size:12px;"
                    "background:transparent;}"
                    + brand.control_style("radio", BRAND_FILL, ON_BRAND,
                                          CARD, BORDER, MUTED))
                radio.toggled.connect(
                    lambda on, k=key: on and self._set("doubleLayout", k))
                clay.addWidget(radio)
                blurb2 = QtWidgets.QLabel(detail)
                blurb2.setWordWrap(True)
                leading(blurb2)
                blurb2.setContentsMargins(22, 0, 0, 6)
                blurb2.setStyleSheet(f"color:{MUTED}; font-size:10px; border:none;"
                                     "background:transparent;")
                clay.addWidget(blurb2)

            note = QtWidgets.QLabel(
                L("Everything below is yours to set as usual — how many "
                  "questions, which ones, and a clock if you want one. A full "
                  "test is the one thing a sitting for two cannot be: its "
                  "second module is chosen by how a single student did in the "
                  "first."))
            note.setWordWrap(True)
            leading(note)
            note.setStyleSheet(f"color:{BRASS_TEXT}; font-size:11px; border:none;"
                               "background:transparent;")
            clay.addWidget(note)
        return card

    def _timer_row(self):
        row = QtWidgets.QWidget()
        row.setStyleSheet("background:transparent;")
        outer = QtWidgets.QVBoxLayout(row)
        outer.setContentsMargins(0, 0, 0, 0)
        outer.setSpacing(8)
        holder = QtWidgets.QWidget()
        holder.setStyleSheet("background:transparent;")
        lay = FlowLayout(holder, spacing=8)
        outer.addWidget(holder)
        clock = QtWidgets.QWidget()
        clock.setStyleSheet("background:transparent;")
        clock_row = QtWidgets.QHBoxLayout(clock)
        clock_row.setContentsMargins(0, 0, 0, 0)
        clock_row.setSpacing(9)
        caption = QtWidgets.QLabel(L("Use a timer").upper())
        caption.setStyleSheet(
            f"color:{MUTED}; font-size:10px; font-weight:600;"
            "letter-spacing:1.5px; border:none; background:transparent;")
        clock_row.addWidget(caption)
        pill = Switch(bool(self.config["timed"]))
        pill.setAccessibleName(L("Use a timer"))
        pill.toggled.connect(lambda on: self._set("timed", on))
        clock_row.addWidget(pill)
        lay.addWidget(clock)
        if self.config["timed"]:
            presets = (10, 20, 32, 35, 45, 70)
            for m in presets:
                lay.addWidget(self._chip(Lf("%d min", m),
                                         self.config["minutes"] == m,
                                         lambda v=m: self._set("minutes", v)))
            custom = QtWidgets.QLineEdit()
            custom.setAccessibleName(L("Custom"))
            custom.setValidator(QtGui.QIntValidator(0, 999, custom))
            custom.setPlaceholderText(L("Custom"))
            custom.setFixedWidth(max(58, _placeholder_width(L("Custom")) + 10))
            custom.setAlignment(QtCore.Qt.AlignCenter)
            is_custom = self.config["minutes"] not in presets
            if is_custom:
                custom.setText(str(self.config["minutes"]))
            custom.setStyleSheet(
                f"QLineEdit{{border:1px solid {BRASS if is_custom else HAIRLINE};"
                f"background:{BRASS_SOFT if is_custom else SUBTLE}; border-radius:3px;"
                f"padding:5px; font-size:12px; color:{INK};}}")
            custom.editingFinished.connect(
                lambda: self._set_custom_minutes(custom.text()))
            lay.addWidget(custom)
            unit = QtWidgets.QLabel(L("min"))
            unit.setStyleSheet(f"color:{MUTED}; font-size:11px; border:none;"
                               "background:transparent;")
            lay.addWidget(unit)
        if not self.config["timed"]:
            return row

        box = QtWidgets.QWidget()
        box.setStyleSheet("background:transparent;")
        bl = QtWidgets.QVBoxLayout(box)
        bl.setContentsMargins(0, 0, 0, 0)
        bl.setSpacing(6)
        bl.addWidget(row)

        rw, math, minutes = self.store.planned_sitting(self.config)
        total = rw + math
        matches = self.config["minutes"] == minutes
        pace_row = QtWidgets.QHBoxLayout()
        pace_row.setContentsMargins(0, 0, 0, 0)
        pace_row.setSpacing(10)
        chip = self._chip(L("Matching the real test") if matches else L("Match the real test"),
                          matches, lambda m=minutes: self._set("minutes", m), accent=BRASS)
        chip.setEnabled(total > 0)
        pace_row.addWidget(chip)
        if total > 0:
            each = describe_pace(self.config["minutes"] * 60 / total)
            text = (Lf("%@ a question, the pace the test sets", each) if matches
                    else Lf("%1$d min is %2$@ a question; the test would allow "
                            "%3$d min for these %4$d",
                            self.config["minutes"], each, minutes, total))
            note = QtWidgets.QLabel(text)
            note.setWordWrap(True)
            leading(note)
            note.setStyleSheet(
                f"color:{BRASS_TEXT if matches else MUTED}; font-size:11px; border:none;"
                "background:transparent;")
            pace_row.addWidget(note, 1)
        pace_row.addStretch(0)
        bl.addLayout(pace_row)

        rule = QtWidgets.QLabel(
            Lf("The real test allows 32 minutes for 27 Reading and Writing "
               "questions (%1$@ each) and 35 for 22 Math (%2$@ each).",
               describe_pace(PACE_READING_WRITING), describe_pace(PACE_MATH)))
        rule.setWordWrap(True)
        leading(rule)
        rule.setStyleSheet(f"color:{MUTED}; font-size:11px; border:none;"
                           "background:transparent;")
        bl.addWidget(rule)
        return box

    def _sitting_name_row(self):
        row = QtWidgets.QWidget()
        row.setStyleSheet("background:transparent;")
        lay = QtWidgets.QHBoxLayout(row)
        lay.setContentsMargins(0, 0, 0, 0)
        lay.setSpacing(10)
        lay.addWidget(_label(L("Name this sitting")))
        name = QtWidgets.QLineEdit(str(self.config.get("sitting_name", "")))
        name.setAccessibleName(L("Name this sitting"))
        placeholder = self._name_placeholder()
        name.setPlaceholderText(L("Optional") if placeholder == L("Name this sitting") else placeholder)
        name.setClearButtonEnabled(True)
        name.setMaxLength(60)
        name.setFixedWidth(210)
        name.setStyleSheet(
            f"QLineEdit{{background:{SUBTLE}; color:{INK}; border:1px solid "
            f"{HAIRLINE}; border-radius:3px; padding:8px 10px; font-size:12px;}}"
            f"QLineEdit:focus{{border:1px solid {BRASS};}}"
            f"QLineEdit:disabled{{color:{MUTED};}}")
        name.textChanged.connect(
            lambda text: self.config.__setitem__("sitting_name", text))
        lay.addWidget(name)
        lay.addStretch(1)
        return row

    def _start_row(self, bank):
        row = QtWidgets.QWidget()
        row.setStyleSheet("background:transparent;")
        start_row = QtWidgets.QHBoxLayout(row)
        start_row.setContentsMargins(0, 0, 0, 0)
        available = self.store.available_count(self.config)
        full = bool(self.config.get("full_test"))
        if full:
            available = self.store.full_test_readiness(self.config).is_ready and 1 or 0
            summary = QtWidgets.QLabel(Lf(
                "%1$d modules · %2$d questions · %3$d min · every module timed as on the test",
                len(fulltest.DIGITAL), fulltest.READING_WRITING_NEEDED + fulltest.MATH_NEEDED,
                fulltest.TOTAL_MINUTES))
            summary.setWordWrap(True)
            leading(summary)
            summary.setStyleSheet(f"color:{MUTED}; font-size:11px; border:none;"
                                  "background:transparent;")
            start_row.addWidget(summary, 1)
        elif available == 0:
            why = QtWidgets.QLabel(self._empty_pool_reason(bank))
            why.setWordWrap(True)
            leading(why)
            why.setStyleSheet(f"color:{BRASS_TEXT}; font-size:11px; border:none;"
                              "background:transparent;")
            start_row.addWidget(why, 1)
        else:
            rw, math, _ = self.store.planned_sitting(self.config)
            total = rw + math
            parts = [Lp(total, "%d question", "%d questions")]
            if rw and math:
                parts.append(Lf("%1$d R&W · %2$d math", rw, math))
            if any(self.config.get(k) for k in FILTER_KEYS):
                parts.append(self._filter_summary(bank))
            parts.append(Lf("%d min", self.config["minutes"])
                         if self.config["timed"] else L("untimed"))
            if self.config["grading"] == "immediate":
                parts.append(L("graded as you go"))
            chosen = self.config.get("partnerProfileID")
            partner = self.store.partner(chosen) if chosen else None
            if partner is not None:
                parts.append(Lf("with %@", profile_display_name(partner)))
            summary = QtWidgets.QLabel(" · ".join(parts))
            summary.setWordWrap(True)
            leading(summary)
            summary.setStyleSheet(f"color:{MUTED}; font-size:11px; border:none;"
                                  "background:transparent;")
            start_row.addWidget(summary, 1)
        start_row.addStretch(0)


        start = QtWidgets.QPushButton(L("Begin full test") if full else L("Start practice"))
        start.setEnabled(available > 0)
        start.setCursor(QtCore.Qt.PointingHandCursor)
        start.setStyleSheet(
            f"QPushButton{{background:{NAVY}; color:{CARD}; border-radius:3px;"
            "padding:11px 28px; font-size:14px; font-weight:600;}"
            "QPushButton:hover{background:#121E37;}"
            f"QPushButton:disabled{{background:{SUBTLE}; color:{MUTED};}}")
        start.clicked.connect(self._start)
        start_row.addWidget(start)
        return row

    def _name_placeholder(self):
        chosen = list(self.config.get("subjects") or [])
        if len(chosen) != 1:
            return L("Name this sitting")
        label = L("Math") if chosen[0] == "math" else L("Reading and Writing")
        return Lf("%@ practice", label)

    def _set_custom_count(self, text, available):
        digits = "".join(ch for ch in text if ch.isdigit())
        if digits:
            self._set("count", max(1, min(int(digits), max(available, 1))))

    def _set_custom_minutes(self, text):
        digits = "".join(ch for ch in text if ch.isdigit())
        if digits:
            self._set("minutes", max(1, min(int(digits), 360)))

    def _chip(self, label, selected, slot, accent=None):
        tint = accent or NAVY
        ink = brand.readable_ink(tint)
        b = QtWidgets.QPushButton(label)
        b.setCursor(QtCore.Qt.PointingHandCursor)
        b.setStyleSheet(
            f"QPushButton{{background:{tint if selected else SUBTLE};"
            f"color:{ink if selected else INK}; border:1px solid "
            f"{tint if selected else HAIRLINE}; border-radius:3px;"
            f"padding:6px 14px; font-size:12px;"
            f"font-weight:{'600' if selected else '400'};}}"
            f"QPushButton:hover{{background:{tint if selected else PAPER_DEEP};}}")
        b.clicked.connect(lambda: slot())
        return b

    def _set_aside_card(self, bank):
        count = self.store.set_aside_count(bank.id)
        if count == 0:
            return None
        card, lay = _card(L("Set aside for later"))
        row = QtWidgets.QWidget()
        row.setStyleSheet("background:transparent;")
        rl = QtWidgets.QHBoxLayout(row)
        rl.setContentsMargins(0, 0, 0, 0)
        rl.setSpacing(16)
        big = QtWidgets.QLabel(
            f"<span style='font-size:26px; font-weight:600; color:{BRASS_TEXT};"
            f"font-family:{NUMERALS}'>{count}</span>")
        rl.addWidget(big)
        text = QtWidgets.QLabel(
            f"<div style='font-size:13px; font-weight:600; color:{INK}'>"
            + Lp(count, "question kept back", "questions kept back")
            + "</div>"
            f"<div style='font-size:11px; color:{MUTED}'>"
            + L("Set aside while you were practicing, waiting for you to come "
                "back to them.")
            + "</div>")
        text.setWordWrap(True)
        leading(text)
        rl.addWidget(text, 1)
        practise = QtWidgets.QPushButton(L("Practice these"))
        practise.setCursor(QtCore.Qt.PointingHandCursor)
        practise.setStyleSheet(
            f"QPushButton{{background:{NAVY}; color:{CARD}; border-radius:3px;"
            "padding:9px 22px; font-size:13px; font-weight:600;}")
        practise.clicked.connect(lambda: self._practise_set_aside(bank, count))
        rl.addWidget(practise)
        lay.addWidget(row)

        lay.addWidget(_rule())
        actions = QtWidgets.QWidget()
        actions.setStyleSheet("background:transparent;")
        al = QtWidgets.QHBoxLayout(actions)
        al.setContentsMargins(0, 0, 0, 0)
        for label, slot, colour in (
                (L("Export as PDF…"), lambda: self._export_set_aside(bank), NAVY),
                (L("Empty the list"), lambda: self._clear_set_aside(bank), WRONG)):
            b = QtWidgets.QPushButton(label)
            b.setFlat(True)
            b.setCursor(QtCore.Qt.PointingHandCursor)
            b.setStyleSheet(f"QPushButton{{border:none; color:{colour}; font-size:11px;}}")
            b.clicked.connect(slot)
            al.addWidget(b)
        al.addStretch(1)
        lay.addWidget(actions)
        return card

    def _practise_set_aside(self, bank, count):
        cfg = dict(self.config)
        cfg["selection"] = "set_aside"
        cfg["count"] = count
        cfg["subjects"] = ["math", "reading_writing"]
        core.clear_section_split(cfg)
        self.start_requested.emit(cfg)

    def _export_set_aside(self, bank):
        questions = self.store.set_aside_questions(bank.id)
        if not questions:
            return
        dest, _ = QtWidgets.QFileDialog.getSaveFileName(
            self, L("Export the questions you set aside"),
            brand.dialog_path(f"SAT set aside - {bank.name}.pdf"), "PDF files (*.pdf)")
        if not dest:
            return
        brand.remember_folder(dest)
        try:
            exporter.export_missed(
                questions, self.store.images_dir(bank.id), dest,
                Lf("%1$d questions set aside from %2$@",
                   len(questions), bank.name),
                title=L("SAT Practice — Set Aside"))
            os.makedirs(self.store.exports_dir(bank.id), exist_ok=True)
            import shutil
            shutil.copy2(dest, os.path.join(self.store.exports_dir(bank.id),
                                            os.path.basename(dest)))
        except Exception as e:
            brand.warn(self, L("Could not export"), brand.failure_hint(e), detail=str(e))
            return
        self._build_detail()

    def _clear_set_aside(self, bank):
        if brand.ask(
                self, L("Empty the set-aside list?"),
                L("The questions stay in the bank and your progress is untouched; "
                  "only the list of ones you kept back is cleared."),
                accept=L("Empty it"), destructive=True):
            self.store.clear_set_aside(bank.id)
            self._build_detail()

    def _files_card(self, bank):
        card, lay = _card(L("PDFs"))
        files = self.store.stored_files(bank.id)
        if not files:
            empty = QtWidgets.QLabel(L("No PDFs stored for this set yet."))
            empty.setStyleSheet(f"color:{MUTED}; font-size:12px; border:none;")
            lay.addWidget(empty)
            return card
        for f in files:
            lay.addWidget(self._file_row(f))
        return card

    def _file_row(self, f):
        row = QtWidgets.QWidget()
        row.setStyleSheet("background:transparent;")
        lay = QtWidgets.QHBoxLayout(row)
        lay.setContentsMargins(0, 4, 0, 4)
        kind = (L("Imported question bank") if f["kind"] == "source"
                else L("Review export"))
        size = file_size(f["bytes"])
        when = i18n.stamp(f["modified"])
        label = QtWidgets.QLabel(f"<b>{escape(breakable(f['name']))}</b><br>"
                                 f"<span style='color:{MUTED}'>{kind} · {size} · {when}</span>")
        label.setWordWrap(True)
        leading(label, rich=True)
        label.setStyleSheet(f"color:{INK}; font-size:12px; border:none;")
        lay.addWidget(label, 1)
        for text, slot, colour in (
                (L("Open"), lambda: self._open(f), NAVY),
                (L("Save a copy…"), lambda: self._save_copy(f), NAVY),
                (L("Delete"), lambda: self._delete_file(f), WRONG)):
            b = QtWidgets.QPushButton(text)
            b.setFlat(True)
            b.setCursor(QtCore.Qt.PointingHandCursor)
            b.setStyleSheet(f"QPushButton{{border:none; color:{colour}; font-size:11px;}}")
            b.clicked.connect(slot)
            lay.addWidget(b)
        return row

    def _open(self, f):
        QtGui.QDesktopServices.openUrl(QtCore.QUrl.fromLocalFile(f["path"]))

    def _save_copy(self, f):
        dest, _ = QtWidgets.QFileDialog.getSaveFileName(
            self, L("Save a copy of this PDF"), brand.dialog_path(f["name"]),
            "PDF files (*.pdf)")
        if not dest:
            return
        brand.remember_folder(dest)
        try:
            import shutil
            shutil.copy2(f["path"], dest)
        except OSError as e:
            brand.warn(self, L("Could not save"), brand.failure_hint(e), detail=str(e))

    def _delete_file(self, f):
        note = (L("The questions already imported from it stay, and any copy "
                  "you keep elsewhere is untouched.") if f["kind"] == "source"
                else L("Copies you saved elsewhere are untouched."))
        if brand.ask(
                self, L("Delete this PDF?"),
                Lf("“%@” will be removed from this app.", f["name"])
                + "\n\n" + note,
                accept=L("Delete"), destructive=True):
            try:
                os.remove(f["path"])
            except OSError:
                pass
            self._build_detail()

    def _start(self):
        cfg = dict(self.config)
        cfg["count"] = min(cfg["count"], max(1, self.store.available_count(cfg)))
        self.start_requested.emit(cfg)


def _percent(correct, total):
    if not total:
        return "—"
    return f"{int(correct * 100 / total + 0.5)}%"


class ReviewScreen(QtWidgets.QWidget):
    done = QtCore.Signal()
    article_requested = QtCore.Signal(str)
    practise_again = QtCore.Signal(dict)

    def __init__(self, store: Store, session, parent=None):
        super().__init__(parent)
        self.store = store
        self.session = session
        self.body_size = max(11, ui_chosen_body_size() - 2)
        self.setObjectName("reviewScreen")
        self.setStyleSheet(f"QWidget#reviewScreen{{background:{PAPER};}}")
        self.setFocusPolicy(QtCore.Qt.StrongFocus)
        self._age = QtCore.QElapsedTimer()

        root = QtWidgets.QVBoxLayout(self)
        root.setContentsMargins(0, 0, 0, 0)
        root.setSpacing(0)
        root.addWidget(self._header())

        area = QtWidgets.QScrollArea()
        area.setWidgetResizable(True)
        area.setFrameShape(QtWidgets.QFrame.NoFrame)
        area.verticalScrollBar().setStyleSheet(SCROLLBAR)
        holder = QtWidgets.QWidget()
        holder.setObjectName("reviewList")
        holder.setStyleSheet(f"QWidget#reviewList{{background:{PAPER};}}")
        self.list_layout = QtWidgets.QVBoxLayout(holder)
        self.list_layout.setContentsMargins(26, 16, 26, 16)
        self.list_layout.setSpacing(10)
        self._fill_list()
        self.list_layout.addStretch(1)
        area.setWidget(holder)
        root.addWidget(area, 1)
        root.addWidget(self._footer())

    def _header(self):
        bar = QtWidgets.QWidget()
        bar.setObjectName("resultsHeader")
        bar.setStyleSheet(
            f"QWidget#resultsHeader{{background:{CARD}; border-bottom:1px solid {HAIRLINE};}}")
        lay = QtWidgets.QHBoxLayout(bar)
        lay.setContentsMargins(32, 24, 32, 24)
        total = len(self.session.questions)
        correct = self.session.correct_count
        heading = QtWidgets.QWidget()
        hl = QtWidgets.QVBoxLayout(heading)
        hl.setContentsMargins(0, 0, 0, 0)
        hl.setSpacing(0)
        t = QtWidgets.QLabel(L("Test complete") if fulltest.is_full_test(self.session)
                             else L("Section complete"))
        t.setStyleSheet(
            f"color:{NAVY}; font-size:25px; font-weight:600; font-family:{SERIF};")
        hl.addWidget(t)
        hl.addSpacing(9)
        hl.addWidget(_rule(brass=True, width=40))
        hl.addSpacing(9)
        sub = QtWidgets.QLabel(self.session.bank_name)
        sub.setStyleSheet(f"color:{MUTED}; font-size:11px;")
        hl.addWidget(sub)
        lay.addWidget(heading, 1)
        if self.session.is_double:
            tiles = []
            for seat, row in enumerate(self.session.double_scores()):
                accents = self.session.turn_accents
                index = accents[seat] if seat < len(accents) else seat
                tiles.append((f"{row['correct']}/{row['answered']}", row["name"], NAVY,
                              profile_colour(index)))
        else:
            tiles = [
                (f"{correct}/{total}",
                 f"{_percent(correct, total)} {L('correct')}", CORRECT, None),
                (str(total - self.session.answered_count), L("left blank"), MUTED, None)]
        lay.addWidget(self._sizing_buttons())
        for value, label, colour, accent in tiles:
            dot = (f"<span style='color:{accent}; font-size:11px'>●</span>&nbsp;"
                   if accent else "")
            tile = QtWidgets.QLabel(
                f"<div style='font-size:29px; font-weight:600; color:{colour};"
                f"font-family:{NUMERALS}'>{value}</div>"
                f"<div style='font-size:9px; color:{MUTED}; letter-spacing:1px'>"
                f"{dot}{label.upper()}</div>")
            tile.setAlignment(QtCore.Qt.AlignCenter)
            tile.setMinimumWidth(96)
            lay.addWidget(tile)
        return bar

    def _sizing_buttons(self):
        holder = QtWidgets.QWidget()
        holder.setStyleSheet("background:transparent;")
        row = QtWidgets.QHBoxLayout(holder)
        row.setContentsMargins(0, 0, 0, 0)
        row.setSpacing(14)
        for text, delta, tip in (("A-", -1, L("Smaller text")),
                                 ("A+", 1, L("Larger text"))):
            b = QtWidgets.QPushButton(text)
            b.setFlat(True)
            b.setToolTip(tip)
            b.setCursor(QtCore.Qt.PointingHandCursor)
            b.setStyleSheet(
                f"QPushButton{{border:none; color:{NAVY}; font-size:11px;"
                "background:transparent;}")
            b.clicked.connect(lambda _=False, d=delta: self.zoom_by(d))
            row.addWidget(b)
        return holder

    def _fill_list(self):
        images = self.store.images_dir(self.session.bank_id)
        for i, (q, a) in enumerate(zip(self.session.questions, self.session.attempts)):
            ok = is_correct(q, a.response)
            card = QtWidgets.QFrame()
            card.setObjectName("resultCard")
            card.setStyleSheet(
                f"QFrame#resultCard{{background:{CARD}; border:1px solid {HAIRLINE};"
                "border-radius:4px;}")
            lay = QtWidgets.QVBoxLayout(card)
            lay.setContentsMargins(14, 12, 14, 12)

            who = ""
            if self.session.is_double:
                seat = self.session.turn(i)
                accents = self.session.turn_accents
                index = accents[seat] if seat < len(accents) else seat
                tint = profile_colour(index)
                who = (f"<span style='background:{tint}; color:{brand.on_fill(tint)}; font-size:9px;"
                       f"font-weight:600'>&nbsp;{escape(self.session.turn_name(i))}&nbsp;"
                       "</span> &nbsp; ")
            head = QtWidgets.QLabel(
                "<b>" + Lf("Question %d", i + 1) + "</b> &nbsp; " + who
                + f"<span style='color:{CORRECT if ok else WRONG}'>"
                + (L("Correct") if ok else L("Incorrect")) + "</span><br>"
                f"<span style='color:{MUTED}; font-size:11px'>"
                f"{' · '.join(x for x in (q.test, q.domain, q.skill, q.difficulty) if x)}</span><br>"
                "<span style='font-size:11px'>" + L("Your answer:") + " "
                f"<b style='color:{CORRECT if ok else WRONG}'>"
                + (a.response if a.answered else L("blank")) + "</b>"
                + ("" if ok else " &nbsp; " + L("Correct:")
                   + f" <b style='color:{CORRECT}'>{q.correct_answer}</b>")
                + "</span>")
            head.setStyleSheet(f"color:{INK}; font-size:13px; border:none;")
            head.setWordWrap(True)
            leading(head, rich=True)
            top = QtWidgets.QWidget()
            top.setStyleSheet("background:transparent;")
            tl = QtWidgets.QHBoxLayout(top)
            tl.setContentsMargins(0, 0, 0, 0)
            tl.addWidget(head, 1)
            tl.addWidget(self._aside_button(q.id))
            lay.addWidget(top)

            if not ok:
                if q.prompt or q.rationale:
                    paper = brand.live_palette(paper=True)
                    sheet = QtWidgets.QWidget()
                    sheet.setObjectName("reviewSheet")
                    sheet.setStyleSheet(
                        f"QWidget#reviewSheet{{background:{paper['CANVAS']};"
                        "border-radius:6px;}")
                    sl = QtWidgets.QVBoxLayout(sheet)
                    sl.setContentsMargins(14, 12, 14, 12)
                    sl.setSpacing(8)
                    points = widest_region(list(q.prompt) + list(q.rationale))
                    if q.prompt:
                        sl.addWidget(Blocks(q.prompt, images, self.body_size,
                                            question_points=points))
                    if q.rationale:
                        why = QtWidgets.QLabel(L("Why"))
                        why.setStyleSheet(
                            f"color:{paper['MUTED']}; font-size:12px;"
                            "font-weight:600; border:none;")
                        sl.addWidget(why)
                        sl.addWidget(Blocks(q.rationale, images,
                                            max(11, self.body_size - 1),
                                            question_points=points))
                    lay.addWidget(sheet)
                link = self._article_link(q.skill)
                if link is not None:
                    lay.addWidget(link)
            self.list_layout.addWidget(card)

    def _article_link(self, skill):
        if not skill:
            return None
        from .learn import ArticleLink
        link = ArticleLink.create(skill)
        if link is None:
            return None
        link.opened.connect(self.article_requested.emit)
        return link

    def _aside_button(self, qid):
        on = self.store.is_set_aside(self.session.bank_id, qid)
        b = brand.IconButton("tray", L("Set aside"),
                             BRASS if on else MUTED, BRASS, size=11)
        b.setFlat(True)
        b.setToolTip(L("Keep this question to look at again at the end of your study time"))
        b.setStyleSheet(
            f"QPushButton{{border:none; font-size:11px; background:transparent;"
            f"color:{BRASS_TEXT if on else MUTED};"
            f"font-weight:{'600' if on else '400'};}}")
        b.clicked.connect(lambda: self._toggle_aside(qid))
        return b

    def zoom_by(self, delta):
        self.body_size = (REVIEW_BODY_PT if delta == 0
                          else max(11, min(24, self.body_size + delta)))
        self._rebuild_list()

    def _toggle_aside(self, qid):
        self.store.toggle_set_aside(self.session.bank_id, qid)
        self._rebuild_list()

    def _rebuild_list(self):
        while self.list_layout.count():
            item = self.list_layout.takeAt(0)
            if item.widget():
                item.widget().deleteLater()
        self._fill_list()
        self.list_layout.addStretch(1)

    def _footer(self):
        bar = QtWidgets.QWidget()
        bar.setObjectName("resultsFooter")
        bar.setStyleSheet(
            f"QWidget#resultsFooter{{background:{CARD}; border-top:1px solid {HAIRLINE};}}")
        lay = QtWidgets.QHBoxLayout(bar)
        lay.setContentsMargins(26, 12, 26, 12)
        lay.addStretch(1)

        done = QtWidgets.QPushButton(L("Done"))
        done.setFlat(True)
        done.setCursor(QtCore.Qt.PointingHandCursor)
        done.setStyleSheet(f"QPushButton{{border:none; color:{INK}; font-size:13px;}}")
        done.clicked.connect(self.done.emit)
        lay.addWidget(done)

        missed = self.session.missed
        aside_all = QtWidgets.QPushButton(self._aside_all_title())
        aside_all.setEnabled(bool(missed))
        aside_all.setCursor(QtCore.Qt.PointingHandCursor)
        aside_all.setStyleSheet(
            f"QPushButton{{background:{SUBTLE}; color:{INK}; border:1px solid {HAIRLINE};"
            "border-radius:3px; padding:8px 18px; font-size:13px; font-weight:600;}"
            f"QPushButton:disabled{{color:{MUTED};}}")
        aside_all.clicked.connect(self._toggle_all_missed)
        lay.addWidget(aside_all)
        self._aside_all_btn = aside_all

        export_btn = QtWidgets.QPushButton(L("Export missed questions as PDF…"))
        export_btn.setEnabled(bool(missed))
        export_btn.setCursor(QtCore.Qt.PointingHandCursor)
        export_btn.setStyleSheet(
            f"QPushButton{{border:1px solid {NAVY}; color:{NAVY}; border-radius:3px;"
            "padding:8px 20px; font-size:13px; font-weight:600; background:transparent;}"
            f"QPushButton:hover{{background:{BRASS_SOFT};}}"
            f"QPushButton:disabled{{border-color:{HAIRLINE}; color:{MUTED};}}")
        export_btn.clicked.connect(self._export)
        lay.addWidget(export_btn)

        again = QtWidgets.QPushButton(L("Practice these again"))
        again.setEnabled(bool(missed))
        again.setCursor(QtCore.Qt.PointingHandCursor)
        again.setStyleSheet(
            f"QPushButton{{background:{NAVY}; color:{CARD}; border-radius:3px;"
            "padding:9px 22px; font-size:13px; font-weight:600;}"
            f"QPushButton:disabled{{background:{SUBTLE}; color:{MUTED};}}")
        again.clicked.connect(self._again)
        for button in (done, aside_all, export_btn, again):
            button.setAutoDefault(False)
            button.setDefault(False)
            button.installEventFilter(self)
        lay.addWidget(again)
        return bar

    def _all_missed_set_aside(self):
        missed = self.session.missed
        return bool(missed) and all(
            self.store.is_set_aside(self.session.bank_id, q.id) for q in missed)

    def _aside_all_title(self):
        return (L("Remove these from set aside") if self._all_missed_set_aside()
                else L("Set aside all I got wrong"))

    def _toggle_all_missed(self):
        put_back = self._all_missed_set_aside()
        for q in self.session.missed:
            if self.store.is_set_aside(self.session.bank_id, q.id) == put_back:
                self.store.toggle_set_aside(self.session.bank_id, q.id)
        self._aside_all_btn.setText(self._aside_all_title())
        self._rebuild_list()

    def _export_subtitle(self):
        missed = self.session.missed
        answered = sum(1 for a in self.session.attempts if a.answered)
        return " · ".join([
            Lp(len(missed), "%d question to review", "%d questions to review"),
            Lf("from %@", self.session.bank_name),
            Lf("%1$d/%2$d correct", self.session.correct_count, answered),
            i18n.long_date()])

    def _export(self):
        missed = self.session.missed
        default = f"SAT review - {self.session.bank_name}.pdf"
        dest, _ = QtWidgets.QFileDialog.getSaveFileName(
            self, L("Export missed questions"), brand.dialog_path(default),
            "PDF files (*.pdf)")
        if not dest:
            return
        brand.remember_folder(dest)
        subtitle = self._export_subtitle()
        try:
            images = self.store.images_dir(self.session.bank_id)
            exporter.export_missed(missed, images, dest, subtitle)
            os.makedirs(self.store.exports_dir(self.session.bank_id), exist_ok=True)
            import shutil
            shutil.copy2(dest, os.path.join(self.store.exports_dir(self.session.bank_id),
                                            os.path.basename(dest)))
        except Exception as e:
            brand.warn(self, L("Could not export"), brand.failure_hint(e), detail=str(e))
            return
        brand.tell(
            self, L("Exported"),
            Lp(len(missed), "Saved %d question", "Saved %d questions") + "."
            + "\n\n"
            + Lf("You can open or print this PDF, and you can import it back "
                 "into %@ to practice these questions again.", brand.APP_NAME))

    SETTLE_MS = 700

    def showEvent(self, event):
        super().showEvent(event)
        if not self._age.isValid():
            self._age.start()

    def _too_soon(self, event):
        return (event.key() in (QtCore.Qt.Key_Return, QtCore.Qt.Key_Enter)
                and self._age.isValid()
                and self._age.elapsed() < self.SETTLE_MS)

    def eventFilter(self, watched, event):
        if event.type() == QtCore.QEvent.KeyPress and self._too_soon(event):
            return True
        return super().eventFilter(watched, event)

    def keyPressEvent(self, event):
        if self._too_soon(event):
            event.accept()
            return
        super().keyPressEvent(event)

    def _again(self):
        cfg = dict(self.session.config)
        cfg["selection"] = "review_missed"
        cfg["count"] = len(self.session.missed)
        self.practise_again.emit(cfg)


class PlanDialog(QtWidgets.QDialog):

    def __init__(self, store, parent=None):
        super().__init__(parent)
        brand.as_sheet(self, parent)
        self.store = store
        self.plan = schedule_defaults(store.settings.get("schedule"))
        self.setWindowTitle(L("Study plan"))
        self.setModal(True)
        self.setStyleSheet(f"QDialog{{background:{PAPER};}}")

        lay = QtWidgets.QVBoxLayout(self)
        lay.setContentsMargins(22, 20, 22, 18)
        lay.setSpacing(14)
        _title = QtWidgets.QLabel(L("Study plan"))
        _title.setStyleSheet(
            f"color:{NAVY}; font-size:15px; font-weight:600;"
            f"font-family:{SERIF}; background:transparent; border:none;")
        lay.addWidget(_title)
        lay.addSpacing(12)

        self.enabled = QtWidgets.QCheckBox(L("Follow a study plan"))
        self.enabled.setChecked(bool(self.plan["enabled"]))
        self.enabled.setStyleSheet(
            f"QCheckBox{{color:{INK}; font-size:13px; font-weight:600;}}"
            + brand.control_style("check", BRAND_FILL, ON_BRAND,
                                  CARD, BORDER, MUTED))
        self.enabled.toggled.connect(self._refresh)
        lay.addWidget(self.enabled)

        self.body = QtWidgets.QWidget()
        body = QtWidgets.QVBoxLayout(self.body)
        body.setContentsMargins(0, 0, 0, 0)
        body.setSpacing(12)

        body.addWidget(_label(L("Days")))
        days = QtWidgets.QHBoxLayout()
        days.setSpacing(5)
        self.day_buttons = {}
        for weekday in WEEKDAY_ORDER:
            button = QtWidgets.QPushButton(weekday_initial(weekday))
            button.setCheckable(True)
            button.setChecked(weekday in self.plan["days"])
            button.setFixedSize(32, 26)
            button.setCursor(QtCore.Qt.PointingHandCursor)
            button.setStyleSheet(
                f"QPushButton{{border:1px solid {HAIRLINE}; background:{SUBTLE};"
                f"color:{MUTED}; font-size:11px;}}"
                f"QPushButton:checked{{background:{NAVY}; color:{CARD};"
                "font-weight:600; border:1px solid transparent;}")
            self.day_buttons[weekday] = button
            days.addWidget(button)
        days.addStretch(1)
        body.addLayout(days)

        target_row = QtWidgets.QHBoxLayout()
        target_row.setSpacing(10)
        target_row.addWidget(_label(L("Questions a day")))
        self.target = QtWidgets.QSpinBox()
        self.target.setAccessibleName(L("Questions a day"))
        self.target.setRange(1, 200)
        self.target.setValue(int(self.plan["daily_target"]))
        self.target.setStyleSheet(f"font-size:12px; color:{INK};")
        target_row.addWidget(self.target)
        target_row.addStretch(1)
        body.addLayout(target_row)

        self.reminders = QtWidgets.QCheckBox(L("Remind me"))
        self.reminders.setChecked(bool(self.plan["reminders_on"]))
        self.reminders.setStyleSheet(f"color:{INK}; font-size:12px;")
        self.reminders.toggled.connect(self._refresh)
        body.addWidget(self.reminders)

        self.time_row = QtWidgets.QWidget()
        time_lay = QtWidgets.QHBoxLayout(self.time_row)
        time_lay.setContentsMargins(20, 0, 0, 0)
        time_lay.setSpacing(8)
        self.time = QtWidgets.QTimeEdit()
        self.time.setDisplayFormat("HH:mm")
        self.time.setAccessibleName(self.reminders.text())
        self.time.setTime(QtCore.QTime(int(self.plan["reminder_hour"]),
                                       int(self.plan["reminder_minute"])))
        self.time.setStyleSheet(f"font-size:12px; color:{INK};")
        time_lay.addWidget(self.time)
        self.warn = QtWidgets.QCheckBox(L("and again if the streak is about to go"))
        self.warn.setChecked(bool(self.plan["warns_when_streak_at_risk"]))
        self.warn.setStyleSheet(f"color:{MUTED}; font-size:11px;")
        time_lay.addWidget(self.warn)
        time_lay.addStretch(1)
        body.addWidget(self.time_row)

        note = QtWidgets.QLabel(
            L("Reminders here arrive while the app is open. Leave it running in "
            "the background and it will nudge you at the time you set."))
        note.setWordWrap(True)
        leading(note)
        note.setStyleSheet(f"color:{MUTED}; font-size:10px;")
        body.addWidget(note)

        lay.addWidget(self.body)

        buttons = QtWidgets.QDialogButtonBox(
            QtWidgets.QDialogButtonBox.Save | QtWidgets.QDialogButtonBox.Cancel)
        buttons.button(QtWidgets.QDialogButtonBox.Save).setText(L("Save"))
        buttons.button(QtWidgets.QDialogButtonBox.Cancel).setText(L("Cancel"))
        buttons.accepted.connect(self._save)
        buttons.rejected.connect(self.reject)
        lay.addWidget(buttons)

        self._refresh()
        self.setFixedWidth(430)

    def _refresh(self):
        self.body.setVisible(self.enabled.isChecked())
        self.time_row.setVisible(self.reminders.isChecked())
        self.adjustSize()

    def _save(self):
        chosen = sorted(w for w, b in self.day_buttons.items() if b.isChecked())
        if self.enabled.isChecked() and not chosen:
            brand.tell(
                self, L("Pick a day"),
                L("A plan with no days is a plan to do nothing. "
                  "Choose at least one, or turn the plan off."))
            return
        self.plan.update({
            "enabled": self.enabled.isChecked(),
            "days": chosen,
            "daily_target": self.target.value(),
            "reminders_on": self.reminders.isChecked(),
            "reminder_hour": self.time.time().hour(),
            "reminder_minute": self.time.time().minute(),
            "warns_when_streak_at_risk": self.warn.isChecked(),
        })
        self.store.set_setting("schedule", self.plan)
        self.accept()


class ProfilesPane(QtWidgets.QWidget):

    ACCENTS = HomeScreen.PROFILE_ACCENTS

    ROWS_MAX_HEIGHT = 340

    def __init__(self, store, parent=None, on_done=None):
        super().__init__(parent)
        self.store = store
        self._on_done = on_done
        self.rebuilt = lambda: None
        self.setWindowTitle(L("Students"))
        self._build()

    def _build(self):
        discard_layout(self)
        lay = QtWidgets.QVBoxLayout(self)
        lay.setContentsMargins(22, 20, 22, 18)
        lay.setSpacing(0)

        title = QtWidgets.QLabel(L("Students on this computer"))
        title.setStyleSheet(
            f"color:{NAVY}; font-size:17px; font-weight:600; font-family:{SERIF};")
        lay.addWidget(title)
        lay.addSpacing(14)

        rows = QtWidgets.QWidget()
        rows.setObjectName("profileRows")
        rows.setStyleSheet(
            f"QWidget#profileRows{{background:{CARD}; border:1px solid {HAIRLINE};"
            "border-radius:4px;}")
        inner = QtWidgets.QVBoxLayout(rows)
        inner.setContentsMargins(0, 0, 0, 0)
        inner.setSpacing(0)
        for i, p in enumerate(self.store.profiles.profiles):
            if i:
                inner.addWidget(_rule())
            inner.addWidget(self._row(p))
        inner.addWidget(_rule())
        inner.addWidget(self._adder())

        wanted = rows.sizeHint().height()
        if wanted > self.ROWS_MAX_HEIGHT:
            scroller = QtWidgets.QScrollArea()
            scroller.setWidget(rows)
            scroller.setWidgetResizable(True)
            scroller.setFrameShape(QtWidgets.QFrame.NoFrame)
            scroller.setHorizontalScrollBarPolicy(QtCore.Qt.ScrollBarAlwaysOff)
            scroller.setFixedHeight(self.ROWS_MAX_HEIGHT)
            scroller.setStyleSheet(
                SCROLLBAR + "QScrollArea{background:transparent; border:none;}")
            lay.addWidget(scroller)
        else:
            lay.addWidget(rows)
        lay.addSpacing(16)

        lay.addSpacing(16)
        moving = QtWidgets.QLabel(L("Moving between computers"))
        moving.setStyleSheet(
            f"color:{NAVY}; font-size:14px; font-weight:600; font-family:{SERIF};")
        lay.addWidget(moving)
        lay.addSpacing(4)
        carry = QtWidgets.QLabel(
            L("A student using a library computer one day and a laptop the next "
            "should not have to start again. Export this student to a small "
            "file — it fits in an email — and import it on the other computer. "
            "A sitting in progress is not carried: it belongs to the computer "
            "it was begun on."))
        carry.setWordWrap(True)
        leading(carry)
        carry.setStyleSheet(f"color:{MUTED}; font-size:10.5px; border:none;")
        lay.addWidget(carry)
        lay.addSpacing(8)

        moves = QtWidgets.QHBoxLayout()
        moves.setSpacing(14)
        for label, slot in ((L("Export this student…"), self._export_profile),
                            (L("Import a student file…"), self._import_profile)):
            button = QtWidgets.QPushButton(label)
            button.setCursor(QtCore.Qt.PointingHandCursor)
            button.setStyleSheet(
                f"QPushButton{{border:none; color:{NAVY}; font-size:12px;"
                "font-weight:600; text-align:left;}")
            button.clicked.connect(slot)
            moves.addWidget(button)
        moves.addStretch(1)
        lay.addLayout(moves)

        if self.store.pending:
            n = len(self.store.pending)
            waiting = QtWidgets.QLabel(Lp(
                n,
                "%d imported set is waiting for its question PDF. Its progress "
                "is kept and applied the moment you import it.",
                "%d imported sets are waiting for their question PDFs. Their "
                "progress is kept and applied the moment you import them."))
            waiting.setWordWrap(True)
            leading(waiting)
            waiting.setStyleSheet(f"color:{BRASS_TEXT}; font-size:10.5px; border:none;")
            lay.addSpacing(6)
            lay.addWidget(waiting)

        lay.addSpacing(16)
        note = QtWidgets.QLabel(
            L("Each student keeps their own progress, statistics, notes and "
            "flashcard decks. Question sets are shared, so a set only has to be "
            "imported once. Profiles are not password-protected — anyone using "
            "this computer can open any of them."))
        note.setWordWrap(True)
        leading(note)
        note.setStyleSheet(f"color:{MUTED}; font-size:10.5px; border:none;")
        lay.addWidget(note)
        lay.addSpacing(14)

        if self._on_done is not None:
            buttons = QtWidgets.QHBoxLayout()
            buttons.addStretch(1)
            done = QtWidgets.QPushButton(L("Done"))
            done.setCursor(QtCore.Qt.PointingHandCursor)
            done.setStyleSheet(
                f"QPushButton{{background:{NAVY}; color:{CARD}; border-radius:3px;"
                "padding:8px 22px; font-size:13px; font-weight:600;}")
            done.clicked.connect(self._on_done)
            buttons.addWidget(done)
            lay.addLayout(buttons)

        self.rebuilt()

    def _row(self, p):
        row = QtWidgets.QWidget()
        row.setStyleSheet("background:transparent; border:none;")
        lay = QtWidgets.QHBoxLayout(row)
        lay.setContentsMargins(16, 11, 12, 11)
        lay.setSpacing(12)

        colour = profile_colour(p.get("accent", 0))
        mark = QtWidgets.QLabel(profile_initials(p))
        mark.setFixedSize(32, 32)
        mark.setAlignment(QtCore.Qt.AlignCenter)
        mark.setStyleSheet(
            f"background:{colour}; color:{brand.on_fill(colour)}; border-radius:16px;"
            "font-size:12px; font-weight:600;")
        lay.addWidget(mark)

        current = p["id"] == self.store.profile["id"]
        name = QtWidgets.QLabel(
            f"<div style='font-size:13px; font-weight:600; color:{INK}'>"
            f"{p.get('name','')}</div>"
            + (f"<div style='font-size:10px; color:{BRASS_TEXT}'>{L('Open now')}</div>"
               if current else ""))
        name.setStyleSheet("border:none;")
        name.setWordWrap(True)
        leading(name)
        name.setSizePolicy(QtWidgets.QSizePolicy.Ignored, QtWidgets.QSizePolicy.Preferred)
        lay.addWidget(name, 1)

        for i in range(len(self.ACCENTS)):
            colour = profile_colour(i)
            dot = QtWidgets.QPushButton()
            dot.setAccessibleName(Lf("Color %d", i + 1))
            chosen = int(p.get("accent", 0)) % len(self.ACCENTS) == i
            size = 20 if chosen else 13
            dot.setFixedSize(size, size)
            dot.setCursor(QtCore.Qt.PointingHandCursor)
            dot.setStyleSheet(
                f"QPushButton{{background:{colour}; border-radius:{size // 2}px;"
                + (f"border:2px solid {CARD};" if chosen else "border:none;") + "}")
            dot.clicked.connect(
                lambda _=False, pid=p["id"], k=i: self._set_accent(pid, k))
            lay.addWidget(dot)

        more = QtWidgets.QPushButton()
        more.setAccessibleName(L("More"))
        more.setIcon(brand.icon("more", 14, MUTED))
        more.setIconSize(QtCore.QSize(14, 14))
        more.setCursor(QtCore.Qt.PointingHandCursor)
        more.setStyleSheet("QPushButton{border:none; background:transparent;}")
        menu = QtWidgets.QMenu(more)
        brand.dress_menu(menu)
        if not current:
            menu.addAction(L("Open this student")).triggered.connect(
                lambda _=False, o=p: self._open(o))
        menu.addAction(L("Rename…")).triggered.connect(lambda _=False, o=p: self._rename(o))
        if len(self.store.profiles.profiles) > 1:
            menu.addSeparator()
            menu.addAction(L("Delete…")).triggered.connect(lambda _=False, o=p: self._delete(o))
        more.setMenu(menu)
        lay.addWidget(more)
        return row

    def _adder(self):
        row = QtWidgets.QWidget()
        row.setStyleSheet("background:transparent; border:none;")
        lay = QtWidgets.QHBoxLayout(row)
        lay.setContentsMargins(16, 11, 12, 11)
        lay.setSpacing(10)
        field = QtWidgets.QLineEdit()
        field.setPlaceholderText(L("Add another student"))
        field.setAccessibleName(L("Add another student"))
        field.setStyleSheet(
            f"QLineEdit{{border:none; background:transparent; color:{INK};"
            "font-size:13px;}")
        lay.addWidget(field, 1)
        add = QtWidgets.QPushButton(L("Add"))
        add.setCursor(QtCore.Qt.PointingHandCursor)
        add.setStyleSheet(
            f"QPushButton{{border:none; color:{NAVY}; font-size:11px; font-weight:600;}}")
        add.clicked.connect(lambda: self._add(field.text()))
        field.returnPressed.connect(lambda: self._add(field.text()))
        lay.addWidget(add)
        return row

    def _add(self, name):
        self.store.add_profile(name)
        self._build()

    def _set_accent(self, profile_id, accent):
        self.store.profiles.set_accent(profile_id, accent)
        if profile_id == self.store.profile["id"]:
            self.store.profile = next(p for p in self.store.profiles.profiles
                                      if p["id"] == profile_id)
        self._build()

    def _open(self, profile):
        self.store.use_profile(profile)
        self._after_switch()
        say_highlights_taken_off(self, self.store)

    def _after_switch(self):
        host = self.window()
        if type(host).__name__ == "SettingsSheet" and hasattr(host, "_rebuild_app"):
            host._rebuild_app()
            return
        behind = host.parentWidget().window() if host.parentWidget() is not None else None
        if behind is not None and hasattr(behind, "reload_theme"):
            behind.reload_theme()
        self._build()

    def _rename(self, profile):
        name, ok = QtWidgets.QInputDialog.getText(
            self, L("Rename student"), L("Student's name"), text=profile.get("name", ""))
        if ok:
            self.store.profiles.rename(profile["id"], name)
            if profile["id"] == self.store.profile["id"]:
                self.store.profile = next(p for p in self.store.profiles.profiles
                                          if p["id"] == profile["id"])
            self._build()

    def _export_profile(self):
        export_student(self.store, self)

    def _import_profile(self):
        from . import portable
        path, _ = QtWidgets.QFileDialog.getOpenFileName(
            self, L("Import a student file"), brand.dialog_path(opening=True))
        if not path:
            return
        brand.remember_folder(path)
        data = portable.read_profile(path)
        if data is None:
            brand.warn(
                self, L("Import"),
                L("That is not a student file exported from this app."))
            return
        plan = portable.plan_for(data, self.store.banks)

        lines = []
        for m in plan["matches"]:
            if m["localBankID"] is None:
                lines.append("• " + Lf(
                    "%@ — you have not imported this set here yet; its progress "
                    "will be kept until you do.", m["exportedName"]))
            elif m["how"] == "fingerprint":
                lines.append("• " + m["exportedName"] + " — "
                             + Lf("The same set as your “%@”", m["localName"])
                             + Lf(" (%d records)", m["records"]))
            elif m["how"] == "name":
                lines.append("• " + m["exportedName"] + " — "
                             + Lf("Matched to your “%@” by name", m["localName"])
                             + Lf(" (%d records)", m["records"]))
            else:
                lines.append("• " + Lf(
                    "%1$@ — matched to your “%2$@”, %3$d questions in common "
                    "(%4$d records)",
                    m["exportedName"], m["localName"], m["overlap"],
                    m["records"]))

        box = brand.alert(
            self, L("Import"),
            Lf("Import %@?", plan["profileName"] or L("a student")))
        box.setInformativeText(
            "\n".join(lines) + "\n\n"
            + L("Where both computers have a record of the same question, the "
                "one with more attempts on it is kept. Importing the same file "
                "twice changes nothing."))
        merge = box.addButton(L("Add to this student"), QtWidgets.QMessageBox.AcceptRole)
        fresh = box.addButton(L("Bring in as a new student"), QtWidgets.QMessageBox.AcceptRole)
        box.addButton(QtWidgets.QMessageBox.Cancel)
        box.exec()
        clicked = box.clickedButton()
        if clicked not in (merge, fresh):
            return

        report = portable.import_profile(
            self.store, data, plan, mode="merge" if clicked is merge else "new")
        if clicked is fresh:
            i18n.install_qt()
        parts = portable.summary(report)
        brand.tell(
            self, L("Imported"),
            "\n".join(parts) or L("Nothing in that file matched anything here."))
        if clicked is fresh:
            self._after_switch()
        else:
            self._build()

    def _delete(self, profile):
        if brand.ask(
                self, L("Delete"),
                Lf("Delete %@?", profile.get("name", "")) + "\n\n"
                + L("Their progress, notes and flashcard decks are deleted. The "
                    "question sets stay — they are shared with everyone on this "
                    "computer."),
                accept=L("Delete"), destructive=True):
            was_open = profile["id"] == self.store.profile["id"]
            self.store.delete_profile(profile["id"])
            if was_open:
                self._after_switch()
            else:
                self._build()


class ProfilesDialog(QtWidgets.QDialog):

    def __init__(self, store, parent=None):
        super().__init__(parent)
        self.store = store
        self.setWindowTitle(L("Students"))
        self.setMinimumWidth(520)
        self.setStyleSheet(
            f"QDialog{{background:{PAPER}; border:1px solid {HAIRLINE};}}")
        brand.as_sheet(self, parent)
        lay = QtWidgets.QVBoxLayout(self)
        lay.setContentsMargins(0, 0, 0, 0)
        self.pane = ProfilesPane(store, self, on_done=self.accept)

        scroll = QtWidgets.QScrollArea()
        scroll.setWidgetResizable(True)
        scroll.setFrameShape(QtWidgets.QFrame.NoFrame)
        scroll.setHorizontalScrollBarPolicy(QtCore.Qt.ScrollBarAlwaysOff)
        scroll.setStyleSheet(f"QScrollArea{{background:{PAPER}; border:none;}}"
                             + SCROLLBAR)
        scroll.setWidget(self.pane)
        lay.addWidget(scroll)

        self.pane.rebuilt = self.fit
        self.fit()

    def fit(self):
        QtCore.QTimer.singleShot(0, self._fit_now)

    def _fit_now(self):
        if not shiboken6.isValid(self):
            return
        screen = brand.screen_at(self)
        room = int(screen.availableGeometry().height() * 0.85) if screen else 760
        wanted = min(self.pane.sizeHint().height() + 4, room)
        tall = min(room, max(self.height(), wanted)) if self.isVisible() else wanted
        self.resize(max(self.width(), 560), tall)
        put_back = getattr(self, "recentre", None)
        if put_back is not None:
            put_back()


class StreakRestoreDialog(QtWidgets.QDialog):

    def __init__(self, store, gap, parent=None):
        super().__init__(parent)
        brand.as_sheet(self, parent)
        self.store = store
        self.gap = gap
        self.restored = False
        self.setWindowTitle(L("Your run is still here, if you want it"))
        self.setMinimumWidth(470)
        self.setStyleSheet(f"QDialog{{background:{CARD};}}")

        lay = QtWidgets.QVBoxLayout(self)
        lay.setContentsMargins(22, 20, 22, 18)
        lay.setSpacing(0)

        title = QtWidgets.QLabel(L("Your run is still here, if you want it"))
        title.setWordWrap(True)
        leading(title)
        title.setStyleSheet(
            f"color:{NAVY}; font-size:17px; font-weight:600; font-family:{SERIF};")
        lay.addWidget(title)
        lay.addSpacing(8)

        away = (Lp(gap["days_away"], "You were away for %d day.",
                   "You were away for %d days.")
                + " "
                + Lp(gap["streak_before"],
                     "Setting that time aside keeps the run of %d day you had going.",
                     "Setting that time aside keeps the run of %d days you had going."))
        head = QtWidgets.QLabel(away)
        head.setWordWrap(True)
        leading(head)
        head.setStyleSheet(f"color:{INK}; font-size:12px;")
        lay.addWidget(head)
        lay.addSpacing(12)

        note = QtWidgets.QLabel(
            L("Days you set aside are skipped, the way a planned rest day is — "
              "never counted as days you practiced. Your best run and everything "
              "you have answered stay exactly as they are."))
        note.setWordWrap(True)
        leading(note)
        note.setStyleSheet(f"color:{MUTED}; font-size:11px;")
        lay.addWidget(note)
        lay.addSpacing(8)

        choice = QtWidgets.QLabel(
            L("Entirely up to you. A run of days is worth having only while it "
              "is helping."))
        choice.setWordWrap(True)
        leading(choice)
        choice.setStyleSheet(f"color:{BRASS_TEXT}; font-size:11px;")
        lay.addWidget(choice)
        lay.addSpacing(18)

        row = QtWidgets.QHBoxLayout()
        row.addStretch(1)
        leave = QtWidgets.QPushButton(L("Leave it"))
        leave.setCursor(QtCore.Qt.PointingHandCursor)
        leave.setStyleSheet(
            f"QPushButton{{background:{SUBTLE}; color:{INK}; border:1px solid {HAIRLINE};"
            "border-radius:3px; padding:8px 20px; font-size:13px; font-weight:600;}")
        leave.clicked.connect(self._decline)
        row.addWidget(leave)

        keep = QtWidgets.QPushButton(
            Lp(len(gap["missed"]), "Set aside %d day", "Set aside %d days"))
        keep.setCursor(QtCore.Qt.PointingHandCursor)
        keep.setStyleSheet(
            f"QPushButton{{background:{BRAND_FILL}; color:{ON_BRAND}; border-radius:3px;"
            "padding:8px 20px; font-size:13px; font-weight:600;}")
        keep.clicked.connect(self._restore)
        row.addWidget(keep)
        lay.addLayout(row)

    def _decline(self):
        self.store.decline_restore(self.gap)
        self.reject()

    def _restore(self):
        self.store.restore_streak(self.gap)
        self.restored = True
        self.accept()

brand.adopt(__name__)
