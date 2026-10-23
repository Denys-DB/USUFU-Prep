import Foundation

extension AppStore {

    func loadDecks() {
        let files = (try? FileManager.default.contentsOfDirectory(
            at: decksDir, includingPropertiesForKeys: nil)) ?? []
        decks = files
            .filter { $0.pathExtension == "json" }
            .compactMap { url -> Deck? in
                DamagedFile.load(Deck.self, from: url, damaged: noteDamaged)
            }
            .sorted { $0.createdAt < $1.createdAt }
    }

    private func deckFile(_ id: UUID) -> URL {
        decksDir.appendingPathComponent("\(id.uuidString).json")
    }

    func saveDeck(_ deck: Deck) {
        try? FileManager.default.createDirectory(at: decksDir, withIntermediateDirectories: true)
        guard let data = try? JSONEncoder().encode(deck) else { return }
        try? data.write(to: deckFile(deck.id), options: .atomic)
    }

    func deck(_ id: UUID?) -> Deck? {
        guard let id else { return nil }
        return decks.first { $0.id == id }
    }

    var selectedDeck: Deck? { deck(selectedDeckID) }

    @discardableResult
    func addDeck(named name: String? = nil, cards: [Flashcard] = []) -> Deck {
        let trimmed = (name ?? "").trimmed
        let deck = Deck(name: trimmed.isEmpty ? defaultDeckName() : trimmed, cards: cards)
        decks.append(deck)
        saveDeck(deck)
        selectedDeckID = deck.id
        return deck
    }

    private func defaultDeckName() -> String {
        let base = L("Vocabulary")
        guard decks.contains(where: { $0.name == base }) else { return base }
        var n = 2
        while decks.contains(where: { $0.name == "\(base) \(n)" }) { n += 1 }
        return "\(base) \(n)"
    }

    func renameDeck(_ id: UUID, to name: String) {
        let trimmed = name.trimmed
        guard !trimmed.isEmpty, let i = decks.firstIndex(where: { $0.id == id }) else { return }
        decks[i].name = trimmed
        saveDeck(decks[i])
    }

    @discardableResult
    func renameSourceBank(id bankID: String, to name: String) -> Int {
        guard !bankID.isEmpty else { return 0 }
        var changed = 0
        for i in decks.indices {
            var touched = false
            for c in decks[i].cards.indices
            where decks[i].cards[c].sourceBankID == bankID
                && decks[i].cards[c].sourceBankName != name {
                decks[i].cards[c].sourceBankName = name
                touched = true
                changed += 1
            }
            if touched { saveDeck(decks[i]) }
        }
        return changed
    }

    func deleteDeck(_ id: UUID) {
        decks.removeAll { $0.id == id }
        try? FileManager.default.removeItem(at: deckFile(id))
        clearDeckSession(id)
        if selectedDeckID == id { selectedDeckID = decks.first?.id }
    }

    func updateDeck(_ id: UUID, _ change: (inout Deck) -> Void) {
        guard let i = decks.firstIndex(where: { $0.id == id }) else { return }
        change(&decks[i])
        saveDeck(decks[i])
    }

    @discardableResult
    func addCard(_ card: Flashcard, to deckID: UUID) -> Bool {
        guard let i = decks.firstIndex(where: { $0.id == deckID }) else { return false }
        guard !card.term.trimmed.isEmpty, !decks[i].holds(term: card.term) else { return false }
        decks[i].cards.append(card)
        saveDeck(decks[i])
        return true
    }

    @discardableResult
    func addCards(_ cards: [Flashcard], to deckID: UUID) -> Int {
        guard let i = decks.firstIndex(where: { $0.id == deckID }) else { return 0 }
        var added = 0
        for card in cards {
            guard !card.term.trimmed.isEmpty, !decks[i].holds(term: card.term) else { continue }
            decks[i].cards.append(card)
            added += 1
        }
        if added > 0 { saveDeck(decks[i]) }
        return added
    }

    func updateCard(_ card: Flashcard, in deckID: UUID) {
        updateDeck(deckID) { deck in
            guard let i = deck.index(of: card.id) else { return }
            deck.cards[i] = card
        }
    }

    func deleteCard(_ cardID: UUID, from deckID: UUID) {
        updateDeck(deckID) { $0.cards.removeAll { $0.id == cardID } }
    }

    func deleteCards(_ cardIDs: Set<UUID>, from deckID: UUID) {
        guard !cardIDs.isEmpty else { return }
        updateDeck(deckID) { $0.cards.removeAll { cardIDs.contains($0.id) } }
    }

    func setStarred(_ starred: Bool, on cardIDs: Set<UUID>, in deckID: UUID) {
        guard !cardIDs.isEmpty else { return }
        updateDeck(deckID) { deck in
            for i in deck.cards.indices where cardIDs.contains(deck.cards[i].id) {
                deck.cards[i].starred = starred
            }
        }
    }

    func toggleStar(_ cardID: UUID, in deckID: UUID) {
        updateDeck(deckID) { deck in
            guard let i = deck.index(of: cardID) else { return }
            deck.cards[i].starred.toggle()
        }
    }

    func recordSelfGrade(_ cardID: UUID, correct: Bool, in deckID: UUID) {
        recordTest([cardID: correct], in: deckID)
    }

    func recordTurn(_ cardID: UUID, in deckID: UUID) {
        updateDeck(deckID) { deck in
            guard let i = deck.index(of: cardID) else { return }
            deck.cards[i].timesTurned += 1
        }
    }

    func recordSkip(_ cardID: UUID, in deckID: UUID) {
        updateDeck(deckID) { deck in
            guard let i = deck.index(of: cardID) else { return }
            deck.cards[i].timesGlanced += 1
        }
    }

    func recordTest(_ results: [UUID: Bool], in deckID: UUID) {
        guard !results.isEmpty else { return }
        updateDeck(deckID) { deck in
            let now = Date()
            for (cardID, correct) in results {
                guard let i = deck.index(of: cardID) else { continue }
                deck.cards[i].timesSeen += 1
                if correct { deck.cards[i].timesCorrect += 1 }
                deck.cards[i].lastAnswerCorrect = correct
                deck.cards[i].lastSeen = now
            }
        }
    }

    func mineVocabulary(from bank: Bank) async -> [MinedCard] {
        await Task.detached(priority: .userInitiated) {
            VocabularyMiner.mine(bank)
        }.value
    }

    func card(from mined: MinedCard, bank: Bank) -> Flashcard {
        Flashcard(term: mined.term,
                  definition: mined.definition,
                  example: mined.example,
                  sourceQuestionID: mined.questionID,
                  sourceBankID: bank.id,
                  sourceBankName: bank.name)
    }
}
