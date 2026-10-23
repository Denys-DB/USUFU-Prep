import Foundation

struct DailyPlan: Codable, Equatable {
    var enabled: Bool = false
    var wordsPerDay: Int = 10
    var completedDays: [Date] = []

    static let range: ClosedRange<Int> = 3...30
    static let presets = [5, 10, 15, 20]

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? false
        wordsPerDay = try c.decodeIfPresent(Int.self, forKey: .wordsPerDay) ?? 10
        completedDays = try c.decodeIfPresent([Date].self, forKey: .completedDays) ?? []
    }

    mutating func markComplete(_ day: Date, calendar: Calendar = .current) {
        let start = calendar.startOfDay(for: day)
        guard !completedDays.contains(where: { calendar.isDate($0, inSameDayAs: start) }) else {
            return
        }
        completedDays.append(start)
        completedDays.sort()
        if completedDays.count > 600 { completedDays.removeFirst(completedDays.count - 600) }
    }
}

struct DailySet: Equatable {
    var fresh: [Flashcard] = []
    var due: [Flashcard] = []
    var heldBack: Int = 0
    var remainingInDeck: Int = 0

    var cards: [Flashcard] { due + fresh }
    var total: Int { cards.count }

    func answeredCount(on day: Date, calendar: Calendar = .current) -> Int {
        cards.filter { $0.wasAnswered(on: day, calendar: calendar) }.count
    }

    func isComplete(on day: Date, calendar: Calendar = .current) -> Bool {
        !cards.isEmpty && answeredCount(on: day, calendar: calendar) == cards.count
    }
}

enum DailyPractice {

    static func reviewCeiling(wordsPerDay: Int) -> Int { max(15, wordsPerDay * 3) }

    static func set(for cards: [Flashcard], wordsPerDay: Int,
                    now: Date = Date(), calendar: Calendar = .current) -> DailySet {
        let today = calendar.startOfDay(for: now)
        var out = DailySet()

        let introducedToday = cards.filter { card in
            guard let day = card.introducedOn else { return false }
            return calendar.isDate(day, inSameDayAs: today)
        }
        out.fresh = introducedToday

        let freshIDs = Set(introducedToday.map(\.id))
        out.due = cards.filter { !freshIDs.contains($0.id) && $0.isDue(now: now) }

        let never = cards.filter { $0.introducedOn == nil && $0.isNew }
        out.remainingInDeck = never.count

        let room = max(0, wordsPerDay - out.fresh.count)
        if room > 0, out.due.count >= reviewCeiling(wordsPerDay: wordsPerDay) {
            out.heldBack = min(room, never.count)
        }
        return out
    }

    static func toIntroduce(from cards: [Flashcard], wordsPerDay: Int,
                            now: Date = Date(), calendar: Calendar = .current) -> [UUID] {
        let today = set(for: cards, wordsPerDay: wordsPerDay, now: now, calendar: calendar)
        guard today.heldBack == 0 else { return [] }
        let room = max(0, wordsPerDay - today.fresh.count)
        guard room > 0 else { return [] }
        return cards.filter { $0.introducedOn == nil && $0.isNew }
            .prefix(room)
            .map(\.id)
    }

    struct Streak: Equatable {
        var current: Int = 0
        var best: Int = 0
        var atRisk: Bool = false
        var doneToday: Bool = false
    }

    static func streak(_ days: [Date], now: Date = Date(),
                       calendar: Calendar = .current) -> Streak {
        var out = Streak()
        let today = calendar.startOfDay(for: now)
        let starts = Set(days.map { calendar.startOfDay(for: $0) })
        guard !starts.isEmpty else {
            out.atRisk = true
            return out
        }

        out.doneToday = starts.contains(today)
        out.atRisk = !out.doneToday

        var cursor = out.doneToday ? today
            : calendar.date(byAdding: .day, value: -1, to: today) ?? today
        var run = 0
        while starts.contains(cursor) {
            run += 1
            guard let previous = calendar.date(byAdding: .day, value: -1, to: cursor) else { break }
            cursor = previous
        }
        out.current = run

        var best = 0, length = 0
        var previous: Date? = nil
        for day in starts.sorted() {
            if let previous, let next = calendar.date(byAdding: .day, value: 1, to: previous),
               calendar.isDate(next, inSameDayAs: day) {
                length += 1
            } else {
                length = 1
            }
            best = max(best, length)
            previous = day
        }
        out.best = max(best, out.current)
        return out
    }
}

struct DeckStatistics: Equatable {
    var total = 0
    var withDefinition = 0
    var withoutDefinition = 0

    var new = 0
    var learning = 0
    var known = 0

    var answered = 0
    var correct = 0
    var starred = 0
    var skipped = 0

    var dueToday = 0
    var dueThisWeek = 0

    var accuracy: Double? { answered > 0 ? Double(correct) / Double(answered) : nil }

    var knownFraction: Double {
        withDefinition > 0 ? Double(known) / Double(withDefinition) : 0
    }

    static func of(_ cards: [Flashcard], now: Date = Date(),
                   calendar: Calendar = .current) -> DeckStatistics {
        var out = DeckStatistics()
        out.total = cards.count
        let weekAway = now.addingTimeInterval(7 * 24 * 60 * 60)
        for card in cards {
            if card.hasDefinition { out.withDefinition += 1 } else { out.withoutDefinition += 1 }
            if card.starred { out.starred += 1 }
            if card.timesGlanced > 0 { out.skipped += 1 }
            out.answered += card.timesSeen
            out.correct += card.timesCorrect

            if card.timesSeen == 0 {
                out.new += 1
            } else if card.lastAnswerCorrect && card.timesCorrect >= 4 {
                out.known += 1
            } else {
                out.learning += 1
            }

            if card.isDue(now: now) { out.dueToday += 1 }
            else if card.isDue(now: weekAway) { out.dueThisWeek += 1 }
        }
        return out
    }

    enum ActivityRange: String, CaseIterable, Identifiable {
        case week, month, quarter, year
        var id: String { rawValue }

        var weeks: Int {
            switch self {
            case .week: return 1
            case .month: return 5
            case .quarter: return 13
            case .year: return 53
            }
        }

        var title: String {
            switch self {
            case .week: return L("Week")
            case .month: return L("Month")
            case .quarter: return L("3 months")
            case .year: return L("Year")
            }
        }

        var maximumSquare: CGFloat {
            switch self {
            case .week: return 38
            case .month: return 30
            case .quarter: return 19
            case .year: return 12
            }
        }
    }

    static func recentDays(_ completed: [Date], weeks: Int = 8,
                           now: Date = Date(), calendar: Calendar = .current) -> [(Date, Bool)] {
        let today = calendar.startOfDay(for: now)
        let marks = Set(completed.map { calendar.startOfDay(for: $0) })
        return (0..<(weeks * 7)).reversed().compactMap { back in
            guard let day = calendar.date(byAdding: .day, value: -back, to: today) else {
                return nil
            }
            return (day, marks.contains(day))
        }
    }
}

extension AppStore {

    var dailyPlan: DailyPlan { settings.vocabDaily }

    func dailySet(for deck: Deck, now: Date = Date()) -> DailySet {
        DailyPractice.set(for: deck.cards, wordsPerDay: settings.vocabDaily.wordsPerDay,
                          now: now)
    }

    @discardableResult
    func dealDaily(in deckID: UUID, now: Date = Date()) -> DailySet {
        guard let existing = deck(deckID) else { return DailySet() }
        let wanted = DailyPractice.toIntroduce(from: existing.cards,
                                               wordsPerDay: settings.vocabDaily.wordsPerDay,
                                               now: now)
        if !wanted.isEmpty {
            let stamp = Calendar.current.startOfDay(for: now)
            updateDeck(deckID) { deck in
                for i in deck.cards.indices where wanted.contains(deck.cards[i].id) {
                    deck.cards[i].introducedOn = stamp
                }
            }
        }
        let set = dailySet(for: deck(deckID) ?? existing, now: now)
        recordDailyIfComplete(set, now: now)
        return set
    }

    func recordDailyIfComplete(_ set: DailySet, now: Date = Date()) {
        guard set.isComplete(on: now) else { return }
        var plan = settings.vocabDaily
        plan.markComplete(now)
        guard plan != settings.vocabDaily else { return }
        settings.vocabDaily = plan
    }

    func noteDailyProgress(in deckID: UUID, now: Date = Date()) {
        guard settings.vocabDaily.enabled, let deck = deck(deckID) else { return }
        recordDailyIfComplete(dailySet(for: deck, now: now), now: now)
    }

    func deckStatistics(_ deck: Deck, now: Date = Date()) -> DeckStatistics {
        DeckStatistics.of(deck.cards, now: now)
    }

    func clearTodaysDeal(in deckID: UUID, now: Date = Date()) {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: now)
        updateDeck(deckID) { deck in
            for i in deck.cards.indices {
                guard let day = deck.cards[i].introducedOn,
                      calendar.isDate(day, inSameDayAs: today) else { continue }
                deck.cards[i].introducedOn = nil
            }
        }
    }

    func clearDailyHistory() {
        var plan = settings.vocabDaily
        plan.completedDays = []
        settings.vocabDaily = plan
    }

    func clearAllVocabularyProgress(in deckID: UUID) {
        clearDailyHistory()
        updateDeck(deckID) { deck in
            for i in deck.cards.indices {
                deck.cards[i].introducedOn = nil
                deck.cards[i].timesSeen = 0
                deck.cards[i].timesCorrect = 0
                deck.cards[i].timesTurned = 0
                deck.cards[i].timesGlanced = 0
                deck.cards[i].lastAnswerCorrect = false
                deck.cards[i].lastSeen = nil
            }
        }
    }

    func dailyStreak(now: Date = Date()) -> DailyPractice.Streak {
        DailyPractice.streak(settings.vocabDaily.completedDays, now: now)
    }
}
