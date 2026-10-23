import SwiftUI

struct ArticleDiagram: View {
    let name: String
    var caption: String = ""

    static func height(for name: String) -> CGFloat {
        switch name {
        case "special-right-triangles": return 210
        case "parabola": return 250
        case "slope": return 230
        case "circle-sector": return 220
        case "transversal": return 200
        case "similar-triangles": return 260
        case "scatter-fit": return 230
        case "outlier-number-line": return 240
        case "linear-vs-exponential": return 250
        case "inequality-region": return 230
        case "reference-sheet": return ArticleDiagram.sheetHeight
        default: return 0
        }
    }

    private var height: CGFloat { ArticleDiagram.height(for: name) }

    private var onPaper: Bool { name == "reference-sheet" }

    var body: some View {
        if height > 0 {
            VStack(alignment: .leading, spacing: 7) {
                figure
                .frame(height: height)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(onPaper ? Paper.canvas : Palette.subtleFill.opacity(0.5))
                .overlay(RoundedRectangle(cornerRadius: 4)
                    .strokeBorder(onPaper ? Paper.hairline : Palette.hairline, lineWidth: 1))
                .clipShape(RoundedRectangle(cornerRadius: 4))

                if !caption.isEmpty {
                    Text(caption)
                        .font(Face.ui(10.5))
                        .foregroundStyle(Palette.textMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    static let sheetSize = CGSize(width: 1010, height: 468)
    static var sheetScale: CGFloat { ArticleLayout.measure / sheetSize.width }
    static var sheetHeight: CGFloat { (sheetSize.height * sheetScale).rounded() }

    @ViewBuilder
    private var figure: some View {
        if name == "reference-sheet" {
            ReferenceSheetView().sheet
                .frame(width: ArticleDiagram.sheetSize.width,
                       alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
                .scaleEffect(ArticleDiagram.sheetScale, anchor: .topLeading)
                .frame(width: ArticleLayout.measure,
                       height: ArticleDiagram.sheetHeight, alignment: .topLeading)
                .allowsHitTesting(false)
        } else if let supplied = ArticleFigureFile.image(named: name) {
            ZStack {
                Image(nsImage: supplied.base)
                    .resizable().scaledToFit()
                    .foregroundStyle(ink)
                if let accent = supplied.accent {
                    Image(nsImage: accent)
                        .resizable().scaledToFit()
                        .foregroundStyle(self.accent)
                }
            }
            .padding(.horizontal, 12)
        } else {
            Canvas { context, size in
                draw(name, in: context, size: size)
            }
        }
    }

    private var ink: Color { Palette.navy }
    private var accent: Color { Palette.brass }
    private var faint: Color { Palette.textMuted }

    private func label(_ context: GraphicsContext, _ s: String, at p: CGPoint,
                       colour: Color? = nil, size: CGFloat = 11,
                       weight: Font.Weight = .regular) {
        var resolved = context.resolve(Text(s).font(Face.ui(size, weight)))
        resolved.shading = .color(colour ?? ink)
        context.draw(resolved, at: p, anchor: .center)
    }

    private func line(_ context: GraphicsContext, from a: CGPoint, to b: CGPoint,
                      colour: Color? = nil, width: CGFloat = 1.6, dashed: Bool = false) {
        var path = Path()
        path.move(to: a)
        path.addLine(to: b)
        context.stroke(path, with: .color(colour ?? ink),
                       style: StrokeStyle(lineWidth: width, lineCap: .round,
                                          dash: dashed ? [4, 4] : []))
    }

    private func draw(_ name: String, in context: GraphicsContext, size: CGSize) {
        switch name {
        case "special-right-triangles": specialTriangles(context, size)
        case "parabola": parabola(context, size)
        case "slope": slope(context, size)
        case "circle-sector": circleSector(context, size)
        case "transversal": transversal(context, size)
        case "similar-triangles": similarTriangles(context, size)
        case "scatter-fit": scatterFit(context, size)
        case "outlier-number-line": outlierLine(context, size)
        case "linear-vs-exponential": linearVsExponential(context, size)
        case "inequality-region": inequalityRegion(context, size)
        default: break
        }
    }

    private func specialTriangles(_ c: GraphicsContext, _ size: CGSize) {
        let base = size.height - 44
        let leg = min((size.height - 80) / 1.732, 60)

        let a = CGPoint(x: size.width * 0.28 - leg / 2, y: base)
        let b = CGPoint(x: a.x + leg, y: base)
        let apex = CGPoint(x: a.x, y: base - leg)
        var t1 = Path(); t1.move(to: a); t1.addLine(to: b); t1.addLine(to: apex); t1.closeSubpath()
        c.stroke(t1, with: .color(ink), lineWidth: 1.8)
        rightAngle(c, at: a, dx: 11, dy: -11)
        label(c, "45°", at: CGPoint(x: b.x - 21, y: b.y - 10), size: 10, weight: .medium)
        label(c, "45°", at: CGPoint(x: apex.x + 18, y: apex.y + 16), size: 10, weight: .medium)
        label(c, "1", at: CGPoint(x: a.x - 11, y: base - leg / 2), colour: accent, weight: .semibold)
        label(c, "1", at: CGPoint(x: a.x + leg / 2, y: base + 14), colour: accent, weight: .semibold)
        label(c, "√2", at: CGPoint(x: a.x + leg * 0.74, y: base - leg * 0.62),
              colour: accent, weight: .semibold)

        let a2 = CGPoint(x: size.width * 0.72 - leg / 2, y: base)
        let b2 = CGPoint(x: a2.x + leg, y: base)
        let apex2 = CGPoint(x: a2.x, y: base - leg * 1.732)
        var t2 = Path(); t2.move(to: a2); t2.addLine(to: b2); t2.addLine(to: apex2); t2.closeSubpath()
        c.stroke(t2, with: .color(ink), lineWidth: 1.8)
        rightAngle(c, at: a2, dx: 11, dy: -11)
        label(c, "60°", at: CGPoint(x: b2.x - 21, y: b2.y - 10), size: 10, weight: .medium)
        label(c, "30°", at: CGPoint(x: apex2.x + 17, y: apex2.y + 18), size: 10, weight: .medium)
        label(c, "√3", at: CGPoint(x: a2.x - 13, y: base - leg * 0.86),
              colour: accent, weight: .semibold)
        label(c, "1", at: CGPoint(x: a2.x + leg / 2, y: base + 14),
              colour: accent, weight: .semibold)
        label(c, "2", at: CGPoint(x: a2.x + leg * 0.70, y: base - leg * 0.95),
              colour: accent, weight: .semibold)

        label(c, "45–45–90", at: CGPoint(x: size.width * 0.28, y: base + 30),
              colour: faint, size: 10)
        label(c, "30–60–90", at: CGPoint(x: size.width * 0.72, y: base + 30),
              colour: faint, size: 10)
    }

    private func rightAngle(_ c: GraphicsContext, at p: CGPoint, dx: CGFloat, dy: CGFloat) {
        var box = Path()
        box.move(to: CGPoint(x: p.x + dx, y: p.y))
        box.addLine(to: CGPoint(x: p.x + dx, y: p.y + dy))
        box.addLine(to: CGPoint(x: p.x, y: p.y + dy))
        c.stroke(box, with: .color(faint), lineWidth: 1)
    }

    private func parabola(_ c: GraphicsContext, _ size: CGSize) {
        let cx = size.width / 2
        let axisY = size.height * 0.42
        let vertexY = axisY + 74
        let half = min(size.width / 2 - 70, 150)
        let scale = 74 / (half * half) * 1.55

        line(c, from: CGPoint(x: cx, y: 34), to: CGPoint(x: cx, y: size.height - 34),
             colour: faint, width: 1, dashed: true)
        line(c, from: CGPoint(x: 30, y: axisY), to: CGPoint(x: size.width - 30, y: axisY),
             colour: faint, width: 1)

        var curve = Path()
        var first = true
        for px in stride(from: -half, through: half, by: 2) {
            let y = vertexY - scale * px * px
            guard y > 26 else { continue }
            let point = CGPoint(x: cx + px, y: y)
            if first { curve.move(to: point); first = false } else { curve.addLine(to: point) }
        }
        c.stroke(curve, with: .color(ink), lineWidth: 2)

        c.fill(Path(ellipseIn: CGRect(x: cx - 4, y: vertexY - 4, width: 8, height: 8)),
               with: .color(accent))
        label(c, "vertex (h, k)", at: CGPoint(x: cx, y: vertexY + 18),
              colour: accent, size: 10.5, weight: .semibold)

        let root = ((vertexY - axisY) / scale).squareRoot()
        for dx in [-root, root] {
            c.fill(Path(ellipseIn: CGRect(x: cx + dx - 3.5, y: axisY - 3.5,
                                          width: 7, height: 7)), with: .color(ink))
        }
        label(c, L("x-intercepts"), at: CGPoint(x: cx - root - 42, y: axisY + 15),
              colour: faint, size: 10)
        label(c, L("axis of symmetry"), at: CGPoint(x: cx + 66, y: 30), colour: faint, size: 10)
    }

    private func slope(_ c: GraphicsContext, _ size: CGSize) {
        let l: CGFloat = 58, r = size.width - 120
        let b = size.height - 46, t: CGFloat = 42
        line(c, from: CGPoint(x: l - 20, y: b), to: CGPoint(x: size.width - 24, y: b),
             colour: faint, width: 1)
        line(c, from: CGPoint(x: l - 20, y: b + 8), to: CGPoint(x: l - 20, y: t - 20),
             colour: faint, width: 1)

        let a = CGPoint(x: l, y: b - 24)
        let z = CGPoint(x: r, y: t)
        line(c, from: CGPoint(x: l - 14, y: b - 19), to: CGPoint(x: r + 24, y: t - 8),
             colour: ink, width: 2)

        let corner = CGPoint(x: z.x, y: a.y)
        line(c, from: a, to: corner, colour: accent, width: 1.6, dashed: true)
        line(c, from: corner, to: z, colour: accent, width: 1.6, dashed: true)
        for p in [a, z] {
            c.fill(Path(ellipseIn: CGRect(x: p.x - 4, y: p.y - 4, width: 8, height: 8)),
                   with: .color(ink))
        }
        label(c, "(x₁, y₁)", at: CGPoint(x: a.x + 8, y: a.y - 15), size: 10.5)
        label(c, "(x₂, y₂)", at: CGPoint(x: z.x - 6, y: z.y - 15), size: 10.5)
        label(c, "run", at: CGPoint(x: (a.x + corner.x) / 2, y: a.y + 15),
              colour: accent, size: 10.5, weight: .semibold)
        label(c, "rise", at: CGPoint(x: corner.x + 21, y: (corner.y + z.y) / 2),
              colour: accent, size: 10.5, weight: .semibold)
        label(c, "slope = rise / run", at: CGPoint(x: size.width - 63, y: b - 18),
              colour: ink, size: 10.5, weight: .semibold)
    }

    private func circleSector(_ c: GraphicsContext, _ size: CGSize) {
        let centre = CGPoint(x: size.width / 2 - 30, y: size.height / 2)
        let r: CGFloat = 72
        c.stroke(Path(ellipseIn: CGRect(x: centre.x - r, y: centre.y - r,
                                        width: r * 2, height: r * 2)),
                 with: .color(ink), lineWidth: 1.8)

        var wedge = Path()
        wedge.move(to: centre)
        wedge.addArc(center: centre, radius: r, startAngle: .degrees(-60),
                     endAngle: .degrees(0), clockwise: false)
        wedge.closeSubpath()
        c.fill(wedge, with: .color(accent.opacity(0.28)))
        c.stroke(wedge, with: .color(accent), lineWidth: 1.8)

        c.fill(Path(ellipseIn: CGRect(x: centre.x - 3.5, y: centre.y - 3.5, width: 7, height: 7)),
               with: .color(ink))
        label(c, "(h, k)", at: CGPoint(x: centre.x - 26, y: centre.y + 13), size: 10.5)
        line(c, from: centre, to: CGPoint(x: centre.x + r, y: centre.y), colour: ink, width: 1.4)
        label(c, "r", at: CGPoint(x: centre.x + r / 2, y: centre.y + 13),
              colour: ink, size: 11, weight: .semibold)
        label(c, "θ", at: CGPoint(x: centre.x + 30, y: centre.y - 16),
              colour: accent, size: 12, weight: .semibold)

        let x = size.width - 132
        label(c, "arc = (θ/360) · 2πr", at: CGPoint(x: x, y: centre.y - 14),
              colour: ink, size: 11, weight: .semibold)
        label(c, "sector = (θ/360) · πr²", at: CGPoint(x: x, y: centre.y + 10),
              colour: ink, size: 11, weight: .semibold)
    }

    private func transversal(_ c: GraphicsContext, _ size: CGSize) {
        let x0: CGFloat = 40, x1 = size.width - 40
        let yA = size.height * 0.30, yB = size.height * 0.70
        line(c, from: CGPoint(x: x0, y: yA), to: CGPoint(x: x1, y: yA), colour: ink)
        line(c, from: CGPoint(x: x0, y: yB), to: CGPoint(x: x1, y: yB), colour: ink)

        let top = CGPoint(x: size.width * 0.62, y: yA - 30)
        let bottom = CGPoint(x: size.width * 0.38, y: yB + 30)
        line(c, from: bottom, to: top, colour: accent, width: 1.8)

        func cross(_ y: CGFloat) -> CGPoint {
            let s = (y - bottom.y) / (top.y - bottom.y)
            return CGPoint(x: bottom.x + (top.x - bottom.x) * s, y: y)
        }
        let hitA = cross(yA), hitB = cross(yB)
        label(c, "a", at: CGPoint(x: hitA.x - 17, y: yA - 13), colour: accent,
              size: 12, weight: .semibold)
        label(c, "b", at: CGPoint(x: hitA.x + 16, y: yA + 14), size: 12, weight: .semibold)
        label(c, "a", at: CGPoint(x: hitB.x - 17, y: yB - 13), colour: accent,
              size: 12, weight: .semibold)
        label(c, "b", at: CGPoint(x: hitB.x + 16, y: yB + 14), size: 12, weight: .semibold)
        label(c, L("the two a's are equal"), at: CGPoint(x: x0 + 84, y: (yA + yB) / 2),
              colour: faint, size: 10.5)
        label(c, "a + b = 180°", at: CGPoint(x: x1 - 56, y: (yA + yB) / 2),
              colour: faint, size: 10.5)
    }

    private func similarTriangles(_ c: GraphicsContext, _ size: CGSize) {
        let base = size.height - 48
        let unit = min((size.height - 96) / 3.45, (size.width - 150) / 5.6)
        func triangle(_ ox: CGFloat, _ k: CGFloat, _ tag: String,
                      _ side: String, _ bottom: String) {
            let w = unit * 1.4 * k, h = unit * 1.15 * k
            var p = Path()
            p.move(to: CGPoint(x: ox, y: base))
            p.addLine(to: CGPoint(x: ox + w, y: base))
            p.addLine(to: CGPoint(x: ox + w * 0.34, y: base - h))
            p.closeSubpath()
            c.stroke(p, with: .color(ink), lineWidth: 1.8)
            label(c, bottom, at: CGPoint(x: ox + w / 2, y: base + 14),
                  colour: accent, weight: .semibold)
            label(c, side, at: CGPoint(x: ox + w * 0.67 + 14, y: base - h / 2),
                  colour: accent, weight: .semibold)
            label(c, tag, at: CGPoint(x: ox + w / 2, y: base + 32), colour: faint, size: 10)
        }
        triangle(50, 1, "smaller", "4", "3")
        triangle(size.width - 50 - unit * 1.4 * 3, 3, "larger  (×3)", "12", "9")
    }

    private func scatterFit(_ c: GraphicsContext, _ size: CGSize) {
        let l: CGFloat = 54, r = size.width - 40
        let b = size.height - 40, t: CGFloat = 26
        line(c, from: CGPoint(x: l, y: b), to: CGPoint(x: r, y: b), colour: faint, width: 1)
        line(c, from: CGPoint(x: l, y: b), to: CGPoint(x: l, y: t), colour: faint, width: 1)

        let points: [(Double, Double)] = [
            (0.08, 0.22), (0.16, 0.30), (0.22, 0.24), (0.30, 0.42), (0.36, 0.38),
            (0.44, 0.55), (0.50, 0.48), (0.58, 0.63), (0.64, 0.58), (0.72, 0.76),
            (0.80, 0.70), (0.88, 0.84),
        ]
        for (px, py) in points {
            let x = l + (r - l) * px, y = b - (b - t) * py
            c.fill(Path(ellipseIn: CGRect(x: x - 3, y: y - 3, width: 6, height: 6)),
                   with: .color(ink.opacity(0.75)))
        }
        line(c, from: CGPoint(x: l + (r - l) * 0.04, y: b - (b - t) * 0.20),
             to: CGPoint(x: l + (r - l) * 0.92, y: b - (b - t) * 0.82),
             colour: accent, width: 2)
        label(c, L("line of best fit"), at: CGPoint(x: r - 66, y: t + 14),
              colour: accent, size: 10.5, weight: .semibold)
        label(c, L("slope = the rate, in the units of the axes"),
              at: CGPoint(x: (l + r) / 2, y: b + 20), colour: faint, size: 10)
    }

    private func outlierLine(_ c: GraphicsContext, _ size: CGSize) {
        let l: CGFloat = 54, r = size.width - 54
        let lo: CGFloat = 26, hi: CGFloat = 312
        func at(_ v: CGFloat) -> CGFloat { l + (r - l) * (v - lo) / (hi - lo) }
        let yA = size.height * 0.30, yB = size.height * 0.72

        line(c, from: CGPoint(x: at(33.5), y: yA - 30), to: CGPoint(x: at(33.5), y: yB + 26),
             colour: accent.opacity(0.45), width: 1, dashed: true)

        for (y, values, median, mean) in
            [(yA, [30, 32, 34, 36] as [CGFloat], CGFloat(33), CGFloat(33)),
             (yB, [30, 32, 34, 36, 300] as [CGFloat], CGFloat(34), CGFloat(86.4))] {
            line(c, from: CGPoint(x: l, y: y), to: CGPoint(x: r, y: y), colour: faint, width: 1)
            for v in values {
                c.fill(Path(ellipseIn: CGRect(x: at(v) - 3.5, y: y - 3.5, width: 7, height: 7)),
                       with: .color(ink))
            }
            line(c, from: CGPoint(x: at(median), y: y - 20), to: CGPoint(x: at(median), y: y - 6),
                 colour: accent, width: 1.8)
            line(c, from: CGPoint(x: at(mean), y: y + 6), to: CGPoint(x: at(mean), y: y + 20),
                 colour: ink, width: 1.8)
        }

        label(c, L("the four salaries alone"),
              at: CGPoint(x: l + (r - l) * 0.46, y: yA - 34), colour: faint, size: 10)
        label(c, L("median 33"), at: CGPoint(x: at(33) + 38, y: yA - 28),
              colour: accent, size: 10.5, weight: .semibold)
        label(c, L("mean 33"), at: CGPoint(x: at(33) + 32, y: yA + 30),
              size: 10.5, weight: .semibold)

        label(c, L("with 300 added"),
              at: CGPoint(x: l + (r - l) * 0.46, y: yB - 34), colour: faint, size: 10)
        label(c, L("median 34"), at: CGPoint(x: at(34) + 38, y: yB - 28),
              colour: accent, size: 10.5, weight: .semibold)
        label(c, L("mean 86.4"), at: CGPoint(x: at(86.4), y: yB + 30),
              size: 10.5, weight: .semibold)

        label(c, "30 · 32 · 34 · 36", at: CGPoint(x: at(33) + 24, y: yB + 30),
              colour: faint, size: 9.5)
        label(c, "300", at: CGPoint(x: at(300), y: yB - 18), colour: faint, size: 10)
    }

    private func linearVsExponential(_ c: GraphicsContext, _ size: CGSize) {
        let l: CGFloat = 50, r = size.width - 56
        let b = size.height - 54, t: CGFloat = 38
        line(c, from: CGPoint(x: l, y: b), to: CGPoint(x: r + 10, y: b), colour: faint, width: 1)
        line(c, from: CGPoint(x: l, y: b), to: CGPoint(x: l, y: t - 12), colour: faint, width: 1)

        var straight = Path()
        straight.move(to: CGPoint(x: l, y: b - 10))
        straight.addLine(to: CGPoint(x: r, y: b - (b - t) * 0.55))
        c.stroke(straight, with: .color(faint), style: StrokeStyle(lineWidth: 2, dash: [5, 4]))

        var curve = Path()
        var first = true
        for step in stride(from: 0.0, through: 1.0, by: 0.02) {
            let x = l + (r - l) * step
            let y = b - 10 - (b - t - 10) * (pow(6.0, step) - 1) / 5
            let point = CGPoint(x: x, y: y)
            if first { curve.move(to: point); first = false } else { curve.addLine(to: point) }
        }
        c.stroke(curve, with: .color(accent), lineWidth: 2.2)

        label(c, L("linear — adds the same amount"),
              at: CGPoint(x: l + 118, y: b + 22), colour: faint, size: 10.5)
        label(c, L("exponential — multiplies"),
              at: CGPoint(x: r - 74, y: t - 24), colour: accent, size: 10.5, weight: .semibold)
    }

    private func inequalityRegion(_ c: GraphicsContext, _ size: CGSize) {
        let l: CGFloat = 50, r = size.width - 50
        let b = size.height - 48, t: CGFloat = 34
        line(c, from: CGPoint(x: l, y: b), to: CGPoint(x: r + 6, y: b), colour: faint, width: 1)
        line(c, from: CGPoint(x: l, y: b), to: CGPoint(x: l, y: t - 8), colour: faint, width: 1)

        let a = CGPoint(x: l, y: b - 26)
        let z = CGPoint(x: r, y: t + 26)
        var above = Path()
        above.move(to: a); above.addLine(to: z)
        above.addLine(to: CGPoint(x: r, y: t)); above.addLine(to: CGPoint(x: l, y: t))
        above.closeSubpath()
        c.fill(above, with: .color(accent.opacity(0.20)))
        line(c, from: a, to: z, colour: accent, width: 2, dashed: true)

        label(c, "y > mx + b", at: CGPoint(x: l + 104, y: t + 18),
              colour: accent, size: 11.5, weight: .semibold)
        label(c, L("shaded above the line"), at: CGPoint(x: l + 108, y: t + 36),
              colour: faint, size: 10)
        label(c, L("dashed: the line itself is not included"),
              at: CGPoint(x: (l + r) / 2, y: b + 22), colour: faint, size: 10)
    }
}
