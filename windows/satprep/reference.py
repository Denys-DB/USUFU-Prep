from __future__ import annotations

import math

from . import brand
from PySide6 import QtCore, QtGui, QtWidgets
from .i18n import L, Lf, Lp


INK = QtGui.QColor("#1B2A4A")
BRASS = QtGui.QColor("#A98A51")
MUTED = "#666F86"
CARD = "#FDFBF6"
CANVAS = "#FFFFFF"
HAIRLINE = "#DAD2C3"
SERIF = "Georgia, 'Times New Roman', serif"


def rebuild_derived():
    global INK, BRASS
    if isinstance(INK, str):
        INK = QtGui.QColor(INK)
    if isinstance(BRASS, str):
        BRASS = QtGui.QColor(BRASS)


def _unit(dx, dy):
    length = max(0.0001, math.hypot(dx, dy))
    return dx / length, dy / length


def _inside_angle(vertex, p, q, radius):
    ux, uy = _unit(p.x() - vertex.x(), p.y() - vertex.y())
    vx, vy = _unit(q.x() - vertex.x(), q.y() - vertex.y())
    bx, by = _unit(ux + vx, uy + vy)
    half = math.acos(max(-1.0, min(1.0, ux * vx + uy * vy))) / 2
    d = radius / max(0.05, math.sin(half))
    return vertex.x() + bx * d, vertex.y() + by * d


def _beside(p, q, inside, gap):
    mx, my = (p.x() + q.x()) / 2, (p.y() + q.y()) / 2
    nx, ny = _unit(-(q.y() - p.y()), q.x() - p.x())
    if nx * (inside.x() - mx) + ny * (inside.y() - my) > 0:
        nx, ny = -nx, -ny
    return mx + nx * gap, my + ny * gap


def _centroid(a, b, c):
    return QtCore.QPointF((a.x() + b.x() + c.x()) / 3, (a.y() + b.y() + c.y()) / 3)


def _ellipse_arc(cx, cy, rx, ry, a0, a1, steps=64):
    pts = []
    for i in range(steps + 1):
        t = math.radians(a0 + (a1 - a0) * i / steps)
        pts.append(QtCore.QPointF(cx + rx * math.cos(t), cy + ry * math.sin(t)))
    return QtGui.QPolygonF(pts)


def _right_angle(corner, p, q, size=7):
    ux, uy = _unit(p.x() - corner.x(), p.y() - corner.y())
    vx, vy = _unit(q.x() - corner.x(), q.y() - corner.y())
    return QtGui.QPolygonF([
        QtCore.QPointF(corner.x() + ux * size, corner.y() + uy * size),
        QtCore.QPointF(corner.x() + (ux + vx) * size, corner.y() + (uy + vy) * size),
        QtCore.QPointF(corner.x() + vx * size, corner.y() + vy * size)])


SHORT_LEG = 32.0
THIRTY_SIXTY = ((2.0, 72.0), (2.0 + SHORT_LEG * math.sqrt(3), 72.0),
                (2.0 + SHORT_LEG * math.sqrt(3), 72.0 - SHORT_LEG))
FORTY_FIVE = ((88.0, 32.0), (88.0, 72.0), (128.0, 72.0))
ANGLE_LABEL_RADIUS = {"thirty": 6.8, "sixty": 8.0, "forty_five": 8.0}
CYLINDER_TOP = (66.0, 20.0)
CYLINDER_RADII = (34.0, 13.0)
CYLINDER_RADIUS_START = CYLINDER_TOP
PYRAMID_BASE = ((20.0, 76.0), (96.0, 76.0), (44.0, 58.0), (120.0, 58.0))
PYRAMID_CENTRE = ((PYRAMID_BASE[0][0] + PYRAMID_BASE[3][0]) / 2,
                  (PYRAMID_BASE[0][1] + PYRAMID_BASE[3][1]) / 2)
PYRAMID_APEX = (PYRAMID_CENTRE[0], 10.0)


def _at(ox, oy, pt):
    return QtCore.QPointF(ox + pt[0], oy + pt[1])


class _Sheet(QtWidgets.QWidget):
    CELL_W = 176
    FIG_W = 164
    FIG_H = 100

    def __init__(self, parent=None):
        super().__init__(parent)
        self.setMinimumSize(960, 430)
        self.setStyleSheet(f"background:{CANVAS};")

    def _pen(self, width=1.3, dashed=False):
        pen = QtGui.QPen(INK, width)
        pen.setCapStyle(QtCore.Qt.RoundCap)
        pen.setJoinStyle(QtCore.Qt.RoundJoin)
        if dashed:
            pen.setStyle(QtCore.Qt.CustomDashLine)
            pen.setDashPattern([3, 3])
        return pen

    def _label(self, p: QtGui.QPainter, text, x, y, size=11, italic=True, serif=True):
        f = QtGui.QFont("Times New Roman" if serif else "Arial")
        f.setPixelSize(max(1, round(size)))
        f.setItalic(italic)
        p.setFont(f)
        p.setPen(INK)
        p.drawText(QtCore.QRectF(x - 30, y - 10, 60, 20),
                   QtCore.Qt.AlignCenter, text)

    def _circle(self, p, ox, oy):
        cx, cy, r = ox + 66, oy + 50, 38
        p.setPen(self._pen())
        p.drawEllipse(QtCore.QPointF(cx, cy), r, r)
        p.setBrush(INK)
        p.drawEllipse(QtCore.QPointF(cx, cy), 3, 3)
        p.setBrush(QtCore.Qt.NoBrush)
        p.drawLine(QtCore.QPointF(cx, cy), QtCore.QPointF(cx + r, cy))
        self._label(p, "r", cx + r / 2, cy - 10)

    def _rect(self, p, ox, oy):
        r = QtCore.QRectF(ox + 24, oy + 28, 100, 46)
        p.setPen(self._pen())
        p.drawRect(r)
        self._label(p, "ℓ", r.center().x(), r.top() - 10)
        self._label(p, "w", r.right() + 12, r.center().y())

    def _triangle(self, p, ox, oy):
        a = QtCore.QPointF(ox + 64, oy + 16)
        b = QtCore.QPointF(ox + 24, oy + 74)
        c = QtCore.QPointF(ox + 126, oy + 74)
        p.setPen(self._pen())
        p.drawPolygon(QtGui.QPolygonF([a, b, c]))
        p.setPen(self._pen(1.1, dashed=True))
        p.drawLine(a, QtCore.QPointF(a.x(), c.y()))
        p.setPen(self._pen(1))
        p.drawPolyline(QtGui.QPolygonF([
            QtCore.QPointF(a.x(), c.y() - 9), QtCore.QPointF(a.x() + 9, c.y() - 9),
            QtCore.QPointF(a.x() + 9, c.y())]))
        self._label(p, "h", a.x() + 12, oy + 44)
        self._label(p, "b", (b.x() + c.x()) / 2, c.y() + 12)

    def _right_triangle(self, p, ox, oy):
        top = QtCore.QPointF(ox + 32, oy + 20)
        corner = QtCore.QPointF(ox + 32, oy + 72)
        right = QtCore.QPointF(ox + 124, oy + 72)
        p.setPen(self._pen())
        p.drawPolygon(QtGui.QPolygonF([top, corner, right]))
        p.setPen(self._pen(1))
        p.drawPolyline(QtGui.QPolygonF([
            QtCore.QPointF(corner.x(), corner.y() - 9),
            QtCore.QPointF(corner.x() + 9, corner.y() - 9),
            QtCore.QPointF(corner.x() + 9, corner.y())]))
        self._label(p, "b", corner.x() - 11, oy + 46)
        self._label(p, "a", (corner.x() + right.x()) / 2, right.y() + 12)
        self._label(p, "c", ox + 84, oy + 36)

    def _radical(self, p, coefficient, radicand, cx, cy, size=11):
        italic = QtGui.QFont("Times New Roman")
        italic.setPixelSize(max(1, round(size)))
        italic.setItalic(True)
        upright = QtGui.QFont("Times New Roman")
        upright.setPixelSize(max(1, round(size)))
        wa = QtGui.QFontMetricsF(italic).horizontalAdvance(coefficient)
        wr = QtGui.QFontMetricsF(upright).horizontalAdvance("√")
        wb = QtGui.QFontMetricsF(italic).horizontalAdvance(radicand)
        x = cx - (wa + wr + wb) / 2
        self._label(p, coefficient, x + wa / 2, cy, size=size)
        x += wa
        self._label(p, "√", x + wr / 2, cy, size=size, italic=False)
        x += wr
        self._label(p, radicand, x + wb / 2, cy, size=size)
        top = cy - size * 0.52
        p.setPen(self._pen(0.8))
        p.drawLine(QtCore.QPointF(x - wr * 0.12, top), QtCore.QPointF(x + wb + 0.5, top))

    def _special(self, p, ox, oy):
        a, b, c = (_at(ox, oy, pt) for pt in THIRTY_SIXTY)
        p.setPen(self._pen())
        p.drawPolygon(QtGui.QPolygonF([a, b, c]))
        p.setPen(self._pen(1))
        p.drawPolyline(_right_angle(b, a, c))
        g = _centroid(a, b, c)
        self._label(p, "2x", *_beside(a, c, g, 9), size=11)
        self._label(p, "x", *_beside(b, c, g, 7), size=11)
        self._radical(p, "x", "3", *_beside(a, b, g, 9), size=11)
        room = ANGLE_LABEL_RADIUS
        self._label(p, "30°", *_inside_angle(a, b, c, room["thirty"]), size=7.5, italic=False)
        self._label(p, "60°", *_inside_angle(c, a, b, room["sixty"]), size=7.5, italic=False)

        d, e, f = (_at(ox, oy, pt) for pt in FORTY_FIVE)
        p.setPen(self._pen())
        p.drawPolygon(QtGui.QPolygonF([d, e, f]))
        p.setPen(self._pen(1))
        p.drawPolyline(_right_angle(e, d, f))
        g = _centroid(d, e, f)
        self._label(p, "s", *_beside(d, e, g, 7), size=11)
        self._label(p, "s", *_beside(e, f, g, 9), size=11)
        self._radical(p, "s", "2", *_beside(d, f, g, 12), size=11)
        self._label(p, "45°", *_inside_angle(d, e, f, room["forty_five"]), size=7.5, italic=False)
        self._label(p, "45°", *_inside_angle(f, d, e, room["forty_five"]), size=7.5, italic=False)

    def _box(self, p, ox, oy):
        x0, y0, w, h, dx, dy = ox + 22, oy + 34, 78, 34, 22, 16
        p.setPen(self._pen())
        p.drawRect(QtCore.QRectF(x0, y0, w, h))
        p.drawPolygon(QtGui.QPolygonF([
            QtCore.QPointF(x0, y0), QtCore.QPointF(x0 + dx, y0 - dy),
            QtCore.QPointF(x0 + w + dx, y0 - dy), QtCore.QPointF(x0 + w, y0)]))
        p.drawPolygon(QtGui.QPolygonF([
            QtCore.QPointF(x0 + w, y0), QtCore.QPointF(x0 + w + dx, y0 - dy),
            QtCore.QPointF(x0 + w + dx, y0 + h - dy), QtCore.QPointF(x0 + w, y0 + h)]))
        self._label(p, "h", x0 + w + dx + 10, y0 + h - dy / 2 - 4)
        self._label(p, "w", x0 + w + dx / 2 + 6, y0 + h - dy / 2 + 14)
        self._label(p, "ℓ", x0 + w / 2 - 6, y0 + h + 12)

    def _cylinder(self, p, ox, oy):
        cx, top = ox + CYLINDER_TOP[0], oy + CYLINDER_TOP[1]
        rx, ry = CYLINDER_RADII
        bot = oy + 72
        p.setPen(self._pen())
        p.drawPolyline(_ellipse_arc(cx, top, rx, ry, 0, 360))
        p.drawLine(QtCore.QPointF(cx - rx, top), QtCore.QPointF(cx - rx, bot))
        p.drawLine(QtCore.QPointF(cx + rx, top), QtCore.QPointF(cx + rx, bot))
        p.drawPolyline(_ellipse_arc(cx, bot, rx, ry, 0, 180))
        rim = QtCore.QPointF(cx + rx * math.cos(-0.35), top + ry * math.sin(-0.35))
        p.setBrush(INK)
        start = _at(ox, oy, CYLINDER_RADIUS_START)
        p.drawEllipse(start, 2.5, 2.5)
        p.setBrush(QtCore.Qt.NoBrush)
        p.drawLine(start, rim)
        self._label(p, "r", (cx + rim.x()) / 2, top + 4.5)
        self._label(p, "h", cx + rx + 11, (top + bot) / 2)

    def _sphere(self, p, ox, oy):
        cx, cy, r, ry = ox + 68, oy + 48, 38, 14
        p.setPen(self._pen())
        p.drawEllipse(QtCore.QPointF(cx, cy), r, r)
        p.drawPolyline(_ellipse_arc(cx, cy, r, ry, 0, 180))
        p.setPen(self._pen(1.1, dashed=True))
        p.drawPolyline(_ellipse_arc(cx, cy, r, ry, 180, 360))
        p.setPen(self._pen())
        p.setBrush(INK)
        p.drawEllipse(QtCore.QPointF(cx, cy), 3, 3)
        p.setBrush(QtCore.Qt.NoBrush)
        p.drawLine(QtCore.QPointF(cx, cy), QtCore.QPointF(cx + r, cy))
        self._label(p, "r", cx + r / 2, cy + 5)

    def _cone(self, p, ox, oy):
        cx, cy, rx, ry = ox + 66, oy + 68, 34, 14
        apex = QtCore.QPointF(cx, oy + 10)
        centre = QtCore.QPointF(cx, cy)
        p.setPen(self._pen())
        p.drawPolyline(QtGui.QPolygonF([
            QtCore.QPointF(cx - rx, cy), apex, QtCore.QPointF(cx + rx, cy)]))
        p.drawPolyline(_ellipse_arc(cx, cy, rx, ry, 0, 180))
        p.drawLine(apex, centre)
        p.setPen(self._pen(1.1, dashed=True))
        p.drawPolyline(_ellipse_arc(cx, cy, rx, ry, 180, 360))
        p.drawLine(centre, QtCore.QPointF(cx + rx, cy))
        p.setPen(self._pen(1))
        p.drawPolyline(_right_angle(centre, apex, QtCore.QPointF(cx + rx, cy)))
        self._label(p, "h", cx - 8, oy + 46)
        self._label(p, "r", cx + rx / 2, cy + 5.5)

    def _pyramid(self, p, ox, oy):
        fl, fr, bl, br = (_at(ox, oy, pt) for pt in PYRAMID_BASE)
        centre, apex = _at(ox, oy, PYRAMID_CENTRE), _at(ox, oy, PYRAMID_APEX)
        p.setPen(self._pen())
        p.drawPolyline(QtGui.QPolygonF([fl, fr, br]))
        p.drawPolyline(QtGui.QPolygonF([fl, apex, fr]))
        p.drawLine(apex, br)
        p.setPen(self._pen(1.1, dashed=True))
        p.drawPolyline(QtGui.QPolygonF([fl, bl, br]))
        p.drawLine(bl, apex)
        p.drawLine(apex, centre)
        p.setPen(self._pen(1))
        p.drawPolyline(_right_angle(centre, apex, QtCore.QPointF(centre.x() + 10, centre.y())))
        self._label(p, "h", centre.x() - 7, oy + 40)
        self._label(p, "w", *_beside(fr, br, centre, 9))
        self._label(p, "ℓ", *_beside(fl, fr, centre, 10))

    def _formula(self, p, text, cx, y, size=13):
        f = QtGui.QFont("Times New Roman", size)
        f.setItalic(True)
        p.setFont(f)
        p.setPen(INK)
        p.drawText(QtCore.QRectF(cx - 90, y, 180, 20), QtCore.Qt.AlignCenter, text)

    def _fraction_formula(self, p, lead, num, den, trail, cx, y):
        big = QtGui.QFont("Times New Roman", 13)
        big.setItalic(True)
        small = QtGui.QFont("Times New Roman", 10)
        small.setItalic(True)
        p.setPen(INK)

        fm_big = QtGui.QFontMetricsF(big)
        fm_small = QtGui.QFontMetricsF(small)
        w_lead = fm_big.horizontalAdvance(lead + " ")
        w_frac = max(fm_small.horizontalAdvance(num), fm_small.horizontalAdvance(den)) + 6
        w_trail = fm_big.horizontalAdvance(" " + trail)
        total = w_lead + w_frac + w_trail
        x = cx - total / 2

        p.setFont(big)
        p.drawText(QtCore.QRectF(x, y, w_lead, 20),
                   QtCore.Qt.AlignVCenter | QtCore.Qt.AlignLeft, lead)
        p.setFont(small)
        p.drawText(QtCore.QRectF(x + w_lead, y - 6, w_frac, 14),
                   QtCore.Qt.AlignCenter, num)
        p.drawText(QtCore.QRectF(x + w_lead, y + 7, w_frac, 14),
                   QtCore.Qt.AlignCenter, den)
        p.setPen(self._pen(1))
        p.drawLine(QtCore.QPointF(x + w_lead + 2, y + 9),
                   QtCore.QPointF(x + w_lead + w_frac - 2, y + 9))
        p.setPen(INK)
        p.setFont(big)
        p.drawText(QtCore.QRectF(x + w_lead + w_frac, y, w_trail + 6, 20),
                   QtCore.Qt.AlignVCenter | QtCore.Qt.AlignLeft, " " + trail)

    def paintEvent(self, event):
        p = QtGui.QPainter(self)
        p.setRenderHint(QtGui.QPainter.Antialiasing)
        p.fillRect(self.rect(), QtGui.QColor(CANVAS))

        gap = 8
        cell = self.CELL_W + gap
        left = 20

        row1_fig_y = 16
        row1_cap_y = row1_fig_y + self.FIG_H + 4
        for i, draw in enumerate((self._circle, self._rect, self._triangle,
                                  self._right_triangle, self._special)):
            draw(p, left + i * cell, row1_fig_y)
        cx = lambda i: left + i * cell + self.FIG_W / 2
        self._formula(p, "A = πr²", cx(0), row1_cap_y)
        self._formula(p, "C = 2πr", cx(0), row1_cap_y + 18)
        self._formula(p, "A = ℓw", cx(1), row1_cap_y)
        self._fraction_formula(p, "A =", "1", "2", "bh", cx(2), row1_cap_y + 4)
        self._formula(p, "c² = a² + b²", cx(3), row1_cap_y)
        f = QtGui.QFont("Georgia", 11)
        p.setFont(f)
        p.setPen(INK)
        self.caption_cell = QtCore.QRectF(cx(4) - self.CELL_W / 2, row1_cap_y,
                                          self.CELL_W, 40)
        self.caption_bounds = p.drawText(
            self.caption_cell,
            QtCore.Qt.AlignHCenter | QtCore.Qt.AlignTop | QtCore.Qt.TextWordWrap,
            L("Special Right Triangles"))

        row2_fig_y = row1_cap_y + 46
        row2_cap_y = row2_fig_y + self.FIG_H + 4
        for i, draw in enumerate((self._box, self._cylinder, self._sphere,
                                  self._cone, self._pyramid)):
            draw(p, left + i * cell, row2_fig_y)
        self._formula(p, "V = ℓwh", cx(0), row2_cap_y)
        self._formula(p, "V = πr²h", cx(1), row2_cap_y)
        self._fraction_formula(p, "V =", "4", "3", "πr³", cx(2), row2_cap_y + 4)
        self._fraction_formula(p, "V =", "1", "3", "πr²h", cx(3), row2_cap_y + 4)
        self._fraction_formula(p, "V =", "1", "3", "ℓwh", cx(4), row2_cap_y + 4)

        facts_y = row2_cap_y + 40
        p.setFont(QtGui.QFont("Georgia", 11))
        for i, line in enumerate((
                L("The number of degrees of arc in a circle is 360."),
                L("The number of radians of arc in a circle is 2π."),
                L("The sum of the measures in degrees of the angles of a triangle is 180."))):
            p.drawText(QtCore.QRectF(left, facts_y + i * 20, 900, 20),
                       QtCore.Qt.AlignLeft | QtCore.Qt.AlignVCenter, line)

        self.setMinimumHeight(int(facts_y + 3 * 20 + 20))
        p.end()


class ReferenceDialog(QtWidgets.QDialog):
    def __init__(self, parent=None):
        super().__init__(parent)
        brand.as_sheet(self, parent)
        self.setWindowTitle(L("Reference"))
        self.setStyleSheet(f"background:{CANVAS};")
        self.resize(1000, 560)
        lay = QtWidgets.QVBoxLayout(self)
        lay.setContentsMargins(0, 0, 0, 0)
        lay.setSpacing(0)

        header = QtWidgets.QWidget()
        header.setStyleSheet(f"background:{CARD}; border-bottom:1px solid {HAIRLINE};")
        hl = QtWidgets.QVBoxLayout(header)
        hl.setContentsMargins(24, 18, 24, 14)
        hl.setSpacing(7)
        title = QtWidgets.QLabel(L("Reference"))
        title.setStyleSheet(
            f"color:{QtGui.QColor(INK).name()}; font-size:19px; font-weight:600;"
            f"font-family:{SERIF};")
        hl.addWidget(title)
        rule = QtWidgets.QFrame()
        rule.setFixedSize(32, 1)
        rule.setStyleSheet(f"background:{QtGui.QColor(BRASS).name()};")
        hl.addWidget(rule)
        lay.addWidget(header)

        area = QtWidgets.QScrollArea()
        area.setWidgetResizable(True)
        area.setFrameShape(QtWidgets.QFrame.NoFrame)
        area.setWidget(_Sheet())
        from .ui import SCROLLBAR
        area.verticalScrollBar().setStyleSheet(SCROLLBAR)
        area.horizontalScrollBar().setStyleSheet(SCROLLBAR)
        lay.addWidget(area, 1)

        bar = QtWidgets.QHBoxLayout()
        bar.setContentsMargins(14, 8, 14, 12)
        bar.addStretch(1)
        close = QtWidgets.QPushButton(L("Close"))
        close.setShortcut(QtGui.QKeySequence(QtCore.Qt.Key_Escape))
        close.setCursor(QtCore.Qt.PointingHandCursor)
        close.setStyleSheet(
            "QPushButton{background:#1B2A4A; color:#FDFBF6; border-radius:3px;"
            "padding:8px 24px; font-size:13px; font-weight:600;}"
            "QPushButton:hover{background:#121E37;}")
        close.clicked.connect(self.accept)
        bar.addWidget(close)
        lay.addLayout(bar)

brand.adopt(__name__)
