import AppKit

private let navy = CGColor(red: 0.106, green: 0.165, blue: 0.290, alpha: 1)
private let navyDeep = CGColor(red: 0.055, green: 0.086, blue: 0.161, alpha: 1)
private let beige = CGColor(red: 0.957, green: 0.941, blue: 0.910, alpha: 1)

private func onRing(_ c: CGPoint, _ radius: CGFloat, _ degrees: Double) -> CGPoint {
    let r = degrees * .pi / 180
    return CGPoint(x: c.x + CGFloat(cos(r)) * radius, y: c.y + CGFloat(sin(r)) * radius)
}

private func drawSeal(_ ctx: CGContext, center c: CGPoint, s: CGFloat, ink: CGColor) {
    let full = s >= 300
    let crest = s >= 96
    let line = max(0.9, s * 0.0062 * (s < 128 ? 1.6 : 1))
    ctx.setStrokeColor(ink)
    ctx.setLineJoin(.round)
    ctx.setLineCap(.round)

    for r in (full ? [0.487, 0.462, 0.352, 0.336] : [0.487, 0.455]) as [CGFloat] {
        let heavy = (r == 0.462 || r == 0.352 || r == 0.455)
        ctx.setLineWidth(heavy ? line * 1.9 : line)
        ctx.strokeEllipse(in: CGRect(x: c.x - s * r, y: c.y - s * r,
                                     width: s * r * 2, height: s * r * 2))
    }

    if full { drawArcText(ctx, center: c, s: s, ink: ink) }

    let field: CGFloat = full ? 1 : 1.34
    if crest { drawWreath(ctx, center: c, s: s, field: field, line: line, ink: ink) }
    drawBook(ctx, center: c, s: s, field: crest ? field : 1.7, line: line,
             ink: ink, ruled: crest)
}

private func drawArcText(_ ctx: CGContext, center c: CGPoint, s: CGFloat, ink: CGColor) {
    func set(_ text: String, radius: CGFloat, centredOn: Double, sweep: Double,
             size: CGFloat, upright: Bool) {
        let characters = Array(text)
        guard characters.count > 1 else { return }
        let step = sweep / Double(characters.count - 1)
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont(descriptor: NSFont.systemFont(ofSize: size, weight: .semibold)
                .fontDescriptor.withDesign(.serif) ?? NSFont.systemFont(ofSize: size).fontDescriptor,
                          size: size) ?? NSFont.systemFont(ofSize: size, weight: .semibold),
            .foregroundColor: NSColor(cgColor: ink) ?? .white,
        ]
        for (i, character) in characters.enumerated() where character != " " {
            let degrees = upright ? centredOn - sweep / 2 + step * Double(i)
                                  : centredOn + sweep / 2 - step * Double(i)
            let point = onRing(c, radius, degrees)
            let glyph = String(character) as NSString
            let measured = glyph.size(withAttributes: attrs)

            ctx.saveGState()
            ctx.translateBy(x: point.x, y: point.y)
            ctx.rotate(by: CGFloat((degrees + (upright ? 90 : -90)) * .pi / 180))
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: true)
            glyph.draw(at: NSPoint(x: -measured.width / 2, y: -measured.height / 2),
                       withAttributes: attrs)
            NSGraphicsContext.restoreGraphicsState()
            ctx.restoreGState()
        }
    }
    set("UNITED STATES UNIVERSITIES FOR UKRAINE", radius: s * 0.404,
        centredOn: 270, sweep: 212, size: s * 0.054, upright: true)
    set("Est. 2026", radius: s * 0.392, centredOn: 90, sweep: 46,
        size: s * 0.061, upright: false)
}

private func drawWreath(_ ctx: CGContext, center c: CGPoint, s: CGFloat,
                        field: CGFloat, line: CGFloat, ink: CGColor) {
    for mirrored in [false, true] {
        ctx.saveGState()
        if mirrored {
            ctx.translateBy(x: c.x, y: c.y)
            ctx.scaleBy(x: -1, y: 1)
            ctx.translateBy(x: -c.x, y: -c.y)
        }
        let from = -66.0, to = 86.0
        let stemRadius = s * 0.238 * field

        ctx.setLineWidth(line * 1.5)
        ctx.beginPath()
        for i in 0...56 {
            let p = onRing(c, stemRadius, from + (to - from) * Double(i) / 56)
            if i == 0 { ctx.move(to: p) } else { ctx.addLine(to: p) }
        }
        ctx.strokePath()

        ctx.setLineWidth(line)
        for i in 0..<9 {
            let t = Double(i) / 8
            let degrees = from + (to - from) * t
            let length = s * CGFloat(0.052 + 0.042 * t) * field
            let width = length * 0.44
            let anchor = onRing(c, stemRadius, degrees)
            for outward in [true, false] {
                let axis = (outward ? degrees : degrees + 180) - 34
                let span = length * (outward ? 1 : 0.78)
                let offset = onRing(.zero, span * 0.52, axis)
                ctx.saveGState()
                ctx.translateBy(x: anchor.x + offset.x, y: anchor.y + offset.y)
                ctx.rotate(by: CGFloat(axis * .pi / 180))
                ctx.strokeEllipse(in: CGRect(x: -span / 2, y: -width / 2,
                                             width: span, height: width))
                ctx.restoreGState()
            }
        }
        ctx.restoreGState()
    }
}

private func drawBook(_ ctx: CGContext, center c: CGPoint, s: CGFloat,
                      field: CGFloat, line: CGFloat, ink: CGColor, ruled: Bool) {
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

        ctx.setLineWidth(line * 1.6)
        ctx.beginPath()
        ctx.move(to: CGPoint(x: inner, y: spineTop))
        ctx.addQuadCurve(to: CGPoint(x: outer, y: leafTop),
                         control: CGPoint(x: c.x + side * halfWidth * 0.52,
                                          y: spineTop - height * 0.10))
        ctx.addLine(to: CGPoint(x: outer, y: leafFoot))
        ctx.addQuadCurve(to: CGPoint(x: inner, y: spineFoot),
                         control: CGPoint(x: c.x + side * halfWidth * 0.52,
                                          y: spineFoot - height * 0.02))
        ctx.closePath()
        ctx.strokePath()

        let thickness = s * 0.015 * field
        ctx.setLineWidth(line)
        ctx.beginPath()
        ctx.move(to: CGPoint(x: outer, y: leafTop))
        ctx.addLine(to: CGPoint(x: outer + side * thickness, y: leafTop + height * 0.14))
        ctx.addLine(to: CGPoint(x: outer + side * thickness, y: leafFoot + height * 0.12))
        ctx.addLine(to: CGPoint(x: outer, y: leafFoot))
        ctx.strokePath()

        if ruled {
            ctx.setLineWidth(line * 0.85)
            for n in 0..<3 {
                let y = leafTop + height * (0.42 + 0.34 * CGFloat(n))
                let inset = halfWidth * (0.16 + 0.05 * CGFloat(n))
                ctx.beginPath()
                ctx.move(to: CGPoint(x: inner + side * halfWidth * 0.16, y: y))
                ctx.addLine(to: CGPoint(x: outer - side * inset, y: y))
                ctx.strokePath()
            }
        }
    }

    ctx.setLineWidth(line * 1.6)
    ctx.beginPath()
    ctx.move(to: CGPoint(x: c.x, y: spineTop))
    ctx.addLine(to: CGPoint(x: c.x, y: spineFoot))
    ctx.strokePath()

    ctx.setLineWidth(line * 1.2)
    ctx.stroke(CGRect(x: c.x - s * 0.020 * field, y: spineFoot,
                      width: s * 0.040 * field, height: s * 0.024 * field))
}

let artwork: CGImage? = {
    guard CommandLine.arguments.count > 2,
          let image = NSImage(contentsOfFile: CommandLine.arguments[2]) else { return nil }
    var rect = CGRect(origin: .zero, size: image.size)
    return image.cgImage(forProposedRect: &rect, context: nil, hints: nil)
}()

func drawIcon(size: CGFloat) -> Data? {
    let image = NSImage(size: NSSize(width: size, height: size))
    image.lockFocus()
    guard let ctx = NSGraphicsContext.current?.cgContext else { image.unlockFocus(); return nil }

    let inset = size * 0.06
    let rect = CGRect(x: inset, y: inset, width: size - inset * 2, height: size - inset * 2)
    let squircle = CGPath(roundedRect: rect, cornerWidth: size * 0.22,
                          cornerHeight: size * 0.22, transform: nil)

    ctx.saveGState()
    ctx.addPath(squircle)
    ctx.clip()
    let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                              colors: [navy, navyDeep] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(gradient, start: CGPoint(x: 0, y: size),
                           end: CGPoint(x: size, y: 0), options: [])
    ctx.restoreGState()

    if let artwork, size >= 128 {
        let side = size * 0.74
        let box = CGRect(x: (size - side) / 2, y: (size - side) / 2,
                         width: side, height: side)
        ctx.saveGState()
        ctx.clip(to: box, mask: artwork)
        ctx.setFillColor(beige)
        ctx.fill(box)
        ctx.restoreGState()
    } else {
        ctx.saveGState()
        ctx.translateBy(x: 0, y: size)
        ctx.scaleBy(x: 1, y: -1)
        drawSeal(ctx, center: CGPoint(x: size / 2, y: size / 2), s: size * 0.72, ink: beige)
        ctx.restoreGState()
    }

    image.unlockFocus()
    guard let tiff = image.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff)
    else { return nil }
    bitmap.size = NSSize(width: size, height: size)
    return bitmap.representation(using: .png, properties: [:])
}

let out = CommandLine.arguments[1]
try? FileManager.default.createDirectory(atPath: out, withIntermediateDirectories: true)
for (name, px) in [("icon_16x16", 16), ("icon_16x16@2x", 32), ("icon_32x32", 32),
                   ("icon_32x32@2x", 64), ("icon_128x128", 128), ("icon_128x128@2x", 256),
                   ("icon_256x256", 256), ("icon_256x256@2x", 512), ("icon_512x512", 512),
                   ("icon_512x512@2x", 1024)] {
    if let data = drawIcon(size: CGFloat(px)) {
        try? data.write(to: URL(fileURLWithPath: "\(out)/\(name).png"))
    }
}
print("icons written")
