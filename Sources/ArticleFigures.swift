import SwiftUI
import AppKit

enum ArticleFigureFile {

    struct Art { var base: NSImage; var accent: NSImage? }

    private static var cache: [String: Art?] = [:]

    static func image(named name: String) -> Art? {
        if let hit = cache[name] { return hit }
        let found = load(name)
        cache[name] = found
        return found
    }

    static func forget() { cache = [:] }

    private static func load(_ name: String) -> Art? {
        guard let base = read(name) else { return nil }
        base.isTemplate = true
        let accent = read(name + "-accent")
        accent?.isTemplate = true
        return Art(base: base, accent: accent)
    }

    private static func read(_ name: String) -> NSImage? {
        if let url = Bundle.main.url(forResource: name, withExtension: "png"),
           let image = NSImage(contentsOf: url) {
            return image
        }
        let beside = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Resources/Articles/figures/\(name).png")
        guard FileManager.default.fileExists(atPath: beside.path) else { return nil }
        return NSImage(contentsOf: beside)
    }

    static let names = [
        "special-right-triangles", "parabola", "slope", "circle-sector",
        "transversal", "similar-triangles", "scatter-fit",
        "outlier-number-line", "linear-vs-exponential", "inequality-region",
    ]
}
