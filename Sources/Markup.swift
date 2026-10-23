import SwiftUI

enum Markup {

    enum Style: String, CaseIterable, Identifiable {
        case bold, italic, underline, highlight

        var id: String { rawValue }

        var marker: String {
            switch self {
            case .bold: return "**"
            case .italic: return "*"
            case .underline: return "++"
            case .highlight: return "=="
            }
        }

        var symbol: String {
            switch self {
            case .bold: return "bold"
            case .italic: return "italic"
            case .underline: return "underline"
            case .highlight: return "highlighter"
            }
        }

        var title: String {
            switch self {
            case .bold: return L("Bold")
            case .italic: return L("Italic")
            case .underline: return L("Underline")
            case .highlight: return L("Highlight")
            }
        }

        static var byLength: [Style] { [.bold, .underline, .highlight, .italic] }
    }

    static func plain(_ text: String) -> String {
        var out = ""
        forEachRun(in: text) { piece, _ in out += piece }
        return out
    }

    static func isFormatted(_ text: String) -> Bool { plain(text) != text }

    static func attributed(_ text: String, font: Font,
                           highlight: Color = Palette.highlight(0)) -> AttributedString {
        var out = AttributedString()
        forEachRun(in: text) { piece, styles in
            var run = AttributedString(piece)
            var f = font
            if styles.contains(.bold) { f = f.bold() }
            if styles.contains(.italic) { f = f.italic() }
            run.font = f
            if styles.contains(.underline) { run.underlineStyle = .single }
            if styles.contains(.highlight) { run.backgroundColor = highlight }
            out += run
        }
        return out
    }

    private static func forEachRun(in text: String,
                                   _ body: (String, Set<Style>) -> Void) {
        let chars = Array(text)
        var active = Set<Style>()
        var buffer = ""
        var i = 0

        while i < chars.count {
            if let style = marker(at: i, in: chars, active: active) {
                if !buffer.isEmpty { body(buffer, active); buffer = "" }
                if active.contains(style) { active.remove(style) } else { active.insert(style) }
                i += style.marker.count
                continue
            }
            buffer.append(chars[i])
            i += 1
        }
        if !buffer.isEmpty { body(buffer, active) }
    }

    private static func marker(at i: Int, in chars: [Character],
                               active: Set<Style>) -> Style? {
        for style in Style.byLength {
            let m = Array(style.marker)
            guard i + m.count <= chars.count,
                  Array(chars[i..<(i + m.count)]) == m else { continue }
            if style == .italic, i + 1 < chars.count, chars[i + 1] == "*" { continue }
            if active.contains(style) {
                return closesHere(i, in: chars) ? style : nil
            }
            guard opensHere(i + m.count, in: chars) else { return nil }
            return closes(style, after: i + m.count, in: chars) ? style : nil
        }
        return nil
    }

    private static func opensHere(_ i: Int, in chars: [Character]) -> Bool {
        i < chars.count && !chars[i].isWhitespace
    }

    private static func closesHere(_ i: Int, in chars: [Character]) -> Bool {
        i > 0 && !chars[i - 1].isWhitespace
    }

    private static func closes(_ style: Style, after start: Int, in chars: [Character]) -> Bool {
        let m = Array(style.marker)
        guard start < chars.count else { return false }
        var i = start
        while i + m.count <= chars.count {
            if Array(chars[i..<(i + m.count)]) == m {
                if style == .italic, i + 1 < chars.count, chars[i + 1] == "*" {
                    i += 1
                    continue
                }
                if i > start, closesHere(i, in: chars) { return true }
            }
            i += 1
        }
        return false
    }

    static func toggle(_ style: Style, in text: String,
                       range: Range<Int>) -> (text: String, range: Range<Int>) {
        let chars = Array(text)
        let lower = max(0, min(range.lowerBound, chars.count))
        let upper = max(lower, min(range.upperBound, chars.count))
        guard upper > lower else { return (text, range) }

        let m = Array(style.marker)
        let n = m.count

        if lower >= n, upper + n <= chars.count,
           Array(chars[(lower - n)..<lower]) == m,
           Array(chars[upper..<(upper + n)]) == m {
            var next = chars
            next.removeSubrange(upper..<(upper + n))
            next.removeSubrange((lower - n)..<lower)
            return (String(next), (lower - n)..<(upper - n))
        }
        if upper - lower >= 2 * n,
           Array(chars[lower..<(lower + n)]) == m,
           Array(chars[(upper - n)..<upper]) == m {
            var next = chars
            next.removeSubrange((upper - n)..<upper)
            next.removeSubrange(lower..<(lower + n))
            return (String(next), lower..<(upper - 2 * n))
        }

        var next = chars
        next.insert(contentsOf: m, at: upper)
        next.insert(contentsOf: m, at: lower)
        return (String(next), (lower + n)..<(upper + n))
    }
}

struct MarkupField: NSViewRepresentable {
    @Binding var text: String
    @Binding var selection: Range<Int>
    var height: CGFloat = 62

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSTextView.scrollableTextView()
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        guard let view = scroll.documentView as? NSTextView else { return scroll }
        view.delegate = context.coordinator
        view.isRichText = false
        view.font = .systemFont(ofSize: 12.5)
        view.drawsBackground = false
        view.textContainerInset = NSSize(width: 4, height: 5)
        view.appearance = NSAppearance(named: .aqua)
        view.string = text
        context.coordinator.view = view
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let view = scroll.documentView as? NSTextView else { return }
        if view.string != text {
            let caret = view.selectedRange()
            view.string = text
            let limit = (text as NSString).length
            view.setSelectedRange(NSRange(location: min(caret.location, limit),
                                          length: min(caret.length, limit - min(caret.location, limit))))
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: MarkupField
        weak var view: NSTextView?

        init(_ parent: MarkupField) { self.parent = parent }

        func textDidChange(_ notification: Notification) {
            guard let view = notification.object as? NSTextView else { return }
            parent.text = view.string
            report(view)
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard let view = notification.object as? NSTextView else { return }
            report(view)
        }

        private func report(_ view: NSTextView) {
            let ns = view.selectedRange()
            let text = view.string as NSString
            let lower = text.substring(to: min(ns.location, text.length)).count
            let upper = lower + text.substring(with: NSRange(
                location: min(ns.location, text.length),
                length: min(ns.length, text.length - min(ns.location, text.length)))).count
            parent.selection = lower..<upper
        }

        func select(_ range: Range<Int>) {
            guard let view else { return }
            let text = view.string as NSString
            let prefix = String(view.string.prefix(range.lowerBound)) as NSString
            let body = String(view.string.dropFirst(range.lowerBound)
                .prefix(range.count)) as NSString
            let location = min(prefix.length, text.length)
            view.setSelectedRange(NSRange(location: location,
                                          length: min(body.length, text.length - location)))
            view.window?.makeFirstResponder(view)
        }
    }
}
