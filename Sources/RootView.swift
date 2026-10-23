import SwiftUI
import AppKit

struct RootView: View {
    @EnvironmentObject var store: AppStore
    @EnvironmentObject var intro: IntroState

    @State private var restorable: Mercy.Gap?

    var body: some View {
        ZStack {
            Palette.paper.ignoresSafeArea()

            Group {
                if store.learnCoversResults, let id = store.learning,
                   let article = Articles.current.first(where: { $0.id == id }) {
                    ArticleView(article: article, backTitle: L("Results")) { store.closeLearn() }
                } else if store.learnCoversResults, store.learning != nil {
                    ArticlesView()
                } else if let session = store.session {
                    if session.isFinished {
                        ReviewView(session: session)
                    } else if session.isSideBySide {
                        DoubleExamView().pinnedPaper()
                    } else {
                        ExamView().pinnedPaper()
                    }
                } else if let id = store.learning,
                          let article = Articles.current.first(where: { $0.id == id }) {
                    ArticleView(article: article) { store.openLearn() }
                } else if store.learning != nil {
                    ArticlesView()
                } else if let focus = store.focus, store.deck(focus.deckID) != nil {
                    DeckFocusView(focus: focus)
                } else {
                    HomeView()
                }
            }

            if intro.isRunning {
                IntroCurtain(intro: intro)
            }

            if let gap = restorable, store.session == nil, !intro.isRunning {
                Color.black.opacity(0.18).ignoresSafeArea()
                    .transition(.opacity)
                StreakRestorePrompt(gap: gap) {
                    withAnimation(Motion.quick) { restorable = nil }
                }
                .transition(.opacity.combined(with: .scale(scale: 0.98)))
            }
        }
        .frame(minWidth: WindowChrome.minWidth, maxWidth: .infinity,
               minHeight: WindowChrome.minHeight, maxHeight: .infinity)
        .pinsWindowToPaper(store.session.map { !$0.isFinished } ?? false)
        .id("\(store.settings.language.rawValue)/\(store.settings.stealthMode)")
        .coordinateSpace(name: IntroState.space)
        .onPreferenceChange(SealFrameKey.self) { intro.target = $0 }
        .task {
            await intro.playOnce()
            withAnimation(Motion.standard) { restorable = store.restorableGap() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .usufuLanguageChanged)) { _ in
            intro.replay()
        }
        .alert(L("After the update, some highlights no longer matched their words and were taken off; their notes are kept."),
               isPresented: Binding(
                   get: { store.highlightsTakenOff > 0 && store.rereadingBankIDs.isEmpty
                       && store.session == nil },
                   set: { if !$0 { store.highlightsTakenOff = 0 } })) {
            Button(L("OK")) { store.highlightsTakenOff = 0 }
        }
    }
}
