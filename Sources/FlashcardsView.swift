import SwiftUI
import Combine

struct DeckView: View {
    @EnvironmentObject var store: AppStore
    let deck: Deck

    enum Tab: String, CaseIterable {
        case daily, flashcards, test, cards

        var title: String {
            switch self {
            case .daily: return L("Daily/Statistics")
            case .flashcards: return L("Flashcards")
            case .test: return L("Test")
            case .cards: return L("Cards")
            }
        }
        var symbol: String {
            switch self {
            case .daily: return "chart.bar"
            case .flashcards: return "rectangle.on.rectangle"
            case .test: return "doc.text"
            case .cards: return "list.bullet"
            }
        }
    }

    @State private var renaming = false
    @State private var renameText = ""

    var body: some View {
        VStack(spacing: 0) {
            header
            Rule()
            ZStack {
                switch store.deckTab {
                case .daily:
                    DailyPane(deck: deck) {
                        store.updateDeckSession(deck.id) { $0.scope = .today }
                        store.focus = .cards(deck.id)
                    }
                    .transition(.opacity)
                case .flashcards:
                    FlashcardsPane(deck: deck).transition(.opacity)
                case .test:
                    VocabTestPane(deck: deck).transition(.opacity)
                case .cards:
                    CardsPane(deck: deck).transition(.opacity)
                }
            }
            .animation(Motion.standard, value: store.deckTab)
            .id(deck.id)
        }
        .alert(L("Rename deck"), isPresented: $renaming) {
            TextField(L("Name"), text: $renameText)
            Button(L("Cancel"), role: .cancel) { renaming = false }
            Button(L("Save")) { store.renameDeck(deck.id, to: renameText) }
        }
    }

    private var header: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .center, spacing: 14) {
                titleBlock
                Spacer(minLength: 12)
                studyButtons
                tabs
            }
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .center, spacing: 14) {
                    titleBlock
                    Spacer(minLength: 12)
                    studyButtons
                }
                HStack(spacing: 8) {
                    Spacer(minLength: 0)
                    tabs
                }
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 14)
        .background(Palette.card)
    }

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(deck.name)
                .font(Face.display(19))
                .foregroundStyle(Palette.navy)
                .lineLimit(1)
            Text(subtitle)
                .font(Face.ui(11))
                .foregroundStyle(Palette.textMuted)
                .lineLimit(1)
        }
        .onTapGesture(count: 2) { renameText = deck.name; renaming = true }
        .help(L("Double-click to rename this deck"))
    }

    private var studyButtons: some View {
        HStack(spacing: 8) {
            BluebookButton(title: L("Practice with cards"),
                           enabled: !deck.cards.isEmpty, lifts: true) {
                store.focus = .cards(deck.id)
            }
            BluebookButton(title: L("Start the test"), style: .secondary,
                           enabled: VocabTest.availableCount(in: deck.cards)
                               >= VocabTest.minimumCards,
                           lifts: true) {
                store.focus = .test(deck.id)
            }
        }
        .fixedSize(horizontal: true, vertical: false)
    }

    private var tabs: some View {
        HStack(spacing: 8) {
            ForEach(Tab.allCases, id: \.self) { t in
                DeckTabButton(tab: t, selected: store.deckTab == t) {
                    withAnimation(Motion.settle) { store.deckTab = t }
                }
            }
        }
        .fixedSize(horizontal: true, vertical: false)
    }

    private var subtitle: String {
        var parts = [Lp(deck.cards.count, "%d card", "%d cards")]
        if deck.starredCount > 0 { parts.append(Lf("%d starred", deck.starredCount)) }
        if deck.undefinedCount > 0 {
            parts.append(Lf("%d without a definition", deck.undefinedCount))
        }
        return parts.joined(separator: " · ")
    }
}

private struct DeckTabButton: View {
    let tab: DeckView.Tab
    let selected: Bool
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 7) {
                Image(systemName: tab.symbol)
                    .font(.system(size: 12, weight: .medium))
                Text(tab.title)
                    .font(Face.ui(12.5, selected ? .semibold : .regular))
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
            }
            .fixedSize(horizontal: true, vertical: false)
            .foregroundStyle(selected ? Palette.card : Palette.text)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(selected ? Palette.navy
                        : (hovering ? Palette.paperDeep : Palette.subtleFill))
            .overlay(RoundedRectangle(cornerRadius: 4)
                .strokeBorder(selected ? .clear : Palette.hairline, lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 4))
        }
        .buttonStyle(.plain)
        .animation(Motion.quick, value: hovering)
        .onHover { hovering = $0 }
    }
}

struct FlashcardsPane: View {
    @EnvironmentObject var store: AppStore
    let deck: Deck

    @State private var hinting = false
    @State private var autoplaying = false
    @State private var focused = false
    @State private var showingSpeed = false

    private var session: DeckSession { store.deckSession(deck.id) }
    private func edit(_ change: @escaping (inout DeckSession) -> Void) {
        store.updateDeckSession(deck.id, change)
    }

    private var scope: CardScope { session.scope }
    private var order: [UUID] { session.order }
    private var shuffled: Bool { session.shuffled }
    private var position: Int { session.position }
    private var showingBack: Bool { session.showingBack }
    private var showingBackBinding: Binding<Bool> {
        Binding(get: { session.showingBack }, set: { v in edit { $0.showingBack = v } })
    }

    private var pool: [Flashcard] {
        scope.filter(deck.cards, wordsPerDay: store.settings.vocabDaily.wordsPerDay)
    }

    private var card: Flashcard? {
        guard position >= 0, position < order.count else { return nil }
        let id = order[position]
        return deck.cards.first { $0.id == id }
    }

    var body: some View {
        Group {
            if deck.cards.isEmpty {
                EmptyDeckNotice(deck: deck)
            } else if pool.isEmpty {
                emptyScope
            } else {
                deckBody
            }
        }
        .onAppear { if order.isEmpty { rebuild(reset: true) } else { reconcile() } }
        .onChange(of: deck.cards.count) { _ in reconcile() }
        .onChange(of: scope) { _ in rebuild(reset: true) }
    }

    private var deckBody: some View {
        VStack(spacing: 0) {
            scopeBar
            cardFace
                .padding(.horizontal, 26)
                .padding(.top, 6)
            controls
                .padding(.horizontal, 26)
                .padding(.top, 14)
                .padding(.bottom, 20)
        }
        .watchingKeys(handleKey)
        .fullScreenLikeOverlay(isPresented: $focused) {
            FocusedCard(deck: deck, card: card, showingBack: showingBackBinding,
                        hinting: $hinting, position: position, total: order.count,
                        scale: store.settings.flashcardTextScale,
                        animated: store.settings.flashcardFlipAnimation,
                        onFlip: flip, onPrevious: previous, onNext: next,
                        onStar: star, onGrade: grade,
                        onClose: { focused = false })
        }
        .onReceive(ticker) { _ in advanceAutoplay() }
    }

    private var cardFace: some View {
        CardFace(card: card,
                 showingBack: showingBackBinding,
                 hinting: $hinting,
                 starred: card?.starred ?? false,
                 scale: store.settings.flashcardTextScale,
                 animated: store.settings.flashcardFlipAnimation,
                 compact: false,
                 onStar: star,
                 onFlip: flip,
                 onGrade: grade)
    }

    private var scopeBar: some View {
        let all = shownScopes
        let split = (all.count + 1) / 2
        return ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) { scopeChips(all); Spacer(minLength: 0) }
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) { scopeChips(Array(all.prefix(split))); Spacer(minLength: 0) }
                HStack(spacing: 8) { scopeChips(Array(all.dropFirst(split))); Spacer(minLength: 0) }
            }
        }
        .padding(.horizontal, 26)
        .padding(.top, 16)
    }

    @ViewBuilder
    private func scopeChips(_ scopes: [CardScope]) -> some View {
        ForEach(scopes, id: \.self) { s in
            let n = s.filter(deck.cards,
                             wordsPerDay: store.settings.vocabDaily.wordsPerDay).count
            Chip(title: s.title, selected: scope == s, enabled: n > 0 || s == .all,
                 count: n, accent: Palette.brass) {
                edit { $0.scope = s }
                rebuild(reset: true)
            }
            .help(s.detail)
        }
    }

    private var shownScopes: [CardScope] {
        CardScope.allCases.filter { scope in
            switch scope {
            case .skimmed: return store.settings.trackSkippedCards
            case .today: return store.settings.vocabDaily.enabled
            default: return true
            }
        }
    }

    private var emptyScope: some View {
        VStack(spacing: 12) {
            scopeBar
            Spacer()
            Text(emptyScopeMessage)
                .font(Face.ui(12.5))
                .foregroundStyle(Palette.textMuted)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 400)
            BluebookButton(title: L("Show all cards"), style: .secondary, lifts: true) {
                edit { $0.scope = .all }
                rebuild(reset: true)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyScopeMessage: String {
        switch scope {
        case .starred:
            return L("Nothing is starred yet. Press the star on a card to keep it back "
                     + "for later.")
        case .trouble:
            return L("Nothing here yet. This fills up as you press Missed it on a card, "
                     + "or get one wrong in a test.")
        case .skimmed:
            return L("Nothing here yet. This fills up with the words you go past "
                     + "without turning over.")
        case .today:
            return L("Nothing due today, and no new words left in this deck. Add more "
                     + "words, or practice the whole deck.")
        case .all:
            return L("Nothing here yet.")
        }
    }

    private var controls: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) {
                cardTools
                Spacer(minLength: 24)
                counter
            }
            VStack(spacing: 10) {
                HStack(spacing: 12) { cardTools; Spacer(minLength: 0) }
                counter
            }
        }
    }

    private var cardTools: some View {
        HStack(spacing: 10) {
                RoundIcon(symbol: autoplaying ? "pause.fill" : "play.fill",
                          filled: autoplaying,
                          help: autoplaying ? L("Stop autoplay")
                                            : Lf("Play the cards, %d seconds a side",
                                                 Int(store.settings.flashcardSeconds))) {
                    autoplaying.toggle()
                }
                RoundIcon(symbol: "shuffle", filled: shuffled,
                          help: shuffled ? L("Back to the deck\'s own order")
                                         : L("Shuffle the order")) {
                    edit { $0.shuffled.toggle() }
                    rebuild(reset: true)
                }
                RoundIcon(symbol: "arrow.up.left.and.arrow.down.right", filled: false,
                          help: L("Fill the window")) { focused = true }
                RoundIcon(symbol: "timer", filled: false,
                          help: L("How long autoplay holds each side")) {
                    showingSpeed = true
                }
                .popover(isPresented: $showingSpeed, arrowEdge: .bottom) {
                    SpeedPicker(seconds: Binding(
                        get: { store.settings.flashcardSeconds },
                        set: { store.settings.flashcardSeconds = $0 }))
                }

                TextSizeControl(scale: Binding(
                    get: { store.settings.flashcardTextScale },
                    set: { store.settings.flashcardTextScale = $0 }))
                    .padding(.leading, 4)

                if Motion.enabled {
                    FlipSwitch(on: Binding(
                        get: { store.settings.flashcardFlipAnimation },
                        set: { store.settings.flashcardFlipAnimation = $0 }))
                        .padding(.leading, 4)
                }

        }
        .fixedSize(horizontal: true, vertical: false)
    }

    private var counter: some View {
        HStack(spacing: 18) {
            ArrowButton(symbol: "arrow.left", enabled: position > 0, action: previous)
            Text("\(min(position + 1, order.count)) / \(order.count)")
                .font(Face.ui(13, .medium))
                .foregroundStyle(Palette.text)
                .monospacedDigit()
                .lineLimit(1)
                .frame(minWidth: 76)
            ArrowButton(symbol: "arrow.right",
                        enabled: position < order.count - 1, action: next)
        }
        .fixedSize(horizontal: true, vertical: false)
    }

    private func handleKey(_ event: NSEvent) -> Bool {
        if Key.isPlain(event, code: Key.space) { flip(); return true }
        if Key.isPlain(event, code: Key.leftArrow) { previous(); return true }
        if Key.isPlain(event, code: Key.rightArrow) { next(); return true }
        if Key.isPlain(event, character: "1") { grade(false); return true }
        if Key.isPlain(event, character: "2") { grade(true); return true }
        if Key.isCommand(event, anyOf: ["-"]) { step(scale: -0.1); return true }
        if Key.isCommand(event, anyOf: ["+", "="]) { step(scale: 0.1); return true }
        if Key.isCommand(event, anyOf: ["0"]) { store.settings.flashcardTextScale = 1; return true }
        return false
    }

    private func step(scale delta: Double) {
        store.settings.flashcardTextScale =
            TypeScale.clampCardScale(store.settings.flashcardTextScale + delta)
    }

    private func rebuild(reset: Bool) {
        let ids = pool.map(\.id)
        let shuffle = shuffled
        let cards = Set(deck.cards.map(\.id))
        edit { s in
            s.order = shuffle ? ids.shuffled() : ids
            s.deckCards = cards
            if reset || s.position >= s.order.count { s.position = 0 }
            s.showingBack = false
            s.turned = false
        }
        hinting = false
    }

    private func reconcile() {
        let current = store.deck(deck.id) ?? deck
        let pool = scope.filter(current.cards, wordsPerDay: store.settings.vocabDaily.wordsPerDay)
        let next = session.reconciled(deck: current.cards.map(\.id), pool: pool.map(\.id))
        guard next != session else { return }
        edit { $0 = next }
    }

    private func flip() {
        if !showingBack, !session.turned, let c = card {
            edit { $0.turned = true }
            store.recordTurn(c.id, in: deck.id)
        }
        let animated = store.settings.flashcardFlipAnimation && Motion.enabled
        withAnimation(animated ? Motion.standard : nil) { edit { $0.showingBack.toggle() } }
    }

    private func star() {
        guard let c = card else { return }
        store.toggleStar(c.id, in: deck.id)
    }

    private func grade(_ correct: Bool) {
        guard let c = card else { return }
        store.recordSelfGrade(c.id, correct: correct, in: deck.id)
        store.noteDailyProgress(in: deck.id)
        edit { $0.turned = true }
        if position < order.count - 1 { move(to: position + 1) }
        else { edit { $0.showingBack = true } }
    }

    private func previous() {
        guard position > 0 else { return }
        move(to: position - 1)
    }

    private func next() {
        guard position < order.count - 1 else { return }
        move(to: position + 1)
    }

    private func move(to index: Int) {
        recordSkipIfUnturned()
        hinting = false
        edit { s in
            s.showingBack = false
            s.turned = false
            s.position = index
        }
    }

    private func recordSkipIfUnturned() {
        guard store.settings.trackSkippedCards, !session.turned, let c = card else { return }
        store.recordSkip(c.id, in: deck.id)
    }

    @State private var ticker = Timer.publish(every: 0.5, on: .main, in: .common).autoconnect()
    @State private var heldFor: Double = 0

    private func advanceAutoplay() {
        guard autoplaying else { heldFor = 0; return }
        heldFor += 0.5
        guard heldFor >= max(1, store.settings.flashcardSeconds) else { return }
        heldFor = 0
        if !showingBack {
            flip()
        } else if position < order.count - 1 {
            next()
        } else {
            autoplaying = false
        }
    }
}

struct CardFace: View {
    let card: Flashcard?
    @Binding var showingBack: Bool
    @Binding var hinting: Bool
    let starred: Bool
    var scale: Double = 1
    var animated: Bool = true
    let compact: Bool
    let onStar: () -> Void
    let onFlip: () -> Void
    var onGrade: ((Bool) -> Void)? = nil

    private var termFont: Font { Face.display(TypeScale.cardTerm(scale, compact: compact), .regular) }
    private var bodyFont: Font { Face.ui(TypeScale.cardBody(scale, compact: compact)) }
    private var exampleFont: Font { Face.ui(TypeScale.cardExample(scale, compact: compact)) }

    var body: some View {
        ZStack {
            face(front: true).opacity(showingBack ? 0 : 1)
            face(front: false)
                .rotation3DEffect(.degrees(animated ? 180 : 0), axis: (x: 0, y: 1, z: 0))
                .opacity(showingBack ? 1 : 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Palette.card)
        .overlay(RoundedRectangle(cornerRadius: 6)
            .strokeBorder(Palette.hairline, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .rotation3DEffect(.degrees(animated && showingBack ? 180 : 0),
                          axis: (x: 0, y: 1, z: 0), perspective: 0.35)
        .contentShape(Rectangle())
        .onTapGesture { onFlip() }
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel(showingBack ? L("Definition") : L("Word"))
        .accessibilityHint(L("Click, or press space, to turn the card over"))
    }

    @ViewBuilder
    private func face(front: Bool) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Spacer()
                if front, let card, card.hasDefinition {
                    CardChrome(symbol: "lightbulb", title: L("Get a hint"),
                               active: hinting) {
                        withAnimation(Motion.quick) { hinting.toggle() }
                    }
                }
                CardChrome(symbol: starred ? "star.fill" : "star",
                           title: starred ? L("Starred") : L("Star"),
                           active: starred, action: onStar)
                    .help(starred
                          ? L("Take the star off — it leaves the Starred list")
                          : L("Keep this word back to come to on its own, in Starred"))
            }
            .padding(.horizontal, 18)
            .padding(.top, 16)

            Spacer(minLength: 0)

            if let card {
                if front {
                    VStack(spacing: 18) {
                        Text(Markup.attributed(card.term, font: termFont))
                            .foregroundStyle(Palette.navy)
                            .multilineTextAlignment(.center)
                            .lineLimit(1)
                            .minimumScaleFactor(0.3)
                        if hinting {
                            Text(Hint.text(for: card))
                                .font(bodyFont)
                                .foregroundStyle(Palette.textMuted)
                                .multilineTextAlignment(.center)
                                .frame(maxWidth: 640)
                                .transition(.opacity)
                        }
                    }
                    .padding(.horizontal, 34)
                } else {
                    VStack(spacing: 16) {
                        Text(card.hasDefinition
                             ? Markup.attributed(card.definition, font: bodyFont)
                             : AttributedString(card.backText))
                            .font(bodyFont)
                            .foregroundStyle(card.hasDefinition ? Palette.text
                                                                : Palette.textMuted)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: 760)
                        if !card.example.isEmpty {
                            VStack(spacing: 8) {
                                Rule(brass: true).frame(width: 34)
                                Text(Markup.attributed(card.example, font: exampleFont))
                                    .italic()
                                    .foregroundStyle(Palette.textMuted)
                                    .multilineTextAlignment(.center)
                                    .frame(maxWidth: 760)
                            }
                        }
                    }
                    .padding(.horizontal, 34)
                }
            }

            Spacer(minLength: 0)

            footer(card)
        }
    }

    @ViewBuilder
    private func footer(_ card: Flashcard?) -> some View {
        VStack(spacing: 10) {
            if showingBack, let card, let onGrade {
                HStack(spacing: 10) {
                    GradeButton(title: L("Missed it"), symbol: "xmark",
                                tint: Palette.wrong, soft: Palette.wrongSoft,
                                shortcut: "1") { onGrade(false) }
                    GradeButton(title: L("Got it"), symbol: "checkmark",
                                tint: Palette.correct, soft: Palette.correctSoft,
                                shortcut: "2") { onGrade(true) }
                }
                .transition(.opacity)
                .accessibilityLabel(Lf("How did you do on %@?", Markup.plain(card.term)))
            }
            let record = card.map(\.recordLine).flatMap { $0.isEmpty ? nil : $0 }
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) {
                    recordText(record)
                    Spacer(minLength: 12)
                    hintText
                    Spacer(minLength: 12)
                    recordText(record).hidden()
                }
                HStack(spacing: 12) {
                    recordText(record)
                    Spacer(minLength: 12)
                    hintText
                }
                VStack(spacing: 3) {
                    hintText
                    recordText(record)
                }
            }
        }
        .padding(.horizontal, 18)
        .padding(.bottom, 16)
    }

    private var hintText: some View {
        Text(L("Click, or press space, to turn the card over"))
            .font(Face.ui(10.5))
            .foregroundStyle(Palette.textMuted.opacity(0.8))
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
    }

    @ViewBuilder
    private func recordText(_ line: String?) -> some View {
        Text(line ?? "")
            .font(Face.ui(10))
            .foregroundStyle(Palette.textMuted.opacity(0.75))
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
    }
}

private struct GradeButton: View {
    let title: String
    let symbol: String
    let tint: Color
    let soft: Color
    let shortcut: String
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 7) {
                Image(systemName: symbol).font(.system(size: 11, weight: .bold))
                Text(title).font(Face.ui(12.5, .semibold))
                Text(shortcut)
                    .font(Face.ui(9, .medium))
                    .foregroundStyle(tint.opacity(0.7))
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .overlay(RoundedRectangle(cornerRadius: 2)
                        .strokeBorder(tint.opacity(0.35), lineWidth: 1))
            }
            .foregroundStyle(tint)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(hovering ? soft : soft.opacity(0.45))
            .overlay(RoundedRectangle(cornerRadius: 4)
                .strokeBorder(tint.opacity(hovering ? 0.7 : 0.35), lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 4))
        }
        .buttonStyle(.plain)
        .animation(Motion.quick, value: hovering)
        .onHover { hovering = $0 }
    }
}

private struct FlipSwitch: View {
    @Binding var on: Bool

    var body: some View {
        HStack(spacing: 7) {
            Text(L("Turn"))
                .font(Face.ui(10.5, .medium))
                .foregroundStyle(Palette.textMuted)
            Toggle("", isOn: $on)
                .toggleStyle(.switch)
                .controlSize(.mini)
                .labelsHidden()
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 4)
        .background(Palette.subtleFill)
        .overlay(Capsule().strokeBorder(Palette.hairline, lineWidth: 1))
        .clipShape(Capsule())
        .help(on ? L("Turn without the animation") : L("Turn with the animation"))
    }
}

private struct TextSizeControl: View {
    @Binding var scale: Double

    var body: some View {
        HStack(spacing: 2) {
            step(L("Smaller"), "textformat.size.smaller", -0.1,
                 enabled: scale > TypeScale.cardScaleRange.lowerBound + 0.001)
            Text("\(Int((scale * 100).rounded()))%")
                .font(Face.ui(10, .medium))
                .foregroundStyle(Palette.textMuted)
                .monospacedDigit()
                .frame(width: 38)
                .contentShape(Rectangle())
                .onTapGesture { scale = 1 }
                .help(L("Back to the normal size"))
            step(L("Bigger"), "textformat.size.larger", 0.1,
                 enabled: scale < TypeScale.cardScaleRange.upperBound - 0.001)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .background(Palette.subtleFill)
        .overlay(Capsule().strokeBorder(Palette.hairline, lineWidth: 1))
        .clipShape(Capsule())
    }

    private func step(_ label: String, _ symbol: String, _ delta: Double,
                      enabled: Bool) -> some View {
        Button { scale = TypeScale.clampCardScale(scale + delta) } label: {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(enabled ? Palette.text : Palette.textMuted.opacity(0.35))
                .frame(width: 24, height: 22)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .iconHelp(label)
    }
}

private struct CardChrome: View {
    let symbol: String
    let title: String?
    let active: Bool
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: symbol)
                    .font(.system(size: 12, weight: .medium))
                if let title {
                    Text(title).font(Face.ui(11.5, .medium))
                }
            }
            .foregroundStyle(active ? Palette.brass : Palette.textMuted)
            .padding(.horizontal, title == nil ? 7 : 9)
            .padding(.vertical, 5)
            .background(hovering ? Palette.paperDeep : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 3))
        }
        .buttonStyle(.plain)
        .animation(Motion.quick, value: hovering)
        .onHover { hovering = $0 }
    }
}

private struct RoundIcon: View {
    let symbol: String
    let filled: Bool
    let help: String
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundStyle(filled ? Palette.card : Palette.text)
                .frame(width: 34, height: 34)
                .background(Circle().fill(filled ? Palette.navy
                                          : (hovering ? Palette.paperDeep : Palette.subtleFill)))
                .overlay(Circle().strokeBorder(filled ? .clear : Palette.hairline, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .iconHelp(help)
        .animation(Motion.quick, value: hovering)
        .onHover { hovering = $0 }
    }
}

struct QuietLink: View {
    let title: String
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(Face.ui(11.5, .medium))
                .foregroundStyle(hovering ? Palette.navy : Palette.textMuted)
                .underline(hovering)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

private struct ArrowButton: View {
    let symbol: String
    let enabled: Bool
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(enabled ? (hovering ? Palette.navy : Palette.text)
                                 : Palette.textMuted.opacity(0.35))
                .frame(width: 30, height: 30)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .accessibilityLabel(symbol == "arrow.left" ? L("Back") : L("Next"))
        .onHover { hovering = $0 && enabled }
    }
}

private struct SpeedPicker: View {
    @Binding var seconds: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionLabel(text: L("Autoplay"))
            Text(Lp(Int(seconds), "%d second a side", "%d seconds a side"))
                .font(Face.ui(12.5, .medium))
                .foregroundStyle(Palette.text)
            Slider(value: $seconds, in: 1...20, step: 1)
                .frame(width: 210)
            Text(L("A card is held on its front for this long, then on its back, "
                   + "then the next one arrives."))
                .font(Face.ui(10.5))
                .foregroundStyle(Palette.textMuted)
                .frame(width: 210, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
    }
}

private struct FocusedCard: View {
    let deck: Deck
    let card: Flashcard?
    @Binding var showingBack: Bool
    @Binding var hinting: Bool
    let position: Int
    let total: Int
    let scale: Double
    let animated: Bool
    let onFlip: () -> Void
    let onPrevious: () -> Void
    let onNext: () -> Void
    let onStar: () -> Void
    let onGrade: (Bool) -> Void
    let onClose: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(deck.name)
                    .font(Face.display(15))
                    .foregroundStyle(Palette.navy)
                Spacer()
                Button(action: onClose) {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.down.right.and.arrow.up.left")
                        Text(L("Close")).font(Face.ui(12))
                    }
                    .foregroundStyle(Palette.textMuted)
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.escape, modifiers: [])
            }
            .padding(.horizontal, 26)
            .padding(.vertical, 14)

            CardFace(card: card, showingBack: $showingBack, hinting: $hinting,
                     starred: card?.starred ?? false, scale: scale, animated: animated,
                     compact: true, onStar: onStar, onFlip: onFlip, onGrade: onGrade)
                .padding(.horizontal, 34)

            HStack(spacing: 18) {
                ArrowButton(symbol: "arrow.left", enabled: position > 0, action: onPrevious)
                Text("\(min(position + 1, total)) / \(total)")
                    .font(Face.ui(13, .medium))
                    .foregroundStyle(Palette.text)
                    .monospacedDigit()
                ArrowButton(symbol: "arrow.right", enabled: position < total - 1, action: onNext)
            }
            .padding(.vertical, 18)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Palette.paper)
    }
}

extension View {
    @ViewBuilder
    func fullScreenLikeOverlay<C: View>(isPresented: Binding<Bool>,
                                        @ViewBuilder content: () -> C) -> some View {
        overlay {
            if isPresented.wrappedValue {
                content().transition(.opacity)
            }
        }
        .animation(Motion.standard, value: isPresented.wrappedValue)
    }
}

struct EmptyDeckNotice: View {
    @EnvironmentObject var store: AppStore
    let deck: Deck
    @State private var mining = false

    var body: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "rectangle.on.rectangle")
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(Palette.brass)
            Text(L("This deck is empty"))
                .font(Face.display(19))
                .foregroundStyle(Palette.navy)
            Text(L("Take the words out of a question set you have already imported, "
                   + "or type your own in. The Words-in-Context questions carry their "
                   + "own definitions, so most words arrive with one already written."))
                .font(Face.ui(12.5))
                .foregroundStyle(Palette.textMuted)
                .multilineTextAlignment(.center)
                .lineSpacing(3)
                .frame(maxWidth: 460)
            BluebookButton(title: L("Take words from a question set…"),
                           enabled: !store.banks.isEmpty, lifts: true) {
                mining = true
            }
            Text(store.banks.isEmpty
                 ? L("Import a question bank PDF first, or write your own cards "
                     + "on the Cards tab.")
                 : L("Or write your own on the Cards tab."))
                .font(Face.ui(11))
                .foregroundStyle(Palette.textMuted)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .sheet(isPresented: $mining) {
            MiningSheet(deck: deck) { _ in mining = false }
                .environmentObject(store)
        }
    }
}
