from __future__ import annotations

import shiboken6
from PySide6 import QtCore, QtGui, QtWidgets

from . import brand

BREATHE_MS = 600
HOLD_MS = 1100
FLIGHT_MS = 1100
DISSOLVE_MS = 900

SWITCH_HOLD_MS = 380
SWITCH_FADE_MS = 550
SWITCH_SCALE = 0.82

SEAL_CAP = 300
SEAL_SHARE = 0.52
START_SCALE = 0.92


class IntroOverlay(QtWidgets.QWidget):

    finished = QtCore.Signal()

    def __init__(self, parent, aim, landing_ink=None):
        super().__init__(parent)
        self._aim = aim
        self._landing_ink = landing_ink
        self._target = QtCore.QRectF()
        self._progress = 0.0
        self._phase = "breathe"
        self.setAttribute(QtCore.Qt.WA_TransparentForMouseEvents, False)
        self.setGeometry(parent.rect())
        parent.installEventFilter(self)
        self._steps = []
        self._settles = 0
        self._previous = None
        self._ground = 1.0

    def eventFilter(self, watched, event):
        if event.type() == QtCore.QEvent.Resize and watched is self.parentWidget():
            self.setGeometry(watched.rect())
        return False

    def play(self):
        self.show()
        self.raise_()
        self._run("breathe", BREATHE_MS, self._after_breathe)

    def _after_breathe(self):
        self._phase = "hold"
        self._progress = 1.0
        self.update()
        QtCore.QTimer.singleShot(HOLD_MS, self._fly)

    def _fly(self):
        here = self._aim()
        if here is None:
            self._land()
            return
        if here != self._previous and self._settles < 12:
            self._settles += 1
            self._previous = here
            QtCore.QTimer.singleShot(40, self._fly)
            return
        self._target = QtCore.QRectF(here)
        curve = QtCore.QEasingCurve(QtCore.QEasingCurve.BezierSpline)
        curve.addCubicBezierSegment(QtCore.QPointF(0.55, 0.0),
                                    QtCore.QPointF(0.2, 1.0),
                                    QtCore.QPointF(1.0, 1.0))
        self._dissolve()
        self._run("flight", FLIGHT_MS, self._land, curve)

    def _land(self):
        self._phase = "done"
        self.hide()
        self.finished.emit()
        self.deleteLater()

    def _run(self, phase, duration, done, curve=None):
        self._phase = phase
        animation = QtCore.QVariantAnimation(self)
        animation.setStartValue(0.0)
        animation.setEndValue(1.0)
        animation.setDuration(duration)
        animation.setEasingCurve(curve or QtCore.QEasingCurve(
            QtCore.QEasingCurve.OutCubic))
        animation.valueChanged.connect(self._step)
        animation.finished.connect(done)
        animation.start(QtCore.QAbstractAnimation.DeleteWhenStopped)
        self._steps.append(animation)

    def _dissolve(self):
        fade = QtCore.QVariantAnimation(self)
        fade.setStartValue(1.0)
        fade.setEndValue(0.0)
        fade.setDuration(DISSOLVE_MS)
        fade.setEasingCurve(QtCore.QEasingCurve.OutCubic)
        fade.valueChanged.connect(self._fade)
        fade.start(QtCore.QAbstractAnimation.DeleteWhenStopped)
        self._steps.append(fade)

    def _fade(self, value):
        self._ground = float(value)
        self.update()

    def _step(self, value):
        self._progress = float(value)
        self.update()

    def play_switch(self, rebuild=None):
        self._phase = "switch"
        self._ground = 1.0
        self._progress = 1.0
        self.show()
        self.raise_()
        self.update()
        QtCore.QTimer.singleShot(SWITCH_HOLD_MS,
                                 lambda: self._switch_away(rebuild))

    def _switch_away(self, rebuild):
        if rebuild is not None:
            rebuild()
        self.raise_()
        fade = QtCore.QVariantAnimation(self)
        fade.setStartValue(1.0)
        fade.setEndValue(0.0)
        fade.setDuration(SWITCH_FADE_MS)
        fade.setEasingCurve(QtCore.QEasingCurve.OutCubic)
        fade.valueChanged.connect(self._fade)
        fade.finished.connect(self._land)
        fade.start(QtCore.QAbstractAnimation.DeleteWhenStopped)
        self._steps.append(fade)

    def _resting(self):
        side = min(SEAL_CAP, self.width() * SEAL_SHARE)
        side = min(side, self.height() * 0.6)
        return QtCore.QRectF((self.width() - side) / 2,
                             (self.height() - side) / 2, side, side)

    def _seal_rect(self):
        rest = self._resting()
        if self._phase == "breathe":
            scale = START_SCALE + (1 - START_SCALE) * self._progress
            side = rest.width() * scale
            return QtCore.QRectF(rest.center().x() - side / 2,
                                 rest.center().y() - side / 2, side, side)
        if self._phase == "switch":
            side = rest.width() * SWITCH_SCALE
            return QtCore.QRectF(rest.center().x() - side / 2,
                                 rest.center().y() - side / 2, side, side)
        if self._phase == "flight":
            t = self._progress
            return QtCore.QRectF(
                rest.x() + (self._target.x() - rest.x()) * t,
                rest.y() + (self._target.y() - rest.y()) * t,
                rest.width() + (self._target.width() - rest.width()) * t,
                rest.height() + (self._target.height() - rest.height()) * t)
        return rest

    def _ground_opacity(self):
        return max(0.0, min(1.0, self._ground))

    def _seal_opacity(self):
        if self._phase == "breathe":
            return self._progress
        if self._phase == "switch":
            return self._ground
        return 1.0

    def _seal_ink(self):
        cream = QtGui.QColor(brand.INTRO_SEAL)
        if self._landing_ink is None or self._phase != "flight":
            return cream
        landed = self._landing_ink()
        if landed is None:
            return cream
        t = 1.0 - self._ground_opacity()
        return QtGui.QColor(
            round(cream.red() + (landed.red() - cream.red()) * t),
            round(cream.green() + (landed.green() - cream.green()) * t),
            round(cream.blue() + (landed.blue() - cream.blue()) * t))

    def paintEvent(self, event):
        painter = QtGui.QPainter(self)
        painter.setRenderHint(QtGui.QPainter.Antialiasing)

        ground = QtGui.QColor(brand.INTRO_BACKDROP_NIGHT if brand.stealth_on()
                              else brand.INTRO_BACKDROP)
        ground.setAlphaF(self._ground_opacity())
        painter.fillRect(self.rect(), ground)

        painter.setOpacity(self._seal_opacity())
        brand.paint_seal(painter, self._seal_rect(), self._seal_ink())
        painter.end()

    def mousePressEvent(self, event):
        self._land()


def play_switch_over(window, rebuild=None):
    if not brand.motion_on():
        if rebuild is not None:
            rebuild()
        return None
    overlay = IntroOverlay(window, lambda: None)
    overlay.play_switch(rebuild)
    return overlay


def play_over(window, home, on_done=None):
    seal = getattr(home, "masthead_seal", None)
    if seal is None or not brand.motion_on():
        if on_done:
            on_done()
        return None

    def aim():
        if not shiboken6.isValid(seal) or not seal.parent():
            return None
        return QtCore.QRect(seal.mapTo(window, QtCore.QPoint(0, 0)), seal.size())

    seal.set_blank(True)
    overlay = IntroOverlay(window, aim, landing_ink=lambda: (
        seal.ink() if shiboken6.isValid(seal) else None))

    def done():
        if shiboken6.isValid(seal):
            seal.set_blank(False)
        if on_done:
            on_done()

    overlay.finished.connect(done)
    overlay.play()
    return overlay
