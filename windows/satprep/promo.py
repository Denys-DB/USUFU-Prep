from __future__ import annotations

import sys
import webbrowser

from PySide6 import QtCore, QtGui, QtWidgets

from . import brand
from . import i18n
from . import legal
from .i18n import L
from .ui import (BORDER, BRASS, BRASS_TEXT, CARD, HAIRLINE, INK, MUTED, NAVY, ON_BRAND,
                 PAPER, SERIF, leading)

WEBSITE = "https://usufu.org"
WEBSITE_LABEL = "usufu.org"

POINT_ICONS = (chr(0xF000),
               chr(0xE121),
               chr(0xE9D2),
               chr(0xE72E))
if sys.platform != "win32":
    POINT_ICONS = (chr(0x25A4), chr(0x25F7), chr(0x2197), chr(0x2302))


def lede():
    return L("A free, non-profit study tool from United States Universities "
             "For Ukraine, built for Ukrainian students preparing for "
             "university in the United States.")


def what_it_does():
    return (
        (L("Your own question bank"),
         L("Export the questions you want from the College Board's Question "
           "Bank and import the PDF here. It becomes a practice test you can "
           "sit as many times as you like.")),
        (L("The real thing's shape"),
         L("The screen, the timing and the controls follow the digital test, "
           "so the format costs you nothing on the day. Sit a single module or "
           "the whole test, with the break.")),
        (L("Practice that knows what you missed"),
         L("Questions you get wrong come back, spaced out over days. The "
           "statistics say which skills are costing you marks, and you can "
           "drill exactly those.")),
        (L("Nothing leaves your computer"),
         L("No account, no network, no subscription, no tracking. Your "
           "questions, answers and progress stay in a folder you can open, "
           "copy and delete yourself.")),
    )


def about_us():
    return (
        L("United States Universities For Ukraine is an independent, "
          "non-profit educational initiative. We help Ukrainian students and "
          "their families understand how studying in the United States "
          "actually works — what to prepare, when, and what it costs."),
        L("This app is one part of that, and it is free. The rest is on our "
          "website: guides to admissions, scholarships and financial aid, "
          "visas and documents, grade and score converters, and planning "
          "timelines."),
    )


def _rule():
    line = QtWidgets.QFrame()
    line.setFixedHeight(1)
    line.setStyleSheet(f"background:{HAIRLINE}; border:none;")
    return line


def _section_label(text):
    label = QtWidgets.QLabel(text.upper())
    label.setStyleSheet(
        f"color:{MUTED}; font-size:10px; font-weight:600; letter-spacing:1.5px;"
        "border:none; background:transparent;")
    return label


class AboutPanel(QtWidgets.QDialog):

    def __init__(self, parent=None):
        super().__init__(parent)
        self.setWindowTitle(brand.APP_NAME)
        self.setModal(True)
        self.setFixedSize(620, 620)
        self.setStyleSheet(
            f"QDialog{{background:{PAPER}; border:1px solid {HAIRLINE};}}")
        brand.as_sheet(self, parent)

        outer = QtWidgets.QVBoxLayout(self)
        outer.setContentsMargins(0, 0, 0, 0)
        outer.setSpacing(0)

        scroll = QtWidgets.QScrollArea()
        scroll.setWidgetResizable(True)
        scroll.setFrameShape(QtWidgets.QFrame.NoFrame)
        scroll.setHorizontalScrollBarPolicy(QtCore.Qt.ScrollBarAlwaysOff)
        scroll.setStyleSheet(f"QScrollArea{{background:{PAPER}; border:none;}}")
        from .ui import SCROLLBAR
        scroll.verticalScrollBar().setStyleSheet(SCROLLBAR)

        page = QtWidgets.QWidget()
        page.setStyleSheet(f"background:{PAPER};")
        lay = QtWidgets.QVBoxLayout(page)
        lay.setContentsMargins(26, 26, 26, 26)
        lay.setSpacing(22)

        lay.addWidget(self._masthead())
        lay.addWidget(_rule())
        lay.addWidget(self._points())
        lay.addWidget(_rule())
        lay.addWidget(self._who())
        lay.addWidget(self._website())
        lay.addStretch(1)

        scroll.setWidget(page)
        outer.addWidget(scroll, 1)
        outer.addWidget(_rule())
        outer.addWidget(self._foot())

    def _masthead(self):
        box = QtWidgets.QWidget()
        box.setStyleSheet("background:transparent;")
        lay = QtWidgets.QVBoxLayout(box)
        lay.setContentsMargins(0, 0, 0, 0)
        lay.setSpacing(14)
        lay.addWidget(brand.Seal(108, NAVY), 0, QtCore.Qt.AlignHCenter)

        mark = brand.Wordmark(340, NAVY)
        if mark.has_art():
            lay.addWidget(mark, 0, QtCore.Qt.AlignHCenter)
        else:
            fallback = QtWidgets.QLabel(
                f"<div style='font-size:19px; font-weight:600; color:{NAVY};"
                f"font-family:{SERIF}'>{brand.ORGANISATION}</div>"
                f"<div style='font-size:12px; color:{BRASS_TEXT}; font-family:{SERIF};"
                f"font-style:italic'>{brand.SLOGAN}</div>")
            fallback.setAlignment(QtCore.Qt.AlignCenter)
            fallback.setStyleSheet("border:none;")
            lay.addWidget(fallback)

        line = QtWidgets.QLabel(lede())
        line.setWordWrap(True)
        leading(line)
        line.setAlignment(QtCore.Qt.AlignCenter)
        line.setStyleSheet(f"color:{MUTED}; font-size:11.5px; border:none;")
        lay.addWidget(line)
        return box

    def _points(self):
        box = QtWidgets.QWidget()
        box.setStyleSheet("background:transparent;")
        lay = QtWidgets.QVBoxLayout(box)
        lay.setContentsMargins(0, 0, 0, 0)
        lay.setSpacing(14)
        lay.addWidget(_section_label(L("What this app does")))

        for glyph, (title, body) in zip(POINT_ICONS, what_it_does()):
            row = QtWidgets.QHBoxLayout()
            row.setSpacing(11)
            mark = QtWidgets.QLabel(glyph)
            mark.setFont(QtGui.QFont(brand.ICON_FONT, 11))
            mark.setFixedWidth(20)
            mark.setAlignment(QtCore.Qt.AlignTop | QtCore.Qt.AlignHCenter)
            mark.setStyleSheet(f"color:{BRASS_TEXT}; border:none; background:transparent;")
            row.addWidget(mark, 0, QtCore.Qt.AlignTop)

            words = QtWidgets.QVBoxLayout()
            words.setSpacing(3)
            head = QtWidgets.QLabel(title)
            head.setWordWrap(True)
            leading(head)
            head.setStyleSheet(f"color:{INK}; font-size:12px; font-weight:600;"
                               "border:none; background:transparent;")
            words.addWidget(head)
            note = QtWidgets.QLabel(body)
            note.setWordWrap(True)
            leading(note)
            note.setStyleSheet(f"color:{MUTED}; font-size:11px; border:none;"
                               "background:transparent;")
            words.addWidget(note)
            row.addLayout(words, 1)
            lay.addLayout(row)
        return box

    def _who(self):
        box = QtWidgets.QWidget()
        box.setStyleSheet("background:transparent;")
        lay = QtWidgets.QVBoxLayout(box)
        lay.setContentsMargins(0, 0, 0, 0)
        lay.setSpacing(10)
        lay.addWidget(_section_label(L("Who we are")))
        for line in about_us():
            para = QtWidgets.QLabel(line)
            para.setWordWrap(True)
            leading(para)
            para.setStyleSheet(f"color:{INK}; font-size:11.5px; border:none;"
                               "background:transparent;")
            lay.addWidget(para)
        return box

    def _website(self):
        card = QtWidgets.QFrame()
        card.setObjectName("promoCard")
        card.setStyleSheet(
            f"QFrame#promoCard{{background:{CARD}; border:1px solid {HAIRLINE};"
            "border-radius:4px;}")
        lay = QtWidgets.QVBoxLayout(card)
        lay.setContentsMargins(18, 18, 18, 18)
        lay.setSpacing(9)

        head = QtWidgets.QLabel(L("Everything else is on our website"))
        head.setStyleSheet(
            f"color:{NAVY}; font-size:13px; font-weight:600; font-family:{SERIF};"
            "border:none; background:transparent;")
        lay.addWidget(head)

        note = QtWidgets.QLabel(
            L("Admissions, scholarships and aid, visas and documents, grade "
              "converters, and a planning timeline — all free, in English and "
              "Ukrainian."))
        note.setWordWrap(True)
        leading(note)
        note.setStyleSheet(f"color:{MUTED}; font-size:11px; border:none;"
                           "background:transparent;")
        lay.addWidget(note)

        link = QtWidgets.QPushButton(WEBSITE_LABEL + "  ↗")
        link.setCursor(QtCore.Qt.PointingHandCursor)
        link.setToolTip(L("Opens in your browser"))
        night = brand.stealth_on()
        live = brand.live_palette()
        link.setStyleSheet(
            "QPushButton{"
            + (f"background:{live['SUBTLE']}; color:{live['BRASS']};"
               f"border:1px solid {live['BRASS']};" if night
               else f"background:{live['BRAND_FILL']}; color:{live['ON_BRAND']};"
                    "border:none;")
            + "border-radius:3px; padding:8px 16px; font-size:12px;"
            "font-weight:600;}")
        link.clicked.connect(self._open_website)
        lay.addWidget(link, 0, QtCore.Qt.AlignLeft)
        return card

    def _open_website(self):
        webbrowser.open(WEBSITE)

    def _foot(self):
        bar = QtWidgets.QWidget()
        bar.setStyleSheet(f"background:{PAPER};")
        lay = QtWidgets.QHBoxLayout(bar)
        lay.setContentsMargins(22, 13, 22, 13)

        notice = QtWidgets.QLabel(
            legal.COPYRIGHT.get(i18n.current(), legal.COPYRIGHT["en"]))
        notice.setStyleSheet(f"color:{MUTED}; font-size:9.5px; border:none;")
        apart = QtWidgets.QLabel(
            L("Not affiliated with the College Board. "
              "Everything stays on your computer."))
        apart.setStyleSheet(f"color:{MUTED}; font-size:9.5px; border:none;")
        lines = QtWidgets.QVBoxLayout()
        lines.setSpacing(2)
        lines.addWidget(notice)
        lines.addWidget(apart)
        lay.addLayout(lines)
        lay.addStretch(1)

        close = QtWidgets.QPushButton(L("Close"))
        close.setCursor(QtCore.Qt.PointingHandCursor)
        close.setStyleSheet(
            f"QPushButton{{border:none; color:{NAVY}; font-size:12px;"
            "font-weight:600; background:transparent;}")
        close.clicked.connect(self.accept)
        lay.addWidget(close)
        return bar

brand.adopt(__name__)
