import SwiftUI

enum Brand {
    static let organisation = "United States Universities For Ukraine"
    static let initials = "USUFU"
    static let slogan = "Advancing Excellence. Ensuring Success."
    static let established = "Est. 2026"
    static let appName = "USUFU Prep"
    static let tagline = "Practice the digital SAT and PSAT from your own College Board question bank."

    static let stage = ""
    static var isPrerelease: Bool { !stage.isEmpty }
}


enum BrandAsset {
    static let seal = load("usufu-seal")
    static let wordmark = load("usufu-wordmark")

    private static func load(_ name: String) -> NSImage? {
        var url = Bundle.main.url(forResource: name, withExtension: "png")
        if url == nil {
            let repo = URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .appendingPathComponent("Resources/\(name).png")
            if FileManager.default.fileExists(atPath: repo.path) { url = repo }
        }
        guard let url, let image = NSImage(contentsOf: url) else { return nil }
        image.isTemplate = true
        return image
    }
}

struct USUFUSeal: View {
    var size: CGFloat = 96
    var tint: Color = Palette.navy
    var strokeScale: CGFloat = 1

    private enum Detail { case full, crest, mark }
    private var detail: Detail {
        if size >= 108 { return .full }
        if size >= 40 { return .crest }
        return .mark
    }

    static let artworkFloor: CGFloat = 44

    var body: some View {
        Group {
            if let artwork = BrandAsset.seal, size >= Self.artworkFloor {
                Image(nsImage: artwork)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
                    .foregroundColor(tint)
            } else {
                drawn
            }
        }
        .frame(width: size, height: size)
        .accessibilityLabel(Brand.organisation)
    }

    private var drawn: some View {
        Canvas { context, canvasSize in
            let s = min(canvasSize.width, canvasSize.height)
            let c = CGPoint(x: canvasSize.width / 2, y: canvasSize.height / 2)
            let line = max(0.7, s * 0.0062 * strokeScale)

            let rings: [CGFloat] = detail == .full
                ? [0.487, 0.462, 0.352, 0.336] : [0.487, 0.455]
            for r in rings {
                let heavy = (r == 0.462 || r == 0.352 || r == 0.455)
                context.stroke(Path(ellipseIn: CGRect(x: c.x - s * r, y: c.y - s * r,
                                                      width: s * r * 2, height: s * r * 2)),
                               with: .color(tint), lineWidth: heavy ? line * 1.9 : line)
            }

            if detail == .full {
                arcText(&context, Brand.organisation.uppercased(),
                        center: c, radius: s * 0.404,
                        centredOn: .degrees(270), sweep: .degrees(212),
                        font: .system(size: s * 0.054, weight: .semibold, design: .serif),
                        upright: true)
                arcText(&context, Brand.established,
                        center: c, radius: s * 0.392,
                        centredOn: .degrees(90), sweep: .degrees(46),
                        font: .system(size: s * 0.061, weight: .bold, design: .serif),
                        upright: false)
            }

            let field: CGFloat = detail == .full ? 1 : 1.34
            if detail != .mark {
                wreath(&context, center: c, s: s, field: field, line: line)
            }
            book(&context, center: c, s: s,
                 field: detail == .mark ? 1.7 : field, line: line,
                 ruled: detail != .mark)
        }
    }

    private func arcText(_ context: inout GraphicsContext, _ text: String,
                         center: CGPoint, radius: CGFloat,
                         centredOn: Angle, sweep: Angle, font: Font, upright: Bool) {
        let characters = Array(text)
        guard characters.count > 1 else { return }
        let start = centredOn.degrees - sweep.degrees / 2
        let step = sweep.degrees / Double(characters.count - 1)

        for (i, character) in characters.enumerated() {
            guard character != " " else { continue }
            let degrees = upright ? start + step * Double(i)
                                  : centredOn.degrees + sweep.degrees / 2 - step * Double(i)
            let radians = degrees * .pi / 180
            let point = CGPoint(x: center.x + CGFloat(cos(radians)) * radius,
                                y: center.y + CGFloat(sin(radians)) * radius)
            let resolved = context.resolve(
                Text(String(character)).font(font).foregroundColor(tint))
            context.drawLayer { layer in
                layer.translateBy(x: point.x, y: point.y)
                layer.rotate(by: .degrees(degrees + (upright ? 90 : -90)))
                layer.draw(resolved, at: .zero, anchor: .center)
            }
        }
    }

    private func wreath(_ context: inout GraphicsContext, center c: CGPoint,
                        s: CGFloat, field: CGFloat, line: CGFloat) {
        for mirrored in [false, true] {
            context.drawLayer { layer in
                if mirrored {
                    layer.translateBy(x: c.x, y: c.y)
                    layer.scaleBy(x: -1, y: 1)
                    layer.translateBy(x: -c.x, y: -c.y)
                }
                branch(&layer, center: c, s: s, field: field, line: line)
            }
        }
    }

    private func branch(_ context: inout GraphicsContext, center c: CGPoint,
                        s: CGFloat, field: CGFloat, line: CGFloat) {
        let from = -66.0, to = 86.0
        let stemRadius = s * 0.238 * field
        let leaves = 9

        var stem = Path()
        for i in 0...56 {
            let t = Double(i) / 56
            stem.addPoint(onRing(c, stemRadius, from + (to - from) * t), first: i == 0)
        }
        context.stroke(stem, with: .color(tint),
                       style: StrokeStyle(lineWidth: line * 1.5, lineCap: .round))

        for i in 0..<leaves {
            let t = Double(i) / Double(leaves - 1)
            let degrees = from + (to - from) * t
            let length = s * (0.052 + 0.042 * t) * field
            let width = length * 0.44
            let anchor = onRing(c, stemRadius, degrees)

            for outward in [true, false] {
                let axis = (outward ? degrees : degrees + 180) - 34
                let span = length * (outward ? 1 : 0.78)
                let offset = onRing(.zero, span * 0.52, axis)
                context.drawLayer { layer in
                    layer.translateBy(x: anchor.x + offset.x, y: anchor.y + offset.y)
                    layer.rotate(by: .degrees(axis))
                    layer.stroke(Path(ellipseIn: CGRect(x: -span / 2, y: -width / 2,
                                                        width: span, height: width)),
                                 with: .color(tint), lineWidth: line)
                }
            }
        }
    }

    private func onRing(_ c: CGPoint, _ radius: CGFloat, _ degrees: Double) -> CGPoint {
        let radians = degrees * .pi / 180
        return CGPoint(x: c.x + CGFloat(cos(radians)) * radius,
                       y: c.y + CGFloat(sin(radians)) * radius)
    }

    private func book(_ context: inout GraphicsContext, center c: CGPoint,
                      s: CGFloat, field: CGFloat, line: CGFloat, ruled: Bool) {
        let halfWidth = s * 0.150 * field
        let height = s * 0.128 * field
        let gutter = s * 0.010 * field
        let spineTop = c.y - height * 0.62
        let spineFoot = c.y + height * 0.86
        let leafTop = c.y - height * 0.82
        let leafFoot = c.y + height * 0.66

        for side in [-1.0, 1.0] as [CGFloat] {
            let outer = c.x + side * halfWidth
            let inner = c.x + side * gutter

            var page = Path()
            page.move(to: CGPoint(x: inner, y: spineTop))
            page.addQuadCurve(to: CGPoint(x: outer, y: leafTop),
                              control: CGPoint(x: c.x + side * halfWidth * 0.52,
                                               y: spineTop - height * 0.10))
            page.addLine(to: CGPoint(x: outer, y: leafFoot))
            page.addQuadCurve(to: CGPoint(x: inner, y: spineFoot),
                              control: CGPoint(x: c.x + side * halfWidth * 0.52,
                                               y: spineFoot - height * 0.02))
            page.closeSubpath()
            context.stroke(page, with: .color(tint),
                           style: StrokeStyle(lineWidth: line * 1.6, lineJoin: .round))

            let thickness = s * 0.015 * field
            var edge = Path()
            edge.move(to: CGPoint(x: outer, y: leafTop))
            edge.addLine(to: CGPoint(x: outer + side * thickness, y: leafTop + height * 0.14))
            edge.addLine(to: CGPoint(x: outer + side * thickness, y: leafFoot + height * 0.12))
            edge.addLine(to: CGPoint(x: outer, y: leafFoot))
            context.stroke(edge, with: .color(tint),
                           style: StrokeStyle(lineWidth: line, lineJoin: .round))

            if ruled {
                for n in 0..<3 {
                    let y = leafTop + height * (0.42 + 0.34 * CGFloat(n))
                    let inset = halfWidth * (0.16 + 0.05 * CGFloat(n))
                    var rule = Path()
                    rule.move(to: CGPoint(x: inner + side * halfWidth * 0.16, y: y))
                    rule.addLine(to: CGPoint(x: outer - side * inset, y: y))
                    context.stroke(rule, with: .color(tint), lineWidth: line * 0.85)
                }
            }
        }

        var spine = Path()
        spine.move(to: CGPoint(x: c.x, y: spineTop))
        spine.addLine(to: CGPoint(x: c.x, y: spineFoot))
        context.stroke(spine, with: .color(tint), lineWidth: line * 1.6)

        let clasp = CGRect(x: c.x - s * 0.020 * field, y: spineFoot,
                           width: s * 0.040 * field, height: s * 0.024 * field)
        context.stroke(Path(roundedRect: clasp, cornerRadius: s * 0.005 * field),
                       with: .color(tint), lineWidth: line * 1.2)
    }
}

private extension Path {
    mutating func addPoint(_ point: CGPoint, first: Bool) {
        if first { move(to: point) } else { addLine(to: point) }
    }
}

struct USUFUWordmark: View {
    var size: CGFloat = 24
    var tint: Color = Palette.navy
    var accent: Color = Palette.brass
    var showsSlogan: Bool = true
    var compact: Bool = false

    var body: some View {
        Group {
            if let artwork = BrandAsset.wordmark, !compact, showsSlogan {
                Image(nsImage: artwork)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
                    .foregroundColor(tint)
                    .frame(maxWidth: size * 30)
            } else {
                set
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Brand.organisation)
    }

    private var set: some View {
        VStack(spacing: size * 0.24) {
            Text(compact ? Brand.initials : Brand.organisation)
                .font(.system(size: size, weight: .semibold, design: .serif))
                .foregroundColor(tint)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            if showsSlogan {
                Rectangle()
                    .fill(accent.opacity(0.55))
                    .frame(height: max(0.5, size * 0.022))
                    .frame(maxWidth: size * 14)

                Text(Brand.slogan)
                    .font(.system(size: size * 0.46, weight: .regular, design: .serif))
                    .italic()
                    .foregroundColor(tint.opacity(0.72))
                    .multilineTextAlignment(.center)
            }
        }
    }
}

struct USUFULockup: View {
    var sealSize: CGFloat = 86
    var wordSize: CGFloat = 21
    var tint: Color = Palette.navy
    var accent: Color = Palette.brass
    var showsSlogan: Bool = true

    var body: some View {
        VStack(spacing: sealSize * 0.16) {
            USUFUSeal(size: sealSize, tint: tint)
            USUFUWordmark(size: wordSize, tint: tint, accent: accent, showsSlogan: showsSlogan)
        }
    }
}
