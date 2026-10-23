import SwiftUI

struct DeckFocusView: View {
    @EnvironmentObject var store: AppStore
    let focus: DeckFocus

    private var deck: Deck? { store.deck(focus.deckID) }

    var body: some View {
        VStack(spacing: 0) {
            if let deck {
                header(deck)
                Rule()
                switch focus {
                case .cards: FlashcardsPane(deck: deck)
                case .test: VocabTestPane(deck: deck)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Palette.paper)
        .watchingKeys { event in
            guard Key.isPlain(event, code: Key.escape) else { return false }
            store.focus = nil
            return true
        }
    }

    private func header(_ deck: Deck) -> some View {
        HStack(alignment: .center, spacing: 14) {
            Button {
                store.focus = nil
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 11, weight: .semibold))
                    Text(L("Library")).font(Face.ui(12))
                }
                .foregroundStyle(Palette.textMuted)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(L("Back to the library — nothing is lost"))

            Rule().frame(width: 1, height: 22)

            VStack(alignment: .leading, spacing: 2) {
                Text(deck.name)
                    .font(Face.display(16, .semibold))
                    .foregroundStyle(Palette.navy)
                    .lineLimit(1)
                Text(subtitle(deck))
                    .font(Face.ui(10.5))
                    .foregroundStyle(Palette.textMuted)
                    .lineLimit(1)
            }

            Spacer(minLength: 12)

            Text(L("Esc to leave"))
                .font(Face.ui(10))
                .foregroundStyle(Palette.textMuted.opacity(0.8))
        }
        .padding(.horizontal, 24)
        .padding(.top, WindowChrome.trafficLights + 6)
        .padding(.bottom, 12)
        .background(Palette.card)
    }

    private func subtitle(_ deck: Deck) -> String {
        let session = store.deckSession(deck.id)
        switch focus {
        case .cards:
            return session.scope == .today
                ? L("Today's words") : Lp(deck.cards.count, "%d card", "%d cards")
        case .test:
            return L("Test")
        }
    }


}
