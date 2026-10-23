import Foundation
import CoreGraphics
import CoreText
import AppKit

private let payloadMarker = "%%SATPREP-BANK-V1"
private let payloadEnd = "%%SATPREP-END"

enum ExportPayloadSafety {
    static let maxImageBytes = 16 * 1024 * 1024

    private static let reserved: Set<String> = {
        var out: Set<String> = ["CON", "PRN", "AUX", "NUL"]
        for n in 1...9 { out.insert("COM\(n)"); out.insert("LPT\(n)") }
        return out
    }()

    static func isSafeImageName(_ name: String) -> Bool {
        guard name.range(of: #"^[A-Za-z0-9._-]+\.png\z"#, options: .regularExpression) != nil,
              !name.contains(".."), !name.hasPrefix(".") else { return false }
        let stem = name.uppercased().components(separatedBy: ".").first ?? ""
        return !reserved.contains(stem)
    }

    static let islandLimit = 800.0
    static let sheetLimit = 200_000

    static func validInline(_ inline: [InlineParagraph]) -> Bool {
        func finite(_ v: Double, _ lo: Double, _ hi: Double) -> Bool { v.isFinite && v >= lo && v <= hi }
        for p in inline {
            guard !p.runs.isEmpty else { return false }
            for r in p.runs where r.text == nil {
                guard let name = r.image, isSafeImageName(name),
                      [r.x, r.y, r.w, r.h].allSatisfy({ $0 >= 0 && $0 <= sheetLimit }),
                      r.w > 0, r.h > 0,
                      finite(r.width, 0.1, islandLimit), finite(r.height, 0.1, islandLimit),
                      finite(r.depth, -islandLimit, islandLimit) else { return false }
            }
        }
        return true
    }

    static func imageURL(_ name: String, in directory: URL) -> URL? {
        guard isSafeImageName(name) else { return nil }
        let dir = directory.standardizedFileURL
        let url = dir.appendingPathComponent(name).standardizedFileURL
        guard url.deletingLastPathComponent().path == dir.path else { return nil }
        return url
    }

    static func sanitised(_ question: Question) -> Question {
        func clean(_ blocks: [ContentBlock]) -> [ContentBlock] {
            blocks.map { block in
                var safe = block
                if block.kind == .image, !isSafeImageName(block.imageName) { safe.imageName = "" }
                if !block.inline.isEmpty,
                   !(block.kind == .image && validInline(block.inline)
                     && block.xHeight.isFinite && block.xHeight >= 0.5 && block.xHeight <= 100) {
                    safe.inline = []
                    safe.xHeight = 0
                }
                return safe
            }
        }
        var q = question
        q.stimulus = clean(q.stimulus)
        q.prompt = clean(q.prompt)
        q.rationale = clean(q.rationale)
        q.choices = q.choices.map { var c = $0; c.blocks = clean(c.blocks); return c }
        return q
    }
}

private struct BankPayload: Codable {
    var questions: [Question]
    var images: [String: String]
}

enum ExportedBankReader {
    static func read(url: URL) -> [Question]? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        let bytes = [UInt8](data)
        guard let start = find(bytes, payloadMarker, from: 0) else { return nil }
        let bodyStart = start + payloadMarker.utf8.count
        guard let end = find(bytes, payloadEnd, from: bodyStart) else { return nil }

        let base64 = String(decoding: bytes[bodyStart..<end], as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let raw = Data(base64Encoded: base64, options: .ignoreUnknownCharacters),
              let payload = try? JSONDecoder().decode(BankPayload.self, from: raw) else { return nil }
        return payload.questions.map(ExportPayloadSafety.sanitised)
    }

    static func restoreImages(url: URL, into directory: URL) {
        guard let data = try? Data(contentsOf: url) else { return }
        let bytes = [UInt8](data)
        guard let start = find(bytes, payloadMarker, from: 0) else { return }
        let bodyStart = start + payloadMarker.utf8.count
        guard let end = find(bytes, payloadEnd, from: bodyStart) else { return }
        let base64 = String(decoding: bytes[bodyStart..<end], as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let raw = Data(base64Encoded: base64, options: .ignoreUnknownCharacters),
              let payload = try? JSONDecoder().decode(BankPayload.self, from: raw) else { return }

        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let longest = (ExportPayloadSafety.maxImageBytes / 3 + 1) * 4 + 4096
        for (name, b64) in payload.images {
            guard let url = ExportPayloadSafety.imageURL(name, in: directory),
                  b64.utf8.count <= longest,
                  let imageData = Data(base64Encoded: b64, options: .ignoreUnknownCharacters),
                  imageData.count <= ExportPayloadSafety.maxImageBytes else { continue }
            try? imageData.write(to: url, options: .atomic)
        }
    }
}

enum PDFExporter {

    struct Options {
        var title: String = L("SAT Practice — Questions to Review")
        var subtitle: String = ""
        var includeRationale: Bool = true
        var includeAnswers: Bool = true
    }

    private static let pageSize = CGSize(width: 612, height: 792)
    private static let margin: CGFloat = 54
    private static var contentWidth: CGFloat { pageSize.width - margin * 2 }

    static func export(questions: [Question], imagesDirectory: URL,
                       options: Options = Options(), to url: URL) throws {
        let pdfData = NSMutableData()
        guard let consumer = CGDataConsumer(data: pdfData) else {
            throw NSError(domain: "SATPrep", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: L("Could not create the PDF.")])
        }
        var mediaBox = CGRect(origin: .zero, size: pageSize)
        var info: [String: Any] = [
            kCGPDFContextTitle as String: options.title,
            kCGPDFContextCreator as String: Brand.appName
        ]
        info[kCGPDFContextAuthor as String] = Brand.appName
        guard let ctx = CGContext(consumer: consumer, mediaBox: &mediaBox, info as CFDictionary) else {
            throw NSError(domain: "SATPrep", code: 2,
                          userInfo: [NSLocalizedDescriptionKey: L("Could not create the PDF context.")])
        }

        var writer = PageWriter(ctx: ctx, pageSize: pageSize, margin: margin)
        writer.beginPage()
        writer.drawTitle(options.title, subtitle: options.subtitle)

        for (i, q) in questions.enumerated() {
            writer.ensureSpace(120)
            writer.drawQuestionHeader(index: i + 1, question: q)

            for block in q.stimulus { writer.draw(block: block, imagesDirectory: imagesDirectory) }
            if !q.stimulus.isEmpty { writer.advance(6) }
            for block in q.prompt { writer.draw(block: block, imagesDirectory: imagesDirectory) }

            if q.kind == .multipleChoice {
                writer.advance(6)
                for choice in q.choices {
                    writer.drawChoice(choice, correct: options.includeAnswers && choice.letter == q.correctAnswer,
                                      imagesDirectory: imagesDirectory)
                }
            }

            if options.includeAnswers {
                writer.advance(6)
                writer.drawAnswerLine(q)
            }
            if options.includeRationale, !q.rationale.isEmpty {
                writer.advance(4)
                writer.drawLabel("Rationale")
                for block in q.rationale { writer.draw(block: block, imagesDirectory: imagesDirectory) }
            }
            writer.advance(10)
            writer.drawSeparator()
            writer.advance(14)
        }

        writer.endPage()
        ctx.closePDF()

        var out = Data(pdfData as Data)
        let payload = BankPayload(questions: questions,
                                  images: collectImages(questions: questions,
                                                        directory: imagesDirectory))
        if let json = try? JSONEncoder().encode(payload) {
            var tail = "\n\(payloadMarker)\n"
            tail += json.base64EncodedString(options: [.lineLength76Characters, .endLineWithLineFeed])
            tail += "\n\(payloadEnd)\n"
            out.append(tail.data(using: .utf8)!)
        }
        try out.write(to: url, options: .atomic)
    }

    private static func collectImages(questions: [Question], directory: URL) -> [String: String] {
        var names = Set<String>()
        for q in questions {
            for b in q.stimulus + q.prompt + q.rationale where b.kind == .image {
                names.insert(b.imageName)
                names.formUnion(b.inlineImages)
            }
            for c in q.choices {
                for b in c.blocks where b.kind == .image {
                    names.insert(b.imageName)
                    names.formUnion(b.inlineImages)
                }
            }
        }
        var out = [String: String]()
        for name in names where !name.isEmpty {
            if let url = ExportPayloadSafety.imageURL(name, in: directory),
               let data = try? Data(contentsOf: url) {
                out[name] = data.base64EncodedString()
            }
        }
        return out
    }
}

private struct PageWriter {
    let ctx: CGContext
    let pageSize: CGSize
    let margin: CGFloat
    var cursorY: CGFloat = 0
    private var pageOpen = false

    private var bottomLimit: CGFloat { margin }

    init(ctx: CGContext, pageSize: CGSize, margin: CGFloat) {
        self.ctx = ctx
        self.pageSize = pageSize
        self.margin = margin
        self.cursorY = pageSize.height - margin
    }

    var contentWidth: CGFloat { pageSize.width - margin * 2 }

    mutating func beginPage() {
        var box = CGRect(origin: .zero, size: pageSize)
        ctx.beginPage(mediaBox: &box)
        ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        ctx.fill(box)
        cursorY = pageSize.height - margin
        pageOpen = true
    }

    mutating func endPage() {
        if pageOpen { ctx.endPage(); pageOpen = false }
    }

    mutating func newPage() {
        endPage()
        beginPage()
    }

    mutating func ensureSpace(_ height: CGFloat) {
        if cursorY - height < bottomLimit { newPage() }
    }

    mutating func advance(_ dy: CGFloat) { cursorY -= dy }

    private static func wrap(_ text: String, font: NSFont, width: CGFloat) -> [String] {
        let words = text.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
        guard !words.isEmpty else { return [""] }
        func measure(_ s: String) -> CGFloat {
            NSAttributedString(string: s, attributes: [.font: font]).size().width
        }
        var lines = [String]()
        var current = ""
        for word in words {
            let trial = current.isEmpty ? word : current + " " + word
            if measure(trial) <= width || current.isEmpty {
                current = trial
            } else {
                lines.append(current)
                current = word
            }
        }
        if !current.isEmpty { lines.append(current) }
        return lines
    }

    private func font(_ size: CGFloat, bold: Bool = false) -> NSFont {
        bold ? .systemFont(ofSize: size, weight: .semibold) : .systemFont(ofSize: size)
    }

    @discardableResult
    mutating func drawText(_ string: String, size: CGFloat, bold: Bool = false,
                           color: NSColor = .black, indent: CGFloat = 0,
                           lineSpacing: CGFloat = 3,
                           underlines: [Range<Int>] = []) -> CGFloat {
        guard !string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return 0 }

        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = lineSpacing
        paragraph.paragraphSpacing = 6

        let attributed = NSMutableAttributedString(string: string, attributes: [
            .font: font(size, bold: bold),
            .foregroundColor: color,
            .paragraphStyle: paragraph
        ])
        let chars = Array(string)
        for range in underlines {
            let lo = max(0, min(range.lowerBound, chars.count))
            let hi = max(lo, min(range.upperBound, chars.count))
            guard hi > lo else { continue }
            let start = String(chars[0..<lo]).utf16.count
            let length = String(chars[lo..<hi]).utf16.count
            attributed.addAttribute(.underlineStyle,
                                    value: NSUnderlineStyle.single.rawValue,
                                    range: NSRange(location: start, length: length))
        }

        let width = contentWidth - indent
        let framesetter = CTFramesetterCreateWithAttributedString(attributed)
        var offset = 0

        while offset < attributed.length {
            var available = cursorY - bottomLimit
            if available < 24 { newPage(); available = cursorY - bottomLimit }

            let probe = CGPath(rect: CGRect(x: margin + indent, y: bottomLimit,
                                            width: width, height: available), transform: nil)
            let probeFrame = CTFramesetterCreateFrame(framesetter,
                                                      CFRange(location: offset, length: 0), probe, nil)
            let visible = CTFrameGetVisibleStringRange(probeFrame)
            if visible.length == 0 { newPage(); continue }

            var fitRange = CFRange()
            let used = CTFramesetterSuggestFrameSizeWithConstraints(
                framesetter, visible, nil,
                CGSize(width: width, height: .greatestFiniteMagnitude), &fitRange)
            let height = ceil(used.height) + 1

            let tight = CGPath(rect: CGRect(x: margin + indent, y: cursorY - height,
                                            width: width, height: height), transform: nil)
            let frame = CTFramesetterCreateFrame(framesetter, visible, tight, nil)

            ctx.saveGState()
            ctx.textMatrix = .identity
            CTFrameDraw(frame, ctx)
            ctx.restoreGState()

            cursorY -= height
            offset += visible.length
            if offset < attributed.length { newPage() }
        }
        return cursorY
    }

    mutating func draw(block: ContentBlock, imagesDirectory: URL, indent: CGFloat = 0) {
        switch block.kind {
        case .text:
            drawText(block.text, size: 10.5, indent: indent,
                     underlines: block.underlineRanges)
            advance(4)
        case .table:
            drawTable(block.rows, indent: indent)
            advance(4)
        case .image:
            drawImage(block, imagesDirectory: imagesDirectory, indent: indent)
        }
    }

    mutating func drawTable(_ rows: [[String]], indent: CGFloat = 0) {
        guard !rows.isEmpty else { return }
        let columns = rows.filter { $0.count > 1 }.map(\.count).max() ?? 1
        let headerIndex = rows.firstIndex { $0.count > 1 }
        let width = contentWidth - indent
        let colWidth = width / CGFloat(columns)
        let size: CGFloat = 9.5
        let padding: CGFloat = 5

        for (r, row) in rows.enumerated() {
            let spanning = row.count == 1 && columns > 1
            let bold = spanning || r == headerIndex

            var height: CGFloat = 0
            var wrapped = [[String]]()
            for cell in row {
                let cw = (spanning ? width : colWidth) - padding * 2
                let lines = Self.wrap(cell, font: font(size, bold: bold), width: cw)
                wrapped.append(lines)
                height = max(height, CGFloat(lines.count) * size * 1.3 + padding * 2)
            }
            if cursorY - height < bottomLimit { newPage() }

            let top = cursorY
            for (c, lines) in wrapped.enumerated() {
                let x = margin + indent + (spanning ? 0 : CGFloat(c) * colWidth)
                let cw = spanning ? width : colWidth
                if r == headerIndex {
                    ctx.setFillColor(NSColor(white: 0.94, alpha: 1).cgColor)
                    ctx.fill(CGRect(x: x, y: top - height, width: cw, height: height))
                }
                ctx.setStrokeColor(NSColor(white: 0.62, alpha: 1).cgColor)
                ctx.setLineWidth(0.5)
                ctx.stroke(CGRect(x: x, y: top - height, width: cw, height: height))

                var y = top - padding - size
                for line in lines {
                    let attrs: [NSAttributedString.Key: Any] = [
                        .font: font(size, bold: bold),
                        .foregroundColor: NSColor.black
                    ]
                    let attributed = NSAttributedString(string: line, attributes: attrs)
                    let lineWidth = attributed.size().width
                    let tx = (bold ? x + (cw - lineWidth) / 2 : x + padding)
                    let ctLine = CTLineCreateWithAttributedString(attributed)
                    ctx.textPosition = CGPoint(x: tx, y: y)
                    CTLineDraw(ctLine, ctx)
                    y -= size * 1.3
                }
            }
            cursorY = top - height
        }
    }

    mutating func drawImage(_ block: ContentBlock, imagesDirectory: URL, indent: CGFloat = 0) {
        let url = imagesDirectory.appendingPathComponent(block.imageName)
        guard let image = NSImage(contentsOf: url),
              let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return }

        let natural = block.pointWidth > 0 ? CGFloat(block.pointWidth) : contentWidth
        let width = min(natural, contentWidth - indent)
        let aspect = block.pixelHeight > 0 ? CGFloat(block.pixelHeight / block.pixelWidth) : 0.2
        let height = width * aspect

        if cursorY - height < bottomLimit {
            if height < contentWidth * 1.2 { newPage() }
        }
        let drawHeight = min(height, pageSize.height - margin * 2)
        let drawWidth = drawHeight / max(aspect, 0.0001)

        ctx.saveGState()
        ctx.interpolationQuality = .high
        ctx.draw(cg, in: CGRect(x: margin + indent, y: cursorY - drawHeight,
                                width: drawWidth, height: drawHeight))
        ctx.restoreGState()
        cursorY -= drawHeight + 6
    }

    mutating func drawTitle(_ title: String, subtitle: String) {
        drawText(title, size: 20, bold: true)
        advance(2)
        if !subtitle.isEmpty {
            drawText(subtitle, size: 10.5, color: NSColor(white: 0.35, alpha: 1))
        }
        advance(6)
        drawSeparator()
        advance(16)
    }

    mutating func drawQuestionHeader(index: Int, question q: Question) {
        drawText(Lf("Question %d", index), size: 13, bold: true)
        advance(1)
        var bits = [q.test, q.domain, q.skill, q.difficulty].filter { !$0.isEmpty }
        bits.append("ID \(q.id)")
        drawText(bits.joined(separator: "  ·  "), size: 8.5,
                 color: NSColor(white: 0.42, alpha: 1))
        advance(6)
    }

    mutating func drawLabel(_ text: String) {
        drawText(text, size: 10, bold: true, color: NSColor(white: 0.25, alpha: 1))
        advance(2)
    }

    mutating func drawChoice(_ choice: Choice, correct: Bool, imagesDirectory: URL) {
        ensureSpace(28)
        let bulletY = cursorY
        let radius: CGFloat = 8

        let center = CGPoint(x: margin + radius, y: bulletY - radius + 2)
        ctx.saveGState()
        ctx.setLineWidth(1)
        if correct {
            ctx.setFillColor(CGColor(red: 0.11, green: 0.42, blue: 0.20, alpha: 1))
            ctx.fillEllipse(in: CGRect(x: center.x - radius, y: center.y - radius,
                                       width: radius * 2, height: radius * 2))
        } else {
            ctx.setStrokeColor(CGColor(gray: 0.55, alpha: 1))
            ctx.strokeEllipse(in: CGRect(x: center.x - radius, y: center.y - radius,
                                         width: radius * 2, height: radius * 2))
        }
        ctx.restoreGState()

        let letterAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 9, weight: .semibold),
            .foregroundColor: correct ? NSColor.white : NSColor(white: 0.3, alpha: 1)
        ]
        let letterLine = CTLineCreateWithAttributedString(
            NSAttributedString(string: choice.letter, attributes: letterAttrs))
        var la: CGFloat = 0, ld: CGFloat = 0, ll: CGFloat = 0
        let lw = CTLineGetTypographicBounds(letterLine, &la, &ld, &ll)
        ctx.saveGState()
        ctx.textMatrix = .identity
        ctx.textPosition = CGPoint(x: center.x - CGFloat(lw) / 2, y: center.y - (la - ld) / 2)
        CTLineDraw(letterLine, ctx)
        ctx.restoreGState()

        let indent: CGFloat = radius * 2 + 8
        let before = cursorY
        for block in choice.blocks {
            draw(block: block, imagesDirectory: imagesDirectory, indent: indent)
        }
        if cursorY == before { advance(radius * 2 + 4) }
        advance(3)
    }

    mutating func drawAnswerLine(_ q: Question) {
        let text = Lf("Correct answer:  %@", q.correctAnswer)
        drawText(text, size: 10.5, bold: true,
                 color: NSColor(red: 0.11, green: 0.42, blue: 0.20, alpha: 1))
        advance(3)
    }

    mutating func drawSeparator() {
        ctx.saveGState()
        ctx.setStrokeColor(CGColor(gray: 0.82, alpha: 1))
        ctx.setLineWidth(0.5)
        ctx.move(to: CGPoint(x: margin, y: cursorY))
        ctx.addLine(to: CGPoint(x: pageSize.width - margin, y: cursorY))
        ctx.strokePath()
        ctx.restoreGState()
    }
}

extension PDFExporter {

    static func exportParentSummary(_ summary: ParentSummary, to url: URL) throws {
        let pdfData = NSMutableData()
        guard let consumer = CGDataConsumer(data: pdfData) else {
            throw NSError(domain: "SATPrep", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: L("Could not create the PDF.")])
        }
        var mediaBox = CGRect(origin: .zero, size: pageSize)
        let info: [String: Any] = [
            kCGPDFContextTitle as String: Lf("Practice summary — %@", summary.studentName),
            kCGPDFContextCreator as String: Brand.appName,
        ]
        guard let ctx = CGContext(consumer: consumer, mediaBox: &mediaBox,
                                  info as CFDictionary) else {
            throw NSError(domain: "SATPrep", code: 2,
                          userInfo: [NSLocalizedDescriptionKey: L("Could not create the PDF context.")])
        }

        var writer = PageWriter(ctx: ctx, pageSize: pageSize, margin: margin)
        writer.beginPage()
        writer.drawTitle(Lf("Practice summary — %@", summary.studentName),
                         subtitle: Lf("The last %1$d days · %2$@",
                                      summary.days, Format.stamp(summary.generatedAt)))

        for tile in summary.tiles {
            writer.drawText(tile.value, size: 22, bold: true)
            writer.advance(1)
            writer.drawText(tile.label, size: 9.5, color: NSColor(white: 0.42, alpha: 1))
            writer.advance(10)
        }
        writer.drawSeparator()
        writer.advance(14)

        for line in summary.lines {
            writer.drawText(line, size: 12)
            writer.advance(8)
        }

        if !summary.caveats.isEmpty {
            writer.advance(10)
            writer.drawSeparator()
            writer.advance(12)
            for caveat in summary.caveats {
                writer.drawText(caveat, size: 9, color: NSColor(white: 0.45, alpha: 1))
                writer.advance(6)
            }
        }

        writer.advance(8)
        writer.drawText(Brand.appName + " · " + Brand.organisation, size: 8.5,
                        color: NSColor(white: 0.55, alpha: 1))
        writer.endPage()
        ctx.closePDF()
        try pdfData.write(to: url, options: .atomic)
    }
}
