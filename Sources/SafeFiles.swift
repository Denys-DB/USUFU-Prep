import Foundation

enum DamagedFile {

    static let marker = ".damaged-"

    static func isSetAside(_ name: String) -> Bool { name.contains(marker) }

    private static func stamp(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyyMMdd-HHmmss"
        return f.string(from: date)
    }

    @discardableResult
    static func setAside(_ url: URL, now: Date = Date()) -> URL? {
        let fm = FileManager.default
        guard fm.fileExists(atPath: url.path) else { return nil }
        let base = "\(url.lastPathComponent)\(marker)\(stamp(now))"
        let dir = url.deletingLastPathComponent()
        var target = dir.appendingPathComponent(base)
        var n = 2
        while fm.fileExists(atPath: target.path) {
            target = dir.appendingPathComponent("\(base)-\(n)")
            n += 1
        }
        do {
            try fm.moveItem(at: url, to: target)
            return target
        } catch {
            return nil
        }
    }

    static func load<T: Decodable>(_ type: T.Type, from url: URL,
                                   decoder: JSONDecoder = JSONDecoder(),
                                   damaged: (URL) -> Void) -> T? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        if let data = try? Data(contentsOf: url),
           let value = try? decoder.decode(T.self, from: data) {
            return value
        }
        damaged(setAside(url) ?? url)
        return nil
    }
}
