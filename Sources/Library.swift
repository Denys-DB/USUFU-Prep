import Foundation

struct Shelf: Codable, Identifiable, Hashable {
    var id: UUID = UUID()
    var name: String
    var bankIDs: [String] = []
    var collapsed: Bool = false

    init(name: String, bankIDs: [String] = []) {
        self.name = name
        self.bankIDs = bankIDs
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? "Shelf"
        bankIDs = try c.decodeIfPresent([String].self, forKey: .bankIDs) ?? []
        collapsed = try c.decodeIfPresent(Bool.self, forKey: .collapsed) ?? false
    }
}

enum ShelfOrder: String, Codable, CaseIterable {
    case manual
    case name
    case newest
    case largest
    case leastPractised

    var title: String {
        switch self {
        case .manual: return L("The order I put them in")
        case .name: return L("Name, A to Z")
        case .newest: return L("Newest first")
        case .largest: return L("Most questions first")
        case .leastPractised: return L("Least practiced first")
        }
    }
    var symbol: String {
        switch self {
        case .manual: return "hand.draw"
        case .name: return "textformat.abc"
        case .newest: return "clock"
        case .largest: return "number"
        case .leastPractised: return "chart.bar"
        }
    }
    var isManual: Bool { self == .manual }
}

struct LibraryLayout: Codable, Equatable {
    var shelves: [Shelf] = []
    var unshelved: [String] = []
    var order: ShelfOrder = .manual

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        shelves = try c.decodeIfPresent([Shelf].self, forKey: .shelves) ?? []
        unshelved = try c.decodeIfPresent([String].self, forKey: .unshelved) ?? []
        order = (try? c.decodeIfPresent(ShelfOrder.self, forKey: .order))
            .flatMap { $0 } ?? .manual
    }

    static func == (a: LibraryLayout, b: LibraryLayout) -> Bool {
        a.shelves == b.shelves && a.unshelved == b.unshelved && a.order == b.order
    }

    mutating func reconcile(with banks: [Bank]) {
        let known = Set(banks.map(\.id))
        var placed = Set<String>()

        for index in shelves.indices {
            shelves[index].bankIDs = shelves[index].bankIDs.filter {
                known.contains($0) && placed.insert($0).inserted
            }
        }
        unshelved = unshelved.filter { known.contains($0) && placed.insert($0).inserted }

        let missing = banks.map(\.id).filter { !placed.contains($0) }
        unshelved.insert(contentsOf: missing, at: 0)
    }

    func shelf(of bankID: String) -> Shelf? {
        shelves.first { $0.bankIDs.contains(bankID) }
    }

    mutating func remove(_ bankID: String) {
        for index in shelves.indices { shelves[index].bankIDs.removeAll { $0 == bankID } }
        unshelved.removeAll { $0 == bankID }
    }

    mutating func move(_ bankID: String, to shelfID: UUID?, at position: Int? = nil) {
        remove(bankID)
        if let shelfID, let index = shelves.firstIndex(where: { $0.id == shelfID }) {
            let at = min(max(0, position ?? shelves[index].bankIDs.count),
                         shelves[index].bankIDs.count)
            shelves[index].bankIDs.insert(bankID, at: at)
        } else {
            let at = min(max(0, position ?? unshelved.count), unshelved.count)
            unshelved.insert(bankID, at: at)
        }
    }

    mutating func addShelf(named name: String) -> Shelf {
        let shelf = Shelf(name: name)
        shelves.append(shelf)
        return shelf
    }

    mutating func removeShelf(_ shelfID: UUID) {
        guard let index = shelves.firstIndex(where: { $0.id == shelfID }) else { return }
        unshelved.append(contentsOf: shelves[index].bankIDs)
        shelves.remove(at: index)
    }

    mutating func moveShelf(_ shelfID: UUID, by delta: Int) {
        guard let index = shelves.firstIndex(where: { $0.id == shelfID }) else { return }
        let target = min(max(0, index + delta), shelves.count - 1)
        guard target != index else { return }
        let shelf = shelves.remove(at: index)
        shelves.insert(shelf, at: target)
    }

    func freshShelfName(_ base: String = L("New shelf")) -> String {
        let taken = Set(shelves.map { $0.name.lowercased() })
        guard taken.contains(base.lowercased()) else { return base }
        for n in 2...99 where !taken.contains("\(base) \(n)".lowercased()) {
            return "\(base) \(n)"
        }
        return base
    }
}

enum ShelfSorter {
    static func arrange(_ ids: [String], order: ShelfOrder, banks: [String: Bank],
                        progress: [String: BankProgress]) -> [Bank] {
        let resolved = ids.compactMap { banks[$0] }
        switch order {
        case .manual:
            return resolved
        case .name:
            return resolved.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        case .newest:
            return resolved.sorted { $0.createdAt > $1.createdAt }
        case .largest:
            return resolved.sorted { $0.questions.count > $1.questions.count }
        case .leastPractised:
            func fraction(_ bank: Bank) -> Double {
                guard !bank.questions.isEmpty else { return 1 }
                let seen = progress[bank.id]?.seenCount ?? 0
                return Double(seen) / Double(bank.questions.count)
            }
            return resolved.sorted {
                let (a, b) = (fraction($0), fraction($1))
                return a == b ? $0.name.localizedStandardCompare($1.name) == .orderedAscending
                              : a < b
            }
        }
    }
}
