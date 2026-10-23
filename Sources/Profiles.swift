import Foundation

struct Profile: Codable, Identifiable, Hashable {
    var id: String = UUID().uuidString
    var name: String = ""
    var accent: Int = 0
    var createdAt: Date = Date()
    var lastUsedAt: Date = Date()

    init(id: String = UUID().uuidString, name: String, accent: Int = 0) {
        self.id = id
        self.name = name
        self.accent = accent
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        accent = try c.decodeIfPresent(Int.self, forKey: .accent) ?? 0
        createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        lastUsedAt = try c.decodeIfPresent(Date.self, forKey: .lastUsedAt) ?? createdAt
    }

    var initials: String {
        let words = name.split(separator: " ").filter { $0.first?.isLetter == true }.prefix(2)
        let letters = words.compactMap { $0.first }.map(String.init)
        return letters.isEmpty ? "?" : letters.joined().uppercased()
    }

    var displayName: String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return L("Student") }
        guard trimmed.count > Profile.nameShownLimit else { return trimmed }
        return String(trimmed.prefix(Profile.nameShownLimit - 1)) + "…"
    }

    static let nameShownLimit = 22
    static let accents = 6
}

struct ProfileBook: Codable {
    var profiles: [Profile] = []
    var lastUsedID: String? = nil
    var sweptLegacy: Bool = false

    init(profiles: [Profile] = [], lastUsedID: String? = nil) {
        self.profiles = profiles
        self.lastUsedID = lastUsedID
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        profiles = try c.decodeIfPresent([Profile].self, forKey: .profiles) ?? []
        lastUsedID = try c.decodeIfPresent(String.self, forKey: .lastUsedID)
        sweptLegacy = try c.decodeIfPresent(Bool.self, forKey: .sweptLegacy) ?? false
    }
}

struct ProfileStore {

    let sharedRoot: URL
    private(set) var book: ProfileBook
    private(set) var recoveredFrom: URL? = nil

    static let personalFolders = ["Progress", "Sessions", "Notes", "Decks"]
    static let personalFiles = ["Plans.json", "Settings.json", "Library.json"]

    var profiles: [Profile] { book.profiles }

    private var bookFile: URL { sharedRoot.appendingPathComponent("Profiles.json") }
    private var profilesDir: URL {
        sharedRoot.appendingPathComponent("Profiles", isDirectory: true)
    }

    func directory(of id: String) -> URL {
        profilesDir.appendingPathComponent(id, isDirectory: true)
    }

    static func open(sharedRoot: URL, defaultName: @autoclosure () -> String) -> ProfileStore {
        var store = ProfileStore(sharedRoot: sharedRoot, book: ProfileBook())
        let fm = FileManager.default
        let raw = try? Data(contentsOf: store.bookFile)
        if fm.fileExists(atPath: store.bookFile.path),
           raw.flatMap({ try? JSONDecoder().decode(ProfileBook.self, from: $0) }) == nil {
            store.recoveredFrom = DamagedFile.setAside(store.bookFile) ?? store.bookFile
            store.book = Self.rebuilt(from: raw ?? Data(), folders: store.profilesDir)
            if !store.book.profiles.isEmpty { store.save() }
        } else if let data = raw,
           let book = try? JSONDecoder().decode(ProfileBook.self, from: data) {
            store.book = book
            store.healDuplicates()
        }
        if store.book.profiles.isEmpty {
            let first = store.migrateSingleStudent(named: defaultName())
            store.book.profiles = [first]
            store.book.lastUsedID = first.id
            store.save()
        } else {
            store.sweepLegacyFolders()
        }
        return store
    }

    static func rebuilt(from damaged: Data, folders: URL) -> ProfileBook {
        let fm = FileManager.default
        let text = String(decoding: damaged, as: UTF8.self)
        var salvaged = [String: (name: String, accent: Int)]()
        if let rx = try? NSRegularExpression(
            pattern: "\\{[^{}]*?\"id\"\\s*:\\s*\"([0-9A-Fa-f-]{36})\"[^{}]*") {
            let ns = text as NSString
            for m in rx.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
                let object = ns.substring(with: m.range)
                let id = ns.substring(with: m.range(at: 1))
                func field(_ key: String, _ pattern: String) -> String? {
                    guard let r = try? NSRegularExpression(pattern: "\"" + key + "\"\\s*:\\s*" + pattern),
                          let hit = r.firstMatch(in: object, range: NSRange(location: 0,
                                                 length: (object as NSString).length))
                    else { return nil }
                    return (object as NSString).substring(with: hit.range(at: 1))
                }
                let name = field("name", "\"((?:[^\"\\\\]|\\\\.)*)\"")
                    .flatMap { try? JSONSerialization.jsonObject(with: Data("\"\($0)\"".utf8),
                                                                 options: .fragmentsAllowed) as? String } ?? ""
                let accent = field("accent", "(-?\\d+)").flatMap(Int.init) ?? 0
                salvaged[id.uppercased()] = (name, accent)
            }
        }
        var lastUsed: String? = nil
        if let rx = try? NSRegularExpression(pattern: "\"lastUsedID\"\\s*:\\s*\"([0-9A-Fa-f-]{36})\""),
           let hit = rx.firstMatch(in: text, range: NSRange(location: 0, length: (text as NSString).length)) {
            lastUsed = (text as NSString).substring(with: hit.range(at: 1))
        }

        let dirs = ((try? fm.contentsOfDirectory(at: folders, includingPropertiesForKeys: [.contentModificationDateKey])) ?? [])
            .filter { $0.hasDirectoryPath && UUID(uuidString: $0.lastPathComponent) != nil }
        func modified(_ url: URL) -> Date {
            (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
        }
        var book = ProfileBook()
        var used = Set<String>()
        for dir in dirs.sorted(by: { modified($0) < modified($1) }) {
            let id = dir.lastPathComponent
            let found = salvaged[id.uppercased()]
            var name = (found?.name ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if name.isEmpty { name = L("Student") }
            var unique = name
            var n = 2
            while used.contains(unique) { unique = "\(name) \(n)"; n += 1 }
            used.insert(unique)
            var profile = Profile(id: id, name: unique, accent: found?.accent ?? (book.profiles.count % Profile.accents))
            profile.lastUsedAt = modified(dir)
            book.profiles.append(profile)
        }
        book.lastUsedID = book.profiles.contains { $0.id == lastUsed } ? lastUsed
            : book.profiles.max { $0.lastUsedAt < $1.lastUsedAt }?.id
        book.sweptLegacy = true
        return book
    }

    var current: Profile {
        book.profiles.first { $0.id == book.lastUsedID } ?? book.profiles[0]
    }

    private func migrateSingleStudent(named name: String) -> Profile {
        let profile = Profile(name: name)
        let dir = directory(of: profile.id)
        let fm = FileManager.default
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        for folder in Self.personalFolders {
            let from = sharedRoot.appendingPathComponent(folder, isDirectory: true)
            guard fm.fileExists(atPath: from.path) else { continue }
            try? fm.copyItem(at: from, to: dir.appendingPathComponent(folder, isDirectory: true))
        }
        for file in Self.personalFiles {
            let from = sharedRoot.appendingPathComponent(file)
            guard fm.fileExists(atPath: from.path) else { continue }
            try? fm.copyItem(at: from, to: dir.appendingPathComponent(file))
        }
        return profile
    }

    @discardableResult
    mutating func sweepLegacyFolders() -> Bool {
        guard !book.sweptLegacy, !book.profiles.isEmpty else { return false }
        let fm = FileManager.default

        func contents(of dir: URL) -> Set<String> {
            guard let walker = fm.enumerator(at: dir, includingPropertiesForKeys: nil)
            else { return [] }
            var out = Set<String>()
            for case let url as URL in walker where !url.hasDirectoryPath {
                out.insert(url.lastPathComponent)
            }
            return out
        }

        var legacy = [URL: Set<String>]()
        for folder in Self.personalFolders {
            let dir = sharedRoot.appendingPathComponent(folder, isDirectory: true)
            guard fm.fileExists(atPath: dir.path) else { continue }
            legacy[dir] = contents(of: dir)
        }
        for file in Self.personalFiles {
            let url = sharedRoot.appendingPathComponent(file)
            guard fm.fileExists(atPath: url.path) else { continue }
            legacy[url] = [file]
        }
        guard !legacy.isEmpty else {
            book.sweptLegacy = true
            save()
            return false
        }

        var held = Set<String>()
        for profile in book.profiles {
            held.formUnion(contents(of: directory(of: profile.id)))
        }

        for (_, names) in legacy where !names.isSubset(of: held) { return false }
        for (url, _) in legacy { try? fm.removeItem(at: url) }
        book.sweptLegacy = true
        save()
        return true
    }

    mutating func add(named name: String) -> Profile {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        var profile = Profile(name: trimmed.isEmpty ? unusedName() : distinct(trimmed),
                              accent: leastUsedAccent())
        profile.createdAt = Date()
        profile.lastUsedAt = Date()
        try? FileManager.default.createDirectory(at: directory(of: profile.id),
                                                 withIntermediateDirectories: true)
        book.profiles.append(profile)
        save()
        return profile
    }

    mutating func healDuplicates() {
        var seenNames = Set<String>()
        var changed = false
        for i in book.profiles.indices {
            let name = book.profiles[i].name
            if seenNames.contains(name) {
                var n = 2
                while seenNames.contains("\(name) \(n)") { n += 1 }
                book.profiles[i].name = "\(name) \(n)"
                changed = true
            }
            seenNames.insert(book.profiles[i].name)
        }
        var usedAccents = [Int: Int]()
        for i in book.profiles.indices {
            let accent = book.profiles[i].accent
            if usedAccents[accent] != nil, book.profiles.count <= Profile.accents {
                book.profiles[i].accent = leastUsedAccent(excluding: i)
                changed = true
            }
            usedAccents[book.profiles[i].accent, default: 0] += 1
        }
        if changed { save() }
    }

    func leastUsedAccent(excluding index: Int? = nil) -> Int {
        var counts = [Int](repeating: 0, count: Profile.accents)
        for (i, p) in book.profiles.enumerated() where i != index {
            counts[((p.accent % Profile.accents) + Profile.accents) % Profile.accents] += 1
        }
        return counts.enumerated().min { $0.element < $1.element ? true
                                       : $0.element > $1.element ? false
                                       : $0.offset < $1.offset }?.offset ?? 0
    }

    func distinct(_ name: String, excluding id: String? = nil) -> String {
        let taken = Set(book.profiles.filter { $0.id != id }.map(\.name))
        guard taken.contains(name) else { return name }
        var n = 2
        while taken.contains("\(name) \(n)") { n += 1 }
        return "\(name) \(n)"
    }

    mutating func rename(_ id: String, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let i = book.profiles.firstIndex(where: { $0.id == id })
        else { return }
        book.profiles[i].name = distinct(trimmed, excluding: id)
        save()
    }

    mutating func setAccent(_ id: String, to accent: Int) {
        guard let i = book.profiles.firstIndex(where: { $0.id == id }) else { return }
        book.profiles[i].accent = ((accent % Profile.accents) + Profile.accents) % Profile.accents
        save()
    }

    @discardableResult
    mutating func remove(_ id: String) -> Bool {
        guard book.profiles.count > 1,
              let i = book.profiles.firstIndex(where: { $0.id == id }) else { return false }
        try? FileManager.default.removeItem(at: directory(of: id))
        book.profiles.remove(at: i)
        if book.lastUsedID == id { book.lastUsedID = book.profiles.first?.id }
        save()
        return true
    }

    mutating func markUsed(_ id: String) {
        guard let i = book.profiles.firstIndex(where: { $0.id == id }) else { return }
        book.profiles[i].lastUsedAt = Date()
        book.lastUsedID = id
        save()
    }

    func unusedName() -> String {
        let base = L("Student")
        let taken = Set(book.profiles.map(\.name))
        if !taken.contains(base) { return base }
        var n = 2
        while taken.contains("\(base) \(n)") { n += 1 }
        return "\(base) \(n)"
    }

    func save() {
        try? FileManager.default.createDirectory(at: profilesDir, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try? encoder.encode(book).write(to: bookFile, options: .atomic)
    }
}
