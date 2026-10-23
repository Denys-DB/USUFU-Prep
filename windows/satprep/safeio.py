from __future__ import annotations

import json
import os
import stat
import tempfile
import time

MARKER = ".damaged-"

REPLACE_PATIENCE = 2.0
REPLACE_STEP = 0.025


def _writable(path):
    try:
        mode = os.stat(path).st_mode
    except OSError:
        return False
    if mode & stat.S_IWRITE:
        return False
    try:
        os.chmod(path, mode | stat.S_IWRITE)
        return True
    except OSError:
        return False


def _replace(src, dst):
    deadline = time.monotonic() + REPLACE_PATIENCE
    while True:
        try:
            os.replace(src, dst)
            return
        except PermissionError:
            if _writable(dst):
                continue
            if time.monotonic() >= deadline:
                raise
            time.sleep(REPLACE_STEP)


def is_set_aside(name):
    return MARKER in name


def atomic_write_bytes(path, data):
    folder = os.path.dirname(os.path.abspath(path))
    os.makedirs(folder, exist_ok=True)
    fd, tmp = tempfile.mkstemp(dir=folder, prefix="." + os.path.basename(path) + ".",
                               suffix=".tmp")
    try:
        with os.fdopen(fd, "wb") as f:
            f.write(data)
            f.flush()
            os.fsync(f.fileno())
        _replace(tmp, path)
    except BaseException:
        try:
            os.remove(tmp)
        except OSError:
            pass
        raise
    if hasattr(os, "O_DIRECTORY"):
        try:
            dfd = os.open(folder, os.O_RDONLY | os.O_DIRECTORY)
            try:
                os.fsync(dfd)
            finally:
                os.close(dfd)
        except OSError:
            pass


def atomic_write_text(path, text):
    atomic_write_bytes(path, text.encode("utf-8"))


def write_json(path, obj, **dump_kwargs):
    atomic_write_text(path, json.dumps(obj, **dump_kwargs))


def set_aside(path, now=None):
    if not os.path.exists(path):
        return None
    stamp = time.strftime("%Y%m%d-%H%M%S", time.localtime(now if now is not None else time.time()))
    base = f"{path}{MARKER}{stamp}"
    target, n = base, 2
    while os.path.exists(target):
        target = f"{base}-{n}"
        n += 1
    try:
        _replace(path, target)
        return target
    except OSError:
        return None


def read_json(path, default, damaged=None, expect=None):
    if not os.path.exists(path):
        return default
    try:
        with open(path, encoding="utf-8") as f:
            value = json.load(f)
        if expect is None or isinstance(value, expect):
            return value
    except Exception:
        pass
    moved = set_aside(path)
    if damaged:
        damaged(moved or path)
    return default
