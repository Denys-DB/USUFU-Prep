import SwiftUI
import AppKit
import CoreImage

private func themed(_ light: (Double, Double, Double),
                    _ dark: (Double, Double, Double)) -> Color {
    func ns(_ c: (Double, Double, Double)) -> NSColor {
        NSColor(srgbRed: c.0, green: c.1, blue: c.2, alpha: 1)
    }
    let lightColor = ns(light), darkColor = ns(dark)
    return Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? darkColor : lightColor
    })
}

enum Palette {

    private static let _paper = themed((0.957, 0.941, 0.910), (0.055, 0.086, 0.161))
    private static let _card = themed((0.992, 0.984, 0.965), (0.086, 0.129, 0.227))
    private static let _paperDeep = themed((0.925, 0.902, 0.855), (0.039, 0.063, 0.122))
    private static let _subtleFill = themed((0.945, 0.929, 0.898), (0.114, 0.165, 0.278))

    private static let _navy = themed((0.106, 0.165, 0.290), (0.949, 0.929, 0.878))
    private static let _navyDeep = themed((0.071, 0.118, 0.216), (0.984, 0.973, 0.945))
    private static let _navySoft = themed((0.906, 0.918, 0.941), (0.145, 0.204, 0.333))

    private static let _text = themed((0.106, 0.165, 0.290), (0.933, 0.914, 0.867))
    private static let _textMuted = themed((0.400, 0.443, 0.525), (0.616, 0.667, 0.757))
    private static let _secondaryText = themed((0.400, 0.443, 0.525), (0.616, 0.667, 0.757))

    private static let _onBrand = themed((0.992, 0.984, 0.965), (0.055, 0.086, 0.161))
    private static let _brandFill = themed((0.106, 0.165, 0.290), (0.902, 0.878, 0.812))

    private static let _hairline = themed((0.855, 0.824, 0.765), (0.157, 0.216, 0.345))
    private static let _border = themed((0.788, 0.749, 0.675), (0.220, 0.294, 0.443))

    private static let _brass = themed((0.663, 0.541, 0.318), (0.812, 0.686, 0.427))
    private static let _brassSoft = themed((0.914, 0.878, 0.804), (0.180, 0.169, 0.133))

    static let canvas = Color.white
    private static let _chrome = themed((0.976, 0.973, 0.965), (0.075, 0.114, 0.204))
    private static let _accent = themed((0.09, 0.35, 0.79), (0.404, 0.612, 0.941))
    private static let _accentSoft = themed((0.93, 0.95, 1.0), (0.098, 0.161, 0.290))

    static let highlights: [Color] = [
        Color(red: 1.00, green: 0.93, blue: 0.55),
        Color(red: 0.72, green: 0.91, blue: 0.72),
        Color(red: 0.72, green: 0.86, blue: 0.98),
        Color(red: 0.99, green: 0.78, blue: 0.84),
    ]

    static func highlight(_ index: Int) -> Color {
        highlights[((index % highlights.count) + highlights.count) % highlights.count]
    }

    static var introBackdrop: Color {
        Paper.stealth ? Color(red: 0.043, green: 0.047, blue: 0.055)
                      : Color(red: 0.055, green: 0.086, blue: 0.161)
    }
    static let introSeal = Color(red: 0.957, green: 0.941, blue: 0.910)

    private static let _correct = themed((0.129, 0.353, 0.220), (0.478, 0.769, 0.561))
    private static let _correctSoft = themed((0.902, 0.937, 0.898), (0.086, 0.180, 0.145))
    private static let _wrong = themed((0.514, 0.153, 0.153), (0.910, 0.518, 0.518))
    private static let _wrongSoft = themed((0.965, 0.918, 0.906), (0.204, 0.098, 0.098))

    static var paper: Color { Paper.stealth ? Paper.paper : _paper }
    static var card: Color { Paper.stealth ? Paper.card : _card }
    static var paperDeep: Color { Paper.stealth ? Paper.paperDeep : _paperDeep }
    static var subtleFill: Color { Paper.stealth ? Paper.subtleFill : _subtleFill }
    static var navy: Color { Paper.stealth ? Paper.navy : _navy }
    static var navyDeep: Color { Paper.stealth ? Paper.navyDeep : _navyDeep }
    static var navySoft: Color { Paper.stealth ? Paper.navySoft : _navySoft }
    static var text: Color { Paper.stealth ? Paper.text : _text }
    static var textMuted: Color { Paper.stealth ? Paper.textMuted : _textMuted }
    static var secondaryText: Color { Paper.stealth ? Paper.secondaryText : _secondaryText }
    static var onBrand: Color { Paper.stealth ? Paper.onBrand : _onBrand }
    static var brandFill: Color { Paper.stealth ? Paper.brandFill : _brandFill }
    static var hairline: Color { Paper.stealth ? Paper.hairline : _hairline }
    static var border: Color { Paper.stealth ? Paper.border : _border }
    static var brass: Color { Paper.stealth ? Paper.brass : _brass }
    static var brassSoft: Color { Paper.stealth ? Paper.brassSoft : _brassSoft }
    static var chrome: Color { Paper.stealth ? Paper.chrome : _chrome }
    static var accent: Color { Paper.stealth ? Paper.accent : _accent }
    static var accentSoft: Color { Paper.stealth ? Paper.accentSoft : _accentSoft }
    static var correct: Color { Paper.stealth ? Paper.correct : _correct }
    static var correctSoft: Color { Paper.stealth ? Paper.correctSoft : _correctSoft }
    static var wrong: Color { Paper.stealth ? Paper.wrong : _wrong }
    static var wrongSoft: Color { Paper.stealth ? Paper.wrongSoft : _wrongSoft }
}


struct PaperColor {
    let day: Color
    let night: Color
    var resolved: Color { Paper.stealth ? night : day }

    let nightComponents: (Double, Double, Double)

    init(_ day: (Double, Double, Double), _ night: (Double, Double, Double)) {
        self.day = Color(red: day.0, green: day.1, blue: day.2)
        self.night = Color(red: night.0, green: night.1, blue: night.2)
        self.nightComponents = night
    }
}

enum Paper {
    static var stealth = false

    private static let _paper = PaperColor((0.957, 0.941, 0.910), (0.067, 0.075, 0.090))
    private static let _card = PaperColor((0.992, 0.984, 0.965), (0.086, 0.094, 0.114))
    private static let _paperDeep = PaperColor((0.925, 0.902, 0.855), (0.031, 0.035, 0.043))
    private static let _subtleFill = PaperColor((0.945, 0.929, 0.898), (0.129, 0.137, 0.161))

    private static let _navy = PaperColor((0.106, 0.165, 0.290), (0.878, 0.886, 0.906))
    private static let _navyDeep = PaperColor((0.071, 0.118, 0.216), (0.949, 0.953, 0.965))
    private static let _navySoft = PaperColor((0.906, 0.918, 0.941), (0.169, 0.180, 0.212))

    private static let _text = PaperColor((0.106, 0.165, 0.290), (0.878, 0.886, 0.906))
    private static let _textMuted = PaperColor((0.400, 0.443, 0.525), (0.573, 0.596, 0.643))
    private static let _secondaryText = PaperColor((0.400, 0.443, 0.525), (0.573, 0.596, 0.643))

    private static let _onBrand = PaperColor((0.992, 0.984, 0.965), (0.918, 0.929, 0.949))
    private static let _brandFill = PaperColor((0.106, 0.165, 0.290), (0.145, 0.216, 0.376))

    private static let _hairline = PaperColor((0.855, 0.824, 0.765), (0.161, 0.169, 0.196))
    private static let _border = PaperColor((0.788, 0.749, 0.675), (0.235, 0.247, 0.286))

    private static let _brass = PaperColor((0.663, 0.541, 0.318), (0.706, 0.588, 0.376))
    private static let _brassSoft = PaperColor((0.914, 0.878, 0.804), (0.184, 0.157, 0.110))

    private static let _canvas = PaperColor((1, 1, 1), (0.043, 0.051, 0.063))
    private static let _chrome = PaperColor((0.976, 0.973, 0.965), (0.075, 0.082, 0.098))
    private static let _accent = PaperColor((0.09, 0.35, 0.79), (0.435, 0.596, 0.859))
    private static let _accentSoft = PaperColor((0.93, 0.95, 1.0), (0.106, 0.145, 0.235))
    private static let _accentFill = PaperColor((0.09, 0.35, 0.79), (0.157, 0.263, 0.427))
    private static let _accentFillDeep = PaperColor((0.071, 0.118, 0.216), (0.216, 0.345, 0.545))

    private static let _correct = PaperColor((0.129, 0.353, 0.220), (0.451, 0.729, 0.533))
    private static let _correctSoft = PaperColor((0.902, 0.937, 0.898), (0.075, 0.157, 0.110))
    private static let _wrong = PaperColor((0.514, 0.153, 0.153), (0.855, 0.482, 0.482))
    private static let _wrongSoft = PaperColor((0.965, 0.918, 0.906), (0.196, 0.086, 0.086))

    static var paper: Color { _paper.resolved }
    static var card: Color { _card.resolved }
    static var paperDeep: Color { _paperDeep.resolved }
    static var subtleFill: Color { _subtleFill.resolved }

    static var navy: Color { _navy.resolved }
    static var navyDeep: Color { _navyDeep.resolved }
    static var navySoft: Color { _navySoft.resolved }

    static var text: Color { _text.resolved }
    static var textMuted: Color { _textMuted.resolved }
    static var secondaryText: Color { _secondaryText.resolved }

    static var onBrand: Color { _onBrand.resolved }
    static var brandFill: Color { _brandFill.resolved }

    static var hairline: Color { _hairline.resolved }
    static var border: Color { _border.resolved }

    static var brass: Color { _brass.resolved }
    static var brassSoft: Color { _brassSoft.resolved }

    static var canvas: Color { _canvas.resolved }
    static var canvasNight: (Double, Double, Double) { _canvas.nightComponents }
    static var accentSoftNight: (Double, Double, Double) { _accentSoft.nightComponents }
    static var chrome: Color { _chrome.resolved }
    static var accent: Color { _accent.resolved }
    static var accentSoft: Color { _accentSoft.resolved }
    static var accentFill: Color { _accentFill.resolved }
    static var accentFillDeep: Color { _accentFillDeep.resolved }

    static var correct: Color { _correct.resolved }
    static var correctSoft: Color { _correctSoft.resolved }
    static var wrong: Color { _wrong.resolved }
    static var wrongSoft: Color { _wrongSoft.resolved }

    private static let _highlights: [PaperColor] = [
        PaperColor((1.00, 0.93, 0.55), (0.294, 0.243, 0.043)),
        PaperColor((0.72, 0.91, 0.72), (0.106, 0.271, 0.129)),
        PaperColor((0.72, 0.86, 0.98), (0.078, 0.239, 0.361)),
        PaperColor((0.99, 0.78, 0.84), (0.322, 0.129, 0.184)),
    ]

    static var highlights: [Color] { _highlights.map(\.resolved) }

    static func highlight(_ index: Int) -> Color {
        _highlights[((index % _highlights.count) + _highlights.count) % _highlights.count]
            .resolved
    }

    static var invertsFigures: Bool { stealth }
}

enum Appearance: String, Codable, CaseIterable {
    case system, light, dark

    var title: String {
        switch self {
        case .system: return L("Match the system")
        case .light: return L("Beige")
        case .dark: return L("Navy")
        }
    }
    var detail: String {
        switch self {
        case .system: return L("Follow whatever macOS is set to.")
        case .light: return L("Navy ink on beige paper.")
        case .dark: return L("Beige ink on navy paper.")
        }
    }
    var symbol: String {
        switch self {
        case .system: return "circle.lefthalf.filled"
        case .light: return "sun.max"
        case .dark: return "moon"
        }
    }

    var nsAppearance: NSAppearance? {
        switch self {
        case .system: return nil
        case .light: return NSAppearance(named: .aqua)
        case .dark: return NSAppearance(named: .darkAqua)
        }
    }
}

private struct WindowAppearance: NSViewRepresentable {
    let appearance: NSAppearance?

    func makeNSView(context: Context) -> NSView { NSView(frame: .zero) }

    func updateNSView(_ view: NSView, context: Context) {
        DispatchQueue.main.async {
            guard let window = view.window, window.appearance != appearance else { return }
            window.appearance = appearance
        }
    }
}

extension View {
    func iconHelp(_ text: String) -> some View {
        help(text).accessibilityLabel(text)
    }
}

extension View {
    func pinnedPaperWindow() -> some View {
        background(WindowAppearance(appearance: NSAppearance(named: Paper.stealth
                                                             ? .darkAqua : .aqua)))
            .pinnedPaper()
    }

    func pinsWindowToPaper(_ active: Bool) -> some View {
        background(WindowAppearance(
            appearance: active ? NSAppearance(named: Paper.stealth ? .darkAqua : .aqua) : nil))
    }

    func pinnedPaper() -> some View {
        environment(\.colorScheme, Paper.stealth ? .dark : .light)
            .environment(\.usufuPinnedLight, !Paper.stealth)
    }
}

private struct PinnedLightKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var usufuPinnedLight: Bool {
        get { self[PinnedLightKey.self] }
        set { self[PinnedLightKey.self] = newValue }
    }
}

enum Face {
    static func display(_ size: CGFloat, _ weight: Font.Weight = .semibold) -> Font {
        .system(size: size, weight: weight, design: .serif)
    }
    static func ui(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight)
    }
    static func figures(_ size: CGFloat, _ weight: Font.Weight = .semibold) -> Font {
        .system(size: size, weight: weight).monospacedDigit()
    }
}

enum Motion {
    static var reducedByChoice = false

    static var enabled: Bool {
        if reducedByChoice { return false }
        if UserDefaults.standard.bool(forKey: "SATPrepNoAnimation") { return false }
        return !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }

    static var quick: Animation? { enabled ? .easeOut(duration: 0.16) : nil }
    static var standard: Animation? { enabled ? .easeOut(duration: 0.26) : nil }
    static var settle: Animation? {
        enabled ? .spring(response: 0.34, dampingFraction: 0.78) : nil
    }
    static var fill: Animation? { enabled ? .easeOut(duration: 0.75) : nil }

    static func entrance(_ index: Int) -> Animation? {
        enabled ? .easeOut(duration: 0.42).delay(Double(index) * 0.05) : nil
    }
}

private struct Entrance: ViewModifier {
    let index: Int
    @State private var shown = !Motion.enabled

    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .offset(y: shown ? 0 : 12)
            .onAppear {
                guard !shown else { return }
                withAnimation(Motion.entrance(index)) { shown = true }
            }
    }
}

extension View {
    func entrance(_ index: Int) -> some View { modifier(Entrance(index: index)) }
}

private struct CountingText: View, Animatable {
    var value: Double
    var format: (Double) -> String

    var animatableData: Double {
        get { value }
        set { value = newValue }
    }

    var body: some View { Text(format(value)) }
}

struct Counter: View {
    let value: Double
    var format: (Double) -> String = { "\(Int($0.rounded()))" }

    @State private var shown: Double = 0

    var body: some View {
        CountingText(value: shown, format: format)
            .onAppear {
                guard Motion.enabled else { shown = value; return }
                withAnimation(Motion.fill) { shown = value }
            }
            .onChange(of: value) { new in
                withAnimation(Motion.standard) { shown = new }
            }
    }
}

struct GrowingBar: View {
    var value: Double
    var tint: Color
    var track: Color = Palette.subtleFill
    var height: CGFloat = 8
    var marker: Double? = nil

    @State private var shown: Double = 0

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Rectangle().fill(track)
                Rectangle().fill(tint)
                    .frame(width: geo.size.width * min(max(shown, 0), 1))
                if let marker {
                    Rectangle().fill(Palette.border)
                        .frame(width: 1)
                        .offset(x: geo.size.width * marker)
                }
            }
        }
        .frame(height: height)
        .onAppear {
            guard Motion.enabled else { shown = value; return }
            withAnimation(Motion.fill) { shown = value }
        }
        .onChange(of: value) { new in
            withAnimation(Motion.standard) { shown = new }
        }
    }
}

struct GoalRing: View {
    var fraction: Double
    var size: CGFloat = 46
    var lineWidth: CGFloat = 5
    var tint: Color = Palette.brass

    @State private var shown: Double = 0

    var body: some View {
        ZStack {
            Circle()
                .stroke(Palette.hairline, lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: min(max(shown, 0), 1))
                .stroke(tint, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .frame(width: size, height: size)
        .onAppear {
            guard Motion.enabled else { shown = fraction; return }
            withAnimation(Motion.fill.map { $0.delay(0.15) }) { shown = fraction }
        }
        .onChange(of: fraction) { new in
            withAnimation(Motion.settle) { shown = new }
        }
    }
}

struct Disclosure<Content: View>: View {
    let title: String
    var summary: String = ""
    @Binding var open: Bool
    @ViewBuilder var content: Content

    @State private var hovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button {
                withAnimation(Motion.settle) { open.toggle() }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(Palette.textMuted)
                        .rotationEffect(.degrees(open ? 90 : 0))
                    SectionLabel(text: title)
                    if !summary.isEmpty {
                        Text(summary)
                            .font(Face.ui(11))
                            .foregroundStyle(open ? Palette.textMuted : Palette.brass)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
                .background(hovering ? Palette.subtleFill.opacity(0.6) : .clear)
            }
            .buttonStyle(.plain)
            .onHover { hovering = $0 }

            if open {
                content
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .clipped()
    }
}

struct FlowRow: SwiftUI.Layout {
    var spacing: CGFloat = 8
    var lineSpacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews,
                      cache: inout ()) -> CGSize {
        let width: CGFloat = proposal.width ?? .infinity
        let lines = wrap(subviews, in: width)
        var height: CGFloat = 0
        var widest: CGFloat = 0
        for (i, line) in lines.enumerated() {
            height += line.height
            if i > 0 { height += lineSpacing }
            widest = max(widest, line.width)
        }
        return CGSize(width: min(width, widest), height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize,
                       subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for line in wrap(subviews, in: bounds.width) {
            var x = bounds.minX
            for index in line.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: y + (line.height - size.height) / 2),
                                      proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += line.height + lineSpacing
        }
    }

    private struct Line {
        var indices: [Int] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func wrap(_ subviews: Subviews, in width: CGFloat) -> [Line] {
        var lines = [Line()]
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            let needed = lines[lines.count - 1].indices.isEmpty
                ? size.width : lines[lines.count - 1].width + spacing + size.width
            if needed > width, !lines[lines.count - 1].indices.isEmpty {
                lines.append(Line())
            }
            var line = lines[lines.count - 1]
            line.width = line.indices.isEmpty ? size.width : line.width + spacing + size.width
            line.height = max(line.height, size.height)
            line.indices.append(index)
            lines[lines.count - 1] = line
        }
        return lines
    }
}

struct SectionLabel: View {
    let text: String
    var onPaper = false
    var body: some View {
        Text(text.uppercased())
            .font(Face.ui(10, .semibold))
            .tracking(1.3)
            .foregroundStyle(onPaper ? Paper.textMuted : Palette.textMuted)
    }
}

enum SidebarPanes {

    static func boundary(above: Double, below: Double,
                         floorAbove: Double, floorBelow: Double,
                         by travel: Double) -> (above: Double, below: Double) {
        let span = max(above + below, 0)
        let low = max(min(floorAbove, span), 0)
        let high = max(span - max(floorBelow, 0), low)
        let settled = min(max(above + travel, low), high)
        return (settled, span - settled)
    }

    static func divide(span: Double, stored: Double?,
                       floorAbove: Double, floorBelow: Double,
                       naturalAbove: Double) -> (above: Double, below: Double) {
        let want = stored ?? naturalAbove
        return boundary(above: want, below: max(span, 0) - want,
                        floorAbove: floorAbove, floorBelow: floorBelow, by: 0)
    }

    static func cursor(above: Double, below: Double,
                       floorAbove: Double, floorBelow: Double) -> NSCursor {
        switch (above - floorAbove > 0.5, below - floorBelow > 0.5) {
        case (true, true):   return .resizeUpDown
        case (true, false):  return .resizeUp
        case (false, true):  return .resizeDown
        case (false, false): return .arrow
        }
    }
}

enum WindowChrome {
    static func parkFocus(in sheet: NSWindow, openedBy event: NSEvent.EventType?) {
        if let event, [.keyDown, .keyUp, .flagsChanged].contains(event) { return }
        let holder = sheet.firstResponder
        guard !(holder is NSText), !(holder is NSTextView) else { return }
        sheet.makeFirstResponder(nil)
    }
    static func isMain(_ w: NSWindow) -> Bool {
        !(w is NSPanel) && w.sheetParent == nil
            && w.styleMask.contains(.titled) && w.styleMask.contains(.resizable)
            && (w.isVisible || w.isMiniaturized)
    }
    static let trafficLights: CGFloat = 30

    static let minWidth: CGFloat = 900
    static let minHeight: CGFloat = 620
}

struct Rule: View {
    var brass = false
    var onPaper = false
    var body: some View {
        Rectangle()
            .fill(brass ? (onPaper ? Paper.brass : Palette.brass).opacity(0.55)
                        : (onPaper ? Paper.hairline : Palette.hairline))
            .frame(height: 1)
    }
}

struct Panel<Content: View>: View {
    var title: String?
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let title {
                VStack(alignment: .leading, spacing: 7) {
                    SectionLabel(text: title)
                    Rule(brass: true).frame(width: 34)
                }
            }
            content
        }
        .padding(22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.card)
        .overlay(
            RoundedRectangle(cornerRadius: 4)
                .strokeBorder(Palette.hairline, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 4))
    }
}

enum TypeScale {
    static let pdfBodyPointSize: Double = 9.0
    static let defaultBodySize: Double = 15
    static let bodySizeRange: ClosedRange<Double> = 11...26

    static func imageScale(bodySize: Double) -> Double { bodySize / pdfBodyPointSize }
    static func clampBodySize(_ size: Double) -> Double {
        min(bodySizeRange.upperBound, max(bodySizeRange.lowerBound, size))
    }

    static let cardScaleRange: ClosedRange<Double> = 0.6...2.5

    static func clampCardScale(_ scale: Double) -> Double {
        min(cardScaleRange.upperBound, max(cardScaleRange.lowerBound, scale))
    }

    static func cardTerm(_ scale: Double, compact: Bool) -> Double {
        (compact ? 62 : 52) * clampCardScale(scale)
    }
    static func cardBody(_ scale: Double, compact: Bool) -> Double {
        (compact ? 30 : 26) * clampCardScale(scale)
    }
    static func cardExample(_ scale: Double, compact: Bool) -> Double {
        (compact ? 17 : 15) * clampCardScale(scale)
    }
}

enum QuestionLayout {
    static let textColumn: CGFloat = 720

    static let choiceChrome: CGFloat = 13 + 24 + 11 + 13 + 10 + 38

    static func widest(_ blocks: [ContentBlock]) -> Double {
        blocks.filter { $0.kind == .image }.map(drawnWidth).max() ?? 0
    }

    static func drawnWidth(_ block: ContentBlock) -> Double {
        guard block.kind == .image else { return 0 }
        guard block.hasWords else { return block.pointWidth }
        return block.inline.flatMap(\.runs).filter { $0.image != nil }.map(\.width).max() ?? 0
    }

    static func widest(choices: [Choice]) -> Double {
        widest(choices.flatMap(\.blocks))
    }

    static let displayLimit = 330.0

    static func isDisplay(_ block: ContentBlock, after previous: ContentBlock?) -> Bool {
        guard block.kind == .image else { return false }
        if block.centred { return true }
        guard block.pointWidth > 0, block.pointWidth < displayLimit else { return false }
        guard let previous, previous.kind == .text else { return true }
        let tail = previous.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let last = tail.last else { return true }
        return ".:?!;".contains(last)
    }

    static func figureScale(bodyPoints: Double, choicePoints: Double,
                            bodySize: Double, width: CGFloat) -> Double {
        let wanted = TypeScale.imageScale(bodySize: bodySize)
        guard width > 0 else { return wanted }
        var fit = 1.0
        if bodyPoints > 0 {
            fit = min(fit, Double(width) / (bodyPoints * wanted))
        }
        if choicePoints > 0 {
            fit = min(fit, Double(max(1, width - choiceChrome)) / (choicePoints * wanted))
        }
        return wanted * min(1, fit)
    }

    static func columnWidth(bodyPoints: Double, choicePoints: Double,
                            bodySize: Double, available: CGFloat) -> CGFloat {
        guard available > 0 else { return textColumn }
        let wanted = TypeScale.imageScale(bodySize: bodySize)
        let needed = max(CGFloat(bodyPoints * wanted),
                         CGFloat(choicePoints * wanted) + choiceChrome)
        return min(available, max(textColumn, needed))
    }
}

struct ContentBlockView: View {
    let block: ContentBlock
    let imagesDirectory: URL
    var bodySize: Double = 15
    var figureScale: Double? = nil
    var paneWidth: CGFloat = 0
    var centred = false
    var centresDisplays = true

    var body: some View {
        switch block.kind {
        case .text:
            Text(block.attributed)
                .font(.system(size: bodySize))
                .foregroundStyle(Paper.text)
                .lineSpacing(bodySize * 0.34)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        case .table:
            TableBlockView(rows: block.rows, bodySize: bodySize,
                           width: paneWidth > 0
                               ? min(paneWidth, QuestionLayout.textColumn)
                               : QuestionLayout.textColumn)
                .frame(maxWidth: QuestionLayout.textColumn, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .leading)
        case .image where block.hasWords:
            InlineBlockView(block: block, imagesDirectory: imagesDirectory, bodySize: bodySize,
                            scale: figureScale ?? TypeScale.imageScale(bodySize: bodySize),
                            paneWidth: paneWidth, centresDisplays: centresDisplays)
        case .image:
            BlockImage(block: block, imagesDirectory: imagesDirectory,
                       scale: figureScale ?? TypeScale.imageScale(bodySize: bodySize),
                       paneWidth: paneWidth, centred: centred || block.centred)
        }
    }
}

struct InlineBlockView: View {
    let block: ContentBlock
    let imagesDirectory: URL
    var bodySize: Double = 15
    var scale: Double
    var paneWidth: CGFloat = 0
    var centresDisplays = true

    var body: some View {
        VStack(alignment: .leading, spacing: bodySize * 0.8) {
            ForEach(Array(block.inline.enumerated()), id: \.offset) { _, para in
                if para.display, let run = para.runs.first {
                    IslandImage(run: run, imagesDirectory: imagesDirectory,
                                width: CGFloat(run.width * scale), paneWidth: paneWidth)
                        .frame(maxWidth: .infinity,
                               alignment: centresDisplays ? .center : .leading)
                } else {
                    paragraph(para.runs)
                        .font(.system(size: bodySize))
                        .foregroundStyle(Paper.text)
                        .lineSpacing(bodySize * 0.34)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .blendMode(Paper.invertsFigures ? .screen : .multiply)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(para.runs.compactMap(\.text).joined())
                }
            }
        }
    }

    private func paragraph(_ runs: [InlineRun]) -> Text {
        let font = NSFont.systemFont(ofSize: bodySize)
        let ratio = Double(font.xHeight) / (block.xHeight > 0 ? block.xHeight : QuestionParser.proseXHeight)
        var out = Text("")
        for run in runs {
            if let t = run.text {
                out = out + Text(t)
            } else if let image = ImageCache.shared.island(run, in: imagesDirectory) {
                let shown = NSImage(cgImage: image,
                                    size: NSSize(width: run.width * ratio, height: run.height * ratio))
                out = out + Text(Image(nsImage: shown)).baselineOffset(-run.depth * ratio)
            }
        }
        return out
    }
}

struct IslandImage: View {
    let run: InlineRun
    let imagesDirectory: URL
    var width: CGFloat
    var paneWidth: CGFloat = 0

    var body: some View {
        let shown = paneWidth > 0 ? min(width, paneWidth) : width
        let aspect = run.width > 0 ? CGFloat(run.height / run.width) : 0.2
        Group {
            if let image = ImageCache.shared.island(run, in: imagesDirectory) {
                Image(decorative: image, scale: 1)
                    .resizable()
                    .interpolation(.high)
                    .blendMode(Paper.invertsFigures ? .screen : .multiply)
            } else {
                RoundedRectangle(cornerRadius: 4).fill(Paper.subtleFill)
            }
        }
        .frame(width: shown, height: shown * aspect)
    }
}

func readableInk(on background: Color, in scheme: ColorScheme) -> Color {
    let appearance = NSAppearance(named: scheme == .dark ? .darkAqua : .aqua)
        ?? NSAppearance.currentDrawing()
    var ns = NSColor.black
    appearance.performAsCurrentDrawingAppearance {
        ns = NSColor(background).usingColorSpace(.sRGB) ?? .black
    }
    func linear(_ c: CGFloat) -> Double {
        let v = Double(c)
        return v <= 0.03928 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4)
    }
    let luminance = 0.2126 * linear(ns.redComponent)
        + 0.7152 * linear(ns.greenComponent)
        + 0.0722 * linear(ns.blueComponent)
    return luminance > 0.55
        ? Color(red: 0.09, green: 0.11, blue: 0.16)
        : Color(red: 0.98, green: 0.98, blue: 0.97)
}

extension View {
    @ViewBuilder
    func noFocusRing() -> some View {
        if #available(macOS 14.0, *) {
            self.focusEffectDisabled()
        } else {
            self.focusable(false)
        }
    }
}

struct KeyMonitor: ViewModifier {
    let handler: (NSEvent) -> Bool
    @State private var token: Any?

    func body(content: Content) -> some View {
        content
            .onAppear {
                guard token == nil else { return }
                token = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
                    let escape = event.keyCode == Key.escape
                    if !escape, let responder = NSApp.keyWindow?.firstResponder,
                       responder is NSTextView || responder is NSTextField
                        || responder is NSSearchField {
                        return event
                    }
                    return handler(event) ? nil : event
                }
            }
            .onDisappear {
                if let token { NSEvent.removeMonitor(token) }
                token = nil
            }
    }
}

extension View {
    func watchingKeys(_ handler: @escaping (NSEvent) -> Bool) -> some View {
        modifier(KeyMonitor(handler: handler))
    }
}

enum Key {
    static let space: UInt16 = 49
    static let leftArrow: UInt16 = 123
    static let rightArrow: UInt16 = 124
    static let escape: UInt16 = 53

    static func isPlain(_ event: NSEvent, character: String) -> Bool {
        guard !event.modifierFlags.intersects([.command, .control, .option]) else { return false }
        return event.charactersIgnoringModifiers == character
    }

    static func isPlain(_ event: NSEvent, code: UInt16) -> Bool {
        !event.modifierFlags.intersects([.command, .control, .option]) && event.keyCode == code
    }

    static func isCommand(_ event: NSEvent, anyOf characters: [String]) -> Bool {
        event.modifierFlags.contains(.command)
            && characters.contains(event.charactersIgnoringModifiers ?? "")
    }
}

extension NSEvent.ModifierFlags {
    func intersects(_ other: NSEvent.ModifierFlags) -> Bool {
        !intersection(other.union([])).isEmpty
    }
}

struct PaneWidthKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

extension View {
    func measuringPaneWidth(_ width: Binding<CGFloat>) -> some View {
        background(GeometryReader { geo in
            Color.clear.preference(key: PaneWidthKey.self, value: geo.size.width)
        })
        .onPreferenceChange(PaneWidthKey.self) { width.wrappedValue = $0 }
    }
}

enum TableFit {

    static func longestWord(in rows: [[String]]) -> String {
        rows.flatMap { $0 }
            .flatMap { $0.split(whereSeparator: { $0.isWhitespace }) }
            .map(String.init)
            .max { $0.count < $1.count } ?? ""
    }

    static func size(for word: String, width: CGFloat, base: Double,
                     bold: Bool = true) -> Double {
        guard width > 0, !word.isEmpty else { return base }
        var size = base
        while size > 8 {
            let font = NSFont.systemFont(ofSize: size, weight: bold ? .semibold : .regular)
            let measured = (word as NSString)
                .size(withAttributes: [.font: font]).width
            if measured <= width { return size }
            size -= 0.5
        }
        return 8
    }
}

struct TableBlockView: View {
    let rows: [[String]]
    var bodySize: Double = 15

    var width: CGFloat = 0

    @State private var laidOut: CGFloat = 0

    private var usableWidth: CGFloat { laidOut > 0 ? laidOut : width }

    private var columns: Int { rows.filter { $0.count > 1 }.map(\.count).max() ?? 1 }
    private var headerIndex: Int? { rows.firstIndex { $0.count > 1 } }

    private var nominalSize: Double {
        max(10, (bodySize - 1 - 1.5 * Double(max(0, columns - 4))).rounded())
    }
    private var cellPadding: CGFloat { columns <= 4 ? 10 : (columns <= 5 ? 6 : 4) }

    private var cellSize: Double {
        guard usableWidth > 0, columns > 0 else { return nominalSize }
        let column = usableWidth / CGFloat(columns) - cellPadding * 2 - 7
        return TableFit.size(for: TableFit.longestWord(in: rows),
                             width: column, base: nominalSize)
    }

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.offset) { r, row in
                let spanning = row.count == 1 && columns > 1
                HStack(spacing: 0) {
                    ForEach(Array(row.enumerated()), id: \.offset) { _, cell in
                        Text(cell)
                            .font(.system(size: cellSize,
                                          weight: spanning || r == headerIndex ? .semibold : .regular))
                            .foregroundStyle(Paper.text)
                            .multilineTextAlignment(spanning || r == headerIndex ? .center : .leading)
                            .minimumScaleFactor(0.65)
                            .frame(maxWidth: .infinity,
                                   alignment: spanning || r == headerIndex ? .center : .leading)
                            .padding(.horizontal, cellPadding)
                            .padding(.vertical, 6)
                            .frame(maxHeight: .infinity)
                            .background(r == headerIndex ? Paper.subtleFill : Color.clear)
                            .overlay(Rectangle().strokeBorder(Paper.border, lineWidth: 0.5))
                            .textSelection(.enabled)
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
            }
        }
        .measuringPaneWidth($laidOut)
        .overlay(Rectangle().strokeBorder(Paper.border, lineWidth: 1))
        .fixedSize(horizontal: false, vertical: true)
    }
}

struct BlockImage: View {
    let block: ContentBlock
    let imagesDirectory: URL
    let scale: Double
    var paneWidth: CGFloat = 0
    var centred = false

    var body: some View {
        let width = displayWidth
        image
            .frame(width: width, height: width * aspect)
            .frame(maxWidth: .infinity, alignment: centred ? .center : .leading)
    }

    private var aspect: CGFloat {
        guard block.pixelWidth > 0 else { return 0.2 }
        return CGFloat(block.pixelHeight / block.pixelWidth)
    }

    private var displayWidth: CGFloat {
        let natural = CGFloat(block.pointWidth * scale)
        guard natural > 0 else { return paneWidth > 0 ? paneWidth : QuestionLayout.textColumn }
        return paneWidth > 0 ? min(natural, paneWidth) : natural
    }

    @ViewBuilder
    private var image: some View {
        if let nsImage = ImageCache.shared.image(named: block.imageName, in: imagesDirectory) {
            Image(nsImage: nsImage)
                .resizable()
                .interpolation(.high)
                .blendMode(Paper.invertsFigures ? .screen : .multiply)
        } else {
            RoundedRectangle(cornerRadius: 4)
                .fill(Paper.subtleFill)
                .overlay(Text(L("Image missing")).font(.system(size: 11)).foregroundStyle(.secondary))
        }
    }
}

final class ImageCache {
    static let shared = ImageCache()
    private var store = NSCache<NSString, NSImage>()

    init() { store.countLimit = 400 }

    private var islands = NSCache<NSString, CGImage>()

    func island(_ run: InlineRun, in directory: URL) -> CGImage? {
        guard let name = run.image else { return nil }
        let key = (directory.path + "/" + name + "@\(run.x),\(run.y),\(run.w),\(run.h)"
                   + (Paper.invertsFigures ? "#inverted" : "")) as NSString
        if let cached = islands.object(forKey: key) { return cached }
        guard let sheet = image(named: name, in: directory)?
                .cgImage(forProposedRect: nil, context: nil, hints: nil),
              run.w > 0, run.h > 0, run.x >= 0, run.y >= 0,
              run.x + run.w <= sheet.width, run.y + run.h <= sheet.height,
              let cut = sheet.cropping(to: CGRect(x: run.x, y: run.y, width: run.w, height: run.h))
        else { return nil }
        islands.setObject(cut, forKey: key)
        return cut
    }

    func image(named name: String, in directory: URL) -> NSImage? {
        guard !name.isEmpty else { return nil }
        let key = (directory.path + "/" + name
                   + (Paper.invertsFigures ? "#inverted" : "")) as NSString
        if let cached = store.object(forKey: key) { return cached }
        guard let img = NSImage(contentsOf: directory.appendingPathComponent(name))
        else { return nil }
        let out = Paper.invertsFigures ? (ImageCache.inverted(img) ?? img) : img
        store.setObject(out, forKey: key)
        return out
    }

    static func inverted(_ image: NSImage) -> NSImage? {
        guard let tiff = image.tiffRepresentation,
              let source = CIImage(data: tiff) else { return nil }
        let peak = 0.93
        let out = source
            .applyingFilter("CIColorInvert")
            .applyingFilter("CIColorMatrix", parameters: [
                "inputRVector": CIVector(x: peak, y: 0, z: 0, w: 0),
                "inputGVector": CIVector(x: 0, y: peak, z: 0, w: 0),
                "inputBVector": CIVector(x: 0, y: 0, z: peak, w: 0),
                "inputBiasVector": CIVector(x: 0, y: 0, z: 0, w: 0),
            ])
        let context = CIContext(options: [.workingColorSpace: NSNull()])
        guard let cg = context.createCGImage(out, from: out.extent) else { return nil }
        return NSImage(cgImage: cg, size: image.size)
    }
}

struct BlocksView: View {
    let blocks: [ContentBlock]
    let imagesDirectory: URL
    var bodySize: Double = 15
    var spacing: CGFloat = 12
    var figureScale: Double? = nil
    var questionPoints: Double? = nil
    var fixedWidth: CGFloat? = nil
    var centresDisplays = true

    @State private var measured: CGFloat = 0

    private var paneWidth: CGFloat { fixedWidth ?? measured }

    var body: some View {
        VStack(alignment: .leading, spacing: spacing) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { index, block in
                ContentBlockView(block: block, imagesDirectory: imagesDirectory,
                                 bodySize: bodySize, figureScale: scale,
                                 paneWidth: paneWidth,
                                 centred: centresDisplays && QuestionLayout.isDisplay(
                                    block, after: index > 0 ? blocks[index - 1] : nil),
                                 centresDisplays: centresDisplays)
            }
        }
        .frame(maxWidth: fixedWidth ?? .infinity, alignment: .leading)
        .measuringPaneWidth($measured)
    }

    private var scale: Double? {
        if let figureScale { return figureScale }
        guard let questionPoints, questionPoints > 0, paneWidth > 0 else { return nil }
        return QuestionLayout.figureScale(bodyPoints: questionPoints, choicePoints: 0,
                                          bodySize: bodySize, width: paneWidth)
    }
}

struct BluebookButton: View {
    enum Style { case primary, secondary, plain }
    let title: String
    var style: Style = .primary
    var enabled: Bool = true
    var onCanvas: Bool = false
    var lifts: Bool = false
    let action: () -> Void

    @State private var hovering = false

    private var tint: Color { onCanvas ? Paper.accentFill : Palette.navy }

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(Face.ui(13, .semibold))
                .tracking(0.2)
                .padding(.horizontal, 22)
                .padding(.vertical, 10)
                .background(background)
                .foregroundStyle(foreground)
                .overlay(
                    RoundedRectangle(cornerRadius: 3)
                        .strokeBorder(borderColor, lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: 3))
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled || style == .primary ? 1 : 0.35)
        .modifier(Lift(active: lifts && hovering, enabled: lifts))
        .onHover { hovering = $0 && enabled }
    }

    private var background: Color {
        if !enabled && style == .primary { return onCanvas ? Paper.subtleFill : Palette.subtleFill }
        switch style {
        case .primary: return hovering ? (onCanvas ? Paper.accentFillDeep : Palette.navyDeep) : tint
        case .secondary:
            return hovering ? (onCanvas ? Paper.brassSoft : Palette.brassSoft).opacity(0.5) : .clear
        case .plain:
            return hovering ? (onCanvas ? Paper.paperDeep : Palette.paperDeep)
                            : (onCanvas ? Paper.subtleFill : Palette.subtleFill)
        }
    }
    private var foreground: Color {
        if !enabled && style == .primary { return onCanvas ? Paper.text : Palette.text }
        switch style {
        case .primary: return onCanvas ? Paper.onBrand : Palette.card
        case .secondary: return tint
        case .plain: return onCanvas ? Paper.text : Palette.text
        }
    }
    private var borderColor: Color {
        if !enabled && style == .primary { return onCanvas ? Paper.hairline : Palette.hairline }
        switch style {
        case .primary: return .clear
        case .secondary: return tint.opacity(0.55)
        case .plain: return onCanvas ? Paper.hairline : Palette.hairline
        }
    }
}

private struct Lift: ViewModifier {
    let active: Bool
    let enabled: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if enabled {
            content
                .scaleEffect(active ? 1.025 : 1)
                .shadow(color: Palette.navy.opacity(active ? 0.16 : 0), radius: 6, y: 3)
                .animation(Motion.quick, value: active)
        } else {
            content
        }
    }
}

struct Chip: View {
    let title: String
    var selected: Bool
    var enabled: Bool = true
    var count: Int? = nil
    var accent: Color = Palette.navy
    let action: () -> Void

    @State private var hovering = false
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                let ink = selected ? readableInk(on: accent, in: scheme) : Palette.text
                Text(title)
                    .font(Face.ui(12, selected ? .semibold : .regular))
                    .foregroundStyle(ink)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                if let count {
                    Text("\(count)")
                        .font(Face.ui(10, .medium))
                        .foregroundStyle(selected ? ink.opacity(0.75) : Palette.textMuted)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(selected ? ink.opacity(0.18) : Palette.card)
                        .clipShape(RoundedRectangle(cornerRadius: 2))
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            .background(selected ? accent
                        : (hovering ? Palette.paperDeep : Palette.subtleFill))
            .overlay(
                RoundedRectangle(cornerRadius: 3)
                    .strokeBorder(selected ? .clear : Palette.hairline, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 3))
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.35)
        .scaleEffect(selected ? 1.0 : (hovering ? 1.03 : 1.0))
        .animation(Motion.settle, value: selected)
        .animation(Motion.quick, value: hovering)
        .onHover { hovering = $0 && enabled && !selected }
    }
}

struct OptionRow: View {
    let title: String
    let detail: String
    let selected: Bool
    var namespace: Namespace.ID? = nil
    var badge: String? = nil
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 12) {
                ZStack {
                    Rectangle().fill(Color.clear).frame(width: 2)
                    if selected {
                        let mark = Rectangle().fill(Palette.brass).frame(width: 2)
                        if let namespace {
                            mark.matchedGeometryEffect(id: "optionMark", in: namespace)
                        } else {
                            mark
                        }
                    }
                }
                .frame(width: 2)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(Face.ui(13, selected ? .semibold : .regular))
                        .foregroundStyle(Palette.text)
                    Text(detail)
                        .font(Face.ui(11))
                        .foregroundStyle(Palette.textMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 6)
                if let badge {
                    Text(badge)
                        .font(Face.ui(10, .medium))
                        .foregroundStyle(selected ? Palette.brass : Palette.textMuted)
                        .padding(.top, 2)
                }
            }
            .padding(.vertical, 8)
            .padding(.trailing, 10)
            .padding(.leading, 0)
            .background(selected ? Palette.brassSoft.opacity(0.32)
                        : (hovering ? Palette.paperDeep.opacity(0.45) : Color.clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .animation(Motion.quick, value: hovering)
        .onHover { hovering = $0 }
    }
}

struct AppearanceSwitch: View {
    @Binding var appearance: Appearance
    @Namespace private var mark
    @State private var hovering: Appearance?

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Appearance.allCases, id: \.self) { option in
                Button {
                    withAnimation(Motion.settle) { appearance = option }
                } label: {
                    Image(systemName: option.symbol)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(appearance == option ? Palette.onBrand
                                         : (hovering == option ? Palette.text : Palette.textMuted))
                        .frame(width: 34, height: 22)
                        .background {
                            if appearance == option {
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(Palette.brandFill)
                                    .matchedGeometryEffect(id: "appearanceMark", in: mark)
                            }
                        }
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .onHover { hovering = $0 ? option : nil }
                .help(option.title + " — " + option.detail)
                .accessibilityLabel(option.title)
            }
        }
        .padding(2)
        .background(RoundedRectangle(cornerRadius: 4).fill(Palette.subtleFill))
        .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(Palette.hairline, lineWidth: 1))
        .animation(Motion.quick, value: hovering)
        .accessibilityLabel(L("Appearance"))
    }
}

struct SchedulePanel: View {
    @Binding var schedule: StudySchedule
    @State private var askingPermission = false
    @State private var permissionRefused = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Toggle("", isOn: Binding(
                    get: { schedule.enabled },
                    set: { schedule.enabled = $0 }))
                    .toggleStyle(.switch)
                    .controlSize(.mini)
                    .labelsHidden()
                VStack(alignment: .leading, spacing: 1) {
                    Text(L("Follow a study plan"))
                        .font(Face.ui(12, .semibold))
                        .foregroundStyle(Palette.text)
                    Text(schedule.summary)
                        .font(Face.ui(10))
                        .foregroundStyle(Palette.textMuted)
                }
                Spacer(minLength: 0)
            }

            if schedule.enabled {
                VStack(alignment: .leading, spacing: 12) {
                    dayPicker
                    targetRow
                    reminderRow
                }
                .transition(.opacity)
            }
        }
        .animation(Motion.standard, value: schedule.enabled)
        .animation(Motion.quick, value: schedule.remindersOn)
    }

    private var dayPicker: some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionLabel(text: L("Days"))
            HStack(spacing: 5) {
                ForEach(StudySchedule.weekdayOrder(), id: \.self) { weekday in
                    let on = schedule.days.contains(weekday)
                    Button {
                        withAnimation(Motion.quick) {
                            if on { schedule.days.remove(weekday) }
                            else { schedule.days.insert(weekday) }
                        }
                    } label: {
                        Text(StudySchedule.weekdayName(weekday))
                            .font(Face.ui(10, on ? .semibold : .regular))
                            .foregroundStyle(on ? Palette.onBrand : Palette.textMuted)
                            .frame(width: 28, height: 24)
                            .background(on ? Palette.brandFill : Palette.subtleFill)
                            .overlay(RoundedRectangle(cornerRadius: 3)
                                .strokeBorder(on ? .clear : Palette.hairline, lineWidth: 1))
                            .clipShape(RoundedRectangle(cornerRadius: 3))
                    }
                    .buttonStyle(.plain)
                }
            }
            if schedule.days.isEmpty {
                Text(L("Pick at least one day, or the plan is a plan to do nothing."))
                    .font(Face.ui(10))
                    .foregroundStyle(Palette.brass)
            }
        }
    }

    private var targetRow: some View {
        HStack(spacing: 10) {
            SectionLabel(text: L("Questions a day"))
            Stepper(value: Binding(
                get: { schedule.dailyTarget },
                set: { schedule.dailyTarget = max(1, min(200, $0)) }), in: 1...200, step: 5) {
                Text("\(schedule.dailyTarget)")
                    .font(Face.ui(12, .semibold))
                    .monospacedDigit()
                    .foregroundStyle(Palette.text)
            }
            .controlSize(.small)
            Spacer(minLength: 0)
        }
    }

    @ViewBuilder
    private var reminderRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Toggle("", isOn: Binding(
                    get: { schedule.remindersOn },
                    set: { wanted in
                        if wanted { ask() } else { schedule.remindersOn = false }
                    }))
                    .toggleStyle(.switch)
                    .controlSize(.mini)
                    .labelsHidden()
                Text(L("Remind me"))
                    .font(Face.ui(12))
                    .foregroundStyle(Palette.text)

                if schedule.remindersOn {
                    DatePicker("", selection: Binding(
                        get: {
                            var c = DateComponents()
                            c.hour = schedule.reminderHour
                            c.minute = schedule.reminderMinute
                            return Calendar.current.date(from: c) ?? Date()
                        },
                        set: {
                            let c = Calendar.current.dateComponents([.hour, .minute], from: $0)
                            schedule.reminderHour = c.hour ?? 17
                            schedule.reminderMinute = c.minute ?? 0
                        }), displayedComponents: .hourAndMinute)
                        .labelsHidden()
                        .controlSize(.small)
                        .frame(width: 84)
                }
                Spacer(minLength: 0)
            }

            if schedule.remindersOn {
                Toggle(isOn: Binding(
                    get: { schedule.warnsWhenStreakAtRisk },
                    set: { schedule.warnsWhenStreakAtRisk = $0 })) {
                    Text(L("And again in the evening if the streak is about to go"))
                        .font(Face.ui(10))
                        .foregroundStyle(Palette.textMuted)
                }
                .toggleStyle(.checkbox)
                .controlSize(.small)
            }

            if permissionRefused {
                Text(L("macOS is not allowing notifications for this app. "
                     + "System Settings › Notifications can turn them back on."))
                    .font(Face.ui(10))
                    .foregroundStyle(Palette.brass)
                    .fixedSize(horizontal: false, vertical: true)
            } else if !Reminders.isAvailable {
                Text(L("Reminders need the built app rather than a development run."))
                    .font(Face.ui(10))
                    .foregroundStyle(Palette.textMuted)
            }
        }
    }

    private func ask() {
        guard Reminders.isAvailable else { schedule.remindersOn = true; return }
        askingPermission = true
        Task {
            let granted = await Reminders.requestAuthorization()
            askingPermission = false
            permissionRefused = !granted
            schedule.remindersOn = granted
        }
    }
}

struct SetAsideToggle: View {
    @Binding var setAside: Bool

    var body: some View {
        Button {
            setAside.toggle()
        } label: {
            HStack(spacing: 5) {
                Image(systemName: setAside ? "tray.full.fill" : "tray")
                    .font(.system(size: 12))
                    .foregroundStyle(setAside ? Paper.brass : Paper.text)
                Text(L("Set aside"))
                    .font(Face.ui(12, setAside ? .semibold : .regular))
                    .foregroundStyle(setAside ? Paper.brass : Paper.text)
            }
        }
        .buttonStyle(.plain)
        .help(L("Keep this question to look at again at the end of your study time"))
    }
}

struct MarkForReviewToggle: View {
    @Binding var marked: Bool

    var body: some View {
        Button {
            marked.toggle()
        } label: {
            HStack(spacing: 5) {
                Image(systemName: marked ? "bookmark.fill" : "bookmark")
                    .font(.system(size: 12))
                    .foregroundStyle(marked ? Paper.wrong : Paper.text)
                Text(L("Mark for Review"))
                    .font(.system(size: 12))
                    .foregroundStyle(Paper.text)
            }
        }
        .buttonStyle(.plain)
        .help(L("Flag this question so you can come back to it"))
    }
}

struct EliminatorToggle: View {
    @Binding var on: Bool

    var body: some View {
        Button { on.toggle() } label: {
            ZStack {
                RoundedRectangle(cornerRadius: 4)
                    .fill(on ? Paper.accent : Color.clear)
                    .frame(width: 30, height: 22)
                RoundedRectangle(cornerRadius: 4)
                    .strokeBorder(on ? Paper.accent : Paper.border, lineWidth: 1)
                    .frame(width: 30, height: 22)
                Text("ABC")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(on ? Paper.canvas : Paper.text)
                    .overlay(
                        Rectangle()
                            .fill(on ? Paper.canvas : Paper.text)
                            .frame(height: 1)
                    )
            }
        }
        .buttonStyle(.plain)
        .help(L("Answer Eliminator — cross out choices you have ruled out"))
        .accessibilityLabel(L("Answer Eliminator — cross out choices you have ruled out"))
        .accessibilityAddTraits(on ? .isSelected : [])
    }
}

enum Split {
    static let range: ClosedRange<CGFloat> = 0.25...0.75
    static let dividerWidth: CGFloat = 11

    static func clamp(_ fraction: CGFloat) -> CGFloat {
        min(range.upperBound, max(range.lowerBound, fraction))
    }
}

struct SplitPane<Left: View, Right: View>: View {
    @Binding var fraction: CGFloat
    @ViewBuilder var left: Left
    @ViewBuilder var right: Right

    @State private var dragOrigin: (startX: CGFloat, fraction: CGFloat)?

    private static var dragSpace: String { "SplitPane.drag" }

    var body: some View {
        GeometryReader { geo in
            let total = geo.size.width
            let leftWidth = total * Split.clamp(fraction)

            HStack(spacing: 0) {
                left.frame(width: leftWidth)
                divider(total: total)
                right.frame(width: max(0, total - leftWidth - Split.dividerWidth))
            }
            .coordinateSpace(name: Self.dragSpace)
        }
    }

    private func divider(total: CGFloat) -> some View {
        ZStack {
            Rectangle().fill(Paper.hairline).frame(width: 1)
            RoundedRectangle(cornerRadius: 2)
                .fill(Color(nsColor: .init(white: 0.35, alpha: 1)))
                .frame(width: 5, height: 26)
                .overlay(
                    Image(systemName: "arrow.left.and.right")
                        .font(.system(size: 7, weight: .bold))
                        .foregroundStyle(.white)
                )
        }
        .frame(width: Split.dividerWidth)
        .contentShape(Rectangle())
        .onHover { inside in
            if inside { NSCursor.resizeLeftRight.push() } else { NSCursor.pop() }
        }
        .gesture(
            DragGesture(minimumDistance: 1, coordinateSpace: .named(Self.dragSpace))
                .onChanged { value in
                    guard total > 0 else { return }
                    let origin: CGFloat
                    if let held = dragOrigin, held.startX == value.startLocation.x {
                        origin = held.fraction
                    } else {
                        origin = fraction
                        dragOrigin = (value.startLocation.x, fraction)
                    }
                    fraction = Split.clamp(origin + value.translation.width / total)
                }
                .onEnded { _ in dragOrigin = nil }
        )
    }
}

extension View {
    func dashedRule() -> some View {
        overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color.clear)
                .frame(height: 1)
                .overlay(
                    Line().stroke(style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
                        .foregroundStyle(Palette.border)
                )
        }
    }
}

struct Line: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: 0, y: rect.midY))
        p.addLine(to: CGPoint(x: rect.width, y: rect.midY))
        return p
    }
}

enum Format {

    static func fileSize(_ bytes: Int64) -> String {
        let mb = Double(bytes) / 1_000_000
        if mb >= 1000 { return String(format: "%.1f GB", mb / 1000) }
        if mb >= 10 { return String(format: "%.0f MB", mb) }
        if mb >= 1 { return String(format: "%.1f MB", mb) }
        return String(format: "%.0f KB", max(1, Double(bytes) / 1000))
    }

    static func clock(_ seconds: Double) -> String {
        let s = max(0, Int(seconds.rounded()))
        return String(format: "%d:%02d", s / 60, s % 60)
    }

    static func pace(_ seconds: Double) -> String {
        let s = max(0, Int(seconds.rounded()))
        if s < 60 { return "\(s)s" }
        return String(format: "%dm %02ds", s / 60, s % 60)
    }

    static func day(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: Localisation.current.localeIdentifier)
        f.dateStyle = .medium
        f.timeStyle = .none
        return f.string(from: date)
    }

    static func stamp(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: Localisation.current.localeIdentifier)
        f.dateStyle = .medium
        f.timeStyle = .short
        return f.string(from: date)
    }

    static func duration(_ seconds: Double) -> String {
        let s = max(0, Int(seconds.rounded()))
        if s < 60 { return Lf("%d s", s) }
        let m = s / 60
        if m < 60 { return Lf("%d min", m) }
        return Lf("%1$d h %2$d min", m / 60, m % 60)
    }
}

struct HighlightableText: NSViewRepresentable {
    let text: String
    let underlines: [Range<Int>]
    let annotations: [Annotation]
    var bodySize: Double
    var onSelect: (Range<Int>?) -> Void
    var onTapAnnotation: (Annotation) -> Void

    func makeNSView(context: Context) -> ClickableTextView {
        let view = ClickableTextView()
        view.appearance = NSAppearance(named: Paper.stealth ? .darkAqua : .aqua)
        view.isEditable = false
        view.isSelectable = true
        view.drawsBackground = false
        view.textContainerInset = .zero
        view.textContainer?.lineFragmentPadding = 0
        view.delegate = context.coordinator
        return view
    }

    func updateNSView(_ view: ClickableTextView, context: Context) {
        view.appearance = NSAppearance(named: Paper.stealth ? .darkAqua : .aqua)
        context.coordinator.onSelect = onSelect
        let current = annotations
        let tap = onTapAnnotation
        view.onClick = { index in
            if let hit = current.first(where: { $0.range.contains(index) }) { tap(hit) }
        }
        let next = attributed
        let marks = annotations.map { "\($0.id)/\($0.colorIndex)/\($0.start)/\($0.end)" }
        let marksChanged = context.coordinator.shownMarks.map { $0 != marks } ?? false
        context.coordinator.shownMarks = marks
        if !(view.textStorage?.isEqual(to: next) ?? false) {
            let kept = view.selectedRanges
            view.textStorage?.setAttributedString(next)
            let length = next.length
            let valid = kept.map(\.rangeValue).filter { NSMaxRange($0) <= length }
            if marksChanged {
                let end = valid.map { NSMaxRange($0) }.max() ?? 0
                view.setSelectedRange(NSRange(location: min(end, length), length: 0))
            } else if !valid.isEmpty {
                view.selectedRanges = valid.map { NSValue(range: $0) }
            }
        }
        view.textContainer?.containerSize = CGSize(width: view.bounds.width,
                                                   height: .greatestFiniteMagnitude)
        view.textContainer?.widthTracksTextView = true
        view.invalidateIntrinsicContentSize()
    }

    func makeCoordinator() -> Coordinator { Coordinator(onSelect: onSelect) }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var onSelect: (Range<Int>?) -> Void
        var shownMarks: [String]?
        init(onSelect: @escaping (Range<Int>?) -> Void) { self.onSelect = onSelect }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard let view = notification.object as? NSTextView else { return }
            let r = view.selectedRange()
            guard r.length > 0, let s = view.string as NSString? else { onSelect(nil); return }
            let prefix = s.substring(to: r.location) as String
            let body = s.substring(with: r) as String
            let start = prefix.count
            onSelect(start..<(start + body.count))
        }
    }

    private var attributed: NSAttributedString {
        PassageText.attributed(text: text, underlines: underlines,
                               annotations: annotations, bodySize: bodySize)
    }
}

enum PassageText {
    static func attributed(text: String, underlines: [Range<Int>],
                           annotations: [Annotation], bodySize: Double) -> NSAttributedString {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = bodySize * 0.34
        paragraph.paragraphSpacing = bodySize * 0.5
        let result = NSMutableAttributedString(string: text, attributes: [
            .font: NSFont.systemFont(ofSize: bodySize),
            .foregroundColor: NSColor(Paper.text),
            .paragraphStyle: paragraph
        ])
        let chars = Array(text)
        func utf16Range(_ r: Range<Int>) -> NSRange? {
            let lo = max(0, min(r.lowerBound, chars.count))
            let hi = max(lo, min(r.upperBound, chars.count))
            guard hi > lo else { return nil }
            return NSRange(location: String(chars[0..<lo]).utf16.count,
                           length: String(chars[lo..<hi]).utf16.count)
        }
        for r in underlines {
            guard let nr = utf16Range(r) else { continue }
            result.addAttribute(.underlineStyle,
                                value: NSUnderlineStyle.single.rawValue, range: nr)
        }
        for a in annotations {
            guard let nr = utf16Range(a.range) else { continue }
            result.addAttribute(.backgroundColor,
                                value: NSColor(Paper.highlight(a.colorIndex)), range: nr)
            if a.hasNote {
                result.addAttribute(.underlineStyle,
                                    value: NSUnderlineStyle.thick.rawValue, range: nr)
                result.addAttribute(.underlineColor, value: NSColor(Paper.brass),
                                    range: nr)
            }
        }
        return result
    }
}

final class ClickableTextView: NSTextView {
    var onClick: ((Int) -> Void)?

    override var intrinsicContentSize: NSSize {
        guard let manager = layoutManager, let container = textContainer else {
            return super.intrinsicContentSize
        }
        container.containerSize = NSSize(width: bounds.width, height: .greatestFiniteMagnitude)
        manager.ensureLayout(for: container)
        return NSSize(width: NSView.noIntrinsicMetric,
                      height: ceil(manager.usedRect(for: container).height))
    }

    override func layout() {
        super.layout()
        invalidateIntrinsicContentSize()
    }

    override func mouseDown(with event: NSEvent) {
        super.mouseDown(with: event)
        guard selectedRange().length == 0, let onClick else { return }
        let point = convert(event.locationInWindow, from: nil)
        let index = characterIndexForInsertion(at: point)
        let s = string as NSString
        guard index >= 0, index <= s.length else { return }
        onClick((s.substring(to: index) as String).count)
    }
}


struct AnnotatableBlocksView: View {
    let blocks: [ContentBlock]
    let field: AnnotationField
    let questionID: String
    let annotations: [Annotation]
    let imagesDirectory: URL
    var bodySize: Double = 15
    var spacing: CGFloat = 12
    var figureScale: Double? = nil
    var onSelect: (AnnotationField, Int, Range<Int>?) -> Void
    var onTapAnnotation: (Annotation) -> Void

    @State private var paneWidth: CGFloat = 0

    var body: some View {
        VStack(alignment: .leading, spacing: spacing) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { index, block in
                if block.kind == .text {
                    HighlightableText(
                        text: block.text,
                        underlines: block.underlineRanges,
                        annotations: annotations.filter {
                            $0.field == field && $0.blockIndex == index
                        },
                        bodySize: bodySize,
                        onSelect: { onSelect(field, index, $0) },
                        onTapAnnotation: onTapAnnotation)
                    .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    ContentBlockView(block: block, imagesDirectory: imagesDirectory,
                                     bodySize: bodySize, figureScale: figureScale,
                                     paneWidth: paneWidth,
                                     centred: QuestionLayout.isDisplay(
                                        block, after: index > 0 ? blocks[index - 1] : nil))
                }
            }
        }
        .measuringPaneWidth($paneWidth)
    }
}
