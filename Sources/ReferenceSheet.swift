import SwiftUI

struct ReferenceSheetView: View {
    var onClose: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: 0) {
            header
            Rule(onPaper: true)
            ScrollView {
                sheet
            }
            .background(Paper.canvas)
        }
        .frame(width: 1010, height: 560)
        .background(Paper.canvas)
    }

    var sheet: some View {
        VStack(alignment: .leading, spacing: 26) {
            row1
            row2
            facts
        }
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var header: some View {
        HStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 7) {
                Text(L("Reference"))
                    .font(Face.display(19, .semibold))
                    .foregroundStyle(Paper.navy)
                Rule(brass: true, onPaper: true).frame(width: 32)
            }
            Spacer()
            if let onClose {
                Button(action: onClose) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 15))
                        .foregroundStyle(Paper.card, Paper.textMuted)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(L("Close"))
                .keyboardShortcut(.escape, modifiers: [])
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 18)
        .padding(.bottom, 14)
        .background(Paper.card)
        .overlay(alignment: .bottom) { Rule(onPaper: true) }
    }

    private var row1: some View {
        HStack(alignment: .top, spacing: 20) {
            Item(caption: { VStack(spacing: 3) { Formula("A = πr²"); Formula("C = 2πr") } }) {
                CircleFigure()
            }
            Item(caption: { Formula("A = ℓw") }) { RectangleFigure() }
            Item(caption: { FormulaFrac(lead: "A =", num: "1", den: "2", trail: "bh") }) { TriangleFigure() }
            Item(caption: { Formula("c² = a² + b²") }) { RightTriangleFigure() }
            Item(caption: { Text(L("Special Right Triangles"))
                    .font(.system(size: 13, design: .serif)).foregroundStyle(Paper.navy) }) {
                SpecialTrianglesFigure()
            }
        }
    }

    private var row2: some View {
        HStack(alignment: .top, spacing: 20) {
            Item(caption: { Formula("V = ℓwh") }) { BoxFigure() }
            Item(caption: { Formula("V = πr²h") }) { CylinderFigure() }
            Item(caption: { FormulaFrac(lead: "V =", num: "4", den: "3", trail: "πr³") }) { SphereFigure() }
            Item(caption: { FormulaFrac(lead: "V =", num: "1", den: "3", trail: "πr²h") }) { ConeFigure() }
            Item(caption: { FormulaFrac(lead: "V =", num: "1", den: "3", trail: "ℓwh") }) { PyramidFigure() }
        }
    }

    private var facts: some View {
        VStack(alignment: .leading, spacing: 9) {
            fact(L("The number of degrees of arc in a circle is 360."))
            fact(L("The number of radians of arc in a circle is 2π."))
            fact(L("The sum of the measures in degrees of the angles of a triangle is 180."))
        }
        .padding(.top, 4)
    }

    private func fact(_ s: String) -> some View {
        Text(s).font(.system(size: 13, design: .serif)).foregroundStyle(Paper.navy)
    }
}

private struct Item<Caption: View, Figure: View>: View {
    @ViewBuilder var caption: Caption
    @ViewBuilder var figure: Figure

    init(@ViewBuilder caption: () -> Caption, @ViewBuilder figure: () -> Figure) {
        self.caption = caption()
        self.figure = figure()
    }

    var body: some View {
        VStack(spacing: 8) {
            figure.frame(width: 164, height: 100)
            caption
        }
        .frame(width: 176)
    }
}

private struct Formula: View {
    let text: String
    init(_ t: String) { text = t }
    var body: some View {
        Text(text)
            .font(.system(size: 14, design: .serif))
            .italic()
            .foregroundStyle(Paper.text)
    }
}

private struct FormulaFrac: View {
    let lead: String
    let num: String
    let den: String
    let trail: String

    var body: some View {
        HStack(alignment: .center, spacing: 4) {
            Text(lead).font(.system(size: 14, design: .serif)).italic()
            VStack(spacing: 1) {
                Text(num).font(.system(size: 11, design: .serif)).italic()
                Rectangle().frame(width: 12, height: 1)
                Text(den).font(.system(size: 11, design: .serif)).italic()
            }
            Text(trail).font(.system(size: 14, design: .serif)).italic()
        }
        .foregroundStyle(Paper.text)
    }
}

private var ink: Color { Paper.navy }
private let stroke = StrokeStyle(lineWidth: 1.3, lineCap: .round, lineJoin: .round)
private let dashed = StrokeStyle(lineWidth: 1.1, dash: [3, 3])

private func label(_ s: String, size: CGFloat = 12) -> Text {
    Text(s).font(.system(size: size, design: .serif)).italic().foregroundColor(ink)
}
private func plain(_ s: String, size: CGFloat = 10) -> Text {
    Text(s).font(.system(size: size, design: .serif)).foregroundColor(ink)
}

private struct CircleFigure: View {
    var body: some View {
        Canvas { ctx, size in
            let c = CGPoint(x: size.width / 2 - 8, y: size.height / 2)
            let r: CGFloat = 38
            ctx.stroke(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)),
                       with: .color(ink), style: stroke)
            ctx.fill(Path(ellipseIn: CGRect(x: c.x - 3, y: c.y - 3, width: 6, height: 6)),
                     with: .color(ink))
            var line = Path(); line.move(to: c); line.addLine(to: CGPoint(x: c.x + r, y: c.y))
            ctx.stroke(line, with: .color(ink), style: stroke)
            ctx.draw(label("r"), at: CGPoint(x: c.x + r / 2, y: c.y - 10))
        }
    }
}

private struct RectangleFigure: View {
    var body: some View {
        Canvas { ctx, size in
            let rect = CGRect(x: 22, y: 28, width: 100, height: 46)
            ctx.stroke(Path(rect), with: .color(ink), style: stroke)
            ctx.draw(label("ℓ"), at: CGPoint(x: rect.midX, y: rect.minY - 11))
            ctx.draw(label("w"), at: CGPoint(x: rect.maxX + 12, y: rect.midY))
        }
    }
}

private struct TriangleFigure: View {
    var body: some View {
        Canvas { ctx, size in
            let a = CGPoint(x: 62, y: 16), b = CGPoint(x: 22, y: 74), c = CGPoint(x: 124, y: 74)
            var t = Path(); t.move(to: a); t.addLine(to: b); t.addLine(to: c); t.closeSubpath()
            ctx.stroke(t, with: .color(ink), style: stroke)

            var h = Path(); h.move(to: a); h.addLine(to: CGPoint(x: a.x, y: c.y))
            ctx.stroke(h, with: .color(ink), style: dashed)

            var sq = Path()
            sq.move(to: CGPoint(x: a.x, y: c.y - 9))
            sq.addLine(to: CGPoint(x: a.x + 9, y: c.y - 9))
            sq.addLine(to: CGPoint(x: a.x + 9, y: c.y))
            ctx.stroke(sq, with: .color(ink), style: StrokeStyle(lineWidth: 1))

            ctx.draw(label("h"), at: CGPoint(x: a.x + 11, y: 40))
            ctx.draw(label("b"), at: CGPoint(x: (b.x + c.x) / 2, y: c.y + 12))
        }
    }
}

private struct RightTriangleFigure: View {
    var body: some View {
        Canvas { ctx, size in
            let top = CGPoint(x: 30, y: 20), corner = CGPoint(x: 30, y: 72), right = CGPoint(x: 122, y: 72)
            var t = Path(); t.move(to: top); t.addLine(to: corner); t.addLine(to: right); t.closeSubpath()
            ctx.stroke(t, with: .color(ink), style: stroke)

            var sq = Path()
            sq.move(to: CGPoint(x: corner.x, y: corner.y - 9))
            sq.addLine(to: CGPoint(x: corner.x + 9, y: corner.y - 9))
            sq.addLine(to: CGPoint(x: corner.x + 9, y: corner.y))
            ctx.stroke(sq, with: .color(ink), style: StrokeStyle(lineWidth: 1))

            ctx.draw(label("b"), at: CGPoint(x: corner.x - 11, y: 46))
            ctx.draw(label("a"), at: CGPoint(x: (corner.x + right.x) / 2, y: right.y + 12))
            ctx.draw(label("c"), at: CGPoint(x: 82, y: 36))
        }
    }
}

private func unit(_ v: CGVector) -> CGVector {
    let l = max(0.0001, (v.dx * v.dx + v.dy * v.dy).squareRoot())
    return CGVector(dx: v.dx / l, dy: v.dy / l)
}

private func beside(_ p: CGPoint, _ q: CGPoint, awayFrom inside: CGPoint, by gap: CGFloat) -> CGPoint {
    let mid = CGPoint(x: (p.x + q.x) / 2, y: (p.y + q.y) / 2)
    var n = unit(CGVector(dx: -(q.y - p.y), dy: q.x - p.x))
    if n.dx * (inside.x - mid.x) + n.dy * (inside.y - mid.y) > 0 { n = CGVector(dx: -n.dx, dy: -n.dy) }
    return CGPoint(x: mid.x + n.dx * gap, y: mid.y + n.dy * gap)
}

private func ellipseArc(_ c: CGPoint, _ rx: CGFloat, _ ry: CGFloat, from a0: Double, to a1: Double) -> Path {
    var path = Path()
    let steps = 64
    for i in 0...steps {
        let t = (a0 + (a1 - a0) * Double(i) / Double(steps)) * .pi / 180
        let pt = CGPoint(x: c.x + rx * CGFloat(cos(t)), y: c.y + ry * CGFloat(sin(t)))
        if i == 0 { path.move(to: pt) } else { path.addLine(to: pt) }
    }
    return path
}

private func rightAngle(_ corner: CGPoint, _ p: CGPoint, _ q: CGPoint, size: CGFloat = 7) -> Path {
    let u = unit(CGVector(dx: p.x - corner.x, dy: p.y - corner.y))
    let v = unit(CGVector(dx: q.x - corner.x, dy: q.y - corner.y))
    var path = Path()
    path.move(to: CGPoint(x: corner.x + u.dx * size, y: corner.y + u.dy * size))
    path.addLine(to: CGPoint(x: corner.x + (u.dx + v.dx) * size, y: corner.y + (u.dy + v.dy) * size))
    path.addLine(to: CGPoint(x: corner.x + v.dx * size, y: corner.y + v.dy * size))
    return path
}

private func drawRadical(_ ctx: GraphicsContext, _ coefficient: String, _ radicand: String,
                         at centre: CGPoint, size: CGFloat) {
    let a = ctx.resolve(label(coefficient, size: size))
    let root = ctx.resolve(plain("√", size: size))
    let b = ctx.resolve(label(radicand, size: size))
    let big = CGSize(width: 200, height: 200)
    let wa = a.measure(in: big).width, wr = root.measure(in: big).width, wb = b.measure(in: big).width
    var x = centre.x - (wa + wr + wb) / 2
    ctx.draw(a, at: CGPoint(x: x + wa / 2, y: centre.y)); x += wa
    ctx.draw(root, at: CGPoint(x: x + wr / 2, y: centre.y)); x += wr
    ctx.draw(b, at: CGPoint(x: x + wb / 2, y: centre.y))
    var bar = Path()
    let top = centre.y - size * 0.52
    bar.move(to: CGPoint(x: x - wr * 0.12, y: top)); bar.addLine(to: CGPoint(x: x + wb + 0.5, y: top))
    ctx.stroke(bar, with: .color(ink), style: StrokeStyle(lineWidth: 0.8))
}

enum SheetGeometry {
    static let thirtySixty: (p: CGPoint, q: CGPoint, r: CGPoint) = {
        let short: CGFloat = 32, long = 32 * CGFloat(3).squareRoot()
        return (CGPoint(x: 2, y: 72), CGPoint(x: 2 + long, y: 72), CGPoint(x: 2 + long, y: 72 - short))
    }()
    static let fortyFive: (a: CGPoint, b: CGPoint, c: CGPoint) =
        (CGPoint(x: 88, y: 32), CGPoint(x: 88, y: 72), CGPoint(x: 128, y: 72))
    static let angleLabelRadius: (thirty: CGFloat, sixty: CGFloat, fortyFive: CGFloat) = (6.8, 8, 8)

    static let cylinderTop = CGPoint(x: 66, y: 20)
    static let cylinderRadii: (rx: CGFloat, ry: CGFloat) = (34, 13)
    static var cylinderRadiusStart: CGPoint { cylinderTop }

    static let pyramidBase: (fl: CGPoint, fr: CGPoint, bl: CGPoint, br: CGPoint) =
        (CGPoint(x: 20, y: 76), CGPoint(x: 96, y: 76), CGPoint(x: 44, y: 58), CGPoint(x: 120, y: 58))
    static var pyramidCentre: CGPoint {
        CGPoint(x: (pyramidBase.fl.x + pyramidBase.br.x) / 2, y: (pyramidBase.fl.y + pyramidBase.br.y) / 2)
    }
    static var pyramidApex: CGPoint { CGPoint(x: pyramidCentre.x, y: 10) }

    static func insideAngle(_ vertex: CGPoint, _ p: CGPoint, _ q: CGPoint, radius: CGFloat) -> CGPoint {
        let u = unit(CGVector(dx: p.x - vertex.x, dy: p.y - vertex.y))
        let v = unit(CGVector(dx: q.x - vertex.x, dy: q.y - vertex.y))
        let bis = unit(CGVector(dx: u.dx + v.dx, dy: u.dy + v.dy))
        let half = acos(max(-1, min(1, u.dx * v.dx + u.dy * v.dy))) / 2
        let d = radius / max(0.05, sin(half))
        return CGPoint(x: vertex.x + bis.dx * d, y: vertex.y + bis.dy * d)
    }
}

private struct SpecialTrianglesFigure: View {
    var body: some View {
        Canvas { ctx, size in
            let (p, q, r) = SheetGeometry.thirtySixty
            let room = SheetGeometry.angleLabelRadius
            var t1 = Path(); t1.move(to: p); t1.addLine(to: q); t1.addLine(to: r); t1.closeSubpath()
            ctx.stroke(t1, with: .color(ink), style: stroke)
            ctx.stroke(rightAngle(q, p, r), with: .color(ink), style: StrokeStyle(lineWidth: 1))
            let in1 = CGPoint(x: (p.x + q.x + r.x) / 3, y: (p.y + q.y + r.y) / 3)
            ctx.draw(label("2x", size: 11), at: beside(p, r, awayFrom: in1, by: 9))
            ctx.draw(label("x", size: 11), at: beside(q, r, awayFrom: in1, by: 7))
            drawRadical(ctx, "x", "3", at: beside(p, q, awayFrom: in1, by: 9), size: 11)
            ctx.draw(plain("30°", size: 7.5), at: SheetGeometry.insideAngle(p, q, r, radius: room.thirty))
            ctx.draw(plain("60°", size: 7.5), at: SheetGeometry.insideAngle(r, p, q, radius: room.sixty))

            let (a, b, c) = SheetGeometry.fortyFive
            var t2 = Path(); t2.move(to: a); t2.addLine(to: b); t2.addLine(to: c); t2.closeSubpath()
            ctx.stroke(t2, with: .color(ink), style: stroke)
            ctx.stroke(rightAngle(b, a, c), with: .color(ink), style: StrokeStyle(lineWidth: 1))
            let in2 = CGPoint(x: (a.x + b.x + c.x) / 3, y: (a.y + b.y + c.y) / 3)
            ctx.draw(label("s", size: 11), at: beside(a, b, awayFrom: in2, by: 7))
            ctx.draw(label("s", size: 11), at: beside(b, c, awayFrom: in2, by: 9))
            drawRadical(ctx, "s", "2", at: beside(a, c, awayFrom: in2, by: 12), size: 11)
            ctx.draw(plain("45°", size: 7.5), at: SheetGeometry.insideAngle(a, b, c, radius: room.fortyFive))
            ctx.draw(plain("45°", size: 7.5), at: SheetGeometry.insideAngle(c, a, b, radius: room.fortyFive))
        }
    }
}

private struct BoxFigure: View {
    var body: some View {
        Canvas { ctx, size in
            let x0: CGFloat = 20, y0: CGFloat = 34, w: CGFloat = 78, h: CGFloat = 34
            let dx: CGFloat = 22, dy: CGFloat = 16

            var front = Path(); front.addRect(CGRect(x: x0, y: y0, width: w, height: h))
            var top = Path()
            top.move(to: CGPoint(x: x0, y: y0)); top.addLine(to: CGPoint(x: x0 + dx, y: y0 - dy))
            top.addLine(to: CGPoint(x: x0 + w + dx, y: y0 - dy)); top.addLine(to: CGPoint(x: x0 + w, y: y0))
            top.closeSubpath()
            var side = Path()
            side.move(to: CGPoint(x: x0 + w, y: y0)); side.addLine(to: CGPoint(x: x0 + w + dx, y: y0 - dy))
            side.addLine(to: CGPoint(x: x0 + w + dx, y: y0 + h - dy)); side.addLine(to: CGPoint(x: x0 + w, y: y0 + h))
            side.closeSubpath()

            for p in [front, top, side] { ctx.stroke(p, with: .color(ink), style: stroke) }

            ctx.draw(label("h"), at: CGPoint(x: x0 + w + dx + 10, y: y0 + h - dy / 2 - 4))
            ctx.draw(label("w"), at: CGPoint(x: x0 + w + dx / 2 + 4, y: y0 + h - dy / 2 + 12))
            ctx.draw(label("ℓ"), at: CGPoint(x: x0 + w / 2 - 6, y: y0 + h + 12))
        }
    }
}

private struct CylinderFigure: View {
    var body: some View {
        Canvas { ctx, size in
            let top = SheetGeometry.cylinderTop, (rx, ry) = SheetGeometry.cylinderRadii
            let cx = top.x, topY = top.y, botY: CGFloat = 72
            let bottom = CGPoint(x: cx, y: botY)

            ctx.stroke(ellipseArc(top, rx, ry, from: 0, to: 360), with: .color(ink), style: stroke)
            var sides = Path()
            sides.move(to: CGPoint(x: cx - rx, y: topY)); sides.addLine(to: CGPoint(x: cx - rx, y: botY))
            sides.move(to: CGPoint(x: cx + rx, y: topY)); sides.addLine(to: CGPoint(x: cx + rx, y: botY))
            ctx.stroke(sides, with: .color(ink), style: stroke)
            ctx.stroke(ellipseArc(bottom, rx, ry, from: 0, to: 180), with: .color(ink), style: stroke)

            let rim = CGPoint(x: cx + rx * CGFloat(cos(-0.35)), y: topY + ry * CGFloat(sin(-0.35)))
            ctx.fill(Path(ellipseIn: CGRect(x: cx - 2.5, y: topY - 2.5, width: 5, height: 5)), with: .color(ink))
            var rline = Path(); rline.move(to: SheetGeometry.cylinderRadiusStart); rline.addLine(to: rim)
            ctx.stroke(rline, with: .color(ink), style: stroke)
            ctx.draw(label("r"), at: CGPoint(x: (cx + rim.x) / 2, y: topY + 4.5))
            ctx.draw(label("h"), at: CGPoint(x: cx + rx + 11, y: (topY + botY) / 2))
        }
    }
}

private struct SphereFigure: View {
    var body: some View {
        Canvas { ctx, size in
            let c = CGPoint(x: 68, y: 48), r: CGFloat = 38, ry: CGFloat = 14
            ctx.stroke(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)),
                       with: .color(ink), style: stroke)
            ctx.stroke(ellipseArc(c, r, ry, from: 180, to: 360), with: .color(ink), style: dashed)
            ctx.stroke(ellipseArc(c, r, ry, from: 0, to: 180), with: .color(ink), style: stroke)

            ctx.fill(Path(ellipseIn: CGRect(x: c.x - 3, y: c.y - 3, width: 6, height: 6)), with: .color(ink))
            var rl = Path(); rl.move(to: c); rl.addLine(to: CGPoint(x: c.x + r, y: c.y))
            ctx.stroke(rl, with: .color(ink), style: stroke)
            ctx.draw(label("r"), at: CGPoint(x: c.x + r / 2, y: c.y + 5))
        }
    }
}

private struct ConeFigure: View {
    var body: some View {
        Canvas { ctx, size in
            let cx: CGFloat = 66, cy: CGFloat = 68, rx: CGFloat = 34, ry: CGFloat = 14
            let apex = CGPoint(x: cx, y: 10), centre = CGPoint(x: cx, y: cy)

            var sides = Path()
            sides.move(to: CGPoint(x: cx - rx, y: cy)); sides.addLine(to: apex)
            sides.addLine(to: CGPoint(x: cx + rx, y: cy))
            ctx.stroke(sides, with: .color(ink), style: stroke)
            ctx.stroke(ellipseArc(centre, rx, ry, from: 0, to: 180), with: .color(ink), style: stroke)
            ctx.stroke(ellipseArc(centre, rx, ry, from: 180, to: 360), with: .color(ink), style: dashed)

            var hl = Path(); hl.move(to: apex); hl.addLine(to: centre)
            ctx.stroke(hl, with: .color(ink), style: stroke)
            var rl = Path(); rl.move(to: centre); rl.addLine(to: CGPoint(x: cx + rx, y: cy))
            ctx.stroke(rl, with: .color(ink), style: dashed)
            ctx.stroke(rightAngle(centre, apex, CGPoint(x: cx + rx, y: cy)), with: .color(ink),
                       style: StrokeStyle(lineWidth: 1))

            ctx.draw(label("h"), at: CGPoint(x: cx - 8, y: 46))
            ctx.draw(label("r"), at: CGPoint(x: cx + rx / 2, y: cy + 5.5))
        }
    }
}

private struct PyramidFigure: View {
    var body: some View {
        Canvas { ctx, size in
            let (fl, fr, bl, br) = SheetGeometry.pyramidBase
            let centre = SheetGeometry.pyramidCentre, apex = SheetGeometry.pyramidApex

            var solid = Path()
            solid.move(to: fl); solid.addLine(to: fr); solid.addLine(to: br)
            solid.move(to: fl); solid.addLine(to: apex); solid.addLine(to: fr)
            solid.move(to: apex); solid.addLine(to: br)
            ctx.stroke(solid, with: .color(ink), style: stroke)

            var hidden = Path()
            hidden.move(to: fl); hidden.addLine(to: bl); hidden.addLine(to: br)
            hidden.move(to: bl); hidden.addLine(to: apex)
            hidden.move(to: apex); hidden.addLine(to: centre)
            ctx.stroke(hidden, with: .color(ink), style: dashed)
            ctx.stroke(rightAngle(centre, apex, CGPoint(x: centre.x + 10, y: centre.y)), with: .color(ink),
                       style: StrokeStyle(lineWidth: 1))

            ctx.draw(label("h"), at: CGPoint(x: centre.x - 7, y: 40))
            ctx.draw(label("w"), at: beside(fr, br, awayFrom: centre, by: 9))
            ctx.draw(label("ℓ"), at: beside(fl, fr, awayFrom: centre, by: 10))
        }
    }
}
