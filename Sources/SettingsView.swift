import SwiftUI
import AppKit

extension Notification.Name {
    static let usufuOpenSettings = Notification.Name("usufu.openSettings")
    static let usufuOpenAbout = Notification.Name("usufu.openAbout")
}

struct SettingsView: View {
    @EnvironmentObject var store: AppStore
    var onClose: () -> Void

    enum Tab: String, CaseIterable {
        case study, customisation, students, storage, about

        var title: String {
            switch self {
            case .study: return L("What you study")
            case .customisation: return L("Customization")
            case .students: return L("Students")
            case .storage: return L("Storage")
            case .about: return L("About")
            }
        }
        var symbol: String {
            switch self {
            case .study: return "checklist"
            case .customisation: return "slider.horizontal.3"
            case .students: return "person.2"
            case .storage: return "externaldrive"
            case .about: return "info.circle"
            }
        }
    }

    @State private var tab: Tab = .study
    @State private var legalDocument = Legal.documents.first?.title ?? ""

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Rectangle().fill(Palette.hairline).frame(width: 1)
            detail
        }
        .frame(width: 780, height: 560)
        .background(Palette.paper)
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                USUFUSeal(size: 30, tint: Palette.navy)
                VStack(alignment: .leading, spacing: 1) {
                    Text(L("Settings"))
                        .font(Face.display(15, .semibold))
                        .foregroundStyle(Palette.navy)
                    Text(Brand.initials)
                        .font(Face.ui(9, .semibold))
                        .tracking(1.2)
                        .foregroundStyle(Palette.textMuted)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 18)
            .padding(.bottom, 14)

            ForEach(Tab.allCases, id: \.self) { t in
                Button { tab = t } label: {
                    HStack(spacing: 9) {
                        Image(systemName: t.symbol)
                            .font(.system(size: 12))
                            .frame(width: 17)
                            .foregroundStyle(tab == t ? Palette.brass : Palette.textMuted)
                        Text(t.title)
                            .font(Face.ui(12, tab == t ? .semibold : .regular))
                            .foregroundStyle(Palette.text)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(tab == t ? Palette.brassSoft.opacity(0.35) : .clear)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .noFocusRing()
            }

            Spacer()

            Button(L("Done"), action: onClose)
                .buttonStyle(.plain)
                .font(Face.ui(12, .semibold))
                .foregroundStyle(Palette.navy)
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
        }
        .frame(width: 190)
        .background(Palette.paperDeep)
    }

    private var detail: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                switch tab {
                case .study: study
                case .customisation: customisation
                case .students: students
                case .storage: storage
                case .about: about
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var study: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 12) {
                heading(L("What this app is for, for you"),
                        L("Turn off the parts you are not using and they leave the "
                          + "sidebar entirely. Nothing is deleted: your sets, your "
                          + "progress, your decks and your notes are all still on "
                          + "this computer, and turning a part back on brings it "
                          + "back exactly as it was."))

                toggle(L("SAT practice"),
                       L("Your question sets, the practice screen, the statistics "
                         + "and the Import button. Off, the library goes with them "
                         + "— for a student using this only for vocabulary."),
                       get: { store.settings.showQuestionSets },
                       set: { store.settings.showQuestionSets = $0 })

                toggle(L("Flashcards"),
                       L("Your decks, the cards in them and the vocabulary test. "
                         + "Off, the Flashcards section goes — for a student who "
                         + "came here for the questions."),
                       get: { store.settings.showFlashcards },
                       set: { store.settings.showFlashcards = $0 })

                toggle(L("Learn in the sidebar"),
                       L("Short explanations of what each skill actually is. "
                         + "Articles are still reachable from a question you got "
                         + "wrong and from the statistics screen."),
                       get: { store.settings.showLearnInSidebar },
                       set: { store.settings.showLearnInSidebar = $0 })

                if !store.settings.showQuestionSets && !store.settings.showFlashcards {
                    Text(L("Both are off, so there is nothing to study. The sidebar "
                           + "says as much and points back here."))
                        .font(Face.ui(10))
                        .foregroundStyle(Palette.brass)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(26)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var customisation: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 14) {
                heading(L("Theme"), L("The organization's two papers. Whichever you "
                        + "pick, the test screen stays white — the real one is, and "
                        + "every figure in your PDFs is drawn on white. Stealth Mode "
                        + "below is the one thing that changes that."))

                HStack(spacing: 10) {
                    ForEach(Appearance.allCases, id: \.self) { option in
                        themeCard(option)
                    }
                }
                .disabled(store.settings.stealthMode)
                .opacity(store.settings.stealthMode ? 0.4 : 1)

                if store.settings.stealthMode {
                    Text(L("Stealth Mode is on, so the whole app is black and the "
                           + "paper below is not in use. Turn it off and you are "
                           + "back on the one you picked."))
                        .font(Face.ui(10))
                        .foregroundStyle(Palette.brass)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Rule()

            VStack(alignment: .leading, spacing: 12) {
                heading(L("Stealth Mode"),
                        L("For studying at night in a room where somebody else is "
                          + "asleep. One switch, because at that hour you should not "
                          + "have to find three."))

                toggle(L("Dark test screen, and nothing from this app makes a sound"),
                       L("The whole app is drawn on black — the test screen, the "
                         + "results, your highlights and the formula sheet included — "
                         + "and the figures from your PDFs are inverted so they are "
                         + "not the one bright thing left on the page. Reminders from "
                         + "this app are silenced, and none are shown at all while you "
                         + "are sitting a test. It changes nothing outside this app — "
                         + "if you want the whole computer quiet, that is a setting of "
                         + "its own."),
                       get: { store.settings.stealthMode },
                       set: { store.settings.stealthMode = $0 })

                if store.settings.stealthMode {
                    Text(L("The real test is on a white screen. Worth turning this off "
                           + "for a full practice test in the daytime, so test day is "
                           + "not the first time you see it."))
                        .font(Face.ui(10))
                        .foregroundStyle(Palette.brass)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Rule()

            VStack(alignment: .leading, spacing: 12) {
                heading(L("Language"), L("Four languages, the way the website does it. "
                        + "Anything not yet translated stays in English rather "
                        + "than showing a gap."))

                HStack(spacing: 8) {
                    ForEach(Language.allCases, id: \.self) { language in
                        Chip(title: "\(language.badge) · \(language.title)",
                             selected: store.settings.language == language) {
                            store.settings.language = language
                        }
                    }
                }
            }

            Rule()

            VStack(alignment: .leading, spacing: 12) {
                heading(L("What the app shows"),
                        L("The sidebar and the practice screen carry the same "
                          + "signposts on your first day and your two-hundredth. "
                          + "Turn off the ones you have stopped needing."))

                toggle(L("The Import button"),
                       L("Dragging a PDF onto the window still works, and the button "
                         + "comes back on its own if a question set is ever needed."),
                       get: { store.settings.showImportButton },
                       set: { store.settings.showImportButton = $0 })

                toggle(L("Keep a copy somewhere else"),
                       L("The card that offers to write everything of yours out as "
                         + "one file, and the reminder to do it. Turning it off does "
                         + "not stop you exporting — Storage below still will — it "
                         + "only stops the asking."),
                       get: { store.settings.showBackupCard },
                       set: { store.settings.showBackupCard = $0 })

                toggle(L("The page for a parent"),
                       L("A plain-language summary on the statistics screen, in "
                         + "whichever language is set, that can be saved as a "
                         + "one-page PDF. Off if there is nobody to show it to."),
                       get: { store.settings.showParentSummary },
                       set: { store.settings.showParentSummary = $0 })

                toggle(L("Study together"),
                       L("The card that sets up a sitting for two students on one "
                         + "computer. It only appears when there is more than one "
                         + "student on this computer anyway; turn it off and it "
                         + "will not appear at all."),
                       get: { store.settings.showDoubleMode },
                       set: { store.settings.showDoubleMode = $0 })
            }

            Rule()

            VStack(alignment: .leading, spacing: 12) {
                heading(L("Streaks"),
                        L("A run of days can be the thing that keeps you going or the "
                          + "thing you are afraid to break. Either one can be turned "
                          + "off on its own. The days themselves are still recorded, "
                          + "so turning a streak back on loses nothing."))

                toggle(L("The streak on the practice screen"),
                       L("Counted against the days in your study plan, where a "
                         + "planned rest day is skipped rather than failed."),
                       get: { store.settings.showQuestionStreak },
                       set: { store.settings.showQuestionStreak = $0 })

                toggle(L("The streak on a flashcard deck"),
                       L("Counted on the days you finish the words you were dealt."),
                       get: { store.settings.showVocabularyStreak },
                       set: { store.settings.showVocabularyStreak = $0 })
            }

            Rule()

            VStack(alignment: .leading, spacing: 12) {
                heading(L("Motion"), L("The app fades cards in, counts figures up and "
                        + "slides marks between choices. Turn it off if you would "
                        + "rather it just appeared."))

                Toggle(isOn: Binding(
                    get: { store.settings.reduceMotion },
                    set: { store.settings.reduceMotion = $0 })) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(L("Reduce motion in this app"))
                            .font(Face.ui(12))
                            .foregroundStyle(Palette.text)
                        Text(L("Takes effect straight away. The test screen never "
                               + "animated anyway — a sitting should feel like the "
                               + "real thing."))
                            .font(Face.ui(10))
                            .foregroundStyle(Palette.textMuted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .toggleStyle(.switch)

                if systemReducesMotion {
                    Text(L("macOS is set to Reduce Motion, so the app is already still "
                           + "whatever this is set to."))
                        .font(Face.ui(10))
                        .foregroundStyle(Palette.brass)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Rule()

            VStack(alignment: .leading, spacing: 12) {
                heading(L("Flashcards"), L("How the cards behave when you are going "
                        + "through a deck."))

                Toggle(isOn: Binding(
                    get: { store.settings.trackSkippedCards },
                    set: { store.settings.trackSkippedCards = $0 })) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(L("Count the words I skip past"))
                            .font(Face.ui(12))
                            .foregroundStyle(Palette.text)
                        Text(L("A word you go past without ever turning the card "
                               + "over goes into \"Words I skipped past\". Nothing else "
                               + "can tell you which of a long deck you have not really "
                               + "studied. Turn it off and the pile is hidden."))
                            .font(Face.ui(10))
                            .foregroundStyle(Palette.textMuted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .toggleStyle(.switch)

                if Motion.enabled {
                    Toggle(isOn: Binding(
                        get: { store.settings.flashcardFlipAnimation },
                        set: { store.settings.flashcardFlipAnimation = $0 })) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(L("Turn the card with an animation"))
                                .font(Face.ui(12))
                                .foregroundStyle(Palette.text)
                            Text(L("Also switchable from the corner of the card itself, "
                                   + "which is where you will want it mid-run."))
                                .font(Face.ui(10))
                                .foregroundStyle(Palette.textMuted)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .toggleStyle(.switch)
                } else {
                    Text(L("Reduce motion is on, so cards turn without an "
                           + "animation. Turn it off above and the choice comes back."))
                        .font(Face.ui(10))
                        .foregroundStyle(Palette.brass)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Rule()

            VStack(alignment: .leading, spacing: 8) {
                heading(L("Your daily target"), nil)
                Text(L("The ring on the practice screen, and the days you have set "
                       + "aside, are part of your study plan — press Plan beside the "
                       + "ring to change them. They are kept there rather than here "
                       + "because they are something you look at while deciding what "
                       + "to practice."))
                    .font(Face.ui(11))
                    .foregroundStyle(Palette.textMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var systemReducesMotion: Bool {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }

    private func themeCard(_ option: Appearance) -> some View {
        let selected = store.settings.appearance == option
        return Button {
            store.settings.appearance = option
        } label: {
            VStack(spacing: 9) {
                ZStack {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(preview(option).ground)
                    VStack(spacing: 4) {
                        USUFUSeal(size: 26, tint: preview(option).ink)
                        RoundedRectangle(cornerRadius: 1)
                            .fill(preview(option).ink.opacity(0.75))
                            .frame(width: 52, height: 3)
                        RoundedRectangle(cornerRadius: 1)
                            .fill(preview(option).ink.opacity(0.4))
                            .frame(width: 34, height: 3)
                    }
                }
                .frame(height: 96)
                .overlay(RoundedRectangle(cornerRadius: 4)
                    .strokeBorder(selected ? Palette.brass : Palette.hairline,
                                  lineWidth: selected ? 2 : 1))

                VStack(spacing: 2) {
                    Text(option.title)
                        .font(Face.ui(12, selected ? .semibold : .regular))
                        .foregroundStyle(Palette.text)
                    Text(option.detail)
                        .font(Face.ui(9.5))
                        .foregroundStyle(Palette.textMuted)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func preview(_ option: Appearance) -> (ground: Color, ink: Color) {
        let beige = (ground: Color(red: 0.957, green: 0.941, blue: 0.910),
                     ink: Color(red: 0.106, green: 0.165, blue: 0.290))
        let navy = (ground: Color(red: 0.055, green: 0.086, blue: 0.161),
                    ink: Color(red: 0.949, green: 0.929, blue: 0.878))
        switch option {
        case .light: return beige
        case .dark: return navy
        case .system:
            return NSApp.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
                ? navy : beige
        }
    }

    private var students: some View {
        VStack(alignment: .leading, spacing: 14) {
            heading(L("Students on this computer"),
                    L("Many families share one computer. Each student here keeps "
                      + "their own progress, statistics, notes and flashcard decks, "
                      + "and their own language and theme. Question sets are shared, "
                      + "so a set only has to be imported once — and it is the part "
                      + "that takes the disk space."))
            ProfilesPanel()
            Rule()
            heading(L("Moving between computers"),
                    L("A student using a library computer one day and a laptop the "
                      + "next should not have to start again. Export this student "
                      + "to a small file — it fits in an email — and import it on "
                      + "the other computer."))
            PortablePanel()
            Rule()
            Text(L("Profiles are not password-protected — anyone using this computer can open any of them. They exist so two students do not overwrite each other's work, not to keep it private."))
                .font(Face.ui(11))
                .foregroundStyle(Palette.textMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var storage: some View {
        VStack(alignment: .leading, spacing: 14) {
            heading(L("Where everything is kept"),
                    L("Question sets, progress, highlights, notes, saved sittings and "
                      + "your imported PDFs all live in one folder. Copy it to back "
                      + "everything up."))

            Text(store.root.path)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(Palette.text)
                .textSelection(.enabled)
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Palette.subtleFill)
                .clipShape(RoundedRectangle(cornerRadius: 3))

            BluebookButton(title: L("Open this folder"), style: .plain) {
                NSWorkspace.shared.open(store.root)
            }

            Rule()

            heading(L("What is in it"),
                    L("Nearly all of it is the figures drawn out of your PDFs. A set "
                      + "can be removed from the practice screen, under the PDFs it "
                      + "was built from."))
            VStack(alignment: .leading, spacing: 5) {
                ForEach(store.banks) { bank in
                    HStack {
                        Text(bank.name)
                            .font(Face.ui(11))
                            .foregroundStyle(Palette.text)
                        Spacer(minLength: 12)
                        Text(Lf("%d questions", bank.questions.count))
                            .font(Face.ui(11))
                            .foregroundStyle(Palette.textMuted)
                        Text(Format.fileSize(store.sizeOnDisk(of: bank.id)))
                            .font(Face.ui(11, .semibold))
                            .monospacedDigit()
                            .foregroundStyle(Palette.brass)
                            .frame(width: 66, alignment: .trailing)
                    }
                }
                if !store.banks.isEmpty {
                    Rule().padding(.vertical, 3)
                    HStack {
                        Text(L("Everything in this folder"))
                            .font(Face.ui(11, .semibold))
                            .foregroundStyle(Palette.text)
                        Spacer(minLength: 12)
                        Text(Format.fileSize(store.sizeOnDisk()))
                            .font(Face.ui(11, .semibold))
                            .monospacedDigit()
                            .foregroundStyle(Palette.navy)
                            .frame(width: 66, alignment: .trailing)
                    }
                }
                if store.banks.isEmpty {
                    Text(L("No question sets yet."))
                        .font(Face.ui(11))
                        .foregroundStyle(Palette.textMuted)
                }
            }
        }
    }

    private var about: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 14) {
                USUFUSeal(size: 64, tint: Palette.navy)
                VStack(alignment: .leading, spacing: 3) {
                    Text(Brand.appName)
                        .font(Face.display(17, .semibold))
                        .foregroundStyle(Palette.navy)
                    Text(Brand.organisation)
                        .font(Face.ui(11))
                        .foregroundStyle(Palette.text)
                    Text(Brand.slogan)
                        .font(Face.ui(11))
                        .italic()
                        .foregroundStyle(Palette.brass)
                    if let version = Bundle.main
                        .object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String {
                        Text(Lf("Version %@", version))
                            .font(Face.ui(10))
                            .foregroundStyle(Palette.textMuted)
                            .padding(.top, 2)
                    }
                }
            }

            Rule()

            Text(L("The small print"))
                .font(Face.display(14, .semibold))
                .foregroundStyle(Palette.navy)

            HStack(spacing: 8) {
                ForEach(Legal.documents) { document in
                    Chip(title: document.title, selected: legalDocument == document.title) {
                        withAnimation(Motion.quick) { legalDocument = document.title }
                    }
                }
            }

            if let document = Legal.documents.first(where: { $0.title == legalDocument }) {
                VStack(alignment: .leading, spacing: 14) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(document.summary)
                            .font(Face.ui(11))
                            .foregroundStyle(Palette.textMuted)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(Lf("Last updated: %@.", Legal.lastUpdated))
                            .font(Face.ui(10))
                            .foregroundStyle(Palette.textMuted)
                    }

                    ForEach(document.sections) { section in
                        VStack(alignment: .leading, spacing: 5) {
                            Text(section.title)
                                .font(Face.ui(11, .semibold))
                                .foregroundStyle(Palette.navy)
                            ForEach(Array(section.paragraphs.enumerated()), id: \.offset) { _, line in
                                Text(line)
                                    .font(Face.ui(11))
                                    .foregroundStyle(Palette.text)
                                    .lineSpacing(3)
                                    .fixedSize(horizontal: false, vertical: true)
                                    .textSelection(.enabled)
                            }
                        }
                    }
                }
            }

            Rule()
            Text(Legal.copyright)
                .font(Face.ui(10))
                .foregroundStyle(Palette.textMuted)
        }
    }

    private func toggle(_ title: String, _ detail: String,
                        get: @escaping () -> Bool,
                        set: @escaping (Bool) -> Void) -> some View {
        Toggle(isOn: Binding(get: get, set: set)) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(Face.ui(12))
                    .foregroundStyle(Palette.text)
                Text(detail)
                    .font(Face.ui(10))
                    .foregroundStyle(Palette.textMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .toggleStyle(.switch)
    }

    private func heading(_ title: String, _ detail: String?) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(Face.display(14, .semibold))
                .foregroundStyle(Palette.navy)
            if let detail {
                Text(detail)
                    .font(Face.ui(11))
                    .foregroundStyle(Palette.textMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
