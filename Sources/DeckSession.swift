import Foundation

struct VocabSitting: Equatable {
    var side: VocabAnswerSide
    var scope: CardScope
    var questions: [VocabQuestion]
    var attempts: [VocabAttempt]
    var index: Int = 0
    var finished: Bool = false
    var secondsRemaining: Double? = nil

    var answeredCount: Int { attempts.filter { $0.chosen != nil }.count }

    var correctCount: Int {
        zip(questions, attempts).filter { $0.1.chosen == $0.0.answerIndex }.count
    }

    var missedCardIDs: [UUID] {
        zip(questions, attempts).filter { $0.1.chosen != $0.0.answerIndex }.map(\.0.cardID)
    }
}

struct DeckSession: Equatable {

    var scope: CardScope = .all
    var shuffled: Bool = false
    var order: [UUID] = []
    var deckCards: Set<UUID> = []
    var position: Int = 0
    var showingBack: Bool = false
    var turned: Bool = false

    var testSide: VocabAnswerSide = .definitions
    var testScope: CardScope = .all
    var testCount: Int = 20
    var testMinutes: Int? = nil
    var sitting: VocabSitting? = nil

    var sort: CardSort = .deckOrder
}

extension AppStore {

    func deckSession(_ id: UUID) -> DeckSession { deckSessions[id] ?? DeckSession() }

    func updateDeckSession(_ id: UUID, _ change: (inout DeckSession) -> Void) {
        var next = deckSessions[id] ?? DeckSession()
        change(&next)
        deckSessions[id] = next
    }

    func clearDeckSession(_ id: UUID) { deckSessions[id] = nil }
}

enum DeckFocus: Equatable {
    case cards(UUID)
    case test(UUID)

    var deckID: UUID {
        switch self {
        case .cards(let id), .test(let id): return id
        }
    }
}

extension DeckSession {
    func reconciled(deck cards: [UUID], pool: [UUID]) -> DeckSession {
        var next = self
        let alive = Set(cards)
        let here = position < order.count ? order[position] : nil
        var kept = order.filter { alive.contains($0) }
        let have = Set(kept)
        var arrived = [UUID]()
        for id in pool where !deckCards.contains(id) && !have.contains(id) { arrived.append(id) }
        kept += shuffled ? arrived.shuffled() : arrived
        next.order = kept
        next.deckCards = alive
        if let here, let at = kept.firstIndex(of: here) {
            next.position = at
        } else {
            next.position = min(position, max(0, kept.count - 1))
            next.showingBack = false
        }
        return next
    }
}
