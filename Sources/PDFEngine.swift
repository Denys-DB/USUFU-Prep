import Foundation
import CoreGraphics
import Compression

enum Inflate {
    static func zlib(_ input: [UInt8]) -> [UInt8]? {
        guard input.count > 2 else { return nil }

        var start = 0
        let cmf = input[0], flg = input[1]
        if (cmf & 0x0F) == 8, (UInt16(cmf) << 8 | UInt16(flg)) % 31 == 0 {
            start = 2
        }
        if let out = rawInflate(Array(input[start...])), !out.isEmpty { return out }
        if start == 2 { return rawInflate(input) }
        return rawInflate(Array(input.dropFirst(2)))
    }

    private static func rawInflate(_ input: [UInt8]) -> [UInt8]? {
        guard !input.isEmpty else { return nil }
        var stream = compression_stream(
            dst_ptr: UnsafeMutablePointer<UInt8>(bitPattern: 1)!, dst_size: 0,
            src_ptr: UnsafePointer<UInt8>(bitPattern: 1)!, src_size: 0,
            state: nil)
        guard compression_stream_init(&stream, COMPRESSION_STREAM_DECODE, COMPRESSION_ZLIB)
                == COMPRESSION_STATUS_OK else { return nil }
        defer { compression_stream_destroy(&stream) }

        let bufSize = 1 << 16
        var output = [UInt8]()
        output.reserveCapacity(input.count * 4)
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufSize)
        defer { buffer.deallocate() }

        return input.withUnsafeBufferPointer { src -> [UInt8]? in
            stream.src_ptr = src.baseAddress!
            stream.src_size = src.count
            while true {
                stream.dst_ptr = buffer
                stream.dst_size = bufSize
                let status = compression_stream_process(&stream, Int32(COMPRESSION_STREAM_FINALIZE.rawValue))
                let produced = bufSize - stream.dst_size
                if produced > 0 { output.append(contentsOf: UnsafeBufferPointer(start: buffer, count: produced)) }
                switch status {
                case COMPRESSION_STATUS_END: return output
                case COMPRESSION_STATUS_OK:
                    if produced == 0 && stream.src_size == 0 { return output }
                default:
                    return output.isEmpty ? nil : output
                }
            }
        }
    }
}

indirect enum PDFObject {
    case null
    case bool(Bool)
    case number(Double)
    case string([UInt8])
    case name(String)
    case array([PDFObject])
    case dictionary([String: PDFObject])
    case stream([String: PDFObject], [UInt8])
    case reference(Int)

    var doubleValue: Double? { if case .number(let d) = self { return d }; return nil }
    var intValue: Int? { if case .number(let d) = self { return Int(d) }; return nil }
    var nameValue: String? { if case .name(let n) = self { return n }; return nil }
    var arrayValue: [PDFObject]? { if case .array(let a) = self { return a }; return nil }
    var dictValue: [String: PDFObject]? {
        switch self {
        case .dictionary(let d): return d
        case .stream(let d, _): return d
        default: return nil
        }
    }
}

struct PDFToken {
    enum Kind { case number, string, name, op, arrayOpen, arrayClose, dictOpen, dictClose }
    var kind: Kind
    var number: Double = 0
    var bytes: [UInt8] = []
    var text: String = ""
}

@inline(__always) private func isWhite(_ c: UInt8) -> Bool {
    c == 0x00 || c == 0x09 || c == 0x0A || c == 0x0C || c == 0x0D || c == 0x20
}
@inline(__always) private func isDelim(_ c: UInt8) -> Bool {
    c == 0x28 || c == 0x29 || c == 0x3C || c == 0x3E || c == 0x5B || c == 0x5D
    || c == 0x7B || c == 0x7D || c == 0x2F || c == 0x25
}
@inline(__always) private func hexVal(_ c: UInt8) -> UInt8? {
    switch c {
    case 0x30...0x39: return c - 0x30
    case 0x41...0x46: return c - 0x41 + 10
    case 0x61...0x66: return c - 0x61 + 10
    default: return nil
    }
}

struct PDFLexer {
    let data: [UInt8]
    var pos: Int

    init(_ data: [UInt8], at: Int = 0) { self.data = data; self.pos = at }

    mutating func skipWhitespaceAndComments() {
        while pos < data.count {
            let c = data[pos]
            if isWhite(c) { pos += 1 }
            else if c == 0x25 {
                while pos < data.count && data[pos] != 0x0A && data[pos] != 0x0D { pos += 1 }
            } else { return }
        }
    }

    mutating func next() -> PDFToken? {
        skipWhitespaceAndComments()
        guard pos < data.count else { return nil }
        let c = data[pos]

        if c == 0x28 { return literalString() }
        if c == 0x3C {
            if pos + 1 < data.count && data[pos + 1] == 0x3C {
                pos += 2; return PDFToken(kind: .dictOpen)
            }
            return hexString()
        }
        if c == 0x3E && pos + 1 < data.count && data[pos + 1] == 0x3E {
            pos += 2; return PDFToken(kind: .dictClose)
        }
        if c == 0x5B { pos += 1; return PDFToken(kind: .arrayOpen) }
        if c == 0x5D { pos += 1; return PDFToken(kind: .arrayClose) }
        if c == 0x2F { return nameToken() }
        if c == 0x7B || c == 0x7D {
            pos += 1
            return PDFToken(kind: .op, text: c == 0x7B ? "{" : "}")
        }

        let start = pos
        while pos < data.count && !isWhite(data[pos]) && !isDelim(data[pos]) { pos += 1 }
        if pos == start { pos += 1 }
        let word = String(decoding: data[start..<pos], as: UTF8.self)
        if let d = parseNumber(word) { return PDFToken(kind: .number, number: d) }
        return PDFToken(kind: .op, text: word)
    }

    private func parseNumber(_ s: String) -> Double? {
        var seenDigit = false
        for ch in s.unicodeScalars {
            switch ch {
            case "0"..."9": seenDigit = true
            case "+", "-", ".": continue
            default: return nil
            }
        }
        guard seenDigit else { return nil }
        return Double(s) ?? Double(s.replacingOccurrences(of: "--", with: "-")) ?? 0
    }

    private mutating func nameToken() -> PDFToken {
        pos += 1
        var out = [UInt8]()
        while pos < data.count && !isWhite(data[pos]) && !isDelim(data[pos]) {
            if data[pos] == 0x23, pos + 2 < data.count,
               let h = hexVal(data[pos + 1]), let l = hexVal(data[pos + 2]) {
                out.append(h << 4 | l); pos += 3
            } else {
                out.append(data[pos]); pos += 1
            }
        }
        return PDFToken(kind: .name, text: String(decoding: out, as: UTF8.self))
    }

    private mutating func literalString() -> PDFToken {
        pos += 1
        var out = [UInt8]()
        var depth = 1
        while pos < data.count {
            let c = data[pos]
            if c == 0x5C {
                pos += 1
                guard pos < data.count else { break }
                let e = data[pos]
                switch e {
                case 0x6E: out.append(0x0A); pos += 1
                case 0x72: out.append(0x0D); pos += 1
                case 0x74: out.append(0x09); pos += 1
                case 0x62: out.append(0x08); pos += 1
                case 0x66: out.append(0x0C); pos += 1
                case 0x0A: pos += 1
                case 0x0D:
                    pos += 1
                    if pos < data.count && data[pos] == 0x0A { pos += 1 }
                case 0x30...0x37:
                    var v = 0, n = 0
                    while pos < data.count, n < 3, data[pos] >= 0x30, data[pos] <= 0x37 {
                        v = v * 8 + Int(data[pos] - 0x30); pos += 1; n += 1
                    }
                    out.append(UInt8(v & 0xFF))
                default: out.append(e); pos += 1
                }
            } else if c == 0x28 { depth += 1; out.append(c); pos += 1 }
            else if c == 0x29 {
                depth -= 1; pos += 1
                if depth == 0 { break }
                out.append(c)
            } else { out.append(c); pos += 1 }
        }
        return PDFToken(kind: .string, bytes: out)
    }

    private mutating func hexString() -> PDFToken {
        pos += 1
        var nibbles = [UInt8]()
        while pos < data.count && data[pos] != 0x3E {
            if let v = hexVal(data[pos]) { nibbles.append(v) }
            pos += 1
        }
        if pos < data.count { pos += 1 }
        if nibbles.count % 2 == 1 { nibbles.append(0) }
        var out = [UInt8](); out.reserveCapacity(nibbles.count / 2)
        for i in stride(from: 0, to: nibbles.count, by: 2) {
            out.append(nibbles[i] << 4 | nibbles[i + 1])
        }
        return PDFToken(kind: .string, bytes: out)
    }
}

struct PDFObjectParser {
    var lexer: PDFLexer

    init(_ data: [UInt8], at: Int = 0) { lexer = PDFLexer(data, at: at) }

    mutating func parseObject() -> PDFObject? {
        guard let tok = lexer.next() else { return nil }
        return parseObject(startingWith: tok)
    }

    mutating func parseObject(startingWith tok: PDFToken) -> PDFObject? {
        switch tok.kind {
        case .number:
            let save = lexer.pos
            if let t2 = lexer.next(), t2.kind == .number,
               let t3 = lexer.next(), t3.kind == .op, t3.text == "R" {
                return .reference(Int(tok.number))
            }
            lexer.pos = save
            return .number(tok.number)
        case .string: return .string(tok.bytes)
        case .name: return .name(tok.text)
        case .arrayOpen:
            var items = [PDFObject]()
            while let t = lexer.next() {
                if t.kind == .arrayClose { break }
                if t.kind == .dictClose { break }
                if let o = parseObject(startingWith: t) { items.append(o) } else { break }
            }
            return .array(items)
        case .dictOpen:
            var dict = [String: PDFObject]()
            while let t = lexer.next() {
                if t.kind == .dictClose { break }
                guard t.kind == .name else {
                    if t.kind == .arrayClose { continue }
                    continue
                }
                guard let v = parseObject() else { break }
                dict[t.text] = v
            }
            let save = lexer.pos
            if let t = lexer.next(), t.kind == .op, t.text == "stream" {
                var p = lexer.pos
                if p < lexer.data.count && lexer.data[p] == 0x0D { p += 1 }
                if p < lexer.data.count && lexer.data[p] == 0x0A { p += 1 }
                return .stream(dict, streamBytes(from: p, dict: dict))
            }
            lexer.pos = save
            return .dictionary(dict)
        case .op:
            switch tok.text {
            case "true": return .bool(true)
            case "false": return .bool(false)
            case "null": return .null
            default: return nil
            }
        case .arrayClose, .dictClose: return nil
        }
    }

    private mutating func streamBytes(from start: Int, dict: [String: PDFObject]) -> [UInt8] {
        let data = lexer.data
        if let len = dict["Length"]?.intValue, len >= 0, start + len <= data.count {
            var end = start + len
            var probe = PDFLexer(data, at: end)
            probe.skipWhitespaceAndComments()
            if matches(data, at: probe.pos, "endstream") {
                lexer.pos = probe.pos + 9
                return Array(data[start..<end])
            }
            _ = end; end = start
        }
        if let idx = find(data, "endstream", from: start) {
            var end = idx
            if end > start && data[end - 1] == 0x0A { end -= 1 }
            if end > start && data[end - 1] == 0x0D { end -= 1 }
            lexer.pos = idx + 9
            return Array(data[start..<max(start, end)])
        }
        lexer.pos = data.count
        return Array(data[start...])
    }
}

@inline(__always) func matches(_ data: [UInt8], at: Int, _ s: String) -> Bool {
    let b = Array(s.utf8)
    guard at >= 0, at + b.count <= data.count else { return false }
    for i in 0..<b.count where data[at + i] != b[i] { return false }
    return true
}

func find(_ data: [UInt8], _ s: String, from: Int) -> Int? {
    let pat = Array(s.utf8)
    guard !pat.isEmpty, from >= 0, data.count >= pat.count else { return nil }
    let first = pat[0]
    var i = max(0, from)
    let limit = data.count - pat.count
    while i <= limit {
        if data[i] == first {
            var ok = true
            for j in 1..<pat.count where data[i + j] != pat[j] { ok = false; break }
            if ok { return i }
        }
        i += 1
    }
    return nil
}

final class PDFFile {
    let bytes: [UInt8]
    private(set) var objects: [Int: PDFObject] = [:]

    init?(url: URL) {
        guard let d = try? Data(contentsOf: url) else { return nil }
        bytes = [UInt8](d)
        guard find(bytes, "%PDF", from: 0) != nil else { return nil }
        scanObjects()
        expandObjectStreams()
        if objects.isEmpty { return nil }
    }

    private func scanObjects() {
        var i = 0
        let n = bytes.count
        while i + 3 < n {
            guard let idx = find(bytes, "obj", from: i) else { break }
            i = idx + 3
            if idx + 3 < n, !isWhite(bytes[idx + 3]), !isDelim(bytes[idx + 3]) { continue }

            var p = idx - 1
            while p >= 0 && isWhite(bytes[p]) { p -= 1 }
            let genEnd = p
            while p >= 0 && bytes[p] >= 0x30 && bytes[p] <= 0x39 { p -= 1 }
            guard genEnd > p else { continue }
            while p >= 0 && isWhite(bytes[p]) { p -= 1 }
            let numEnd = p
            while p >= 0 && bytes[p] >= 0x30 && bytes[p] <= 0x39 { p -= 1 }
            guard numEnd > p else { continue }
            if p >= 0, !isWhite(bytes[p]), !isDelim(bytes[p]) { continue }

            let numStr = String(decoding: bytes[(p + 1)...numEnd], as: UTF8.self)
            guard let num = Int(numStr) else { continue }

            var parser = PDFObjectParser(bytes, at: idx + 3)
            if let obj = parser.parseObject() {
                objects[num] = obj
                i = max(i, parser.lexer.pos)
            }
        }
    }

    private func expandObjectStreams() {
        let streams = objects.filter { $0.value.dictValue?["Type"]?.nameValue == "ObjStm" }
        for (_, obj) in streams {
            guard case .stream(let dict, _) = obj,
                  let content = decodedStream(obj),
                  let count = resolve(dict["N"])?.intValue,
                  let first = resolve(dict["First"])?.intValue else { continue }
            var lex = PDFLexer(content, at: 0)
            var pairs = [(Int, Int)]()
            for _ in 0..<count {
                guard let a = lex.next(), a.kind == .number,
                      let b = lex.next(), b.kind == .number else { break }
                pairs.append((Int(a.number), Int(b.number)))
            }
            for (num, off) in pairs {
                let at = first + off
                guard at >= 0, at < content.count else { continue }
                if objects[num] != nil { continue }
                var p = PDFObjectParser(content, at: at)
                if let o = p.parseObject() { objects[num] = o }
            }
        }
    }

    func resolve(_ obj: PDFObject?) -> PDFObject? {
        var cur = obj
        var hops = 0
        while case .reference(let n)? = cur, hops < 32 {
            cur = objects[n]; hops += 1
        }
        return cur
    }

    func decodedStream(_ obj: PDFObject?) -> [UInt8]? {
        guard case .stream(let dict, let raw)? = resolve(obj) else { return nil }
        var filters = [String]()
        switch resolve(dict["Filter"]) {
        case .name(let n)?: filters = [n]
        case .array(let a)?: filters = a.compactMap { resolve($0)?.nameValue }
        default: break
        }
        var data = raw
        for f in filters {
            switch f {
            case "FlateDecode", "Fl":
                guard let out = Inflate.zlib(data) else { return nil }
                data = out
            case "ASCIIHexDecode", "AHx": data = asciiHexDecode(data)
            case "ASCII85Decode", "A85": data = ascii85Decode(data)
            case "DCTDecode", "JPXDecode", "CCITTFaxDecode", "JBIG2Decode":
                return data
            default: break
            }
        }
        if let parms = resolve(dict["DecodeParms"])?.dictValue,
           let pred = resolve(parms["Predictor"])?.intValue, pred >= 10 {
            let colors = resolve(parms["Colors"])?.intValue ?? 1
            let bpc = resolve(parms["BitsPerComponent"])?.intValue ?? 8
            let columns = resolve(parms["Columns"])?.intValue ?? 1
            data = pngPredictor(data, colors: colors, bpc: bpc, columns: columns)
        }
        return data
    }

    private func asciiHexDecode(_ d: [UInt8]) -> [UInt8] {
        var nib = [UInt8]()
        for c in d { if c == 0x3E { break }; if let v = hexVal(c) { nib.append(v) } }
        if nib.count % 2 == 1 { nib.append(0) }
        var out = [UInt8]()
        for i in stride(from: 0, to: nib.count, by: 2) { out.append(nib[i] << 4 | nib[i + 1]) }
        return out
    }

    private func ascii85Decode(_ d: [UInt8]) -> [UInt8] {
        var out = [UInt8](), tuple = [UInt32](), i = 0
        while i < d.count {
            let c = d[i]; i += 1
            if isWhite(c) { continue }
            if c == 0x7E { break }
            if c == 0x7A && tuple.isEmpty {
                out.append(contentsOf: [0, 0, 0, 0]); continue
            }
            guard c >= 0x21 && c <= 0x75 else { continue }
            tuple.append(UInt32(c - 0x21))
            if tuple.count == 5 {
                var v: UInt32 = 0
                for t in tuple { v = v &* 85 &+ t }
                out.append(contentsOf: [UInt8(v >> 24 & 0xFF), UInt8(v >> 16 & 0xFF),
                                        UInt8(v >> 8 & 0xFF), UInt8(v & 0xFF)])
                tuple.removeAll(keepingCapacity: true)
            }
        }
        if tuple.count > 1 {
            let n = tuple.count
            for _ in n..<5 { tuple.append(84) }
            var v: UInt32 = 0
            for t in tuple { v = v &* 85 &+ t }
            let full = [UInt8(v >> 24 & 0xFF), UInt8(v >> 16 & 0xFF), UInt8(v >> 8 & 0xFF), UInt8(v & 0xFF)]
            out.append(contentsOf: full.prefix(n - 1))
        }
        return out
    }

    private func pngPredictor(_ d: [UInt8], colors: Int, bpc: Int, columns: Int) -> [UInt8] {
        let bpp = max(1, colors * bpc / 8)
        let rowLen = (columns * colors * bpc + 7) / 8
        guard rowLen > 0 else { return d }
        var out = [UInt8](); out.reserveCapacity(d.count)
        var prev = [UInt8](repeating: 0, count: rowLen)
        var i = 0
        while i + 1 <= d.count - 1 {
            let ft = d[i]; i += 1
            guard i + rowLen <= d.count else { break }
            var row = Array(d[i..<(i + rowLen)]); i += rowLen
            switch ft {
            case 1: for k in bpp..<rowLen { row[k] = row[k] &+ row[k - bpp] }
            case 2: for k in 0..<rowLen { row[k] = row[k] &+ prev[k] }
            case 3:
                for k in 0..<rowLen {
                    let left = k >= bpp ? Int(row[k - bpp]) : 0
                    row[k] = row[k] &+ UInt8((left + Int(prev[k])) / 2 & 0xFF)
                }
            case 4:
                for k in 0..<rowLen {
                    let a = k >= bpp ? Int(row[k - bpp]) : 0
                    let b = Int(prev[k])
                    let c = k >= bpp ? Int(prev[k - bpp]) : 0
                    let p = a + b - c
                    let pa = abs(p - a), pb = abs(p - b), pc = abs(p - c)
                    let pr = (pa <= pb && pa <= pc) ? a : (pb <= pc ? b : c)
                    row[k] = row[k] &+ UInt8(pr & 0xFF)
                }
            default: break
            }
            out.append(contentsOf: row)
            prev = row
        }
        return out
    }

    lazy var pages: [PDFObject] = {
        if let catalog = objects.values.first(where: { $0.dictValue?["Type"]?.nameValue == "Catalog" }),
           let rootRef = catalog.dictValue?["Pages"] {
            var out = [PDFObject]()
            var seen = Set<Int>()
            collectPages(rootRef, into: &out, seen: &seen, depth: 0)
            if !out.isEmpty { return out }
        }
        return objects.keys.sorted().compactMap { k -> PDFObject? in
            let o = objects[k]!
            return o.dictValue?["Type"]?.nameValue == "Page" ? o : nil
        }
    }()

    private func collectPages(_ node: PDFObject, into out: inout [PDFObject],
                              seen: inout Set<Int>, depth: Int) {
        guard depth < 64 else { return }
        if case .reference(let n) = node {
            if seen.contains(n) { return }
            seen.insert(n)
        }
        guard let dict = resolve(node)?.dictValue else { return }
        let type = dict["Type"]?.nameValue
        if type == "Page" {
            out.append(resolve(node)!)
        } else if let kids = resolve(dict["Kids"])?.arrayValue {
            for kid in kids { collectPages(kid, into: &out, seen: &seen, depth: depth + 1) }
        } else if type == nil, dict["Contents"] != nil {
            out.append(resolve(node)!)
        }
    }

    func pageAttribute(_ page: PDFObject, _ key: String) -> PDFObject? {
        var cur: PDFObject? = page
        var hops = 0
        while let dict = resolve(cur)?.dictValue, hops < 64 {
            if let v = dict[key] { return resolve(v) }
            cur = dict["Parent"]; hops += 1
        }
        return nil
    }

    func pageContent(_ page: PDFObject) -> [UInt8] {
        guard let dict = page.dictValue, let contents = dict["Contents"] else { return [] }
        if let arr = resolve(contents)?.arrayValue {
            var out = [UInt8]()
            for c in arr {
                if let d = decodedStream(c) { out.append(contentsOf: d); out.append(0x0A) }
            }
            return out
        }
        return decodedStream(contents) ?? []
    }

    func mediaBox(_ page: PDFObject) -> CGRect {
        guard let arr = pageAttribute(page, "MediaBox")?.arrayValue, arr.count >= 4 else {
            return CGRect(x: 0, y: 0, width: 612, height: 792)
        }
        let v = arr.map { resolve($0)?.doubleValue ?? 0 }
        let x0 = min(v[0], v[2]), y0 = min(v[1], v[3])
        return CGRect(x: x0, y: y0, width: abs(v[2] - v[0]), height: abs(v[3] - v[1]))
    }
}

struct PDFFontInfo {
    var toUnicode: [Int: String] = [:]
    var bytesPerCode: Int = 1
    var isBold: Bool = false

    var widths: [Int: Double] = [:]
    var defaultWidth: Double = 0.5
    var simpleEncoding: Bool = true

    func advance(_ bytes: [UInt8], size: Double, charSpace: Double, wordSpace: Double) -> Double {
        var total = 0.0
        let step = bytesPerCode
        var i = 0
        while i < bytes.count {
            var code = 0
            for k in 0..<step where i + k < bytes.count { code = code << 8 | Int(bytes[i + k]) }
            i += step
            total += (widths[code] ?? defaultWidth) * size + charSpace
            if step == 1, code == 32, simpleEncoding { total += wordSpace }
        }
        return total
    }

    func glyphs(_ bytes: [UInt8], size: Double,
                charSpace: Double, wordSpace: Double) -> [(text: String, advance: Double)] {
        var out: [(text: String, advance: Double)] = []
        let step = bytesPerCode
        var i = 0
        while i < bytes.count {
            var code = 0
            var chunk = [UInt8]()
            for k in 0..<step where i + k < bytes.count {
                code = code << 8 | Int(bytes[i + k])
                chunk.append(bytes[i + k])
            }
            i += step
            var adv = (widths[code] ?? defaultWidth) * size + charSpace
            if step == 1, code == 32, simpleEncoding { adv += wordSpace }
            out.append((decode(chunk), adv))
        }
        return out
    }

    func decode(_ bytes: [UInt8]) -> String {
        var out = ""
        let step = bytesPerCode
        var i = 0
        while i < bytes.count {
            var code = 0
            for k in 0..<step where i + k < bytes.count { code = code << 8 | Int(bytes[i + k]) }
            i += step
            if let s = toUnicode[code] { out += s }
            else if step == 1, let scalar = Unicode.Scalar(UInt8(code)) as Unicode.Scalar?,
                    code >= 32, code < 127 {
                if toUnicode.isEmpty { out.unicodeScalars.append(scalar) }
            }
        }
        return out
    }
}

enum CMapParser {
    static func parse(_ data: [UInt8]) -> [Int: String] {
        var map = [Int: String]()
        var lex = PDFLexer(data, at: 0)
        var pending = [PDFToken]()

        func utf16BEString(_ b: [UInt8]) -> String {
            guard !b.isEmpty else { return "" }
            var units = [UInt16]()
            var i = 0
            while i + 1 < b.count { units.append(UInt16(b[i]) << 8 | UInt16(b[i + 1])); i += 2 }
            if i < b.count { units.append(UInt16(b[i]) << 8) }
            return String(decoding: units, as: UTF16.self)
        }
        func codeValue(_ b: [UInt8]) -> Int {
            var v = 0
            for byte in b.prefix(4) { v = v << 8 | Int(byte) }
            return v
        }

        while let t = lex.next() {
            if t.kind == .op && t.text == "beginbfchar" {
                pending.removeAll()
                while let x = lex.next() {
                    if x.kind == .op && x.text == "endbfchar" { break }
                    pending.append(x)
                    if pending.count == 2 {
                        if pending[0].kind == .string && pending[1].kind == .string {
                            map[codeValue(pending[0].bytes)] = utf16BEString(pending[1].bytes)
                        }
                        pending.removeAll()
                    }
                }
            } else if t.kind == .op && t.text == "beginbfrange" {
                var items = [PDFToken]()
                var depth = 0
                var arrayItems = [[UInt8]]()
                while let x = lex.next() {
                    if x.kind == .op && x.text == "endbfrange" { break }
                    if x.kind == .arrayOpen { depth = 1; arrayItems.removeAll(); continue }
                    if x.kind == .arrayClose {
                        depth = 0
                        if items.count == 2 {
                            let lo = codeValue(items[0].bytes)
                            for (k, dst) in arrayItems.enumerated() {
                                map[lo + k] = utf16BEString(dst)
                            }
                        }
                        items.removeAll()
                        continue
                    }
                    if depth == 1 { if x.kind == .string { arrayItems.append(x.bytes) }; continue }
                    items.append(x)
                    if items.count == 3 {
                        if items[0].kind == .string, items[1].kind == .string, items[2].kind == .string {
                            let lo = codeValue(items[0].bytes)
                            let hi = codeValue(items[1].bytes)
                            let dstBytes = items[2].bytes
                            let base = utf16BEString(dstBytes)
                            if hi >= lo, hi - lo < 65536 {
                                if let firstScalar = base.unicodeScalars.first, base.unicodeScalars.count == 1 {
                                    for k in 0...(hi - lo) {
                                        if let s = Unicode.Scalar(firstScalar.value + UInt32(k)) {
                                            map[lo + k] = String(Character(s))
                                        }
                                    }
                                } else {
                                    map[lo] = base
                                }
                            }
                        }
                        items.removeAll()
                    }
                }
            }
        }
        return map
    }
}

struct TextRun {
    var text: String
    var x: Double
    var y: Double
    var width: Double
    var size: Double
    var isBold: Bool
    var charBoxes: [ClosedRange<Double>] = []
}

struct TextCell {
    var text: String
    var minX: Double
    var maxX: Double
}

struct TextLine {
    var runs: [TextRun]
    var y: Double
    var minX: Double
    var maxX: Double
    var size: Double
    var text: String
    var cells: [TextCell]
    var charBoxes: [ClosedRange<Double>?] = []
    var underlines: [Range<Int>] = []
    var bullet: Bool = false

    static func merge(_ spans: [Range<Int>]) -> [Range<Int>] {
        var out = [Range<Int>]()
        for s in spans.sorted(by: { $0.lowerBound < $1.lowerBound }) {
            if let last = out.last, s.lowerBound <= last.upperBound {
                out[out.count - 1] = last.lowerBound..<max(last.upperBound, s.upperBound)
            } else {
                out.append(s)
            }
        }
        return out
    }
}

enum Layout {
    static let sameLine = 6.0
    static let cellGap = 8.0
    static let spaceGap = 1.2
}

struct PageGraphics {
    var rects: [CGRect] = []
}

struct TableGrid {
    var edges: [Double]
    var rowRules: [Double]
}

struct ExtractedPage {
    var index: Int
    var lines: [TextLine]
    var graphics: PageGraphics
    var mediaBox: CGRect
    var tables: [TableGrid] = []
}

struct PageExtractor {
    let file: PDFFile

    private struct Matrix {
        var a: Double = 1
        var b: Double = 0
        var c: Double = 0
        var d: Double = 1
        var e: Double = 0
        var f: Double = 0
        static let identity = Matrix()
        func concat(_ m: Matrix) -> Matrix {
            Matrix(a: a * m.a + b * m.c,
                   b: a * m.b + b * m.d,
                   c: c * m.a + d * m.c,
                   d: c * m.b + d * m.d,
                   e: e * m.a + f * m.c + m.e,
                   f: e * m.b + f * m.d + m.f)
        }
        func apply(_ x: Double, _ y: Double) -> (Double, Double) {
            (a * x + c * y + e, b * x + d * y + f)
        }
    }

    func extract(pageIndex: Int) -> ExtractedPage? {
        guard pageIndex >= 0, pageIndex < file.pages.count else { return nil }
        let page = file.pages[pageIndex]
        let content = file.pageContent(page)
        let fonts = loadFonts(page)
        let box = file.mediaBox(page)

        var runs = [TextRun]()
        var graphics = PageGraphics()
        run(content, fonts: fonts, resources: file.pageAttribute(page, "Resources")?.dictValue ?? [:],
            ctm: .identity, runs: &runs, graphics: &graphics, depth: 0)

        var lines = assembleLines(runs)
        markUnderlines(&lines, graphics: graphics)
        markBullets(&lines, graphics: &graphics)
        return ExtractedPage(index: pageIndex,
                             lines: lines,
                             graphics: graphics,
                             mediaBox: box,
                             tables: findTables(graphics))
    }

    private func findTables(_ graphics: PageGraphics) -> [TableGrid] {
        let bars = graphics.rects.filter {
            $0.width >= 3 && $0.height <= 1.8 && $0.width > $0.height * 4
        }
        guard !bars.isEmpty else { return [] }

        var byY = [Double: [CGRect]]()
        for bar in bars { byY[Double(bar.midY).rounded(), default: []].append(bar) }

        var signatures = [String: [Double]]()
        var edgesFor = [String: [Double]]()
        for (y, group) in byY {
            let segs = group.sorted { $0.minX < $1.minX }
            var edges: [Double] = [Double(segs[0].minX)]
            var contiguous = true
            for (a, b) in zip(segs, segs.dropFirst()) {
                if abs(b.minX - a.maxX) > 1.5 { contiguous = false; break }
                edges.append(Double(b.minX))
            }
            edges.append(Double(segs[segs.count - 1].maxX))
            guard contiguous, edges.count >= 3 else { continue }
            guard !(0..<(edges.count - 1)).contains(where: { edges[$0 + 1] - edges[$0] < 15 })
            else { continue }

            let key = edges.map { String(Int($0.rounded())) }.joined(separator: ",")
            signatures[key, default: []].append(y)
            edgesFor[key] = edges
        }

        return signatures.compactMap { key, ys in
            guard ys.count >= 2, let edges = edgesFor[key] else { return nil }
            return TableGrid(edges: edges, rowRules: ys.sorted(by: >))
        }
    }

    private func markUnderlines(_ lines: inout [TextLine], graphics: PageGraphics) {
        let bars = graphics.rects.filter {
            $0.width >= 3 && $0.height <= 1.8 && $0.width > $0.height * 4
        }
        guard !bars.isEmpty else { return }

        for i in lines.indices {
            let line = lines[i]
            guard !line.charBoxes.isEmpty else { continue }
            let lowest = line.y
            var spans = [Range<Int>]()
            for bar in bars {
                let mid = bar.midY
                guard mid <= lowest + 0.8, mid >= lowest - max(line.size, 6) * 0.5 else { continue }
                var lo = Int.max, hi = -1
                for (idx, box) in line.charBoxes.enumerated() {
                    guard let box else { continue }
                    if box.upperBound > bar.minX - 0.8 && box.lowerBound < bar.maxX + 0.8 {
                        lo = min(lo, idx); hi = max(hi, idx)
                    }
                }
                if hi - lo >= 1 { spans.append(lo..<(hi + 1)) }
            }
            lines[i].underlines = TextLine.merge(spans)
        }
    }

    private func markBullets(_ lines: inout [TextLine], graphics: inout PageGraphics) {
        struct Hit { var line: Int; var rect: Int; var x: Double }
        var hits = [Hit]()

        for (gi, r) in graphics.rects.enumerated() {
            let w = Double(r.width), h = Double(r.height)
            guard w >= 1.5, w <= 6, h >= 1.5, h <= 6,
                  max(w, h) <= min(w, h) * 1.6 else { continue }
            let crowded = graphics.rects.enumerated().contains { oi, o in
                oi != gi && o.minX - 3.5 < r.maxX && r.minX < o.maxX + 3.5
                    && o.minY < r.maxY && r.minY < o.maxY
            }
            if crowded { continue }
            guard let li = lines.firstIndex(where: { line in
                !line.text.trimmed.isEmpty
                    && Double(r.maxX) <= line.minX + 1
                    && Double(r.minX) >= line.minX - 26
                    && Double(r.midY) <= line.y + 9
                    && Double(r.midY) >= line.y - 2
            }) else { continue }
            let line = lines[li]
            let between = graphics.rects.enumerated().contains { oi, o in
                oi != gi && Double(o.minX) >= Double(r.maxX) - 0.5
                    && Double(o.maxX) <= line.minX + 1
                    && Double(o.minY) < line.y + 9 && Double(o.maxY) > line.y - 2
            }
            if between { continue }
            hits.append(Hit(line: li, rect: gi, x: Double(r.minX)))
        }

        var byIndent = [Int: [Hit]]()
        for h in hits { byIndent[Int(h.x.rounded()), default: []].append(h) }

        var painted = Set<Int>()
        for (_, group) in byIndent where Set(group.map(\.line)).count >= 2 {
            for h in group {
                lines[h.line].bullet = true
                painted.insert(h.rect)
            }
        }
        guard !painted.isEmpty else { return }
        graphics.rects = graphics.rects.enumerated()
            .filter { !painted.contains($0.offset) }
            .map(\.element)
    }

    private func loadFonts(_ page: PDFObject) -> [String: PDFFontInfo] {
        guard let res = file.pageAttribute(page, "Resources")?.dictValue else { return [:] }
        return loadFonts(resources: res)
    }

    private func loadFonts(resources: [String: PDFObject]) -> [String: PDFFontInfo] {
        guard let fontDict = file.resolve(resources["Font"])?.dictValue else { return [:] }
        var out = [String: PDFFontInfo]()
        for (name, ref) in fontDict {
            guard let fd = file.resolve(ref)?.dictValue else { continue }
            var info = PDFFontInfo()
            let subtype = fd["Subtype"]?.nameValue ?? ""
            info.bytesPerCode = (subtype == "Type0") ? 2 : 1

            if subtype == "Type0", let enc = file.resolve(fd["Encoding"])?.nameValue,
               !enc.hasPrefix("Identity") {
                info.bytesPerCode = 2
            }
            if let tu = fd["ToUnicode"], let d = file.decodedStream(tu) {
                info.toUnicode = CMapParser.parse(d)
            }
            loadWidths(into: &info, font: fd, subtype: subtype)
            let base = file.resolve(fd["BaseFont"])?.nameValue ?? ""
            info.isBold = base.lowercased().contains("bold")
            if !info.isBold, let desc = file.resolve(fd["FontDescriptor"])?.dictValue {
                if let flags = file.resolve(desc["Flags"])?.intValue, flags & (1 << 18) != 0 { info.isBold = true }
                if let sw = file.resolve(desc["StemV"])?.doubleValue, sw >= 120 { info.isBold = true }
            }
            if !info.isBold, let descendants = file.resolve(fd["DescendantFonts"])?.arrayValue,
               let d0 = file.resolve(descendants.first)?.dictValue,
               let desc = file.resolve(d0["FontDescriptor"])?.dictValue,
               let flags = file.resolve(desc["Flags"])?.intValue, flags & (1 << 18) != 0 {
                info.isBold = true
            }
            out[name] = info
        }
        return out
    }

    private func loadWidths(into info: inout PDFFontInfo, font fd: [String: PDFObject], subtype: String) {
        var scale = 0.001
        if subtype == "Type3" {
            if let m = file.resolve(fd["FontMatrix"])?.arrayValue, m.count >= 1,
               let a = file.resolve(m[0])?.doubleValue, a != 0 {
                scale = a
            } else {
                scale = 0.001
            }
            info.simpleEncoding = false
        }

        if subtype == "Type0" {
            info.simpleEncoding = false
            guard let descendants = file.resolve(fd["DescendantFonts"])?.arrayValue,
                  let d0 = file.resolve(descendants.first)?.dictValue else { return }
            info.defaultWidth = (file.resolve(d0["DW"])?.doubleValue ?? 1000) * scale
            guard let w = file.resolve(d0["W"])?.arrayValue else { return }
            var i = 0
            while i < w.count {
                guard let first = file.resolve(w[i])?.intValue else { break }
                if i + 1 < w.count, let list = file.resolve(w[i + 1])?.arrayValue {
                    for (k, item) in list.enumerated() {
                        if let v = file.resolve(item)?.doubleValue { info.widths[first + k] = v * scale }
                    }
                    i += 2
                } else if i + 2 < w.count,
                          let last = file.resolve(w[i + 1])?.intValue,
                          let v = file.resolve(w[i + 2])?.doubleValue {
                    if last >= first, last - first < 65536 {
                        for c in first...last { info.widths[c] = v * scale }
                    }
                    i += 3
                } else { break }
            }
            return
        }

        if let firstChar = file.resolve(fd["FirstChar"])?.intValue,
           let widths = file.resolve(fd["Widths"])?.arrayValue {
            for (k, item) in widths.enumerated() {
                if let v = file.resolve(item)?.doubleValue { info.widths[firstChar + k] = v * scale }
            }
        }
        if let desc = file.resolve(fd["FontDescriptor"])?.dictValue,
           let mw = file.resolve(desc["MissingWidth"])?.doubleValue {
            info.defaultWidth = mw * scale
        } else if subtype == "Type3" {
            info.defaultWidth = 0
        }
    }

    private func run(_ content: [UInt8], fonts: [String: PDFFontInfo],
                     resources: [String: PDFObject], ctm initialCTM: Matrix,
                     runs: inout [TextRun], graphics: inout PageGraphics, depth: Int) {
        guard depth < 8 else { return }

        var lex = PDFLexer(content, at: 0)
        var operands = [PDFObject]()
        var arrayStack: [[PDFObject]] = []

        var ctm = initialCTM
        var ctmStack = [Matrix]()
        var tm = Matrix.identity, tlm = Matrix.identity
        var font = PDFFontInfo(), fontSize = 1.0
        var leading = 0.0, charSpace = 0.0, wordSpace = 0.0, hScale = 1.0, rise = 0.0
        var renderMode = 0

        var pathMinX = Double.infinity, pathMinY = Double.infinity
        var pathMaxX = -Double.infinity, pathMaxY = -Double.infinity
        var pathHasPoints = false
        var cx = 0.0, cy = 0.0

        func notePoint(_ x: Double, _ y: Double) {
            let (ux, uy) = ctm.apply(x, y)
            pathMinX = min(pathMinX, ux); pathMaxX = max(pathMaxX, ux)
            pathMinY = min(pathMinY, uy); pathMaxY = max(pathMaxY, uy)
            pathHasPoints = true
        }
        func resetPath() {
            pathMinX = .infinity; pathMinY = .infinity
            pathMaxX = -.infinity; pathMaxY = -.infinity
            pathHasPoints = false
        }
        func paintPath() {
            if pathHasPoints, pathMaxX > pathMinX || pathMaxY > pathMinY {
                graphics.rects.append(CGRect(x: pathMinX, y: pathMinY,
                                             width: pathMaxX - pathMinX,
                                             height: pathMaxY - pathMinY))
            }
            resetPath()
        }

        func num(_ i: Int) -> Double {
            let idx = operands.count - 1 - i
            guard idx >= 0 else { return 0 }
            return operands[idx].doubleValue ?? 0
        }

        func showText(_ items: [PDFObject]) {
            guard renderMode != 3, renderMode != 7 else {
                return
            }
            var buffer = ""
            var pieceStarts: [(count: Int, x: Double)] = []
            let startTm = tm
            for item in items {
                switch item {
                case .string(let b):
                    for g in font.glyphs(b, size: fontSize,
                                         charSpace: charSpace, wordSpace: wordSpace) {
                        pieceStarts.append((g.text.count, tm.concat(ctm).e))
                        buffer += g.text
                        tm = Matrix(a: 1, b: 0, c: 0, d: 1,
                                    e: g.advance * hScale, f: 0).concat(tm)
                    }
                case .number(let adj):
                    let shift = -adj / 1000.0 * fontSize * hScale
                    tm = Matrix(a: 1, b: 0, c: 0, d: 1, e: shift, f: 0).concat(tm)
                default: break
                }
            }
            guard !buffer.isEmpty else { return }
            let m = startTm.concat(ctm)
            let endM = tm.concat(ctm)
            let effSize = fontSize * sqrt(abs(m.a * m.d - m.b * m.c)).nonZero(else: 1)
            let advance = abs(endM.e - m.e)

            var boxes = [ClosedRange<Double>]()
            boxes.reserveCapacity(buffer.count)
            for (i, piece) in pieceStarts.enumerated() where piece.count > 0 {
                let next = i + 1 < pieceStarts.count ? pieceStarts[i + 1].x : endM.e
                let lo = min(piece.x, next), hi = max(piece.x, next)
                let step = (hi - lo) / Double(piece.count)
                for k in 0..<piece.count {
                    boxes.append((lo + step * Double(k))...(lo + step * Double(k + 1)))
                }
            }
            runs.append(TextRun(text: buffer, x: m.e, y: m.f,
                                width: advance,
                                size: effSize, isBold: font.isBold,
                                charBoxes: boxes.count == buffer.count ? boxes : []))
        }

        while let tok = lex.next() {
            switch tok.kind {
            case .number: operands.append(.number(tok.number))
            case .string: operands.append(.string(tok.bytes))
            case .name: operands.append(.name(tok.text))
            case .arrayOpen: arrayStack.append(operands); operands = []
            case .arrayClose:
                let inner = operands
                operands = arrayStack.popLast() ?? []
                operands.append(.array(inner))
            case .dictOpen:
                var p = PDFObjectParser(content, at: lex.pos)
                var dict = [String: PDFObject]()
                while let t = p.lexer.next() {
                    if t.kind == .dictClose { break }
                    guard t.kind == .name, let v = p.parseObject() else { continue }
                    dict[t.text] = v
                }
                lex.pos = p.lexer.pos
                operands.append(.dictionary(dict))
            case .dictClose: break
            case .op:
                switch tok.text {
                case "q": ctmStack.append(ctm)
                case "Q": ctm = ctmStack.popLast() ?? .identity
                case "cm":
                    ctm = Matrix(a: num(5), b: num(4), c: num(3),
                                 d: num(2), e: num(1), f: num(0)).concat(ctm)
                case "gs": break

                case "m": cx = num(1); cy = num(0); notePoint(cx, cy)
                case "l": cx = num(1); cy = num(0); notePoint(cx, cy)
                case "c":
                    notePoint(num(5), num(4)); notePoint(num(3), num(2))
                    cx = num(1); cy = num(0); notePoint(cx, cy)
                case "v":
                    notePoint(num(3), num(2)); cx = num(1); cy = num(0); notePoint(cx, cy)
                case "y":
                    notePoint(num(3), num(2)); cx = num(1); cy = num(0); notePoint(cx, cy)
                case "h": break
                case "re":
                    let x = num(3), y = num(2), w = num(1), h = num(0)
                    notePoint(x, y); notePoint(x + w, y); notePoint(x + w, y + h); notePoint(x, y + h)
                    cx = x; cy = y

                case "f", "F", "f*", "B", "B*", "b", "b*", "S", "s": paintPath()
                case "n": resetPath()
                case "W", "W*": break

                case "BT": tm = .identity; tlm = .identity
                case "ET": break
                case "Tf":
                    if case .name(let fname)? = operands.dropLast().last ?? operands.last {
                        font = fonts[fname] ?? PDFFontInfo()
                    }
                    fontSize = num(0)
                case "Td":
                    tlm = Matrix(a: 1, b: 0, c: 0, d: 1, e: num(1), f: num(0)).concat(tlm); tm = tlm
                case "TD":
                    leading = -num(0)
                    tlm = Matrix(a: 1, b: 0, c: 0, d: 1, e: num(1), f: num(0)).concat(tlm); tm = tlm
                case "Tm":
                    tlm = Matrix(a: num(5), b: num(4), c: num(3), d: num(2), e: num(1), f: num(0))
                    tm = tlm
                case "T*":
                    tlm = Matrix(a: 1, b: 0, c: 0, d: 1, e: 0, f: -leading).concat(tlm); tm = tlm
                case "TL": leading = num(0)
                case "Tc": charSpace = num(0)
                case "Tw": wordSpace = num(0)
                case "Tz": hScale = num(0) / 100.0
                case "Ts": rise = num(0)
                case "Tr": renderMode = Int(num(0))
                case "Tj": showText([operands.last ?? .null])
                case "TJ":
                    if case .array(let items)? = operands.last { showText(items) }
                case "'":
                    tlm = Matrix(a: 1, b: 0, c: 0, d: 1, e: 0, f: -leading).concat(tlm); tm = tlm
                    showText([operands.last ?? .null])
                case "\"":
                    wordSpace = num(2); charSpace = num(1)
                    tlm = Matrix(a: 1, b: 0, c: 0, d: 1, e: 0, f: -leading).concat(tlm); tm = tlm
                    showText([operands.last ?? .null])

                case "Do":
                    if case .name(let xname)? = operands.last,
                       let xobjs = file.resolve(resources["XObject"])?.dictValue,
                       let xref = xobjs[xname], let xdict = file.resolve(xref)?.dictValue {
                        let sub = xdict["Subtype"]?.nameValue
                        if sub == "Image" {
                            let corners = [(0.0, 0.0), (1.0, 0.0), (1.0, 1.0), (0.0, 1.0)].map { ctm.apply($0.0, $0.1) }
                            let xs = corners.map(\.0), ys = corners.map(\.1)
                            graphics.rects.append(CGRect(x: xs.min()!, y: ys.min()!,
                                                         width: xs.max()! - xs.min()!,
                                                         height: ys.max()! - ys.min()!))
                        } else if sub == "Form", let body = file.decodedStream(xref) {
                            var formCTM = ctm
                            if let mtx = file.resolve(xdict["Matrix"])?.arrayValue, mtx.count >= 6 {
                                let v = mtx.map { file.resolve($0)?.doubleValue ?? 0 }
                                formCTM = Matrix(a: v[0], b: v[1], c: v[2], d: v[3], e: v[4], f: v[5]).concat(ctm)
                            }
                            let formRes = file.resolve(xdict["Resources"])?.dictValue ?? resources
                            let formFonts = loadFonts(resources: formRes).isEmpty ? fonts : loadFonts(resources: formRes)
                            run(body, fonts: formFonts, resources: formRes, ctm: formCTM,
                                runs: &runs, graphics: &graphics, depth: depth + 1)
                        }
                    }
                case "BI":
                    if let ei = find(content, "EI", from: lex.pos) { lex.pos = ei + 2 }
                    let corners = [(0.0, 0.0), (1.0, 0.0), (1.0, 1.0), (0.0, 1.0)].map { ctm.apply($0.0, $0.1) }
                    let xs = corners.map(\.0), ys = corners.map(\.1)
                    graphics.rects.append(CGRect(x: xs.min()!, y: ys.min()!,
                                                 width: xs.max()! - xs.min()!,
                                                 height: ys.max()! - ys.min()!))
                default: break
                }
                _ = wordSpace; _ = rise
                operands.removeAll(keepingCapacity: true)
            }
        }
    }

    private func spliceInlineRuns(_ items: [TextRun]) -> [TextRun] {
        var out = [TextRun]()
        for r in items {
            guard let host = out.indices.last(where: {
                !out[$0].charBoxes.isEmpty
                    && r.x > out[$0].x
                    && r.x < out[$0].x + out[$0].width
            }) else { out.append(r); continue }

            var at = out[host].charBoxes.firstIndex { $0.lowerBound > r.x }
                ?? out[host].text.count
            at = min(max(at, 0), out[host].text.count)

            let idx = out[host].text.index(out[host].text.startIndex, offsetBy: at)
            out[host].text.insert(contentsOf: r.text, at: idx)

            if r.charBoxes.count == r.text.count {
                out[host].charBoxes.insert(contentsOf: r.charBoxes, at: at)
            } else {
                out[host].charBoxes = []
            }
            out[host].width = max(out[host].width,
                                  r.x + r.width - out[host].x)
        }
        return out
    }

    private func assembleLines(_ runs: [TextRun]) -> [TextLine] {
        guard !runs.isEmpty else { return [] }
        let sorted = runs.sorted { a, b in
            if abs(a.y - b.y) > 0.75 { return a.y > b.y }
            return a.x < b.x
        }
        var groups = [[TextRun]]()
        for r in sorted {
            if var last = groups.last, let ref = last.first,
               abs(ref.y - r.y) <= Layout.sameLine {
                last.append(r); groups[groups.count - 1] = last
            } else {
                groups.append([r])
            }
        }
        return groups.map { group in
            let items = spliceInlineRuns(group.sorted { $0.x < $1.x })
            var packed = [(ch: Character, box: ClosedRange<Double>?)]()
            var cells = [TextCell]()
            var cellStartIndex = 0
            var currentStart = items.first?.x ?? 0
            var currentEnd = currentStart
            var prevEnd: Double? = nil

            func flushCell() {
                let text = String(packed[cellStartIndex...].map(\.ch)).trimmed
                if !text.isEmpty {
                    cells.append(TextCell(text: text, minX: currentStart, maxX: currentEnd))
                }
            }

            for r in items {
                if let pe = prevEnd {
                    let gap = r.x - pe
                    if gap > Layout.cellGap {
                        flushCell()
                        packed.append((" ", nil))
                        cellStartIndex = packed.count
                        currentStart = r.x
                    } else if gap > Layout.spaceGap,
                              packed.last?.ch != " ", !r.text.hasPrefix(" ") {
                        packed.append((" ", nil))
                    }
                }
                if packed.count == cellStartIndex { currentStart = r.x }
                for (i, ch) in r.text.enumerated() {
                    packed.append((ch, i < r.charBoxes.count ? r.charBoxes[i] : nil))
                }
                currentEnd = r.x + r.width
                prevEnd = currentEnd
            }
            flushCell()

            var squeezed = [(ch: Character, box: ClosedRange<Double>?)]()
            for p in packed {
                if p.ch.isWhitespace {
                    if squeezed.last?.ch == " " { continue }
                    squeezed.append((" ", p.box))
                } else {
                    squeezed.append(p)
                }
            }
            while squeezed.first?.ch == " " { squeezed.removeFirst() }
            while squeezed.last?.ch == " " { squeezed.removeLast() }

            return TextLine(runs: items,
                            y: items.map(\.y).max() ?? 0,
                            minX: items.map(\.x).min() ?? 0,
                            maxX: items.map { $0.x + $0.width }.max() ?? 0,
                            size: items.map(\.size).max() ?? 9,
                            text: String(squeezed.map(\.ch)),
                            cells: cells,
                            charBoxes: squeezed.map(\.box))
        }
    }
}

extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }

    var squeezed: String {
        var out = ""
        var lastWasSpace = false
        for ch in self {
            let isSpace = ch == " " || ch == "\t" || ch == "\u{00A0}"
            if isSpace {
                if !lastWasSpace { out.append(" ") }
                lastWasSpace = true
            } else {
                out.append(ch); lastWasSpace = false
            }
        }
        return out.trimmed
    }
}

extension Double {
    func nonZero(else fallback: Double) -> Double { abs(self) < 1e-9 ? fallback : self }
}
