import Foundation
import CoreGraphics

struct PendingImage {
    var pageIndex: Int
    var rect: CGRect
    var centred: Bool = false
    var inline: [RawInlineParagraph] = []
}

enum RawBlock {
    case text(String, underlines: [Range<Int>] = [])
    case image(PendingImage)
    case table([[String]])

    var textValue: String? { if case .text(let t, _) = self { return t }; return nil }
    var marks: [Range<Int>] { if case .text(_, let u) = self { return u }; return [] }
}

struct RawQuestion {
    var id: String
    var assessment = ""
    var test = ""
    var domain = ""
    var skill = ""
    var difficulty = ""
    var kind: QuestionKind = .multipleChoice
    var stimulus: [RawBlock] = []
    var prompt: [RawBlock] = []
    var choices: [(letter: String, blocks: [RawBlock])] = []
    var correctAnswer = ""
    var rationale: [RawBlock] = []
    var pageIndices: [Int] = []
}

enum QuestionParser {
    static let version = 27


    static func parse(file: PDFFile) -> [RawQuestion] {
        let extractor = PageExtractor(file: file)
        var pages = [ExtractedPage]()
        for i in 0..<file.pages.count {
            if let p = extractor.extract(pageIndex: i) { pages.append(p) }
        }
        guard !pages.isEmpty else { return [] }

        var starts = [Int]()
        for (i, page) in pages.enumerated() where questionID(on: page) != nil {
            starts.append(i)
        }
        guard !starts.isEmpty else { return [] }

        var results = [RawQuestion]()
        for (n, startIdx) in starts.enumerated() {
            let endIdx = (n + 1 < starts.count) ? starts[n + 1] : pages.count
            let group = Array(pages[startIdx..<endIdx])
            if let q = parseQuestion(pages: group) { results.append(q) }
        }
        return results
    }

    private static func questionID(on page: ExtractedPage) -> String? {
        for line in page.lines.prefix(3) {
            let t = line.text.trimmed
            guard let r = t.range(of: "Question ID:", options: .caseInsensitive) else { continue }
            let id = String(t[r.upperBound...]).trimmed
            if !id.isEmpty { return id }
        }
        return nil
    }

    private struct Loc: Comparable {
        var page: Int
        var y: Double
        static func < (a: Loc, b: Loc) -> Bool {
            a.page != b.page ? a.page < b.page : a.y > b.y
        }
    }

    private static func parseQuestion(pages: [ExtractedPage]) -> RawQuestion? {
        guard let first = pages.first, let id = questionID(on: first) else { return nil }
        var q = RawQuestion(id: id)
        q.pageIndices = pages.map(\.index)

        readMetadata(from: first, into: &q)

        var anchors: [(kind: AnchorKind, loc: Loc, line: TextLine)] = []
        for (pi, page) in pages.enumerated() {
            for a in findAnchors(on: page) {
                anchors.append((a.kind, Loc(page: pi, y: a.line.y), a.line))
            }
        }
        anchors.sort { $0.loc < $1.loc }
        var seenKinds = Set<String>()
        anchors = anchors.filter { seenKinds.insert(String(describing: $0.kind)).inserted }

        guard let questionIdx = anchors.firstIndex(where: { $0.kind == .question }) else { return nil }

        let documentEnd = Loc(page: pages.count - 1, y: pages[pages.count - 1].contentBottom)

        func sectionEnd(after i: Int) -> Loc {
            i + 1 < anchors.count ? anchors[i + 1].loc : documentEnd
        }

        let whole = q.test.lowercased().contains("math")

        let bodyBlocks = blocks(in: pages, from: anchors[questionIdx].loc,
                                to: sectionEnd(after: questionIdx), whole: whole)

        if let answerIdx = anchors.firstIndex(where: { $0.kind == .answer }) {
            q.kind = .multipleChoice
            q.choices = parseChoices(in: pages, from: anchors[answerIdx].loc,
                                     to: sectionEnd(after: answerIdx), whole: whole)
            if q.choices.isEmpty { q.kind = .studentResponse }
        } else {
            q.kind = .studentResponse
        }

        if let ca = anchors.first(where: { $0.kind == .correctAnswer }) {
            let t = ca.line.text
            if let r = t.range(of: "Correct Answer:", options: .caseInsensitive) {
                q.correctAnswer = String(t[r.upperBound...]).trimmed
            }
        }

        var rationaleText = ""
        if let ratIdx = anchors.firstIndex(where: { $0.kind == .rationale }) {
            let from = anchors[ratIdx].loc
            let to = sectionEnd(after: ratIdx)
            q.rationale = blocks(in: pages, from: from, to: to, whole: whole)
            rationaleText = plainText(in: pages, from: from, to: to)
        }

        if q.correctAnswer.isEmpty {
            q.correctAnswer = inferAnswer(fromText: rationaleText, kind: q.kind) ?? ""
        }

        splitBody(bodyBlocks, into: &q)
        return q
    }

    private static func span(on pageIndex: Int, in pages: [ExtractedPage],
                             from: Loc, to: Loc) -> (top: Double, bottom: Double) {
        let page = pages[pageIndex]
        let top = (pageIndex == from.page) ? from.y : page.contentTop
        let bottom = (pageIndex == to.page) ? to.y : page.contentBottom
        return (top, bottom)
    }

    private static func blocks(in pages: [ExtractedPage], from: Loc, to: Loc,
                               whole: Bool = false) -> [RawBlock] {
        guard from.page <= to.page, from.page >= 0, to.page < pages.count else { return [] }
        var out = [RawBlock]()
        for pi in from.page...to.page {
            let (top, bottom) = span(on: pi, in: pages, from: from, to: to)
            out += blocks(on: pages[pi], between: bottom, and: top, whole: whole)
        }
        return out
    }

    private static func plainText(in pages: [ExtractedPage], from: Loc, to: Loc) -> String {
        guard from.page <= to.page, from.page >= 0, to.page < pages.count else { return "" }
        var parts = [String]()
        for pi in from.page...to.page {
            let (top, bottom) = span(on: pi, in: pages, from: from, to: to)
            parts.append(plainText(on: pages[pi], between: bottom, and: top))
        }
        return parts.joined(separator: " ")
    }

    private static func readMetadata(from page: ExtractedPage, into q: inout RawQuestion) {
        guard let headerIdx = page.lines.firstIndex(where: { line in
            line.cells.contains { $0.text.caseInsensitiveCompare("Assessment") == .orderedSame }
        }) else { return }

        let header = page.lines[headerIdx]
        let columns = header.cells
        guard columns.count >= 2 else { return }

        var values = [String](repeating: "", count: columns.count)
        for line in page.lines[(headerIdx + 1)...] {
            if isLabel(line, "Question") { break }
            for cell in line.cells {
                var best = 0
                var bestDist = Double.greatestFiniteMagnitude
                for (i, col) in columns.enumerated() {
                    let d = abs(col.minX - cell.minX)
                    if d < bestDist { bestDist = d; best = i }
                }
                if values[best].isEmpty { values[best] = cell.text }
                else { values[best] += " " + cell.text }
            }
        }

        func value(_ name: String) -> String {
            guard let i = columns.firstIndex(where: {
                $0.text.caseInsensitiveCompare(name) == .orderedSame
            }), i < values.count else { return "" }
            return values[i].trimmed
        }

        q.assessment = value("Assessment")
        q.test = value("Test")
        q.domain = value("Domain")
        q.skill = value("Skill")
        q.difficulty = value("Difficulty")
    }

    private enum AnchorKind { case question, answer, correctAnswer, rationale }
    private struct Anchor { var kind: AnchorKind; var line: TextLine }

    private static func isLabel(_ line: TextLine, _ label: String) -> Bool {
        line.minX < 60 && line.text.trimmed.caseInsensitiveCompare(label) == .orderedSame
    }

    private static func findAnchors(on page: ExtractedPage) -> [Anchor] {
        var out = [Anchor]()
        for line in page.lines {
            if isLabel(line, "Question") { out.append(Anchor(kind: .question, line: line)) }
            else if isLabel(line, "Answer") { out.append(Anchor(kind: .answer, line: line)) }
            else if isLabel(line, "Rationale") { out.append(Anchor(kind: .rationale, line: line)) }
            else if line.minX < 60,
                    line.text.range(of: "Correct Answer:", options: [.caseInsensitive, .anchored]) != nil {
                out.append(Anchor(kind: .correctAnswer, line: line))
            }
        }
        var seen = Set<String>()
        return out.filter { a in
            let key = String(describing: a.kind)
            if seen.contains(key) { return false }
            seen.insert(key); return true
        }
    }

    private static func parseChoices(in pages: [ExtractedPage], from: Loc, to: Loc,
                                     whole: Bool = false)
        -> [(letter: String, blocks: [RawBlock])] {
        guard from.page <= to.page, from.page >= 0, to.page < pages.count else { return [] }

        struct Entry { var page: Int; var line: TextLine }
        var entries = [Entry]()
        for pi in from.page...to.page {
            let (top, bottom) = span(on: pi, in: pages, from: from, to: to)
            for line in pages[pi].lines.filter({ $0.y < top - 1 && $0.y > bottom + 1 })
                                       .sorted(by: { $0.y > $1.y }) {
                entries.append(Entry(page: pi, line: line))
            }
        }

        var starts = [(index: Int, letter: String)]()
        for (i, e) in entries.enumerated() {
            guard e.line.minX < 60, let letter = leadingChoiceLetter(e.line.text) else { continue }
            starts.append((i, letter))
        }
        guard !starts.isEmpty else { return [] }

        var out = [(letter: String, blocks: [RawBlock])]()
        for (n, start) in starts.enumerated() {
            let endIndex = (n + 1 < starts.count) ? starts[n + 1].index : entries.count
            let slice = Array(entries[start.index..<endIndex])
            guard let firstEntry = slice.first else { continue }

            let previous = n > 0 ? entries[starts[n - 1].index] : nil
            let next = (n + 1 < starts.count) ? entries[starts[n + 1].index] : nil

            var blocks = [RawBlock]()
            let endPage = next?.page ?? to.page
            for pi in firstEntry.page...endPage {
                let onPage = slice.filter { $0.page == pi }.map(\.line)
                let (sectionTop, sectionBottom) = span(on: pi, in: pages, from: from, to: to)

                var bandTop = sectionTop
                if pi == firstEntry.page, let previous, previous.page == pi {
                    bandTop = divide(pages[pi], upper: previous.line.y,
                                     lower: firstEntry.line.y)
                }
                var bandBottom = sectionBottom
                if let next, next.page == pi {
                    bandBottom = divide(pages[pi], upper: onPage.last?.y ?? sectionTop,
                                        lower: next.line.y)
                }

                let leftEdge = pi == firstEntry.page
                    ? choiceContentLeft(firstEntry.line, page: pages[pi],
                                        bandTop: bandTop, bandBottom: bandBottom)
                    : nil

                blocks += makeBlocks(page: pages[pi], lines: onPage,
                                     bandTop: bandTop, bandBottom: bandBottom,
                                     leftEdge: leftEdge,
                                     stripPrefix: pi == firstEntry.page,
                                     whole: whole)
            }
            out.append((letter: start.letter, blocks: blocks))
        }
        return out
    }

    private static func divide(_ page: ExtractedPage, upper: Double, lower: Double) -> Double {
        let midpoint = (upper + lower) / 2
        guard upper - lower > 4 else { return midpoint }

        var spans = [(top: Double, bottom: Double)]()
        for l in page.lines where l.y - 4 < upper && l.y + 10 > lower {
            spans.append((min(l.y + 10, upper), max(l.y - 4, lower)))
        }
        for g in page.contentGraphics
        where g.width > 1.5 && g.height > 1.5
            && Double(g.minY) < upper && Double(g.maxY) > lower {
            spans.append((min(Double(g.maxY), upper), max(Double(g.minY), lower)))
        }
        guard !spans.isEmpty else { return midpoint }

        var runs = [(top: Double, bottom: Double)]()
        for span in spans.sorted(by: { $0.top > $1.top }) {
            if var last = runs.last, span.top >= last.bottom - 2 {
                last.bottom = min(last.bottom, span.bottom)
                runs[runs.count - 1] = last
            } else {
                runs.append(span)
            }
        }

        guard let index = runs.lastIndex(where: { $0.top >= lower - 0.1 }),
              index > runs.startIndex else { return midpoint }
        let above = runs[index - 1]
        let mine = runs[index]
        guard above.bottom - mine.top >= 2 else { return midpoint }
        return (above.bottom + mine.top) / 2
    }

    private static func leadingChoiceLetter(_ text: String) -> String? {
        let t = text.trimmed
        guard t.count >= 2 else { return nil }
        let chars = Array(t)
        guard let first = chars.first, "ABCD".contains(first) else { return nil }
        guard chars[1] == "." || chars[1] == ")" else { return nil }
        return String(first)
    }

    private static func choiceContentLeft(_ firstLine: TextLine, page: ExtractedPage,
                                          bandTop: Double, bandBottom: Double) -> Double {
        var afterLabel: Double? = nil
        var labelEnd: Double? = nil
        if leadingChoiceLetter(firstLine.text) != nil {
            labelEnd = firstLine.charBoxes.prefix(2).compactMap { $0 }.last?.upperBound
            let chars = Array(firstLine.text)
            var i = 2
            while i < chars.count, chars[i].isWhitespace { i += 1 }
            if i < firstLine.charBoxes.count, let box = firstLine.charBoxes[i] {
                afterLabel = box.lowerBound
            } else if let last = firstLine.charBoxes.prefix(2).compactMap({ $0 }).last {
                afterLabel = last.upperBound
            }
        }

        var candidates = [Double]()
        for run in firstLine.runs {
            let t = run.text.trimmed
            if leadingChoiceLetter(t + " x") != nil || "ABCD".contains(t.first ?? " ") {
                if t.count <= 2 {
                    continue
                }
                if let afterLabel {
                    candidates.append(afterLabel)
                    continue
                }
            }
            candidates.append(run.x)
        }
        for g in page.contentGraphics where g.midY < bandTop && g.midY > bandBottom {
            if let end = labelEnd ?? afterLabel, Double(g.maxX) <= end + 0.5 { continue }
            candidates.append(g.minX)
        }

        let floor = afterLabel ?? firstLine.minX
        guard let left = candidates.min() else { return floor }
        return left >= floor ? max(left - 1, floor) : left
    }

    private static func blocks(on page: ExtractedPage,
                               between bottom: Double, and top: Double,
                               whole: Bool = false) -> [RawBlock] {
        let lines = page.lines.filter { $0.y < top - 1 && $0.y > bottom + 1 }
                              .sorted { $0.y > $1.y }
        return makeBlocks(page: page, lines: lines, bandTop: top - 4, bandBottom: bottom + 4,
                          leftEdge: nil, stripPrefix: false, whole: whole)
    }

    private static func makeBlocks(page: ExtractedPage, lines: [TextLine],
                                   bandTop: Double, bandBottom: Double,
                                   leftEdge: Double?, stripPrefix: Bool,
                                   whole: Bool = false) -> [RawBlock] {
        let painted = page.contentGraphics.filter { g in
            g.midY <= bandTop && g.midY >= bandBottom
        }
        let graphics = painted.filter { $0.width > 1.5 && $0.height > 1.5 }
        let rules = painted.filter { !($0.width > 1.5 && $0.height > 1.5) }

        var tables = page.tables.filter { grid in
            grid.rowRules.contains { $0 <= bandTop + 1 && $0 >= bandBottom - 1 }
        }
        if !tables.isEmpty, drawnInside(tables, graphics) { tables = [] }
        if !tables.isEmpty {
            let recovered = blocksAroundTables(page, lines, tables, graphics: graphics,
                                               rules: rules, stripPrefix: stripPrefix,
                                               whole: whole)
            let rebuilt = recovered.filter { if case .table = $0 { return true }; return false }
            if rebuilt.count == tables.count { return recovered }
        }

        if graphics.isEmpty {
            let (joined, marks) = joinLines(lines, stripChoicePrefix: stripPrefix)
            return joined.isEmpty ? [] : [.text(joined, underlines: marks)]
        }
        return artBlocks(page: page, lines: lines, graphics: graphics, rules: rules,
                         leftEdge: leftEdge, stripPrefix: stripPrefix, whole: whole)
    }

    private static func artBlocks(page: ExtractedPage, lines: [TextLine],
                                  graphics: [CGRect], rules: [CGRect],
                                  leftEdge: Double?, stripPrefix: Bool,
                                  whole: Bool = false) -> [RawBlock] {
        let pictures = pictures(in: lines, graphics: graphics, rules: rules, whole: whole)
        var out = [RawBlock]()
        var strip = stripPrefix
        var claimed = Set<Int>()
        for p in pictures { claimed.formUnion(p.lines) }

        func flush(_ run: [TextLine]) {
            guard !run.isEmpty else { return }
            let (joined, marks) = joinLines(run, stripChoicePrefix: strip)
            if !joined.isEmpty { out.append(.text(joined, underlines: marks)) }
            strip = false
        }

        var run = [TextLine]()
        var pending = pictures.sorted { $0.top > $1.top }
        for (i, line) in lines.enumerated() {
            while let next = pending.first, next.top >= line.y + 10 {
                flush(run); run = []
                if let block = imageBlock(page: page, picture: next,
                                          lines: lines,
                                          leftEdge: out.isEmpty ? leftEdge : nil,
                                          measure: whole) {
                    out.append(block)
                    strip = false
                }
                pending.removeFirst()
            }
            if !claimed.contains(i) { run.append(line) }
        }
        flush(run)
        for p in pending {
            if let block = imageBlock(page: page, picture: p, lines: lines,
                                      leftEdge: out.isEmpty ? leftEdge : nil,
                                      measure: whole) {
                out.append(block)
            }
        }

        if out.isEmpty {
            let (joined, marks) = joinLines(lines, stripChoicePrefix: stripPrefix)
            return joined.isEmpty ? [] : [.text(joined, underlines: marks)]
        }
        return out
    }

    static func leavesIndentedRun(_ lines: [TextLine], _ i: Int,
                                  baseIndent: Double) -> Bool {
        guard i >= 2, i < lines.count else { return false }
        let edge = baseIndent + 6
        return lines[i].minX <= edge
            && lines[i - 1].minX > edge
            && lines[i - 2].minX > edge
    }

    static func opensNumberedStatement(_ text: String) -> Bool {
        let t = text.trimmed
        guard let dot = t.firstIndex(of: ".") else { return false }
        guard ["II", "III", "IV"].contains(String(t[t.startIndex..<dot]))
        else { return false }
        let after = t.index(after: dot)
        return after < t.endIndex && t[after] == " "
    }

    static let terminalSuffixes = [".", "!", "?", ".\"", ".'", ".\u{201D}", ".\u{2019}",
                                   "?\"", "!\"", "?\u{201D}", "!\u{201D}"]

    static let abbreviations: Set<String> = [
        "St", "Mr", "Mrs", "Ms", "Dr", "Prof", "Rev", "Hon", "Sr", "Jr",
        "Gen", "Col", "Capt", "Lt", "Sgt", "Mt", "Ft", "Ave", "Rd",
        "No", "Vol", "Fig", "Ed", "Eds", "Trans", "Univ", "Dept",
        "Co", "Inc", "Ltd",
    ]

    static func endsOnAbbreviation(_ t: String) -> Bool {
        guard t.hasSuffix(".") else { return false }
        let stem = t.dropLast()
        let token = String(stem.reversed().prefix(while: { $0.isLetter }).reversed())
        guard !token.isEmpty else { return false }
        if token.count == 1, let c = token.first, c.isASCII, c.isUppercase {
            return true
        }
        return abbreviations.contains(token)
    }

    static func endsSentence(_ text: String) -> Bool {
        let t = text.trimmed
        guard terminalSuffixes.contains(where: { t.hasSuffix($0) }) else { return false }
        return !endsOnAbbreviation(t)
    }

    static func opensIndentedBlock(_ a: TextLine, _ b: TextLine,
                                   baseIndent: Double) -> Bool {
        guard endsSentence(a.text) else { return false }
        guard abs(a.minX - baseIndent) <= 0.5 else { return false }
        let step = b.minX - a.minX
        return step >= 6 && step <= 12
    }

    static func paragraphBreak(_ a: TextLine, _ b: TextLine,
                               baseIndent: Double,
                               lines: [TextLine]? = nil,
                               index: Int? = nil) -> Bool {
        let gap = a.y - b.y
        if gap > 22 { return true }
        if let lines, let index,
           leavesIndentedRun(lines, index, baseIndent: baseIndent) { return true }
        if opensNumberedStatement(b.text) { return true }
        if opensIndentedBlock(a, b, baseIndent: baseIndent) { return true }
        return b.minX > baseIndent + 12 && gap > 17
    }

    static func growToParagraphs(_ lines: [TextLine], _ pictures: inout [Picture],
                                 marks: [CGRect] = []) {
        guard !lines.isEmpty else { return }
        let baseIndent = lines.map(\.minX).min()!
        let near = closedUp(lines, marks)
        for pi in pictures.indices {
            for i in pictures[pi].lines.sorted() {
                if near[i].minX > baseIndent + 6 { continue }
                var j = i
                while j > 0,
                      !paragraphBreak(near[j - 1], near[j], baseIndent: baseIndent,
                                      lines: near, index: j) {
                    j -= 1
                    pictures[pi].lines.insert(j)
                }
                j = i
                while j + 1 < lines.count,
                      !paragraphBreak(near[j], near[j + 1], baseIndent: baseIndent,
                                      lines: near, index: j + 1) {
                    j += 1
                    pictures[pi].lines.insert(j)
                }
            }
            for i in pictures[pi].lines {
                pictures[pi].bottom = min(pictures[pi].bottom, lines[i].y - 4)
                pictures[pi].top = max(pictures[pi].top, lines[i].y + 10)
                pictures[pi].artLeft = min(pictures[pi].artLeft, lines[i].minX)
                pictures[pi].artRight = max(pictures[pi].artRight, lines[i].maxX)
            }
        }
    }

    struct Picture {
        var top: Double
        var bottom: Double
        var artLeft: Double
        var artRight: Double
        var rects: [CGRect]
        var lines: Set<Int> = []
    }

    private static func pictures(in lines: [TextLine], graphics: [CGRect],
                                 rules: [CGRect], whole: Bool = false) -> [Picture] {
        var out = graphics.map {
            Picture(top: Double($0.maxY), bottom: Double($0.minY),
                    artLeft: Double($0.minX), artRight: Double($0.maxX), rects: [$0])
        }
        guard !out.isEmpty else { return [] }

        func coalesce() {
            out.sort { $0.top > $1.top }
            var merged = [Picture]()
            for p in out {
                if var last = merged.last, p.top >= last.bottom - 4 {
                    last.top = max(last.top, p.top)
                    last.bottom = min(last.bottom, p.bottom)
                    last.artLeft = min(last.artLeft, p.artLeft)
                    last.artRight = max(last.artRight, p.artRight)
                    last.rects += p.rects
                    last.lines.formUnion(p.lines)
                    merged[merged.count - 1] = last
                } else {
                    merged.append(p)
                }
            }
            out = merged
        }
        func inside(_ line: TextLine, _ left: Double, _ right: Double) -> Bool {
            (line.minX >= left - 6 && line.maxX <= right + 6) || line.minX >= 100
        }

        func absorbRules() -> Bool {
            var grew = false
            for r in rules {
                for (pi, p) in out.enumerated() {
                    guard Double(r.maxY) >= p.bottom - 4, Double(r.minY) <= p.top + 4,
                          Double(r.maxX) >= p.artLeft - 6, Double(r.minX) <= p.artRight + 6,
                          Double(r.minX) < p.artLeft - 0.5 || Double(r.maxX) > p.artRight + 0.5
                            || Double(r.maxY) > p.top + 0.5 || Double(r.minY) < p.bottom - 0.5
                    else { continue }
                    out[pi].artLeft = min(p.artLeft, Double(r.minX))
                    out[pi].artRight = max(p.artRight, Double(r.maxX))
                    out[pi].top = max(p.top, Double(r.maxY))
                    out[pi].bottom = min(p.bottom, Double(r.minY))
                    grew = true
                    break
                }
            }
            return grew
        }

        func bridge() -> Bool {
            out.sort { $0.top > $1.top }
            var merged = [Picture]()
            var joined = false
            for p in out {
                if var last = merged.last,
                   max(last.artLeft, p.artLeft) < min(last.artRight, p.artRight) {
                    let left = min(last.artLeft, p.artLeft)
                    let right = max(last.artRight, p.artRight)
                    let between = lines.indices.filter {
                        lines[$0].y - 4 < last.bottom && lines[$0].y + 10 > p.top
                    }
                    let joinable = between.allSatisfy { inside(lines[$0], left, right) }
                        && p.lines.allSatisfy { inside(lines[$0], left, right) }
                    if joinable {
                        last.top = max(last.top, p.top)
                        last.bottom = min(last.bottom, p.bottom)
                        last.artLeft = left
                        last.artRight = right
                        last.rects += p.rects
                        last.lines.formUnion(p.lines)
                        last.lines.formUnion(between)
                        merged[merged.count - 1] = last
                        joined = true
                        continue
                    }
                }
                merged.append(p)
            }
            out = merged
            return joined
        }
        coalesce()

        var claimed = Set<Int>()
        var grew = true
        while grew {
            grew = absorbRules()
            for (i, line) in lines.enumerated() where !claimed.contains(i) {
                let lineTop = line.y + 10, lineBottom = line.y - 4
                for (pi, p) in out.enumerated() {
                    let through = lineTop >= p.bottom && lineBottom <= p.top
                    let beside = inside(line, p.artLeft, p.artRight)
                        && lineBottom <= p.top + 36 && lineTop >= p.bottom - 36
                    guard through || beside else { continue }
                    out[pi].top = max(p.top, lineTop)
                    out[pi].bottom = min(p.bottom, lineBottom)
                    out[pi].lines.insert(i)
                    claimed.insert(i)
                    grew = true
                    break
                }
            }
            coalesce()
            if bridge() {
                grew = true
                for p in out { claimed.formUnion(p.lines) }
            }
        }

        if whole {
            growToParagraphs(lines, &out, marks: graphics + rules)
            coalesce()
        }
        return out
    }

    private static func imageBlock(page: ExtractedPage, picture: Picture,
                                   lines: [TextLine], leftEdge: Double?,
                                   measure: Bool = false) -> RawBlock? {
        var minX = leftEdge ?? Double.greatestFiniteMagnitude
        var maxX = -Double.greatestFiniteMagnitude
        var minY = Double.greatestFiniteMagnitude
        var maxY = -Double.greatestFiniteMagnitude

        for i in picture.lines {
            let l = lines[i]
            let sideways = l.text.count > 1
                && l.maxX - l.minX < Double(l.text.count) * l.size * 0.2
            let pad = sideways ? l.size * 1.5 : 0
            minX = min(minX, l.minX - pad); maxX = max(maxX, l.maxX + pad)
            minY = min(minY, l.y - 4); maxY = max(maxY, l.y + 10)
        }
        for g in picture.rects {
            minX = min(minX, Double(g.minX)); maxX = max(maxX, Double(g.maxX))
            minY = min(minY, Double(g.minY)); maxY = max(maxY, Double(g.maxY))
        }
        minX = min(minX, picture.artLeft); maxX = max(maxX, picture.artRight)
        minY = min(minY, picture.bottom);  maxY = max(maxY, picture.top)

        let artLeft = minX, artRight = maxX
        if measure, leftEdge == nil, !picture.lines.isEmpty {
            let m = page.textMeasure
            minX = min(minX, m.left)
            maxX = max(maxX, m.right)
        } else if let le = leftEdge {
            minX = le
        }
        guard minX.isFinite, maxX > minX, maxY > minY else { return nil }

        for g in page.contentGraphics
        where Double(g.maxY) <= maxY && Double(g.minY) >= minY
            && Double(g.maxX) > minX && Double(g.minX) < maxX {
            minX = min(minX, Double(g.minX))
            maxX = max(maxX, Double(g.maxX))
        }

        let x0 = leftEdge.map { max(minX - 1.5, $0) } ?? (minX - 1.5)
        let rect = CGRect(x: x0, y: minY - 2,
                          width: (maxX + 1.5) - x0,
                          height: (maxY - minY) + 4)
            .intersection(page.contentBox)

        guard rect.width > 2, rect.height > 2 else { return nil }
        return .image(PendingImage(pageIndex: page.index, rect: rect,
                                   centred: isCentred(measure: page.textMeasure,
                                                      artLeft: artLeft, artRight: artRight,
                                                      minX: minX, maxX: maxX),
                                   inline: measure
                                       ? inlineParagraphs(page: page, picture: picture,
                                                          lines: lines, leftEdge: leftEdge) ?? []
                                       : []))
    }

    static func isCentred(measure: (left: Double, right: Double),
                          artLeft: Double, artRight: Double,
                          minX: Double, maxX: Double, slack: Double = 14) -> Bool {
        let (left, right) = measure
        guard right - left > 0, artRight > artLeft else { return false }
        if artLeft <= left + slack { return false }
        if maxX - minX >= (right - left) - slack { return false }
        let middle = (left + right) / 2
        return abs((artLeft + artRight) / 2 - middle) <= slack
    }

    private static func tableBounds(_ grid: TableGrid) -> CGRect {
        let span = tableSpan(grid)
        let x0 = grid.edges.first ?? 0, x1 = grid.edges.last ?? 0
        return CGRect(x: x0, y: span.bottom, width: x1 - x0, height: span.top - span.bottom)
    }

    static func drawnInside(_ tables: [TableGrid], _ graphics: [CGRect]) -> Bool {
        for grid in tables where !grid.rowRules.isEmpty {
            let b = tableBounds(grid)
            for r in graphics where Double(r.minX) >= Double(b.minX) - 1
                && Double(r.maxX) <= Double(b.maxX) + 1
                && Double(r.minY) >= Double(b.minY) - 1
                && Double(r.maxY) <= Double(b.maxY) + 1 {
                return true
            }
        }
        return false
    }

    private static func tableSpan(_ grid: TableGrid) -> (top: Double, bottom: Double) {
        let rules = grid.rowRules
        let step = rules.count > 1 ? (rules[0] - rules[1]) : 20
        return (rules[0] + step, rules[rules.count - 1])
    }

    private static let sentenceTail: Set<Character> = [".", ":", "?", "!",
                                                       "\u{201D}", "\u{2019}", "\"", "'"]

    static func proseAboveFirstRule(_ inside: [TextLine], firstRule: Double,
                                    margin: Double) -> [TextLine] {
        let above = inside.filter { $0.y - 4 >= firstRule }
                          .sorted { a, b in a.y == b.y ? a.minX < b.minX : a.y > b.y }
        var run = [TextLine]()
        for line in above {
            if line.minX > margin + 1.0 { break }
            run.append(line)
        }
        guard let tail = run.last?.text.trimmed.last, sentenceTail.contains(tail)
        else { return [] }
        return run
    }

    static func titleLinesAbove(_ before: [TextLine], _ inside: [TextLine],
                                margin: Double) -> [TextLine] {
        guard !before.isEmpty, !inside.isEmpty else { return [] }
        var topOfTable = inside.map(\.y).max() ?? 0
        var taken = [TextLine]()
        for line in before.reversed() {
            if line.minX <= margin + 40 { break }
            if line.y - topOfTable > 16 { break }
            taken.append(line)
            topOfTable = line.y
        }
        return taken.reversed()
    }

    private static func blocksAroundTables(_ page: ExtractedPage, _ lines: [TextLine],
                                           _ tables: [TableGrid],
                                           graphics: [CGRect], rules: [CGRect],
                                           stripPrefix: Bool,
                                           whole: Bool = false) -> [RawBlock] {
        var strip = stripPrefix
        var out = [RawBlock]()
        var remaining = lines

        func emit(_ run: [TextLine]) {
            guard !run.isEmpty else { return }
            let top = (run.map(\.y).max() ?? 0) + 12
            let bottom = (run.map(\.y).min() ?? 0) - 6
            let art = graphics.filter { $0.midY <= top && $0.midY >= bottom }
            if art.isEmpty {
                let (joined, marks) = joinLines(run, stripChoicePrefix: strip)
                if !joined.isEmpty { out.append(.text(joined, underlines: marks)) }
            } else {
                out += artBlocks(page: page, lines: run,
                                 graphics: art,
                                 rules: rules.filter { $0.midY <= top && $0.midY >= bottom },
                                 leftEdge: nil, stripPrefix: strip, whole: whole)
            }
            strip = false
        }

        let bodyMargin = lines.map(\.minX).min() ?? 0

        for grid in tables.sorted(by: { tableSpan($0).top > tableSpan($1).top }) {
            let span = tableSpan(grid)
            var before = remaining.filter { $0.y >= span.top }
            var inside = remaining.filter { $0.y < span.top && $0.y >= span.bottom - 1 }
            remaining = remaining.filter { $0.y < span.bottom - 1 }

            if let firstRule = grid.rowRules.first {
                let returned = proseAboveFirstRule(inside, firstRule: firstRule,
                                                   margin: bodyMargin)
                if !returned.isEmpty {
                    let given = Set(returned.map { "\($0.y)|\($0.minX)|\($0.text)" })
                    before += returned
                    before.sort { $0.y > $1.y }
                    inside = inside.filter {
                        !given.contains("\($0.y)|\($0.minX)|\($0.text)")
                    }
                }
            }

            let lifted = titleLinesAbove(before, inside, margin: bodyMargin)
            let kept = before.count - lifted.count
            emit(Array(before.prefix(kept)))
            var rows = tableRows(inside, grid).filter { row in
                row.contains { !$0.trimmed.isEmpty }
            }
            if !lifted.isEmpty {
                let head = lifted.map { $0.text.trimmed }
                                 .joined(separator: " ").trimmed
                if !rows.isEmpty, rows[0].count == 1 {
                    rows[0] = [(head + " " + rows[0][0]).trimmed]
                } else if !head.isEmpty {
                    rows.insert([head], at: 0)
                }
            }
            if !rows.isEmpty { out.append(.table(rows)) }
        }
        emit(remaining)
        return out
    }

    static func tableRows(_ lines: [TextLine], _ grid: TableGrid) -> [[String]] {
        let edges = grid.edges
        let columns = edges.count - 1
        let rules = grid.rowRules
        let step = rules.count > 1 ? (rules[0] - rules[1]) : 20

        var rows = [[String]]()
        var banded = [[TextLine]](repeating: [], count: rules.count)
        for line in lines {
            guard line.maxX > edges[0] - 2, line.minX < edges[columns] + 2
            else { continue }
            for (i, rule) in rules.enumerated() {
                let top = i == 0 ? rule + step : rules[i - 1]
                if line.y < top && line.y >= rule - 1 {
                    banded[i].append(line)
                    break
                }
            }
        }

        for (i, _) in rules.enumerated() {
            let band = banded[i]
            var cells = [String](repeating: "", count: columns)
            var spanning: String? = nil
            var ruled = band.contains { runs(in: $0).count > 1 }
            if !ruled {
                var touched = Set<Int>()
                for line in band {
                    let rs = runs(in: line)
                    if rs.count == 1, let c = column(of: rs[0], edges) {
                        touched.insert(c)
                    }
                }
                ruled = touched.count >= 2
            }

            for line in band {
                let pieces = runs(in: line)
                guard !pieces.isEmpty else { continue }
                if pieces.count == 1, !ruled || column(of: pieces[0], edges) == nil {
                    spanning = spanning.map { $0 + " " + pieces[0].text } ?? pieces[0].text
                    continue
                }
                for piece in pieces {
                    guard let c = column(of: piece, edges) else { continue }
                    cells[c] = cells[c].isEmpty ? piece.text : cells[c] + " " + piece.text
                }
            }

            if let spanning, cells.allSatisfy(\.isEmpty) {
                rows.append([spanning])
            } else {
                if let spanning {
                    rows.append([spanning])
                }
                rows.append(cells.map { $0.trimmed })
            }
        }
        return rows
    }

    private static func runs(in line: TextLine,
                             gap: Double = 4.0) -> [(text: String, minX: Double, maxX: Double)] {
        var out = [(text: String, minX: Double, maxX: Double)]()
        var text = ""
        var lo: Double? = nil
        var hi: Double? = nil
        for (ch, box) in zip(line.text, line.charBoxes) {
            guard let box else {
                if !text.isEmpty { text.append(" ") }
                continue
            }
            if let last = hi, box.lowerBound - last > gap {
                if !text.trimmed.isEmpty, let l = lo, let h = hi {
                    out.append((text.trimmed, l, h))
                }
                text = ""; lo = nil
            }
            if lo == nil { lo = box.lowerBound }
            text.append(ch)
            hi = box.upperBound
        }
        if !text.trimmed.isEmpty, let l = lo, let h = hi { out.append((text.trimmed, l, h)) }
        return out
    }

    private static func column(of run: (text: String, minX: Double, maxX: Double),
                               _ edges: [Double]) -> Int? {
        for i in 0..<(edges.count - 1) where run.minX >= edges[i] - 2 && run.maxX <= edges[i + 1] + 2 {
            return i
        }
        let mid = (run.minX + run.maxX) / 2
        for i in 0..<(edges.count - 1) where edges[i] <= mid && mid < edges[i + 1] {
            return (run.maxX - run.minX) > (edges[i + 1] - edges[i]) + 4 ? nil : i
        }
        return nil
    }

    private static func joinLines(_ lines: [TextLine],
                                  stripChoicePrefix: Bool) -> (String, [Range<Int>]) {
        guard !lines.isEmpty else { return ("", []) }
        var parts = [String]()
        var partSpans = [[Range<Int>]]()
        var current = ""
        var currentSpans = [Range<Int>]()
        var previousY: Double? = nil
        var previousLine: TextLine? = nil
        let baseIndent = lines.map(\.minX).min() ?? 0

        for (i, line) in lines.enumerated() {
            let raw = line.text
            var text = raw.trimmed
            if text.isEmpty { continue }
            var trim = raw.count - String(raw.drop(while: \.isWhitespace)).count
            if stripChoicePrefix && i == 0 {
                let stripped = stripLeadingChoiceLabel(text)
                trim += text.count - stripped.count
                text = stripped
            }
            if line.bullet {
                text = "• " + text
                trim -= 2
            }

            var newParagraph = false
            if let py = previousY {
                let gap = py - line.y
                if gap > 22 { newParagraph = true }
                if line.minX > baseIndent + 12 && gap > 17 { newParagraph = true }
                if leavesIndentedRun(lines, i, baseIndent: baseIndent) {
                    newParagraph = true
                }
                if let pl = previousLine,
                   opensIndentedBlock(pl, line, baseIndent: baseIndent) {
                    newParagraph = true
                }
            }
            if line.bullet { newParagraph = true }
            if opensNumberedStatement(line.text) { newParagraph = true }
            if newParagraph, !current.isEmpty {
                parts.append(current); partSpans.append(currentSpans)
                current = ""; currentSpans = []
            }

            let offset: Int
            if current.isEmpty {
                offset = 0
                current = text
            } else if current.hasSuffix("-") {
                offset = current.count
                current += text
            } else {
                current += " "
                offset = current.count
                current += text
            }

            for span in line.underlines {
                let lo = min(max(span.lowerBound - trim, 0), text.count)
                let hi = min(max(span.upperBound - trim, 0), text.count)
                if hi > lo { currentSpans.append((offset + lo)..<(offset + hi)) }
            }
            previousY = line.y
            previousLine = line
        }
        if !current.isEmpty { parts.append(current); partSpans.append(currentSpans) }

        var out = ""
        var spans = [Range<Int>]()
        var pos = 0
        for (i, part) in parts.enumerated() {
            if i > 0 { out += "\n\n"; pos += 2 }
            out += part
            spans += partSpans[i].map { ($0.lowerBound + pos)..<($0.upperBound + pos) }
            pos += part.count
        }
        return (out, tidy(spans, in: out))
    }

    static func tidy(_ spans: [Range<Int>], in text: String) -> [Range<Int>] {
        let chars = Array(text)
        var clean = [Range<Int>]()
        for span in spans {
            var lo = max(0, span.lowerBound), hi = min(span.upperBound, chars.count)
            while lo < hi, chars[lo].isWhitespace { lo += 1 }
            while hi > lo, chars[hi - 1].isWhitespace { hi -= 1 }
            if hi > lo { clean.append(lo..<hi) }
        }
        var merged = [Range<Int>]()
        for span in clean.sorted(by: { $0.lowerBound < $1.lowerBound }) {
            if let last = merged.last, span.lowerBound - last.upperBound <= 2,
               chars[last.upperBound..<span.lowerBound].allSatisfy(\.isWhitespace) {
                merged[merged.count - 1] = last.lowerBound..<max(last.upperBound, span.upperBound)
            } else if let last = merged.last, span.lowerBound <= last.upperBound {
                merged[merged.count - 1] = last.lowerBound..<max(last.upperBound, span.upperBound)
            } else {
                merged.append(span)
            }
        }
        return merged
    }

    private static func stripLeadingChoiceLabel(_ s: String) -> String {
        var t = s.trimmed
        guard let first = t.first, "ABCD".contains(first) else { return t }
        t.removeFirst()
        if let n = t.first, n == "." || n == ")" { t.removeFirst() }
        return t.trimmed
    }

    private static func splitBody(_ body: [RawBlock], into q: inout RawQuestion) {
        let subject = Subject.from(testColumn: q.test)
        guard subject == .readingWriting, body.count >= 1 else {
            q.stimulus = []
            q.prompt = body
            return
        }

        guard case .text(let last, let marks)? = body.last else {
            q.stimulus = body
            q.prompt = []
            return
        }

        let paragraphs = last.components(separatedBy: "\n\n")
        guard paragraphs.count >= 2 else {
            if let idx = lastSentenceStart(in: last), idx > last.startIndex {
                let cut = last.distance(from: last.startIndex, to: idx)
                let head = cutBlock(last, marks, 0, cut)
                let tail = cutBlock(last, marks, cut, last.count)
                if !(head.textValue ?? "").isEmpty && !(tail.textValue ?? "").isEmpty {
                    q.stimulus = Array(body.dropLast()) + [head]
                    q.prompt = [tail]
                    return
                }
            }
            q.stimulus = Array(body.dropLast())
            q.prompt = [.text(last, underlines: marks)]
            return
        }

        let headLen = paragraphs.dropLast().joined(separator: "\n\n").count
        q.stimulus = Array(body.dropLast()) + [cutBlock(last, marks, 0, headLen)]
        q.prompt = [cutBlock(last, marks, last.count - paragraphs.last!.count, last.count)]
    }

    private static func cutBlock(_ text: String, _ marks: [Range<Int>],
                                 _ start: Int, _ end: Int) -> RawBlock {
        let chars = Array(text)
        let lo = max(0, min(start, chars.count)), hi = max(lo, min(end, chars.count))
        var slice = Array(chars[lo..<hi])
        var lead = 0
        while lead < slice.count, slice[lead].isWhitespace { lead += 1 }
        var trail = 0
        while trail < slice.count - lead, slice[slice.count - 1 - trail].isWhitespace { trail += 1 }
        slice = Array(slice[lead..<(slice.count - trail)])

        let kept: [Range<Int>] = marks.compactMap { span in
            let a = max(span.lowerBound, lo + lead) - lo - lead
            let b = min(span.upperBound, hi - trail) - lo - lead
            return b > a ? a..<b : nil
        }
        return .text(String(slice), underlines: TextLine.merge(kept))
    }

    private static func lastSentenceStart(in text: String) -> String.Index? {
        let t = text.trimmed
        guard t.hasSuffix("?") else { return nil }
        var idx = t.index(before: t.endIndex)
        while idx > t.startIndex {
            let prev = t.index(before: idx)
            let ch = t[prev]
            if ch == "." || ch == "?" || ch == "!" {
                var after = idx
                while after < t.endIndex, t[after] == " " { after = t.index(after: after) }
                if after < t.endIndex, t[after].isUppercase { return after }
            }
            idx = prev
        }
        return nil
    }

    private static func plainText(on page: ExtractedPage,
                                  between bottom: Double, and top: Double) -> String {
        page.lines.filter { $0.y < top - 1 && $0.y > bottom + 1 }
            .sorted { $0.y > $1.y }
            .map(\.text)
            .joined(separator: " ")
    }

    private static func inferAnswer(fromText text: String, kind: QuestionKind) -> String? {
        guard !text.isEmpty else { return nil }

        if kind == .multipleChoice {
            for pattern in ["Choice %@ is the best answer", "Choice %@ is correct"] {
                for letter in ["A", "B", "C", "D"] {
                    if text.contains(String(format: pattern, letter)) { return letter }
                }
            }
            return nil
        }

        if let r = text.range(of: "correct answer is", options: .caseInsensitive) {
            let rest = String(text[r.upperBound...]).trimmed
            var value = ""
            for ch in rest {
                if ch.isNumber || ch == "." || ch == "/" || ch == "-" || ch == "," { value.append(ch) }
                else if value.isEmpty && ch == " " { continue }
                else { break }
            }
            value = value.trimmingCharacters(in: CharacterSet(charactersIn: ".,"))
            if !value.isEmpty { return value }
        }
        return acceptedForms(in: text)
    }

    static func acceptedForms(in text: String) -> String? {
        guard let phrase = text.range(of: "to enter a correct answer",
                                      options: .caseInsensitive) else { return nil }
        var before = text[..<phrase.lowerBound]
        for tail in [" are examples", " is an example", " are ways", " is a way"] {
            if let r = before.range(of: tail, options: [.caseInsensitive, .backwards]) {
                before = before[..<r.lowerBound]
                break
            }
        }
        let start = before.range(of: "Note that ", options: [.caseInsensitive, .backwards])?
            .upperBound ?? before.index(before.endIndex, offsetBy: -min(120, before.count))
        let list = String(before[start...])

        var values = [String]()
        for token in list.components(separatedBy: CharacterSet(charactersIn: ", \n\t")) {
            var t = token
            while t.hasSuffix(".") { t.removeLast() }
            guard !t.isEmpty, t.count <= 12,
                  t.allSatisfy({ $0.isNumber || $0 == "." || $0 == "/" || $0 == "-" }),
                  t.contains(where: \.isNumber) else { continue }
            if !values.contains(t) { values.append(t) }
        }
        return values.isEmpty ? nil : values.joined(separator: ", ")
    }
}

struct RawInlineParagraph {
    enum Run {
        case text(String)
        case island(CGRect, depth: Double)
    }
    var display: Bool
    var runs: [Run]
}

extension QuestionParser {
    static let proseXHeight = 4.75

    static let inlineAscent = 6.8
    static let inlineDescent = 1.9
    static let tallestMark = 48.0
    static let islandGap = 3.5
    static let lineReach = 14.0
    static let islandPad = 0.75
    static let lineLeft = 18.0

    static let islandMark: Character = "\u{FFFC}"

    static func inlineBase(_ l: TextLine) -> Double {
        var ys = [Double]()
        for r in l.runs { for _ in r.text { ys.append(r.y) } }
        guard !ys.isEmpty else { return l.y }
        ys.sort(by: >)
        return ys[ys.count / 2]
    }
    static func inlineTop(_ l: TextLine) -> Double { inlineBase(l) + inlineAscent }
    static func inlineBottom(_ l: TextLine) -> Double { inlineBase(l) - inlineDescent }

    static func lineOf(_ lines: [TextLine], _ r: CGRect) -> Int? {
        let cy = Double(r.midY)
        var best: Int? = nil
        var dist = lineReach
        for (k, l) in lines.enumerated() {
            let d = abs((inlineTop(l) + inlineBottom(l)) / 2 - cy)
            if d <= dist { best = k; dist = d }
        }
        return best
    }

    static func closedUp(_ lines: [TextLine], _ marks: [CGRect]) -> [TextLine] {
        var up = [Double](repeating: 0, count: lines.count)
        var down = up
        var left = lines.map(\.minX)
        for r in marks where Double(r.height) <= tallestMark {
            guard let k = lineOf(lines, r) else { continue }
            up[k] = max(up[k], Double(r.maxY) - inlineTop(lines[k]))
            down[k] = max(down[k], inlineBottom(lines[k]) - Double(r.minY))
            left[k] = min(left[k], Double(r.minX))
        }
        var out = [TextLine]()
        var shift = 0.0
        for (k, l) in lines.enumerated() {
            if k > 0, inlineBase(lines[k - 1]) - inlineBase(l) - (up[k] + down[k - 1]) <= lineLeft {
                shift += up[k] + down[k - 1]
            }
            var moved = l
            moved.minX = left[k]
            moved.y += shift
            for i in moved.runs.indices { moved.runs[i].y += shift }
            out.append(moved)
        }
        return out
    }

    static func inlineParagraphs(page: ExtractedPage, picture: Picture,
                                 lines: [TextLine], leftEdge: Double?) -> [RawInlineParagraph]? {
        let own = picture.lines.sorted().map { lines[$0] }.filter { !$0.text.trimmed.isEmpty }
        guard !own.isEmpty, own.allSatisfy({ $0.underlines.isEmpty }) else { return nil }
        let top = max(picture.top, own.map(inlineTop).max()!)
        let bottom = min(picture.bottom, own.map(inlineBottom).min()!)
        var left = min(picture.artLeft, own.map(\.minX).min()!) - 2
        let right = max(picture.artRight, own.map(\.maxX).max()!) + 2
        if let le = leftEdge { left = le - 2 }
        let marks = page.contentGraphics.filter {
            Double($0.midY) <= top + 2 && Double($0.midY) >= bottom - 2
                && Double($0.midX) >= left && Double($0.midX) <= right
        }
        guard !marks.isEmpty, marks.allSatisfy({ Double($0.height) <= tallestMark }) else { return nil }

        var byLine = [[CGRect]](repeating: [], count: own.count)
        var loose = [CGRect]()
        for r in marks {
            if let k = lineOf(own, r) { byLine[k].append(r) } else { loose.append(r) }
        }

        struct Island { var x0, x1, top, bottom: Double; var line: Int? }
        var islands = [Island]()
        var dropped = [Set<Int>](repeating: [], count: own.count)
        for (k, l) in own.enumerated() {
            var mine = [Island]()
            for r in byLine[k].sorted(by: { $0.minX < $1.minX }) {
                if let last = mine.last, Double(r.minX) - last.x1 < islandGap {
                    mine[mine.count - 1] = Island(x0: last.x0, x1: max(last.x1, Double(r.maxX)),
                                                  top: max(last.top, Double(r.maxY)),
                                                  bottom: min(last.bottom, Double(r.minY)), line: k)
                } else {
                    mine.append(Island(x0: Double(r.minX), x1: Double(r.maxX),
                                       top: Double(r.maxY), bottom: Double(r.minY), line: k))
                }
            }
            let chars = Array(l.text)
            var grew = true
            while grew {
                grew = false
                for (j, box) in l.charBoxes.enumerated() {
                    guard let box, !dropped[k].contains(j) else { continue }
                    for mi in mine.indices
                    where box.upperBound > mine[mi].x0 + 0.5 && box.lowerBound < mine[mi].x1 - 0.5 {
                        dropped[k].insert(j)
                        if j < chars.count, chars[j].isWhitespace { break }
                        mine[mi].x0 = min(mine[mi].x0, box.lowerBound)
                        mine[mi].x1 = max(mine[mi].x1, box.upperBound)
                        mine[mi].top = max(mine[mi].top, inlineTop(l))
                        mine[mi].bottom = min(mine[mi].bottom, inlineBottom(l))
                        grew = true
                        break
                    }
                }
            }
            islands += mine
        }

        for (k, l) in own.enumerated() {
            var run = 0
            for (j, ch) in l.text.enumerated() {
                run = dropped[k].contains(j) && !ch.isWhitespace ? run + 1 : 0
                if run >= 2 { return nil }
            }
        }

        var displays = [Island]()
        for r in loose.sorted(by: { $0.maxY > $1.maxY }) {
            if let d = displays.last, Double(r.maxY) > d.bottom - 1 {
                displays[displays.count - 1] = Island(x0: min(d.x0, Double(r.minX)),
                                                      x1: max(d.x1, Double(r.maxX)),
                                                      top: max(d.top, Double(r.maxY)),
                                                      bottom: min(d.bottom, Double(r.minY)), line: nil)
            } else {
                displays.append(Island(x0: Double(r.minX), x1: Double(r.maxX),
                                       top: Double(r.maxY), bottom: Double(r.minY), line: nil))
            }
        }
        if displays.contains(where: { d in
            own.contains { inlineBottom($0) < d.top - 1 && inlineTop($0) > d.bottom + 1 }
        }) { return nil }

        for m in islands {
            for (k, l) in own.enumerated()
            where k != m.line && inlineBottom(l) < m.top - 1 && inlineTop(l) > m.bottom + 1 {
                for (j, box) in l.charBoxes.enumerated() {
                    if let box, !dropped[k].contains(j), box.upperBound > m.x0, box.lowerBound < m.x1 {
                        return nil
                    }
                }
            }
            for n in islands where n.line != m.line
                && n.x0 < m.x1 && m.x0 < n.x1 && n.bottom < m.top && m.bottom < n.top {
                return nil
            }
        }
        if islands.isEmpty && displays.isEmpty { return nil }

        var order = [Island]()
        var virtual = [TextLine]()
        for (k, l) in own.enumerated() {
            var items = [(x: Double, n: Int, ch: Character, box: ClosedRange<Double>?)]()
            var last = l.minX
            for (j, (ch, box)) in zip(l.text, l.charBoxes).enumerated() {
                if dropped[k].contains(j) { continue }
                if let box, let le = leftEdge, box.upperBound <= le { continue }
                let x = box?.lowerBound ?? last
                last = box?.upperBound ?? last
                items.append((x, items.count, ch, box))
            }
            let mine = islands.filter { $0.line == k }.sorted { $0.x0 < $1.x0 }
            for m in mine { items.append((m.x0, items.count, islandMark, m.x0...m.x1)) }
            items.sort { $0.x != $1.x ? $0.x < $1.x : $0.n < $1.n }
            var text = [Character](), boxes = [ClosedRange<Double>?]()
            for (n, it) in items.enumerated() {
                if it.ch == islandMark, let box = it.box {
                    while let t = text.last, t.isWhitespace { text.removeLast(); boxes.removeLast() }
                    if let prev = boxes.last(where: { $0 != nil }) ?? nil,
                       box.lowerBound - prev.upperBound > Layout.spaceGap {
                        text.append(" "); boxes.append(nil)
                    }
                    text.append(it.ch); boxes.append(box)
                    if let next = items[(n + 1)...].first(where: { $0.box != nil && !$0.ch.isWhitespace })?.box,
                       next.lowerBound - box.upperBound > Layout.spaceGap {
                        text.append(" "); boxes.append(nil)
                    }
                    continue
                }
                if it.ch.isWhitespace, let t = text.last, t.isWhitespace || t == islandMark { continue }
                text.append(it.ch); boxes.append(it.box)
            }
            while let t = text.first, t.isWhitespace { text.removeFirst(); boxes.removeFirst() }
            while let t = text.last, t.isWhitespace { text.removeLast(); boxes.removeLast() }
            if text.isEmpty { continue }
            order += mine
            var v = l
            let base = inlineBase(l)
            v.text = String(text)
            v.charBoxes = boxes
            v.minX = boxes.compactMap { $0?.lowerBound }.min() ?? l.minX
            v.y = base
            v.runs = [TextRun(text: String(text), x: v.minX, y: base, width: l.maxX - v.minX,
                              size: l.size, isBold: false)]
            v.underlines = []
            v.cells = []
            virtual.append(v)
        }

        func cut(_ m: Island) -> CGRect {
            let k = m.line!
            var x0 = m.x0 - islandPad, x1 = m.x1 + islandPad
            for (j, box) in own[k].charBoxes.enumerated() {
                guard let box, !dropped[k].contains(j) else { continue }
                if box.upperBound <= m.x0 + 0.5 {
                    x0 = max(x0, box.upperBound + 0.2)
                } else if box.lowerBound >= m.x1 - 0.5 {
                    x1 = min(x1, box.lowerBound - 0.2)
                }
            }
            var bottom = m.bottom - islandPad, top = m.top + islandPad
            for n in islands where n.line != m.line && n.x0 < x1 && x0 < n.x1 {
                if n.top <= m.bottom {
                    bottom = max(bottom, n.top + 0.2)
                } else if n.bottom >= m.top {
                    top = min(top, n.bottom - 0.2)
                }
            }
            return CGRect(x: x0, y: bottom, width: x1 - x0, height: top - bottom)
        }
        func displayCut(_ d: Island) -> CGRect {
            CGRect(x: d.x0 - islandPad, y: d.bottom - islandPad,
                   width: (d.x1 - d.x0) + 2 * islandPad, height: (d.top - d.bottom) + 2 * islandPad)
        }

        var queue = order[...]
        var failed = false
        func paragraphs(_ run: [TextLine]) -> [RawInlineParagraph] {
            guard !run.isEmpty else { return [] }
            let (joined, _) = joinLines(closedUp(run, marks), stripChoicePrefix: false)
            var out = [RawInlineParagraph]()
            for part in joined.components(separatedBy: "\n\n") {
                var runs = [RawInlineParagraph.Run]()
                for (n, piece) in part.split(separator: islandMark, omittingEmptySubsequences: false)
                    .enumerated() {
                    if n > 0 {
                        guard let m = queue.popFirst() else { failed = true; return [] }
                        let rect = cut(m)
                        runs.append(.island(rect, depth: inlineBase(own[m.line!]) - Double(rect.minY)))
                    }
                    if !piece.isEmpty { runs.append(.text(String(piece))) }
                }
                if !runs.isEmpty { out.append(RawInlineParagraph(display: false, runs: runs)) }
            }
            return out
        }

        var out = [RawInlineParagraph]()
        var run = [TextLine]()
        var pending = displays[...]
        for v in virtual {
            while let d = pending.first, d.top > v.y + inlineAscent {
                out += paragraphs(run); run = []
                pending.removeFirst()
                out.append(RawInlineParagraph(display: true, runs: [.island(displayCut(d), depth: 0)]))
            }
            run.append(v)
        }
        out += paragraphs(run)
        for d in pending {
            out.append(RawInlineParagraph(display: true, runs: [.island(displayCut(d), depth: 0)]))
        }
        if failed || !queue.isEmpty { return nil }
        return out
    }
}

extension ExtractedPage {
    var contentGraphics: [CGRect] {
        let cutoff = metadataCutoffY
        return graphics.rects.filter { $0.maxY < cutoff }
    }

    var metadataCutoffY: Double {
        if let q = lines.first(where: {
            $0.minX < 60 && $0.text.trimmed.caseInsensitiveCompare("Question") == .orderedSame
        }) {
            return q.y - 2
        }
        return contentTop
    }

    var contentTop: Double { mediaBox.maxY - 12 }
    var contentBottom: Double { mediaBox.minY + 14 }

    var textMeasure: (left: Double, right: Double) {
        let drawn = lines.filter { $0.maxX > $0.minX }
        guard !drawn.isEmpty else { return (Double(contentBox.minX), Double(contentBox.maxX)) }
        return (drawn.map(\.minX).min()!, drawn.map(\.maxX).max()!)
    }
    var contentBox: CGRect {
        CGRect(x: mediaBox.minX + 8, y: contentBottom,
               width: mediaBox.width - 16, height: contentTop - contentBottom)
    }
}

extension String {
    var squeezed2: String {
        components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .joined(separator: "\n")
            .replacingOccurrences(of: "\n\n\n", with: "\n\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
