from __future__ import annotations

import re

from .translations import UK, ES, PT, PLURALS

LANGUAGES = ("en", "uk", "es", "pt")

TITLES = {"en": "English", "uk": "Українська", "es": "Español", "pt": "Português"}

BADGES = {"en": "EN", "uk": "UA", "es": "ES", "pt": "PT"}

LOCALES = {"en": "en_GB", "uk": "uk_UA", "es": "es", "pt": "pt_BR"}

_TABLES = {"uk": UK, "es": ES, "pt": PT}

_current = "en"


def current():
    return _current


def use(language):
    global _current
    _current = language if language in LANGUAGES else "en"


def system_default(preferred=None):
    if preferred is None:
        import locale
        preferred = (locale.getdefaultlocale()[0] or "en")
    preferred = preferred.lower().replace("_", "-")
    for language in LANGUAGES:
        if language != "en" and preferred.startswith(language):
            return language
    return "en"


_qt_translators = []


def install_qt(app=None):
    from PySide6 import QtCore, QtWidgets

    app = app or QtWidgets.QApplication.instance()
    if app is None:
        return False
    for old in _qt_translators:
        app.removeTranslator(old)
    _qt_translators.clear()
    if _current == "en":
        return True

    where = QtCore.QLibraryInfo.path(QtCore.QLibraryInfo.TranslationsPath)
    loaded = False
    for stem in ("qtbase", "qt"):
        translator = QtCore.QTranslator()
        if translator.load("%s_%s" % (stem, LOCALES.get(_current, _current)),
                           where) or translator.load(
                               "%s_%s" % (stem, _current), where):
            app.installTranslator(translator)
            _qt_translators.append(translator)
            loaded = True
    return loaded


def short_date(when=None):
    import datetime

    day = datetime.date.fromtimestamp(when) if when is not None else datetime.date.today()
    try:
        from PySide6 import QtCore
        return QtCore.QLocale(LOCALES.get(_current, "en_GB")).toString(
            QtCore.QDate(day.year, day.month, day.day), "d MMM")
    except Exception:
        return "%d %s" % (day.day, day.strftime("%b"))


def stamp(when):
    import datetime

    moment = datetime.datetime.fromtimestamp(float(when))
    try:
        from PySide6 import QtCore
        return QtCore.QLocale(LOCALES.get(_current, "en_GB")).toString(
            QtCore.QDateTime(QtCore.QDate(moment.year, moment.month, moment.day),
                             QtCore.QTime(moment.hour, moment.minute)),
            "d MMM yyyy, HH:mm")
    except Exception:
        return moment.strftime("%d %b %Y, %H:%M")


def long_date(when=None):
    import datetime

    moment = datetime.datetime.fromtimestamp(float(when)) if when else datetime.datetime.now()
    try:
        from PySide6 import QtCore
        locale = QtCore.QLocale(LOCALES.get(_current, "en_GB"))
        pattern = {"uk": "d MMMM yyyy 'р.'", "es": "d 'de' MMMM 'de' yyyy",
                   "pt": "d 'de' MMMM 'de' yyyy"}.get(_current, "d MMMM yyyy")
        return locale.toString(QtCore.QDate(moment.year, moment.month, moment.day), pattern)
    except Exception:
        return moment.strftime("%d %B %Y")


_ENGLISH_MONTHS = {m: i for i, m in enumerate(
    ("January", "February", "March", "April", "May", "June", "July", "August",
     "September", "October", "November", "December"), 1)}


def written_date(text):
    import datetime
    m = re.fullmatch(r"\s*(\d{1,2}) ([A-Za-z]+) (\d{4})\s*", str(text))
    if not m or m.group(2) not in _ENGLISH_MONTHS:
        return text
    try:
        day = datetime.datetime(int(m.group(3)), _ENGLISH_MONTHS[m.group(2)], int(m.group(1)), 12)
    except ValueError:
        return text
    return long_date(day.timestamp())


def t(text):
    table = _TABLES.get(_current)
    return table.get(text, text) if table else text


def L(text):
    return t(text)


_POSITIONAL = re.compile(r"%(\d+)\$([@dfs])")
_PLAIN = re.compile(r"%([@dfs])")


def _pythonise(fmt):
    order = []

    def positional(m):
        index = int(m.group(1)) - 1
        order.append(index)
        return "%%(a%d)s" % index

    if _POSITIONAL.search(fmt):
        return _POSITIONAL.sub(positional, fmt), order
    count = [0]

    def plain(m):
        i = count[0]
        count[0] += 1
        order.append(i)
        return "%%(a%d)s" % i

    return _PLAIN.sub(plain, fmt), order


_GROUP = re.compile(r"\{([^{}]*)\}")


def _decline_groups(fmt, args):
    if "{" not in fmt:
        return fmt
    positional = bool(_POSITIONAL.search(fmt))
    spots, order = [], []
    if positional:
        for m in _POSITIONAL.finditer(fmt):
            spots.append(m.start())
            order.append(int(m.group(1)) - 1)
    else:
        for i, m in enumerate(_PLAIN.finditer(fmt)):
            spots.append(m.start())
            order.append(i)

    def one(m):
        body = m.group(1)
        governing = None
        head, colon, rest = body.partition(":")
        if colon and head.isdigit():
            governing = int(head) - 1
            body = rest
        forms = body.split("|")
        if len(forms) == 1:
            return forms[0]
        if governing is None:
            for i, at in enumerate(spots):
                if at < m.start() and i < len(order):
                    governing = order[i]
        if governing is None or governing >= len(args):
            return forms[-1]
        try:
            n = abs(int(args[governing]))
        except (TypeError, ValueError):
            return forms[-1]
        if _current == "uk" and len(forms) >= 3:
            if 11 <= n % 100 <= 14:
                return forms[2]
            if n % 10 == 1:
                return forms[0]
            if n % 10 in (2, 3, 4):
                return forms[1]
            return forms[2]
        return forms[0] if n == 1 else forms[1]

    return _GROUP.sub(one, fmt)


def _format(fmt, args):
    fmt = _decline_groups(fmt, args)
    python, _ = _pythonise(fmt)
    mapping = {}
    for i, value in enumerate(args):
        mapping["a%d" % i] = value
    try:
        return python % mapping
    except (KeyError, ValueError, TypeError):
        return _GROUP.sub(
            lambda m: m.group(1).partition(":")[2].split("|")[-1]
            if m.group(1).partition(":")[0].isdigit() and ":" in m.group(1)
            else m.group(1).split("|")[-1], fmt)


def Lf(fmt, *args):
    return _format(t(fmt), args)


def declined(count, one, other):
    n = abs(count)
    if _current == "uk":
        forms = PLURALS.get(other)
        if forms and len(forms) == 3:
            if 11 <= n % 100 <= 14:
                return forms[2]
            if n % 10 == 1:
                return forms[0]
            if n % 10 in (2, 3, 4):
                return forms[1]
            return forms[2]
    return t(one if n == 1 else other)


def Lp(count, one, other):
    return _format(declined(count, one, other), (count,))


def plural_forms(language=None):
    return 3 if (language or _current) == "uk" else 2
