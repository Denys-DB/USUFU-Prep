from __future__ import annotations

import os
import subprocess
import sys

import shiboken6
from PySide6 import QtCore, QtGui, QtWidgets

from . import brand
from . import i18n
from . import legal
from .core import file_size
from .i18n import L, Lf
from .ui import (BORDER, BRASS, BRASS_TEXT, CARD, CHROME, HAIRLINE, INK, MUTED, NAVY,
                 ON_BRAND, PAPER, SERIF, SUBTLE, BRAND_FILL,
                 discard_layout, leading)


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


ICON_FONT = brand.ICON_FONT
GLYPHS = brand.ICONS

PREVIEW = {
    "light": ("#F4F0E8", "#1B2A4A"),
    "dark": ("#0E1629", "#F2EDE0"),
}


def _rule():
    line = QtWidgets.QFrame()
    line.setFixedHeight(1)
    line.setStyleSheet(f"background:{HAIRLINE}; border:none;")
    return line


class ThemePreview(QtWidgets.QWidget):

    def __init__(self, ground, ink, parent=None):
        super().__init__(parent)
        self._ground = QtGui.QColor(ground)
        self._ink = QtGui.QColor(ink)
        self.setFixedHeight(96)
        self.setAttribute(QtCore.Qt.WA_TransparentForMouseEvents)

    def paintEvent(self, event):
        painter = QtGui.QPainter(self)
        painter.setRenderHint(QtGui.QPainter.Antialiasing)
        rect = QtCore.QRectF(self.rect()).adjusted(0.5, 0.5, -0.5, -0.5)
        painter.setPen(QtCore.Qt.NoPen)
        painter.setBrush(self._ground)
        painter.drawRoundedRect(rect, 4, 4)

        centre = rect.center().x()
        seal = QtCore.QRectF(centre - 13, rect.top() + 22, 26, 26)
        brand.paint_seal(painter, seal, self._ink)

        for width, alpha, top in ((52, 0.75, 58), (34, 0.40, 66)):
            bar = QtGui.QColor(self._ink)
            bar.setAlphaF(alpha)
            painter.setBrush(bar)
            painter.drawRoundedRect(
                QtCore.QRectF(centre - width / 2, rect.top() + top, width, 3), 1, 1)
        painter.end()


class ThemeCard(QtWidgets.QWidget):

    def __init__(self, key, title, detail, selected, on_pick, parent=None):
        super().__init__(parent)
        self.setCursor(QtCore.Qt.PointingHandCursor)
        self._on_pick = on_pick
        self._key = key
        self.setFocusPolicy(QtCore.Qt.StrongFocus)
        self.setAccessibleName(title)

        lay = QtWidgets.QVBoxLayout(self)
        lay.setContentsMargins(0, 0, 0, 0)
        lay.setSpacing(9)

        ground, ink = PREVIEW[
            brand.system_theme() if key == "system" else key]
        frame = QtWidgets.QWidget()
        frame.setObjectName("themeFrame")
        edge = BRASS if selected else HAIRLINE
        frame.setStyleSheet(
            f"QWidget#themeFrame{{border-radius:4px; border:2px solid {edge};}}")
        inner = QtWidgets.QVBoxLayout(frame)
        inner.setContentsMargins(2, 2, 2, 2)
        inner.addWidget(ThemePreview(ground, ink))
        lay.addWidget(frame)

        name = QtWidgets.QLabel(title)
        name.setAlignment(QtCore.Qt.AlignCenter)
        name.setStyleSheet(
            f"color:{INK}; font-size:12px; border:none;"
            + ("font-weight:600;" if selected else ""))
        lay.addWidget(name)

        note = QtWidgets.QLabel(detail)
        note.setAlignment(QtCore.Qt.AlignCenter)
        note.setWordWrap(True)
        leading(note)
        note.setStyleSheet(f"color:{MUTED}; font-size:9.5px; border:none;")
        lay.addWidget(note)

    def mousePressEvent(self, event):
        self._on_pick(self._key)

    def keyPressEvent(self, event):
        if event.key() in (QtCore.Qt.Key_Space, QtCore.Qt.Key_Return, QtCore.Qt.Key_Enter):
            self._on_pick(self._key)
            return
        super().keyPressEvent(event)

    def focusInEvent(self, event):
        super().focusInEvent(event)
        self.update()

    def focusOutEvent(self, event):
        super().focusOutEvent(event)
        self.update()

    def paintEvent(self, event):
        super().paintEvent(event)
        if self.hasFocus():
            painter = QtGui.QPainter(self)
            pen = QtGui.QPen(QtGui.QColor(BRASS))
            pen.setStyle(QtCore.Qt.DashLine)
            painter.setPen(pen)
            painter.drawRect(self.rect().adjusted(0, 0, -1, -1))
            painter.end()


class SettingsSheet(QtWidgets.QDialog):

    TABS = ("study", "customisation", "students", "storage", "about")

    @staticmethod
    def titles():
        return {
            "study": L("What you study"),
            "customisation": L("Customization"),
            "students": L("Students"),
            "storage": L("Storage"),
            "about": L("About"),
        }

    @staticmethod
    def parts():
        return (
            ("showQuestionSets",
             L("SAT practice"),
             L("Your question sets, the practice screen, the statistics and the "
               "Import button. Off, the library goes with them — for a student "
               "using this only for vocabulary.")),
            ("showFlashcards",
             L("Flashcards"),
             L("Your decks, the cards in them and the vocabulary test. Off, the "
               "Flashcards section goes — for a student who came here for the "
               "questions.")),
            ("showLearnInSidebar",
             L("Learn in the sidebar"),
             L("Short explanations of what each skill actually is. Articles are "
               "still reachable from a question you got wrong and from the "
               "statistics screen.")),
        )

    @staticmethod
    def switches():
        return (
            ("showImportButton",
             L("The Import button"),
             L("Dragging a PDF onto the window still works, and the button comes "
               "back on its own if a question set is ever needed.")),
            ("showBackupCard",
             L("Keep a copy somewhere else"),
             L("The card that offers to write everything of yours out as one file, "
               "and the reminder to do it. Turning it off does not stop you "
               "exporting — Storage below still will — it only stops the asking.")),
            ("showParentSummary",
             L("The page for a parent"),
             L("A plain-language summary on the statistics screen, in whichever "
               "language is set, that can be saved as a one-page PDF. Off if there "
               "is nobody to show it to.")),
            ("showDoubleMode",
             L("Study together"),
             L("The card that sets up a sitting for two students on one computer. "
               "It only appears when there is more than one student on this "
               "computer anyway; turn it off and it will not appear at all.")),
        )

    @staticmethod
    def streaks():
        return (
            ("showQuestionStreak",
             L("The streak on the practice screen"),
             L("Counted against the days in your study plan, where a planned rest "
               "day is skipped rather than failed.")),
            ("showVocabularyStreak",
             L("The streak on a flashcard deck"),
             L("Counted on the days you finish the words you were dealt.")),
        )

    @staticmethod
    def card_switches():
        return (
            ("track_skipped_cards",
             L("Count the words I skip past"),
             L("A word you go past without ever turning the card over goes "
               "into \"Words I skipped past\". Nothing else can tell you which of a "
               "long deck you have not really studied. Turn it off and the pile is "
               "hidden.")),
            ("flashcard_flip_animation",
             L("Turn the card with an animation"),
             L("Also switchable from the corner of the card itself, which is where "
               "you will want it mid-run.")),
        )

    def __init__(self, store, parent=None, tab="customisation"):
        super().__init__(parent)
        self.store = store
        self._tab = tab if tab in self.TABS else "customisation"
        self._document = 0
        self.setWindowTitle(L("Settings"))
        self.setMinimumSize(760, 520)
        self.resize(820, 560)
        self.setStyleSheet(
            f"QDialog{{background:{PAPER}; border:1px solid {HAIRLINE};}}")
        brand.as_sheet(self, parent)
        self._build()

    def _build(self):
        self.setWindowTitle(L("Settings"))
        keep = 0
        old = getattr(self, "_scroll", None)
        if (old is not None and shiboken6.isValid(old)
                and getattr(self, "_built_tab", None) == self._tab):
            keep = old.verticalScrollBar().value()
        discard_layout(self)

        lay = QtWidgets.QHBoxLayout(self)
        lay.setContentsMargins(0, 0, 0, 0)
        lay.setSpacing(0)
        lay.addWidget(self._rail())

        pane = {
            "study": self._study,
            "customisation": self._customisation,
            "students": self._students,
            "storage": self._storage,
            "about": self._about,
        }[self._tab]()

        scroll = QtWidgets.QScrollArea()
        scroll.setWidgetResizable(True)
        scroll.setFrameShape(QtWidgets.QFrame.NoFrame)
        scroll.setHorizontalScrollBarPolicy(QtCore.Qt.ScrollBarAlwaysOff)
        scroll.setStyleSheet(f"QScrollArea{{background:{PAPER}; border:none;}}"
                             + SCROLLBAR)
        scroll.setWidget(pane)
        scroll.setAccessibleName(self.titles()[self._tab])
        lay.addWidget(scroll, 1)
        self._scroll, self._built_tab = scroll, self._tab
        if keep:
            bar = scroll.verticalScrollBar()

            def restore(_low, high):
                if high >= keep:
                    bar.setValue(keep)
                    bar.rangeChanged.disconnect(restore)

            bar.rangeChanged.connect(restore)

    def _rail(self):
        rail = QtWidgets.QWidget()
        rail.setObjectName("settingsRail")
        rail.setFixedWidth(192)
        rail.setStyleSheet(
            f"QWidget#settingsRail{{background:{CHROME};"
            f"border-right:1px solid {HAIRLINE};}}")

        lay = QtWidgets.QVBoxLayout(rail)
        lay.setContentsMargins(14, 18, 12, 16)
        lay.setSpacing(0)

        head = QtWidgets.QHBoxLayout()
        head.setSpacing(9)
        head.addWidget(brand.Seal(30, NAVY), 0, QtCore.Qt.AlignTop)
        lockup = QtWidgets.QLabel(
            f"<div style='font-size:14px; font-weight:600; color:{NAVY};"
            f"font-family:{SERIF}'>" + L("Settings") + "</div>"
            f"<div style='font-size:8.5px; letter-spacing:1.4px; color:{MUTED}'>"
            f"{brand.INITIALS}</div>")
        lockup.setWordWrap(True)
        leading(lockup)
        lockup.setStyleSheet("border:none;")
        head.addWidget(lockup, 1)
        lay.addLayout(head)
        lay.addSpacing(20)

        for key in self.TABS:
            lay.addWidget(self._tab_button(key))
            lay.addSpacing(2)

        lay.addStretch(1)
        done = QtWidgets.QPushButton(L("Done"))
        done.setCursor(QtCore.Qt.PointingHandCursor)
        done.setStyleSheet(
            f"QPushButton{{border:none; color:{NAVY}; font-size:12.5px;"
            "font-weight:600; text-align:left; padding:4px 6px;}")
        done.clicked.connect(self.accept)
        lay.addWidget(done, 0, QtCore.Qt.AlignLeft)
        return rail

    def _tab_button(self, key):
        chosen = key == self._tab
        button = QtWidgets.QPushButton()
        button.setAccessibleName(self.titles()[key])
        button.setCursor(QtCore.Qt.PointingHandCursor)
        button.setFixedHeight(30)
        button.setStyleSheet(
            "QPushButton{border:none; border-radius:5px; text-align:left;"
            + (f"background:{SUBTLE};" if chosen else "background:transparent;")
            + "}"
            + (f"QPushButton:hover{{background:{SUBTLE};}}" if not chosen else ""))

        row = QtWidgets.QHBoxLayout(button)
        row.setContentsMargins(11, 0, 11, 0)
        row.setSpacing(9)

        mark = QtWidgets.QLabel(GLYPHS[key])
        mark.setFont(QtGui.QFont(ICON_FONT, 10))
        mark.setFixedWidth(16)
        mark.setStyleSheet(
            f"color:{NAVY if chosen else MUTED}; border:none; background:transparent;")
        row.addWidget(mark)

        name = QtWidgets.QLabel(self.titles()[key])
        name.setStyleSheet(
            f"color:{NAVY if chosen else MUTED}; font-size:12px; border:none;"
            "background:transparent;"
            + ("font-weight:600;" if chosen else ""))
        row.addWidget(name, 1)

        button.clicked.connect(lambda _=False, k=key: self._go(k))
        return button

    def _go(self, key):
        self._tab = key
        self._build()

    def _pane(self):
        page = QtWidgets.QWidget()
        page.setStyleSheet(f"background:{PAPER};")
        lay = QtWidgets.QVBoxLayout(page)
        lay.setContentsMargins(26, 22, 26, 24)
        lay.setSpacing(0)
        return page, lay

    def _heading(self, title, blurb=None):
        box = QtWidgets.QWidget()
        box.setStyleSheet("background:transparent;")
        lay = QtWidgets.QVBoxLayout(box)
        lay.setContentsMargins(0, 0, 0, 0)
        lay.setSpacing(5)
        label = QtWidgets.QLabel(title)
        label.setStyleSheet(
            f"color:{NAVY}; font-size:17px; font-weight:600; font-family:{SERIF};"
            "border:none;")
        lay.addWidget(label)
        if blurb:
            note = QtWidgets.QLabel(blurb)
            note.setWordWrap(True)
            leading(note)
            note.setStyleSheet(f"color:{MUTED}; font-size:11px; border:none;")
            lay.addWidget(note)
        return box

    def _switch(self, key, label, detail, default=True, on_change=None):
        from .home import Switch

        box = QtWidgets.QWidget()
        box.setStyleSheet("background:transparent;")
        lay = QtWidgets.QVBoxLayout(box)
        lay.setContentsMargins(0, 0, 0, 0)
        lay.setSpacing(2)

        top = QtWidgets.QHBoxLayout()
        top.setContentsMargins(0, 0, 0, 0)
        top.setSpacing(12)
        name = QtWidgets.QLabel(L(label))
        name.setWordWrap(True)
        leading(name)
        name.setStyleSheet(
            f"color:{INK}; font-size:12px; background:transparent; border:none;")
        top.addWidget(name, 1)

        pill = Switch(bool(self.store.settings.get(key, default)))
        pill.setAccessibleName(L(label))

        def changed(on, k=key):
            self.store.set_setting(k, bool(on))
            if on_change is not None:
                on_change()

        pill.toggled.connect(changed)
        top.addWidget(pill, 0, QtCore.Qt.AlignTop)
        lay.addLayout(top)

        note = QtWidgets.QLabel(L(detail))
        note.setWordWrap(True)
        leading(note)
        note.setContentsMargins(0, 0, Switch.TRACK.width() + 12, 0)
        note.setStyleSheet(f"color:{MUTED}; font-size:10px; border:none;")
        lay.addWidget(note)
        return box

    def _gap(self, lay, rule=True, space=14):
        lay.addSpacing(space)
        if rule:
            lay.addWidget(_rule())
            lay.addSpacing(max(13, space))

    def _study(self):
        page, lay = self._pane()

        lay.addWidget(self._heading(
            L("What this app is for, for you"),
            L("Turn off the parts you are not using and they leave the sidebar "
              "entirely. Nothing is deleted: your sets, your progress, your "
              "decks and your notes are all still on this computer, and turning "
              "a part back on brings it back exactly as it was.")))
        lay.addSpacing(14)
        for key, label, detail in self.parts():
            lay.addWidget(self._switch(key, label, detail))
            lay.addSpacing(12)

        if not self.store.settings.get("showQuestionSets", True) \
                and not self.store.settings.get("showFlashcards", True):
            note = QtWidgets.QLabel(
                L("Both are off, so there is nothing to study. The sidebar says "
                  "as much and points back here."))
            note.setWordWrap(True)
            leading(note)
            note.setStyleSheet(f"color:{BRASS_TEXT}; font-size:10px; border:none;")
            lay.addWidget(note)

        lay.addStretch(1)
        return page

    def _customisation(self):
        page, lay = self._pane()

        lay.addWidget(self._heading(
            L("Theme"),
            L("The organization's two papers. Whichever you pick, the test "
              "screen stays white — the real one is, and every figure in your "
              "PDFs is drawn on white. Stealth Mode below is the one thing that "
              "changes that.")))
        lay.addSpacing(14)

        cards = QtWidgets.QHBoxLayout()
        cards.setSpacing(14)
        chosen = self.store.settings.get("appearance", "light")
        night = bool(self.store.settings.get("stealthMode"))
        for key, title, detail in (
                ("system", L("Match the system"),
                 self._system_detail()),
                ("light", L("Beige"), L("Navy ink on beige paper.")),
                ("dark", L("Navy"), L("Beige ink on navy paper."))):
            card = ThemeCard(key, title, detail, chosen == key, self._set_theme)
            if night:
                card.setEnabled(False)
                dim = QtWidgets.QGraphicsOpacityEffect(card)
                dim.setOpacity(0.4)
                card.setGraphicsEffect(dim)
            cards.addWidget(card, 1)
        lay.addLayout(cards)

        if self.store.settings.get("stealthMode"):
            lay.addSpacing(12)
            said = QtWidgets.QLabel(
                L("Stealth Mode is on, so the whole app is black and the paper "
                  "below is not in use. Turn it off and you are back on the one "
                  "you picked."))
            said.setWordWrap(True)
            leading(said)
            said.setStyleSheet(f"color:{BRASS_TEXT}; font-size:10.5px; border:none;")
            lay.addWidget(said)

        self._gap(lay)

        lay.addWidget(self._heading(
            L("Stealth Mode"),
            L("For studying at night in a room where somebody else is asleep. "
              "One switch, because at that hour you should not have to find "
              "three.")))
        lay.addSpacing(12)
        lay.addWidget(self._switch(
            "stealthMode",
            L("Dark test screen, and nothing from this app makes a sound"),
            L("The whole app is drawn on black — the test screen, the results, "
              "your highlights and the formula sheet included — and the figures "
              "from your PDFs are inverted so they are not the one bright thing "
              "left on the page. Reminders from this app are silenced, and none "
              "are shown at all while you are sitting a test. It changes nothing "
              "outside this app — if you want the whole computer quiet, that is "
              "a setting of its own."),
            default=False, on_change=self._stealth_changed))
        lay.addSpacing(6)
        note = QtWidgets.QLabel(
            L("The real test is on a white screen. Worth turning this off for a "
              "full practice test in the daytime, so test day is not the first "
              "time you see it."))
        note.setWordWrap(True)
        leading(note)
        note.setContentsMargins(20, 0, 0, 0)
        note.setStyleSheet(f"color:{BRASS_TEXT}; font-size:10px; border:none;")
        lay.addWidget(note)

        self._gap(lay)

        lay.addWidget(self._heading(
            L("Language"),
            L("Four languages, the way the website does it. Anything not yet "
              "translated stays in English rather than showing a gap.")))
        lay.addSpacing(12)
        langs = QtWidgets.QHBoxLayout()
        langs.setSpacing(8)
        for code in i18n.LANGUAGES:
            langs.addWidget(self._language_button(code))
        langs.addStretch(1)
        lay.addLayout(langs)

        self._gap(lay)

        lay.addWidget(self._heading(
            L("What the app shows"),
            L("The sidebar and the practice screen carry the same signposts on "
              "your first day and your two-hundredth. Turn off the ones you "
              "have stopped needing.")))
        lay.addSpacing(14)
        for key, label, detail in self.switches():
            lay.addWidget(self._switch(key, label, detail))
            lay.addSpacing(12)

        self._gap(lay, space=4)

        lay.addWidget(self._heading(
            L("Streaks"),
            L("A run of days can be the thing that keeps you going or the thing "
              "you are afraid to break. Either one can be turned off on its "
              "own. The days themselves are still recorded, so turning a streak "
              "back on loses nothing.")))
        lay.addSpacing(14)
        for key, label, detail in self.streaks():
            lay.addWidget(self._switch(key, label, detail))
            lay.addSpacing(12)

        self._gap(lay, space=4)

        lay.addWidget(self._heading(
            L("Motion"),
            L("The app fades cards in, counts figures up and slides marks "
              "between choices. Turn it off if you would rather it just "
              "appeared.")))
        lay.addSpacing(14)
        lay.addWidget(self._switch(
            "reduceMotion", L("Reduce motion in this app"),
            L("Takes effect straight away. The test screen never animated "
              "anyway — a sitting should feel like the real thing."),
            default=False, on_change=self._motion_changed))

        self._gap(lay)

        lay.addWidget(self._heading(
            L("Flashcards"),
            L("How the cards behave when you are going through a deck.")))
        lay.addSpacing(14)
        still = bool(self.store.settings.get("reduceMotion", False))
        for key, label, detail in self.card_switches():
            if still and key == "flashcard_flip_animation":
                continue
            lay.addWidget(self._switch(key, label, detail))
            lay.addSpacing(12)
        if still:
            said = QtWidgets.QLabel(
                L("Reduce motion is on, so cards turn without an animation. "
                  "Turn it off above and the choice comes back."))
            said.setWordWrap(True)
            leading(said)
            said.setStyleSheet(f"color:{BRASS_TEXT}; font-size:10px; border:none;")
            lay.addWidget(said)
            lay.addSpacing(12)

        self._gap(lay, space=4)

        lay.addWidget(self._heading(L("Your daily target")))
        lay.addSpacing(6)
        target = QtWidgets.QLabel(
            L("The ring on the practice screen, and the days you have set "
              "aside, are part of your study plan — press Plan beside the ring "
              "to change them. They are kept there rather than here because "
              "they are something you look at while deciding what to "
              "practice."))
        target.setWordWrap(True)
        leading(target)
        target.setStyleSheet(f"color:{MUTED}; font-size:11px; border:none;")
        lay.addWidget(target)

        lay.addStretch(1)
        return page

    def _system_detail(self):
        system = {"win32": "Windows", "darwin": "macOS"}.get(sys.platform, "Linux")
        return L("Follow whatever macOS is set to.").replace("macOS", system)

    def _language_button(self, code):
        chosen = i18n.current() == code
        button = QtWidgets.QPushButton(i18n.BADGES[code])
        button.setCursor(QtCore.Qt.PointingHandCursor)
        button.setToolTip(i18n.TITLES[code])
        live = brand.live_palette()
        button.setStyleSheet(
            f"QPushButton{{border:1px solid {HAIRLINE}; border-radius:3px;"
            f"background:{SUBTLE}; color:{MUTED}; padding:5px 14px;"
            "font-size:11px;}"
            + (f"QPushButton{{background:{live['BRAND_FILL']};"
               f"color:{live['ON_BRAND']}; font-weight:600;"
               "border:1px solid transparent;}"
               if chosen else ""))
        button.clicked.connect(lambda _=False, c=code: self._set_language(c))
        return button

    def _students(self):
        from .home import ProfilesPane
        page = QtWidgets.QWidget()
        page.setObjectName("studentsPage")
        page.setStyleSheet(f"QWidget#studentsPage{{background:{PAPER};}}")
        lay = QtWidgets.QVBoxLayout(page)
        lay.setContentsMargins(0, 0, 0, 0)
        lay.setSpacing(0)
        lay.addWidget(ProfilesPane(self.store, self))
        lay.addStretch(1)
        return page

    def _storage(self):
        page, lay = self._pane()

        lay.addWidget(self._heading(
            L("Where everything is kept"),
            L("Question sets, progress, highlights, notes, saved sittings and "
              "your imported PDFs all live in one folder. Copy it to back "
              "everything up.")))
        lay.addSpacing(12)

        path = QtWidgets.QLabel(self.store.root)
        path.setWordWrap(True)
        leading(path)
        path.setTextInteractionFlags(QtCore.Qt.TextSelectableByMouse)
        path.setStyleSheet(
            f"color:{INK}; font-size:11px; background:{CARD};"
            f"border:1px solid {HAIRLINE}; border-radius:3px; padding:8px 10px;")
        lay.addWidget(path)
        lay.addSpacing(10)

        opener = QtWidgets.QPushButton(L("Open this folder"))
        opener.setCursor(QtCore.Qt.PointingHandCursor)
        opener.setStyleSheet(
            f"QPushButton{{border:1px solid {BORDER}; border-radius:3px;"
            f"background:{CARD}; color:{NAVY}; padding:6px 16px; font-size:12px;}}"
            f"QPushButton:hover{{background:{SUBTLE};}}")
        opener.clicked.connect(self._open_folder)
        lay.addWidget(opener, 0, QtCore.Qt.AlignLeft)

        self._gap(lay)

        lay.addWidget(self._heading(
            L("What is in it"),
            L("Two things take nearly all of it: the figures drawn out of your "
              "PDFs, which are the questions themselves, and the copies of the "
              "PDFs you imported. Those copies can be deleted one at a time "
              "from the practice screen and every question stays.")))
        lay.addSpacing(12)

        banks = list(getattr(self.store, "banks", []) or [])
        if not banks:
            empty = QtWidgets.QLabel(L("No question sets yet."))
            empty.setStyleSheet(f"color:{MUTED}; font-size:11px; border:none;")
            lay.addWidget(empty)
        else:
            table = QtWidgets.QWidget()
            table.setObjectName("storageTable")
            table.setStyleSheet(
                f"QWidget#storageTable{{background:{CARD};"
                f"border:1px solid {HAIRLINE}; border-radius:4px;}}")
            rows = QtWidgets.QVBoxLayout(table)
            rows.setContentsMargins(0, 0, 0, 0)
            rows.setSpacing(0)
            for i, bank in enumerate(banks):
                if i:
                    rows.addWidget(_rule())
                rows.addWidget(self._storage_row(
                    bank.name, Lf("%d questions", len(bank.questions)),
                    file_size(self.store.size_on_disk(bank.id))))
                split = self.store.size_breakdown(bank.id)
                for label, key in ((L("figures from your PDFs"), "images"),
                                   (L("copies of the PDFs you imported"),
                                    "sources")):
                    if split[key] > 0:
                        rows.addWidget(self._storage_row(
                            "", label, file_size(split[key]), inset=True))
            rows.addWidget(_rule())
            rows.addWidget(self._storage_row(
                L("Everything in this folder"), "",
                file_size(self.store.size_on_disk()), strong=True))
            lay.addWidget(table)

        lay.addStretch(1)
        return page

    def _storage_row(self, name, detail, size, strong=False, inset=False):
        row = QtWidgets.QWidget()
        row.setStyleSheet("background:transparent; border:none;")
        lay = QtWidgets.QHBoxLayout(row)
        lay.setContentsMargins(28 if inset else 14, 3 if inset else 10, 14,
                               6 if inset else 10)
        lay.setSpacing(10)

        if name:
            label = QtWidgets.QLabel(name)
            label.setStyleSheet(
                f"color:{INK}; font-size:12px; border:none;"
                + ("font-weight:600;" if strong else ""))
            lay.addWidget(label)

        if detail:
            count = QtWidgets.QLabel(detail)
            count.setStyleSheet(f"color:{MUTED}; font-size:10.5px; border:none;")
            lay.addWidget(count)

        lay.addStretch(1)
        amount = QtWidgets.QLabel(size)
        amount.setStyleSheet(
            f"color:{BRASS_TEXT if strong else MUTED}; font-size:11.5px; border:none;"
            + ("font-weight:600;" if strong else ""))
        lay.addWidget(amount)
        return row

    def _open_folder(self):
        path = self.store.root
        try:
            if sys.platform == "win32":
                os.startfile(path)          # noqa: S606 - the app's own folder
            elif sys.platform == "darwin":
                subprocess.Popen(["open", path])
            else:
                subprocess.Popen(["xdg-open", path])
        except OSError:
            pass

    def _about(self):
        page, lay = self._pane()

        head = QtWidgets.QHBoxLayout()
        head.setSpacing(14)
        head.addWidget(brand.Seal(56, NAVY), 0, QtCore.Qt.AlignTop)
        names = QtWidgets.QLabel(
            f"<div style='font-size:17px; font-weight:600; color:{NAVY};"
            f"font-family:{SERIF}'>{brand.APP_NAME}</div>"
            f"<div style='font-size:11.5px; color:{INK}'>{brand.ORGANISATION}</div>"
            f"<div style='font-size:11px; color:{BRASS_TEXT};"
            f"font-style:italic'>{brand.SLOGAN}</div>"
            f"<div style='font-size:10.5px; color:{MUTED}'>"
            + Lf("Version %@", brand.VERSION) + "</div>")
        names.setStyleSheet("border:none;")
        head.addWidget(names, 1)
        lay.addLayout(head)

        self._gap(lay, space=18)

        lay.addWidget(self._heading(L("The small print")))
        lay.addSpacing(12)

        docs = legal.DOCUMENTS.get(i18n.current(), legal.DOCUMENTS["en"])
        picker = QtWidgets.QHBoxLayout()
        picker.setSpacing(8)
        for i, doc in enumerate(docs):
            picker.addWidget(self._document_button(i, doc["title"]))
        picker.addStretch(1)
        lay.addLayout(picker)
        lay.addSpacing(12)

        chosen = docs[min(self._document, len(docs) - 1)]
        summary = QtWidgets.QLabel(chosen["summary"])
        summary.setWordWrap(True)
        leading(summary)
        summary.setStyleSheet(f"color:{MUTED}; font-size:11px; border:none;")
        lay.addWidget(summary)
        lay.addSpacing(2)
        stamp = QtWidgets.QLabel(
            Lf("Last updated: %@.", i18n.written_date(legal.LAST_UPDATED)))
        stamp.setStyleSheet(f"color:{MUTED}; font-size:10.5px; border:none;")
        lay.addWidget(stamp)
        lay.addSpacing(14)

        for section in chosen["sections"]:
            head = QtWidgets.QLabel(section["title"])
            head.setWordWrap(True)
            leading(head)
            head.setStyleSheet(
                f"color:{NAVY}; font-size:12px; font-weight:600; border:none;")
            lay.addWidget(head)
            lay.addSpacing(3)
            for para in section["paragraphs"]:
                body = QtWidgets.QLabel(para)
                body.setWordWrap(True)
                leading(body)
                body.setTextInteractionFlags(QtCore.Qt.TextSelectableByMouse)
                body.setStyleSheet(f"color:{INK}; font-size:11px; border:none;")
                lay.addWidget(body)
                lay.addSpacing(5)
            lay.addSpacing(9)

        lay.addStretch(1)
        return page

    def _document_button(self, index, title):
        chosen = index == self._document
        button = QtWidgets.QPushButton(title)
        button.setCursor(QtCore.Qt.PointingHandCursor)
        button.setStyleSheet(
            f"QPushButton{{border:1px solid {NAVY if chosen else HAIRLINE};"
            f"border-radius:3px; background:{NAVY if chosen else CARD};"
            f"color:{CARD if chosen else INK}; padding:5px 13px; font-size:11.5px;"
            + ("font-weight:600;" if chosen else "") + "}"
            f"QPushButton:hover{{background:{NAVY if chosen else SUBTLE};}}")
        button.clicked.connect(lambda _=False, i=index: self._show_document(i))
        return button

    def _show_document(self, index):
        self._document = index
        self._build()

    def _rebuild_app(self):
        window = self.parent().window() if self.parent() is not None else None
        if window is not None and hasattr(window, "reload_theme"):
            window.reload_theme()
        self._build()

    def _set_theme(self, key):
        self.store.set_setting("appearance", key)
        brand.apply_theme(key)
        self._rebuild_app()

    def _set_language(self, code):
        self.store.set_setting("language", code)
        i18n.use(code)
        window = self.parent().window() if self.parent() is not None else None
        if window is not None and hasattr(window, "reload_language"):
            window.reload_language()
            from . import intro
            self._splash = intro.play_switch_over(self, self._build)
            if self._splash is None:
                self._build()
            return
        self._rebuild_app()

    def _stealth_changed(self):
        brand.apply_stealth(bool(self.store.settings.get("stealthMode")))
        window = self.parent().window() if self.parent() is not None else None
        if window is not None and hasattr(window, "reload_stealth"):
            window.reload_stealth()
        self._build()

    def _motion_changed(self):
        brand.apply_motion(bool(self.store.settings.get("reduceMotion")))
        # the card-turn switch is not shown while motion is reduced, and it has
        self._build()


AppSettingsDialog = SettingsSheet

brand.adopt(__name__)
