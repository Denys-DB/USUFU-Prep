import SwiftUI

struct CardsPane: View {
    @EnvironmentObject var store: AppStore
    let deck: Deck

    @State private var search = ""
    @State private var mining = false
    @State private var editing: Flashcard?
    @State private var adding = false
    @State private var newTerm = ""
    @State private var newDefinition = ""
    @State private var confirmDelete: Flashcard?
    @State private var selected: Set<UUID> = []
    @State private var confirmDeleteSelected = false
    @State private var note = ""

    private var sort: CardSort { store.deckSession(deck.id).sort }

    private var shown: [Flashcard] {
        let needle = search.trimmed.lowercased()
        let matching = needle.isEmpty ? deck.cards : deck.cards.filter {
            Markup.plain($0.term).lowercased().contains(needle)
                || Markup.plain($0.definition).lowercased().contains(needle)
        }
        return sort.apply(matching)
    }

    private var selectedShown: [Flashcard] { shown.filter { selected.contains($0.id) } }

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Rule()
            list
        }
        .onAppear { if deck.cards.isEmpty { adding = true } }
        .sheet(isPresented: $mining) {
            MiningSheet(deck: deck) { added in
                mining = false
                if added > 0 { note = Lp(added, "%d word added", "%d words added") }
            }
            .environmentObject(store)
        }
        .sheet(item: $editing) { card in
            CardEditor(card: card, deck: deck) { editing = nil }
                .environmentObject(store)
        }
        .alert(L("Delete this card?"), isPresented: Binding(
            get: { confirmDelete != nil }, set: { if !$0 { confirmDelete = nil } })) {
            Button(L("Cancel"), role: .cancel) { confirmDelete = nil }
            Button(L("Delete"), role: .destructive) {
                if let c = confirmDelete { store.deleteCard(c.id, from: deck.id) }
                confirmDelete = nil
            }
        } message: {
            Text(confirmDelete.map {
                Lf("\"%@\" will be removed from this deck.", Markup.plain($0.term))
            } ?? "")
        }
        .alert(L("Delete these cards?"), isPresented: $confirmDeleteSelected) {
            Button(L("Cancel"), role: .cancel) { confirmDeleteSelected = false }
            Button(L("Delete"), role: .destructive) {
                store.deleteCards(Set(selectedShown.map(\.id)), from: deck.id)
                note = Lp(selectedShown.count, "%d card deleted", "%d cards deleted")
                selected = []
                confirmDeleteSelected = false
            }
        } message: {
            Text(Lp(selectedShown.count,
                    "%d card will be removed from this deck.",
                    "%d cards will be removed from this deck."))
        }
    }

    private var toolbar: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 11))
                        .foregroundStyle(Palette.textMuted)
                    TextField(L("Search this deck"), text: $search)
                        .textFieldStyle(.plain)
                        .font(Face.ui(12))
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Palette.subtleFill)
                .overlay(RoundedRectangle(cornerRadius: 3)
                    .strokeBorder(Palette.hairline, lineWidth: 1))
                .clipShape(RoundedRectangle(cornerRadius: 3))
                .frame(maxWidth: 280)

                Spacer()

                if !note.isEmpty {
                    Text(note)
                        .font(Face.ui(11, .medium))
                        .foregroundStyle(Palette.brass)
                        .transition(.opacity)
                }

                Menu {
                    ForEach(CardSort.allCases) { option in
                        Button {
                            store.updateDeckSession(deck.id) { $0.sort = option }
                        } label: {
                            HStack {
                                Text(option.title)
                                if sort == option { Image(systemName: "checkmark") }
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "arrow.up.arrow.down")
                            .font(.system(size: 10, weight: .medium))
                        Text(sort == .deckOrder ? L("Sort") : sort.title)
                            .font(Face.ui(11.5))
                            .lineLimit(1)
                    }
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .help(L("The order the cards are listed in"))
                .padding(.trailing, 4)

                BluebookButton(title: L("Take words from a question set…"),
                               style: .secondary,
                               enabled: !store.banks.isEmpty, lifts: true) { mining = true }
                BluebookButton(title: adding ? L("Close") : L("Add a card"),
                               style: .plain, lifts: true) {
                    withAnimation(Motion.quick) { adding.toggle() }
                }
            }
            if adding { addRow }
            selectionBar
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 14)
        .background(Palette.card)
        .animation(Motion.quick, value: note)
    }

    private var addRow: some View {
        HStack(spacing: 10) {
            TextField(L("Word"), text: $newTerm)
                .textFieldStyle(.roundedBorder)
                .font(Face.ui(12.5))
                .frame(width: 190)
                .onSubmit(commit)
            TextField(L("What it means"), text: $newDefinition)
                .textFieldStyle(.roundedBorder)
                .font(Face.ui(12.5))
                .onSubmit(commit)
            BluebookButton(title: L("Add"), enabled: !newTerm.trimmed.isEmpty, action: commit)
        }
        .transition(.opacity)
    }

    @ViewBuilder
    private var selectionBar: some View {
        if !selectedShown.isEmpty {
            HStack(spacing: 12) {
                Text(Lf("%d selected", selectedShown.count))
                    .font(Face.ui(11.5, .medium))
                    .foregroundStyle(Palette.brass)
                QuietLink(title: L("Select all")) { selected = Set(shown.map(\.id)) }
                QuietLink(title: L("Select none")) { selected = [] }
                Spacer()
                QuietLink(title: L("Star them")) {
                    store.setStarred(true, on: Set(selectedShown.map(\.id)), in: deck.id)
                }
                QuietLink(title: L("Remove their stars")) {
                    store.setStarred(false, on: Set(selectedShown.map(\.id)), in: deck.id)
                }
                BluebookButton(title: L("Delete selected"), style: .secondary) {
                    confirmDeleteSelected = true
                }
            }
            .transition(.opacity)
        }
    }

    private func commit() {
        let term = newTerm.trimmed
        guard !term.isEmpty else { return }
        let added = store.addCard(Flashcard(term: term, definition: newDefinition.trimmed),
                                  to: deck.id)
        note = added ? Lf("Added \"%@\"", term) : Lf("\"%@\" is already in this deck", term)
        newTerm = ""
        newDefinition = ""
    }

    private var list: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(shown) { card in
                    CardRow(card: card,
                            selected: selected.contains(card.id),
                            anySelected: !selected.isEmpty,
                            onToggle: { toggle(card) },
                            onStar: { store.toggleStar(card.id, in: deck.id) },
                            onEdit: { editing = card },
                            onDelete: { confirmDelete = card })
                    Rule()
                }
                if shown.isEmpty {
                    Text(deck.cards.isEmpty
                         ? L("Nothing here yet. Type a word and what it means above, "
                             + "or take a set of words out of a question bank.")
                         : L("No card here matches that."))
                        .font(Face.ui(12))
                        .foregroundStyle(Palette.textMuted)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 400)
                        .padding(.vertical, 40)
                }
            }
        }
        .background(Palette.paper)
        .animation(Motion.quick, value: selected.isEmpty)
    }

    private func toggle(_ card: Flashcard) {
        if selected.contains(card.id) { selected.remove(card.id) }
        else { selected.insert(card.id) }
    }
}

private struct CardRow: View {
    let card: Flashcard
    let selected: Bool
    let anySelected: Bool
    let onToggle: () -> Void
    let onStar: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void

    @State private var hovering = false

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Toggle("", isOn: Binding(get: { selected }, set: { _ in onToggle() }))
                .toggleStyle(.checkbox)
                .labelsHidden()
                .opacity(selected || anySelected || hovering ? 1 : 0.22)
                .help(L("Select this card"))
                .padding(.top, 1)

            Button(action: onStar) {
                Image(systemName: card.starred ? "star.fill" : "star")
                    .font(.system(size: 12))
                    .foregroundStyle(card.starred ? Palette.brass : Palette.textMuted.opacity(0.5))
            }
            .buttonStyle(.plain)
            .iconHelp(card.starred ? L("Remove the star") : L("Star this word"))
            .padding(.top, 2)

            Text(Markup.attributed(card.term, font: Face.ui(13, .semibold)))
                .foregroundStyle(Palette.navy)
                .frame(width: 170, alignment: .leading)

            VStack(alignment: .leading, spacing: 4) {
                if card.hasDefinition {
                    Text(Markup.attributed(card.definition, font: Face.ui(12.5)))
                        .foregroundStyle(Palette.text)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Text(L("No definition yet"))
                        .font(Face.ui(12))
                        .italic()
                        .foregroundStyle(Palette.textMuted)
                }
                if !card.example.isEmpty {
                    Text(Markup.attributed(card.example, font: Face.ui(11)))
                        .italic()
                        .foregroundStyle(Palette.textMuted)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if !card.recordLine.isEmpty {
                    Text(card.recordLine)
                        .font(Face.ui(10))
                        .foregroundStyle(Palette.textMuted.opacity(0.85))
                }
                if !card.sourceBankName.isEmpty {
                    Text(Lf("from %@", card.sourceBankName))
                        .font(Face.ui(10))
                        .foregroundStyle(Palette.textMuted.opacity(0.8))
                }
            }

            Spacer(minLength: 8)

            if let accuracy = card.accuracy {
                Text("\(Int((accuracy * 100).rounded()))%")
                    .font(Face.ui(11, .medium))
                    .foregroundStyle(card.isTrouble ? Palette.wrong : Palette.textMuted)
                    .help(Lf("Right %1$d of %2$d in tests", card.timesCorrect, card.timesSeen))
            }

            HStack(spacing: 4) {
                Button(action: onEdit) {
                    Image(systemName: "pencil").font(.system(size: 11))
                }
                .buttonStyle(.plain)
                .iconHelp(L("Edit this card"))
                Button(action: onDelete) {
                    Image(systemName: "trash").font(.system(size: 11))
                }
                .buttonStyle(.plain)
                .iconHelp(L("Delete this card"))
            }
            .foregroundStyle(Palette.textMuted)
            .opacity(hovering ? 1 : 0.25)
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 11)
        .background(selected ? Palette.brassSoft.opacity(0.35)
                    : (hovering ? Palette.card.opacity(0.6) : Color.clear))
        .animation(Motion.quick, value: hovering)
        .onHover { hovering = $0 }
    }
}

struct CardEditor: View {
    @EnvironmentObject var store: AppStore
    let deck: Deck
    let onClose: () -> Void

    @State private var term: String
    @State private var definition: String
    @State private var example: String
    @State private var hint: String
    private let card: Flashcard

    init(card: Flashcard, deck: Deck, onClose: @escaping () -> Void) {
        self.card = card
        self.deck = deck
        self.onClose = onClose
        _term = State(initialValue: card.term)
        _definition = State(initialValue: card.definition)
        _example = State(initialValue: card.example)
        _hint = State(initialValue: card.hint)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 7) {
                Text(L("Edit card"))
                    .font(Face.display(17))
                    .foregroundStyle(Palette.navy)
                Rule(brass: true).frame(width: 34)
            }

            field(.term, L("Word"), text: $term, lines: 1)
            field(.definition, L("What it means"), text: $definition, lines: 3)
            field(.example, L("A sentence using it"), text: $example, lines: 3)

            VStack(alignment: .leading, spacing: 5) {
                SectionLabel(text: L("Hint"))
                TextField(L("Leave empty and half the definition is used"), text: $hint)
                    .textFieldStyle(.roundedBorder)
                    .font(Face.ui(12.5))
                Text(Lf("Shown as: %@", previewHint))
                    .font(Face.ui(10.5))
                    .foregroundStyle(Palette.textMuted)
            }

            VStack(alignment: .leading, spacing: 6) {
                SectionLabel(text: L("How the card will read"))
                Text(Markup.attributed(definition.isEmpty ? term : definition,
                                       font: Face.ui(14)))
                    .foregroundStyle(Palette.text)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
                    .background(Palette.card)
                    .overlay(RoundedRectangle(cornerRadius: 3)
                        .strokeBorder(Palette.hairline, lineWidth: 1))
            }

            HStack {
                Spacer()
                BluebookButton(title: L("Cancel"), style: .secondary, action: onClose)
                BluebookButton(title: L("Save"), enabled: !term.trimmed.isEmpty) {
                    var next = card
                    next.term = term.trimmed
                    next.definition = definition.trimmed
                    next.example = example.trimmed
                    next.hint = hint.trimmed
                    store.updateCard(next, in: deck.id)
                    onClose()
                }
            }
        }
        .padding(26)
        .frame(width: 560)
        .background(Palette.paper)
    }

    private var previewHint: String {
        var preview = card
        preview.definition = definition
        preview.hint = hint
        let text = Hint.text(for: preview)
        return text.isEmpty ? L("nothing yet — write a definition first") : text
    }

    private enum Field { case term, definition, example }
    @State private var focused: Field = .definition
    @State private var termSelection = 0..<0
    @State private var definitionSelection = 0..<0
    @State private var exampleSelection = 0..<0
    @State private var termView: MarkupField.Coordinator?

    @ViewBuilder
    private func field(_ which: Field, _ label: String,
                       text: Binding<String>, lines: Int) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 8) {
                SectionLabel(text: label)
                Spacer()
                MarkupToolbar(enabled: !selection(for: which).isEmpty) { style in
                    apply(style, to: which, text: text)
                }
            }
            MarkupField(text: text,
                        selection: binding(for: which),
                        height: lines > 1 ? CGFloat(lines) * 22 : 26)
                .frame(height: lines > 1 ? CGFloat(lines) * 22 : 26)
                .background(Palette.card)
                .overlay(RoundedRectangle(cornerRadius: 3)
                    .strokeBorder(Palette.hairline, lineWidth: 1))
                .onTapGesture { focused = which }
        }
    }

    private func selection(for which: Field) -> Range<Int> {
        switch which {
        case .term: return termSelection
        case .definition: return definitionSelection
        case .example: return exampleSelection
        }
    }

    private func binding(for which: Field) -> Binding<Range<Int>> {
        switch which {
        case .term: return $termSelection
        case .definition: return $definitionSelection
        case .example: return $exampleSelection
        }
    }

    private func apply(_ style: Markup.Style, to which: Field, text: Binding<String>) {
        let range = selection(for: which)
        guard !range.isEmpty else { return }
        let result = Markup.toggle(style, in: text.wrappedValue, range: range)
        text.wrappedValue = result.text
        binding(for: which).wrappedValue = result.range
    }
}

private struct MarkupToolbar: View {
    let enabled: Bool
    let apply: (Markup.Style) -> Void

    var body: some View {
        HStack(spacing: 2) {
            ForEach(Markup.Style.allCases) { style in
                Button { apply(style) } label: {
                    Image(systemName: style.symbol)
                        .font(.system(size: 11, weight: .medium))
                        .frame(width: 24, height: 20)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(!enabled)
                .foregroundStyle(enabled ? Palette.text : Palette.textMuted.opacity(0.35))
                .help(enabled ? style.title : L("Select some text first"))
                .accessibilityLabel(style.title)
            }
        }
        .padding(.horizontal, 3)
        .padding(.vertical, 2)
        .background(Palette.subtleFill)
        .overlay(RoundedRectangle(cornerRadius: 3)
            .strokeBorder(Palette.hairline, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 3))
    }
}

struct MiningSheet: View {
    @EnvironmentObject var store: AppStore
    let deck: Deck
    let onClose: (Int) -> Void

    @State private var bankID: String = ""
    @State private var found: [MinedCard] = []
    @State private var chosen: Set<String> = []
    @State private var working = false
    @State private var searched = false
    @State private var onlyDefined = true

    private var listed: [MinedCard] {
        onlyDefined ? found.filter(\.hasDefinition) : found
    }

    private func alreadyHere(_ card: MinedCard) -> Bool { deck.holds(term: card.term) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            head
            Rule()
            content
            Rule()
            foot
        }
        .frame(width: 660, height: 560)
        .background(Palette.paper)
        .onAppear {
            if bankID.isEmpty { bankID = store.config.bankID }
            if bankID.isEmpty { bankID = store.banks.first?.id ?? "" }
        }
    }

    private var head: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 7) {
                Text(L("Take words from a question set"))
                    .font(Face.display(17))
                    .foregroundStyle(Palette.navy)
                Rule(brass: true).frame(width: 34)
            }
            Text(L("The explanations in a College Board export define the words they test, "
                   + "so the words come with their meanings already written. Anything the "
                   + "reader could not define is still offered — you can write that one in."))
                .font(Face.ui(11.5))
                .foregroundStyle(Palette.textMuted)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 10) {
                Picker("", selection: $bankID) {
                    ForEach(store.banks) { bank in
                        Text(bank.name).tag(bank.id)
                    }
                }
                .labelsHidden()
                .frame(maxWidth: 300)
                BluebookButton(title: working ? L("Reading…") : L("Find words"),
                               enabled: !working && !bankID.isEmpty) { search() }
                Spacer()
            }
        }
        .padding(22)
        .background(Palette.card)
    }

    @ViewBuilder
    private var content: some View {
        if working {
            centred { ProgressView().controlSize(.small) }
        } else if !searched {
            centred {
                Text(L("Choose a question set and press Find words."))
                    .font(Face.ui(12))
                    .foregroundStyle(Palette.textMuted)
            }
        } else if listed.isEmpty && !found.isEmpty {
            centred {
                Text(hiddenLine)
                    .font(Face.ui(12))
                    .foregroundStyle(Palette.textMuted)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 400)
            }
        } else if listed.isEmpty {
            centred {
                Text(L("Nothing found in that set. Words come from the "
                       + "Words-in-Context questions, which the Math sets do not have."))
                    .font(Face.ui(12))
                    .foregroundStyle(Palette.textMuted)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 400)
            }
        } else {
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(listed) { card in
                        MinedRow(card: card,
                                 chosen: chosen.contains(card.id),
                                 already: alreadyHere(card)) {
                            if chosen.contains(card.id) { chosen.remove(card.id) }
                            else { chosen.insert(card.id) }
                        }
                        Rule()
                    }
                }
            }
        }
    }

    private var foot: some View {
        HStack(spacing: 12) {
            Toggle(isOn: $onlyDefined) {
                Text(L("Only words with a definition")).font(Face.ui(11.5))
            }
            .toggleStyle(.checkbox)
            if searched && !listed.isEmpty
                && VocabularyMiner.hidden(found, onlyDefined: onlyDefined) > 0 {
                Text(hiddenLine)
                    .font(Face.ui(11))
                    .foregroundStyle(Palette.textMuted)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            if searched && !listed.isEmpty {
                QuietLink(title: L("Select all")) { chosen = Set(selectable.map(\.id)) }
                QuietLink(title: L("Select none")) { chosen = [] }
            }
            Spacer()
            BluebookButton(title: L("Cancel"), style: .secondary) { onClose(0) }
            BluebookButton(title: Lf("Add %d", chosen.count), enabled: !chosen.isEmpty) { add() }
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 14)
        .background(Palette.card)
    }

    private var selectable: [MinedCard] { listed.filter { !alreadyHere($0) } }

    private var hiddenLine: String {
        Lp(VocabularyMiner.hidden(found, onlyDefined: onlyDefined),
           "%d word without a definition is hidden", "%d words without a definition are hidden")
    }

    private func centred<C: View>(@ViewBuilder _ content: () -> C) -> some View {
        VStack { Spacer(); content(); Spacer() }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func search() {
        guard let bank = store.bank(bankID) else { return }
        working = true
        chosen = []
        Task {
            let mined = await store.mineVocabulary(from: bank)
            found = mined
            let opening = VocabularyMiner.opening(mined, already: alreadyHere)
            onlyDefined = opening.onlyDefined
            chosen = opening.chosen
            working = false
            searched = true
        }
    }

    private func add() {
        guard let bank = store.bank(bankID) else { return }
        let cards = found.filter { chosen.contains($0.id) }
            .map { store.card(from: $0, bank: bank) }
        let added = store.addCards(cards, to: deck.id)
        onClose(added)
    }
}

private struct MinedRow: View {
    let card: MinedCard
    let chosen: Bool
    let already: Bool
    let toggle: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Toggle("", isOn: Binding(get: { chosen && !already }, set: { _ in toggle() }))
                .toggleStyle(.checkbox)
                .labelsHidden()
                .disabled(already)
            VStack(alignment: .leading, spacing: 3) {
                Text(card.term)
                    .font(Face.ui(13, .semibold))
                    .foregroundStyle(already ? Palette.textMuted : Palette.navy)
                if card.hasDefinition {
                    Text(card.definition)
                        .font(Face.ui(12))
                        .foregroundStyle(Palette.text)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Text(L("No definition found — you can write one"))
                        .font(Face.ui(11.5))
                        .italic()
                        .foregroundStyle(Palette.textMuted)
                }
                if !card.example.isEmpty {
                    Text(card.example)
                        .font(Face.ui(10.5))
                        .italic()
                        .foregroundStyle(Palette.textMuted)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 8)
            if already {
                Text(L("already here"))
                    .font(Face.ui(10, .medium))
                    .foregroundStyle(Palette.textMuted)
            }
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 9)
        .opacity(already ? 0.55 : 1)
        .contentShape(Rectangle())
        .onTapGesture { if !already { toggle() } }
    }
}
