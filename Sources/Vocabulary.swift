import Foundation

struct Flashcard: Codable, Identifiable, Hashable {
    var id: UUID = UUID()
    var term: String
    var definition: String = ""
    var example: String = ""
    var hint: String = ""
    var starred: Bool = false

    var sourceQuestionID: String = ""
    var sourceBankID: String = ""
    var sourceBankName: String = ""

    var createdAt: Date = Date()

    var timesSeen: Int = 0
    var timesCorrect: Int = 0
    var lastSeen: Date? = nil

    var timesTurned: Int = 0
    var timesGlanced: Int = 0
    var lastAnswerCorrect: Bool = false
    var introducedOn: Date? = nil

    init(term: String, definition: String = "", example: String = "",
         hint: String = "", starred: Bool = false,
         sourceQuestionID: String = "", sourceBankID: String = "",
         sourceBankName: String = "") {
        self.term = term
        self.definition = definition
        self.example = example
        self.hint = hint
        self.starred = starred
        self.sourceQuestionID = sourceQuestionID
        self.sourceBankID = sourceBankID
        self.sourceBankName = sourceBankName
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        term = try c.decodeIfPresent(String.self, forKey: .term) ?? ""
        definition = try c.decodeIfPresent(String.self, forKey: .definition) ?? ""
        example = try c.decodeIfPresent(String.self, forKey: .example) ?? ""
        hint = try c.decodeIfPresent(String.self, forKey: .hint) ?? ""
        starred = try c.decodeIfPresent(Bool.self, forKey: .starred) ?? false
        sourceQuestionID = try c.decodeIfPresent(String.self, forKey: .sourceQuestionID) ?? ""
        sourceBankID = try c.decodeIfPresent(String.self, forKey: .sourceBankID) ?? ""
        sourceBankName = try c.decodeIfPresent(String.self, forKey: .sourceBankName) ?? ""
        createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        timesSeen = try c.decodeIfPresent(Int.self, forKey: .timesSeen) ?? 0
        timesCorrect = try c.decodeIfPresent(Int.self, forKey: .timesCorrect) ?? 0
        lastSeen = try c.decodeIfPresent(Date.self, forKey: .lastSeen)
        timesTurned = try c.decodeIfPresent(Int.self, forKey: .timesTurned) ?? 0
        timesGlanced = try c.decodeIfPresent(Int.self, forKey: .timesGlanced) ?? 0
        lastAnswerCorrect = try c.decodeIfPresent(Bool.self, forKey: .lastAnswerCorrect) ?? false
        introducedOn = try c.decodeIfPresent(Date.self, forKey: .introducedOn)
    }

    var hasDefinition: Bool {
        !definition.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var backText: String {
        hasDefinition ? definition : L("No definition yet — open Cards to write one.")
    }

    var accuracy: Double? {
        timesSeen > 0 ? Double(timesCorrect) / Double(timesSeen) : nil
    }

    var isTrouble: Bool {
        timesSeen >= 1 && lastAnswerCorrect == false && timesCorrect * 2 <= timesSeen
    }

    var isSkimmed: Bool { timesGlanced >= 1 && timesTurned == 0 }

    func isDue(now: Date = Date()) -> Bool {
        ReviewSchedule.isDue(timesSeen: timesSeen, timesCorrect: timesCorrect,
                             lastSeen: lastSeen, lastCorrect: lastAnswerCorrect, now: now)
    }

    var isNew: Bool { timesSeen == 0 && timesTurned == 0 }

    func wasAnswered(on day: Date, calendar: Calendar = .current) -> Bool {
        guard let lastSeen else { return false }
        return calendar.isDate(lastSeen, inSameDayAs: day)
    }

    var recordLine: String {
        var parts = [String]()
        if timesSeen > 0 { parts.append(Lf("right %1$d of %2$d", timesCorrect, timesSeen)) }
        if timesTurned > 0 { parts.append(Lf("turned over %d×", timesTurned)) }
        if timesGlanced > 0 { parts.append(Lf("skipped %d×", timesGlanced)) }
        return parts.joined(separator: " · ")
    }
}

enum CardSort: String, Codable, CaseIterable, Identifiable {
    case deckOrder
    case definitionsMissing
    case alphabetical
    case hardestFirst
    case skippedMost
    case newestFirst

    var id: String { rawValue }

    var title: String {
        switch self {
        case .deckOrder: return L("The order they were added")
        case .definitionsMissing: return L("Without a definition first")
        case .alphabetical: return L("A to Z")
        case .hardestFirst: return L("Worst answered first")
        case .skippedMost: return L("Skipped most first")
        case .newestFirst: return L("Newest first")
        }
    }

    func apply(_ cards: [Flashcard]) -> [Flashcard] {
        func byTerm(_ a: Flashcard, _ b: Flashcard) -> Bool {
            Vocabulary.key(a.term) < Vocabulary.key(b.term)
        }
        switch self {
        case .deckOrder:
            return cards
        case .definitionsMissing:
            return cards.sorted {
                $0.hasDefinition == $1.hasDefinition
                    ? byTerm($0, $1) : (!$0.hasDefinition && $1.hasDefinition)
            }
        case .alphabetical:
            return cards.sorted(by: byTerm)
        case .hardestFirst:
            return cards.sorted {
                let a = $0.accuracy ?? 2, b = $1.accuracy ?? 2
                return a == b ? byTerm($0, $1) : a < b
            }
        case .skippedMost:
            return cards.sorted {
                $0.timesGlanced == $1.timesGlanced
                    ? byTerm($0, $1) : $0.timesGlanced > $1.timesGlanced
            }
        case .newestFirst:
            return cards.sorted {
                $0.createdAt == $1.createdAt
                    ? byTerm($0, $1) : $0.createdAt > $1.createdAt
            }
        }
    }
}

enum Hint {
    static let blank = "____"

    static func text(for card: Flashcard) -> String {
        let own = Markup.plain(card.hint).trimmingCharacters(in: .whitespacesAndNewlines)
        if !own.isEmpty { return own }
        return half(of: Markup.plain(card.definition))
    }

    static func half(of definition: String) -> String {
        let trimmed = definition.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        let words = trimmed.split(separator: " ", omittingEmptySubsequences: true)
        if words.count == 1 {
            let letters = Array(trimmed)
            let keep = max(1, min(letters.count - 1, (letters.count + 1) / 2))
            return String(letters.prefix(keep)) + blank
        }
        let keep = max(1, (words.count + 1) / 2)
        return words.prefix(keep).joined(separator: " ") + " " + blank
    }
}

struct Deck: Codable, Identifiable, Hashable {
    var id: UUID = UUID()
    var name: String
    var createdAt: Date = Date()
    var cards: [Flashcard] = []

    init(name: String, cards: [Flashcard] = []) {
        self.name = name
        self.cards = cards
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? "Deck"
        createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        cards = try c.decodeIfPresent([Flashcard].self, forKey: .cards) ?? []
    }

    var starredCount: Int { cards.filter(\.starred).count }
    var troubleCount: Int { cards.filter(\.isTrouble).count }
    var undefinedCount: Int { cards.filter { !$0.hasDefinition }.count }

    var metCount: Int { cards.filter { $0.timesSeen > 0 }.count }

    func index(of id: UUID) -> Int? { cards.firstIndex { $0.id == id } }

    func holds(term: String) -> Bool {
        let key = Vocabulary.key(term)
        return cards.contains { Vocabulary.key($0.term) == key }
    }
}

enum CardScope: String, Codable, CaseIterable {
    case all
    case today
    case starred
    case trouble
    case skimmed

    var title: String {
        switch self {
        case .all: return L("All cards")
        case .today: return L("Today")
        case .starred: return L("Starred")
        case .trouble: return L("Words I keep missing")
        case .skimmed: return L("Words I skipped past")
        }
    }

    var detail: String {
        switch self {
        case .all: return L("Everything in this deck.")
        case .today:
            return L("Today's few new words, and everything that has come back round.")
        case .starred:
            return L("Words you starred to come back to on their own. Press the star "
                     + "at the top of a card to put one here.")
        case .trouble:
            return L("You said Missed it, or picked the wrong answer in a test, "
                     + "at least half the times you were asked.")
        case .skimmed:
            return L("Gone past twice or more without ever being turned over.")
        }
    }

    func filter(_ cards: [Flashcard], wordsPerDay: Int = 10) -> [Flashcard] {
        switch self {
        case .all: return cards
        case .today:
            let ids = Set(DailyPractice.set(for: cards, wordsPerDay: wordsPerDay).cards.map(\.id))
            return cards.filter { ids.contains($0.id) }
        case .starred: return cards.filter(\.starred)
        case .trouble: return cards.filter(\.isTrouble)
        case .skimmed: return cards.filter(\.isSkimmed)
        }
    }
}

enum VocabAnswerSide: String, Codable, CaseIterable {
    case definitions
    case terms
    case mixed

    var title: String {
        switch self {
        case .definitions: return L("Definitions")
        case .terms: return L("The words themselves")
        case .mixed: return L("A mix of both")
        }
    }
    var detail: String {
        switch self {
        case .definitions: return L("You are shown the word and pick what it means.")
        case .terms: return L("You are shown the meaning and pick the word.")
        case .mixed: return L("Some questions each way, decided per question.")
        }
    }
}

struct VocabQuestion: Identifiable, Hashable {
    var id = UUID()
    var cardID: UUID
    var asksForDefinition: Bool
    var prompt: String
    var options: [String]
    var answerIndex: Int

    var answer: String { options.indices.contains(answerIndex) ? options[answerIndex] : "" }
}

struct VocabAttempt: Hashable {
    var chosen: Int? = nil
}

enum VocabTest {
    static let minimumCards = 4

    static func build(from cards: [Flashcard], asking: [Flashcard]? = nil,
                      side: VocabAnswerSide, count: Int,
                      using rng: inout some RandomNumberGenerator) -> [VocabQuestion] {
        let usable = cards.filter { !$0.term.trimmed.isEmpty && $0.hasDefinition }
        guard usable.count >= minimumCards else { return [] }

        let subject = asking.map { list in
            list.filter { !$0.term.trimmed.isEmpty && $0.hasDefinition }
        } ?? usable
        guard !subject.isEmpty else { return [] }

        let wanted = max(1, min(count, subject.count))
        let asked = subject.shuffled(using: &rng).prefix(wanted)

        return asked.compactMap { card -> VocabQuestion? in
            let asksForDefinition: Bool
            switch side {
            case .definitions: asksForDefinition = true
            case .terms: asksForDefinition = false
            case .mixed: asksForDefinition = Bool.random(using: &rng)
            }

            let face: (Flashcard) -> String = asksForDefinition
                ? { Markup.plain($0.definition).trimmed } : { Markup.plain($0.term).trimmed }
            let back: (Flashcard) -> String = asksForDefinition
                ? { Markup.plain($0.term).trimmed } : { Markup.plain($0.definition).trimmed }

            let correct = face(card)
            guard !correct.isEmpty else { return nil }

            var used: Set<String> = [Vocabulary.key(correct)]
            var options = [correct]
            for other in usable.shuffled(using: &rng) where options.count < 4 {
                guard other.id != card.id else { continue }
                let text = face(other)
                guard !text.isEmpty, used.insert(Vocabulary.key(text)).inserted else { continue }
                options.append(text)
            }
            guard options.count == 4 else { return nil }

            options.shuffle(using: &rng)
            guard let answerIndex = options.firstIndex(of: correct) else { return nil }
            return VocabQuestion(cardID: card.id,
                                 asksForDefinition: asksForDefinition,
                                 prompt: back(card),
                                 options: options,
                                 answerIndex: answerIndex)
        }
    }

    static func availableCount(in cards: [Flashcard]) -> Int {
        let usable = cards.filter { !$0.term.trimmed.isEmpty && $0.hasDefinition }
        return usable.count >= minimumCards ? usable.count : 0
    }
}

enum Vocabulary {
    static func key(_ text: String) -> String {
        Markup.plain(text).lowercased()
            .trimmingCharacters(in: CharacterSet.whitespacesAndNewlines
                .union(CharacterSet(charactersIn: ".,;:\"'“”‘’()")))
            .split(separator: " ", omittingEmptySubsequences: true)
            .joined(separator: " ")
    }
}
