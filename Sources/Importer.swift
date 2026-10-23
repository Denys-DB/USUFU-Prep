import Foundation
import CoreGraphics
import PDFKit
import AppKit

enum ImportError: LocalizedError {
    case unreadable(String)
    case noQuestions(String)
    case encrypted(String)

    var errorDescription: String? {
        switch self {
        case .unreadable(let name):
            return Lf("“%@” could not be read as a PDF.", name) + "\n\n"
                + L("This app reads the PDF that the College Board Question Bank "
                    + "produces when you choose Export — SAT or PSAT. Make sure the "
                    + "file still has its “Question ID” headers and has not been "
                    + "re-saved or printed to a new PDF.")
        case .encrypted(let name):
            return Lf("“%@” is locked with a password or encryption, so this app "
                      + "cannot read it. Export the questions again from the College "
                      + "Board Question Bank and import the new file.", name)
        case .noQuestions(let name):
            return Lf("No questions were found in “%@”.", name) + "\n\n"
                + L("This app reads the PDF that the College Board Question Bank "
                    + "produces when you choose Export — SAT or PSAT. Make sure the "
                    + "file still has its “Question ID” headers and has not been "
                    + "re-saved or printed to a new PDF.")
        }
    }
}

struct ImportResult {
    var questions: [Question]
    var sourceName: String
    var warnings: [String]
}

enum Importer {

    static let renderScale: CGFloat = 3.0

    static func importPDF(at url: URL, imagesDirectory: URL,
                          progress: (@Sendable (Double, String) -> Void)? = nil) throws -> ImportResult {
        let name = url.deletingPathExtension().lastPathComponent

        if let embedded = ExportedBankReader.read(url: url) {
            progress?(1.0, Lf("Loaded %d saved questions", embedded.count))
            return ImportResult(questions: embedded, sourceName: name, warnings: [])
        }

        if let cg = CGPDFDocument(url as CFURL), cg.isEncrypted {
            throw ImportError.encrypted(name)
        }
        guard let file = PDFFile(url: url) else { throw ImportError.unreadable(name) }
        progress?(0.05, "Reading \(name)…")

        let raws = QuestionParser.parse(file: file)
        guard !raws.isEmpty else { throw ImportError.noQuestions(name) }

        let renderDoc = PDFDocument(url: url)
        try FileManager.default.createDirectory(at: imagesDirectory,
                                                withIntermediateDirectories: true)

        var questions = [Question]()
        var warnings = [String]()
        var renderCache = [String: ContentBlock]()
        var lastReported = -1
        var imageIndex = 0

        for (i, raw) in raws.enumerated() {
            let done = Int(100 * Double(i) / Double(raws.count))
            if done != lastReported {
                lastReported = done
                progress?(0.05 + 0.9 * Double(i) / Double(raws.count),
                          "Question \(i + 1) of \(raws.count)")
            }

            imageIndex = 0
            func convert(_ blocks: [RawBlock], tag: String) -> [ContentBlock] {
                blocks.compactMap { block -> ContentBlock? in
                    switch block {
                    case .text(let t, let marks):
                        let lead = t.count - String(t.drop(while: \.isWhitespace)).count
                        let trimmed = t.trimmingCharacters(in: .whitespacesAndNewlines)
                        if trimmed.isEmpty { return nil }
                        let shifted: [Range<Int>] = marks.compactMap { span in
                            let a = max(0, span.lowerBound - lead)
                            let b = min(span.upperBound - lead, trimmed.count)
                            return b > a ? a..<b : nil
                        }
                        return .text(trimmed, underlines: shifted)
                    case .table(let rows):
                        return rows.isEmpty ? nil : .table(rows)
                    case .image(let pending):
                        let key = "\(pending.pageIndex)|\(pending.rect)"
                        if let cached = renderCache[key] { return cached }
                        imageIndex += 1
                        guard let doc = renderDoc,
                              var block = renderRegion(pending, document: doc,
                                                       name: "\(raw.id)-\(tag)-\(imageIndex)",
                                                       directory: imagesDirectory) else { return nil }
                        if !pending.inline.isEmpty {
                            block.inline = renderIslands(pending, document: doc,
                                                         name: "\(raw.id)-\(tag)-\(imageIndex)-maths",
                                                         directory: imagesDirectory)
                            block.xHeight = block.inline.isEmpty ? 0 : QuestionParser.proseXHeight
                        }
                        renderCache[key] = block
                        return block
                    }
                }
            }

            let subject = Subject.from(testColumn: raw.test)
            var q = Question(
                id: raw.id.isEmpty ? UUID().uuidString : raw.id,
                subject: subject,
                assessment: raw.assessment.isEmpty ? "SAT" : raw.assessment,
                test: raw.test.isEmpty ? subject.displayName : raw.test,
                domain: raw.domain,
                skill: raw.skill,
                difficulty: raw.difficulty,
                kind: raw.kind,
                stimulus: convert(raw.stimulus, tag: "stim"),
                prompt: convert(raw.prompt, tag: "prompt"),
                choices: raw.choices.map {
                    Choice(letter: $0.letter, blocks: convert($0.blocks, tag: "ch\($0.letter)"))
                },
                correctAnswer: raw.correctAnswer,
                rationale: convert(raw.rationale, tag: "rat"),
                sourceName: name
            )

            if q.correctAnswer.isEmpty {
                warnings.append(Lf("Question %@: no correct answer found — skipped.", q.id))
                continue
            }
            if q.prompt.isEmpty && q.stimulus.isEmpty {
                warnings.append(Lf("Question %@: no question text found — skipped.", q.id))
                continue
            }
            if q.kind == .multipleChoice && q.choices.count < 2 {
                q.kind = .studentResponse
                q.choices = []
            }
            questions.append(q)
        }

        forgetIslandDrawing()
        progress?(1.0, Lf("Imported %d questions", questions.count))
        guard !questions.isEmpty else { throw ImportError.noQuestions(name) }
        return ImportResult(questions: questions, sourceName: name, warnings: warnings)
    }

    static let regionBleedX: CGFloat = 1.5
    static let regionBleedY: CGFloat = 2

    static func renderRegion(_ pending: PendingImage, document: PDFDocument,
                             name: String, directory: URL) -> ContentBlock? {
        autoreleasepool {
            guard pending.pageIndex >= 0, pending.pageIndex < document.pageCount,
                  document.page(at: pending.pageIndex) != nil else { return nil }

            let page = document.page(at: pending.pageIndex)!
            let bounds = page.bounds(for: .mediaBox)
            let rect = pending.rect.insetBy(dx: -Self.regionBleedX, dy: -Self.regionBleedY)
                .intersection(bounds)
            guard rect.width > 1, rect.height > 1 else { return nil }

            let pixelWidth = Int((rect.width * renderScale).rounded())
            let pixelHeight = Int((rect.height * renderScale).rounded())
            guard pixelWidth > 0, pixelHeight > 0,
                  pixelWidth < 20000, pixelHeight < 20000 else { return nil }

            guard let ctx = CGContext(data: nil, width: pixelWidth, height: pixelHeight,
                                      bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            else { return nil }

            ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
            ctx.fill(CGRect(x: 0, y: 0, width: pixelWidth, height: pixelHeight))

            ctx.saveGState()
            ctx.scaleBy(x: renderScale, y: renderScale)
            ctx.translateBy(x: -rect.minX, y: -rect.minY)
            ctx.setRenderingIntent(.defaultIntent)
            ctx.interpolationQuality = .high
            page.draw(with: .mediaBox, to: ctx)
            ctx.restoreGState()

            guard var image = ctx.makeImage() else { return nil }

            var height = pixelHeight
            if let pixels = ctx.data {
                let (top, bottom) = strayEdgeRows(pixels, bytesPerRow: ctx.bytesPerRow,
                                                  width: pixelWidth, height: pixelHeight)
                if top + bottom > 0, top + bottom < pixelHeight,
                   let cropped = image.cropping(to: CGRect(x: 0, y: top,
                                                           width: pixelWidth,
                                                           height: pixelHeight - top - bottom)) {
                    image = cropped
                    height = pixelHeight - top - bottom
                }
            }
            let rep = NSBitmapImageRep(cgImage: image)
            guard let data = rep.representation(using: .png, properties: [:]) else { return nil }

            let fileName = "\(sanitize(name)).png"
            let url = directory.appendingPathComponent(fileName)
            do { try data.write(to: url, options: .atomic) } catch { return nil }

            return ContentBlock(kind: .image, text: "", imageName: fileName,
                                pixelWidth: Double(pixelWidth), pixelHeight: Double(height),
                                pointWidth: Double(rect.width),
                                centred: pending.centred)
        }
    }

    static let islandScale: CGFloat = 6

    static func renderIslands(_ pending: PendingImage, document: PDFDocument,
                              name: String, directory: URL) -> [InlineParagraph] {
        autoreleasepool {
            var rects = [CGRect]()
            for p in pending.inline {
                for r in p.runs { if case .island(let rect, _) = r { rects.append(rect) } }
            }
            guard !rects.isEmpty, pending.pageIndex >= 0, pending.pageIndex < document.pageCount,
                  let page = document.page(at: pending.pageIndex) else { return [] }
            guard let drawing = islandDrawing(document: document, page: page,
                                              index: pending.pageIndex) else { return [] }
            let all = drawing.box
            let scale = islandScale
            let width = drawing.context.width, height = drawing.context.height
            let drawn = drawing.image
            guard let data = drawing.context.data else { return [] }
            let pixels = data.assumingMemoryBound(to: UInt8.self)
            let stride = drawing.context.bytesPerRow

            var cuts = [(image: CGImage, bottom: Int)]()
            for r in rects {
                var x0 = max(0, Int(((r.minX - all.minX) * scale).rounded(.down)))
                var x1 = min(width, Int(((r.maxX - all.minX) * scale).rounded(.up)))
                var y0 = max(0, Int(((all.maxY - r.maxY) * scale).rounded(.down)))
                var y1 = min(height, Int(((all.maxY - r.minY) * scale).rounded(.up)))
                guard x1 > x0, y1 > y0 else { return [] }
                func blankRow(_ y: Int) -> Bool {
                    for x in x0..<x1 where pixels[y * stride + x] < 247 { return false }
                    return true
                }
                func blankColumn(_ x: Int) -> Bool {
                    for y in y0..<y1 where pixels[y * stride + x] < 247 { return false }
                    return true
                }
                var top = 0, bottom = 0, left = 0, right = 0
                while y0 + top < y1, blankRow(y0 + top) { top += 1 }
                if y0 + top < y1 {
                    while blankRow(y1 - 1 - bottom) { bottom += 1 }
                    y0 += max(0, top - 1); y1 -= max(0, bottom - 1)
                    while blankColumn(x0 + left) { left += 1 }
                    while blankColumn(x1 - 1 - right) { right += 1 }
                    x0 += max(0, left - 1); x1 -= max(0, right - 1)
                    bottom = max(0, bottom - 1)
                } else {
                    bottom = 0
                }
                guard let image = drawn.cropping(to: CGRect(x: x0, y: y0, width: x1 - x0,
                                                            height: y1 - y0)) else { return [] }
                cuts.append((image, bottom))
            }

            let gap = 2
            let sheetWidth = cuts.map(\.image.width).max() ?? 1
            let sheetHeight = cuts.map(\.image.height).reduce(0, +) + gap * (cuts.count - 1)
            guard sheetHeight > 0, sheetHeight < 200_000,
                  let sheet = CGContext(data: nil, width: sheetWidth, height: sheetHeight,
                                        bitsPerComponent: 8, bytesPerRow: 0,
                                        space: CGColorSpaceCreateDeviceGray(),
                                        bitmapInfo: CGImageAlphaInfo.none.rawValue)
            else { return [] }
            sheet.setFillColor(gray: 1, alpha: 1)
            sheet.fill(CGRect(x: 0, y: 0, width: sheetWidth, height: sheetHeight))
            var placed = [Int]()
            var y = 0
            for c in cuts {
                sheet.draw(c.image, in: CGRect(x: 0, y: sheetHeight - y - c.image.height,
                                               width: c.image.width, height: c.image.height))
                placed.append(y)
                y += c.image.height + gap
            }
            guard let image = sheet.makeImage(),
                  let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])
            else { return [] }
            let fileName = "\(sanitize(name)).png"
            do { try png.write(to: directory.appendingPathComponent(fileName), options: .atomic) }
            catch { return [] }

            var out = [InlineParagraph]()
            var n = 0
            for p in pending.inline {
                var runs = [InlineRun]()
                for r in p.runs {
                    switch r {
                    case .text(let t):
                        runs.append(InlineRun(text: t))
                    case .island(_, let depth):
                        let c = cuts[n]
                        func pt(_ px: Int) -> Double { (Double(px) / Double(scale) * 100).rounded() / 100 }
                        runs.append(InlineRun(image: fileName, x: 0, y: placed[n],
                                              w: c.image.width, h: c.image.height,
                                              width: pt(c.image.width), height: pt(c.image.height),
                                              depth: ((depth - Double(c.bottom) / Double(scale)) * 100)
                                                .rounded() / 100))
                        n += 1
                    }
                }
                out.append(InlineParagraph(display: p.display, runs: runs))
            }
            return out
        }
    }

    private struct IslandDrawing {
        let document: ObjectIdentifier
        let index: Int
        let box: CGRect
        let context: CGContext
        let image: CGImage
    }
    private static var lastIslandDrawing: IslandDrawing?
    private static let islandDrawingLock = NSLock()

    private static func forgetIslandDrawing() {
        islandDrawingLock.lock()
        lastIslandDrawing = nil
        islandDrawingLock.unlock()
    }

    private static func islandDrawing(document: PDFDocument, page: PDFPage,
                                      index: Int) -> IslandDrawing? {
        islandDrawingLock.lock()
        defer { islandDrawingLock.unlock() }
        if let d = lastIslandDrawing, d.document == ObjectIdentifier(document), d.index == index {
            return d
        }
        lastIslandDrawing = nil
        let box = page.bounds(for: .mediaBox)
        let width = Int((box.width * islandScale).rounded(.up))
        let height = Int((box.height * islandScale).rounded(.up))
        guard width > 0, height > 0, width < 20000, height < 20000,
              let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                  bytesPerRow: 0, space: CGColorSpaceCreateDeviceGray(),
                                  bitmapInfo: CGImageAlphaInfo.none.rawValue)
        else { return nil }
        ctx.setFillColor(gray: 1, alpha: 1)
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        ctx.saveGState()
        ctx.scaleBy(x: islandScale, y: islandScale)
        ctx.translateBy(x: -box.minX, y: -box.minY)
        ctx.interpolationQuality = .high
        page.draw(with: .mediaBox, to: ctx)
        ctx.restoreGState()
        guard let image = ctx.makeImage() else { return nil }
        let d = IslandDrawing(document: ObjectIdentifier(document), index: index,
                              box: box, context: ctx, image: image)
        lastIslandDrawing = d
        return d
    }

    static func strayEdgeRows(_ pixels: UnsafeMutableRawPointer, bytesPerRow: Int,
                              width: Int, height: Int) -> (top: Int, bottom: Int) {
        let band = min(Int((regionBleedY * renderScale).rounded()) + 2, height / 3)
        guard band > 0, width > 0 else { return (0, 0) }
        let denseLimit = max(1, Int(Double(width) * 0.25))
        let runLimit = max(2, Int(Double(width) * 0.15))
        let bytes = pixels.assumingMemoryBound(to: UInt8.self)

        func shape(ofRow y: Int) -> (ink: Int, longest: Int) {
            var n = 0, longest = 0, current = 0
            let row = bytes + y * bytesPerRow
            for x in 0..<width {
                let p = row + x * 4
                if p[0] < 240 || p[1] < 240 || p[2] < 240 {
                    n += 1; current += 1
                    if current > longest { longest = current }
                } else {
                    current = 0
                }
            }
            return (n, longest)
        }

        func strayRun(_ rowAt: (Int) -> (ink: Int, longest: Int)) -> Int {
            var run = 0
            for i in 0..<band {
                let (n, longest) = rowAt(i)
                if n == 0 { return run }
                if longest > runLimit || n > denseLimit { return 0 }
                run = i + 1
            }
            return 0
        }

        return (strayRun { shape(ofRow: $0) },
                strayRun { shape(ofRow: height - 1 - $0) })
    }

    private static func sanitize(_ s: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        return String(s.unicodeScalars.map { allowed.contains($0) ? Character($0) : "-" })
    }
}
