from __future__ import annotations

import os
import re
from dataclasses import dataclass, field

import pymupdf as fitz

from .i18n import Lf


_TEXT_COVERAGE = 0.55

RENDER_SCALE = 3.0


def _area(r: fitz.Rect) -> float:
    return max(0.0, r.width) * max(0.0, r.height)


_MIN_COLUMN = 15.0


def _table_bounds(edges, bottoms):
    first = bottoms[0] - ((bottoms[1] - bottoms[0]) if len(bottoms) > 1 else 20)
    return edges[0], first, edges[-1], bottoms[-1]


def _drawn_inside(tables, graphics) -> bool:
    for edges, bottoms in tables:
        if not bottoms:
            continue
        x0, y0, x1, y1 = _table_bounds(edges, bottoms)
        for r in graphics:
            if (r.x0 >= x0 - 1 and r.x1 <= x1 + 1
                    and r.y0 >= y0 - 1 and r.y1 <= y1 + 1):
                return True
    return False


def find_tables(bars):
    by_y: dict = {}
    for b in bars:
        by_y.setdefault(round(b.y0, 0), []).append(b)

    signatures: dict = {}
    for y, segs in by_y.items():
        segs = sorted(segs, key=lambda r: r.x0)
        edges = [segs[0].x0]
        contiguous = True
        for a, b in zip(segs, segs[1:]):
            if abs(b.x0 - a.x1) > 1.5:
                contiguous = False
                break
            edges.append(b.x0)
        edges.append(segs[-1].x1)
        if not contiguous or len(edges) < 3:
            continue
        if any(edges[i + 1] - edges[i] < _MIN_COLUMN for i in range(len(edges) - 1)):
            continue
        signatures.setdefault(tuple(round(e, 0) for e in edges), []).append(y)

    return [(list(edges), sorted(ys))
            for edges, ys in signatures.items() if len(ys) >= 2]


def table_rows(lines, edges, bottoms):
    ncols = len(edges) - 1
    first_top = bottoms[0] - ((bottoms[1] - bottoms[0]) if len(bottoms) > 1 else 20)
    tops = [first_top] + bottoms[:-1]

    banded = [[] for _ in tops]
    for line in lines:
        if not (line.x1 > edges[0] - 2 and line.x0 < edges[-1] + 2):
            continue
        for i, (top, bottom) in enumerate(zip(tops, bottoms)):
            if top < line.y1 <= bottom + 1.0:
                banded[i].append(line)
                break

    rows = []
    for band in banded:
        columns = [[] for _ in range(ncols)]
        spanning = None
        ruled = any(len(_runs(l)) > 1 for l in band)
        if not ruled:
            touched = set()
            for l in band:
                rs = _runs(l)
                if len(rs) == 1:
                    col = _column_of(rs[0], edges)
                    if col is not None:
                        touched.add(col)
            ruled = len(touched) >= 2

        for line in band:
            runs = _runs(line)
            if not runs:
                continue
            if len(runs) == 1 and (not ruled
                                   or _column_of(runs[0], edges) is None):
                spanning = (spanning + " " + runs[0][0]) if spanning else runs[0][0]
                continue
            for run in runs:
                col = _column_of(run, edges)
                if col is not None:
                    columns[col].append(run[0])

        if spanning is not None and not any(columns):
            rows.append([spanning])
        else:
            if spanning is not None:
                rows.append([spanning])
            rows.append([" ".join(c).strip() for c in columns])
    return rows


def _runs(line, gap=4.0):
    out = []
    text, x0, x1 = "", None, None
    for ch, box in zip(line.text, line.char_boxes):
        if box is None:
            if text:
                text += " "
            continue
        if x1 is not None and box[0] - x1 > gap:
            if text.strip():
                out.append((text.strip(), x0, x1))
            text, x0 = "", None
        if x0 is None:
            x0 = box[0]
        text += ch
        x1 = box[1]
    if text.strip():
        out.append((text.strip(), x0, x1))
    return out


def _column_of(run, edges=None):
    if edges is None:
        return None
    _, x0, x1 = run
    for i in range(len(edges) - 1):
        if x0 >= edges[i] - 2 and x1 <= edges[i + 1] + 2:
            return i
    mid = (x0 + x1) / 2
    for i in range(len(edges) - 1):
        if edges[i] <= mid < edges[i + 1]:
            return None if (x1 - x0) > (edges[i + 1] - edges[i]) + 4 else i
    return None


def _merge_spans(spans):
    out = []
    for s, e in sorted(spans):
        if out and s <= out[-1][1]:
            out[-1] = (out[-1][0], max(out[-1][1], e))
        else:
            out.append((s, e))
    return out


@dataclass
class Line:
    text: str
    x0: float
    y0: float
    x1: float
    y1: float
    cells: list
    underlines: list = field(default_factory=list)
    char_boxes: list = field(default_factory=list)
    bullet: bool = False
    base: float = 0.0

    @property
    def baseline(self) -> float:
        return self.y1


@dataclass
class Page:
    index: int
    lines: list
    extras: list
    rect: fitz.Rect
    tables: list = field(default_factory=list)
    specks: list = field(default_factory=list)

    @property
    def text_measure(self):
        lines = [l for l in self.lines if l.x1 > l.x0]
        if not lines:
            box = self.content_box()
            return box.x0, box.x1
        return min(l.x0 for l in lines), max(l.x1 for l in lines)

    @property
    def content_top(self) -> float:
        return self.rect.y0 + 12

    @property
    def content_bottom(self) -> float:
        return self.rect.y1 - 14

    def content_box(self) -> fitz.Rect:
        return fitz.Rect(self.rect.x0 + 8, self.content_top,
                         self.rect.x1 - 8, self.content_bottom)


def _group_chars(chars):
    groups: list = []
    for ch in chars:
        if groups and abs(groups[-1][0][1][3] - ch[1][3]) <= 2.5:
            groups[-1].append(ch)
        else:
            groups.append([ch])

    def height(box):
        return box[3] - box[1]

    out: list = []
    for run in groups:
        if out and _is_subscript(out[-1], run):
            out[-1].extend(run)
            continue
        if out:
            taken, rest = _raised_runs(out[-1], run)
            if taken:
                out.pop()
                if rest:
                    out.append(rest)
                run = run + taken
        out.append(run)
    for line in out:
        line.sort(key=lambda t: t[1][0])
    return out


def _is_subscript(line, run) -> bool:
    if len(run) > 4:
        return False
    tall = max(b[3] - b[1] for _, b in line)
    if tall <= 0:
        return False
    if any((b[3] - b[1]) > tall * 0.9 for _, b in run):
        return False
    base = max(b[3] for _, b in line)
    drop = max(b[3] for _, b in run) - base
    if not 0 < drop <= tall * 0.9:
        return False
    left = min(b[0] for _, b in line)
    right = max(b[2] for _, b in line)
    return all(left - 2 <= b[0] and b[2] <= right + 2 for _, b in run)


def _raised_runs(prev, line):
    body = [t for t in line if t[0].strip()]
    if len(body) < 6:
        return [], prev
    tall = max(b[3] - b[1] for _, b in body)
    if tall <= 0:
        return [], prev
    base = max(b[3] for _, b in body)
    left = min(b[0] for _, b in body)
    right = max(b[2] for _, b in body)

    runs: list = []
    for ch in sorted(prev, key=lambda t: t[1][0]):
        if runs and ch[1][0] - max(b[2] for _, b in runs[-1]) <= SPACE_GAP:
            runs[-1].append(ch)
        else:
            runs.append([ch])

    taken, left_over = [], []
    for run in runs:
        vis = [t for t in run if t[0].strip()]
        if not vis or len(vis) > 4:
            left_over += run
            continue
        if any((b[3] - b[1]) > tall * 0.9 for _, b in vis):
            left_over += run
            continue
        rise = base - max(b[3] for _, b in vis)
        if not 0 < rise <= tall * 0.9:
            left_over += run
            continue
        r0 = min(b[0] for _, b in vis)
        r1 = max(b[2] for _, b in vis)
        if not (left - 2 <= r0 and r1 <= right + 2):
            left_over += run
            continue
        if any(b[0] < r1 - 0.5 and b[2] > r0 + 0.5 for _, b in body):
            left_over += run
            continue
        if not any(abs(b[2] - r0) <= 2.0 or abs(r1 - b[0]) <= 2.0 for _, b in body):
            left_over += run
            continue
        taken += run
    return taken, left_over


SPACE_GAP = 1.2

CELL_GAP = 8.0


def _cells_and_chars(group):
    group = sorted(group, key=lambda t: t[1][0])
    cell_chars = [[(group[0][0], group[0][1][0], group[0][1][2])]]
    prev_x1 = group[0][1][2]
    prev_c = group[0][0]
    for c, bx in group[1:]:
        gap = bx[0] - prev_x1
        if gap > CELL_GAP:
            cell_chars.append([])
        elif gap >= SPACE_GAP and prev_c.strip() and c.strip():
            cell_chars[-1].append((" ", None, None))
        cell_chars[-1].append((c, bx[0], bx[2]))
        prev_x1 = max(prev_x1, bx[2])
        prev_c = c

    cells = []
    seq = []
    for cell in cell_chars:
        while cell and not cell[0][0].strip():
            cell.pop(0)
        while cell and not cell[-1][0].strip():
            cell.pop()
        if not cell:
            continue
        cells.append(("".join(c for c, _, _ in cell), cell[0][1], cell[-1][2]))
        if seq:
            seq.append((" ", None, None))
        seq.extend(cell)
    if not cells:
        return [], []

    packed = []
    for ch, a, b in seq:
        if not ch.strip():
            if packed and not packed[-1][0].strip():
                continue
            packed.append((" ", a, b))
        else:
            packed.append((ch, a, b))
    while packed and not packed[0][0].strip():
        packed.pop(0)
    while packed and not packed[-1][0].strip():
        packed.pop()
    if not packed:
        return [], []
    return cells, packed


def read_page(doc: fitz.Document, index: int) -> Page:
    page = doc[index]
    raw = page.get_text("rawdict")

    glyphs: list = []
    chars = []
    origins = {}
    for block in raw.get("blocks", []):
        for ln in block.get("lines", []):
            for s in ln.get("spans", []):
                for ch in s.get("chars", []):
                    if ch.get("c", "").strip():
                        glyphs.append(fitz.Rect(ch["bbox"]))
                for ch in s.get("chars", []):
                    c = ch.get("c")
                    if not c:
                        continue
                    bx = ch["bbox"]
                    if not c.strip() and (bx[2] - bx[0]) < 1.0:
                        continue
                    chars.append((c, bx))
                    origins[(bx[0], bx[3])] = ch["origin"][1]

    chars.sort(key=lambda t: (round(t[1][3], 1), t[1][0]))
    groups = _group_chars(chars)

    _CELL = 16.0
    grid: dict = {}
    for g in glyphs:
        for gx in range(int(g.x0 // _CELL), int(g.x1 // _CELL) + 1):
            for gy in range(int(g.y0 // _CELL), int(g.y1 // _CELL) + 1):
                grid.setdefault((gx, gy), []).append(g)

    def is_glyph(r: fitz.Rect) -> bool:
        need = _area(r) * _TEXT_COVERAGE
        seen = set()
        for gx in range(int(r.x0 // _CELL), int(r.x1 // _CELL) + 1):
            for gy in range(int(r.y0 // _CELL), int(r.y1 // _CELL) + 1):
                for g in grid.get((gx, gy), ()):
                    key = (g.x0, g.y0, g.x1, g.y1)
                    if key in seen:
                        continue
                    seen.add(key)
                    if _area(r & g) >= need:
                        return True
        return False

    drawings = page.get_drawings()
    bars = []
    for item in drawings:
        r = fitz.Rect(item["rect"])
        if r.width >= 3.0 and r.height <= 1.8 and r.width > r.height * 4:
            if not is_glyph(r):
                bars.append(r)

    lines: list = []
    used_bars: list = []
    for group in groups:
        group.sort(key=lambda t: t[1][0])
        cells, packed = _cells_and_chars(group)
        if not cells or not packed:
            continue
        text = "".join(c for c, _, _ in packed)

        bottom = max(t[1][3] for t in group)
        top = min(t[1][1] for t in group)
        spans = []
        for r in bars:
            if not (r.y1 <= bottom + 0.8 and r.y0 >= bottom - (bottom - top) * 0.5 - 1.0):
                continue
            idx = [i for i, (ch, a, b) in enumerate(packed)
                   if a is not None and b > r.x0 - 0.8 and a < r.x1 + 0.8]
            if len(idx) < 2:
                continue
            spans.append((min(idx), max(idx) + 1))
            used_bars.append(r)

        bases = sorted(origins.get((t[1][0], t[1][3]), bottom) for t in group)
        lines.append(Line(
            text=text,
            x0=min(t[1][0] for t in group),
            y0=top,
            x1=max(t[1][2] for t in group),
            y1=bottom,
            cells=cells,
            underlines=_merge_spans(spans),
            char_boxes=[(a, b) if a is not None else None for _, a, b in packed],
            base=bases[len(bases) // 2],
        ))

    lines.sort(key=lambda l: (round(l.y0, 1), l.x0))

    cutoff = 0.0
    for ln in lines:
        if ln.x0 < 60 and ln.text.strip().lower() == "question":
            cutoff = ln.y1
            break

    claimed = {(round(r.x0, 2), round(r.y0, 2), round(r.x1, 2), round(r.y1, 2))
               for r in used_bars}

    extras = []
    specks = []
    for item in drawings:
        r = fitz.Rect(item["rect"])
        if r.y1 <= cutoff:
            continue
        if r.width < 1.2 and r.height < 1.2:
            if r.width > 0 and r.height > 0 and not is_glyph(r):
                specks.append(r)
            continue
        if (round(r.x0, 2), round(r.y0, 2), round(r.x1, 2), round(r.y1, 2)) in claimed:
            continue
        if not is_glyph(r):
            extras.append(r)

    for info in page.get_images(full=True):
        try:
            rects = page.get_image_rects(info[0])
        except Exception:
            continue
        for r in rects:
            r = fitz.Rect(r)
            if r.is_empty or not r.is_valid or r.width <= 1 or r.height <= 1:
                continue
            if r.y1 <= cutoff:
                continue
            extras.append(r)

    extras = _mark_bullets(lines, extras)

    tables = [t for t in find_tables(bars) if t[1][0] > cutoff]
    return Page(index=index, lines=lines, extras=extras, rect=page.rect,
                tables=tables, specks=specks)


def _mark_bullets(lines, extras):
    hits = []
    for gi, r in enumerate(extras):
        if not (1.5 <= r.width <= 6 and 1.5 <= r.height <= 6):
            continue
        if max(r.width, r.height) > min(r.width, r.height) * 1.6:
            continue
        if any(o is not r and o.x0 - 3.5 < r.x1 and r.x0 < o.x1 + 3.5
               and o.y0 < r.y1 and r.y0 < o.y1 for o in extras):
            continue
        mid = (r.y0 + r.y1) / 2
        for li, ln in enumerate(lines):
            if not ln.text.strip():
                continue
            if r.x1 <= ln.x0 + 1 and r.x0 >= ln.x0 - 26 and ln.y0 - 2 <= mid <= ln.y1 + 2:
                if not any(o is not r and o.x0 >= r.x1 - 0.5 and o.x1 <= ln.x0 + 1
                           and o.y0 < ln.y1 and ln.y0 < o.y1 for o in extras):
                    hits.append((li, gi, round(r.x0)))
                break

    by_indent = {}
    for li, gi, x in hits:
        by_indent.setdefault(x, []).append((li, gi))

    painted = set()
    for group in by_indent.values():
        if len({li for li, _ in group}) < 2:
            continue
        for li, gi in group:
            lines[li].bullet = True
            painted.add(gi)
    if not painted:
        return extras
    return [r for i, r in enumerate(extras) if i not in painted]


@dataclass
class Block:
    kind: str
    text: str = ""
    page: int = -1
    rect: tuple = ()
    underlines: list = field(default_factory=list)
    rows: list = field(default_factory=list)
    centred: bool = False
    inline: list = field(default_factory=list)


@dataclass
class RawQuestion:
    id: str
    assessment: str = ""
    test: str = ""
    domain: str = ""
    skill: str = ""
    difficulty: str = ""
    kind: str = "multiple_choice"
    stimulus: list = field(default_factory=list)
    prompt: list = field(default_factory=list)
    choices: list = field(default_factory=list)
    correct_answer: str = ""
    rationale: list = field(default_factory=list)


_ID_RE = re.compile(r"Question ID:\s*(\S+)", re.I)
_CHOICE_RE = re.compile(r"^([ABCD])[.)](\s|$)")


def _question_id(page: Page):
    for ln in page.lines[:3]:
        m = _ID_RE.search(ln.text)
        if m:
            return m.group(1)
    return None


def _is_label(line: Line, label: str) -> bool:
    return line.x0 < 60 and line.text.strip().lower() == label.lower()


def _find_anchors(page: Page, page_index: int):
    out = []
    for ln in page.lines:
        for kind in ("question", "answer", "rationale"):
            if _is_label(ln, kind):
                out.append((kind, page_index, ln))
        if ln.x0 < 60 and re.match(r"correct answer\s*:", ln.text.strip(), re.I):
            out.append(("correct_answer", page_index, ln))
    return out


def parse(doc: fitz.Document, progress=None):
    pages = []
    for i in range(doc.page_count):
        pages.append(read_page(doc, i))
        if progress:
            progress(0.05 + 0.35 * (i + 1) / max(1, doc.page_count),
                     Lf("Reading page %1$d of %2$d", i + 1, doc.page_count))

    starts = [i for i, p in enumerate(pages) if _question_id(p)]
    if not starts:
        return []

    questions = []
    for n, start in enumerate(starts):
        end = starts[n + 1] if n + 1 < len(starts) else len(pages)
        q = _parse_question(pages[start:end])
        if q:
            questions.append(q)
        if progress:
            progress(0.4 + 0.3 * (n + 1) / len(starts),
                     Lf("Question %1$d of %2$d", n + 1, len(starts)))
    return questions


def _parse_question(pages):
    first = pages[0]
    qid = _question_id(first)
    if not qid:
        return None

    q = RawQuestion(id=qid)
    _read_metadata(first, q)

    anchors = []
    for pi, page in enumerate(pages):
        anchors += _find_anchors(page, pi)
    anchors.sort(key=lambda a: (a[1], a[2].y0))
    seen = set()
    ordered = []
    for a in anchors:
        if a[0] in seen:
            continue
        seen.add(a[0])
        ordered.append(a)

    qa = next((a for a in ordered if a[0] == "question"), None)
    if qa is None:
        return None

    doc_end = (len(pages) - 1, pages[-1].content_bottom)

    def section_end(i):
        if i + 1 < len(ordered):
            nxt = ordered[i + 1]
            return (nxt[1], nxt[2].y0)
        return doc_end

    qi = ordered.index(qa)
    whole = "math" in (q.test or "").lower()
    body = _blocks(pages, (qa[1], qa[2].y1), section_end(qi), whole)

    ai = next((i for i, a in enumerate(ordered) if a[0] == "answer"), None)
    if ai is not None:
        q.kind = "multiple_choice"
        q.choices = _parse_choices(pages, (ordered[ai][1], ordered[ai][2].y1),
                                   section_end(ai), whole)
        if not q.choices:
            q.kind = "student_response"
    else:
        q.kind = "student_response"

    ca = next((a for a in ordered if a[0] == "correct_answer"), None)
    if ca is not None:
        m = re.search(r"correct answer\s*:\s*(.+)", ca[2].text, re.I)
        if m:
            q.correct_answer = m.group(1).strip()

    rationale_text = ""
    ri = next((i for i, a in enumerate(ordered) if a[0] == "rationale"), None)
    if ri is not None:
        start = (ordered[ri][1], ordered[ri][2].y1)
        end = section_end(ri)
        q.rationale = _blocks(pages, start, end, whole)
        rationale_text = _plain_text(pages, start, end)

    if not q.correct_answer:
        q.correct_answer = _infer_answer(rationale_text, q.kind) or ""

    _split_body(body, q)
    return q


def _read_metadata(page: Page, q: RawQuestion):
    header = None
    for i, ln in enumerate(page.lines):
        if any(c[0].lower() == "assessment" for c in ln.cells):
            header = (i, ln)
            break
    if not header:
        return
    idx, hline = header
    columns = hline.cells
    values = [""] * len(columns)

    for ln in page.lines[idx + 1:]:
        if _is_label(ln, "Question"):
            break
        for text, x0, _ in ln.cells:
            best = min(range(len(columns)), key=lambda c: abs(columns[c][1] - x0))
            values[best] = (values[best] + " " + text).strip() if values[best] else text

    def value(name):
        for i, c in enumerate(columns):
            if c[0].lower() == name.lower():
                return values[i].strip() if i < len(values) else ""
        return ""

    q.assessment = value("Assessment")   # data, not copy
    q.test = value("Test")               # data, not copy
    q.domain = value("Domain")           # data, not copy
    q.skill = value("Skill")             # data, not copy
    q.difficulty = value("Difficulty")   # data, not copy


def _span(pages, pi, start, end):
    page = pages[pi]
    top = start[1] if pi == start[0] else page.content_top
    bottom = end[1] if pi == end[0] else page.content_bottom
    return top, bottom


def _lines_in(page: Page, top, bottom):
    return [l for l in page.lines if l.y0 >= top - 1 and l.y1 <= bottom + 1]


def _blocks(pages, start, end, whole=False):
    out = []
    for pi in range(start[0], end[0] + 1):
        top, bottom = _span(pages, pi, start, end)
        out += _make_blocks(pages[pi], _lines_in(pages[pi], top, bottom),
                            top, bottom, None, False, whole)
    return out


def _plain_text(pages, start, end):
    parts = []
    for pi in range(start[0], end[0] + 1):
        top, bottom = _span(pages, pi, start, end)
        parts += [l.text for l in _lines_in(pages[pi], top, bottom)]
    return " ".join(parts)


def _make_blocks(page: Page, lines, band_top, band_bottom, left_edge, strip_prefix,
                 whole=False):
    painted = [r for r in page.extras
               if band_bottom >= (r.y0 + r.y1) / 2 >= band_top]
    graphics = [r for r in painted if r.width > 1.5 and r.height > 1.5]
    rules = [r for r in painted if not (r.width > 1.5 and r.height > 1.5)]

    tables = [t for t in page.tables
              if any(band_top - 1 <= y <= band_bottom + 1 for y in t[1])]
    if tables and _drawn_inside(tables, graphics):
        tables = []
    if tables:
        recovered = _blocks_around_tables(page, lines, tables, graphics, rules,
                                          strip_prefix, whole)
        rebuilt = [b for b in recovered if b.kind == "table"]
        if len(rebuilt) == len(tables):
            return recovered

    if not graphics:
        joined, marks = _join_lines(lines, strip_prefix)
        return [Block("text", text=joined, underlines=marks)] if joined else []
    return _art_blocks(page, lines, graphics, rules, left_edge, strip_prefix, whole)


def _art_blocks(page: Page, lines, graphics, rules, left_edge, strip_prefix,
                whole=False):
    pictures = _pictures(lines, graphics, rules, whole)
    claimed = set()
    for p in pictures:
        claimed |= p["lines"]

    out = []
    run = []

    def flush():
        nonlocal run, strip_prefix
        if not run:
            return
        joined, marks = _join_lines(run, strip_prefix)
        if joined:
            out.append(Block("text", text=joined, underlines=marks))
        strip_prefix = False
        run = []

    pending = sorted(pictures, key=lambda p: p["y0"])
    for i, ln in enumerate(lines):
        while pending and pending[0]["y0"] <= ln.y0:
            flush()
            block = _picture_block(page, pending.pop(0), lines,
                                   left_edge if not out else None, whole)
            if block:
                out.append(block)
                strip_prefix = False
        if i not in claimed:
            run.append(ln)
    flush()
    for p in pending:
        block = _picture_block(page, p, lines, left_edge if not out else None,
                               whole)
        if block:
            out.append(block)

    if not out:
        joined, marks = _join_lines(lines, strip_prefix)
        return [Block("text", text=joined, underlines=marks)] if joined else []
    return out


def _pictures(lines, graphics, rules, whole=False):
    out = [{"y0": r.y0, "y1": r.y1, "left": r.x0, "right": r.x1,
            "rects": [r], "lines": set()} for r in graphics]
    if not out:
        return []

    def coalesce():
        out.sort(key=lambda p: p["y0"])
        merged = []
        for p in out:
            if merged and p["y0"] <= merged[-1]["y1"] + 4:
                last = merged[-1]
                last["y0"] = min(last["y0"], p["y0"])
                last["y1"] = max(last["y1"], p["y1"])
                last["left"] = min(last["left"], p["left"])
                last["right"] = max(last["right"], p["right"])
                last["rects"] += p["rects"]
                last["lines"] |= p["lines"]
            else:
                merged.append(p)
        out[:] = merged

    def inside(ln, left, right):
        return (left - 6 <= ln.x0 and ln.x1 <= right + 6) or ln.x0 >= 100

    def absorb_rules():
        grew = False
        for r in rules:
            for p in out:
                if not (r.y1 >= p["y0"] - 4 and r.y0 <= p["y1"] + 4
                        and r.x1 >= p["left"] - 6 and r.x0 <= p["right"] + 6):
                    continue
                if (r.x0 >= p["left"] - 0.5 and r.x1 <= p["right"] + 0.5
                        and r.y0 >= p["y0"] - 0.5 and r.y1 <= p["y1"] + 0.5):
                    continue
                p["left"] = min(p["left"], r.x0)
                p["right"] = max(p["right"], r.x1)
                p["y0"] = min(p["y0"], r.y0)
                p["y1"] = max(p["y1"], r.y1)
                grew = True
                break
        return grew

    def bridge():
        out.sort(key=lambda p: p["y0"])
        merged = []
        joined = False
        for p in out:
            if merged:
                last = merged[-1]
                if max(last["left"], p["left"]) < min(last["right"], p["right"]):
                    left = min(last["left"], p["left"])
                    right = max(last["right"], p["right"])
                    between = [i for i, ln in enumerate(lines)
                               if ln.y1 > last["y1"] and ln.y0 < p["y0"]]
                    if all(inside(lines[i], left, right) for i in between):
                        last["y0"] = min(last["y0"], p["y0"])
                        last["y1"] = max(last["y1"], p["y1"])
                        last["left"] = left
                        last["right"] = right
                        last["rects"] += p["rects"]
                        last["lines"] |= p["lines"] | set(between)
                        joined = True
                        continue
            merged.append(p)
        out[:] = merged
        return joined

    coalesce()

    claimed = set()
    grew = True
    while grew:
        grew = absorb_rules()
        for i, ln in enumerate(lines):
            if i in claimed:
                continue
            for p in out:
                through = ln.y1 >= p["y0"] and ln.y0 <= p["y1"]
                beside = (inside(ln, p["left"], p["right"])
                          and ln.y1 >= p["y0"] - 36 and ln.y0 <= p["y1"] + 36)
                if not (through or beside):
                    continue
                p["y0"] = min(p["y0"], ln.y0)
                p["y1"] = max(p["y1"], ln.y1)
                p["lines"].add(i)
                claimed.add(i)
                grew = True
                break
        coalesce()
        if bridge():
            grew = True
            for p in out:
                claimed |= p["lines"]

    if whole:
        _grow_to_paragraphs(lines, out, graphics + rules)
        coalesce()
    return out


def _leaves_indented_run(lines, i, base_indent) -> bool:
    if i < 2 or i >= len(lines):
        return False
    edge = base_indent + 6
    return (lines[i].x0 <= edge
            and lines[i - 1].x0 > edge
            and lines[i - 2].x0 > edge)


_TERMINAL = (".", "!", "?", '."', ".'", ".\u201d", ".\u2019",
             '?"', '!"', "?\u201d", "!\u201d")

_ABBREVIATIONS = frozenset((
    "St", "Mr", "Mrs", "Ms", "Dr", "Prof", "Rev", "Hon", "Sr", "Jr",
    "Gen", "Col", "Capt", "Lt", "Sgt", "Mt", "Ft", "Ave", "Rd",
    "No", "Vol", "Fig", "Ed", "Eds", "Trans", "Univ", "Dept",
    "Co", "Inc", "Ltd",
))


def _ends_on_abbreviation(t: str) -> bool:
    if not t.endswith("."):
        return False
    stem = t[:-1]
    token = ""
    for ch in reversed(stem):
        if not ch.isalpha():
            break
        token = ch + token
    if not token:
        return False
    if len(token) == 1 and token.isascii() and token.isupper():
        return True
    return token in _ABBREVIATIONS


def _ends_sentence(text: str) -> bool:
    t = text.strip()
    return t.endswith(_TERMINAL) and not _ends_on_abbreviation(t)


def _opens_indented_block(a: Line, b: Line, base_indent: float) -> bool:
    if not _ends_sentence(a.text):
        return False
    if abs(a.x0 - base_indent) > 0.5:
        return False
    step = b.x0 - a.x0
    return 6 <= step <= 12


_ROMAN_MARKERS = ("II", "III", "IV")


def _opens_numbered_statement(text: str) -> bool:
    t = text.strip()
    head, dot, rest = t.partition(".")
    return bool(dot) and head in _ROMAN_MARKERS and rest.startswith(" ")


def _paragraph_break(a: Line, b: Line, base_indent: float,
                     lines=None, i=None) -> bool:
    gap = b.y0 - a.y0
    if gap > 22:
        return True
    if lines is not None and i is not None \
            and _leaves_indented_run(lines, i, base_indent):
        return True
    if _opens_numbered_statement(b.text):
        return True
    if _opens_indented_block(a, b, base_indent):
        return True
    return b.x0 > base_indent + 12 and gap > 17


def _grow_to_paragraphs(lines, pictures, marks=()):
    if not lines:
        return
    base_indent = min(l.x0 for l in lines)
    near = _closed_up(lines, marks)
    for p in pictures:
        for i in sorted(p["lines"]):
            if near[i].x0 > base_indent + 6:
                continue
            j = i
            while j > 0 and not _paragraph_break(near[j - 1], near[j], base_indent,
                                                 near, j):
                j -= 1
                p["lines"].add(j)
            j = i
            while (j + 1 < len(lines)
                   and not _paragraph_break(near[j], near[j + 1], base_indent,
                                            near, j + 1)):
                j += 1
                p["lines"].add(j)
        for i in p["lines"]:
            p["y0"] = min(p["y0"], lines[i].y0)
            p["y1"] = max(p["y1"], lines[i].y1)
            p["left"] = min(p["left"], lines[i].x0)
            p["right"] = max(p["right"], lines[i].x1)


def _picture_block(page: Page, picture, lines, left_edge, measure=False):
    x0 = left_edge if left_edge is not None else float("inf")
    x1 = -float("inf")
    y0 = float("inf")
    y1 = -float("inf")
    for i in picture["lines"]:
        ln = lines[i]
        x0 = min(x0, ln.x0); x1 = max(x1, ln.x1)
        y0 = min(y0, ln.y0); y1 = max(y1, ln.y1)
    for r in picture["rects"]:
        x0 = min(x0, r.x0); x1 = max(x1, r.x1)
        y0 = min(y0, r.y0); y1 = max(y1, r.y1)
    x0 = min(x0, picture["left"])
    x1 = max(x1, picture["right"])
    y0 = min(y0, picture["y0"])
    y1 = max(y1, picture["y1"])

    art_left, art_right = x0, x1
    if measure and left_edge is None and picture["lines"]:
        measure_left, measure_right = page.text_measure
        x0 = min(x0, measure_left)
        x1 = max(x1, measure_right)
    elif left_edge is not None:
        x0 = left_edge
    if not (x1 > x0 and y1 > y0):
        return None

    for r in page.extras:
        if r.y0 >= y0 and r.y1 <= y1 and r.x1 > x0 and r.x0 < x1:
            x0 = min(x0, r.x0)
            x1 = max(x1, r.x1)

    rect = fitz.Rect(x0 - 1.5, y0 - 2, x1 + 1.5, y1 + 2) & page.content_box()
    if rect.width <= 2 or rect.height <= 2:
        return None
    return Block("image", page=page.index,
                 rect=(rect.x0, rect.y0, rect.x1, rect.y1),
                 centred=_is_centred(page, art_left, art_right, x0, x1),
                 inline=(_inline(page, picture, lines, left_edge) or []) if measure else [])


def _is_centred(page, art_left, art_right, x0, x1, slack=14.0) -> bool:
    left, right = page.text_measure
    if right - left <= 0 or art_right <= art_left:
        return False
    if art_left <= left + slack:
        return False
    if x1 - x0 >= (right - left) - slack:
        return False
    middle = (left + right) / 2
    return abs((art_left + art_right) / 2 - middle) <= slack


def _table_span(edges, bottoms):
    step = (bottoms[1] - bottoms[0]) if len(bottoms) > 1 else 20
    return bottoms[0] - step, bottoms[-1]


def _title_lines_above(before, inside, margin):
    if not before or not inside:
        return []
    top_of_table = min(l.y0 for l in inside)
    taken = []
    for line in reversed(before):
        if line.x0 <= margin + 40:
            break
        if top_of_table - line.y0 > 16:
            break
        taken.append(line)
        top_of_table = line.y0
    return list(reversed(taken))


SENTENCE_TAIL = ".:?!”’\"'"


def _prose_above_first_rule(inside, first_rule, margin):
    above = sorted((l for l in inside if l.y1 <= first_rule),
                   key=lambda l: (l.y0, l.x0))
    run = []
    for line in above:
        if line.x0 > margin + 1.0:
            break
        run.append(line)
    if not run or not run[-1].text.rstrip()[-1:] in SENTENCE_TAIL:
        return []
    return run


def _blocks_around_tables(page, lines, tables, graphics, rules, strip_prefix,
                          whole=False):
    spans = sorted((_table_span(e, b), e, b) for e, b in tables)
    body_margin = min((l.x0 for l in lines), default=0.0)
    out = []
    remaining = list(lines)
    state = {"strip": strip_prefix}

    def emit(run):
        if not run:
            return
        top = min(l.y0 for l in run) - 12
        bottom = max(l.y1 for l in run) + 6
        art = [r for r in graphics if top <= (r.y0 + r.y1) / 2 <= bottom]
        if not art:
            joined, marks = _join_lines(run, state["strip"])
            if joined:
                out.append(Block("text", text=joined, underlines=marks))
        else:
            near = [r for r in rules if top <= (r.y0 + r.y1) / 2 <= bottom]
            out.extend(_art_blocks(page, run, art, near, None, state["strip"],
                                   whole))
        state["strip"] = False

    for (top, bottom), edges, bottoms in spans:
        before = [l for l in remaining if l.y1 <= top]
        inside = [l for l in remaining if top < l.y1 <= bottom + 1.0]
        remaining = [l for l in remaining if l.y1 > bottom + 1.0]

        returned = _prose_above_first_rule(inside, bottoms[0], body_margin)
        if returned:
            given = set(map(id, returned))
            before = before + returned
            inside = [l for l in inside if id(l) not in given]

        lifted = _title_lines_above(before, inside, body_margin)
        if lifted:
            before = before[:len(before) - len(lifted)]

        emit(before)
        rows = table_rows(inside, edges, bottoms)
        rows = [r for r in rows if any(c.strip() for c in r)]
        if lifted:
            head = " ".join(l.text.strip() for l in lifted).strip()
            if rows and len(rows[0]) == 1:
                rows[0] = [(head + " " + rows[0][0]).strip()]
            elif head:
                rows.insert(0, [head])
        if rows:
            out.append(Block("table", rows=rows))

    emit(remaining)
    return out


def _join_lines(lines, strip_prefix):
    if not lines:
        return "", []
    base_indent = min(l.x0 for l in lines)
    parts, current, prev_y, prev_ln = [], "", None, None
    part_spans, cur_spans = [], []

    for i, ln in enumerate(lines):
        raw = ln.text
        text = raw.strip()
        if not text:
            continue
        trim = len(raw) - len(raw.lstrip())
        if strip_prefix and i == 0:
            stripped = _CHOICE_RE.sub("", text, count=1)
            trim += len(text) - len(stripped)
            text = stripped
        if ln.bullet:
            text = "• " + text
            trim -= 2

        new_para = False
        if prev_y is not None:
            gap = ln.y0 - prev_y
            if gap > 22:
                new_para = True
            elif ln.x0 > base_indent + 12 and gap > 17:
                new_para = True
            elif _leaves_indented_run(lines, i, base_indent):
                new_para = True
            elif _opens_indented_block(prev_ln, ln, base_indent):
                new_para = True
        if ln.bullet:
            new_para = True
        if _opens_numbered_statement(ln.text):
            new_para = True
        if new_para and current:
            parts.append(current)
            part_spans.append(cur_spans)
            current, cur_spans = "", []

        if not current:
            offset = 0
            current = text
        elif current.endswith("-"):
            offset = len(current)
            current += text
        else:
            current += " "
            offset = len(current)
            current += text

        for s, e in ln.underlines:
            s, e = s - trim, e - trim
            s = max(0, min(s, len(text)))
            e = max(0, min(e, len(text)))
            if e > s:
                cur_spans.append((offset + s, offset + e))
        prev_y = ln.y0
        prev_ln = ln

    if current:
        parts.append(current)
        part_spans.append(cur_spans)

    text_out, spans_out, pos = "", [], 0
    for idx, part in enumerate(parts):
        if idx:
            text_out += "\n\n"
            pos += 2
        text_out += part
        spans_out += [(s + pos, e + pos) for s, e in part_spans[idx]]
        pos += len(part)

    lead = len(text_out) - len(text_out.lstrip())
    text_out = text_out.strip()
    if lead:
        spans_out = [(s - lead, e - lead) for s, e in spans_out]
    n = len(text_out)
    spans_out = [(max(0, s), min(e, n)) for s, e in spans_out]
    return text_out, _tidy_spans(text_out, spans_out)


def _tidy_spans(text: str, spans):
    clean = []
    for s, e in spans:
        while s < e and text[s].isspace():
            s += 1
        while e > s and text[e - 1].isspace():
            e -= 1
        if e > s:
            clean.append((s, e))

    merged = []
    for s, e in sorted(clean):
        if merged and text[merged[-1][1]:s].strip() == "" and s - merged[-1][1] <= 2:
            merged[-1] = (merged[-1][0], max(merged[-1][1], e))
        else:
            merged.append((s, e))
    return _merge_spans(merged)


def _parse_choices(pages, start, end, whole=False):
    entries = []
    for pi in range(start[0], end[0] + 1):
        top, bottom = _span(pages, pi, start, end)
        for ln in _lines_in(pages[pi], top, bottom):
            entries.append((pi, ln))

    starts = [(i, _CHOICE_RE.match(e[1].text.strip()).group(1))
              for i, e in enumerate(entries)
              if e[1].x0 < 60 and _CHOICE_RE.match(e[1].text.strip())]
    if not starts:
        return []

    out = []
    for n, (idx, letter) in enumerate(starts):
        stop = starts[n + 1][0] if n + 1 < len(starts) else len(entries)
        slice_ = entries[idx:stop]
        if not slice_:
            continue
        first_pi, first_ln = slice_[0]
        prev = entries[starts[n - 1][0]] if n > 0 else None
        nxt = entries[starts[n + 1][0]] if n + 1 < len(starts) else None

        blocks = []
        end_pi = nxt[0] if nxt else end[0]
        for pi in range(first_pi, end_pi + 1):
            on_page = [l for p, l in slice_ if p == pi]
            sec_top, sec_bottom = _span(pages, pi, start, end)

            band_top = sec_top
            if pi == first_pi and prev and prev[0] == pi:
                band_top = _divide(pages[pi], prev[1].y1, first_ln.y1)
            band_bottom = sec_bottom
            if nxt and nxt[0] == pi:
                band_bottom = _divide(pages[pi],
                                      on_page[-1].y1 if on_page else sec_top,
                                      nxt[1].y1)

            left = None
            if pi == first_pi:
                left = _choice_content_left(first_ln, pages[pi], band_top, band_bottom)

            blocks += _make_blocks(pages[pi], on_page, band_top, band_bottom,
                                   left, pi == first_pi, whole)
        out.append((letter, blocks))
    return out


def _divide(page: Page, upper: float, lower: float) -> float:
    midpoint = (upper + lower) / 2
    if lower - upper <= 4:
        return midpoint

    spans = []
    for ln in page.lines:
        if ln.y0 < lower and ln.y1 > upper:
            spans.append((max(ln.y0, upper), min(ln.y1, lower)))
    for r in page.extras:
        if r.width > 1.5 and r.height > 1.5 and r.y0 < lower and r.y1 > upper:
            spans.append((max(r.y0, upper), min(r.y1, lower)))
    if not spans:
        return midpoint

    runs = []
    for top, bottom in sorted(spans):
        if runs and top <= runs[-1][1] + 2:
            runs[-1] = (runs[-1][0], max(runs[-1][1], bottom))
        else:
            runs.append((top, bottom))

    index = None
    for i, (top, bottom) in enumerate(runs):
        if bottom >= lower - 0.1:
            index = i
            break
    if index is None or index == 0:
        return midpoint
    above_bottom = runs[index - 1][1]
    mine_top = runs[index][0]
    if mine_top - above_bottom < 2:
        return midpoint
    return (above_bottom + mine_top) / 2


def _choice_content_left(first_line: Line, page: Page, band_top, band_bottom):
    after_label = None
    match = _CHOICE_RE.match(first_line.text)
    if match:
        i = match.end()
        while i < len(first_line.text) and first_line.text[i].isspace():
            i += 1
        boxes = first_line.char_boxes
        if i < len(boxes) and boxes[i]:
            after_label = boxes[i][0]

    candidates = []
    for text, x0, x1 in first_line.cells:
        if _CHOICE_RE.match(text + " "):
            if len(text) <= 2:
                continue
            if after_label is not None:
                candidates.append(after_label)
                continue
        candidates.append(x0)
    for r in page.extras:
        mid = (r.y0 + r.y1) / 2
        if band_top <= mid <= band_bottom:
            candidates.append(r.x0)

    floor = after_label if after_label is not None else first_line.x0
    if not candidates:
        return floor
    low = min(candidates)
    return max(low - 1, floor) if low >= floor else low


def _split_body(body, q: RawQuestion):
    subject = "math" if "math" in q.test.lower() else "reading_writing"
    if subject != "reading_writing" or not body:
        q.stimulus, q.prompt = [], body
        return

    last = body[-1]
    if last.kind != "text":
        q.stimulus, q.prompt = body, []
        return

    paragraphs = last.text.split("\n\n")
    if len(paragraphs) >= 2:
        head = "\n\n".join(paragraphs[:-1])
        q.stimulus = body[:-1] + [_cut(last, 0, len(head))]
        q.prompt = [_cut(last, len(last.text) - len(paragraphs[-1]), len(last.text))]
        return

    head, tail = _split_last_sentence(last.text)
    if head and tail:
        q.stimulus = body[:-1] + [_cut(last, 0, len(head))]
        q.prompt = [_cut(last, len(last.text) - len(tail), len(last.text))]
    else:
        q.stimulus = body[:-1]
        q.prompt = [last]


def _cut(block: Block, start: int, end: int) -> Block:
    text = block.text[start:end]
    lead = len(text) - len(text.lstrip())
    trail = len(text) - len(text.rstrip())
    keep = []
    for s, e in block.underlines:
        s = max(s, start + lead) - start - lead
        e = min(e, end - trail) - start - lead
        if e > s:
            keep.append((s, e))
    return Block("text", text=text.strip(), underlines=_merge_spans(keep))


def _split_last_sentence(text: str):
    t = text.strip()
    if not t.endswith("?"):
        return None, None
    for m in reversed(list(re.finditer(r"[.?!]\s+(?=[A-Z])", t))):
        head = t[:m.end()].strip()
        tail = t[m.end():].strip()
        if head and tail:
            return head, tail
    return None, None


def _infer_answer(text: str, kind: str):
    if not text:
        return None
    if kind == "multiple_choice":
        for pattern in ("Choice {} is the best answer", "Choice {} is correct"):
            for letter in "ABCD":
                if pattern.format(letter) in text:
                    return letter
        return None
    m = re.search(r"correct answer is\s*([-\d.,/]+)", text, re.I)
    if m:
        value = m.group(1).strip(" .,")
        if value:
            return value
    return accepted_forms(text)


def accepted_forms(text: str):
    m = re.search(r"to enter a correct answer", text, re.I)
    if not m:
        return None
    before = text[:m.start()]
    for tail in (" are examples", " is an example", " are ways", " is a way"):
        cut = before.lower().rfind(tail)
        if cut != -1:
            before = before[:cut]
            break
    start = before.lower().rfind("note that ")
    before = before[start + len("note that "):] if start != -1 else before[-120:]

    values = []
    for token in re.split(r"[,\s]+", before):
        t = token.rstrip(".")
        if (t and len(t) <= 12 and any(ch.isdigit() for ch in t)
                and all(ch.isdigit() or ch in "./-" for ch in t)
                and t not in values):
            values.append(t)
    return ", ".join(values) if values else None


def stray_edge_rows(pix):
    w, h = pix.width, pix.height
    band = min(int(round(2 * RENDER_SCALE)) + 2, h // 3)
    if band <= 0 or w <= 0:
        return 0, 0
    dense_limit = max(1, int(w * 0.25))
    run_limit = max(2, int(w * 0.15))
    n = pix.n
    samples = pix.samples
    stride = pix.stride

    def shape(y):
        base = y * stride
        count = longest = current = 0
        for x in range(w):
            p = base + x * n
            if (samples[p] < 240 or samples[p + 1] < 240 or samples[p + 2] < 240):
                count += 1
                current += 1
                if current > longest:
                    longest = current
            else:
                current = 0
        return count, longest

    def run(row_at):
        found = 0
        for i in range(band):
            c, longest = row_at(i)
            if c == 0:
                return found
            if longest > run_limit or c > dense_limit:
                return 0
            found = i + 1
        return 0

    return run(lambda i: shape(i)), run(lambda i: shape(h - 1 - i))


PROSE_X_HEIGHT = 4.75

_SAME_LINE = 6.0

_ISLAND = "\ufffc"

_ASCENT = 6.8
_DESCENT = 1.9


def _top(ln):
    return ln.base - _ASCENT


def _bottom(ln):
    return ln.base + _DESCENT


_TALLEST_MARK = 48.0
_ISLAND_GAP = 3.5
_LINE_REACH = 14.0
_ISLAND_PAD = 0.75


def _line_of(lines, r):
    cy = (r.y0 + r.y1) / 2
    best, dist = None, _LINE_REACH
    for k, ln in enumerate(lines):
        d = abs((_top(ln) + _bottom(ln)) / 2 - cy)
        if d <= dist:
            best, dist = k, d
    return best


def _overhangs(lines, marks):
    up = [0.0] * len(lines)
    down = [0.0] * len(lines)
    left = [ln.x0 for ln in lines]
    for r in marks:
        if r.height > _TALLEST_MARK:
            continue
        k = _line_of(lines, r)
        if k is None:
            continue
        up[k] = max(up[k], _top(lines[k]) - r.y0)
        down[k] = max(down[k], r.y1 - _bottom(lines[k]))
        left[k] = min(left[k], r.x0)
    return up, down, left


_LINE_LEFT = 18.0


def _closed_up(lines, marks):
    up, down, left = _overhangs(lines, marks)
    out, shift = [], 0.0
    for k, ln in enumerate(lines):
        if k:
            over = up[k] + down[k - 1]
            if ln.base - lines[k - 1].base - over <= _LINE_LEFT:
                shift += over
        out.append(Line(text=ln.text, x0=left[k], y0=ln.y0 - shift, x1=ln.x1,
                        y1=ln.y1 - shift, cells=ln.cells, underlines=ln.underlines,
                        char_boxes=ln.char_boxes, bullet=ln.bullet,
                        base=ln.base - shift))
    return out


def _on_one_baseline(lines):
    out, first = [], []
    for ln in sorted(lines, key=lambda l: l.base):
        if out and ln.base - first[-1] <= _SAME_LINE:
            a = out[-1]
            items = sorted(
                [(b[0] if b else None, c, b) for c, b in zip(a.text, a.char_boxes) if b]
                + [(b[0], c, b) for c, b in zip(ln.text, ln.char_boxes) if b],
                key=lambda t: t[0])
            text, boxes = [], []
            for x, c, b in items:
                if boxes and x - boxes[-1][1] > SPACE_GAP and text[-1].strip() and c.strip():
                    text.append(" "); boxes.append(None)
                text.append(c); boxes.append(b)
            base = a.base if len(a.text) >= len(ln.text) else ln.base
            out[-1] = Line(text="".join(text), x0=min(a.x0, ln.x0), y0=min(a.y0, ln.y0),
                           x1=max(a.x1, ln.x1), y1=max(a.y1, ln.y1), cells=a.cells,
                           underlines=a.underlines + ln.underlines,
                           char_boxes=[(b[0], b[1]) if b else None for b in boxes],
                           bullet=a.bullet or ln.bullet, base=base)
        else:
            out.append(ln)
            first.append(ln.base)
    return out


def _inline(page: Page, picture, lines, left_edge):
    idx = sorted(i for i in picture["lines"] if lines[i].text.strip())
    if not idx:
        return None
    own = _on_one_baseline([lines[i] for i in idx])
    if any(ln.underlines for ln in own):
        return None
    top = min(picture["y0"], min(_top(ln) for ln in own))
    bottom = max(picture["y1"], max(_bottom(ln) for ln in own))
    left = min(picture["left"], min(ln.x0 for ln in own)) - 2
    right = max(picture["right"], max(ln.x1 for ln in own)) + 2
    if left_edge is not None:
        left = left_edge - 2
    marks = [r for r in page.extras + page.specks
             if top - 2 <= (r.y0 + r.y1) / 2 <= bottom + 2
             and left <= (r.x0 + r.x1) / 2 <= right]
    if not marks or any(r.height > _TALLEST_MARK for r in marks):
        return None

    by_line = [[] for _ in own]
    loose = []
    for r in marks:
        k = _line_of(own, r)
        (loose if k is None else by_line[k]).append(r)

    islands = []
    dropped = [set() for _ in own]
    for k, ln in enumerate(own):
        mine = []
        for r in sorted(by_line[k], key=lambda r: r.x0):
            if mine and r.x0 - mine[-1][2] < _ISLAND_GAP:
                m = mine[-1]
                mine[-1] = [m[0], min(m[1], r.y0), max(m[2], r.x1), max(m[3], r.y1), k]
            else:
                mine.append([r.x0, r.y0, r.x1, r.y1, k])
        grew = True
        while grew:
            grew = False
            for j, box in enumerate(ln.char_boxes):
                if box is None or j in dropped[k]:
                    continue
                for m in mine:
                    if box[1] > m[0] + 0.5 and box[0] < m[2] - 0.5:
                        dropped[k].add(j)
                        if not ln.text[j].strip():
                            continue
                        m[0] = min(m[0], box[0])
                        m[2] = max(m[2], box[1])
                        m[1] = min(m[1], _top(ln))
                        m[3] = max(m[3], _bottom(ln))
                        grew = True
                        break
        islands += mine

    for k, ln in enumerate(own):
        run = 0
        for j in range(len(ln.text)):
            run = run + 1 if j in dropped[k] and ln.text[j].strip() else 0
            if run >= 2:
                return None

    displays = []
    for r in sorted(loose, key=lambda r: r.y0):
        if displays and r.y0 < displays[-1][3] + 1:
            d = displays[-1]
            displays[-1] = [min(d[0], r.x0), min(d[1], r.y0), max(d[2], r.x1),
                            max(d[3], r.y1), None]
        else:
            displays.append([r.x0, r.y0, r.x1, r.y1, None])
    for d in displays:
        if any(_bottom(ln) > d[1] + 1 and _top(ln) < d[3] - 1 for ln in own):
            return None

    for m in islands:
        for k, ln in enumerate(own):
            if k == m[4] or not (_bottom(ln) > m[1] + 1 and _top(ln) < m[3] - 1):
                continue
            for j, box in enumerate(ln.char_boxes):
                if box and j not in dropped[k] and box[1] > m[0] and box[0] < m[2]:
                    return None
        for n in islands:
            if n is not m and n[4] != m[4] and n[0] < m[2] and m[0] < n[2] \
                    and n[1] < m[3] and m[1] < n[3]:
                return None
    if not islands and not displays:
        return None

    order = []
    virtual = []
    for k, ln in enumerate(own):
        items, last = [], ln.x0
        for j, (ch, box) in enumerate(zip(ln.text, ln.char_boxes)):
            if j in dropped[k]:
                continue
            if box is not None and left_edge is not None and box[1] <= left_edge:
                continue
            x = box[0] if box else last
            last = box[1] if box else last
            items.append((x, ch, box))
        mine = sorted((m for m in islands if m[4] == k), key=lambda m: m[0])
        for m in mine:
            items.append((m[0], _ISLAND, (m[0], m[2])))
        items.sort(key=lambda t: t[0])
        text, boxes = [], []
        for n, (x, ch, box) in enumerate(items):
            if ch == _ISLAND:
                while text and not text[-1].strip():
                    text.pop(); boxes.pop()
                prev = next((b for b in reversed(boxes) if b), None)
                if prev is not None and box[0] - prev[1] > SPACE_GAP:
                    text.append(" "); boxes.append(None)
                text.append(ch); boxes.append(box)
                nxt = next((b for _, c, b in items[n + 1:] if b and c.strip()), None)
                if nxt is not None and nxt[0] - box[1] > SPACE_GAP:
                    text.append(" "); boxes.append(None)
                continue
            if not ch.strip() and text and (not text[-1].strip() or text[-1] == _ISLAND):
                continue
            text.append(ch); boxes.append(box)
        while text and not text[0].strip():
            text.pop(0); boxes.pop(0)
        while text and not text[-1].strip():
            text.pop(); boxes.pop()
        if not text:
            continue
        xs = [b[0] for b in boxes if b]
        order += mine
        virtual.append(Line(text="".join(text), x0=min(xs), y0=_top(ln), x1=ln.x1,
                            y1=_bottom(ln), cells=[], char_boxes=boxes,
                            bullet=ln.bullet, base=ln.base))

    def cut(m):
        ln = own[m[4]]
        x0, x1 = m[0] - _ISLAND_PAD, m[2] + _ISLAND_PAD
        for j, box in enumerate(ln.char_boxes):
            if box is None or j in dropped[m[4]]:
                continue
            if box[1] <= m[0] + 0.5:
                x0 = max(x0, box[1] + 0.2)
            elif box[0] >= m[2] - 0.5:
                x1 = min(x1, box[0] - 0.2)
        y0, y1 = m[1] - _ISLAND_PAD, m[3] + _ISLAND_PAD
        for n in islands:
            if n[4] == m[4] or not (n[0] < x1 and x0 < n[2]):
                continue
            if n[1] >= m[3]:
                y1 = min(y1, n[1] - 0.2)
            elif n[3] <= m[1]:
                y0 = max(y0, n[3] + 0.2)
        return (x0, y0, x1, y1)

    def paragraphs(run):
        if not run:
            return []
        joined, _ = _join_lines(_closed_up(run, marks), False)
        out = []
        for part in joined.split("\n\n"):
            runs = []
            for n, piece in enumerate(part.split(_ISLAND)):
                if n:
                    if not order:
                        failed.append(True)
                        return []
                    m = order.pop(0)
                    rect = cut(m)
                    runs.append({"rect": rect, "depth": rect[3] - own[m[4]].base})
                if piece:
                    runs.append({"text": piece})
            if runs:
                out.append({"display": False, "runs": runs})
        return out

    failed = []
    out, run = [], []
    pending = list(displays)
    for ln in virtual:
        while pending and pending[0][1] < _top(ln):
            out += paragraphs(run); run = []
            d = pending.pop(0)
            rect = (d[0] - _ISLAND_PAD, d[1] - _ISLAND_PAD,
                    d[2] + _ISLAND_PAD, d[3] + _ISLAND_PAD)
            out.append({"display": True, "runs": [{"rect": rect, "depth": 0.0}]})
        run.append(ln)
    out += paragraphs(run)
    for d in pending:
        rect = (d[0] - _ISLAND_PAD, d[1] - _ISLAND_PAD,
                d[2] + _ISLAND_PAD, d[3] + _ISLAND_PAD)
        out.append({"display": True, "runs": [{"rect": rect, "depth": 0.0}]})
    if order or failed:
        return None
    return out


ISLAND_SCALE = 6.0


def _ink_bounds(pix):
    w, h, n = pix.width, pix.height, pix.n
    data = pix.samples
    stride = pix.stride

    def blank_row(y):
        row = data[y * stride:y * stride + w * n]
        return min(row) >= 247

    def blank_col(x, y0, y1):
        for y in range(y0, y1):
            o = y * stride + x * n
            if min(data[o:o + n]) < 247:
                return False
        return True

    top = 0
    while top < h and blank_row(top):
        top += 1
    if top == h:
        return 0, 0, 0, 0
    bottom = 0
    while blank_row(h - 1 - bottom):
        bottom += 1
    left = 0
    while blank_col(left, top, h - bottom):
        left += 1
    right = 0
    while blank_col(w - 1 - right, top, h - bottom):
        right += 1
    return (max(0, top - 1), max(0, bottom - 1), max(0, left - 1), max(0, right - 1))


def render_islands(doc: fitz.Document, page_index: int, rects, out_path: str):
    lists = doc.__dict__.setdefault("_satprep_display_lists", {})
    if page_index not in lists:
        lists.clear()
        lists[page_index] = doc[page_index].get_displaylist()
    pieces = []
    for rect in rects:
        clip = fitz.Rect(*rect)
        if clip.width <= 0.5 or clip.height <= 0.5:
            return None
        pix = lists[page_index].get_pixmap(matrix=fitz.Matrix(ISLAND_SCALE, ISLAND_SCALE),
                                           clip=clip, colorspace=fitz.csGRAY, alpha=False)
        top, bottom, left, right = _ink_bounds(pix)
        if top or bottom or left or right:
            r = fitz.IRect(pix.irect)
            box = fitz.IRect(r.x0 + left, r.y0 + top, r.x1 - right, r.y1 - bottom)
            cut = fitz.Pixmap(pix.colorspace, box, pix.alpha)
            cut.copy(pix, box)
            pix = cut
        pieces.append((pix, bottom))
    gap = 2
    width = max(p.width for p, _ in pieces)
    height = sum(p.height for p, _ in pieces) + gap * (len(pieces) - 1)
    sheet = fitz.Pixmap(fitz.csGRAY, fitz.IRect(0, 0, width, height), False)
    sheet.clear_with(255)
    out, y = [], 0
    for pix, bottom in pieces:
        pix.set_origin(0, y)
        sheet.copy(pix, fitz.IRect(0, y, pix.width, y + pix.height))
        out.append((y, pix.width, pix.height, pix.width / ISLAND_SCALE,
                    pix.height / ISLAND_SCALE, bottom / ISLAND_SCALE))
        y += pix.height + gap
    os.makedirs(os.path.dirname(out_path), exist_ok=True)
    from .safeio import atomic_write_bytes
    atomic_write_bytes(out_path, sheet.tobytes("png"))
    return out


def render_region(doc: fitz.Document, page_index: int, rect, out_path: str):
    page = doc[page_index]
    clip = fitz.Rect(*rect)
    if clip.width <= 1 or clip.height <= 1:
        return None
    pix = page.get_pixmap(matrix=fitz.Matrix(RENDER_SCALE, RENDER_SCALE),
                          clip=clip, alpha=False)
    top, bottom = stray_edge_rows(pix)
    if (top or bottom) and pix.height - top - bottom > 0:
        pix = _cropped(pix, top, bottom)
    os.makedirs(os.path.dirname(out_path), exist_ok=True)
    from .safeio import atomic_write_bytes
    atomic_write_bytes(out_path, pix.tobytes("png"))
    return pix.width, pix.height, clip.width


def _cropped(pix, top, bottom):
    r = fitz.IRect(pix.irect)
    box = fitz.IRect(r.x0, r.y0 + top, r.x1, r.y1 - bottom)
    out = fitz.Pixmap(pix.colorspace, box, pix.alpha)
    out.copy(pix, box)
    return out
