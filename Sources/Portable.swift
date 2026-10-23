import Foundation

struct PortableProfile: Codable {

    static let magic = "usufu-sat-profile"
    static let currentVersion = 1
    static let fileExtension = "satprofile"

    var format: String = PortableProfile.magic
    var version: Int = PortableProfile.currentVersion
    var exportedAt: Date = Date()
    var profileName: String = ""
    var accent: Int = 0

    var banks: [BankBlock] = []
    var decks: [Deck] = []
    var plans: [StudyPreset] = []
    var settings: AppSettings? = nil

    struct BankBlock: Codable {
        var name: String = ""
        var questionCount: Int = 0
        var fingerprint: String = ""
        var questionIDs: [String] = []

        var records: [String: QuestionProgress] = [:]
        var setAside: [String] = []
        var history: [AttemptRecord] = []
        var notes: [Annotation] = []

        init() {}

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
            questionCount = try c.decodeIfPresent(Int.self, forKey: .questionCount) ?? 0
            fingerprint = try c.decodeIfPresent(String.self, forKey: .fingerprint) ?? ""
            questionIDs = try c.decodeIfPresent([String].self, forKey: .questionIDs) ?? []
            records = try c.decodeIfPresent([String: QuestionProgress].self,
                                            forKey: .records) ?? [:]
            setAside = try c.decodeIfPresent([String].self, forKey: .setAside) ?? []
            history = try c.decodeIfPresent([AttemptRecord].self, forKey: .history) ?? []
            notes = try c.decodeIfPresent([Annotation].self, forKey: .notes) ?? []
        }
    }

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        format = try c.decodeIfPresent(String.self, forKey: .format) ?? ""
        version = try c.decodeIfPresent(Int.self, forKey: .version) ?? 0
        exportedAt = try c.decodeIfPresent(Date.self, forKey: .exportedAt) ?? Date()
        profileName = try c.decodeIfPresent(String.self, forKey: .profileName) ?? ""
        accent = try c.decodeIfPresent(Int.self, forKey: .accent) ?? 0
        banks = try c.decodeIfPresent([BankBlock].self, forKey: .banks) ?? []
        decks = try c.decodeIfPresent([Deck].self, forKey: .decks) ?? []
        plans = try c.decodeIfPresent([StudyPreset].self, forKey: .plans) ?? []
        settings = try c.decodeIfPresent(AppSettings.self, forKey: .settings)
    }

    var isRecognised: Bool { format == Self.magic }

    static func encoder() -> JSONEncoder {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .secondsSince1970
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return e
    }

    static func decoder() -> JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .secondsSince1970
        return d
    }
}

enum BankFingerprint {

    static func of(_ questionIDs: [String]) -> String {
        var hash: UInt64 = 0xcbf29ce484222325
        for id in questionIDs.sorted() {
            for byte in id.utf8 {
                hash ^= UInt64(byte)
                hash = hash &* 0x100000001b3
            }
            hash ^= 0x2f
            hash = hash &* 0x100000001b3
        }
        return String(format: "%016llx", hash)
    }
}

struct ImportPlan {
    var profileName: String = ""
    var exportedAt: Date = Date()
    var matches: [Match] = []
    var deckCount: Int = 0
    var planCount: Int = 0

    struct Match: Identifiable {
        var id: String { exportedName + "→" + (localBankID ?? "") }
        var exportedName: String
        var exportedCount: Int
        var localBankID: String?
        var localName: String?
        var overlap: Int
        var records: Int
        var notes: Int
        var how: How

        enum How { case fingerprint, name, overlap, none }
    }

    var lands: Bool {
        matches.contains { $0.localBankID != nil } || deckCount > 0 || planCount > 0
    }
}

enum PortableMatcher {

    static func plan(for file: PortableProfile, banks: [Bank]) -> ImportPlan {
        var plan = ImportPlan(profileName: file.profileName, exportedAt: file.exportedAt,
                              deckCount: file.decks.count, planCount: file.plans.count)
        let localIDs = banks.map { (bank: $0, ids: Set($0.questions.map(\.id))) }
        var claimed = Set<String>()

        for block in file.banks {
            let exported = Set(block.questionIDs)
            var chosen: (Bank, Int, ImportPlan.Match.How)?

            if let hit = localIDs.first(where: {
                !claimed.contains($0.bank.id)
                    && BankFingerprint.of(Array($0.ids)) == block.fingerprint
            }) {
                chosen = (hit.bank, hit.ids.intersection(exported).count, .fingerprint)
            } else if let hit = localIDs.first(where: {
                !claimed.contains($0.bank.id) && $0.bank.name == block.name
            }) {
                chosen = (hit.bank, hit.ids.intersection(exported).count, .name)
            } else {
                let best = localIDs
                    .filter { !claimed.contains($0.bank.id) }
                    .map { ($0.bank, $0.ids.intersection(exported).count) }
                    .max { $0.1 < $1.1 }
                if let best, best.1 * 4 >= max(1, exported.count) {
                    chosen = (best.0, best.1, .overlap)
                }
            }

            if let chosen { claimed.insert(chosen.0.id) }
            plan.matches.append(.init(
                exportedName: block.name,
                exportedCount: block.questionCount,
                localBankID: chosen?.0.id,
                localName: chosen?.0.name,
                overlap: chosen?.1 ?? 0,
                records: block.records.count,
                notes: block.notes.count,
                how: chosen?.2 ?? .none))
        }
        return plan
    }
}

enum ProgressMerge {

    static func better(_ a: QuestionProgress, _ b: QuestionProgress) -> QuestionProgress {
        if a.timesSeen != b.timesSeen { return a.timesSeen > b.timesSeen ? a : b }
        if a.timesCorrect != b.timesCorrect { return a.timesCorrect > b.timesCorrect ? a : b }
        let aSeen = a.lastSeen ?? .distantPast
        let bSeen = b.lastSeen ?? .distantPast
        return aSeen >= bSeen ? a : b
    }

    static func merge(into existing: inout BankProgress, from block: PortableProfile.BankBlock,
                      keeping known: Set<String>) {
        for (id, incoming) in block.records where known.contains(id) {
            if let mine = existing.records[id] {
                existing.records[id] = better(mine, incoming)
            } else {
                existing.records[id] = incoming
            }
        }
        existing.setAside.formUnion(block.setAside.filter { known.contains($0) })

        var seen = Set(existing.history.map { "\($0.questionID)@\($0.at.timeIntervalSince1970)" })
        for row in block.history where known.contains(row.questionID) {
            let key = "\(row.questionID)@\(row.at.timeIntervalSince1970)"
            guard seen.insert(key).inserted else { continue }
            existing.history.append(row)
        }
        existing.history.sort { $0.at < $1.at }
    }

    static func merge(notes existing: inout [Annotation], from incoming: [Annotation],
                      keeping known: Set<String>) {
        var have = Set(existing.map(\.id))
        for note in incoming where known.contains(note.questionID) {
            guard have.insert(note.id).inserted else { continue }
            existing.append(note)
        }
    }
}
