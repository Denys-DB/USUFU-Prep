from __future__ import annotations

import base64
import json
import os
import unicodedata

import pymupdf as fitz

from .core import Question, _to_swift_question, PAYLOAD_MARKER, PAYLOAD_END
from .i18n import L, Lf

PAGE_W, PAGE_H = 595, 842
MARGIN = 54
CONTENT_W = PAGE_W - MARGIN * 2

_FONTS_DIR = os.path.join(os.environ.get("WINDIR", r"C:\Windows"), "Fonts")
_REGULAR_FILES = [os.path.join(_FONTS_DIR, "segoeui.ttf"),
                  os.path.join(_FONTS_DIR, "seguisym.ttf"),
                  os.path.join(_FONTS_DIR, "cambria.ttc"),
                  "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf",
                  "/usr/share/fonts/TTF/DejaVuSans.ttf",
                  "/usr/share/fonts/dejavu/DejaVuSans.ttf",
                  "/System/Library/Fonts/Supplemental/Arial.ttf",
                  "/System/Library/Fonts/Supplemental/Arial Unicode.ttf"]
_FALLBACK_FILES = {
    False: _REGULAR_FILES,
    True: [os.path.join(_FONTS_DIR, "segoeuib.ttf"),
           os.path.join(_FONTS_DIR, "cambriab.ttf"),
           "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf",
           "/usr/share/fonts/TTF/DejaVuSans-Bold.ttf",
           "/usr/share/fonts/dejavu/DejaVuSans-Bold.ttf",
           "/System/Library/Fonts/Supplemental/Arial Bold.ttf"] + _REGULAR_FILES,
}
_fallbacks = {}


def _fallback_fonts(bold):
    if bold not in _fallbacks:
        found = []
        for path in _FALLBACK_FILES[bold]:
            if os.path.exists(path):
                try:
                    found.append(("fb%d%s" % (len(found), "b" if bold else ""),
                                  path, fitz.Font(fontfile=path)))
                except Exception:
                    pass
        _fallbacks[bold] = found
    return _fallbacks[bold]


def _encodable(ch):
    try:
        ch.encode("latin-1")
        return True
    except UnicodeEncodeError:
        return False


def _runs(text, font):
    clusters = []
    for ch in text:
        if clusters and unicodedata.combining(ch):
            clusters[-1] += ch
        else:
            clusters.append(ch)
    runs = []
    for cl in clusters:
        face = None
        if not all(_encodable(c) for c in cl):
            for entry in _fallback_fonts(font == "hebo"):
                if all(entry[2].has_glyph(ord(c)) for c in cl):
                    face = entry
                    break
        if runs and runs[-1][0] is face:
            runs[-1][1] += cl
        else:
            runs.append([face, cl])
    return runs


_base_fonts = {}


def _base_font(font):
    if font not in _base_fonts:
        _base_fonts[font] = fitz.Font(font)
    return _base_fonts[font]


def _length(text, font, size):
    return sum(_base_font(font).text_length(t, fontsize=size) if face is None
               else face[2].text_length(_bases(t), fontsize=size)
               for face, t in _runs(text, font))


def _bases(t):
    return "".join(c for c in t if not unicodedata.combining(c))


_ink = {}


def _mark_ink(face, mark):
    key = (face[1], mark)
    if key not in _ink:
        doc = fitz.open()
        page = doc.new_page(width=200, height=120)
        page.insert_text(fitz.Point(60, 90), mark, fontname="m", fontfile=face[1],
                         fontsize=100)
        pix = page.get_pixmap(dpi=72, colorspace=fitz.csGRAY)
        cols = [x for x in range(pix.width)
                if any(pix.pixel(x, y)[0] < 128 for y in range(pix.height))]
        _ink[key] = ((cols[0] - 60) / 100.0, (cols[-1] + 1 - 60) / 100.0) if cols else (0.0, 0.0)
        doc.close()
    return _ink[key]


def _insert(page, x, baseline, face, t, font, size, color):
    if face is None:
        page.insert_text(fitz.Point(x, baseline), t, fontname=font, fontsize=size,
                         color=color)
        return
    base = _bases(t)
    page.insert_text(fitz.Point(x, baseline), base, fontname=face[0],
                     fontfile=face[1], fontsize=size, color=color)
    pen, before = x, None
    for c in t:
        if not unicodedata.combining(c):
            before = (pen, face[2].text_length(c, fontsize=size))
            pen += before[1]
        elif before is not None:
            left, right = _mark_ink(face, c)
            mx = before[0] + before[1] / 2 - (left + right) / 2 * size
            page.insert_text(fitz.Point(mx, baseline), c, fontname=face[0],
                             fontfile=face[1], fontsize=size, color=color)


def _save(doc, out_path):
    try:
        doc.subset_fonts()
    except Exception:
        pass
    from .safeio import atomic_write_bytes
    atomic_write_bytes(out_path, doc.tobytes(garbage=4, deflate=True,
                                             deflate_images=True))


INK = (0.09, 0.09, 0.09)
MUTED = (0.42, 0.42, 0.42)
GREEN = (0.09, 0.45, 0.22)
RULE = (0.82, 0.82, 0.82)


class _Writer:
    def __init__(self, doc):
        self.doc = doc
        self.page = None
        self.y = 0
        self.new_page()

    def new_page(self):
        self.page = self.doc.new_page(width=PAGE_W, height=PAGE_H)
        self.y = MARGIN

    def space(self, h):
        self.y += h

    def ensure(self, h):
        if self.y + h > PAGE_H - MARGIN:
            self.new_page()

    def text(self, s, size=10.5, bold=False, color=INK, indent=0, underlines=()):
        if not s or not s.strip():
            return
        font = "hebo" if bold else "helv"
        width = CONTENT_W - indent
        line_h = size * 1.35

        marked = [False] * len(s)
        for a, b in (underlines or ()):
            for i in range(max(0, a), min(int(b), len(s))):
                marked[i] = True

        pos = 0
        for para in s.split("\n\n"):
            cells = list(zip(para, marked[pos:pos + len(para)]))
            pos += len(para) + 2

            packed = []
            for ch, flag in cells:
                if ch.isspace():
                    if packed and packed[-1][0] == " ":
                        continue
                    packed.append((" ", flag))
                else:
                    packed.append((ch, flag))
            while packed and packed[0][0] == " ":
                packed.pop(0)
            while packed and packed[-1][0] == " ":
                packed.pop()
            if not packed:
                continue

            for line in self._wrap(packed, font, size, width):
                if self.y + line_h > PAGE_H - MARGIN:
                    self.new_page()
                x = MARGIN + indent
                baseline = self.y + size
                run_x = x
                for face, t in _runs("".join(c for c, _ in line), font):
                    _insert(self.page, run_x, baseline, face, t, font, size, color)
                    run_x += _length(t, font, size)
                i = 0
                while i < len(line):
                    if not line[i][1]:
                        i += 1
                        continue
                    j = i
                    while j < len(line) and line[j][1]:
                        j += 1
                    x0 = x + _length("".join(c for c, _ in line[:i]), font, size)
                    x1 = x + _length("".join(c for c, _ in line[:j]), font, size)
                    self.page.draw_line(fitz.Point(x0, baseline + size * 0.13),
                                        fitz.Point(x1, baseline + size * 0.13),
                                        color=color, width=0.5)
                    i = j
                self.y += line_h
            self.space(3)

    @staticmethod
    def _wrap(cells, font, size, width):
        def measure(seq):
            return _length("".join(c for c, _ in seq), font, size)

        words, current = [], []
        for cell in cells:
            if cell[0] == " ":
                words.append(current)
                current = []
            else:
                current.append(cell)
        words.append(current)

        lines, line = [], []
        for word in words:
            trial = line + ([(" ", False)] if line else []) + word
            if measure(trial) <= width:
                line = trial
                continue
            if line:
                lines.append(line)
                line = []
            while measure(word) > width and len(word) > 1:
                cut = len(word)
                while cut > 1 and measure(word[:cut]) > width:
                    cut -= 1
                lines.append(word[:cut])
                word = word[cut:]
            line = word
        if line:
            lines.append(line)
        return lines

    def image(self, path, point_width, indent=0):
        if not os.path.exists(path):
            return
        try:
            pix = fitz.Pixmap(path)
        except Exception:
            return
        if pix.width == 0:
            return
        aspect = pix.height / pix.width
        w = min(point_width or CONTENT_W, CONTENT_W - indent)
        h = w * aspect
        if h > PAGE_H - MARGIN * 2:
            h = PAGE_H - MARGIN * 2
            w = h / aspect
        self.ensure(h + 4)
        rect = fitz.Rect(MARGIN + indent, self.y, MARGIN + indent + w, self.y + h)
        self.page.insert_image(rect, filename=path)
        self.y += h + 6

    def rule(self):
        self.page.draw_line(fitz.Point(MARGIN, self.y),
                            fitz.Point(PAGE_W - MARGIN, self.y),
                            color=RULE, width=0.5)
        self.space(2)

    def bubble(self, letter, filled):
        r = 8
        cx, cy = MARGIN + r, self.y + r + 1
        circle = fitz.Rect(cx - r, cy - r, cx + r, cy + r)
        if filled:
            self.page.draw_oval(circle, color=GREEN, fill=GREEN, width=1)
            tc = (1, 1, 1)
        else:
            self.page.draw_oval(circle, color=(0.55, 0.55, 0.55), width=1)
            tc = (0.3, 0.3, 0.3)
        size = 9
        width = fitz.get_text_length(letter, fontname="hebo", fontsize=size)
        self.page.insert_text(fitz.Point(cx - width / 2, cy + size * 0.36),
                              letter, fontname="hebo", fontsize=size, color=tc)


def export_missed(questions, images_dir, out_path, subtitle="", title=None):
    doc = fitz.open()
    w = _Writer(doc)

    w.text(title or L("SAT Practice — Questions to Review"), size=20, bold=True)
    if subtitle:
        w.text(subtitle, size=10, color=MUTED)
    w.space(4)
    w.rule()
    w.space(10)

    for i, q in enumerate(questions):
        w.ensure(120)
        w.text(Lf("Question %d", i + 1), size=13, bold=True)
        bits = [b for b in (q.test, q.domain, q.skill, q.difficulty) if b]
        bits.append(f"ID {q.id}")
        w.text("  ·  ".join(bits), size=8.5, color=MUTED)
        w.space(4)

        for b in q.stimulus:
            _block(w, b, images_dir)
        for b in q.prompt:
            _block(w, b, images_dir)

        if q.kind == "multiple_choice":
            w.space(4)
            for c in q.choices:
                w.ensure(28)
                top = w.y
                w.bubble(c.letter, c.letter == q.correct_answer)
                w.y = top
                for b in c.blocks:
                    _block(w, b, images_dir, indent=24)
                if w.y == top:
                    w.space(20)
                w.space(3)

        w.space(4)
        w.text(Lf("Correct answer:  %@", q.correct_answer), size=10.5, bold=True, color=GREEN)

        if q.rationale:
            w.space(2)
            w.text("Rationale", size=10, bold=True, color=(0.25, 0.25, 0.25))
            for b in q.rationale:
                _block(w, b, images_dir)

        w.space(8)
        w.ensure(20)
        w.rule()
        w.space(12)

    _save(doc, out_path)
    doc.close()

    _append_payload(out_path, questions, images_dir)


def _block(w: _Writer, block, images_dir, indent=0):
    if block.kind == "text":
        w.text(block.text, size=10.5, indent=indent,
               underlines=getattr(block, "underlines", ()))
    else:
        w.image(os.path.join(images_dir, block.image_name), block.point_width, indent)


def _append_payload(out_path, questions, images_dir):
    from .core import inline_images
    names = set()
    for q in questions:
        for b in q.all_blocks:
            if b.kind == "image" and b.image_name:
                names.add(b.image_name)
            names.update(inline_images(b))

    from .core import safe_image_path
    images = {}
    for name in names:
        p = safe_image_path(images_dir, name)
        if p and os.path.exists(p):
            with open(p, "rb") as f:
                images[name] = base64.b64encode(f.read()).decode("ascii")

    payload = {"questions": [_to_swift_question(q) for q in questions], "images": images}
    blob = base64.b64encode(json.dumps(payload).encode("utf-8"))

    from .safeio import atomic_write_bytes
    with open(out_path, "rb") as f:
        body = f.read()
    tail = [b"\n" + PAYLOAD_MARKER + b"\n"]
    tail += [blob[i:i + 76] + b"\n" for i in range(0, len(blob), 76)]
    tail.append(PAYLOAD_END + b"\n")
    atomic_write_bytes(out_path, body + b"".join(tail))
