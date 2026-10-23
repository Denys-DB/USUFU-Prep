from __future__ import annotations

import math
import os
import sys

import shiboken6
from PySide6 import QtCore, QtGui, QtWidgets

from .i18n import L

ORGANISATION = "United States Universities For Ukraine"
INITIALS = "USUFU"
SLOGAN = "Advancing Excellence. Ensuring Success."
ESTABLISHED = "Est. 2026"
APP_NAME = "USUFU Prep"
STAGE = ""
def _released_version() -> str:
    try:
        from ._build_version import VERSION as baked
        if baked:
            return baked
    except Exception:
        pass
    import subprocess
    try:
        out = subprocess.run(
            ["git", "describe", "--tags", "--abbrev=0"],
            cwd=os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
            capture_output=True, text=True, timeout=3,
            creationflags=getattr(subprocess, "CREATE_NO_WINDOW", 0))
        if out.returncode == 0 and out.stdout.strip():
            return out.stdout.strip().lstrip("v")
    except Exception:
        pass
    return "unreleased"


VERSION = _released_version()

ICON_FONT = "Segoe MDL2 Assets"
ICONS = {
    "learn": chr(0xE736),
    "switch_student": chr(0xE8CB),
    "study": chr(0xE9D5),
    "customisation": chr(0xE9E9),
    "students": chr(0xE716),
    "storage": chr(0xEDA2),
    "about": chr(0xE946),
    "open": chr(0xE70D),
    "shut": chr(0xE76C),
    "pencil": chr(0xE70F),
    "new_shelf": chr(0xE710),
    "sort": chr(0xE8CB),
    "floor": chr(0xE7B8),
    "shut_left": chr(0xE76B),
    "fill_window": chr(0xE740),
    "shrink_window": chr(0xE73F),
    "settings": chr(0xE713),
    "clock": chr(0xE823),
    "play": chr(0xE768),
    "pause": chr(0xE769),
    "shuffle": chr(0xE8B1),
    "star": chr(0xE734),
    "star_on": chr(0xE735),
    "tick": chr(0xE73E),
    "cross": chr(0xE711),
    "more": chr(0xE712),
    "tray": chr(0xE7B8),
    "flag": chr(0xE7C1),
}

if sys.platform != "win32":
    ICON_FONT = "DejaVu Sans"
    ICONS.update({
        "learn": chr(0x25A4),
        "switch_student": chr(0x21C5),
        "study": chr(0x2611),
        "customisation": chr(0x2630),
        "students": chr(0x263A),
        "storage": chr(0x26C1),
        "about": chr(0x2139),
        "open": chr(0x25BE),
        "shut": chr(0x25B8),
        "pencil": chr(0x270E),
        "new_shelf": chr(0x002B),
        "sort": chr(0x21C5),
        "floor": chr(0x2294),
        "shut_left": chr(0x25C2),
        "fill_window": chr(0x21F1),
        "shrink_window": chr(0x21F2),
        "settings": chr(0x2699),
        "clock": chr(0x25F7),
        "play": chr(0x25B6),
        "pause": chr(0x2016),
        "shuffle": chr(0x21C4),
        "star": chr(0x2606),
        "star_on": chr(0x2605),
        "tick": chr(0x2713),
        "cross": chr(0x2715),
        "more": chr(0x22EF),
        "tray": chr(0x2294),
        "flag": chr(0x2691),
    })


LIGHT = {
    "PAPER": "#F4F0E8",
    "CARD": "#FDFBF6",
    "PAPER_DEEP": "#ECE6DA",
    "SUBTLE": "#F1EDE5",
    "NAVY": "#1B2A4A",
    "NAVY_DEEP": "#121E37",
    "INK": "#1B2A4A",
    "MUTED": "#666F86",
    "HAIRLINE": "#DAD2C3",
    "BORDER": "#C9BFAC",
    "BRASS": "#A98A51",
    "BRASS_SOFT": "#E9E0CD",
    "BRASS_TEXT": "#7D6230",
    "CHROME": "#F9F8F5",
    "ACCENT": "#175AC9",
    "ACCENT_SOFT": "#EDF2FF",
    "CORRECT": "#215A38",
    "CORRECT_SOFT": "#E6F0E6",
    "WRONG": "#832727",
    "WRONG_SOFT": "#F6EAE7",
    "ON_BRAND": "#FDFBF6",
    "BRAND_FILL": "#1B2A4A",
}

DARK = {
    "PAPER": "#0E1629",
    "CARD": "#16213A",
    "PAPER_DEEP": "#0A101F",
    "SUBTLE": "#1D2A47",
    "NAVY": "#F2EDE0",
    "NAVY_DEEP": "#FBF8F1",
    "INK": "#EEE9DD",
    "MUTED": "#9DAAC1",
    "HAIRLINE": "#283758",
    "BORDER": "#384B71",
    "BRASS": "#CFAF6D",
    "BRASS_SOFT": "#2E2B22",
    "BRASS_TEXT": "#CFAF6D",
    "CHROME": "#131D34",
    "ACCENT": "#679CF0",
    "ACCENT_SOFT": "#19294A",
    "CORRECT": "#7AC48F",
    "CORRECT_SOFT": "#162E25",
    "WRONG": "#E88484",
    "WRONG_SOFT": "#341919",
    "ON_BRAND": "#0E1629",
    "BRAND_FILL": "#E6E0CF",
}

THEMES = {"light": LIGHT, "dark": DARK}
_current = "light"
_chosen = "light"

PAPER_DAY = {
    "PAPER": "#F4F0E8",
    "CARD": "#FDFBF6",
    "PAPER_DEEP": "#ECE6DA",
    "SUBTLE": "#F1EDE5",
    "NAVY": "#1B2A4A",
    "NAVY_DEEP": "#121E37",
    "INK": "#1B2A4A",
    "MUTED": "#666F86",
    "HAIRLINE": "#DAD2C3",
    "BORDER": "#C9BFAC",
    "BRASS": "#A98A51",
    "BRASS_SOFT": "#E9E0CD",
    "BRASS_TEXT": "#7D6230",
    "CANVAS": "#FFFFFF",
    "CHROME": "#F9F8F5",
    "ACCENT": "#175AC9",
    "ACCENT_SOFT": "#EDF2FF",
    "ACCENT_FILL": "#175AC9",
    "ACCENT_FILL_DEEP": "#121E37",
    "CORRECT": "#215A38",
    "CORRECT_SOFT": "#E6F0E6",
    "WRONG": "#832727",
    "WRONG_SOFT": "#F6EAE7",
    "ON_BRAND": "#FDFBF6",
    "BRAND_FILL": "#1B2A4A",
}

PAPER_NIGHT = {
    "PAPER": "#111317",
    "CARD": "#16181D",
    "PAPER_DEEP": "#08090B",
    "SUBTLE": "#212329",
    "NAVY": "#E0E2E7",
    "NAVY_DEEP": "#F2F3F6",
    "INK": "#E0E2E7",
    "MUTED": "#9298A4",
    "HAIRLINE": "#292B32",
    "BORDER": "#3C3F49",
    "BRASS": "#B49660",
    "BRASS_SOFT": "#2F281C",
    "BRASS_TEXT": "#B49660",
    "CANVAS": "#0B0D10",
    "CHROME": "#131519",
    "ACCENT": "#6F98DB",
    "ACCENT_SOFT": "#1B253C",
    "ACCENT_FILL": "#28436D",
    "ACCENT_FILL_DEEP": "#37588B",
    "CORRECT": "#73BA88",
    "CORRECT_SOFT": "#13281C",
    "WRONG": "#DA7B7B",
    "WRONG_SOFT": "#321616",
    "ON_BRAND": "#EAEDF2",
    "BRAND_FILL": "#253760",
}

HIGHLIGHTS_DAY = ["#FFEE8C", "#B8E8B8", "#B8DBFA", "#FCC7D6"]
HIGHLIGHTS_NIGHT = ["#4B3E0B", "#1B4521", "#143D5C", "#52212F"]

_stealth = False


def stealth_on() -> bool:
    return _stealth


_THEMED_MODULES = ("satprep.home", "satprep.stats", "satprep.decks",
                   "satprep.learn", "satprep.parent", "satprep.settings",
                   "satprep.promo", "satprep.chrome")
_PAPER_MODULES = ("satprep.ui", "satprep.reference", "satprep.double")


def _rebind(module_name: str, values: dict, night: bool) -> None:
    import sys
    module = sys.modules.get(module_name)
    if module is None:
        return
    for key, value in values.items():
        if hasattr(module, key):
            setattr(module, key, value)
    if hasattr(module, "HIGHLIGHTS"):
        module.HIGHLIGHTS = list(HIGHLIGHTS_NIGHT if night else HIGHLIGHTS_DAY)
    if hasattr(module, "rebuild_derived"):
        module.rebuild_derived()


def refresh_palettes() -> None:
    day = dict(PAPER_DAY)
    day.update(THEMES[_current])
    for name in _THEMED_MODULES:
        _rebind(name, PAPER_NIGHT if _stealth else day, _stealth)
    for name in _PAPER_MODULES:
        _rebind(name, PAPER_NIGHT if _stealth else PAPER_DAY, _stealth)


def live_palette(paper: bool = False) -> dict:
    if _stealth:
        return PAPER_NIGHT
    return PAPER_DAY if paper else THEMES[_current]


def menu_style() -> str:
    p = live_palette()
    return f"""
QMenu {{
    background: {p["CARD"]};
    color: {p["INK"]};
    border: 1px solid {p["BORDER"]};
    border-radius: 4px;
    padding: 4px;
    font-size: 12px;
}}
QMenu::item {{
    background: transparent;
    padding: 5px 22px 5px 12px;
    border-radius: 3px;
}}
QMenu::item:selected {{ background: {p["SUBTLE"]}; color: {p["NAVY_DEEP"]}; }}
QMenu::item:disabled {{ color: {p["MUTED"]}; }}
QMenu::separator {{
    height: 1px;
    background: {p["HAIRLINE"]};
    margin: 4px 8px;
}}
QMenu::icon {{ padding-left: 8px; }}
"""


def dress_menu(menu) -> None:
    menu.setStyleSheet(menu_style())


def adopt(module_name: str) -> None:
    if module_name in _PAPER_MODULES:
        _rebind(module_name, PAPER_NIGHT if _stealth else PAPER_DAY, _stealth)
    else:
        _rebind(module_name, PAPER_NIGHT if _stealth else THEMES[_current], _stealth)


def _q(value):
    return QtGui.QColor(value)


def qt_palette() -> QtGui.QPalette:
    c = PAPER_NIGHT if _stealth else THEMES[_current]
    role = QtGui.QPalette.ColorRole
    group = QtGui.QPalette.ColorGroup

    p = QtGui.QPalette()
    p.setColor(role.Window, _q(c["PAPER"]))
    p.setColor(role.WindowText, _q(c["INK"]))
    p.setColor(role.Base, _q(c["CARD"]))
    p.setColor(role.AlternateBase, _q(c["SUBTLE"]))
    p.setColor(role.Text, _q(c["INK"]))
    p.setColor(role.Button, _q(c["CARD"]))
    p.setColor(role.ButtonText, _q(c["INK"]))
    p.setColor(role.BrightText, _q(c["WRONG"]))
    p.setColor(role.ToolTipBase, _q(c["CARD"]))
    p.setColor(role.ToolTipText, _q(c["INK"]))
    p.setColor(role.PlaceholderText, _q(c["MUTED"]))
    p.setColor(role.Link, _q(c["ACCENT"]))
    p.setColor(role.LinkVisited, _q(c["BRASS"]))
    p.setColor(role.Highlight, _q(c["ACCENT"]))
    p.setColor(role.HighlightedText, _q(c["ON_BRAND"]))
    p.setColor(role.Light, _q(c["CARD"]))
    p.setColor(role.Midlight, _q(c["SUBTLE"]))
    p.setColor(role.Mid, _q(c["HAIRLINE"]))
    p.setColor(role.Dark, _q(c["BORDER"]))
    p.setColor(role.Shadow, _q(c["BORDER"]))

    for r in (role.WindowText, role.Text, role.ButtonText):
        p.setColor(group.Disabled, r, _q(c["MUTED"]))
    p.setColor(group.Disabled, role.Base, _q(c["PAPER"]))
    p.setColor(group.Disabled, role.Button, _q(c["PAPER"]))
    p.setColor(group.Disabled, role.Highlight, _q(c["HAIRLINE"]))
    p.setColor(group.Disabled, role.HighlightedText, _q(c["MUTED"]))
    return p


def apply_qt_palette() -> None:
    app = QtWidgets.QApplication.instance()
    if app is None:
        return
    app.setPalette(qt_palette())
    try:
        scheme = (QtCore.Qt.ColorScheme.Dark
                  if (_stealth or _current == "dark")
                  else QtCore.Qt.ColorScheme.Light)
        QtGui.QGuiApplication.styleHints().setColorScheme(scheme)
    except (AttributeError, TypeError):
        pass


def apply_stealth(on: bool) -> None:
    global _stealth
    _stealth = bool(on)
    refresh_palettes()
    apply_qt_palette()


_motion_reduced = False


INTRO_BACKDROP = "#0E1629"
INTRO_BACKDROP_NIGHT = "#0B0C0E"
INTRO_SEAL = "#F4F0E8"


def stealth_on() -> bool:
    return _stealth


def motion_on() -> bool:
    return not _motion_reduced and not os.environ.get("SATPREP_NO_ANIMATION")


def system_reduces_motion() -> bool:
    import sys
    if sys.platform == "win32":
        try:
            import ctypes
            enabled = ctypes.c_int(1)
            SPI_GETCLIENTAREAANIMATION = 0x1042
            if ctypes.windll.user32.SystemParametersInfoW(
                    SPI_GETCLIENTAREAANIMATION, 0, ctypes.byref(enabled), 0):
                return not bool(enabled.value)
        except Exception:
            return False
        return False
    if sys.platform == "darwin":
        try:
            import subprocess
            out = subprocess.run(["defaults", "read", "com.apple.universalaccess", "reduceMotion"],
                                 capture_output=True, text=True, timeout=2).stdout.strip()
            return out == "1"
        except Exception:
            return False
    return False


def apply_motion(reduced: bool) -> None:
    import sys
    global _motion_reduced
    _motion_reduced = bool(reduced) or system_reduces_motion()
    on = motion_on()
    for name in ("satprep.home", "satprep.decks"):
        module = sys.modules.get(name)
        if module is not None and hasattr(module, "ANIMATIONS_ON"):
            module.ANIMATIONS_ON = on


def paper_colour(key: str) -> str:
    table = PAPER_NIGHT if _stealth else PAPER_DAY
    return table.get(key, PAPER_DAY.get(key, "#000000"))


def system_theme() -> str:
    try:
        from PySide6 import QtGui as _QtGui
        hints = _QtGui.QGuiApplication.styleHints()
        scheme = hints.colorScheme() if hints is not None else None
        if scheme == QtCore.Qt.ColorScheme.Dark:
            return "dark"
        if scheme == QtCore.Qt.ColorScheme.Light:
            return "light"
    except Exception:
        pass
    try:
        import winreg
        key = winreg.OpenKey(
            winreg.HKEY_CURRENT_USER,
            r"Software\Microsoft\Windows\CurrentVersion\Themes\Personalize")
        with key:
            light, _ = winreg.QueryValueEx(key, "AppsUseLightTheme")
        return "light" if light else "dark"
    except Exception:
        return "light"


def chosen_theme() -> str:
    return _chosen


def current_theme() -> str:
    return _current


def apply_theme(name: str) -> None:
    global _current, _chosen
    _chosen = name if name in THEMES or name == "system" else "light"
    _current = system_theme() if _chosen == "system" else _chosen
    refresh_palettes()
    apply_qt_palette()


def colour(key: str) -> str:
    return THEMES[_current].get(key, LIGHT.get(key, "#000000"))


INK_ON_LIGHT = "#171C29"
INK_ON_DARK = "#FAFAF7"


def readable_ink(background: str) -> str:
    c = QtGui.QColor(background)
    if not c.isValid():
        return INK_ON_DARK

    def linear(v: float) -> float:
        return v / 12.92 if v <= 0.03928 else ((v + 0.055) / 1.055) ** 2.4

    luminance = (0.2126 * linear(c.redF())
                 + 0.7152 * linear(c.greenF())
                 + 0.0722 * linear(c.blueF()))
    return INK_ON_LIGHT if luminance > 0.55 else INK_ON_DARK


_ASSETS = os.path.join(os.path.dirname(os.path.abspath(__file__)), "assets")
_cache = {}


def artwork(name):
    if name not in _cache:
        path = os.path.join(_ASSETS, name + ".png")
        pixmap = QtGui.QPixmap(path)
        _cache[name] = None if pixmap.isNull() else pixmap
    return _cache[name]


def paint_artwork(painter, rect, pixmap, ink):
    scaled = pixmap.scaled(int(rect.width()), int(rect.height()),
                           QtCore.Qt.KeepAspectRatio, QtCore.Qt.SmoothTransformation)
    tinted = QtGui.QPixmap(scaled.size())
    tinted.fill(QtCore.Qt.transparent)
    p = QtGui.QPainter(tinted)
    p.drawPixmap(0, 0, scaled)
    p.setCompositionMode(QtGui.QPainter.CompositionMode_SourceIn)
    p.fillRect(tinted.rect(), QtGui.QColor(ink))
    p.end()
    x = rect.x() + (rect.width() - scaled.width()) / 2
    y = rect.y() + (rect.height() - scaled.height()) / 2
    painter.drawPixmap(QtCore.QPointF(x, y), tinted)


def _on_ring(cx, cy, radius, degrees):
    r = math.radians(degrees)
    return QtCore.QPointF(cx + math.cos(r) * radius, cy + math.sin(r) * radius)


def paint_seal(painter: QtGui.QPainter, rect: QtCore.QRectF, ink: QtGui.QColor):
    art = artwork("usufu-seal")
    if art is not None and min(rect.width(), rect.height()) >= 44:
        painter.save()
        painter.setRenderHint(QtGui.QPainter.SmoothPixmapTransform, True)
        paint_artwork(painter, rect, art, ink)
        painter.restore()
        return

    s = min(rect.width(), rect.height())
    cx, cy = rect.center().x(), rect.center().y()
    full = s >= 108
    crest = s >= 40
    line = max(0.7, s * 0.0062)

    painter.save()
    painter.setRenderHint(QtGui.QPainter.Antialiasing, True)
    painter.setBrush(QtCore.Qt.NoBrush)

    rings = [0.487, 0.462, 0.352, 0.336] if full else [0.487, 0.455]
    for r in rings:
        heavy = r in (0.462, 0.352, 0.455)
        painter.setPen(QtGui.QPen(ink, line * (1.9 if heavy else 1.0)))
        painter.drawEllipse(QtCore.QPointF(cx, cy), s * r, s * r)

    if full:
        _arc_text(painter, ORGANISATION.upper(), cx, cy, s * 0.404, 270, 212,
                  s * 0.054, ink, upright=True, weight=QtGui.QFont.DemiBold)
        _arc_text(painter, ESTABLISHED, cx, cy, s * 0.392, 90, 46,
                  s * 0.061, ink, upright=False, weight=QtGui.QFont.Bold)

    field = 1.0 if full else 1.34
    if crest:
        _wreath(painter, cx, cy, s, field, line, ink)
    _book(painter, cx, cy, s, field if crest else 1.7, line, ink, ruled=crest)
    painter.restore()


def _arc_text(painter, text, cx, cy, radius, centred_on, sweep, size, ink,
              upright, weight):
    characters = [c for c in text]
    if len(characters) < 2:
        return
    font = QtGui.QFont("Georgia", int(round(size)))
    font.setStyleHint(QtGui.QFont.Serif)
    font.setWeight(weight)
    font.setPixelSize(max(1, int(round(size))))
    painter.setFont(font)
    painter.setPen(QtGui.QPen(ink))
    metrics = QtGui.QFontMetricsF(font)
    step = sweep / (len(characters) - 1)

    for i, character in enumerate(characters):
        if character == " ":
            continue
        degrees = (centred_on - sweep / 2 + step * i) if upright \
            else (centred_on + sweep / 2 - step * i)
        point = _on_ring(cx, cy, radius, degrees)
        painter.save()
        painter.translate(point)
        painter.rotate(degrees + (90 if upright else -90))
        width = metrics.horizontalAdvance(character)
        painter.drawText(QtCore.QPointF(-width / 2, metrics.capHeight() / 2), character)
        painter.restore()


def _wreath(painter, cx, cy, s, field, line, ink):
    for mirrored in (False, True):
        painter.save()
        if mirrored:
            painter.translate(cx, cy)
            painter.scale(-1, 1)
            painter.translate(-cx, -cy)
        _branch(painter, cx, cy, s, field, line, ink)
        painter.restore()


def _branch(painter, cx, cy, s, field, line, ink):
    start, end = -66.0, 86.0
    stem_radius = s * 0.238 * field

    path = QtGui.QPainterPath()
    for i in range(57):
        point = _on_ring(cx, cy, stem_radius, start + (end - start) * i / 56)
        path.moveTo(point) if i == 0 else path.lineTo(point)
    painter.setPen(QtGui.QPen(ink, line * 1.5, QtCore.Qt.SolidLine,
                              QtCore.Qt.RoundCap))
    painter.drawPath(path)

    painter.setPen(QtGui.QPen(ink, line))
    for i in range(9):
        t = i / 8
        degrees = start + (end - start) * t
        length = s * (0.052 + 0.042 * t) * field
        width = length * 0.44
        anchor = _on_ring(cx, cy, stem_radius, degrees)
        for outward in (True, False):
            axis = (degrees if outward else degrees + 180) - 34
            span = length * (1.0 if outward else 0.78)
            offset = _on_ring(0, 0, span * 0.52, axis)
            painter.save()
            painter.translate(anchor.x() + offset.x(), anchor.y() + offset.y())
            painter.rotate(axis)
            painter.drawEllipse(QtCore.QPointF(0, 0), span / 2, width / 2)
            painter.restore()


def _book(painter, cx, cy, s, field, line, ink, ruled):
    half = s * 0.150 * field
    height = s * 0.128 * field
    gutter = s * 0.010 * field
    spine_top = cy - height * 0.62
    spine_foot = cy + height * 0.86
    leaf_top = cy - height * 0.82
    leaf_foot = cy + height * 0.66

    for side in (-1.0, 1.0):
        outer = cx + side * half
        inner = cx + side * gutter

        page = QtGui.QPainterPath()
        page.moveTo(inner, spine_top)
        page.quadTo(cx + side * half * 0.52, spine_top - height * 0.10,
                    outer, leaf_top)
        page.lineTo(outer, leaf_foot)
        page.quadTo(cx + side * half * 0.52, spine_foot - height * 0.02,
                    inner, spine_foot)
        page.closeSubpath()
        painter.setPen(QtGui.QPen(ink, line * 1.6, QtCore.Qt.SolidLine,
                                  QtCore.Qt.RoundCap, QtCore.Qt.RoundJoin))
        painter.drawPath(page)

        thickness = s * 0.015 * field
        edge = QtGui.QPainterPath()
        edge.moveTo(outer, leaf_top)
        edge.lineTo(outer + side * thickness, leaf_top + height * 0.14)
        edge.lineTo(outer + side * thickness, leaf_foot + height * 0.12)
        edge.lineTo(outer, leaf_foot)
        painter.setPen(QtGui.QPen(ink, line))
        painter.drawPath(edge)

        if ruled:
            painter.setPen(QtGui.QPen(ink, line * 0.85))
            for n in range(3):
                y = leaf_top + height * (0.42 + 0.34 * n)
                inset = half * (0.16 + 0.05 * n)
                painter.drawLine(QtCore.QPointF(inner + side * half * 0.16, y),
                                 QtCore.QPointF(outer - side * inset, y))

    painter.setPen(QtGui.QPen(ink, line * 1.6))
    painter.drawLine(QtCore.QPointF(cx, spine_top), QtCore.QPointF(cx, spine_foot))
    painter.setPen(QtGui.QPen(ink, line * 1.2))
    painter.drawRect(QtCore.QRectF(cx - s * 0.020 * field, spine_foot,
                                   s * 0.040 * field, s * 0.024 * field))


def icon(name: str, size: int, ink: str, gap: int = 0) -> QtGui.QIcon:
    scale = 2
    pixmap = QtGui.QPixmap((size + gap) * scale, size * scale)
    pixmap.fill(QtCore.Qt.transparent)
    painter = QtGui.QPainter(pixmap)
    painter.setRenderHint(QtGui.QPainter.TextAntialiasing)
    font = QtGui.QFont(ICON_FONT)
    font.setPixelSize(size * scale)
    painter.setFont(font)
    painter.setPen(QtGui.QColor(ink))
    painter.drawText(QtCore.QRectF(0, 0, size * scale, size * scale),
                     QtCore.Qt.AlignCenter, ICONS.get(name, ""))
    painter.end()
    pixmap.setDevicePixelRatio(scale)
    return QtGui.QIcon(pixmap)


_MARK_CACHE = {}
_MARK_DIR = None


def _mark_dir():
    global _MARK_DIR
    if _MARK_DIR is None:
        import tempfile
        _MARK_DIR = os.path.join(tempfile.gettempdir(), "usufu-sat-marks")
        os.makedirs(_MARK_DIR, exist_ok=True)
    return _MARK_DIR


def _draw_mark(kind, on, size, scale, fill, on_fill, ground, edge):
    image = QtGui.QImage(size * scale, size * scale,
                         QtGui.QImage.Format_ARGB32_Premultiplied)
    image.fill(QtCore.Qt.transparent)
    p = QtGui.QPainter(image)
    p.setRenderHint(QtGui.QPainter.Antialiasing, True)
    s = size * scale
    inset = 1.0 * scale
    box = QtCore.QRectF(inset, inset, s - 2 * inset, s - 2 * inset)

    if kind == "radio":
        p.setBrush(QtGui.QColor(ground))
        p.setPen(QtGui.QPen(QtGui.QColor(fill if on else edge),
                            (1.4 if on else 1.1) * scale))
        p.drawEllipse(box)
        if on:
            p.setPen(QtCore.Qt.NoPen)
            p.setBrush(QtGui.QColor(fill))
            dot = box.adjusted(box.width() * 0.28, box.height() * 0.28,
                               -box.width() * 0.28, -box.height() * 0.28)
            p.drawEllipse(dot)
    else:
        radius = 2.4 * scale
        if on:
            p.setPen(QtGui.QPen(QtGui.QColor(fill), 1.0 * scale))
            p.setBrush(QtGui.QColor(fill))
            p.drawRoundedRect(box, radius, radius)
            pen = QtGui.QPen(QtGui.QColor(on_fill), 1.7 * scale)
            pen.setCapStyle(QtCore.Qt.RoundCap)
            pen.setJoinStyle(QtCore.Qt.RoundJoin)
            p.setPen(pen)
            p.setBrush(QtCore.Qt.NoBrush)
            path = QtGui.QPainterPath()
            path.moveTo(box.left() + box.width() * 0.24,
                        box.top() + box.height() * 0.52)
            path.lineTo(box.left() + box.width() * 0.43,
                        box.top() + box.height() * 0.71)
            path.lineTo(box.left() + box.width() * 0.77,
                        box.top() + box.height() * 0.30)
            p.drawPath(path)
        else:
            p.setPen(QtGui.QPen(QtGui.QColor(edge), 1.1 * scale))
            p.setBrush(QtGui.QColor(ground))
            p.drawRoundedRect(box, radius, radius)
    p.end()
    return image


def mark_image(kind, on, fill, on_fill, ground, edge, size=15):
    key = (kind, bool(on), fill, on_fill, ground, edge, size)
    hit = _MARK_CACHE.get(key)
    if hit:
        return hit
    import hashlib
    stamp = hashlib.md5(repr(key).encode("utf-8")).hexdigest()[:12]
    path = os.path.join(_mark_dir(), "%s-%s.png" % (kind, stamp))
    if not os.path.exists(path):
        _draw_mark(kind, on, size, 1, fill, on_fill, ground, edge).save(path)
        _draw_mark(kind, on, size, 2, fill, on_fill, ground, edge).save(
            path.replace(".png", "@2x.png"))
    _MARK_CACHE[key] = path
    return path


def _url(path):
    return path.replace("\\", "/")


def control_style(kind, fill, on_fill, ground, edge, muted=None, size=15):
    muted = muted or edge
    name = "QCheckBox" if kind == "check" else "QRadioButton"
    on = _url(mark_image(kind, True, fill, on_fill, ground, edge, size))
    off = _url(mark_image(kind, False, fill, on_fill, ground, edge, size))
    off_dim = _url(mark_image(kind, False, muted, ground, ground, muted, size))
    on_dim = _url(mark_image(kind, True, muted, ground, ground, muted, size))
    return (
        f"{name}::indicator{{width:{size}px; height:{size}px;}}"
        f"{name}::indicator:unchecked{{image:url({off});}}"
        f"{name}::indicator:checked{{image:url({on});}}"
        f"{name}::indicator:unchecked:disabled{{image:url({off_dim});}}"
        f"{name}::indicator:checked:disabled{{image:url({on_dim});}}"
        f"{name}{{spacing:8px;}}")


_last_folder = None


def dialog_path(name="", opening=False):
    folder = _last_folder
    if not folder or not os.path.isdir(folder):
        where = (QtCore.QStandardPaths.DownloadLocation if opening
                 else QtCore.QStandardPaths.DocumentsLocation)
        folder = (QtCore.QStandardPaths.writableLocation(where)
                  or os.path.expanduser("~"))
    return os.path.join(folder, name) if name else folder


def remember_folder(path):
    global _last_folder
    if isinstance(path, (list, tuple)):
        path = path[0] if path else None
    _last_folder = os.path.dirname(path) if path else None


def alert(parent, title, body):
    from html import escape

    def marked(text):
        return escape(str(text)).replace(chr(10), "<br>")

    box = QtWidgets.QMessageBox(parent)
    box.setWindowTitle(title)
    box.setTextFormat(QtCore.Qt.RichText)
    box.setText(
        f"<div style='font-size:13px; font-weight:600'>{marked(title)}</div>"
        f"<div style='margin-top:7px'>{marked(body)}</div>")
    box.setIcon(QtWidgets.QMessageBox.NoIcon)
    box.setIconPixmap(seal_icon(44).pixmap(44, 44))
    as_sheet(box, parent)
    return box


def ask(parent, title, body, accept=None, destructive=False) -> bool:
    box = alert(parent, title, body)
    yes = box.addButton(accept or L("OK"), QtWidgets.QMessageBox.AcceptRole)
    no = box.addButton(L("Cancel"), QtWidgets.QMessageBox.RejectRole)
    box.setDefaultButton(no if destructive else yes)
    box.setEscapeButton(no)
    box.exec()
    return box.clickedButton() is yes


def tell(parent, title, body, detail=None):
    box = alert(parent, title, body)
    if detail:
        box.setDetailedText(detail)
    box.addButton(L("OK"), QtWidgets.QMessageBox.AcceptRole)
    box.exec()


def _luminance(hex_colour: str) -> float:
    h = hex_colour.lstrip("#")
    c = [int(h[i:i + 2], 16) / 255 for i in (0, 2, 4)]
    c = [v / 12.92 if v <= 0.03928 else ((v + 0.055) / 1.055) ** 2.4 for v in c]
    return 0.2126 * c[0] + 0.7152 * c[1] + 0.0722 * c[2]


def contrast_ratio(a: str, b: str) -> float:
    la, lb = _luminance(a), _luminance(b)
    return (max(la, lb) + 0.05) / (min(la, lb) + 0.05)


def legible_on(colour: str, grounds, minimum: float = 3.0) -> str:
    grounds = [g for g in grounds if g]
    if not grounds or all(contrast_ratio(colour, g) >= minimum for g in grounds):
        return colour
    toward = (255, 255, 255) if sum(_luminance(g) for g in grounds) / len(grounds) < 0.4 else (0, 0, 0)
    base = [int(colour.lstrip("#")[i:i + 2], 16) for i in (0, 2, 4)]
    for step in range(1, 26):
        mix = "#%02X%02X%02X" % tuple(round(c + (t - c) * step * 0.04) for c, t in zip(base, toward))
        if all(contrast_ratio(mix, g) >= minimum for g in grounds):
            return mix
    return "#%02X%02X%02X" % toward


def on_fill(fill: str) -> str:
    return "#FFFFFF" if contrast_ratio("#FFFFFF", fill) >= 3.0 else "#14171C"


def failure_hint(error):
    import errno
    code = getattr(error, "errno", None)
    if isinstance(error, PermissionError) or code in (errno.EACCES, errno.EPERM, errno.EROFS):
        return L("Check that the folder is not read-only, or choose another one.")
    if code == errno.ENOSPC:
        return L("The disk is full. Free some space, or choose another place.")
    return L("Check that the folder exists, or choose another one.")


def warn(parent, title, body, detail=None):
    tell(parent, title, body, detail=detail)


def pin_over_column(layout, area, left=32, top=12, right=32, bottom=12):
    bar = area.verticalScrollBar()

    def fit():
        if not (shiboken6.isValid(layout) and shiboken6.isValid(bar)):
            return
        extra = bar.width() if bar.isVisible() else 0
        layout.setContentsMargins(left, top, right + extra, bottom)

    bar.rangeChanged.connect(lambda *_: QtCore.QTimer.singleShot(0, fit))
    fit()


class IconButton(QtWidgets.QPushButton):

    def __init__(self, name, text, ink, hover=None, size=11, parent=None):
        super().__init__(text, parent)
        self._name = name
        self._size = size
        self._ink = ink
        self._hover = hover or ink
        self._gap = 5 if text else 0
        self._paint(ink)
        self.setCursor(QtCore.Qt.PointingHandCursor)

    def _paint(self, colour):
        self.setIcon(icon(self._name, self._size, colour, gap=self._gap))
        self.setIconSize(QtCore.QSize(self._size + self._gap, self._size))

    def enterEvent(self, event):
        self._paint(self._hover)
        super().enterEvent(event)

    def leaveEvent(self, event):
        self._paint(self._ink)
        super().leaveEvent(event)

    def set_ink(self, ink, hover=None):
        self._ink = ink
        self._hover = hover or ink
        self._paint(ink)


class Seal(QtWidgets.QWidget):

    def __init__(self, size=46, ink="#1B2A4A", parent=None):
        super().__init__(parent)
        self._ink = QtGui.QColor(ink)
        self._blank = False
        self.setFixedSize(size, size)
        self.setAttribute(QtCore.Qt.WA_TransparentForMouseEvents)

    def set_ink(self, ink):
        self._ink = QtGui.QColor(ink)
        self.update()

    def ink(self):
        return QtGui.QColor(self._ink)

    def set_blank(self, blank):
        self._blank = bool(blank)
        self.update()

    def paintEvent(self, event):
        if self._blank:
            return
        painter = QtGui.QPainter(self)
        paint_seal(painter, QtCore.QRectF(self.rect()), self._ink)
        painter.end()


def screen_at(widget):
    window = widget.window() if widget is not None else None
    if window is not None:
        found = QtGui.QGuiApplication.screenAt(window.frameGeometry().center())
        if found is not None:
            return found
    return QtGui.QGuiApplication.primaryScreen()


def as_sheet(dialog, parent=None, dim=True):
    dialog.setWindowFlags(QtCore.Qt.Dialog
                          | QtCore.Qt.FramelessWindowHint
                          | QtCore.Qt.NoDropShadowWindowHint)
    dialog.setAttribute(QtCore.Qt.WA_TranslucentBackground, False)

    scrim = None
    if dim and parent is not None:
        window = parent.window()
        if window is not None:
            scrim = QtWidgets.QWidget(window)
            scrim.setObjectName("sheetScrim")
            scrim.setAttribute(QtCore.Qt.WA_StyledBackground, True)
            scrim.setStyleSheet(
                "QWidget#sheetScrim{background:rgba(0,0,0,110);}")
            scrim.setGeometry(window.rect())
            scrim.show()
            scrim.raise_()

    def centre():
        window = parent.window() if parent is not None else None
        if window is None:
            return
        if scrim is not None and shiboken6.isValid(scrim):
            scrim.setGeometry(window.rect())
            scrim.raise_()
            scrim.show()
        here = dialog.frameGeometry()
        here.moveCenter(window.frameGeometry().center())
        screen = screen_at(window)
        if screen is not None:
            room = screen.availableGeometry()
            if here.height() > room.height():
                here.setHeight(room.height())
                dialog.resize(here.width(), room.height())
            if here.width() > room.width():
                here.setWidth(room.width())
                dialog.resize(room.width(), here.height())
            if here.bottom() > room.bottom():
                here.moveBottom(room.bottom())
            if here.top() < room.top():
                here.moveTop(room.top())
            if here.right() > room.right():
                here.moveRight(room.right())
            if here.left() < room.left():
                here.moveLeft(room.left())
        dialog.move(here.topLeft())

    QtCore.QTimer.singleShot(0, centre)
    dialog.recentre = centre

    finished = dialog.finished

    def clear(_=0):
        if scrim is not None and shiboken6.isValid(scrim):
            scrim.deleteLater()

    finished.connect(clear)
    return dialog


class Wordmark(QtWidgets.QWidget):

    def __init__(self, width=340, ink=None, parent=None):
        super().__init__(parent)
        self._art = artwork("usufu-wordmark")
        self._ink = QtGui.QColor(ink or colour("NAVY"))
        self._width = width
        if self._art is not None and self._art.width():
            ratio = self._art.height() / self._art.width()
            self.setFixedSize(width, max(1, round(width * ratio)))
        else:
            self.setFixedSize(width, 0)
        self.setAttribute(QtCore.Qt.WA_TransparentForMouseEvents)

    def has_art(self):
        return self._art is not None

    def set_ink(self, ink):
        self._ink = QtGui.QColor(ink)
        self.update()

    def paintEvent(self, event):
        if self._art is None:
            return
        painter = QtGui.QPainter(self)
        painter.setRenderHint(QtGui.QPainter.SmoothPixmapTransform, True)
        paint_artwork(painter, QtCore.QRectF(self.rect()), self._art, self._ink)
        painter.end()


def seal_icon(size: int, ink: str = "#F4F0E8", ground: str = "#1B2A4A") -> QtGui.QIcon:
    pixmap = QtGui.QPixmap(size, size)
    pixmap.fill(QtCore.Qt.transparent)
    painter = QtGui.QPainter(pixmap)
    painter.setRenderHint(QtGui.QPainter.Antialiasing, True)
    painter.setBrush(QtGui.QColor(ground))
    painter.setPen(QtCore.Qt.NoPen)
    inset = size * 0.06
    painter.drawRoundedRect(QtCore.QRectF(inset, inset, size - inset * 2,
                                          size - inset * 2),
                            size * 0.22, size * 0.22)
    margin = size * 0.13
    paint_seal(painter, QtCore.QRectF(margin, margin, size - margin * 2,
                                      size - margin * 2), QtGui.QColor(ink))
    painter.end()
    return QtGui.QIcon(pixmap)
