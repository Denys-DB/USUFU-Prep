from __future__ import annotations

from PySide6 import QtCore, QtGui, QtWidgets

from .core import Store, Session, is_correct
from .i18n import L, Lf
from . import brand
from . import fulltest
from .ui import (BORDER, BRAND_FILL, BRASS, BRASS_SOFT, Blocks, CANVAS, CARD, ElidedLabel,
                 CHROME, ChoiceRow, DEFAULT_BODY_PT, GridInField, HAIRLINE, INK, MAX_BODY_PT,
                 MIN_BODY_PT, MUTED, NAVY, ON_BRAND, SERIF, NUMERALS, WRONG, _clock,
                 chosen_body_size, leading, question_width, remember_body_size,
                 widest_region)
from .reference import ReferenceDialog


class DoubleExamScreen(QtWidgets.QWidget):

    finished = QtCore.Signal()
    left = QtCore.Signal()

    def __init__(self, store: Store, session: Session, parent=None):
        super().__init__(parent)
        self.store = store
        self.session = session
        self.body_size = chosen_body_size()
        self.setStyleSheet(f"background:{CANVAS};")

        root = QtWidgets.QVBoxLayout(self)
        root.setContentsMargins(0, 0, 0, 0)
        root.setSpacing(0)
        root.addWidget(self._header())
        root.addWidget(self._banner())

        panes = QtWidgets.QHBoxLayout()
        panes.setContentsMargins(0, 0, 0, 0)
        panes.setSpacing(0)
        self._seats = []
        for seat in (0, 1):
            pane = _SeatPane(self, seat)
            pane.setSizePolicy(QtWidgets.QSizePolicy.Ignored,
                               QtWidgets.QSizePolicy.Preferred)
            self._seats.append(pane)
            panes.addWidget(pane, 1)
            if seat == 0:
                rule = QtWidgets.QFrame()
                rule.setFixedWidth(1)
                rule.setStyleSheet(f"background:{HAIRLINE}; border:none;")
                panes.addWidget(rule)
        root.addLayout(panes, 1)
        root.addWidget(self._footer())

        self.tick = QtCore.QTimer(self)
        self.tick.setInterval(1000)
        self.tick.timeout.connect(self._tick)
        self.tick.start()
        self._refresh_clock()

    def _header(self):
        bar = QtWidgets.QWidget()
        bar.setStyleSheet(f"background:{CARD}; border-bottom:1px solid {HAIRLINE};")
        lay = QtWidgets.QHBoxLayout(bar)
        lay.setContentsMargins(22, 12, 22, 10)

        title = QtWidgets.QLabel(
            f"<div style='font-size:16px; font-weight:600; color:{NAVY};"
            f"font-family:{SERIF}'>{self.session.display_title}</div>"
            f"<div style='font-size:10px; color:{MUTED}'>" + L("Side by side")
            + "</div>")
        lay.addWidget(title, 1)

        self.clock = QtWidgets.QLabel()
        self.clock.setAlignment(QtCore.Qt.AlignCenter)
        lay.addWidget(self.clock, 1)

        right = QtWidgets.QHBoxLayout()
        right.setSpacing(16)
        tools = ([(L("Reference"), self._reference)]
                 if fulltest.offers_reference(self.session) else [])
        for text, slot in tools + [(L("Leave"), self._leave),
                                   (L("Submit"), self._submit)]:
            button = QtWidgets.QPushButton(text)
            button.setFlat(True)
            button.setCursor(QtCore.Qt.PointingHandCursor)
            button.setStyleSheet(
                f"QPushButton{{border:none; color:{NAVY}; font-size:11px;"
                "background:transparent;}")
            button.clicked.connect(slot)
            right.addWidget(button)
        holder = QtWidgets.QWidget()
        holder.setLayout(right)
        holder.setStyleSheet("background:transparent;")
        lay.addWidget(holder, 1, QtCore.Qt.AlignRight)
        return bar

    def _banner(self):
        lbl = QtWidgets.QLabel(L("THIS IS A PRACTICE TEST"))
        lbl.setAlignment(QtCore.Qt.AlignCenter)
        lbl.setStyleSheet(
            f"background:{BRASS_SOFT}; color:{NAVY}; font-size:9px; font-weight:600;"
            f"letter-spacing:2px; padding:5px; border-top:1px solid {BRASS};"
            f"border-bottom:1px solid {BRASS};")
        return lbl

    def _footer(self):
        bar = QtWidgets.QWidget()
        bar.setStyleSheet(f"background:{CHROME}; border-top:1px solid {HAIRLINE};")
        lay = QtWidgets.QHBoxLayout(bar)
        lay.setContentsMargins(22, 8, 22, 8)
        left = ElidedLabel(self.session.bank_name)
        left.setStyleSheet(f"color:{MUTED}; font-size:11px; border:none;")
        lay.addWidget(left, 1)
        right = QtWidgets.QLabel(L("Each answer goes into that student's own record."))
        right.setStyleSheet(f"color:{MUTED}; font-size:10px; border:none;")
        lay.addWidget(right)
        return bar

    def zoom_by(self, delta):
        self.body_size = (DEFAULT_BODY_PT if delta == 0
                          else max(MIN_BODY_PT,
                                   min(MAX_BODY_PT, self.body_size + delta)))
        remember_body_size(self.body_size)
        for pane in self._seats:
            pane.render_question()

    def _refresh_clock(self):
        if self.session.config.get("timed"):
            left = max(0, int(self.session.seconds_remaining))
            colour = WRONG if left <= 300 else NAVY
            self.clock.setText(
                f"<div style='font-size:22px; font-weight:600; color:{colour};"
                f"font-family:{NUMERALS}'>{_clock(left)}</div>"
                f"<div style='font-size:9px; color:{MUTED}'>" + L("for both of you")
                + "</div>")
        else:
            self.clock.setText(
                f"<div style='font-size:12px; color:{MUTED}'>" + L("Untimed") + "</div>")

    def _tick(self):
        if not self.session.config.get("timed"):
            return
        self.session.seconds_remaining = max(0, self.session.seconds_remaining - 1)
        self._refresh_clock()
        if self.session.seconds_remaining <= 0:
            self.tick.stop()
            brand.tell(
                self, L("Time's up"),
                L("The timer has run out. Your answers have been kept."))
            self._finish()
        elif int(self.session.seconds_remaining) % 10 == 0:
            self.store.save_session(self.session)

    def answered(self, index, response):
        self.session.attempts[index].response = response
        self.store.save_session(self.session)

    def moved(self, seat, target):
        if target is None:
            if seat not in self.session.seats_finished:
                self.session.seats_finished.append(seat)
        else:
            if seat in self.session.seats_finished:
                self.session.seats_finished.remove(seat)
            if seat == 0:
                self.session.index = target
            else:
                self.session.partner_index = target
        self.store.save_session(self.session)
        self._seats[seat].render_question()
        if self.session.both_seats_finished:
            self._both_done()

    def _both_done(self):
        box = brand.alert(
            self, L("You have both finished"),
            L("Every question has been answered or passed over. Keep working "
              "to go back over any of them, or end the test now."))
        end = box.addButton(L("See results"), QtWidgets.QMessageBox.AcceptRole)
        box.addButton(L("Keep working"), QtWidgets.QMessageBox.RejectRole)
        box.exec()
        if box.clickedButton() is end:
            self._finish()

    def _reference(self):
        ReferenceDialog(self).exec()

    def _leave(self):
        box = brand.alert(
            self, L("Leave this test?"),
            L("Your place is saved, so you can pick this test up later from "
              "the home screen."))
        keep = box.addButton(L("Save and leave"), QtWidgets.QMessageBox.AcceptRole)
        drop = box.addButton(L("Discard"), QtWidgets.QMessageBox.DestructiveRole)
        box.addButton(L("Keep working"), QtWidgets.QMessageBox.RejectRole)
        box.exec()
        if box.clickedButton() is keep:
            self.tick.stop()
            self.store.save_session(self.session)
            self.left.emit()
        elif box.clickedButton() is drop:
            self.tick.stop()
            self.store.discard_session(self.session.bank_id)
            self.left.emit()

    def _submit(self):
        if brand.ask(
                self, L("Submit this section?"),
                L("Both of you will see your own results, and each answer goes "
                  "into that student's own record."),
                accept=L("Hand it in")):
            self._finish()

    def _finish(self):
        self.tick.stop()
        self.store.finish_session(self.session)
        self.finished.emit()


class _SeatPane(QtWidgets.QWidget):

    def __init__(self, screen: DoubleExamScreen, seat: int):
        super().__init__(screen)
        self.screen = screen
        self.seat = seat
        self.setStyleSheet(f"background:{CANVAS};")

        lay = QtWidgets.QVBoxLayout(self)
        lay.setContentsMargins(0, 0, 0, 0)
        lay.setSpacing(0)

        session = screen.session
        accents = session.turn_accents
        index = accents[seat] if seat < len(accents) else seat
        self.tint = screen_accent(index)

        self.band = QtWidgets.QLabel()
        self.band.setStyleSheet(
            f"background:{self.tint}; color:#FFFFFF; font-size:11px; font-weight:600;"
            "letter-spacing:1px; padding:6px 14px;")
        lay.addWidget(self.band)

        self.scroll = QtWidgets.QScrollArea()
        self.scroll.setWidgetResizable(True)
        self.scroll.setFrameShape(QtWidgets.QFrame.NoFrame)
        self.scroll.setStyleSheet(f"background:{CANVAS};")
        from .ui import SCROLLBAR
        self.scroll.verticalScrollBar().setStyleSheet(SCROLLBAR)
        self.body = QtWidgets.QWidget()
        self.body.setStyleSheet(f"background:{CANVAS};")
        self.body_layout = QtWidgets.QVBoxLayout(self.body)
        self.body_layout.setContentsMargins(16, 14, 16, 14)
        self.body_layout.setSpacing(12)
        self.scroll.setWidget(self.body)
        lay.addWidget(self.scroll, 1)

        nav = QtWidgets.QWidget()
        nav.setStyleSheet(f"background:{CHROME}; border-top:1px solid {HAIRLINE};")
        nav_lay = QtWidgets.QHBoxLayout(nav)
        nav_lay.setContentsMargins(14, 8, 14, 8)
        self.back = QtWidgets.QPushButton(L("Back"))
        self.back.setCursor(QtCore.Qt.PointingHandCursor)
        self.back.setStyleSheet(
            f"QPushButton{{background:transparent; color:{INK};"
            f"border:1px solid {HAIRLINE}; border-radius:3px; padding:7px 16px;"
            "font-size:12px; font-weight:600;}"
            f"QPushButton:disabled{{color:{MUTED}; border-color:{HAIRLINE};}}")
        self.back.clicked.connect(lambda: self._move(-1))
        nav_lay.addWidget(self.back)
        nav_lay.addStretch(1)
        self.next = QtWidgets.QPushButton(L("Next"))
        self.next.setCursor(QtCore.Qt.PointingHandCursor)
        self.next.setStyleSheet(
            f"QPushButton{{background:{BRAND_FILL}; color:{ON_BRAND}; border-radius:3px;"
            "padding:7px 16px; font-size:12px; font-weight:600;}"
            f"QPushButton:disabled{{background:{HAIRLINE}; color:{MUTED};}}")
        self.next.clicked.connect(lambda: self._move(1))
        nav_lay.addWidget(self.next)
        lay.addWidget(nav)

        self.render_question()

    def _positions(self):
        return self.screen.session.positions(self.seat)

    def render_question(self):
        session = self.screen.session
        positions = self._positions()
        index = session.index_for(self.seat)
        name = (session.turn_names[self.seat]
                if self.seat < len(session.turn_names) else "")
        finished = session.is_finished_seat(self.seat)
        at = positions.index(index) if index in positions else 0
        self.band.setText(
            f"{name.upper()}   ·   "
            + (L("done") if finished
               else Lf("%1$d of %2$d", min(at + 1, len(positions)), len(positions))))

        while self.body_layout.count():
            item = self.body_layout.takeAt(0)
            if item.widget():
                item.widget().deleteLater()

        if finished or index not in positions:
            done = QtWidgets.QLabel(
                L("Both of you are done.") if session.both_seats_finished
                else L("All done — waiting for the other one to finish."))
            done.setWordWrap(True)
            leading(done)
            done.setAlignment(QtCore.Qt.AlignCenter)
            done.setStyleSheet(f"color:{MUTED}; font-size:12px; border:none;")
            self.body_layout.addWidget(done)
            self.body_layout.addStretch(1)
        else:
            question = session.questions[index]
            attempt = session.attempts[index]
            images = self.screen.store.images_dir(session.bank_id)
            body_points = widest_region(list(question.stimulus)
                                        + list(question.prompt))
            choice_points = widest_region([b for c in question.choices
                                           for b in c.blocks])
            if question.stimulus:
                self.body_layout.addWidget(
                    Blocks(question.stimulus, images, self.screen.body_size,
                           question_points=body_points))
            self.body_layout.addWidget(
                Blocks(question.prompt, images, self.screen.body_size,
                       question_points=body_points))
            if question.kind == "student_response":
                field = GridInField(attempt.response, self.screen.body_size, 220)
                field.changed.connect(
                    lambda v, i=index: self.screen.answered(i, v))
                self.body_layout.addWidget(field)
            else:
                for choice in question.choices:
                    row = ChoiceRow(choice, images, self.screen.body_size,
                                    selected=attempt.response == choice.letter,
                                    eliminated=False, eliminator_on=False,
                                    question_points=choice_points)
                    row.clicked.connect(lambda letter, i=index:
                                        self._answer(i, letter))
                    self.body_layout.addWidget(row)
            self.body_layout.addStretch(1)

        self.back.setEnabled(at > 0)
        self.next.setEnabled(not finished and at < len(positions))

    def _answer(self, index, letter):
        self.screen.answered(index, letter)
        self.render_question()

    def _move(self, delta):
        positions = self._positions()
        index = self.screen.session.index_for(self.seat)
        at = positions.index(index) if index in positions else 0
        target = at + delta
        if target < 0:
            return
        self.screen.moved(self.seat,
                          positions[target] if target < len(positions) else None)


def screen_accent(index):
    from .ui import ExamScreen
    colours = ExamScreen.PROFILE_ACCENTS
    return colours[index % len(colours)]

brand.adopt(__name__)
