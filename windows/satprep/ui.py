from __future__ import annotations

import math
import os
import re
import time

import shiboken6
from PySide6 import QtCore, QtGui, QtWidgets

from .core import (Attempt, Store, Session, is_correct, should_warn,
                   TIMER_WARNING_SECONDS, fit_table_size)
from . import export as exporter
from .reference import ReferenceDialog
from .directions import for_session as directions_for
from .i18n import L, Lf, Lp
from . import brand
from . import fulltest

PAPER = "#F4F0E8"
CARD = "#FDFBF6"
PAPER_DEEP = "#ECE6DA"
SUBTLE = "#F1EDE5"

NAVY = "#1B2A4A"
NAVY_DEEP = "#121E37"
INK = "#1B2A4A"
MUTED = "#666F86"

HAIRLINE = "#DAD2C3"
BORDER = "#C9BFAC"

BRASS = "#A98A51"
BRASS_SOFT = "#E9E0CD"
BRASS_TEXT = "#7D6230"

CANVAS = "#FFFFFF"
CHROME = "#F9F8F5"
ACCENT = "#175AC9"
ACCENT_SOFT = "#EDF2FF"
ACCENT_FILL = "#175AC9"
ACCENT_FILL_DEEP = "#121E37"

CORRECT = "#215A38"
CORRECT_SOFT = "#E6F0E6"
WRONG = "#832727"
WRONG_SOFT = "#F6EAE7"

ON_BRAND = "#FDFBF6"
BRAND_FILL = "#1B2A4A"

SERIF = "Georgia, 'Times New Roman', serif"

NUMERALS = "'Segoe UI', 'Helvetica Neue', Arial, sans-serif"

LEADING = 1.45

_MARKUP = re.compile(r"<\s*/?[a-zA-Z][a-zA-Z0-9]*(\s[^<>]*)?/?>")


def framed_spin(spin, size=12):
    box = QtWidgets.QFrame()
    box.setObjectName("spinFrame")
    box.setStyleSheet(f"QFrame#spinFrame{{background:{CARD}; border:1px solid {HAIRLINE};"
                      "border-radius:3px;}")
    lay = QtWidgets.QHBoxLayout(box)
    lay.setContentsMargins(1, 1, 1, 1)
    lay.setSpacing(0)
    spin.setFrame(False)
    spin.setStyleSheet(f"color:{INK}; font-size:{size}px; background:transparent;")
    lay.addWidget(spin)
    return box


def leading(label, ratio=LEADING, rich=False):
    from html import escape

    def dress(text):
        if not text:
            return text
        if rich or _MARKUP.search(text):
            body = text
        else:
            body = escape(text).replace("\n", "<br>")
        return '<div style="line-height:%d%%;">%s</div>' % (round(ratio * 100), body)

    plain = [label.text()]
    set_text = QtWidgets.QLabel.setText

    def replace(text):
        plain[0] = text
        set_text(label, dress(text))

    label.setTextFormat(QtCore.Qt.RichText)
    label.setText = replace
    label.text = lambda: plain[0]
    replace(plain[0])
    return label

_discarded = []


class ElidedLabel(QtWidgets.QLabel):

    def __init__(self, text="", parent=None):
        super().__init__(text, parent)
        self._full = text
        self.setToolTip(text)
        self.setAccessibleName(text)
        self.setSizePolicy(QtWidgets.QSizePolicy.Ignored, QtWidgets.QSizePolicy.Preferred)

    def minimumSizeHint(self):
        return QtCore.QSize(0, super().minimumSizeHint().height())

    def setFixedWidth(self, width):
        super().setFixedWidth(width)
        self.setSizePolicy(QtWidgets.QSizePolicy.Fixed, QtWidgets.QSizePolicy.Preferred)

    def resizeEvent(self, event):
        super().resizeEvent(event)
        shown = self.fontMetrics().elidedText(self._full, QtCore.Qt.ElideRight,
                                              max(0, self.width()))
        if shown != self.text():
            self.setText(shown)


def discard_layout(widget):
    old = widget.layout()
    if old is None:
        return
    holder = QtWidgets.QWidget()
    holder.setLayout(old)
    holder.hide()
    _discarded.append(holder)
    QtCore.QTimer.singleShot(0, _drain)


def _drain():
    del _discarded[:]


HIGHLIGHTS = ["#FFEE8C", "#B8E8B8", "#B8DBFA", "#FCC7D6"]


def highlight_color(index):
    return HIGHLIGHTS[index % len(HIGHLIGHTS)]


def rebuild_derived():
    global SCROLLBAR
    SCROLLBAR = _scrollbar_style()

def _scrollbar_style():
    return f"""
QScrollBar:vertical {{ background: transparent; width: 10px; margin: 0; }}
QScrollBar::handle:vertical {{ background: {BORDER}; border-radius: 5px; min-height: 36px; }}
QScrollBar::handle:vertical:hover {{ background: {BRASS}; }}
QScrollBar::add-line:vertical, QScrollBar::sub-line:vertical {{ height: 0; }}
QScrollBar::add-page:vertical, QScrollBar::sub-page:vertical {{ background: transparent; }}
QScrollBar:horizontal {{ background: transparent; height: 10px; margin: 0; }}
QScrollBar::handle:horizontal {{ background: {BORDER}; border-radius: 5px; min-width: 36px; }}
QScrollBar::handle:horizontal:hover {{ background: {BRASS}; }}
QScrollBar::add-line:horizontal, QScrollBar::sub-line:horizontal {{ width: 0; }}
QScrollBar::add-page:horizontal, QScrollBar::sub-page:horizontal {{ background: transparent; }}
"""


SCROLLBAR = _scrollbar_style()

PDF_BODY_PT = 9.0
DEFAULT_BODY_PT = 15
MIN_BODY_PT = 11
MAX_BODY_PT = 26

_chosen_body_pt = DEFAULT_BODY_PT


SPLIT_RANGE = (0.25, 0.75)
_SPLIT = {"sitting": None, "fraction": 0.5}


def _split_fraction(session):
    sitting = (session.bank_id, session.started_at)
    if _SPLIT["sitting"] != sitting:
        _SPLIT.update(sitting=sitting, fraction=0.5)
    return _SPLIT["fraction"]


def chosen_body_size():
    return _chosen_body_pt


def remember_body_size(size):
    global _chosen_body_pt
    _chosen_body_pt = max(MIN_BODY_PT, min(MAX_BODY_PT, int(size)))


TEXT_COLUMN = 720
CHOICE_CHROME = 13 + 24 + 11 + 13 + 11 + 44
ELIMINATOR_WIDTH = 44


def drawn_width(block):
    if block.kind != "image":
        return 0.0
    if has_words(block):
        return max((r["width"] for para in block.inline for r in para["runs"]
                    if "image" in r), default=0.0)
    return getattr(block, "point_width", 0) or 0


def widest_region(blocks):
    widths = [drawn_width(b) for b in blocks if b.kind == "image"]
    return max(widths) if widths else 0.0


def question_width(q, with_rationale=True):
    parts = list(q.stimulus) + list(q.prompt)
    if with_rationale:
        parts += list(q.rationale)
    body = widest_region(parts)
    choice = widest_region([b for c in q.choices for b in c.blocks])
    return body, choice


def column_width(q, body_size, available=None, with_rationale=True):
    wanted = body_size / PDF_BODY_PT
    body, choice = question_width(q, with_rationale)
    needed = math.ceil(max(TEXT_COLUMN, body * wanted, choice * wanted + CHOICE_CHROME))
    return min(available, needed) if available else needed


def centered_column(child, width):
    child.setMaximumWidth(int(width))
    child.setSizePolicy(QtWidgets.QSizePolicy.Expanding,
                        QtWidgets.QSizePolicy.Preferred)
    child.setProperty("satColumn", True)
    wrap = QtWidgets.QWidget()
    row = QtWidgets.QHBoxLayout(wrap)
    row.setContentsMargins(0, 0, 0, 0)
    row.addStretch(1)
    row.addWidget(child, 1000)
    row.addStretch(1)
    return wrap


def _clock(seconds: float) -> str:
    s = max(0, int(round(seconds)))
    return f"{s // 60}:{s % 60:02d}"


def _marked_up(text: str, underlines) -> str:
    from html import escape
    out, pos = [], 0
    for start, end in sorted(tuple(r) for r in (underlines or ())):
        start, end = max(0, start), min(end, len(text))
        if end <= start or start < pos:
            continue
        out.append(escape(text[pos:start]))
        out.append("<u>" + escape(text[start:end]) + "</u>")
        pos = end
    out.append(escape(text[pos:]))
    return "".join(out).replace("\n\n", "<br><br>").replace("\n", "<br>")


class PassageView(QtWidgets.QTextEdit):

    selected = QtCore.Signal(int, int)
    annotation_clicked = QtCore.Signal(str)

    def __init__(self, text, underlines, annotations, body_size=15, parent=None):
        super().__init__(parent)
        self._annotations = list(annotations)
        self.setReadOnly(True)
        self.setFrameShape(QtWidgets.QFrame.NoFrame)
        self.setVerticalScrollBarPolicy(QtCore.Qt.ScrollBarAlwaysOff)
        self.setHorizontalScrollBarPolicy(QtCore.Qt.ScrollBarAlwaysOff)
        self.setStyleSheet(
            f"QTextEdit{{background:transparent; border:none; color:{INK};"
            f"font-size:{body_size}px;}}")
        self.setPlainText(text)
        font = QtGui.QFont(self.font())
        font.setPixelSize(body_size)
        spacing = QtGui.QTextBlockFormat()
        spacing.setLineHeight((LEADING - 1) * QtGui.QFontMetricsF(font).height(),
                              QtGui.QTextBlockFormat.LineHeightTypes.LineDistanceHeight.value)
        whole = self.textCursor()
        whole.select(QtGui.QTextCursor.Document)
        whole.mergeBlockFormat(spacing)

        for start, end in underlines or ():
            self._apply(start, end, underline=True)
        for a in self._annotations:
            self._apply(a["start"], a["end"],
                        background=highlight_color(a.get("color", 0)),
                        note=bool(a.get("note", "").strip()))

        self.selectionChanged.connect(self._on_selection)
        self.document().documentLayout().documentSizeChanged.connect(self._fit)
        self.document().setTextWidth(self.viewport().width())
        self._fit()

    def _apply(self, start, end, underline=False, background=None, note=False):
        cursor = self.textCursor()
        cursor.setPosition(max(0, start))
        cursor.setPosition(min(end, self.document().characterCount() - 1),
                           QtGui.QTextCursor.KeepAnchor)
        fmt = QtGui.QTextCharFormat()
        if underline:
            fmt.setFontUnderline(True)
        if background:
            fmt.setBackground(QtGui.QColor(background))
        if note:
            fmt.setUnderlineStyle(QtGui.QTextCharFormat.SingleUnderline)
            fmt.setUnderlineColor(QtGui.QColor(BRASS))
        cursor.mergeCharFormat(fmt)

    def resizeEvent(self, event):
        super().resizeEvent(event)
        self.document().setTextWidth(self.viewport().width())
        self._fit()

    def _fit(self):
        height = int(self.document().size().height()) + 4
        if height != self.height():
            self.setFixedHeight(height)

    def _on_selection(self):
        c = self.textCursor()
        if c.hasSelection():
            self.selected.emit(c.selectionStart(), c.selectionEnd())
        else:
            self.selected.emit(-1, -1)

    def mouseReleaseEvent(self, event):
        super().mouseReleaseEvent(event)
        if event.button() != QtCore.Qt.LeftButton or self.textCursor().hasSelection():
            return
        pos = self.cursorForPosition(event.pos()).position()
        for a in self._annotations:
            if a["start"] <= pos < a["end"]:
                self.annotation_clicked.emit(a["id"])
                return


class TableView(QtWidgets.QWidget):

    def __init__(self, rows, body_size=15, parent=None):
        super().__init__(parent)
        self.setSizePolicy(QtWidgets.QSizePolicy.Preferred, QtWidgets.QSizePolicy.Minimum)
        grid = QtWidgets.QGridLayout(self)
        grid.setContentsMargins(0, 2, 0, 2)
        grid.setSpacing(0)

        width = max((len(r) for r in rows if len(r) > 1), default=1)
        header_at = next((i for i, r in enumerate(rows) if len(r) > 1), None)

        size = max(10, int(body_size - 1 - 1.5 * max(0, width - 4)))
        pad = 10 if width <= 4 else (6 if width <= 5 else 4)

        def _measure(text, at):
            font = QtGui.QFont()
            font.setPixelSize(int(at))
            font.setWeight(QtGui.QFont.DemiBold)
            return QtGui.QFontMetrics(font).horizontalAdvance(text)

        column = TEXT_COLUMN / max(1, width) - pad * 2 - 6
        size = int(fit_table_size(rows, width, column, _measure, size))

        for r, row in enumerate(rows):
            spanning = len(row) == 1 and width > 1
            for c, cell in enumerate(row):
                lbl = QtWidgets.QLabel(cell)
                lbl.setWordWrap(True)
                leading(lbl)
                lbl.setTextInteractionFlags(QtCore.Qt.TextSelectableByMouse)
                lbl.setAlignment(QtCore.Qt.AlignCenter if (spanning or r == header_at)
                                 else (QtCore.Qt.AlignLeft | QtCore.Qt.AlignVCenter))
                bold = spanning or r == header_at
                lbl.setStyleSheet(
                    f"QLabel{{color:{INK}; font-size:{size}px;"
                    f"font-weight:{'600' if bold else '400'};"
                    f"background:{SUBTLE if r == header_at else 'transparent'};"
                    f"border:1px solid {BORDER}; padding:6px {pad}px;}}")
                policy = lbl.sizePolicy()
                policy.setHeightForWidth(True)
                policy.setVerticalPolicy(QtWidgets.QSizePolicy.MinimumExpanding)
                lbl.setSizePolicy(policy)
                face = QtGui.QFont(lbl.font())
                face.setPixelSize(size)
                face.setWeight(QtGui.QFont.DemiBold if bold else QtGui.QFont.Normal)
                metrics = QtGui.QFontMetrics(face)
                word = max((metrics.horizontalAdvance(w) for w in cell.split()), default=0)
                lbl.setMinimumWidth(max(46 if width > 4 else 56,
                                        0 if spanning else word + 2 * pad + 2 + 2))
                grid.addWidget(lbl, r, c, 1, width if spanning else 1)
        for c in range(width):
            longest = 1
            for row in rows:
                if len(row) > c and len(row) > 1:
                    for word in row[c].split():
                        longest = max(longest, len(word))
                    longest = max(longest, min(len(row[c]), 18))
            grid.setColumnStretch(c, max(2, longest))
        for r in range(len(rows)):
            grid.setRowStretch(r, 0)


def _load_figure(path):
    pixmap = QtGui.QPixmap(path)
    if pixmap.isNull() or not brand.stealth_on():
        return pixmap
    image = pixmap.toImage().convertToFormat(QtGui.QImage.Format_ARGB32)
    image.invertPixels(QtGui.QImage.InvertRgb)
    return QtGui.QPixmap.fromImage(image)


_INK_MIDDLES = {}


def ink_middle(path):
    if path in _INK_MIDDLES:
        return _INK_MIDDLES[path]
    found = 0.5
    image = QtGui.QImage(path)
    if not image.isNull() and image.width() and image.height():
        flat = QtGui.QImage(image.size(), QtGui.QImage.Format_RGB32)
        flat.fill(QtCore.Qt.white)
        painter = QtGui.QPainter(flat)
        painter.drawImage(0, 0, image)
        painter.end()
        grey = flat.convertToFormat(QtGui.QImage.Format_Grayscale8)
        w = grey.width()
        stride = grey.bytesPerLine()
        data = bytes(grey.constBits())
        inked = [y for y in range(grey.height())
                 if min(data[y * stride:y * stride + w]) < 200]
        if inked:
            found = (inked[0] + inked[-1] + 1) / 2 / grey.height()
    _INK_MIDDLES[path] = found
    return found


class Figure(QtWidgets.QLabel):

    def __init__(self, path, point_width, body_size, question_points=0.0,
                 chrome=0, parent=None, source=None):
        super().__init__(parent)
        self._source = source if source is not None else _load_figure(path)
        self._point_width = point_width or 100
        self._body_size = body_size
        self._question_points = question_points or (point_width or 100)
        self._chrome = chrome
        self._drawn = 0
        self._last_size = None
        self._last_available = None
        self.setAlignment(QtCore.Qt.AlignLeft | QtCore.Qt.AlignTop)
        if self._source.isNull():
            self.setText(L("Image missing"))
            self.setStyleSheet(f"color:{MUTED}; font-size:{body_size - 3}px;")
        else:
            self._apply()

    def showEvent(self, event):
        super().showEvent(event)
        self._apply()

    def resizeEvent(self, event):
        super().resizeEvent(event)
        self._apply()

    def minimumSizeHint(self):
        hint = super().minimumSizeHint()
        return QtCore.QSize(min(hint.width(), 40), hint.height())

    def _pane_width(self):
        w = self.parentWidget()
        inset = 0
        while w is not None:
            if w.property("satColumn"):
                return w.width()
            if isinstance(w, QtWidgets.QScrollArea):
                return w.viewport().width() - inset
            lay = w.layout()
            if lay is not None and not isinstance(w, QtWidgets.QScrollArea):
                m = lay.contentsMargins()
                inset += m.left() + m.right()
            if isinstance(w, QtWidgets.QFrame):
                inset += 2 * w.frameWidth()
            w = w.parentWidget()
        return self.width()

    def _apply(self):
        if self._source.isNull():
            return
        available = self._pane_width() - self._chrome
        wanted = self._body_size / PDF_BODY_PT
        fit = 1.0
        if available > 0 and self._question_points > 0:
            fit = min(1.0, available / (self._question_points * wanted))
        target = max(1, int(self._point_width * wanted * fit))
        if target == self._drawn:
            return
        if (self._drawn and self._last_size == self._body_size
                and self._last_available is not None
                and abs(available - self._last_available) <= 12):
            return
        self._drawn = target
        self._last_size = self._body_size
        self._last_available = available
        self.setPixmap(self._source.scaledToWidth(target, QtCore.Qt.SmoothTransformation))

    def paintEvent(self, event):
        pm = self.pixmap()
        if pm is None or pm.isNull():
            super().paintEvent(event)
            return
        painter = QtGui.QPainter(self)
        painter.setCompositionMode(QtGui.QPainter.CompositionMode_Screen if brand.stealth_on()
                                   else QtGui.QPainter.CompositionMode_Multiply)
        size = pm.deviceIndependentSize().toSize()
        rect = QtWidgets.QStyle.alignedRect(self.layoutDirection(), self.alignment(),
                                            size, self.contentsRect())
        painter.drawPixmap(rect, pm)
        painter.end()


def _island(run, images_dir, sheets):
    path = os.path.join(images_dir, run["image"])
    if path not in sheets:
        sheets[path] = _load_figure(path)
    sheet = sheets[path]
    rect = QtCore.QRect(run["x"], run["y"], run["w"], run["h"])
    if sheet.isNull() or not sheet.rect().contains(rect):
        return QtGui.QPixmap()
    return sheet.copy(rect)


_CLOSING = ",.;:?!)]”’"


def _island_image(source, width, height, depth, scale, descent, dpr,
                  tail="", font=None):
    w, h, d = width * scale, height * scale, depth * scale
    if d <= descent:
        top, bottom = 0.0, descent - d
        align = QtGui.QTextCharFormat.AlignBaseline
    else:
        above = h - d
        half = max(above, d)
        top, bottom = half - above, half - d
        align = QtGui.QTextCharFormat.AlignMiddle
    extra = QtGui.QFontMetricsF(font).horizontalAdvance(tail) if tail and font else 0.0
    if extra:
        ascent = QtGui.QFontMetricsF(font).ascent()
        if align == QtGui.QTextCharFormat.AlignBaseline:
            top += max(0.0, ascent - (h + top - d))
        else:
            grow = max(0.0, ascent - (h + top + bottom) / 2.0)
            top += grow
            bottom += grow
    lw, lh = max(1.0, w + extra), max(1.0, h + top + bottom)
    canvas = QtGui.QImage(max(1, round(lw * dpr)), max(1, round(lh * dpr)),
                          QtGui.QImage.Format_RGB32)
    canvas.fill(QtCore.Qt.black if brand.stealth_on() else QtCore.Qt.white)
    painter = QtGui.QPainter(canvas)
    painter.setRenderHint(QtGui.QPainter.SmoothPixmapTransform)
    painter.setRenderHint(QtGui.QPainter.TextAntialiasing)
    if not source.isNull():
        target = QtCore.QSize(max(1, round(w * dpr)), max(1, round(h * dpr)))
        small = source.toImage().scaled(target, QtCore.Qt.IgnoreAspectRatio,
                                        QtCore.Qt.SmoothTransformation)
        painter.drawImage(QtCore.QPointF(0, top * dpr), small)
    if extra:
        base = (lh - descent) if align == QtGui.QTextCharFormat.AlignBaseline else lh / 2
        painter.scale(dpr, dpr)
        painter.setFont(font)
        painter.setPen(QtGui.QColor(INK))
        painter.drawText(QtCore.QPointF(w, base), tail)
    painter.end()
    canvas.setDevicePixelRatio(dpr)
    return canvas, lw, lh, align


def has_words(block):
    return block.kind == "image" and any(
        "text" in r and r["text"].strip()
        for para in (getattr(block, "inline", None) or ()) for r in para["runs"])


class InlineParagraph(QtWidgets.QTextEdit):

    def __init__(self, runs, images_dir, x_height, body_size=15, parent=None):
        super().__init__(parent)
        self._runs = runs
        self._images_dir = images_dir
        self._x_height = x_height or 4.75
        self._body_size = body_size
        self.setReadOnly(True)
        self.setFrameShape(QtWidgets.QFrame.NoFrame)
        self.setVerticalScrollBarPolicy(QtCore.Qt.ScrollBarAlwaysOff)
        self.setHorizontalScrollBarPolicy(QtCore.Qt.ScrollBarAlwaysOff)
        self.setSizePolicy(QtWidgets.QSizePolicy.Preferred, QtWidgets.QSizePolicy.Fixed)
        self.setStyleSheet(
            f"QTextEdit{{background:transparent; border:none; color:{INK};"
            f"font-size:{body_size}px;}}")
        self.setTextInteractionFlags(QtCore.Qt.NoTextInteraction)
        self.viewport().setCursor(QtCore.Qt.ArrowCursor)
        self.document().setDocumentMargin(0)
        self._dpr = 0
        self._build()
        self.document().documentLayout().documentSizeChanged.connect(self._fit)

    def _build(self):
        dpr = self.devicePixelRatioF() or 1.0
        self._dpr = dpr
        font = QtGui.QFont(self.font())
        font.setPixelSize(self._body_size)
        self.document().setDefaultFont(font)
        metrics = QtGui.QFontMetricsF(font)
        scale = metrics.xHeight() / self._x_height
        doc = self.document()
        doc.clear()
        cursor = QtGui.QTextCursor(doc)
        block = QtGui.QTextBlockFormat()
        block.setLineHeight((LEADING - 1) * metrics.height(),
                            QtGui.QTextBlockFormat.LineHeightTypes.LineDistanceHeight.value)
        cursor.setBlockFormat(block)
        words, sheets = [], {}
        runs = list(self._runs)
        carried = ""
        for n, r in enumerate(runs):
            if "text" in r:
                text = r["text"][len(carried):]
                carried = ""
                if text:
                    cursor.insertText(text)
                words.append(r["text"])
                continue
            follow = runs[n + 1].get("text", "") if n + 1 < len(runs) else ""
            carried = ""
            for ch in follow:
                if ch not in _CLOSING:
                    break
                carried += ch
            image, lw, lh, align = _island_image(
                _island(r, self._images_dir, sheets), r["width"], r["height"],
                r["depth"], scale, metrics.descent(), dpr, carried, font)
            url = QtCore.QUrl(f"island:{n}")
            doc.addResource(QtGui.QTextDocument.ImageResource, url, image)
            fmt = QtGui.QTextImageFormat()
            fmt.setName(url.toString())
            fmt.setWidth(lw)
            fmt.setHeight(lh)
            fmt.setVerticalAlignment(align)
            cursor.insertImage(fmt)
        self.setAccessibleName(" ".join(w.strip() for w in words if w.strip()))
        doc.setTextWidth(self.viewport().width())
        self._fit()

    def resizeEvent(self, event):
        super().resizeEvent(event)
        self.document().setTextWidth(self.viewport().width())
        self._fit()

    def showEvent(self, event):
        super().showEvent(event)
        if (self.devicePixelRatioF() or 1.0) != self._dpr:
            self._build()

    def _fit(self):
        height = int(self.document().size().height()) + 2
        if height != self.height():
            self.setFixedHeight(height)

    def paintEvent(self, event):
        painter = QtGui.QPainter(self.viewport())
        painter.setCompositionMode(QtGui.QPainter.CompositionMode_Screen if brand.stealth_on()
                                   else QtGui.QPainter.CompositionMode_Multiply)
        ctx = QtGui.QAbstractTextDocumentLayout.PaintContext()
        ctx.palette.setColor(QtGui.QPalette.Text, QtGui.QColor(INK))
        ctx.clip = QtCore.QRectF(event.rect())
        self.document().documentLayout().draw(painter, ctx)
        painter.end()


DISPLAY_LIMIT_POINTS = 330.0


def is_display(block, before):
    if block.kind != "image":
        return False
    if getattr(block, "centred", False):
        return True
    width = getattr(block, "point_width", 0) or 0
    if not 0 < width < DISPLAY_LIMIT_POINTS:
        return False
    if before is None or before.kind != "text":
        return True
    tail = (before.text or "").rstrip()
    return not tail or tail[-1] in ".:?!;"


class Blocks(QtWidgets.QWidget):

    def __init__(self, blocks, images_dir, body_size=15, parent=None,
                 annotatable=None, field=None, annotations=(),
                 on_select=None, on_annotation=None,
                 question_points=0.0, chrome=0, pass_clicks=False):
        super().__init__(parent)
        self.setSizePolicy(QtWidgets.QSizePolicy.Preferred, QtWidgets.QSizePolicy.Maximum)
        lay = QtWidgets.QVBoxLayout(self)
        lay.setContentsMargins(0, 0, 0, 0)
        gap = max(10, round(body_size * 0.8))
        lay.setSpacing(0)
        extra = 0 if pass_clicks else max(6, round(body_size * 0.55))

        def air(before, after):
            if before is None or after is None:
                return 0
            return extra if "table" in (before.kind, after.kind) else 0

        previous = None
        for index, b in enumerate(blocks):
            before = previous
            if previous is not None:
                lay.addSpacing(gap + air(previous, b))
            previous = b
            if b.kind == "table":
                lay.addWidget(TableView(b.rows, body_size))
            elif b.kind == "text" and annotatable:
                mine = [a for a in annotations
                        if a.get("field") == field and a.get("block", 0) == index]
                view = PassageView(b.text, getattr(b, "underlines", ()), mine, body_size)
                if on_select:
                    view.selected.connect(
                        lambda s, e, i=index: on_select(field, i, s, e))
                if on_annotation:
                    view.annotation_clicked.connect(on_annotation)
                lay.addWidget(view)
            elif b.kind == "text":
                lbl = QtWidgets.QLabel(_marked_up(b.text, getattr(b, "underlines", ())))
                lbl.setTextFormat(QtCore.Qt.RichText)
                lbl.setWordWrap(True)
                leading(lbl, rich=True)
                lbl.setTextInteractionFlags(
                    QtCore.Qt.NoTextInteraction if pass_clicks
                    else QtCore.Qt.TextSelectableByMouse)
                lbl.setStyleSheet(
                    f"color:{INK}; font-size:{body_size}px; background:transparent;")
                lay.addWidget(lbl)
            elif has_words(b):
                for n, para in enumerate(b.inline):
                    if n:
                        lay.addSpacing(gap)
                    if para["display"]:
                        r = para["runs"][0]
                        lay.addWidget(Figure(os.path.join(images_dir, r["image"]),
                                             r["width"], body_size,
                                             question_points=question_points,
                                             chrome=chrome,
                                             source=_island(r, images_dir, {})), 0,
                                      (QtCore.Qt.AlignLeft if pass_clicks
                                       else QtCore.Qt.AlignHCenter) | QtCore.Qt.AlignTop)
                    else:
                        lay.addWidget(InlineParagraph(para["runs"], images_dir,
                                                      b.x_height, body_size))
            else:
                figure = Figure(os.path.join(images_dir, b.image_name),
                                b.point_width, body_size,
                                question_points=question_points,
                                chrome=chrome)
                centre = (getattr(b, "centred", False) if pass_clicks
                          else is_display(b, before))
                lay.addWidget(figure, 0,
                              (QtCore.Qt.AlignHCenter if centre
                               else QtCore.Qt.AlignLeft) | QtCore.Qt.AlignTop)

        if pass_clicks:
            self.setAttribute(QtCore.Qt.WA_TransparentForMouseEvents, True)
            for child in self.findChildren(QtWidgets.QWidget):
                child.setAttribute(QtCore.Qt.WA_TransparentForMouseEvents, True)


class GridInField(QtWidgets.QWidget):

    changed = QtCore.Signal(str)

    def __init__(self, response, body_size, width, locked=False, parent=None):
        super().__init__(parent)
        lay = QtWidgets.QVBoxLayout(self)
        lay.setContentsMargins(0, 0, 0, 0)
        lay.setSpacing(6)
        self.field = QtWidgets.QLineEdit(response)
        self.field.setPlaceholderText(L("Enter your answer"))
        self.field.setAccessibleName(L("Enter your answer"))
        self.field.setFixedWidth(width)
        self.field.setStyleSheet(
            f"QLineEdit{{border:2px solid {BORDER}; border-radius:6px; padding:9px;"
            f"font-size:{body_size + 3}px; color:{INK}; background:{CANVAS};}}")
        self.field.setEnabled(not locked)
        self.field.setValidator(QtGui.QRegularExpressionValidator(
            QtCore.QRegularExpression(r"-?[0-9./]{0,5}"), self.field))
        lay.addWidget(self.field)
        self.preview = QtWidgets.QLabel()
        self.preview.setStyleSheet(
            f"color:{MUTED}; font-size:11px; background:transparent;")
        lay.addWidget(self.preview)
        self._show(response)
        self.field.textChanged.connect(self._typed)

    def _show(self, text):
        self.preview.setText(Lf("Answer preview: %@", text or "—"))

    def _typed(self, text):
        self._show(text)
        self.changed.emit(text)


class _StrikeLine(QtWidgets.QWidget):

    def __init__(self, parent, alpha=0.55):
        super().__init__(parent)
        self._alpha = alpha
        self.setAttribute(QtCore.Qt.WA_TransparentForMouseEvents, True)

    def paintEvent(self, event):
        p = QtGui.QPainter(self)
        colour = QtGui.QColor(INK)
        colour.setAlphaF(self._alpha)
        y = self.height() // 2
        p.fillRect(0, y, self.width(), 1, colour)
        p.end()


class ChoiceRow(QtWidgets.QFrame):

    clicked = QtCore.Signal(str)
    eliminate = QtCore.Signal(str)

    def __init__(self, choice, images_dir, body_size, selected, eliminated,
                 eliminator_on, state="none", parent=None, question_points=0.0):
        super().__init__(parent)
        self.letter = choice.letter
        self.setCursor(QtCore.Qt.PointingHandCursor)
        text = " ".join(b.text for b in choice.blocks if b.kind == "text").strip()
        name = (Lf("Answer %1$@: %2$@", choice.letter, text) if text
                else Lf("Answer %@", choice.letter))
        if selected:
            name += ", " + L("selected")
        if eliminated:
            name += ", " + L("crossed out")
        self.setAccessibleName(name)
        self.setFocusPolicy(QtCore.Qt.StrongFocus)

        fill, edge = CANVAS, BORDER
        bubble_fill, bubble_text = "transparent", INK
        if state == "correct":
            fill, edge, bubble_fill, bubble_text = CORRECT_SOFT, CORRECT, CORRECT, CANVAS
        elif state == "incorrect":
            fill, edge, bubble_fill, bubble_text = WRONG_SOFT, WRONG, WRONG, CANVAS
        elif selected:
            fill, edge, bubble_fill, bubble_text = ACCENT_SOFT, ACCENT, ACCENT_FILL, ON_BRAND

        width = 2 if (selected or state != "none") else 1
        self.setStyleSheet(
            f"ChoiceRow{{background:{fill}; border:{width}px solid {edge}; border-radius:8px;}}")

        outer = QtWidgets.QHBoxLayout(self)
        outer.setContentsMargins(13, 11, 13, 11)
        outer.setSpacing(11)

        bubble = QtWidgets.QLabel(choice.letter)
        bubble.setFixedSize(24, 24)
        bubble.setAlignment(QtCore.Qt.AlignCenter)
        bubble.setStyleSheet(
            f"background:{bubble_fill}; color:{bubble_text}; border:1px solid {edge};"
            f"border-radius:12px; font-weight:600; font-size:12px;")
        bubble_box = QtWidgets.QWidget()
        bubble_box.setStyleSheet("background:transparent;")
        self._bubble_lay = QtWidgets.QVBoxLayout(bubble_box)
        self._bubble_lay.setContentsMargins(0, 0, 0, 0)
        self._bubble_lay.addWidget(bubble)
        outer.addWidget(bubble_box, 0, QtCore.Qt.AlignVCenter)

        content = Blocks(choice.blocks, images_dir, body_size,
                         question_points=question_points, chrome=CHOICE_CHROME,
                         pass_clicks=True)
        if all(b.kind == "text" for b in choice.blocks):
            content.setSizePolicy(QtWidgets.QSizePolicy.Preferred,
                                  QtWidgets.QSizePolicy.Preferred)
        if eliminated:
            content.setStyleSheet("color:#8A8A8A;")
            eff = QtWidgets.QGraphicsOpacityEffect(content)
            eff.setOpacity(0.45)
            content.setGraphicsEffect(eff)
        self._content = content
        self._ink = None
        if (len(choice.blocks) == 1 and choice.blocks[0].kind == "image"
                and not has_words(choice.blocks[0])):
            self._ink = ink_middle(os.path.join(images_dir, choice.blocks[0].image_name))
            content.installEventFilter(self)
        outer.addWidget(content, 1)

        self._eliminated = eliminated
        if eliminator_on:
            btn = QtWidgets.QPushButton(L("Undo") if eliminated else choice.letter)
            btn.setToolTip(L("Bring this choice back") if eliminated
                           else L("Cross out this choice"))
            btn.setAccessibleName(L("Bring this choice back") if eliminated
                                  else Lf("Cross out choice %@", choice.letter))
            btn.setFixedSize(ELIMINATOR_WIDTH, 24)
            btn.setCursor(QtCore.Qt.PointingHandCursor)
            btn.setStyleSheet(
                f"QPushButton{{border:1px solid {BORDER}; border-radius:12px;"
                f"background:{CANVAS}; color:{ACCENT if eliminated else INK}; font-size:11px;}}")
            btn.clicked.connect(lambda: self.eliminate.emit(self.letter))
            if not eliminated:
                mark = _StrikeLine(btn, alpha=1.0)
                mark.setGeometry((ELIMINATOR_WIDTH - 18) // 2, 0, 18, 24)
            outer.addWidget(btn, 0, QtCore.Qt.AlignVCenter)
            self._eliminate_btn = btn
        else:
            spacer = QtWidgets.QWidget()
            spacer.setFixedSize(ELIMINATOR_WIDTH, 1)
            outer.addWidget(spacer, 0, QtCore.Qt.AlignTop)

        self._strike = None
        if eliminated:
            self._strike = _StrikeLine(self)
            self._strike.raise_()

    def resizeEvent(self, event):
        super().resizeEvent(event)
        strike = getattr(self, "_strike", None)
        if strike is not None:
            btn = getattr(self, "_eliminate_btn", None)
            end = btn.geometry().left() - 8 if btn is not None else self.width() - 12
            strike.setGeometry(12, 0, max(0, end - 12), self.height())
            strike.raise_()

    def eventFilter(self, obj, e):
        if obj is self._content and e.type() in (QtCore.QEvent.Resize, QtCore.QEvent.Show):
            self._centre_ink()
        return super().eventFilter(obj, e)

    def _centre_ink(self):
        fig = next((f for f in self._content.findChildren(Figure) if not f.isHidden()), None)
        pm = fig.pixmap() if fig is not None else None
        if pm is None or pm.isNull():
            return
        size = pm.deviceIndependentSize().toSize()
        drawn = QtWidgets.QStyle.alignedRect(fig.layoutDirection(), fig.alignment(),
                                             size, fig.contentsRect())
        ink = fig.mapTo(self._content, drawn.topLeft()).y() + self._ink * drawn.height()
        shift = int(round(self._content.height() - 2 * ink))
        margins = (0, max(-shift, 0), 0, max(shift, 0))
        now = self._bubble_lay.contentsMargins()
        if (now.top(), now.bottom()) != (margins[1], margins[3]):
            self._bubble_lay.setContentsMargins(*margins)

    def mousePressEvent(self, event):
        self.clicked.emit(self.letter)

    def keyPressEvent(self, event):
        if event.key() in (QtCore.Qt.Key_Space, QtCore.Qt.Key_Return, QtCore.Qt.Key_Enter):
            self.clicked.emit(self.letter)
            return
        super().keyPressEvent(event)


class ExamScreen(QtWidgets.QWidget):

    finished = QtCore.Signal()
    left = QtCore.Signal()

    TYPING = (QtWidgets.QLineEdit, QtWidgets.QPlainTextEdit, QtWidgets.QTextEdit,
              QtWidgets.QAbstractSpinBox, QtWidgets.QComboBox)

    def __init__(self, store: Store, session: Session, parent=None):
        super().__init__(parent)
        self.store = store
        self.session = session
        self.body_size = chosen_body_size()
        self.eliminator_on = False
        self.timer_hidden = False
        self.five_minute_warning = False
        self.selection = None
        self.setObjectName("examScreen")
        self.setStyleSheet(f"QWidget#examScreen{{background:{CANVAS};}}")
        self.setAttribute(QtCore.Qt.WA_StyledBackground, True)

        root = QtWidgets.QVBoxLayout(self)
        root.setContentsMargins(0, 0, 0, 0)
        root.setSpacing(0)

        root.addWidget(self._header())
        root.addWidget(self._banner())
        self.turn_banner = self._turn_banner()
        if self.turn_banner is not None:
            root.addWidget(self.turn_banner)
        self.highlight_bar = self._highlight_bar()
        _keep = self.highlight_bar.sizePolicy()
        _keep.setRetainSizeWhenHidden(True)
        self.highlight_bar.setSizePolicy(_keep)
        self.highlight_bar.setVisible(False)
        root.addWidget(self.highlight_bar)
        self.body_area = QtWidgets.QWidget()
        self.body_layout = QtWidgets.QVBoxLayout(self.body_area)
        self.body_layout.setContentsMargins(0, 0, 0, 0)
        root.addWidget(self.body_area, 1)
        root.addWidget(self._footer())

        self.tick = QtCore.QTimer(self)
        self.tick.setTimerType(QtCore.Qt.PreciseTimer)
        self.tick.timeout.connect(self._on_tick)
        self.tick.start(1000)

        self.render_question()

    def showEvent(self, event):
        super().showEvent(event)
        QtWidgets.QApplication.instance().installEventFilter(self)

    def hideEvent(self, event):
        QtWidgets.QApplication.instance().removeEventFilter(self)
        super().hideEvent(event)

    def eventFilter(self, obj, e):
        if (e.type() == QtCore.QEvent.KeyPress and isinstance(obj, QtWidgets.QWidget)
                and not isinstance(obj, self.TYPING)
                and self.isVisible() and obj.window() is self.window()
                and QtWidgets.QApplication.activeModalWidget() is None
                and QtWidgets.QApplication.activePopupWidget() is None
                and self._answer_key(e)):
            return True
        return super().eventFilter(obj, e)

    def _header(self):
        bar = QtWidgets.QWidget()
        bar.setObjectName("examHeader")
        bar.setStyleSheet(
            f"QWidget#examHeader{{background:{CARD}; border-bottom:1px solid {HAIRLINE};}}")
        lay = QtWidgets.QHBoxLayout(bar)
        lay.setContentsMargins(24, 12, 24, 11)

        left = QtWidgets.QVBoxLayout()
        title = self.title_label = QtWidgets.QLabel(self._title_text())
        title.setStyleSheet(
            f"color:{NAVY}; font-size:16px; font-weight:600; font-family:{SERIF};"
            "background:transparent;")
        directions = QtWidgets.QPushButton(L("Directions") + "  ˅")
        directions.setFlat(True)
        directions.setCursor(QtCore.Qt.PointingHandCursor)
        directions.setStyleSheet(
            f"QPushButton{{border:none; color:{MUTED}; font-size:11px; text-align:left;"
            "background:transparent;}")
        directions.clicked.connect(self._show_directions)
        left.addWidget(title)
        left.addWidget(directions, 0, QtCore.Qt.AlignLeft)
        self.subtitle = QtWidgets.QLabel(self._subtitle_text())
        self.subtitle.setStyleSheet(
            f"color:{MUTED}; font-size:10px; background:transparent;")
        left.addWidget(self.subtitle, 0, QtCore.Qt.AlignLeft)
        lay.addLayout(left, 1)

        centre = QtWidgets.QVBoxLayout()
        self.timer_label = QtWidgets.QLabel()
        self.timer_label.setAlignment(QtCore.Qt.AlignCenter)
        self.hide_btn = QtWidgets.QPushButton(L("Hide"))
        self.hide_btn.setCursor(QtCore.Qt.PointingHandCursor)
        self.hide_btn.setFixedWidth(74)
        self.hide_btn.setStyleSheet(
            f"QPushButton{{border:1px solid {BORDER}; border-radius:2px;"
            f"padding:2px 12px; color:{NAVY}; font-size:10px; background:transparent;}}")
        self.hide_btn.clicked.connect(self._toggle_timer)
        self.hide_btn.setAccessibleName(L("Hide the timer"))
        centre.addWidget(self.timer_label)
        centre.addWidget(self.hide_btn, 0, QtCore.Qt.AlignHCenter)
        lay.addLayout(centre, 1)

        right = QtWidgets.QHBoxLayout()
        right.setSpacing(18)
        right.addWidget(self._tool("A-", lambda: self._zoom(-1),
                                   L("Smaller text")))
        right.addWidget(self._tool("A+", lambda: self._zoom(1),
                                   L("Larger text")))
        self.reference_btn = self._tool(
            L("Reference"), self._show_reference,
            L("Formulas and figures provided on the Math section"))
        self.reference_btn.setVisible(fulltest.offers_reference(self.session))
        right.addWidget(self.reference_btn)
        q = self.session.questions[self.session.index]
        n = self.store.annotation_count(self.session.bank_id, q.id)
        right.addWidget(self._tool(
            L("Highlights & Notes").replace("&", "&&")
            + (f"  ({n})" if n else ""),
            self._show_notes,
            L("Everything you have highlighted or noted on this question")))
        right.addWidget(self._tool(L("More"), self._show_more))
        lay.addLayout(right, 1)
        lay.setAlignment(right, QtCore.Qt.AlignRight)

        self._refresh_timer()
        return bar

    def _tool(self, text, slot, tip=""):
        b = QtWidgets.QPushButton(text)
        b.setFlat(True)
        if tip:
            b.setToolTip(tip)
            if len(text) <= 2:
                b.setAccessibleName(tip)
        b.setCursor(QtCore.Qt.PointingHandCursor)
        b.setStyleSheet(
            f"QPushButton{{border:none; color:{NAVY}; font-size:10px;"
            "background:transparent;}")
        b.clicked.connect(slot)
        return b

    def _banner(self):
        lbl = QtWidgets.QLabel(L("THIS IS A PRACTICE TEST"))
        lbl.setAlignment(QtCore.Qt.AlignCenter)
        lbl.setStyleSheet(
            f"background:{BRASS_SOFT}; color:{NAVY}; font-size:9px; font-weight:600;"
            f"letter-spacing:2px; padding:5px; border-top:1px solid {BRASS};"
            f"border-bottom:1px solid {BRASS};")
        return lbl

    PROFILE_ACCENTS = ["#1C2950", "#9E7833", "#4A6155", "#7B403D", "#455473",
                       "#665070"]

    def _turn_banner(self):
        if not self.session.is_double:
            return None
        label = QtWidgets.QLabel()
        label.setAlignment(QtCore.Qt.AlignCenter)
        return label

    def _refresh_turn(self):
        if getattr(self, "turn_banner", None) is None:
            return
        seat = self.session.turn(self.session.index)
        accents = self.session.turn_accents
        index = accents[seat] if seat < len(accents) else seat
        tint = self.PROFILE_ACCENTS[index % len(self.PROFILE_ACCENTS)]
        name = self.session.turn_name(self.session.index).upper()
        self.turn_banner.setText(f"{name}  ·  " + L("your turn"))
        self.turn_banner.setStyleSheet(
            f"background:{tint}; color:#FFFFFF; font-size:11px; font-weight:600;"
            "letter-spacing:1px; padding:6px;")

    def _footer(self):
        bar = QtWidgets.QWidget()
        bar.setObjectName("examFooter")
        bar.setStyleSheet(
            f"QWidget#examFooter{{background:{CHROME}; border-top:1px solid {HAIRLINE};}}")
        lay = QtWidgets.QHBoxLayout(bar)
        lay.setContentsMargins(22, 10, 22, 10)

        name = ElidedLabel(self.session.bank_name)
        name.setStyleSheet(f"color:{MUTED}; font-size:11px; background:transparent;")
        lay.addWidget(name, 1)

        self.nav_btn = QtWidgets.QPushButton()
        self.nav_btn.setCursor(QtCore.Qt.PointingHandCursor)
        self.nav_btn.setStyleSheet(
            f"QPushButton{{background:{NAVY}; color:{CARD}; border-radius:3px;"
            "padding:7px 16px; font-size:12px; font-weight:600;}")
        self.nav_btn.clicked.connect(self._show_navigator)
        lay.addWidget(self.nav_btn, 0, QtCore.Qt.AlignCenter)

        right = QtWidgets.QHBoxLayout()
        right.setSpacing(10)
        self.back_btn = QtWidgets.QPushButton(L("Back"))
        self.back_btn.setCursor(QtCore.Qt.PointingHandCursor)
        self.back_btn.setStyleSheet(
            f"QPushButton{{background:{SUBTLE}; color:{INK}; border:1px solid {HAIRLINE};"
            "border-radius:3px; padding:9px 22px; font-size:13px; font-weight:600;}")
        self.back_btn.clicked.connect(lambda: self._move(-1))
        self.next_btn = QtWidgets.QPushButton(L("Next"))
        self.next_btn.setCursor(QtCore.Qt.PointingHandCursor)
        self.next_btn.setStyleSheet(
            f"QPushButton{{background:{ACCENT_FILL}; color:{ON_BRAND}; border-radius:3px;"
            "padding:9px 22px; font-size:13px; font-weight:600;}")
        self.next_btn.clicked.connect(self._next_or_submit)
        right.addWidget(self.back_btn)
        right.addWidget(self.next_btn)
        holder = QtWidgets.QWidget()
        holder.setLayout(right)
        lay.addWidget(holder, 1, QtCore.Qt.AlignRight)
        return bar

    def _title_text(self):
        return fulltest.module_title(self.session) or self.session.display_title

    def _subtitle_text(self):
        module = fulltest.current_module(self.session)
        pieces = [fulltest.module_progress_line(self.session)
                  or self.session.subtitle_line]
        if module is not None and module.form != fulltest.MIXED:
            pieces.append(fulltest.form_label(module.form))
        return " · ".join(p for p in pieces if p)

    def render_question(self):
        self.reference_btn.setVisible(fulltest.offers_reference(self.session))
        if hasattr(self, "subtitle"):
            self.subtitle.setText(self._subtitle_text())
            self.title_label.setText(self._title_text())
        self.selection = None
        self._column_fitted = None
        self._refresh_turn()
        if hasattr(self, "highlight_bar"):
            self.highlight_bar.setVisible(False)
        while self.body_layout.count():
            item = self.body_layout.takeAt(0)
            if item.widget():
                item.widget().deleteLater()

        q = self.session.questions[self.session.index]
        images = self.store.images_dir(self.session.bank_id)

        if q.subject == "reading_writing" and q.stimulus:
            split = QtWidgets.QSplitter(QtCore.Qt.Horizontal)
            split.addWidget(self._scroller(
                self._annotatable(q.stimulus, "stimulus", images,
                                  question_points=widest_region(q.stimulus)),
                L("Passage")))
            questions = self._scroller(self._question_column(q, images),
                                       self._pane_name())
            questions.setMinimumWidth(
                questions.widget().minimumSizeHint().width()
                + questions.verticalScrollBar().sizeHint().width())
            split.addWidget(questions)
            fraction = _split_fraction(self.session)
            split.setSizes([int(1000 * fraction), 1000 - int(1000 * fraction)])
            split.splitterMoved.connect(lambda *_, s=split: self._split_moved(s))
            self.body_layout.addWidget(split)
        else:
            col = QtWidgets.QWidget()
            v = QtWidgets.QVBoxLayout(col)
            v.setContentsMargins(0, 0, 0, 0)
            if q.stimulus:
                v.addWidget(self._annotatable(q.stimulus, "stimulus", images,
                                              question_points=self._question_points(q)))
            v.addWidget(self._question_column(q, images))
            v.addStretch(1)
            width = column_width(q, self.body_size, self._available(),
                                 with_rationale=self._shows_rationale())
            wrap = centered_column(col, width)
            self.body_layout.addWidget(self._scroller(wrap, self._pane_name()))

        module = fulltest.current_module(self.session)
        first = module.start if module is not None else 0
        total = module.count if module is not None else len(self.session.questions)
        self.nav_btn.setText(
            Lf("Question %1$d of %2$d", self.session.index - first + 1,
               total) + "  ˄")
        self.nav_btn.setAccessibleName(
            L("Go to question") + ", "
            + Lf("Question %1$d of %2$d", self.session.index - first + 1, total))
        self.back_btn.setVisible(self.session.index > first)
        self._order_tabs()
        last = first + total - 1
        if module is not None:
            index = fulltest.current_module_index(self.session)
            final = index is not None and index + 1 >= len(self.session.modules)
            self.next_btn.setText(L("Next"))
        else:
            self.next_btn.setText(L("Next"))

    def _split_moved(self, split):
        sizes = split.sizes()
        total = sum(sizes)
        if not total:
            return
        fraction = sizes[0] / float(total)
        held = min(SPLIT_RANGE[1], max(SPLIT_RANGE[0], fraction))
        if held != fraction:
            left = int(round(total * held))
            split.blockSignals(True)
            split.setSizes([left, total - left])
            split.blockSignals(False)
        _SPLIT["fraction"] = held

    def _available(self):
        return max(0, self.width() - 52)

    def _shows_rationale(self):
        return self.session.config.get("grading") == "immediate"

    def resizeEvent(self, event):
        super().resizeEvent(event)
        self._fit_column()

    def _fit_column(self):
        available = self._available()
        if available <= 0 or available == getattr(self, "_column_fitted", None):
            return
        self._column_fitted = available
        q = self.session.questions[self.session.index]
        width = column_width(q, self.body_size, available,
                             with_rationale=self._shows_rationale())
        for w in self.findChildren(QtWidgets.QWidget):
            if w.property("satColumn"):
                w.setMaximumWidth(int(width))
        QtCore.QTimer.singleShot(0, self._refit_figures)

    def _pane_name(self):
        module = fulltest.current_module(self.session)
        first = module.start if module is not None else 0
        total = module.count if module is not None else len(self.session.questions)
        return Lf("Question %1$d of %2$d", self.session.index - first + 1, total)

    def _order_tabs(self):
        if not self.body_layout.count() or self.body_layout.itemAt(0).widget() is None:
            return
        body = self.body_layout.itemAt(0).widget()
        panes = ([body] if isinstance(body, QtWidgets.QScrollArea)
                 else body.findChildren(QtWidgets.QScrollArea))
        def place(w):
            p = w.mapTo(body, QtCore.QPoint(0, 0))
            depth, up = 0, w
            while up is not None and up is not body:
                depth, up = depth + 1, up.parentWidget()
            return (p.y(), p.x(), depth)

        named = [w for w in panes if w.accessibleName()]
        inside = [w for w in body.findChildren(QtWidgets.QWidget)
                  if (w.focusPolicy() & QtCore.Qt.TabFocus) and not w.isHidden()
                  and w not in named and not isinstance(w, QtWidgets.QScrollBar)]
        chain = sorted(named + inside, key=place)
        chain += [self.nav_btn, self.back_btn, self.next_btn]
        for a, b in zip(chain, chain[1:]):
            QtWidgets.QWidget.setTabOrder(a, b)
        letter, self._refocus = getattr(self, "_refocus", None), None
        for row in body.findChildren(ChoiceRow):
            if letter and row.letter == letter:
                row.setFocus(QtCore.Qt.OtherFocusReason)

    def _refit_figures(self):
        for figure in self.findChildren(Figure):
            figure._apply()

    def _scroller(self, widget, name=""):
        area = QtWidgets.QScrollArea()
        area.setAccessibleName(name)
        area.setWidgetResizable(True)
        area.setFrameShape(QtWidgets.QFrame.NoFrame)
        area.setStyleSheet(SCROLLBAR)
        holder = QtWidgets.QWidget()
        lay = QtWidgets.QVBoxLayout(holder)
        lay.setContentsMargins(26, 18, 26, 18)
        lay.addWidget(widget)
        lay.addStretch(1)
        bar = area.verticalScrollBar()

        def keep_width(_low=0, high=None, lay=lay, bar=bar):
            high = bar.maximum() if high is None else high
            lay.setContentsMargins(26, 18, 26 if high > 0 else 26 + bar.sizeHint().width(), 18)

        bar.rangeChanged.connect(keep_width)
        keep_width()
        holder.setObjectName("examPage")
        holder.setStyleSheet(f"QWidget#examPage{{background:{CANVAS};}}")
        area.setWidget(holder)
        area.setStyleSheet(SCROLLBAR + f"QScrollArea{{background:{CANVAS};}}")
        return area

    def _question_points(self, q):
        body, _ = question_width(q, self._shows_rationale())
        return body

    def _question_column(self, q, images):
        col = QtWidgets.QWidget()
        lay = QtWidgets.QVBoxLayout(col)
        lay.setContentsMargins(0, 0, 0, 0)
        lay.setSpacing(14)

        body_points, choice_points = question_width(q, self._shows_rationale())

        lay.addWidget(self._question_bar(q))
        if q.prompt:
            lay.addWidget(self._annotatable(q.prompt, "prompt", images,
                                            question_points=body_points))

        attempt = self.session.attempts[self.session.index]
        graded = self.session.config.get("grading") == "immediate" and attempt.revealed

        if q.kind == "multiple_choice":
            for c in q.choices:
                state = "none"
                if graded:
                    if c.letter == q.correct_answer:
                        state = "correct"
                    elif c.letter == attempt.response:
                        state = "incorrect"
                row = ChoiceRow(c, images, self.body_size,
                                selected=attempt.response == c.letter,
                                eliminated=c.letter in attempt.eliminated,
                                eliminator_on=self.eliminator_on, state=state,
                                question_points=choice_points)
                row.clicked.connect(self._select)
                row.eliminate.connect(self._toggle_eliminate)
                lay.addWidget(row)
        else:
            field = GridInField(attempt.response, self.body_size, 260, locked=graded)
            field.changed.connect(self._set_response)
            lay.addWidget(field)

        self._feedback_host = None
        if self.session.config.get("grading") == "immediate":
            host = QtWidgets.QWidget()
            host_lay = QtWidgets.QVBoxLayout(host)
            host_lay.setContentsMargins(0, 0, 0, 0)
            host_lay.addWidget(self._feedback(q, attempt, images))
            lay.addWidget(host)
            self._feedback_host = host

        lay.addStretch(1)
        return col

    def _annotatable(self, blocks, field, images, question_points=0.0):
        q = self.session.questions[self.session.index]
        return Blocks(blocks, images, self.body_size,
                      annotatable=True, field=field,
                      annotations=self.store.annotations(self.session.bank_id, q.id),
                      on_select=self._on_select,
                      on_annotation=self._open_note,
                      question_points=question_points)

    def _on_select(self, field, block, start, end):
        self.selection = None if start < 0 else (field, block, start, end)
        self.highlight_bar.setVisible(self.selection is not None)

    def _highlight_bar(self):
        bar = QtWidgets.QWidget()
        bar.setObjectName("highlightBar")
        bar.setStyleSheet(
            f"QWidget#highlightBar{{background:{BRASS_SOFT}; "
            f"border-bottom:1px solid {BRASS};}}")
        lay = QtWidgets.QHBoxLayout(bar)
        lay.setContentsMargins(22, 8, 22, 8)
        lay.setSpacing(10)

        label = QtWidgets.QLabel(L("Highlight").upper())
        label.setStyleSheet(
            f"color:{MUTED}; font-size:10px; font-weight:600; letter-spacing:1.5px;"
            "background:transparent;")
        lay.addWidget(label)

        for i in range(len(HIGHLIGHTS)):
            swatch = QtWidgets.QPushButton()
            swatch.setFixedSize(18, 18)
            swatch.setCursor(QtCore.Qt.PointingHandCursor)
            swatch.setToolTip(L("Highlight the selected text"))
            swatch.setAccessibleName(L("Highlight the selected text"))
            swatch.setStyleSheet(
                f"QPushButton{{background:{highlight_color(i)}; border:1px solid {BORDER};"
                "border-radius:9px;}")
            swatch.clicked.connect(lambda _=False, c=i: self._add_highlight(c))
            lay.addWidget(swatch)

        note = QtWidgets.QPushButton(L("Add note"))
        note.setFlat(True)
        note.setCursor(QtCore.Qt.PointingHandCursor)
        note.setStyleSheet(
            f"QPushButton{{border:none; color:{NAVY}; font-size:11px; font-weight:600;"
            "background:transparent;}")
        note.clicked.connect(lambda: self._add_highlight(0, with_note=True))
        lay.addWidget(note)
        lay.addStretch(1)
        return bar

    def _add_highlight(self, color, with_note=False):
        if not self.selection:
            return
        field, block, start, end = self.selection
        q = self.session.questions[self.session.index]
        created = self.store.add_annotation(self.session.bank_id, q.id, field, block,
                                            start, end, color=color)
        self.selection = None
        self.render_question()
        if with_note:
            self._open_note(created["id"])

    def _open_note(self, ann_id):
        q = self.session.questions[self.session.index]
        match = next((a for a in self.store.annotations(self.session.bank_id, q.id)
                      if a["id"] == ann_id), None)
        if not match:
            return
        dialog = NoteDialog(self.store, self.session.bank_id, match, self)
        dialog.exec()
        self.render_question()

    def _show_notes(self):
        q = self.session.questions[self.session.index]
        NotesDialog(self.store, self.session.bank_id, q, self).exec()
        self.render_question()

    def _question_bar(self, q):
        bar = QtWidgets.QWidget()
        bar.setObjectName("questionBar")
        bar.setStyleSheet(
            f"QWidget#questionBar{{background:{CHROME}; border-bottom:1px solid {HAIRLINE};}}")
        lay = QtWidgets.QHBoxLayout(bar)
        lay.setContentsMargins(10, 7, 10, 7)

        num = QtWidgets.QLabel(str(self.session.index + 1))
        num.setFixedSize(24, 24)
        num.setAlignment(QtCore.Qt.AlignCenter)
        num.setStyleSheet(
            f"QLabel{{background:{NAVY}; color:{CARD}; font-weight:700; font-size:13px;"
            "border:none;}")
        lay.addWidget(num)

        attempt = self.session.attempts[self.session.index]
        mark = QtWidgets.QCheckBox(L("Mark for Review"))
        mark.setChecked(attempt.marked)
        mark.setCursor(QtCore.Qt.PointingHandCursor)
        mark.setStyleSheet(
            f"QCheckBox{{color:{INK}; font-size:12px; border:none;"
            "background:transparent;}"
            + brand.control_style("check", BRAND_FILL, ON_BRAND,
                                  CARD, BORDER, MUTED))
        mark.toggled.connect(self._set_marked)
        lay.addWidget(mark)

        aside_on = self.store.is_set_aside(self.session.bank_id, q.id)
        aside = brand.IconButton("tray", L("Set aside"),
                                 BRASS if aside_on else INK, BRASS, size=11)
        aside.setFlat(True)
        aside.setToolTip(L("Keep this question to look at again at the end of your study time"))
        aside.setStyleSheet(
            f"QPushButton{{border:none; font-size:12px; background:transparent;"
            f"color:{BRASS if aside_on else INK};"
            f"font-weight:{'600' if aside_on else '400'};}}")
        aside.clicked.connect(self._toggle_set_aside)
        lay.addWidget(aside)
        lay.addStretch(1)

        if q.kind == "multiple_choice":
            elim = QtWidgets.QPushButton("ABC")
            elim.setCheckable(True)
            elim.setChecked(self.eliminator_on)
            elim.setFixedSize(40, 24)
            elim.setCursor(QtCore.Qt.PointingHandCursor)
            elim.setToolTip(L("Answer Eliminator — cross out choices you have ruled out"))
            elim.setAccessibleName(L("Answer Eliminator — cross out choices you have ruled out"))
            elim.setStyleSheet(
                f"QPushButton{{border:1px solid {BORDER}; border-radius:4px;"
                f"background:{CANVAS}; color:{INK}; font-size:9px; font-weight:700;}}"
                f"QPushButton:checked{{background:{ACCENT_FILL}; color:{ON_BRAND};"
                f"border-color:{ACCENT_FILL};}}")
            elim.toggled.connect(self._toggle_eliminator)
            lay.addWidget(elim)
        return bar

    def _feedback(self, q, attempt, images):
        box = QtWidgets.QWidget()
        lay = QtWidgets.QVBoxLayout(box)
        lay.setContentsMargins(14, 12, 14, 12)

        if not attempt.revealed:
            if attempt.answered:
                btn = QtWidgets.QPushButton(L("Check answer"))
                btn.setCursor(QtCore.Qt.PointingHandCursor)
                btn.setStyleSheet(
                    f"QPushButton{{border:1px solid {ACCENT}; color:{ACCENT};"
                    "border-radius:3px; padding:8px 20px; font-size:13px; font-weight:600;}")
                btn.clicked.connect(self._reveal)
                lay.addWidget(btn, 0, QtCore.Qt.AlignLeft)
            return box

        ok = is_correct(q, attempt.response)
        box.setStyleSheet(
            f"background:{CORRECT_SOFT if ok else WRONG_SOFT}; border-radius:8px;")
        head = QtWidgets.QLabel(
            L("Correct") if ok
            else Lf("Not quite — the answer is %@", q.correct_answer))
        head.setStyleSheet(
            f"color:{CORRECT if ok else WRONG}; font-size:13px; font-weight:600;")
        lay.addWidget(head)
        if q.rationale:
            why = QtWidgets.QLabel(L("Why"))
            why.setStyleSheet(f"color:{MUTED}; font-size:12px; font-weight:600;")
            lay.addWidget(why)
            lay.addWidget(Blocks(q.rationale, images, self.body_size - 1,
                                 question_points=self._question_points(q)))
        return box

    def _select(self, letter):
        a = self.session.attempts[self.session.index]
        if letter in a.eliminated:
            a.eliminated.remove(letter)
        a.response = letter
        self.store.save_session(self.session)
        self._keep_focus(letter)
        self.render_question()

    def _keep_focus(self, letter):
        focused = QtWidgets.QApplication.focusWidget()
        self._refocus = letter if isinstance(focused, ChoiceRow) else None

    def _toggle_eliminate(self, letter):
        a = self.session.attempts[self.session.index]
        if letter in a.eliminated:
            a.eliminated.remove(letter)
        else:
            a.eliminated.append(letter)
            if a.response == letter:
                a.response = ""
        self.store.save_session(self.session)
        self.render_question()

    def _toggle_eliminator(self, on):
        self.eliminator_on = on
        self.render_question()

    def _set_response(self, text):
        attempt = self.session.attempts[self.session.index]
        was = attempt.answered
        attempt.response = text
        self.store.save_session(self.session)
        host = getattr(self, "_feedback_host", None)
        if (host is not None and shiboken6.isValid(host)
                and was != attempt.answered and not attempt.revealed):
            host_lay = host.layout()
            while host_lay.count():
                old = host_lay.takeAt(0).widget()
                if old is not None:
                    old.hide()
                    old.deleteLater()
            q = self.session.questions[self.session.index]
            host_lay.addWidget(self._feedback(q, attempt, None))

    def _toggle_set_aside(self):
        q = self.session.questions[self.session.index]
        self.store.toggle_set_aside(self.session.bank_id, q.id)
        self.render_question()

    def _set_marked(self, on):
        self.session.attempts[self.session.index].marked = on
        self.store.save_session(self.session)

    def _reveal(self):
        self.session.attempts[self.session.index].revealed = True
        self.store.save_session(self.session)
        self.render_question()

    def _move(self, delta):
        i = self.session.index + delta
        if fulltest.can_move(self.session, i):
            self.session.index = i
            self.store.save_session(self.session)
            self.render_question()

    def keyPressEvent(self, e):
        if not self._answer_key(e):
            super().keyPressEvent(e)

    def _answer_key(self, e):
        typing = isinstance(QtWidgets.QApplication.focusWidget(), self.TYPING)
        if typing or e.modifiers() not in (QtCore.Qt.NoModifier, QtCore.Qt.KeypadModifier):
            return False
        if e.key() == QtCore.Qt.Key_Left:
            self._move(-1)
            return True
        if e.key() == QtCore.Qt.Key_Right:
            self._move(1)
            return True
        q = self.session.questions[self.session.index]
        a = self.session.attempts[self.session.index]
        locked = self.session.config.get("grading") == "immediate" and a.revealed
        letter = e.text().upper()
        if not any(c.letter == letter for c in q.choices) and 0x41 <= e.nativeVirtualKey() <= 0x5A:
            letter = chr(e.nativeVirtualKey())
        if (q.kind == "multiple_choice" and not locked and letter
                and any(c.letter == letter for c in q.choices)):
            self._select(letter)
            return True
        return False

    def _next_or_submit(self):
        if fulltest.is_full_test(self.session):
            module = fulltest.current_module(self.session)
            if module is not None and self.session.index >= module.end - 1:
                self._show_review()
                return
            self._move(1)
            return
        if self.session.index < len(self.session.questions) - 1:
            self._move(1)
        else:
            self._show_review()

    def _clock_left(self):
        if fulltest.is_full_test(self.session):
            module = fulltest.current_module(self.session)
            if module is not None:
                return module.seconds_remaining
        return self.session.seconds_remaining

    def _spend_a_second(self):
        if fulltest.is_full_test(self.session):
            module = fulltest.current_module(self.session)
            if module is not None:
                module.seconds_remaining -= 1
                return
        self.session.seconds_remaining -= 1

    def _submit_module(self):
        module = fulltest.current_module(self.session)
        if module is None:
            self._submit()
            return
        index = fulltest.current_module_index(self.session)
        last = index is not None and index + 1 >= len(self.session.modules)
        unanswered = sum(1 for i in range(module.start, module.end)
                         if i < len(self.session.attempts)
                         and not self.session.attempts[i].response)
        parts = []
        if unanswered:
            parts.append(Lp(unanswered, "%d question is unanswered",
                            "%d questions are unanswered"))
        parts.append(L("This ends the test and shows your results.") if last
                     else L("You cannot come back to this module once it is "
                            "handed in, the same as on the real test."))
        if not brand.ask(
                self,
                L("Finish the test?") if last else L("Submit this module?"),
                ". ".join(parts),
                accept=L("Hand it in")):
            return
        self._hand_in_module()

    def _hand_in_module(self):
        module = fulltest.current_module(self.session)
        index = fulltest.current_module_index(self.session)
        if module is None or index is None:
            self._submit()
            return
        module.submitted = True
        module.seconds_remaining = 0

        if index + 1 >= len(self.session.modules):
            self.tick.stop()
            self.store.finish_session(self.session)
            self.finished.emit()
            return

        self._route_if_adaptive(index)
        following = self.session.modules[index + 1]
        self.session.index = following.start
        self.store.save_session(self.session)

        if module.break_after > 0:
            self.tick.stop()
            self._take_break(module.break_after, following)
        if not self.tick.isActive():
            self.tick.start(1000)
        self.five_minute_warning = False
        self.timer_hidden = False
        self.render_question()
        self._refresh_timer()

    def _take_break(self, minutes, following):
        BreakDialog(minutes, following, self).exec()

    def _route_if_adaptive(self, index):
        following = self.session.modules[index + 1]
        if following.number != 2:
            return
        options = getattr(self.session, "adaptive", None) or {}
        option = options.get(following.id)
        if not option:
            return
        correct, _answered = fulltest.score(self.session,
                                            self.session.modules[index])
        form = fulltest.route(correct, self.session.modules[index].count)
        chosen = option.upper if form == fulltest.UPPER else option.lower
        if len(chosen) != following.count:
            return
        following.form = form
        self.session.questions[following.start:following.end] = list(chosen)
        for i, question in enumerate(chosen):
            at = following.start + i
            if at < len(self.session.attempts):
                self.session.attempts[at] = Attempt(question.id)

    def _submit(self):
        unanswered = len(self.session.questions) - self.session.answered_count
        marked = sum(1 for a in self.session.attempts if a.marked)
        bits = []
        if unanswered:
            bits.append(Lf("%d unanswered", unanswered))
        if marked:
            bits.append(Lf("%d marked for review", marked))
        msg = (L("All questions are answered.") if not bits
               else Lf("You have %@.", L(" and ").join(bits)))
        if not brand.ask(self, L("Submit this section?"), msg,
                         accept=L("Hand it in")):
            return
        self.tick.stop()
        self.store.finish_session(self.session)
        self.finished.emit()

    def zoom_by(self, delta):
        self.body_size = (DEFAULT_BODY_PT if delta == 0
                          else max(MIN_BODY_PT, min(MAX_BODY_PT, self.body_size + delta)))
        remember_body_size(self.body_size)
        self.render_question()

    def _zoom_by(self, delta):
        self.zoom_by(delta)

    def _zoom(self, delta):
        self.zoom_by(delta)

    def _show_reference(self):
        ReferenceDialog(self).exec()

    def _show_directions(self):
        DirectionsDialog(self.session, self).exec()

    def _show_more(self):
        menu = QtWidgets.QMenu(self)
        brand.dress_menu(menu)
        stealth = menu.addAction(
            L("Turn Stealth Mode off") if brand.stealth_on()
            else L("Turn Stealth Mode on"), self._toggle_stealth)
        stealth.setToolTip(
            L("Back to the white screen the real test uses.") if brand.stealth_on()
            else L("Draw this on black, and keep the app quiet."))
        menu.addSeparator()
        leave = menu.addAction(L("Save and leave"), self._save_and_leave)
        leave.setToolTip(L("Keep your place and come back to it later."))
        module = fulltest.current_module(self.session)
        if module is not None:
            index = fulltest.current_module_index(self.session)
            final = index is not None and index + 1 >= len(self.session.modules)
            submit = menu.addAction(L("Finish test") if final else L("Submit module"),
                                    self._submit_module)
            submit.setToolTip(L("Finish now and see your results.") if final
                              else L("Hand in this module and go on to the next."))
        else:
            submit = menu.addAction(L("Submit section"), self._submit)
            submit.setToolTip(L("Finish now and see your results."))
        menu.addSeparator()
        discard = menu.addAction(L("Quit without saving"),
                                 self._quit_without_saving)
        discard.setToolTip(L("Throw this sitting away."))
        menu.setToolTipsVisible(True)
        menu.exec(QtGui.QCursor.pos())

    def _toggle_stealth(self):
        self.store.save_session(self.session)
        self.tick.stop()
        self.store.set_setting("stealthMode",
                               not bool(self.store.settings.get("stealthMode")))
        window = self.window()
        if hasattr(window, "reload_stealth"):
            window.reload_stealth()

    def _save_and_leave(self):
        self.tick.stop()
        self.store.save_session(self.session)
        self.left.emit()

    def _quit_without_saving(self):
        if brand.ask(
                self, L("Leave this test?"),
                L("Throw this sitting away."),
                accept=L("Throw it away"), destructive=True):
            self.tick.stop()
            self.store.discard_session(self.session.bank_id)
            self.left.emit()

    def _show_navigator(self):
        dlg = NavigatorDialog(self.session, self)
        if dlg.exec() and dlg.picked is not None:
            self.session.index = dlg.picked
            self.store.save_session(self.session)
            self.render_question()
        elif dlg.go_review:
            self._show_review()

    def _show_review(self):
        dlg = NavigatorDialog(self.session, self, review=True)
        if not dlg.exec():
            return
        if dlg.picked is not None:
            self.session.index = dlg.picked
            self.store.save_session(self.session)
            self.render_question()
        elif dlg.submit:
            if fulltest.current_module(self.session) is not None:
                self._submit_module()
            else:
                self._submit()

    def _toggle_timer(self):
        self.timer_hidden = not self.timer_hidden
        self.hide_btn.setText(L("Show") if self.timer_hidden else L("Hide"))
        self.hide_btn.setAccessibleName(L("Show the timer") if self.timer_hidden
                                        else L("Hide the timer"))
        self._refresh_timer()

    def _refresh_timer(self):
        if not self.session.config.get("timed"):
            self.timer_label.setText(L("Untimed"))
            self.timer_label.setStyleSheet(
                f"color:{MUTED}; font-size:12px; letter-spacing:1px;"
                "background:transparent;")
            self.hide_btn.setVisible(False)
            return
        if self.timer_hidden:
            self.timer_label.setText(brand.ICONS["clock"])
            self.timer_label.setStyleSheet(
                f"color:{MUTED}; font-size:16px; background:transparent;"
                f"font-family:'{brand.ICON_FONT}';")
            return
        low = self._clock_left() <= TIMER_WARNING_SECONDS
        self.timer_label.setText(_clock(self._clock_left()))
        self.timer_label.setStyleSheet(
            f"color:{WRONG if low else NAVY}; font-size:23px; font-weight:600;"
            f"font-family:{NUMERALS}; background:transparent;")

    def _on_tick(self):
        if not self.session.finished and 0 <= self.session.index < len(self.session.attempts):
            a = self.session.attempts[self.session.index]
            a.seconds_spent = getattr(a, "seconds_spent", 0.0) + 1
            if int(a.seconds_spent) % 15 == 0:
                self.store.save_session(self.session)

        if not self.session.config.get("timed") or self.session.finished:
            return
        if self._clock_left() <= 0:
            return
        self._spend_a_second()

        module = fulltest.current_module(self.session)
        total = (module.minutes if module is not None
                 else self.session.config.get("minutes", 0)) * 60
        if should_warn(self._clock_left(), self.five_minute_warning, total):
            self.five_minute_warning = True
            was_hidden = self.timer_hidden
            self.timer_hidden = False
            self.hide_btn.setText(L("Hide"))
            self.hide_btn.setAccessibleName(L("Hide the timer"))
            self._refresh_timer()
            text = (L("The clock is showing again so you can pace the rest of "
                      "the section.") if was_hidden
                    else L("Pace the rest of the section by the clock."))
            QtCore.QTimer.singleShot(
                0, self, lambda: brand.tell(self, L("5 minutes remaining"), text))

        self._refresh_timer()
        if int(self._clock_left()) % 10 == 0:
            self.store.save_session(self.session)
        if self._clock_left() <= 0:
            self.tick.stop()
            for sheet in self.findChildren(QtWidgets.QDialog):
                if sheet.isVisible():
                    sheet.reject()
            if fulltest.is_full_test(self.session):
                brand.tell(
                    self, L("Time's up"),
                    L("The timer has run out. Your answers have been kept."))
                self._hand_in_module()
                return
            brand.tell(
                self, L("Time's up"),
                L("The timer has run out. Your answers have been kept."))
            self.store.finish_session(self.session)
            self.finished.emit()


class BreakDialog(QtWidgets.QDialog):

    def __init__(self, minutes, following=None, parent=None):
        super().__init__(parent)
        brand.as_sheet(self, parent)
        self.following = following
        self.setWindowTitle(brand.APP_NAME)
        self.setModal(True)
        self.setMinimumSize(560, 360)
        self.left = float(minutes * 60)
        self.setStyleSheet(f"QDialog{{background:{CANVAS};}}")

        lay = QtWidgets.QVBoxLayout(self)
        lay.setContentsMargins(40, 34, 40, 30)
        lay.setSpacing(0)
        lay.addStretch(1)

        title = QtWidgets.QLabel(L("BREAK"))
        title.setAlignment(QtCore.Qt.AlignCenter)
        title.setStyleSheet(
            f"color:{MUTED}; font-size:11px; font-weight:600; letter-spacing:3px;"
            "background:transparent;")
        lay.addWidget(title)
        lay.addSpacing(14)

        self.clock = QtWidgets.QLabel()
        self.clock.setAlignment(QtCore.Qt.AlignCenter)
        self.clock.setStyleSheet(
            f"color:{NAVY}; font-size:64px; font-weight:600; font-family:{NUMERALS};"
            "background:transparent;")
        lay.addWidget(self.clock)
        lay.addSpacing(16)

        if self.following is not None:
            nxt = QtWidgets.QLabel(Lf("Next: %@", self.following.title))
            nxt.setAlignment(QtCore.Qt.AlignCenter)
            nxt.setStyleSheet(
                f"color:{INK}; font-size:14px; font-weight:600;"
                "background:transparent;")
            lay.addWidget(nxt)
            lay.addSpacing(4)
            shape = QtWidgets.QLabel(
                Lp(self.following.count, "%d question", "%d questions") + " · "
                + Lp(self.following.minutes, "%d minute", "%d minutes"))
            shape.setAlignment(QtCore.Qt.AlignCenter)
            shape.setStyleSheet(
                f"color:{MUTED}; font-size:12px; background:transparent;")
            lay.addWidget(shape)
            lay.addSpacing(8)

        blurb = QtWidgets.QLabel(
            L("The clock starts again when the break ends, whether you are "
              "back or not."))
        blurb.setWordWrap(True)
        leading(blurb)
        blurb.setAlignment(QtCore.Qt.AlignCenter)
        blurb.setStyleSheet(f"color:{MUTED}; font-size:11px; background:transparent;")
        lay.addWidget(blurb)
        lay.addSpacing(26)

        resume = QtWidgets.QPushButton(L("Resume testing"))
        resume.setCursor(QtCore.Qt.PointingHandCursor)
        resume.setStyleSheet(
            f"QPushButton{{background:{NAVY}; color:{CANVAS}; border:none;"
            "border-radius:3px; padding:11px 30px; font-size:14px;"
            "font-weight:600;}")
        resume.clicked.connect(self.accept)
        lay.addWidget(resume, 0, QtCore.Qt.AlignHCenter)
        lay.addStretch(1)

        self._tick = QtCore.QTimer(self)
        self._tick.setTimerType(QtCore.Qt.PreciseTimer)
        self._tick.timeout.connect(self._count)
        self._tick.start(1000)
        self._refresh()

    def _count(self):
        self.left -= 1
        if self.left <= 0:
            self._tick.stop()
            self.accept()
            return
        self._refresh()

    def _refresh(self):
        self.clock.setText(_clock(self.left))
        self.clock.setStyleSheet(
            f"color:{WRONG if self.left <= 60 else NAVY}; font-size:64px;"
            f"font-weight:600; font-family:{NUMERALS}; background:transparent;")


class NavigatorDialog(QtWidgets.QDialog):

    def __init__(self, session, parent=None, review=False):
        super().__init__(parent)
        brand.as_sheet(self, parent)
        self.review = review
        self.setWindowTitle(L("Check your work") if review else L("Go to question"))
        self.picked = None
        self.go_review = False
        self.submit = False
        self.setStyleSheet(f"background:{CANVAS};")
        lay = QtWidgets.QVBoxLayout(self)
        _title = QtWidgets.QLabel(L("Check your work") if review else L("Go to question"))
        _title.setStyleSheet(
            f"color:{INK}; font-size:{19 if review else 15}px; font-weight:600;"
            f"font-family:{SERIF}; background:transparent; border:none;")
        lay.addWidget(_title)
        module = fulltest.current_module(session)
        first = module.start if module is not None else 0
        last = module.end if module is not None else len(session.questions)
        if review:
            about = QtWidgets.QLabel(L("Every question here, and which ones you have answered. "
                                       "Choose one to go back to it; hand the section in when you are ready."))
            about.setWordWrap(True)
            leading(about)
            about.setStyleSheet(f"color:{INK}; font-size:12px; background:transparent; border:none;")
            lay.addWidget(about)
            unanswered = sum(1 for i in range(first, last) if not session.attempts[i].answered)
            marked = sum(1 for i in range(first, last) if session.attempts[i].marked)
            bits = []
            if unanswered:
                bits.append(Lp(unanswered, "%d question is unanswered", "%d questions are unanswered"))
            if marked:
                bits.append(Lf("%d marked for review", marked))
            if bits:
                warn = QtWidgets.QLabel(" · ".join(bits))
                warn.setStyleSheet(f"color:{WRONG}; font-size:12px; font-weight:600;"
                                   "background:transparent; border:none;")
                lay.addWidget(warn)
        lay.addSpacing(10)
        grid = QtWidgets.QGridLayout()
        grid.setSpacing(8)
        for slot, i in enumerate(range(first, last)):
            a = session.attempts[i]
            btn = QtWidgets.QPushButton(str(slot + 1))
            btn.setFixedSize(38, 32)
            btn.setCursor(QtCore.Qt.PointingHandCursor)
            border = ACCENT if i == session.index else BORDER
            bg = BRAND_FILL if a.answered else CANVAS
            fg = ON_BRAND if a.answered else INK
            btn.setStyleSheet(
                f"QPushButton{{background:{bg}; color:{fg}; border:"
                f"{2 if i == session.index else 1}px solid {border}; border-radius:4px;"
                "font-size:12px;}")
            if a.marked:
                btn.setText(f"{slot + 1}⚑")
            btn.setAccessibleName(", ".join(
                [str(slot + 1), L("Answered") if a.answered else L("Unanswered")]
                + ([L("For review")] if a.marked else [])))
            btn.clicked.connect(lambda _=False, idx=i: self._pick(idx))
            grid.addWidget(btn, slot // 8, slot % 8)
        lay.addLayout(grid)
        lay.addSpacing(10)
        key = QtWidgets.QHBoxLayout()
        key.setSpacing(16)
        for fill, words in ((BRAND_FILL, L("Answered")), (CANVAS, L("Unanswered"))):
            pair = QtWidgets.QHBoxLayout()
            pair.setSpacing(4)
            swatch = QtWidgets.QFrame()
            swatch.setFixedSize(12, 12)
            swatch.setStyleSheet(f"background:{fill}; border:1px solid {BORDER};"
                                 "border-radius:3px;")
            pair.addWidget(swatch)
            text = QtWidgets.QLabel(words)
            text.setStyleSheet(f"color:{MUTED}; font-size:11px; background:transparent;")
            pair.addWidget(text)
            key.addLayout(pair)
        review_key = QtWidgets.QLabel("⚑ " + L("For review"))
        review_key.setStyleSheet(f"color:{MUTED}; font-size:11px; background:transparent;")
        key.addWidget(review_key)
        key.addStretch(1)
        lay.addLayout(key)
        lay.addSpacing(12)
        row = QtWidgets.QHBoxLayout()
        if review:
            back = QtWidgets.QPushButton(L("Back"))
            back.setCursor(QtCore.Qt.PointingHandCursor)
            back.setStyleSheet(f"QPushButton{{background:{SUBTLE}; color:{INK};"
                               f"border:1px solid {HAIRLINE}; border-radius:3px;"
                               "padding:7px 18px; font-weight:600;}")
            back.clicked.connect(self.reject)
            row.addWidget(back)
            row.addStretch(1)
            final = module is None or fulltest.current_module_index(session) + 1 >= len(session.modules)
            hand_in = QtWidgets.QPushButton(
                L("Submit") if module is None else (L("Finish test") if final else L("Submit module")))
            hand_in.setStyleSheet(f"QPushButton{{background:{ACCENT_FILL}; color:{ON_BRAND};"
                                  "border:none; border-radius:3px; padding:7px 18px; font-weight:600;}")
            hand_in.clicked.connect(self._hand_in)
            row.addWidget(hand_in)
        else:
            row.addStretch(1)
            to_review = QtWidgets.QPushButton(L("Go to Review Page"))
            to_review.setStyleSheet(f"QPushButton{{color:{ACCENT}; border:1px solid {ACCENT};"
                                    "border-radius:13px; padding:5px 14px; background:transparent;}")
            to_review.clicked.connect(self._to_review)
            row.addWidget(to_review)
            row.addStretch(1)
        lay.addLayout(row)

    def _pick(self, idx):
        self.picked = idx
        self.accept()

    def _to_review(self):
        self.go_review = True
        self.accept()

    def _hand_in(self):
        self.submit = True
        self.accept()


class NoteDialog(QtWidgets.QDialog):

    def __init__(self, store, bank_id, annotation, parent=None):
        super().__init__(parent)
        brand.as_sheet(self, parent)
        self.store = store
        self.bank_id = bank_id
        self.annotation = annotation
        self.setWindowTitle(L("Note"))
        self.resize(480, 340)
        self.setStyleSheet(f"background:{PAPER};")

        lay = QtWidgets.QVBoxLayout(self)
        lay.setContentsMargins(0, 0, 0, 0)
        lay.setSpacing(0)

        head = QtWidgets.QWidget()
        head.setObjectName("noteHead")
        head.setStyleSheet(
            f"QWidget#noteHead{{background:{CARD}; border-bottom:1px solid {HAIRLINE};}}")
        hl = QtWidgets.QVBoxLayout(head)
        hl.setContentsMargins(22, 18, 22, 14)
        hl.setSpacing(7)
        title = QtWidgets.QLabel(L("Note"))
        title.setStyleSheet(
            f"color:{NAVY}; font-size:18px; font-weight:600; font-family:{SERIF};"
            "background:transparent;")
        hl.addWidget(title)
        rule = QtWidgets.QFrame()
        rule.setFixedSize(28, 1)
        rule.setStyleSheet(f"background:{BRASS};")
        hl.addWidget(rule)
        lay.addWidget(head)

        self.editor = QtWidgets.QTextEdit()
        self.editor.setPlainText(annotation.get("note", ""))
        self.editor.setAccessibleName(L("Note"))
        self.editor.verticalScrollBar().setStyleSheet(SCROLLBAR)
        self.editor.setStyleSheet(
            f"QTextEdit{{background:{CARD}; border:1px solid {HAIRLINE}; border-radius:4px;"
            f"padding:10px; font-size:13px; color:{INK};}}")
        wrap = QtWidgets.QWidget()
        wl = QtWidgets.QVBoxLayout(wrap)
        wl.setContentsMargins(20, 20, 20, 20)
        wl.addWidget(self.editor)
        lay.addWidget(wrap, 1)

        foot = QtWidgets.QWidget()
        foot.setObjectName("noteFoot")
        foot.setStyleSheet(
            f"QWidget#noteFoot{{background:{CARD}; border-top:1px solid {HAIRLINE};}}")
        fl = QtWidgets.QHBoxLayout(foot)
        fl.setContentsMargins(20, 14, 20, 14)
        remove = QtWidgets.QPushButton(L("Remove highlight"))
        remove.setFlat(True)
        remove.setCursor(QtCore.Qt.PointingHandCursor)
        remove.setStyleSheet(
            f"QPushButton{{border:none; color:{WRONG}; font-size:12px; background:transparent;}}")
        remove.clicked.connect(self._remove)
        fl.addWidget(remove)
        fl.addStretch(1)
        cancel = QtWidgets.QPushButton(L("Cancel"))
        cancel.setFlat(True)
        cancel.setCursor(QtCore.Qt.PointingHandCursor)
        cancel.setStyleSheet(
            f"QPushButton{{border:none; color:{MUTED}; font-size:12px; background:transparent;}}")
        cancel.clicked.connect(self.reject)
        fl.addWidget(cancel)
        save = QtWidgets.QPushButton(L("Save"))
        save.setCursor(QtCore.Qt.PointingHandCursor)
        save.setStyleSheet(
            f"QPushButton{{background:{NAVY}; color:{CARD}; border-radius:3px;"
            "padding:8px 22px; font-size:13px; font-weight:600;}")
        save.clicked.connect(self._save)
        fl.addWidget(save)
        lay.addWidget(foot)

    def _save(self):
        self.store.update_annotation(self.bank_id, self.annotation["id"],
                                     note=self.editor.toPlainText().strip())
        self.accept()

    def _remove(self):
        self.store.remove_annotation(self.bank_id, self.annotation["id"])
        self.accept()


class DirectionsDialog(QtWidgets.QDialog):

    def __init__(self, session, parent=None):
        super().__init__(parent)
        brand.as_sheet(self, parent)
        self.setWindowTitle(L("Directions"))
        self.setStyleSheet(f"background:{PAPER};")

        lay = QtWidgets.QVBoxLayout(self)
        lay.setContentsMargins(0, 0, 0, 0)
        lay.setSpacing(0)

        head = QtWidgets.QWidget()
        head.setObjectName("directionsHead")
        head.setStyleSheet(
            f"QWidget#directionsHead{{background:{CARD}; border-bottom:1px solid {HAIRLINE};}}")
        hl = QtWidgets.QVBoxLayout(head)
        hl.setContentsMargins(24, 18, 24, 14)
        hl.setSpacing(5)
        title = QtWidgets.QLabel(L("Directions"))
        title.setStyleSheet(
            f"color:{NAVY}; font-size:19px; font-weight:600; font-family:{SERIF};"
            "background:transparent;")
        hl.addWidget(title)
        sitting = QtWidgets.QLabel(fulltest.module_title(session) or session.display_title)
        sitting.setStyleSheet(f"color:{MUTED}; font-size:11px; background:transparent;")
        hl.addWidget(sitting)
        rule = QtWidgets.QFrame()
        rule.setFixedSize(32, 1)
        rule.setStyleSheet(f"background:{BRASS};")
        hl.addWidget(rule)
        lay.addWidget(head)

        page = QtWidgets.QWidget()
        page.setObjectName("directionsPage")
        page.setStyleSheet(f"QWidget#directionsPage{{background:{PAPER};}}")
        pl = QtWidgets.QVBoxLayout(page)
        pl.setContentsMargins(24, 18, 24, 18)
        pl.setSpacing(6)
        for i, (heading, lines) in enumerate(directions_for(session)):
            if i:
                pl.addSpacing(12)
            name = QtWidgets.QLabel(heading.upper())
            name.setStyleSheet(
                f"color:{MUTED}; font-size:10px; font-weight:600; letter-spacing:1.2px;")
            pl.addWidget(name)
            for line in lines:
                text = QtWidgets.QLabel(line)
                text.setWordWrap(True)
                text.setTextFormat(QtCore.Qt.PlainText)
                text.setStyleSheet(f"color:{INK}; font-size:13px;")
                leading(text)
                pl.addWidget(text)
        pl.addStretch(1)
        area = QtWidgets.QScrollArea()
        area.setWidgetResizable(True)
        area.setFrameShape(QtWidgets.QFrame.NoFrame)
        area.setStyleSheet(SCROLLBAR)
        area.setWidget(page)
        lay.addWidget(area, 1)

        foot = QtWidgets.QWidget()
        foot.setObjectName("directionsFoot")
        foot.setStyleSheet(
            f"QWidget#directionsFoot{{background:{CARD}; border-top:1px solid {HAIRLINE};}}")
        fl = QtWidgets.QHBoxLayout(foot)
        fl.setContentsMargins(20, 12, 20, 12)
        fl.addStretch(1)
        done = QtWidgets.QPushButton(L("Close"))
        done.setCursor(QtCore.Qt.PointingHandCursor)
        done.setStyleSheet(
            f"QPushButton{{background:{NAVY}; color:{CARD}; border-radius:3px;"
            "padding:8px 22px; font-size:13px; font-weight:600;}")
        done.clicked.connect(self.accept)
        fl.addWidget(done)
        lay.addWidget(foot)

        window = parent.window() if parent is not None else None
        room = window.height() if window is not None else 900
        self.resize(560, min(room, max(460, room - 150)))


class NotesDialog(QtWidgets.QDialog):

    def __init__(self, store, bank_id, question, parent=None):
        super().__init__(parent)
        brand.as_sheet(self, parent)
        self.store = store
        self.bank_id = bank_id
        self.question = question
        self.setWindowTitle(L("Highlights & Notes"))
        self.resize(560, 480)
        self.setStyleSheet(f"background:{PAPER};")

        lay = QtWidgets.QVBoxLayout(self)
        lay.setContentsMargins(0, 0, 0, 0)
        lay.setSpacing(0)

        head = QtWidgets.QWidget()
        head.setObjectName("notesHead")
        head.setStyleSheet(
            f"QWidget#notesHead{{background:{CARD}; border-bottom:1px solid {HAIRLINE};}}")
        hl = QtWidgets.QVBoxLayout(head)
        hl.setContentsMargins(24, 18, 24, 14)
        hl.setSpacing(7)
        title = QtWidgets.QLabel(L("Highlights & Notes"))
        title.setStyleSheet(
            f"color:{NAVY}; font-size:19px; font-weight:600; font-family:{SERIF};"
            "background:transparent;")
        hl.addWidget(title)
        rule = QtWidgets.QFrame()
        rule.setFixedSize(32, 1)
        rule.setStyleSheet(f"background:{BRASS};")
        hl.addWidget(rule)
        lay.addWidget(head)

        self.area = QtWidgets.QScrollArea()
        self.area.setWidgetResizable(True)
        self.area.setFrameShape(QtWidgets.QFrame.NoFrame)
        self.area.setStyleSheet(SCROLLBAR)
        lay.addWidget(self.area, 1)

        foot = QtWidgets.QWidget()
        foot.setObjectName("notesFoot")
        foot.setStyleSheet(
            f"QWidget#notesFoot{{background:{CARD}; border-top:1px solid {HAIRLINE};}}")
        fl = QtWidgets.QHBoxLayout(foot)
        fl.setContentsMargins(20, 14, 20, 14)
        clear = QtWidgets.QPushButton(L("Remove all"))
        clear.setFlat(True)
        clear.setCursor(QtCore.Qt.PointingHandCursor)
        clear.setStyleSheet(
            f"QPushButton{{border:none; color:{WRONG}; font-size:12px; background:transparent;}}")
        clear.clicked.connect(self._clear)
        fl.addWidget(clear)
        fl.addStretch(1)
        done = QtWidgets.QPushButton(L("Done"))
        done.setCursor(QtCore.Qt.PointingHandCursor)
        done.setStyleSheet(
            f"QPushButton{{background:{NAVY}; color:{CARD}; border-radius:3px;"
            "padding:8px 22px; font-size:13px; font-weight:600;}")
        done.clicked.connect(self.accept)
        fl.addWidget(done)
        lay.addWidget(foot)

        self._fill()

    def _fill(self):
        items = self.store.annotations(self.bank_id, self.question.id)
        page = QtWidgets.QWidget()
        page.setObjectName("notesList")
        page.setStyleSheet(f"QWidget#notesList{{background:{PAPER};}}")
        pl = QtWidgets.QVBoxLayout(page)
        pl.setContentsMargins(20, 20, 20, 20)
        pl.setSpacing(10)

        if not items:
            from html import escape
            empty = QtWidgets.QLabel(
                "<div style='font-size:14px; font-weight:600; color:%s'>%s</div>"
                "<div style='font-size:11px; color:%s'>%s</div>" % (
                    INK, escape(L("Nothing marked on this question yet")), MUTED,
                    escape(L("Select words in a passage, or in Math text without formulas, "
                             "to highlight them, and add a note if you want one."))))
            empty.setWordWrap(True)
            leading(empty)
            empty.setAlignment(QtCore.Qt.AlignCenter)
            pl.addStretch(1)
            pl.addWidget(empty)
            pl.addStretch(1)
        else:
            for a in items:
                pl.addWidget(self._row(a))
            pl.addStretch(1)
        self.area.setWidget(page)

    def _row(self, a):
        card = QtWidgets.QFrame()
        card.setObjectName("noteCard")
        card.setStyleSheet(
            f"QFrame#noteCard{{background:{CARD}; border:1px solid {HAIRLINE};"
            "border-radius:4px;}")
        lay = QtWidgets.QHBoxLayout(card)
        lay.setContentsMargins(14, 12, 14, 12)
        lay.setSpacing(10)

        swatch = QtWidgets.QFrame()
        swatch.setFixedWidth(4)
        swatch.setStyleSheet(
            f"background:{highlight_color(a.get('color', 0))}; border-radius:2px;")
        lay.addWidget(swatch)

        body = f"<div style='font-size:12px; color:{INK}'>{self._excerpt(a)}</div>"
        if a.get("note", "").strip():
            from html import escape
            body += (f"<div style='font-size:12px; color:{MUTED}; margin-top:6px'>"
                     f"{escape(a['note']).replace(chr(10), '<br>')}</div>")
        text = QtWidgets.QLabel(body)
        text.setWordWrap(True)
        leading(text)
        text.setStyleSheet("border:none; background:transparent;")
        lay.addWidget(text, 1)

        actions = QtWidgets.QVBoxLayout()
        for label, slot, colour in (
                (L("Edit note") if a.get("note", "").strip() else L("Add note"),
                 lambda: self._edit(a), NAVY),
                (L("Remove"), lambda: self._remove(a), WRONG)):
            b = QtWidgets.QPushButton(label)
            b.setFlat(True)
            b.setCursor(QtCore.Qt.PointingHandCursor)
            b.setStyleSheet(
                f"QPushButton{{border:none; color:{colour}; font-size:11px;"
                "background:transparent;}")
            b.clicked.connect(slot)
            actions.addWidget(b)
        holder = QtWidgets.QWidget()
        holder.setLayout(actions)
        holder.setStyleSheet("background:transparent;")
        lay.addWidget(holder)
        return card

    def _excerpt(self, a):
        from html import escape
        blocks = (self.question.stimulus if a.get("field") == "stimulus"
                  else self.question.prompt)
        index = a.get("block", 0)
        if index >= len(blocks):
            return L("(passage changed)")
        text = blocks[index].text[a["start"]:a["end"]]
        return escape(text if len(text) <= 220 else text[:220] + "…")

    def _edit(self, a):
        NoteDialog(self.store, self.bank_id, a, self).exec()
        self._fill()

    def _remove(self, a):
        self.store.remove_annotation(self.bank_id, a["id"])
        self._fill()

    def _clear(self):
        self.store.clear_annotations(self.bank_id, self.question.id)
        self._fill()

brand.adopt(__name__)
