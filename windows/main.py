import os
import re
import sys
import time

from PySide6 import QtWidgets, QtGui, QtCore, QtNetwork

from satprep import brand
from satprep import chrome
from satprep import i18n
from satprep.i18n import L, Lf, Lp
from satprep.core import Store
from satprep.home import HomeScreen, ReviewScreen
from satprep.ui import ExamScreen


PREFERRED_SIZE = (1180, 820)

MINIMUM_SIZE = (900, 620)


def window_plan(avail_w, avail_h, preferred=PREFERRED_SIZE):
    w, h = preferred
    if w <= avail_w and h <= avail_h:
        return ("normal", w, h)
    return ("maximized", avail_w, avail_h)


def place_on_screen(win):
    screen = (QtGui.QGuiApplication.screenAt(QtGui.QCursor.pos())
              or QtGui.QGuiApplication.primaryScreen())
    avail = screen.availableGeometry()
    mode, w, h = window_plan(avail.width(), avail.height())
    win.setMinimumSize(min(MINIMUM_SIZE[0], avail.width()),
                       min(MINIMUM_SIZE[1], avail.height()))
    win.resize(w, h)
    if mode == "normal":
        win.move(avail.x() + (avail.width() - w) // 2, avail.y() + (avail.height() - h) // 2)
    else:
        win.move(avail.topLeft())
    return mode


class _ReturnPresses(QtCore.QObject):

    def eventFilter(self, obj, event):
        if event.type() == QtCore.QEvent.KeyPress                 and event.key() in (QtCore.Qt.Key_Return, QtCore.Qt.Key_Enter)                 and not (event.modifiers() & ~QtCore.Qt.KeypadModifier)                 and isinstance(obj, (QtWidgets.QPushButton, QtWidgets.QToolButton))                 and not (isinstance(obj, QtWidgets.QPushButton) and obj.autoDefault())                 and obj.isEnabled() and obj.isVisible():
            obj.click()
            return True
        return False


class MainWindow(QtWidgets.QMainWindow):
    def __init__(self, store=None):
        super().__init__()
        self.setWindowTitle(brand.APP_NAME)
        self.setWindowIcon(brand.seal_icon(256))
        self.resize(*PREFERRED_SIZE)
        self.store = store if store is not None else Store()
        self.apply_palette()
        QtWidgets.QApplication.instance().applicationStateChanged.connect(
            self._reread_motion)

        self.stack = QtWidgets.QStackedWidget()
        self.title_bar = None
        if chrome.supported():
            self.setWindowFlag(QtCore.Qt.FramelessWindowHint, True)
            self.title_bar = chrome.TitleBar(self)
            shell = QtWidgets.QWidget()
            shell_lay = QtWidgets.QVBoxLayout(shell)
            shell_lay.setContentsMargins(0, 0, 0, 0)
            shell_lay.setSpacing(0)
            shell_lay.addWidget(self.title_bar)
            shell_lay.addWidget(self.stack, 1)
            self.setCentralWidget(shell)
            self._sizable = chrome.restore_sizing_frame(self)
        else:
            self.setCentralWidget(self.stack)
        self.show_home()
        waiting = self.store.sets_with_saved_sittings()
        if waiting and hasattr(self.stack.currentWidget(), "_choose_set"):
            self.stack.currentWidget()._choose_set(waiting[0][0].id)
        self._bind_sizing_keys()
        self._return_presses = _ReturnPresses(self)
        QtWidgets.QApplication.instance().installEventFilter(self._return_presses)

        self._intro = None
        QtCore.QTimer.singleShot(0, self._play_intro)

        QtCore.QTimer.singleShot(0, self._reread_stale)

        self._nudged_on = None
        self._reminder = QtCore.QTimer(self)
        self._reminder.setInterval(60_000)
        self._reminder.timeout.connect(self._check_reminder)
        self._reminder.start()
        self._tray = None

    def nativeEvent(self, event_type, message):
        if self.title_bar is None or event_type != b"windows_generic_MSG":
            return super().nativeEvent(event_type, message)
        try:
            import ctypes
            import ctypes.wintypes
            msg = ctypes.wintypes.MSG.from_address(int(message))
        except Exception:
            return super().nativeEvent(event_type, message)

        if msg.message == 0x0024:
            ratio = self.devicePixelRatioF() or 1.0
            least = self.minimumSize()
            if chrome.fill_minmax(msg.hWnd, msg.lParam,
                                  (round(least.width() * ratio), round(least.height() * ratio))):
                return True, 0
            return super().nativeEvent(event_type, message)

        if msg.message == 0x0083:
            if msg.wParam:
                rect = ctypes.cast(
                    msg.lParam,
                    ctypes.POINTER(ctypes.wintypes.RECT)).contents
                work = chrome.work_area(msg.hWnd) if chrome.is_zoomed(msg.hWnd) else None
                if work:
                    (rect.left, rect.top, rect.right, rect.bottom) = chrome.maximised_client(
                        (rect.left, rect.top, rect.right, rect.bottom), work)
                rect.top -= 1
                return True, 0
            return super().nativeEvent(event_type, message)

        if msg.message != 0x0084:
            return super().nativeEvent(event_type, message)

        x = ctypes.c_short(msg.lParam & 0xFFFF).value
        y = ctypes.c_short((msg.lParam >> 16) & 0xFFFF).value
        ratio = self.devicePixelRatioF() or 1.0
        local = self.mapFromGlobal(QtCore.QPoint(int(x / ratio), int(y / ratio)))

        where = chrome.hit_test(self, local, self.title_bar.height(),
                                self.title_bar.buttons_rect())
        if where is None:
            return super().nativeEvent(event_type, message)
        return True, where

    def changeEvent(self, event):
        if event.type() == QtCore.QEvent.WindowStateChange and self.title_bar:
            self.title_bar.refresh()
        super().changeEvent(event)

    def showEvent(self, event):
        super().showEvent(event)
        if self.title_bar is not None and not getattr(self, "_sized_once", False):
            self._sized_once = True
            self._sizable = chrome.restore_sizing_frame(self)

    def _reread_stale(self):
        stale = [b for b in self.store.banks if self.store.needs_reread(b)]
        if not stale:
            self._say_highlights_taken_off()
            self._offer_restore()
            return
        dlg = QtWidgets.QProgressDialog(
            L("Bringing your question sets up to date…"), None, 0, 100, self)
        dlg.setWindowTitle(L("Reading again"))
        dlg.setWindowModality(QtCore.Qt.WindowModal)
        dlg.setMinimumDuration(400)

        def report(p, msg):
            dlg.setValue(int(p * 100))
            dlg.setLabelText(msg)
            QtWidgets.QApplication.processEvents()

        self.stack.setEnabled(False)
        try:
            self.store.reread_stale_banks(progress=report)
        finally:
            self.stack.setEnabled(True)
        dlg.close()
        self.show_home()
        self._say_highlights_taken_off()
        self._offer_restore()

    def _say_highlights_taken_off(self):
        from satprep.home import say_highlights_taken_off
        say_highlights_taken_off(self, self.store)

    def _offer_restore(self):
        gap = self.store.restorable_gap()
        if not gap:
            return
        from satprep.home import StreakRestoreDialog
        dialog = StreakRestoreDialog(self.store, gap, self)
        dialog.exec()
        if dialog.restored:
            self.show_home()

    def _check_reminder(self):
        if self.store.settings.get("stealthMode") and self._sitting_on_screen():
            return
        plan = self.store.schedule()
        if not (plan.get("enabled") and plan.get("reminders_on")):
            return
        state = self.store.streak()
        if state["is_rest_day"] or state["met_today"]:
            return

        now = QtCore.QDateTime.currentDateTime()
        today = now.date()
        due = QtCore.QTime(int(plan["reminder_hour"]), int(plan["reminder_minute"]))
        warn = QtCore.QTime(int(plan.get("warning_hour", 20)), 0)

        slot = None
        if now.time() >= due:
            slot = "due"
        if plan.get("warns_when_streak_at_risk") and state["at_risk"] \
                and now.time() >= warn:
            slot = "warn"
        if slot is None or self._nudged_on == (today, slot):
            return
        self._nudged_on = (today, slot)

        left = state["remaining_today"]
        if slot == "warn":
            title = (L("Your streak ends tonight") if state["current"] == 1
                     else Lf("%d-day streak ends tonight", state["current"]))
            body = Lp(left, "One more question keeps it.",
                      "%d more questions keep it.")
        else:
            title = L("Time to practice")
            body = Lp(left, "One question left today.",
                      "%d questions left today.")
        self._notify(title, body)

    def _bind_sizing_keys(self):
        for keys, delta in ((("Ctrl++", "Ctrl+=", "Meta++", "Meta+="), 1),
                            (("Ctrl+-", "Meta+-"), -1),
                            (("Ctrl+0", "Meta+0"), 0)):
            for combo in keys:
                shortcut = QtGui.QShortcut(QtGui.QKeySequence(combo), self)
                shortcut.setContext(QtCore.Qt.ApplicationShortcut)
                shortcut.activated.connect(lambda d=delta: self._zoom(d))

    def _zoom(self, delta):
        current = self.stack.currentWidget()
        zoom = getattr(current, "zoom_by", None)
        if callable(zoom):
            zoom(delta)

    def _sitting_on_screen(self):
        current = self.stack.currentWidget()
        return current is not None and type(current).__name__ in ("ExamScreen",
                                                                  "DoubleExamScreen")

    def _notify(self, title, body):
        if self._tray is None and QtWidgets.QSystemTrayIcon.isSystemTrayAvailable():
            self._tray = QtWidgets.QSystemTrayIcon(brand.seal_icon(64), self)
            self._tray.setToolTip(brand.APP_NAME)
            self._tray.show()
        if self._tray is not None:
            if self.store.settings.get("stealthMode"):
                self._tray.showMessage(title, body,
                                       QtWidgets.QSystemTrayIcon.NoIcon, 8000)
            else:
                self._tray.showMessage(title, body, brand.seal_icon(64), 8000)
        else:
            box = brand.alert(self, title, body)
            box.addButton(L("OK"), QtWidgets.QMessageBox.AcceptRole)
            box.setModal(False)
            box.show()

    def apply_palette(self):
        brand.apply_theme(self.store.settings.get("appearance", "light"))
        brand.apply_stealth(bool(self.store.settings.get("stealthMode", False)))
        brand.apply_motion(bool(self.store.settings.get("reduceMotion", False)))

    def _reread_motion(self, state):
        if state == QtCore.Qt.ApplicationActive:
            brand.apply_motion(bool(self.store.settings.get("reduceMotion", False)))

    def reload_theme(self):
        self.apply_palette()
        self._rebuild_title_bar()
        self._rebuild_where_they_are()

    def _rebuild_title_bar(self):
        if self.title_bar is None:
            return
        old = self.title_bar
        self.title_bar = chrome.TitleBar(self)
        self.title_bar.refresh()
        old.parentWidget().layout().replaceWidget(old, self.title_bar)
        old.deleteLater()

    def _rebuild_where_they_are(self):
        top = self.stack.currentWidget()
        kind = type(top).__name__
        article = getattr(top, "article", None)
        deck = getattr(top, "deck_id", None)
        mode = getattr(top, "mode", "cards")
        self.show_home()
        if kind == "LearnScreen":
            self.show_learn()
        elif kind == "ArticleScreen" and article is not None:
            self.show_learn()
            self.show_article(article.get("id"))
        elif kind == "DeckFocusScreen" and deck is not None:
            self.show_deck_focus(deck, mode)

    def reload_language(self):
        from satprep import intro
        i18n.install_qt()
        self._intro = intro.play_switch_over(self, self._show_home_retitled)

    def _show_home_retitled(self):
        self._rebuild_title_bar()
        self.show_home()

    def reload_stealth(self):
        brand.apply_stealth(bool(self.store.settings.get("stealthMode", False)))
        self._rebuild_title_bar()
        current = self.stack.currentWidget()
        if current is not None and type(current).__name__ in ("ExamScreen",
                                                              "DoubleExamScreen"):
            self.open_exam(current.session)
        else:
            self._rebuild_where_they_are()

    def _swap(self, widget):
        while self.stack.count():
            old = self.stack.widget(0)
            self.stack.removeWidget(old)
            old.deleteLater()
        self.stack.addWidget(widget)
        self.stack.setCurrentWidget(widget)
        self._take_keyboard(widget)

    def _push(self, widget):
        self.stack.addWidget(widget)
        self.stack.setCurrentWidget(widget)
        self._take_keyboard(widget)

    def _pop(self):
        if self.stack.count() < 2:
            self.show_home()
            return
        top = self.stack.widget(self.stack.count() - 1)
        self.stack.removeWidget(top)
        top.deleteLater()
        under = self.stack.widget(self.stack.count() - 1)
        self.stack.setCurrentWidget(under)
        if hasattr(under, "returned"):
            under.returned()
        self._take_keyboard(under)

    def _take_keyboard(self, widget):
        if widget.focusPolicy() != QtCore.Qt.NoFocus:
            widget.setFocus(QtCore.Qt.OtherFocusReason)

    def _play_intro(self):
        from satprep import intro
        home = self.stack.currentWidget()
        if home is None or not hasattr(home, "masthead_seal"):
            return
        self._intro = intro.play_over(self, home)

    def show_home(self):
        home = HomeScreen(self.store)
        home.start_requested.connect(self.start)
        home.resume_requested.connect(self.open_exam)
        home.sitting_opened.connect(self.show_review)
        home.learn_requested.connect(self.show_learn)
        home.article_requested.connect(self.show_article)
        home.focus_requested.connect(self.show_deck_focus)
        self._swap(home)

    def show_deck_focus(self, deck_id, mode):
        from satprep.decks import DeckFocusScreen
        screen = DeckFocusScreen(self.store, deck_id, mode)
        screen.closed.connect(self._pop)
        self._push(screen)

    def show_learn(self, scroll_to=None):
        from satprep.learn import LearnScreen
        screen = LearnScreen(self.store, scroll_to=scroll_to)
        screen.opened.connect(self.show_article)
        screen.closed.connect(self._pop)
        self._push(screen)

    def show_article(self, article_id):
        from satprep import articles
        from satprep.learn import ArticleScreen
        found = next((a for a in articles.current() if a.get("id") == article_id), None)
        if found is None:
            return
        screen = ArticleScreen(found)
        screen.back.connect(self._pop)
        self._push(screen)

    def start(self, config):
        if not self._may_replace_saved(config.get("bank_id")):
            return
        session = self.store.start_session(config)
        if session is None:
            brand.tell(
                self, L("Nothing to practice"),
                L("There are no questions matching those settings."))
            return
        self.open_exam(session)

    def _may_replace_saved(self, bank_id):
        if not bank_id:
            return True
        saved = self.store.saved_session(bank_id)
        if saved is None or saved.answered_count == 0:
            return True
        return brand.ask(
            self, L("Start a new practice?"),
            Lf("You have a test in progress — %@. Starting a new one replaces "
               "it, and the answers in it are lost.", saved.resume_detail()),
            accept=L("Start a new one"), destructive=True)

    def open_exam(self, session):
        if session.is_side_by_side:
            from satprep.double import DoubleExamScreen
            exam = DoubleExamScreen(self.store, session)
        else:
            exam = ExamScreen(self.store, session)
        exam.finished.connect(lambda: self.show_review(session))
        exam.left.connect(self.show_home)
        self._swap(exam)

    def show_review(self, session):
        review = ReviewScreen(self.store, session)
        review.done.connect(self.show_home)
        review.article_requested.connect(self.show_article)
        review.practise_again.connect(self.start)
        self._swap(review)


def _error_log_path():
    if os.environ.get("SATPREP_ERROR_LOG"):
        return os.environ["SATPREP_ERROR_LOG"]
    if getattr(sys, "frozen", False):
        from satprep import core
        folder = core.data_root()
        try:
            os.makedirs(folder, exist_ok=True)
        except OSError:
            pass
        return os.path.join(folder, "satprep-error.log")
    return os.path.join(os.path.dirname(os.path.abspath(__file__)), "satprep-error.log")


_crash_log = None
_crash_log_sizes = (0, 0)


def _keep_crash_evidence():
    global _crash_log, _crash_log_sizes
    if sys.platform == "win32":
        return
    import faulthandler
    try:
        stream = sys.__stderr__
        if stream is None or not stream.isatty():
            path = _error_log_path()
            before = os.path.getsize(path) if os.path.exists(path) else 0
            _crash_log = open(path, "a", encoding="utf-8", buffering=1)
            _crash_log.write(f"\n--- {time.strftime('%Y-%m-%d %H:%M:%S')} started ---\n")
            _crash_log.flush()
            _crash_log_sizes = (before, os.fstat(_crash_log.fileno()).st_size)
            os.dup2(_crash_log.fileno(), 2)
            faulthandler.enable(file=_crash_log, all_threads=True)
        else:
            faulthandler.enable(all_threads=True)
    except Exception:
        pass


def _settle_crash_evidence():
    if _crash_log is None:
        return
    try:
        _crash_log.flush()
        before, after = _crash_log_sizes
        if os.fstat(_crash_log.fileno()).st_size == after:
            os.ftruncate(_crash_log.fileno(), before)
            if before == 0:
                os.remove(_error_log_path())
    except Exception:
        pass


def _report(exc_type, exc, tb):
    import traceback
    text = "".join(traceback.format_exception(exc_type, exc, tb))
    try:
        log = _error_log_path()
        with open(log, "a", encoding="utf-8") as f:
            f.write(f"\n--- {time.strftime('%Y-%m-%d %H:%M:%S')} ---\n{text}")
    except Exception:
        log = "(could not be written)"
    if _crash_log is None:
        sys.__stderr__.write(text)
    try:
        box = brand.alert(
            None, Lf("%@ stopped", brand.APP_NAME),
            Lf("Something went wrong and %@ had to stop.", brand.APP_NAME))
        box.addButton(L("OK"), QtWidgets.QMessageBox.AcceptRole)
        box.setInformativeText(
            Lf("The details were saved to:%@", "\n" + log))
        box.setDetailedText(text)
        box.exec()
    except Exception:
        pass


def _instance_key():
    import getpass
    try:
        who = getpass.getuser() or "student"
    except Exception:
        who = "student"
    return "usufu-sat-prep-" + re.sub(r"[^A-Za-z0-9_-]", "-", who)


def _already_running(app, on_second):
    socket = QtNetwork.QLocalSocket()
    socket.connectToServer(_instance_key())
    if socket.waitForConnected(300):
        socket.write(b"raise")
        socket.waitForBytesWritten(300)
        socket.disconnectFromServer()
        return True

    QtNetwork.QLocalServer.removeServer(_instance_key())
    server = QtNetwork.QLocalServer(app)
    if not server.listen(_instance_key()):
        return False
    server.newConnection.connect(on_second)
    app._instance_server = server
    return False


def main():
    _keep_crash_evidence()
    sys.excepthook = _report
    app = QtWidgets.QApplication(sys.argv)
    app.setApplicationName(brand.APP_NAME)
    app.setOrganizationName(brand.ORGANISATION)
    app.setStyle("Fusion")
    brand.apply_qt_palette()

    holder = {}

    def raise_existing():
        window = holder.get("window")
        if window is None:
            return
        window.setWindowState(
            (window.windowState() & ~QtCore.Qt.WindowMinimized)
            | QtCore.Qt.WindowActive)
        window.show()
        window.raise_()
        window.activateWindow()

    if _already_running(app, raise_existing):
        _settle_crash_evidence()
        return

    win = MainWindow()
    i18n.install_qt(app)
    holder["window"] = win
    if place_on_screen(win) == "maximized":
        win.showMaximized()
    else:
        win.show()
    code = app.exec()
    _settle_crash_evidence()
    sys.exit(code)


if __name__ == "__main__":
    main()
