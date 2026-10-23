from __future__ import annotations

import sys

from PySide6 import QtCore, QtGui, QtWidgets

from . import brand
from .i18n import L
from .ui import CHROME, HAIRLINE, INK, MUTED, NAVY, SUBTLE, WRONG

GRIP = 8
BAR_HEIGHT = 38

GLYPH_MIN = chr(0xE921)
GLYPH_MAX = chr(0xE922)
GLYPH_RESTORE = chr(0xE923)
GLYPH_CLOSE = chr(0xE8BB)


def supported():
    return sys.platform == "win32"


def restore_sizing_frame(window):
    if not supported():
        return False
    try:
        import ctypes
        GWL_STYLE = -16
        WS_CAPTION = 0x00C00000
        WS_THICKFRAME = 0x00040000
        WS_MAXIMIZEBOX = 0x00010000
        WS_MINIMIZEBOX = 0x00020000
        user32 = ctypes.windll.user32
        hwnd = int(window.winId())
        get = getattr(user32, "GetWindowLongPtrW", user32.GetWindowLongW)
        put = getattr(user32, "SetWindowLongPtrW", user32.SetWindowLongW)
        get.restype = ctypes.c_ssize_t
        put.restype = ctypes.c_ssize_t
        put.argtypes = [ctypes.c_void_p, ctypes.c_int, ctypes.c_ssize_t]
        style = get(ctypes.c_void_p(hwnd), GWL_STYLE)
        put(ctypes.c_void_p(hwnd), GWL_STYLE,
            style | WS_CAPTION | WS_THICKFRAME | WS_MAXIMIZEBOX | WS_MINIMIZEBOX)
        SWP = 0x0002 | 0x0001 | 0x0004 | 0x0020
        user32.SetWindowPos(ctypes.c_void_p(hwnd), None, 0, 0, 0, 0, SWP)
        return True
    except Exception:
        return False


def maximised_client(window, work):
    return (max(window[0], work[0]), max(window[1], work[1]),
            min(window[2], work[2]), min(window[3], work[3]))


def work_area(hwnd):
    try:
        import ctypes
        import ctypes.wintypes as wt

        class MONITORINFO(ctypes.Structure):
            _fields_ = [("cbSize", wt.DWORD), ("rcMonitor", wt.RECT),
                        ("rcWork", wt.RECT), ("dwFlags", wt.DWORD)]

        user32 = ctypes.windll.user32
        user32.MonitorFromWindow.restype = ctypes.c_void_p
        info = MONITORINFO()
        info.cbSize = ctypes.sizeof(MONITORINFO)
        monitor = user32.MonitorFromWindow(ctypes.c_void_p(hwnd), 2)
        if not user32.GetMonitorInfoW(ctypes.c_void_p(monitor), ctypes.byref(info)):
            return None
        w = info.rcWork
        return (w.left, w.top, w.right, w.bottom)
    except Exception:
        return None


def frame_overhang(hwnd):
    try:
        import ctypes
        import ctypes.wintypes as wt
        user32 = ctypes.windll.user32
        h = ctypes.c_void_p(hwnd)
        style = user32.GetWindowLongW(h, -16)
        ex_style = user32.GetWindowLongW(h, -20)
        rect = wt.RECT(0, 0, 0, 0)
        if not user32.AdjustWindowRectExForDpi(ctypes.byref(rect), style & 0xFFFFFFFF, False,
                                               ex_style & 0xFFFFFFFF, user32.GetDpiForWindow(h)):
            return 0
        return max(0, -rect.left)
    except Exception:
        return 0


def fill_minmax(hwnd, lparam, least):
    try:
        import ctypes
        import ctypes.wintypes as wt

        class MINMAXINFO(ctypes.Structure):
            _fields_ = [("ptReserved", wt.POINT), ("ptMaxSize", wt.POINT),
                        ("ptMaxPosition", wt.POINT), ("ptMinTrackSize", wt.POINT),
                        ("ptMaxTrackSize", wt.POINT)]

        class MONITORINFO(ctypes.Structure):
            _fields_ = [("cbSize", wt.DWORD), ("rcMonitor", wt.RECT),
                        ("rcWork", wt.RECT), ("dwFlags", wt.DWORD)]

        user32 = ctypes.windll.user32
        user32.MonitorFromWindow.restype = ctypes.c_void_p
        info = MONITORINFO()
        info.cbSize = ctypes.sizeof(MONITORINFO)
        monitor = user32.MonitorFromWindow(ctypes.c_void_p(hwnd), 2)
        if not lparam or not user32.GetMonitorInfoW(ctypes.c_void_p(monitor), ctypes.byref(info)):
            return False
        work, screen = info.rcWork, info.rcMonitor
        over = frame_overhang(hwnd)
        mmi = MINMAXINFO.from_address(int(lparam))
        mmi.ptMaxPosition.x = work.left - screen.left - over
        mmi.ptMaxPosition.y = work.top - screen.top - over
        mmi.ptMaxSize.x = (work.right - work.left) + 2 * over
        mmi.ptMaxSize.y = (work.bottom - work.top) + 2 * over
        mmi.ptMinTrackSize.x = max(mmi.ptMinTrackSize.x, int(least[0]))
        mmi.ptMinTrackSize.y = max(mmi.ptMinTrackSize.y, int(least[1]))
        return True
    except Exception:
        return False


def is_zoomed(hwnd):
    try:
        import ctypes
        return bool(ctypes.windll.user32.IsZoomed(ctypes.c_void_p(hwnd)))
    except Exception:
        return False


def rebuild_derived():
    pass

class _WindowButton(QtWidgets.QPushButton):

    def __init__(self, glyph, tip, danger=False, parent=None):
        super().__init__(glyph, parent)
        self.setFlat(True)
        self.setToolTip(tip)
        self.setAccessibleName(tip)
        self.setFixedSize(46, BAR_HEIGHT)
        self.setFocusPolicy(QtCore.Qt.NoFocus)
        self.setFont(QtGui.QFont(brand.ICON_FONT, 8))
        hover = WRONG if danger else SUBTLE
        ink = "#FFFFFF" if danger else INK
        self.setStyleSheet(
            f"QPushButton{{border:none; background:transparent; color:{MUTED};}}"
            f"QPushButton:hover{{background:{hover}; color:{ink};}}")


class TitleBar(QtWidgets.QWidget):

    def __init__(self, window, parent=None):
        super().__init__(parent)
        self._window = window
        self.setFixedHeight(BAR_HEIGHT)
        self.setObjectName("titleBar")
        self.setStyleSheet(
            f"QWidget#titleBar{{background:{CHROME};"
            f"border-bottom:1px solid {HAIRLINE};}}")

        lay = QtWidgets.QHBoxLayout(self)
        lay.setContentsMargins(12, 0, 0, 0)
        lay.setSpacing(9)

        seal = brand.Seal(18, NAVY)
        lay.addWidget(seal, 0, QtCore.Qt.AlignVCenter)

        name = QtWidgets.QLabel(brand.APP_NAME)
        name.setStyleSheet(
            f"color:{MUTED}; font-size:11px; border:none;"
            "background:transparent;")
        lay.addWidget(name, 0, QtCore.Qt.AlignVCenter)
        lay.addStretch(1)

        self.min_button = _WindowButton(GLYPH_MIN, L("Minimize"))
        self.min_button.clicked.connect(window.showMinimized)
        lay.addWidget(self.min_button)

        self.max_button = _WindowButton(GLYPH_MAX, L("Maximize"))
        self.max_button.clicked.connect(self._toggle_max)
        lay.addWidget(self.max_button)

        self.close_button = _WindowButton(GLYPH_CLOSE, L("Close"), danger=True)
        self.close_button.clicked.connect(window.close)
        lay.addWidget(self.close_button)

        for passive in (seal, name):
            passive.setAttribute(QtCore.Qt.WA_TransparentForMouseEvents, True)

    def _toggle_max(self):
        if self._window.isMaximized():
            self._window.showNormal()
        else:
            self._window.showMaximized()
        self.refresh()

    def refresh(self):
        full = self._window.isMaximized()
        self.max_button.setText(GLYPH_RESTORE if full else GLYPH_MAX)
        self.max_button.setToolTip(L("Restore") if full else L("Maximize"))
        self.max_button.setAccessibleName(L("Restore") if full else L("Maximize"))

    def buttons_rect(self):
        left = self.min_button.geometry().left()
        return QtCore.QRect(self.mapTo(self._window, QtCore.QPoint(left, 0)),
                            QtCore.QSize(self.width() - left, self.height()))


def hit_test(window, local, bar_height, buttons=None):
    HTLEFT, HTRIGHT, HTTOP, HTTOPLEFT = 10, 11, 12, 13
    HTTOPRIGHT, HTBOTTOM, HTBOTTOMLEFT, HTBOTTOMRIGHT = 14, 15, 16, 17
    HTCAPTION = 2

    x, y = local.x(), local.y()
    w, h = window.width(), window.height()
    if not window.isMaximized():
        left, right = x < GRIP, x > w - GRIP
        top, bottom = y < GRIP, y > h - GRIP
        if top and left:
            return HTTOPLEFT
        if top and right:
            return HTTOPRIGHT
        if bottom and left:
            return HTBOTTOMLEFT
        if bottom and right:
            return HTBOTTOMRIGHT
        if left:
            return HTLEFT
        if right:
            return HTRIGHT
        if top:
            return HTTOP
        if bottom:
            return HTBOTTOM
    if buttons is not None and buttons.contains(local):
        return None
    if y < bar_height:
        return HTCAPTION
    return None


brand.adopt(__name__)
