import SwiftUI
import UniformTypeIdentifiers
import AppKit

struct HomeView: View {
    @EnvironmentObject var store: AppStore
    @EnvironmentObject var intro: IntroState

    enum Tab: String, CaseIterable {
        case practise, statistics, history
        var title: String {
            switch self {
            case .practise: return L("Practice")
            case .statistics: return L("Statistics")
            case .history: return L("History")
            }
        }
    }

    @State private var tab: Tab = .practise

    @State private var isTargeted = false
    @State private var renaming: Bank?
    @State private var renameText = ""
    @State private var confirmDelete: Bank?
    @Namespace private var bankMark
    @State private var hoveredBank: String?
    @State private var unfinished: Set<String> = []
    @State private var renamingShelf: Shelf?
    @State private var shelfRenameText = ""
    @State private var draggingOver: String?
    @State private var showOrderPicker = false
    @State private var showSettings = false
    @State private var showAbout = false
    @State private var returning: AppStore.WelcomeBack?
    @State private var hoveredDeck: UUID?
    @State private var renamingDeck: Deck?
    @State private var deckRenameText = ""
    @State private var confirmDeleteDeck: Deck?
    @State private var deckDividerHot = false

    private struct HandleDrag: Equatable {
        var startY: Double
        var above: Double
        var below: Double
    }
    @State private var handleDrag: HandleDrag?

    var body: some View {
        HSplitView {
            sidebar
                .frame(minWidth: 250, idealWidth: 280, maxWidth: 360)
            detail
                .frame(minWidth: 520)
        }
        .onDrop(of: [.fileURL], isTargeted: $isTargeted) { providers in
            handleDrop(providers)
            return true
        }
        .overlay {
            if isTargeted {
                ZStack {
                    Palette.brassSoft.opacity(0.22)
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(Palette.brass, style: StrokeStyle(lineWidth: 2.5, dash: [9, 6]))
                        .padding(8)
                    Text(L("Drop the PDF to import it"))
                        .font(Face.display(16, .semibold))
                        .foregroundStyle(Palette.navy)
                        .padding(.horizontal, 22).padding(.vertical, 12)
                        .background(Palette.card)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                .allowsHitTesting(false)
                .transition(.opacity)
            }
        }
        .animation(Motion.quick, value: isTargeted)
        .overlay {
            if let progress = store.importing { importOverlay(progress) }
        }
        .alert(L("Rename question set"), isPresented: Binding(
            get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField(L("Name"), text: $renameText)
            Button(L("Cancel"), role: .cancel) { renaming = nil }
            Button(L("Save")) {
                if let b = renaming, !renameText.trimmingCharacters(in: .whitespaces).isEmpty {
                    store.renameBank(b, to: renameText.trimmingCharacters(in: .whitespaces))
                }
                renaming = nil
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .usufuOpenSettings)) { _ in
            showSettings = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .usufuOpenAbout)) { _ in
            showAbout = true
        }
        .onAppear {
            returning = store.welcomeBack()
            refreshUnfinished()
        }
        .onChange(of: store.session?.id) { _ in refreshUnfinished() }
        .onChange(of: store.banks.count) { _ in refreshUnfinished() }
        .onChange(of: store.profile.id) { _ in refreshUnfinished() }
        .onChange(of: store.savedSessionsRevision) { _ in refreshUnfinished() }
        .sheet(isPresented: $showAbout) {
            AboutPanel { showAbout = false }
        }
        .sheet(isPresented: $showSettings) {
            SettingsView { showSettings = false }.environmentObject(store)
        }
        .alert(L("Rename shelf"), isPresented: Binding(
            get: { renamingShelf != nil }, set: { if !$0 { renamingShelf = nil } })) {
            TextField(L("Name"), text: $shelfRenameText)
            Button(L("Cancel"), role: .cancel) { renamingShelf = nil }
            Button(L("Save")) {
                if let shelf = renamingShelf { store.renameShelf(shelf.id, to: shelfRenameText) }
                renamingShelf = nil
            }
        }
        .alert(L("Delete this question set?"), isPresented: Binding(
            get: { confirmDelete != nil }, set: { if !$0 { confirmDelete = nil } })) {
            Button(L("Cancel"), role: .cancel) { confirmDelete = nil }
            Button(L("Delete"), role: .destructive) {
                if let b = confirmDelete { store.deleteBank(b) }
                confirmDelete = nil
            }
        } message: {
            Text(L("The imported questions and your progress for this set will be removed. The original PDF is not touched."))
        }
        .alert(L("Rename deck"), isPresented: Binding(
            get: { renamingDeck != nil }, set: { if !$0 { renamingDeck = nil } })) {
            TextField(L("Name"), text: $deckRenameText)
            Button(L("Cancel"), role: .cancel) { renamingDeck = nil }
            Button(L("Save")) {
                if let d = renamingDeck { store.renameDeck(d.id, to: deckRenameText) }
                renamingDeck = nil
            }
        }
        .alert(L("Delete this deck?"), isPresented: Binding(
            get: { confirmDeleteDeck != nil }, set: { if !$0 { confirmDeleteDeck = nil } })) {
            Button(L("Cancel"), role: .cancel) { confirmDeleteDeck = nil }
            Button(L("Delete"), role: .destructive) {
                if let d = confirmDeleteDeck { store.deleteDeck(d.id) }
                confirmDeleteDeck = nil
            }
        } message: {
            Text(L("The cards in it are removed. Your question sets are not touched."))
        }
    }

    @Namespace private var tabMark
    @State private var hoveredTab: Tab?

    private var tabBar: some View {
        HStack(spacing: 0) {
            ForEach(Tab.allCases, id: \.self) { t in
                Button {
                    withAnimation(Motion.settle) { tab = t }
                } label: {
                    VStack(spacing: 7) {
                        Text(t.title)
                            .font(Face.ui(12, tab == t ? .semibold : .regular))
                            .foregroundStyle(tab == t ? Palette.navy
                                             : (hoveredTab == t ? Palette.text : Palette.textMuted))
                        ZStack {
                            Rectangle().fill(Color.clear).frame(height: 2)
                            if tab == t {
                                Rectangle().fill(Palette.brass).frame(height: 2)
                                    .matchedGeometryEffect(id: "tabMark", in: tabMark)
                            }
                        }
                    }
                    .padding(.horizontal, 18)
                    .padding(.top, 8)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .onHover { hoveredTab = $0 ? t : nil }
            }
            Spacer()
        }
        .padding(.horizontal, 16)
        .background(Palette.card)
        .animation(Motion.quick, value: hoveredTab)
    }

    private var sidebar: some View {
        VStack(spacing: 0) {
            masthead

            if let returning {
                WelcomeBackBanner(welcome: returning) {
                    store.dismissWelcomeBack(returning)
                    withAnimation(Motion.quick) { self.returning = nil }
                }
                .transition(.opacity)
            }

            if !store.damagedFiles.isEmpty {
                DamagedFilesNotice {
                    withAnimation(Motion.quick) { store.damagedFiles = [] }
                }
                .transition(.opacity)
            }

            Rule()

            if store.settings.showQuestionSets {
                shelfBar
            }

            panesRegion

            if store.settings.showLearnInSidebar {
                Rule()
                learnSection
            }

            if store.settings.showQuestionSets,
               store.settings.showImportButton || store.banks.isEmpty {
                Rule()
                VStack(spacing: 9) {
                    BluebookButton(title: L("Import question bank PDF…")) { chooseFiles() }
                        .frame(maxWidth: .infinity)
                    Text(L("or drag PDFs into this window"))
                        .font(Face.ui(10))
                        .foregroundStyle(Palette.textMuted)
                }
                .padding(16)
            }

            if store.profiles.profiles.count > 1 {
                Rule()
                ProfileBar()
            }

            Rule()
            colophon
        }
        .background(isTargeted ? Palette.brassSoft : Palette.paperDeep)
        .animation(Motion.standard, value: isTargeted)
    }

    private func refreshUnfinished() {
        unfinished = Set(store.setsWithSavedSittings().map(\.bank.id))
    }

    private var masthead: some View {
        HStack(spacing: 0) {
        Button { showAbout = true } label: {
        HStack(alignment: .center, spacing: 12) {
            USUFUSeal(size: 54, tint: Palette.navy)
                .introLandingSeal(intro)
            VStack(alignment: .leading, spacing: 5) {
                HStack(alignment: .firstTextBaseline, spacing: 7) {
                    Text(Brand.initials)
                        .font(Face.display(19, .semibold))
                        .tracking(1.4)
                        .foregroundStyle(Palette.navy)
                    if Brand.isPrerelease {
                        Text(Brand.stage)
                            .font(Face.ui(8.5, .semibold))
                            .tracking(1.1)
                            .foregroundStyle(Palette.brass)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .overlay(
                                RoundedRectangle(cornerRadius: 3)
                                    .strokeBorder(Palette.brass.opacity(0.55), lineWidth: 1)
                            )
                            .help(L("This is a test version. Your work is kept as usual."))
                    }
                }
                Text(Brand.slogan)
                    .font(Face.ui(9.5))
                    .italic()
                    .tracking(0.2)
                    .foregroundStyle(Palette.textMuted)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(L("About this app, and United States Universities For Ukraine"))
        .noFocusRing()
        Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.top, WindowChrome.trafficLights + 8)
        .padding(.bottom, 15)
    }

    private var shelfBar: some View {
        HStack(spacing: 6) {
            SectionLabel(text: L("Library"))
            Spacer(minLength: 0)

            Button { showOrderPicker.toggle() } label: {
                Image(systemName: store.layout.order.symbol)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Palette.textMuted)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .iconHelp(Lf("How the sets are ordered — currently %@",
                     store.layout.order.title.prefix(1).lowercased() + store.layout.order.title.dropFirst()))
            .popover(isPresented: $showOrderPicker, arrowEdge: .bottom) {
                orderPicker
            }

            Button {
                withAnimation(Motion.settle) { store.addShelf() }
            } label: {
                Image(systemName: "plus.rectangle.on.folder")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Palette.textMuted)
            }
            .buttonStyle(.plain)
            .iconHelp(L("New shelf"))
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 2)
    }

    private var orderPicker: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionLabel(text: L("Order the sets by"))
                .padding(.horizontal, 16)
                .padding(.top, 14)
                .padding(.bottom, 8)

            ForEach(ShelfOrder.allCases, id: \.self) { order in
                Button {
                    var next = store.layout
                    next.order = order
                    withAnimation(Motion.settle) { store.layout = next }
                    showOrderPicker = false
                } label: {
                    HStack(spacing: 9) {
                        Image(systemName: order.symbol)
                            .font(.system(size: 11))
                            .frame(width: 16)
                            .foregroundStyle(store.layout.order == order
                                             ? Palette.brass : Palette.textMuted)
                        Text(order.title)
                            .font(Face.ui(12, store.layout.order == order ? .semibold : .regular))
                            .foregroundStyle(Palette.text)
                        Spacer(minLength: 12)
                        if store.layout.order == order {
                            Image(systemName: "checkmark")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(Palette.brass)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 7)
                    .contentShape(Rectangle())
                    .background(store.layout.order == order
                                ? Palette.brassSoft.opacity(0.35) : Color.clear)
                }
                .buttonStyle(.plain)
            }

            Text(L("Sorting never overwrites the order you arranged by hand — "
                 + "switch back and it returns."))
                .font(Face.ui(10))
                .foregroundStyle(Palette.textMuted)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 16)
                .padding(.top, 10)
                .padding(.bottom, 14)
        }
        .frame(width: 268)
        .background(Palette.card)
    }

    @ViewBuilder
    private func shelfSection(_ section: AppStore.Shelved) -> some View {
        let collapsed = section.shelf?.collapsed ?? false
        VStack(alignment: .leading, spacing: 3) {
            shelfHeading(section, collapsed: collapsed)

            if !collapsed {
                if section.banks.isEmpty {
                    Text(section.shelf == nil
                         ? L("Everything is on a shelf.")
                         : L("Empty — drag a set here, or use its menu."))
                        .font(Face.ui(10))
                        .foregroundStyle(Palette.textMuted.opacity(0.8))
                        .padding(.horizontal, 20)
                        .padding(.vertical, 7)
                } else {
                    ForEach(section.banks) { bank in
                        bankRow(bank)
                    }
                }
            }
        }
        .padding(.bottom, 4)
        .dropDestination(for: String.self) { ids, _ in
            guard let id = ids.first else { return false }
            withAnimation(Motion.settle) {
                store.move(bank: id, toShelf: section.shelf?.id)
            }
            return true
        } isTargeted: { targeted in
            draggingOver = targeted ? section.id : nil
        }
        .background(draggingOver == section.id
                    ? Palette.brassSoft.opacity(0.5) : Color.clear)
    }

    private func shelfHeading(_ section: AppStore.Shelved, collapsed: Bool) -> some View {
        HStack(spacing: 6) {
            if let shelf = section.shelf {
                Button {
                    withAnimation(Motion.settle) {
                        store.setShelfCollapsed(shelf.id, !collapsed)
                    }
                } label: {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 8, weight: .bold))
                        .rotationEffect(.degrees(collapsed ? 0 : 90))
                        .foregroundStyle(Palette.textMuted)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(collapsed ? L("Show") : L("Hide"))
            } else {
                Image(systemName: "tray")
                    .font(.system(size: 9))
                    .foregroundStyle(Palette.textMuted.opacity(0.7))
            }

            Text(section.title)
                .font(Face.ui(10, .semibold))
                .tracking(0.9)
                .foregroundStyle(Palette.textMuted)
                .lineLimit(1)

            if !section.banks.isEmpty {
                Text("\(section.banks.count)")
                    .font(Face.ui(9))
                    .foregroundStyle(Palette.textMuted.opacity(0.75))
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 5)
        .contentShape(Rectangle())
        .contextMenu {
            if let shelf = section.shelf {
                Button(L("Rename shelf…")) {
                    shelfRenameText = shelf.name
                    renamingShelf = shelf
                }
                Button(L("Move up")) { store.moveShelf(shelf.id, by: -1) }
                Button(L("Move down")) { store.moveShelf(shelf.id, by: 1) }
                Divider()
                Button(L("Remove shelf"), role: .destructive) {
                    withAnimation(Motion.settle) { store.removeShelf(shelf.id) }
                }
                Text(L("The sets on it are kept — they go back to Unshelved."))
            } else {
                Button(L("New shelf")) { store.addShelf() }
            }
        }
    }

    private var colophon: some View {
        VStack(spacing: 9) {
            Text(Brand.slogan)
                .font(.system(size: 10, weight: .regular, design: .serif))
                .italic()
                .foregroundStyle(Palette.textMuted)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            Button { showSettings = true } label: {
                HStack(spacing: 5) {
                    Image(systemName: "gearshape")
                        .font(.system(size: 10))
                    Text(L("Settings"))
                        .font(Face.ui(10.5))
                }
                .foregroundStyle(Palette.textMuted)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Text(Legal.footprint)
                .font(Face.ui(9))
                .foregroundStyle(Palette.textMuted.opacity(0.75))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    private var emptySidebar: some View {
        VStack(spacing: 10) {
            Spacer()
            if store.loadFailures.isEmpty {
                Image(systemName: "doc.text.magnifyingglass")
                    .font(.system(size: 26))
                    .foregroundStyle(Palette.border)
                Text(L("No question sets yet"))
                    .font(Face.display(14, .semibold))
                    .foregroundStyle(Palette.text)
                Text(L("Import a PDF exported from the College Board Question Bank — SAT or PSAT."))
                    .font(Face.ui(11))
                    .foregroundStyle(Palette.textMuted)
            } else {
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 26))
                    .foregroundStyle(Palette.brass)
                Text(Lf("%d question set(s) could not be read", store.loadFailures.count))
                    .font(Face.display(14, .semibold))
                    .foregroundStyle(Palette.text)
                    .multilineTextAlignment(.center)
                Text(L("Your files are still on disk. Re-importing the original PDF will rebuild the set."))
                    .font(Face.ui(11))
                    .foregroundStyle(Palette.textMuted)
            }
            Spacer()
        }
        .multilineTextAlignment(.center)
        .padding(.horizontal, 24)
    }

    private func bankRow(_ bank: Bank) -> some View {
        bankRowBody(bank).id(bank.id)
    }

    private func bankRowBody(_ bank: Bank) -> some View {
        let prog = store.progress[bank.id] ?? BankProgress(bankID: bank.id)
        let selected = store.config.bankID == bank.id
        let fraction = bank.questions.isEmpty ? 0
            : Double(prog.seenCount) / Double(bank.questions.count)
        return Button {
            store.config.bankID = bank.id
            store.selectedDeckID = nil
        } label: {
            HStack(spacing: 0) {
                ZStack {
                    Rectangle().fill(Color.clear).frame(width: 2)
                    if selected {
                        Rectangle().fill(Palette.brass).frame(width: 2)
                            .matchedGeometryEffect(id: "bankMark", in: bankMark)
                    }
                }
                .frame(width: 2)
                VStack(alignment: .leading, spacing: 6) {
                    Text(bank.name)
                        .font(Face.ui(13, .medium))
                        .foregroundStyle(Palette.text)
                        .lineLimit(1)
                    HStack(spacing: 6) {
                        Text(Lf("%1$d questions · %2$d seen",
                                bank.questions.count, prog.seenCount))
                            .font(Face.ui(10))
                            .foregroundStyle(Palette.textMuted)
                        if unfinished.contains(bank.id) {
                            Text(L("paused"))
                                .font(Face.ui(8.5, .semibold))
                                .tracking(0.4)
                                .foregroundStyle(Palette.brass)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1)
                                .background(Capsule().fill(Palette.brassSoft.opacity(0.55)))
                                .help(L("You have a test in progress in this set"))
                        }
                    }
                    GrowingBar(value: fraction, tint: Palette.brass.opacity(0.75),
                               track: Palette.hairline, height: 2)
                }
                .padding(.vertical, 10)
                .padding(.horizontal, 14)
                Spacer(minLength: 0)
            }
            .background(selected ? Palette.card
                        : (hoveredBank == bank.id ? Palette.paper.opacity(0.5) : Color.clear))
            .overlay(alignment: .trailing) {
                if selected { Rectangle().fill(Palette.hairline).frame(width: 1) }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 0)
        .simultaneousGesture(TapGesture(count: 2).onEnded {
            renameText = bank.name
            renaming = bank
        })
        .onHover { hoveredBank = $0 ? bank.id : nil }
        .animation(Motion.quick, value: hoveredBank)
        .draggable(bank.id)
        .contextMenu {
            Button(L("Rename…")) { renameText = bank.name; renaming = bank }
            Button(L("Add another PDF to this set…")) { chooseFiles(into: bank.id) }
            Divider()
            Menu(L("Move to shelf")) {
                ForEach(store.layout.shelves) { shelf in
                    Button(shelf.name) {
                        withAnimation(Motion.settle) {
                            store.move(bank: bank.id, toShelf: shelf.id)
                        }
                    }
                    .disabled(shelf.bankIDs.contains(bank.id))
                }
                if !store.layout.shelves.isEmpty { Divider() }
                Button(L("Unshelved")) {
                    withAnimation(Motion.settle) { store.move(bank: bank.id, toShelf: nil) }
                }
                .disabled(store.layout.shelf(of: bank.id) == nil)
                Divider()
                Button(L("New shelf…")) {
                    store.addShelf()
                    if let shelf = store.layout.shelves.last {
                        store.move(bank: bank.id, toShelf: shelf.id)
                        shelfRenameText = shelf.name
                        renamingShelf = shelf
                    }
                }
            }
            Button(L("Move up")) { store.move(bank: bank.id, by: -1) }
                .disabled(!store.layout.order.isManual)
            Button(L("Move down")) { store.move(bank: bank.id, by: 1) }
                .disabled(!store.layout.order.isManual)
            Divider()
            Button(L("Reset my progress")) {
                store.progress[bank.id] = BankProgress(bankID: bank.id)
            }
            Button(L("Delete"), role: .destructive) { confirmDelete = bank }
        }
    }

    private var learnSection: some View {
        Button { store.openLearn() } label: {
            HStack(spacing: 8) {
                Image(systemName: "book")
                    .font(.system(size: 11))
                    .foregroundStyle(Palette.brass)
                VStack(alignment: .leading, spacing: 1) {
                    Text(L("Learn"))
                        .font(Face.ui(12, .semibold))
                        .foregroundStyle(Palette.text)
                    Text(L("How each skill works"))
                        .font(Face.ui(9.5))
                        .foregroundStyle(Palette.textMuted)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 11)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var panesRegion: some View {
        if store.settings.showQuestionSets && store.settings.showFlashcards {
            GeometryReader { geo in
                let panes = dividedPanes(in: geo.size.height)
                VStack(spacing: 0) {
                    librarySection
                        .frame(height: panes.above)
                    deckDivider(panes)
                    deckSection
                        .frame(height: panes.below)
                }
                .frame(width: geo.size.width, height: geo.size.height, alignment: .top)
                .coordinateSpace(name: Self.dragSpace)
            }
        } else if store.settings.showQuestionSets {
            librarySection
        } else if store.settings.showFlashcards {
            deckSection
        } else {
            nothingChosen
        }
    }

    private var nothingChosen: some View {
        VStack(spacing: 12) {
            Spacer(minLength: 0)
            Image(systemName: "square.dashed")
                .font(.system(size: 24))
                .foregroundStyle(Palette.border)
            Text(L("Nothing to study yet"))
                .font(Face.display(13, .semibold))
                .foregroundStyle(Palette.text)
            Text(L("Please choose what you want to study in Settings — SAT practice, "
                   + "flashcards, or both. Nothing of yours has been deleted."))
                .font(Face.ui(11))
                .foregroundStyle(Palette.textMuted)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Button { showSettings = true } label: {
                HStack(spacing: 5) {
                    Image(systemName: "gearshape")
                        .font(.system(size: 10))
                    Text(L("Open Settings"))
                        .font(Face.ui(11, .medium))
                }
                .foregroundStyle(Palette.brass)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 22)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private var librarySection: some View {
        if store.banks.isEmpty && store.layout.shelves.isEmpty {
            emptySidebar
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(store.shelved()) { section in
                            shelfSection(section)
                        }
                        Spacer(minLength: 8)
                    }
                    .padding(.top, 6)
                }
                .onChange(of: store.config.bankID) { id in
                    withAnimation(Motion.standard) { proxy.scrollTo(id) }
                }
            }
        }
    }

    private static let dragSpace = "usufu.sidebar.panes"

    private static let deckRowHeight: Double = 47
    private static let deckChrome: Double = 33 + 6
    private static let handleHeight: Double = 14
    private static let minLibraryHeight: Double = 72
    private static var minDeckHeight: Double { deckChrome + deckRowHeight }
    private static let deckInviteHeight: Double = 33 + 26

    private var naturalDeckHeight: Double {
        min(Double(max(store.decks.count, 1)) * Self.deckRowHeight, 168) + Self.deckChrome
    }

    private func dividedPanes(in region: Double) -> (above: Double, below: Double) {
        guard !store.decks.isEmpty else {
            let below = min(Self.deckInviteHeight, max(region - 1, 0))
            return (max(region - 1 - below, 0), below)
        }
        return SidebarPanes.divide(span: max(region - Self.handleHeight, 0),
                                   stored: store.settings.libraryPaneHeight,
                                   floorAbove: Self.minLibraryHeight,
                                   floorBelow: Self.minDeckHeight,
                                   naturalAbove: max(region - Self.handleHeight
                                                     - naturalDeckHeight, 0))
    }

    @ViewBuilder
    private func deckDivider(_ panes: (above: Double, below: Double)) -> some View {
        if store.decks.isEmpty {
            Rule()
        } else {
            handle(panes)
        }
    }

    private func handle(_ panes: (above: Double, below: Double)) -> some View {
        ZStack {
            Rule()
            RoundedRectangle(cornerRadius: 1)
                .fill(Palette.border)
                .frame(width: 34, height: 3)
                .opacity(deckDividerHot ? 1 : 0)
        }
        .frame(height: Self.handleHeight)
        .contentShape(Rectangle())
        .onHover { inside in
            deckDividerHot = inside
            if inside {
                SidebarPanes.cursor(above: panes.above, below: panes.below,
                                    floorAbove: Self.minLibraryHeight,
                                    floorBelow: Self.minDeckHeight).set()
            } else {
                NSCursor.arrow.set()
            }
        }
        .gesture(
            DragGesture(minimumDistance: 1, coordinateSpace: .named(Self.dragSpace))
                .onChanged { g in
                    let pinned: HandleDrag
                    if let held = handleDrag, held.startY == g.startLocation.y {
                        pinned = held
                    } else {
                        pinned = HandleDrag(startY: g.startLocation.y,
                                            above: panes.above, below: panes.below)
                        handleDrag = pinned
                    }
                    let moved = SidebarPanes.boundary(
                        above: pinned.above, below: pinned.below,
                        floorAbove: Self.minLibraryHeight,
                        floorBelow: Self.minDeckHeight,
                        by: g.translation.height)
                    store.settings.libraryPaneHeight = moved.above
                }
                .onEnded { _ in handleDrag = nil }
        )
        .onTapGesture(count: 2) {
            withAnimation(Motion.settle) { store.settings.libraryPaneHeight = nil }
        }
        .help(L("Drag to resize · double-click to fit"))
        .animation(Motion.quick, value: deckDividerHot)
    }

    private var deckSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                SectionLabel(text: L("Flashcards"))
                Spacer(minLength: 0)
                Button {
                    _ = store.addDeck()
                } label: {
                    Image(systemName: "plus.rectangle.on.rectangle")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(Palette.textMuted)
                }
                .buttonStyle(.plain)
                .iconHelp(L("New deck"))
            }
            .padding(.horizontal, 16)
            .padding(.top, 13)
            .padding(.bottom, 7)

            if store.decks.isEmpty {
                Button {
                    _ = store.addDeck()
                } label: {
                    Text(L("Make a deck of vocabulary"))
                        .font(Face.ui(11))
                        .foregroundStyle(Palette.textMuted)
                        .padding(.horizontal, 16)
                        .padding(.bottom, 13)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 0) {
                            ForEach(store.decks) { deck in deckRow(deck).id(deck.id) }
                        }
                    }
                    .onChange(of: store.selectedDeckID) { id in
                        if let id { withAnimation(Motion.standard) { proxy.scrollTo(id) } }
                    }
                }
                .frame(maxHeight: .infinity)
                .padding(.bottom, 6)
            }
        }
    }

    private func deckRow(_ deck: Deck) -> some View {
        let selected = store.selectedDeckID == deck.id
        return Button {
            store.selectedDeckID = deck.id
        } label: {
            HStack(spacing: 0) {
                Rectangle()
                    .fill(selected ? Palette.brass : Color.clear)
                    .frame(width: 2)
                    .animation(Motion.quick, value: selected)
                VStack(alignment: .leading, spacing: 3) {
                    Text(deck.name)
                        .font(Face.ui(12.5, .medium))
                        .foregroundStyle(Palette.text)
                        .lineLimit(1)
                    Text(Lp(deck.cards.count, "%d card", "%d cards"))
                        .font(Face.ui(10))
                        .foregroundStyle(Palette.textMuted)
                }
                .padding(.vertical, 8)
                .padding(.horizontal, 14)
                Spacer(minLength: 0)
                if deck.starredCount > 0 {
                    Image(systemName: "star.fill")
                        .font(.system(size: 8))
                        .foregroundStyle(Palette.brass.opacity(0.8))
                        .padding(.trailing, 12)
                }
            }
            .background(selected ? Palette.card
                        : (hoveredDeck == deck.id ? Palette.paper.opacity(0.5) : Color.clear))
            .overlay(alignment: .trailing) {
                if selected { Rectangle().fill(Palette.hairline).frame(width: 1) }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hoveredDeck = $0 ? deck.id : nil }
        .animation(Motion.quick, value: hoveredDeck)
        .contextMenu {
            Button(L("Rename…")) {
                deckRenameText = deck.name
                renamingDeck = deck
            }
            Divider()
            Button(L("Delete"), role: .destructive) { confirmDeleteDeck = deck }
        }
    }

    @ViewBuilder
    private var detail: some View {
        if store.settings.showFlashcards, let deck = store.selectedDeck {
            DeckView(deck: deck)
        } else if store.settings.showQuestionSets,
                  let bank = store.bank(store.config.bankID) {
            VStack(spacing: 0) {
                tabBar
                Rule()
                ZStack {
                    switch tab {
                    case .practise:
                        SetupView(bank: bank)
                            .transition(.opacity)
                    case .statistics:
                        StatisticsView(bank: bank)
                            .transition(.opacity)
                    case .history:
                        HistoryView(bank: bank)
                            .transition(.opacity)
                    }
                }
                .animation(Motion.standard, value: tab)
                .id(bank.id)
            }
        } else {
            welcome
        }
    }

    @ViewBuilder
    private var welcome: some View {
        if !store.settings.showQuestionSets && !store.settings.showFlashcards {
            welcomePage(
                message: L("Please choose what you want to study in Settings — SAT "
                           + "practice, flashcards, or both. Nothing of yours has "
                           + "been deleted."),
                button: L("Open Settings")) { showSettings = true }
        } else if !store.settings.showQuestionSets {
            welcomePage(
                message: L("Pick a deck on the left to study your words, or make a new "
                           + "one. SAT practice is turned off; Settings will bring it "
                           + "back whenever you want it."),
                button: L("New deck")) { _ = store.addDeck() }
        } else {
            welcomePage(
                message: L("In the College Board Question Bank — SAT or PSAT — pick the "
                           + "questions you want and choose Export. Import that PDF here "
                           + "and it becomes a practice test you can sit as many times "
                           + "as you like."),
                button: L("Choose a PDF…")) { chooseFiles() }
        }
    }

    private func welcomePage(message: String, button: String,
                             action: @escaping () -> Void) -> some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)

            USUFULockup(sealSize: 132, wordSize: 25,
                        tint: Palette.navy, accent: Palette.brass)
                .padding(.horizontal, 44)
                .entrance(0)

            Text(message)
                .font(Face.ui(12.5))
                .foregroundStyle(Palette.textMuted)
                .multilineTextAlignment(.center)
                .lineSpacing(4)
                .frame(maxWidth: 460)
                .padding(.top, 34)
                .entrance(1)

            BluebookButton(title: button, lifts: true, action: action)
                .padding(.top, 22)
                .entrance(2)

            Text(L("Everything stays on this Mac. No account, no network, no subscription."))
                .font(Face.ui(10.5))
                .foregroundStyle(Palette.textMuted.opacity(0.85))
                .padding(.top, 16)
                .entrance(3)

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            USUFUSeal(size: 640, tint: Palette.navy)
                .opacity(0.035)
                .offset(x: 210, y: 120)
                .allowsHitTesting(false)
        }
        .clipped()
        .background(Palette.paper)
    }

    private func importOverlay(_ progress: AppStore.ImportProgress) -> some View {
        ZStack {
            Color.black.opacity(0.25).ignoresSafeArea()
            VStack(spacing: 14) {
                Text(L("Reading your question bank"))
                    .font(Face.display(15, .semibold))
                    .foregroundStyle(Palette.navy)
                GrowingBar(value: progress.fraction, tint: Palette.brass,
                           track: Palette.hairline, height: 4)
                    .frame(width: 260)
                Text(progress.message)
                    .font(Face.ui(11))
                    .foregroundStyle(Palette.textMuted)
                    .frame(width: 260)
                    .multilineTextAlignment(.center)
                Text(L("A large Math export can take a minute. The window stays "
                     + "usable while it reads."))
                    .font(Face.ui(10))
                    .foregroundStyle(Palette.textMuted.opacity(0.8))
                    .frame(width: 260)
                    .multilineTextAlignment(.center)
            }
            .padding(28)
            .background(Palette.card)
            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Palette.hairline, lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .shadow(color: .black.opacity(0.18), radius: 20, y: 8)
            .transition(.scale(scale: 0.96).combined(with: .opacity))
        }
        .animation(Motion.settle, value: progress.fraction)
    }

    private func chooseFiles(into bankID: String? = nil) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.pdf]
        panel.allowsMultipleSelection = true
        panel.message = L("Choose one or more PDFs exported from the College Board Question Bank")
        panel.prompt = "Import"
        guard panel.runModal() == .OK, !panel.urls.isEmpty else { return }
        runImport(panel.urls, into: bankID)
    }

    private func handleDrop(_ providers: [NSItemProvider]) {
        Task {
            var urls = [URL]()
            for provider in providers {
                if let item = try? await provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier),
                   let data = item as? Data,
                   let url = URL(dataRepresentation: data, relativeTo: nil),
                   url.pathExtension.lowercased() == "pdf" {
                    urls.append(url)
                }
            }
            if !urls.isEmpty { runImport(urls, into: nil) }
        }
    }

    private func runImport(_ urls: [URL], into bankID: String?) {
        Task { await store.importPDFs(urls: urls, into: bankID) }
    }
}

struct SetupView: View {
    @EnvironmentObject var store: AppStore
    let bank: Bank

    @State private var showPlan = false
    @State private var savedSession: Session?
    @State private var confirmingDiscard = false
    @State private var customMinutes: String = ""
    @State private var customCount: String = ""
    @FocusState private var customFocused: Bool
    @State private var sectionCountText: [Subject: String] = [:]
    @State private var confirmDeleteFile: AppStore.StoredFile?
    @State private var confirmClearSetAside = false
    @State private var rereading = false
    @State private var rereadStatus = ""
    @State private var filesVersion = 0
    @State private var narrowing = false
    @State private var namingPlan = false
    @State private var planName = ""
    @Namespace private var selectionMark
    @Namespace private var orderMark
    @Namespace private var gradingMark

    var body: some View {
        VStack(spacing: 0) {
        PinnedStartBar(width: 760, padding: 26) { startBar }
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                header.entrance(0)

                if let saved = savedSession {
                    resumeCard(saved).entrance(1)
                }

                if store.rereadingBankIDs.contains(bank.id) {
                    rereadingNotice
                } else if store.offersReadAgain(bank) {
                    rereadCard
                }

                if !store.importWarnings.isEmpty {
                    warningsCard
                }

                plansBar.entrance(2)

                fullTestCard.entrance(3)

                if store.profiles.profiles.count > 1, store.settings.showDoubleMode {
                    doubleCard.entrance(3)
                }

                Panel(title: L("What to practice")) {
                    subjectPicker
                    Rule()
                    selectionPicker
                    Rule()
                    narrowPicker
                    Rule()
                    countPicker
                }
                .opacity(store.config.fullTest ? 0.4 : 1)
                .disabled(store.config.fullTest)
                .entrance(4)

                Panel(title: L("How to practice")) {
                    orderPicker
                    Rule()
                    gradingPicker
                    Rule()
                    timerPicker
                }
                .opacity(store.config.fullTest ? 0.4 : 1)
                .disabled(store.config.fullTest)
                .entrance(4)

                if store.settings.showBackupCard, store.backupIsWorthMentioning() {
                    BackupCard().entrance(5)
                }

                setAsideCard.entrance(5)

                filesCard.entrance(6)

                sittingNameRow.entrance(7)
            }
            .padding(26)
            .frame(maxWidth: 760, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        }
        .background(Palette.paper)
        .onAppear {
            savedSession = store.savedSession(for: bank.id)
            narrowing = store.config.hasFilters
        }
        .onChange(of: bank.id) { _ in
            savedSession = store.savedSession(for: bank.id)
            if bank.id != store.importNoticeBankID {
                store.lastError = nil
                store.importWarnings = []
            }
        }
        .onChange(of: store.profile.id) { _ in savedSession = store.savedSession(for: bank.id) }
        .alert(L("Name this plan"), isPresented: $namingPlan) {
            TextField(L("Morning drill"), text: $planName)
            Button(L("Cancel"), role: .cancel) { namingPlan = false }
            Button(L("Save")) {
                store.savePreset(named: planName, config: store.config)
                planName = ""
            }
        } message: {
            Text(L("These settings are saved under that name and can be applied to "
                 + "any question set in one click."))
        }
        .alert(L("Empty the set-aside list?"), isPresented: $confirmClearSetAside) {
            Button(L("Cancel"), role: .cancel) {}
            Button(L("Empty"), role: .destructive) { store.clearSetAside(in: bank.id) }
        } message: {
            Text(L("The questions stay in the bank and your progress is untouched; only the list of ones you kept back is cleared."))
        }
        .alert(L("Delete this PDF?"), isPresented: Binding(
            get: { confirmDeleteFile != nil }, set: { if !$0 { confirmDeleteFile = nil } })) {
            Button(L("Cancel"), role: .cancel) { confirmDeleteFile = nil }
            Button(L("Delete"), role: .destructive) {
                if let f = confirmDeleteFile { store.deleteStoredFile(f); filesVersion += 1 }
                confirmDeleteFile = nil
            }
        } message: {
            Text(confirmDeleteFile.map {
                $0.kind == .source
                    ? Lf("“%@” will be removed from this app. The questions already "
                         + "imported from it stay, and any copy you keep elsewhere is "
                         + "untouched.", $0.name)
                    : Lf("“%@” will be removed from this app. Copies you saved "
                         + "elsewhere are untouched.", $0.name)
            } ?? "")
        }
    }

    private var progress: BankProgress { store.progress[bank.id] ?? BankProgress(bankID: bank.id) }

    private var header: some View {
        HStack(alignment: .top, spacing: 20) {
            VStack(alignment: .leading, spacing: 12) {
                Text(bank.name)
                    .font(Face.display(27, .semibold))
                    .foregroundStyle(Palette.navy)
                Rule(brass: true).frame(width: 46)
                FlowRow(spacing: 26, lineSpacing: 12) {
                    stat(bank.questions.count, L("questions"))
                    if bank.readingCount > 0 { stat(bank.readingCount, L("reading & writing")) }
                    if bank.mathCount > 0 { stat(bank.mathCount, L("math")) }
                    stat(progress.seenCount, L("seen"))
                    stat(missedCount, L("to review"))
                }
            }
            Spacer(minLength: 12)
            if store.settings.showQuestionStreak { rhythmCard }
        }
    }

    private var missedCount: Int {
        bank.questions.filter { progress.lastWrong($0.id) }.count
    }

    private func stat(_ value: Int, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Counter(value: Double(value))
                .font(Face.figures(22, .semibold))
                .foregroundStyle(Palette.navy)
                .monospacedDigit()
            Text(label.uppercased())
                .font(Face.ui(9, .medium))
                .tracking(0.9)
                .foregroundStyle(Palette.textMuted)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
        }
        .fixedSize(horizontal: true, vertical: false)
    }

    private enum TodayCard { static let minWidth: CGFloat = 250 }

    private var rhythmCard: some View {
        let state = store.streak()
        return VStack(spacing: 0) {
            HStack(spacing: 14) {
                ZStack {
                    GoalRing(fraction: state.fractionToday,
                             size: 54,
                             tint: state.metToday || state.isRestDay
                                   ? Palette.correct : Palette.brass)
                    VStack(spacing: 0) {
                        Counter(value: Double(state.answeredToday))
                            .font(Face.figures(15, .semibold))
                            .foregroundStyle(Palette.navy)
                            .monospacedDigit()
                        Text(state.isRestDay ? L("today") : "/\(state.targetToday)")
                            .font(Face.ui(8))
                            .foregroundStyle(Palette.textMuted)
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                            .frame(maxWidth: 40)
                    }
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(headline(state))
                        .font(Face.ui(12, .semibold))
                        .foregroundStyle(state.metToday ? Palette.correct : Palette.navy)
                    Text(streakLine(state))
                        .font(Face.ui(10))
                        .foregroundStyle(Palette.textMuted)
                        .fixedSize(horizontal: false, vertical: true)
                    if let note = excusedNote(state) {
                        Text(note)
                            .font(Face.ui(9.5))
                            .foregroundStyle(Palette.brass)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if store.settings.schedule.isActive {
                        weekDots(state)
                            .padding(.top, 2)
                    }
                }
                Spacer(minLength: 0)
                Button {
                    withAnimation(Motion.settle) { showPlan.toggle() }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "calendar")
                            .font(.system(size: 10, weight: .semibold))
                        Text(showPlan ? L("Close") : L("Plan"))
                            .font(Face.ui(10, .semibold))
                            .fixedSize()
                    }
                    .foregroundStyle(Palette.navy)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(Palette.subtleFill)
                    .clipShape(RoundedRectangle(cornerRadius: 3))
                }
                .buttonStyle(.plain)
                .help(L("Which days you practice, how much, and when to be reminded"))
            }
            .padding(14)

            if showPlan {
                Rule()
                SchedulePanel(schedule: Binding(
                    get: { store.settings.schedule },
                    set: { store.settings.schedule = $0; store.refreshReminders() }))
                    .padding(14)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .frame(minWidth: TodayCard.minWidth, alignment: .leading)
        .background(Palette.card)
        .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(Palette.hairline, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 4))
    }

    private func weekDots(_ state: StreakState) -> some View {
        let schedule = store.settings.schedule
        let calendar = Calendar.current
        let answers = store.answersByDay()
        let today = calendar.startOfDay(for: Date())
        let week = calendar.dateInterval(of: .weekOfYear, for: today)
        return HStack(spacing: 4) {
            ForEach(0..<7, id: \.self) { offset in
                let day = week.flatMap {
                    calendar.date(byAdding: .day, value: offset,
                                  to: calendar.startOfDay(for: $0.start))
                }
                let target = day.map { schedule.target(on: $0) } ?? 0
                let done = day.flatMap { answers[$0] } ?? 0
                Circle()
                    .fill(target == 0 ? Palette.hairline.opacity(0.5)
                          : (done >= target ? Palette.correct
                             : (day.map { $0 < today } == true ? Palette.wrong.opacity(0.45)
                                : Palette.border.opacity(0.55))))
                    .frame(width: 6, height: 6)
                    .overlay {
                        if day == today {
                            Circle().strokeBorder(Palette.brass, lineWidth: 1)
                                .frame(width: 10, height: 10)
                        }
                    }
                    .frame(width: 10, height: 10)
            }
        }
        .help(L("This week against your plan"))
    }

    private func excusedNote(_ state: StreakState) -> String? {
        guard state.current > 0, let start = state.runStartedOn else { return nil }
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let inside = store.settings.excusedDays
            .map { calendar.startOfDay(for: $0) }
            .filter { $0 >= start && $0 <= today }
        guard !inside.isEmpty else { return nil }
        return Lp(inside.count,
                  "Includes %d day you set aside",
                  "Includes %d days you set aside")
    }

    private func headline(_ state: StreakState) -> String {
        if state.isRestDay { return L("Rest day") }
        if state.metToday { return L("Today's plan is done") }
        return L("Today")
    }

    private func streakLine(_ state: StreakState) -> String {
        if state.isRestDay {
            return state.current > 0
                ? Lp(state.current, "%d-day streak held · nothing planned today",
                     "%d-day streak held · nothing planned today")
                : L("Nothing planned today")
        }
        if state.current >= 2 {
            let left = state.remainingToday
            return left > 0
                ? Lf("%1$d days in a row · %2$d to go today", state.current, left)
                : Lp(state.current, "%d day in a row", "%d days in a row")
        }
        if state.metToday { return L("First day of a new streak") }
        if state.remainingToday > 0 && state.answeredToday > 0 {
            return Lp(state.remainingToday, "%d more to keep today",
                      "%d more to keep today")
        }
        return Lf("Answer %d questions to start a streak", state.targetToday)
    }

    @ViewBuilder
    private var plansBar: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 8) {
                SectionLabel(text: L("Study plans"))
                Spacer()
                Button {
                    planName = ""
                    namingPlan = true
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "plus").font(.system(size: 8, weight: .bold))
                        Text(L("Save these settings"))
                    }
                    .font(Face.ui(11, .semibold))
                    .foregroundStyle(Palette.navy)
                }
                .buttonStyle(.plain)
            }
            if store.presets.isEmpty {
                Text(L("Save the settings you use most and they come back in one click."))
                    .font(Face.ui(11))
                    .foregroundStyle(Palette.textMuted)
            } else {
                FlowRow(spacing: 8) {
                    ForEach(store.presets) { preset in
                        planChip(preset)
                    }
                }
            }
        }
    }

    private func planChip(_ preset: StudyPreset) -> some View {
        let applied = store.isApplied(preset)
        return HStack(spacing: 5) {
            Button {
                withAnimation(Motion.settle) { store.applyPreset(preset) }
            } label: {
                Text(preset.name)
                    .font(Face.ui(12, applied ? .semibold : .regular))
                    .foregroundStyle(applied ? Palette.card : Palette.text)
            }
            .buttonStyle(.plain)
            Button {
                withAnimation(Motion.standard) { store.deletePreset(preset) }
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 7, weight: .bold))
                    .foregroundStyle(applied ? Palette.card.opacity(0.8) : Palette.textMuted)
            }
            .buttonStyle(.plain)
            .iconHelp(L("Forget this plan"))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(applied ? Palette.navy : Palette.subtleFill)
        .overlay(RoundedRectangle(cornerRadius: 3)
            .strokeBorder(applied ? .clear : Palette.hairline, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 3))
        .animation(Motion.settle, value: applied)
    }

    private func resumeCard(_ saved: Session) -> some View {
        HStack(spacing: 16) {
            Rectangle().fill(Palette.brass).frame(width: 2, height: 34)
            VStack(alignment: .leading, spacing: 3) {
                Text(L("You have a test in progress"))
                    .font(Face.ui(10, .semibold))
                    .foregroundStyle(Palette.brass)
                    .textCase(.uppercase)
                    .tracking(0.6)
                Text(saved.resumeTitle)
                    .font(Face.display(14, .semibold))
                    .foregroundStyle(Palette.navy)
                Text(saved.resumeDetail())
                    .font(Face.ui(11))
                    .foregroundStyle(Palette.textMuted)
            }
            Spacer()
            BluebookButton(title: L("Resume")) { store.resumeSession(saved) }
            Button(L("Discard")) { confirmingDiscard = true }
            .buttonStyle(.plain)
            .font(Face.ui(12))
            .foregroundStyle(Palette.textMuted)
        }
        .alert(L("Discard this sitting?"), isPresented: $confirmingDiscard) {
            Button(L("Cancel"), role: .cancel) {}
            Button(L("Discard sitting"), role: .destructive) {
                store.discardSavedSession(for: bank.id)
                savedSession = nil
            }
        } message: {
            Text(L("It is deleted: where you had got to, the answers given in it and the time left. This cannot be undone."))
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.brassSoft.opacity(0.45))
        .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(Palette.brass.opacity(0.35), lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 4))
    }

    @ViewBuilder
    private var setAsideCard: some View {
        let count = store.setAsideCount(in: bank.id)
        if count > 0 {
            Panel(title: L("Set aside for later")) {
                HStack(spacing: 16) {
                    Text("\(count)")
                        .font(Face.figures(26, .semibold))
                        .foregroundStyle(Palette.brass)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(count == 1 ? L("question kept back") : L("questions kept back"))
                            .font(Face.ui(13, .medium))
                            .foregroundStyle(Palette.text)
                        Text(L("Set aside while you were practicing, waiting for you to come back to them."))
                            .font(Face.ui(11))
                            .foregroundStyle(Palette.textMuted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 12)
                    BluebookButton(title: L("Practice these")) {
                        var c = store.config
                        c.selection = .setAside
                        c.questionCount = count
                        c.subjects = Set(Subject.allCases)
                        store.startSession(config: c)
                    }
                }
                Rule()
                HStack(spacing: 14) {
                    Button(L("Export as PDF…")) { exportSetAside() }
                        .buttonStyle(.plain).font(Face.ui(11)).foregroundStyle(Palette.navy)
                    Button(L("Empty the list")) { confirmClearSetAside = true }
                        .buttonStyle(.plain).font(Face.ui(11)).foregroundStyle(Palette.wrong)
                    Spacer()
                }
            }
        }
    }

    private func exportSetAside() {
        guard store.setAsideCount(in: bank.id) > 0 else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.pdf]
        panel.nameFieldStringValue = Lf("SAT set aside — %@.pdf", bank.name)
        panel.message = Lf("This PDF can be read or printed, and imported back into %@.",
                           Brand.appName)
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try store.exportSetAside(in: bank.id, to: url)
            filesVersion += 1
        } catch {
            store.lastError = Lf("Could not export: %@", error.localizedDescription)
        }
    }

    private var rereadingNotice: some View {
        HStack(spacing: 14) {
            ProgressView().controlSize(.small)
            Text(L("Reading this set again with the current reader…"))
                .font(Face.ui(12))
                .foregroundStyle(Palette.textMuted)
            Spacer()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.brassSoft.opacity(0.45))
        .clipShape(RoundedRectangle(cornerRadius: 4))
    }

    private var rereadCard: some View {
        HStack(spacing: 16) {
            Rectangle().fill(Palette.brass).frame(width: 2, height: 38)
            VStack(alignment: .leading, spacing: 3) {
                Text(L("This set can be read again"))
                    .font(Face.display(14, .semibold))
                    .foregroundStyle(Palette.navy)
                Text(L("It was imported before the reader learned to keep tables, "
                     + "underlined text, and hyphens. Reading the stored PDFs again "
                     + "fixes those. Your progress, notes, and set-aside list are kept."))
                    .font(Face.ui(11))
                    .foregroundStyle(Palette.textMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 12)
            BluebookButton(title: rereading ? L("Reading…") : L("Read again"),
                           enabled: !rereading) {
                rereading = true
                Task {
                    await store.reread(bankID: bank.id) { p, m in rereadStatus = m }
                    rereading = false
                    rereadStatus = ""
                }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.brassSoft.opacity(0.45))
        .overlay(RoundedRectangle(cornerRadius: 4)
            .strokeBorder(Palette.brass.opacity(0.35), lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 4))
    }

    private var warningsCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(store.lastError != nil ? L("Nothing was imported")
                 : Lp(store.importWarnings.count, "%d question was skipped:", "%d questions were skipped:"))
                .font(Face.ui(12, .semibold))
                .foregroundStyle(Palette.brass)
            ForEach(store.importWarnings.prefix(6), id: \.self) { w in
                Text("— " + w).font(Face.ui(11)).foregroundStyle(Palette.textMuted)
            }
            Button(L("Dismiss")) {
                store.importWarnings = []
                store.lastError = nil
            }
                .buttonStyle(.plain).font(Face.ui(11)).foregroundStyle(Palette.navy)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.brassSoft.opacity(0.4))
        .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(Palette.brass.opacity(0.3), lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 4))
    }

    private var filesCard: some View {
        _ = filesVersion
        let files = store.storedFiles(for: bank.id)
        return Panel(title: L("PDFs")) {
            if files.isEmpty {
                Text(L("No PDFs stored for this set yet."))
                    .font(Face.ui(12))
                    .foregroundStyle(Palette.textMuted)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(files.enumerated()), id: \.element.id) { idx, file in
                        if idx > 0 { Rule() }
                        fileRow(file)
                    }
                }
            }
            Rule()
            HStack(spacing: 12) {
                BluebookButton(title: L("Add another PDF to this set…"),
                               style: .secondary, lifts: true) {
                    addFiles()
                }
                Text(L("Reading and Writing and Math can live in one set, and so "
                     + "can SAT and PSAT — you choose what to draw from above."))
                    .font(Face.ui(11))
                    .foregroundStyle(Palette.textMuted)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
        }
    }

    private func addFiles() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.pdf]
        panel.allowsMultipleSelection = true
        panel.message = Lf("Choose PDFs to add to “%@”", bank.name)
        panel.prompt = L("Add")
        guard panel.runModal() == .OK, !panel.urls.isEmpty else { return }
        let urls = panel.urls
        let id = bank.id
        Task {
            await store.importPDFs(urls: urls, into: id) { _, _ in }
            filesVersion += 1
        }
    }

    private func fileRow(_ file: AppStore.StoredFile) -> some View {
        HStack(spacing: 11) {
            Image(systemName: file.kind == .source ? "doc.text" : "arrow.uturn.backward")
                .font(.system(size: 14))
                .foregroundStyle(file.kind == .source ? Palette.navy : Palette.brass)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 2) {
                Text(file.name)
                    .font(Face.ui(12, .medium))
                    .foregroundStyle(Palette.text)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text("\(file.kind == .source ? L("Imported question bank") : L("Review export")) · \(file.sizeText) · \(file.dateText)")
                    .font(Face.ui(10))
                    .foregroundStyle(Palette.textMuted)
            }

            Spacer()

            Button(L("Open")) { NSWorkspace.shared.open(file.url) }
                .buttonStyle(.plain).font(Face.ui(11)).foregroundStyle(Palette.navy)
            Button(L("Save a copy…")) { store.saveCopy(of: file) }
                .buttonStyle(.plain).font(Face.ui(11)).foregroundStyle(Palette.navy)
            Button(L("Delete")) { confirmDeleteFile = file }
                .buttonStyle(.plain).font(Face.ui(11)).foregroundStyle(Palette.wrong)
        }
        .padding(.vertical, 8)
    }

    private var subjectPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel(text: L("Sections"))
            HStack(spacing: 10) {
                subjectChip(.readingWriting, count: bank.readingCount)
                subjectChip(.math, count: bank.mathCount)
            }
        }
    }

    private func subjectChip(_ subject: Subject, count: Int) -> some View {
        let on = store.config.subjects.contains(subject)
        return Chip(title: subject.displayName, selected: on, enabled: count > 0,
                    count: count) {
            withAnimation(Motion.settle) {
                if on {
                    if store.config.subjects.count > 1 { store.config.subjects.remove(subject) }
                } else {
                    store.config.subjects.insert(subject)
                }
                store.config.trim(to: bank)
            }
        }
    }

    private var selectionPicker: some View {
        VStack(alignment: .leading, spacing: 9) {
            SectionLabel(text: L("Which questions"))
            VStack(spacing: 1) {
                ForEach(SelectionMode.allCases, id: \.self) { mode in
                    OptionRow(title: mode.title,
                              detail: mode.detail,
                              selected: store.config.selection == mode,
                              namespace: selectionMark,
                              badge: modeBadge(mode)) {
                        withAnimation(Motion.settle) { store.config.selection = mode }
                    }
                }
            }
        }
    }

    private func modeBadge(_ mode: SelectionMode) -> String? {
        var c = store.config
        c.selection = mode
        let n = store.availableCount(for: c)
        return n == 0 ? L("none") : "\(n)"
    }

    private var orderPicker: some View {
        optionGroup(L("Order"), MixMode.allCases,
                    selection: $store.config.mix, namespace: orderMark,
                    title: \.title, detail: \.detail)
    }

    private var gradingPicker: some View {
        optionGroup(L("Grading"), GradingMode.allCases,
                    selection: $store.config.grading, namespace: gradingMark,
                    title: \.title, detail: \.detail)
    }

    private func optionGroup<T: Hashable>(_ label: String, _ options: [T],
                                          selection: Binding<T>,
                                          namespace: Namespace.ID,
                                          title: KeyPath<T, String>,
                                          detail: KeyPath<T, String>) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            SectionLabel(text: label)
            VStack(spacing: 1) {
                ForEach(options, id: \.self) { option in
                    OptionRow(title: option[keyPath: title],
                              detail: option[keyPath: detail],
                              selected: selection.wrappedValue == option,
                              namespace: namespace) {
                        withAnimation(Motion.settle) { selection.wrappedValue = option }
                    }
                }
            }
        }
    }

    private var narrowPicker: some View {
        let subjects = store.config.subjects
        return Disclosure(title: L("Narrow it down"),
                          summary: filterSummary,
                          open: $narrowing) {
            VStack(alignment: .leading, spacing: 14) {
                let assessments = bank.assessments(in: subjects)
                if assessments.count > 1 {
                    filterGroup(L("Assessment"), assessments,
                                selected: store.config.assessments) { label in
                        toggleFilter(label, in: \.assessments)
                    }
                }
                filterGroup(L("Difficulty"), bank.difficulties(in: subjects),
                            selected: store.config.difficulties) { label in
                    toggleFilter(label, in: \.difficulties)
                }
                let domains = bank.domains(in: subjects)
                if domains.count > 1 {
                    filterGroup(L("Domain"), domains, selected: store.config.domains) { label in
                        toggleFilter(label, in: \.domains)
                    }
                }
                let skills = bank.skills(in: subjects)
                if skills.count > 1 {
                    filterGroup(L("Skill"), skills, selected: store.config.skills) { label in
                        toggleFilter(label, in: \.skills)
                    }
                }
                if store.config.hasFilters {
                    Button(L("Clear all filters")) {
                        withAnimation(Motion.settle) { store.config.clearFilters() }
                    }
                    .buttonStyle(.plain)
                    .font(Face.ui(11))
                    .foregroundStyle(Palette.navy)
                }
            }
            .padding(.top, 2)
        }
    }

    private var filterSummary: String {
        let c = store.config
        guard c.hasFilters else { return L("everything") }
        var parts = [String]()
        if !c.assessments.isEmpty {
            parts.append(c.assessments.count == 1 ? c.assessments.first!
                         : "\(c.assessments.count) assessments")
        }
        if !c.difficulties.isEmpty {
            parts.append(bank.difficulties().map(\.label).filter { c.difficulties.contains($0) }
                .joined(separator: "/"))
        }
        if !c.domains.isEmpty {
            parts.append(c.domains.count == 1 ? c.domains.first! : "\(c.domains.count) domains")
        }
        if !c.skills.isEmpty {
            parts.append(c.skills.count == 1 ? c.skills.first! : "\(c.skills.count) skills")
        }
        return parts.joined(separator: " · ")
    }

    private func filterGroup(_ label: String, _ tallies: [Bank.Tally],
                             selected: Set<String>,
                             toggle: @escaping (String) -> Void) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 8) {
                Text(label)
                    .font(Face.ui(11, .medium))
                    .foregroundStyle(Palette.text)
                if selected.isEmpty {
                    Text(L("all"))
                        .font(Face.ui(10))
                        .foregroundStyle(Palette.textMuted)
                }
            }
            FlowRow(spacing: 7, lineSpacing: 7) {
                ForEach(tallies) { t in
                    Chip(title: t.label, selected: selected.contains(t.label),
                         count: t.count, accent: Palette.brass) {
                        withAnimation(Motion.settle) { toggle(t.label) }
                    }
                }
            }
        }
    }

    private func toggleFilter(_ label: String, in path: WritableKeyPath<StudyConfig, Set<String>>) {
        var set = store.config[keyPath: path]
        if set.contains(label) { set.remove(label) } else { set.insert(label) }
        store.config[keyPath: path] = set
    }

    private static let countPresets = [10, 20, 22, 27, 40]

    private var countPicker: some View {
        let available = store.availableCount(for: store.config)
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                SectionLabel(text: L("How many questions"))
                Spacer()
                Text(Lf("%1$d of %2$d available", min(store.config.questionCount, available), available))
                    .font(Face.ui(11)).foregroundStyle(Palette.textMuted)
                    .monospacedDigit()
            }
            FlowRow(spacing: 8, lineSpacing: 8) {
                ForEach(Self.countPresets, id: \.self) { n in
                    chip(label(for: n), selected: store.config.questionCount == n && n <= available) {
                        store.config.questionCount = n
                        customCount = ""
                    }
                    .disabled(n > available)
                }
                chip(L("All"), selected: store.config.questionCount >= available && available > 0
                     && !Self.countPresets.filter { $0 <= available }
                            .contains(store.config.questionCount)) {
                    store.config.questionCount = max(available, 1)
                    customCount = ""
                }
                .disabled(available == 0)
                customCountField(available: available)
            }
            if store.config.subjects.count > 1 { splitRow }
            if available == 0 { emptyPoolNotice }
        }
    }

    private var splitRow: some View {
        let split = store.config.hasSectionSplit
        return VStack(alignment: .leading, spacing: 7) {
            Rule().padding(.top, 2)
            HStack(spacing: 8) {
                Text(split ? L("How many of each") : L("Mixed together"))
                    .font(Face.ui(11, .semibold))
                    .foregroundStyle(Palette.text)
                Text(split ? "" : L("the total is drawn from both sections"))
                    .font(Face.ui(10))
                    .foregroundStyle(Palette.textMuted)
                Spacer(minLength: 0)
                Button(split ? L("Mix them") : L("Choose how many of each")) {
                    sectionCountText.removeAll()
                    withAnimation(Motion.settle) {
                        if split {
                            store.config.clearSectionSplit()
                        } else {
                            let half = max(1, store.config.questionCount / 2)
                            for subject in store.config.subjects {
                                store.config.setCount(
                                    min(half, store.available(for: store.config, in: subject)),
                                    for: subject)
                            }
                        }
                    }
                }
                .buttonStyle(.plain)
                .font(Face.ui(10, .semibold))
                .foregroundStyle(Palette.brass)
            }

            if split {
                HStack(spacing: 14) {
                    ForEach([Subject.readingWriting, Subject.math], id: \.self) { subject in
                        if store.config.subjects.contains(subject) {
                            sectionCountField(subject)
                        }
                    }
                    Spacer(minLength: 0)
                    let drawn = store.splitDraw(for: store.config)
                    Text(Lp(drawn, "%d question in all", "%d questions in all"))
                        .font(Face.ui(10))
                        .foregroundStyle(Palette.textMuted)
                        .monospacedDigit()
                }
            }
        }
    }

    private func sectionCountField(_ subject: Subject) -> some View {
        let most = store.available(for: store.config, in: subject)
        let value = store.config.count(for: subject)
        return HStack(spacing: 6) {
            Text(subject == .math ? L("Math") : L("R&W"))
                .font(Face.ui(11))
                .foregroundStyle(Palette.text)
            TextField("", text: Binding(
                get: { sectionCountText[subject] ?? "\(min(value, most))" },
                set: { typed in
                    let digits = String(typed.filter(\.isNumber).prefix(4))
                    sectionCountText[subject] = digits
                    store.config.setCount(min(Int(digits) ?? 0, most), for: subject)
                }))
                .textFieldStyle(.plain)
                .font(Face.ui(12, .semibold))
                .foregroundStyle(value > most ? Palette.wrong : Palette.text)
                .monospacedDigit()
                .multilineTextAlignment(.trailing)
                .frame(width: 34)
                .padding(.horizontal, 5)
                .padding(.vertical, 3)
                .background(Palette.card)
                .overlay(RoundedRectangle(cornerRadius: 2)
                    .strokeBorder(Palette.hairline, lineWidth: 1))
                .clipShape(RoundedRectangle(cornerRadius: 2))
            Stepper("", value: Binding(
                get: { value },
                set: {
                    let n = min(max($0, 0), max(most, 0))
                    store.config.setCount(n, for: subject)
                    sectionCountText[subject] = "\(n)"
                }),
                    in: 0...max(most, 1))
            .labelsHidden()
            Text(Lf("of %d", most))
                .font(Face.ui(10))
                .foregroundStyle(Palette.textMuted)
                .monospacedDigit()
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background(Palette.subtleFill)
        .overlay(RoundedRectangle(cornerRadius: 3)
            .strokeBorder(Palette.hairline, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 3))
    }

    private func label(for count: Int) -> String {
        switch count {
        case 22: return L("22 · math module")
        case 27: return "27 · R&W module"
        default: return "\(count)"
        }
    }

    @ViewBuilder
    private var emptyPoolNotice: some View {
        let c = store.config
        HStack(spacing: 8) {
            Image(systemName: "info.circle")
                .font(.system(size: 11))
                .foregroundStyle(Palette.brass)
            Text(emptyPoolReason)
                .font(Face.ui(11))
                .foregroundStyle(Palette.brass)
                .fixedSize(horizontal: false, vertical: true)
            if c.hasFilters {
                Button(L("Clear filters")) {
                    withAnimation(Motion.settle) { store.config.clearFilters() }
                }
                .buttonStyle(.plain)
                .font(Face.ui(11, .semibold))
                .foregroundStyle(Palette.navy)
            }
        }
        .transition(.opacity)
    }

    private var emptyPoolReason: String {
        let c = store.config
        switch c.selection {
        case .dueForReview:
            if let next = store.nextReviewDue(in: bank.id) {
                return Lf("Nothing is due yet — the next question comes back %@.",
                          Self.relative(next))
            }
            return L("Nothing is due for review yet. Answer some questions and they "
                     + "come back on a widening schedule.")
        case .weakestSkills:
            return Lf("Not enough attempts yet to say which skills are weakest. "
                      + "Answer at least %d questions in a skill and it can be ranked.",
                      Breakdown.confidentAt)
        case .setAside:
            return L("You have not set any questions aside yet.")
        case .reviewMissed:
            return L("Nothing to review — you have not got any of these wrong.")
        case .unseenOnly:
            return L("You have seen every question that matches. Try another way of choosing.")
        default:
            return c.hasFilters
                ? L("No questions match these filters.")
                : L("No questions match these settings yet.")
        }
    }

    private static func relative(_ date: Date) -> String {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .full
        return f.localizedString(for: date, relativeTo: Date())
    }

    private var timerPicker: some View {
        let planned = store.plannedSitting(for: store.config)
        return VStack(alignment: .leading, spacing: 8) {
            Toggle(isOn: Binding(
                get: { store.config.timed },
                set: { on in withAnimation(Motion.settle) { store.config.timed = on } })) {
                SectionLabel(text: L("Use a timer"))
            }
            .toggleStyle(.switch)
            .controlSize(.small)
            .tint(Palette.navy)

            if store.config.timed {
                FlowRow(spacing: 8, lineSpacing: 8) {
                    ForEach([10, 20, 32, 35, 45, 70], id: \.self) { m in
                        chip(Lf("%d min", m), selected: store.config.minutes == m) {
                            store.config.minutes = m
                            customMinutes = ""
                        }
                    }
                    customMinutesField
                }
                paceRow(planned)
                    .transition(.opacity)
            }
        }
    }

    private func paceRow(_ planned: (readingWriting: Int, math: Int, minutes: Int)) -> some View {
        let total = planned.readingWriting + planned.math
        let matches = store.config.minutes == planned.minutes
        let each = total > 0 ? Double(store.config.minutes * 60) / Double(total) : 0
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                Chip(title: matches ? L("Matching the real test") : L("Match the real test"),
                     selected: matches, enabled: total > 0, accent: Palette.brass) {
                    withAnimation(Motion.settle) {
                        store.config.minutes = planned.minutes
                        customMinutes = ""
                    }
                }
                if total > 0 {
                    Text(matches
                         ? Lf("%@ a question, the pace the test sets",
                              Pace.describe(seconds: each))
                         : Lf("%1$d min is %2$@ a question; the test would allow "
                              + "%3$d min for these %4$d",
                              store.config.minutes, Pace.describe(seconds: each),
                              planned.minutes, total))
                        .font(Face.ui(11))
                        .foregroundStyle(matches ? Palette.brass : Palette.textMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Text(Lf("The real test allows 32 minutes for 27 Reading and Writing "
                    + "questions (%1$@ each) and 35 for 22 Math (%2$@ each).",
                    Pace.describe(seconds: Pace.readingWritingSeconds),
                    Pace.describe(seconds: Pace.mathSeconds)))
                .font(Face.ui(11)).foregroundStyle(Palette.textMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func chip(_ label: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Chip(title: label, selected: selected, action: action)
    }

    private func customCountField(available: Int) -> some View {
        let isCustom = !Self.countPresets.contains(store.config.questionCount)
            && store.config.questionCount < max(available, 1)
        let lit = isCustom || customFocused
        return HStack(spacing: 6) {
            HStack(spacing: 5) {
                Image(systemName: "square.and.pencil")
                    .font(.system(size: 9.5))
                    .foregroundStyle(lit ? Palette.brass : Palette.textMuted)
                TextField(L("Custom"), text: $customCount)
                    .textFieldStyle(.plain)
                    .font(Face.ui(12, lit ? .semibold : .regular))
                    .foregroundStyle(Palette.text)
                    .multilineTextAlignment(.center)
                    .monospacedDigit()
                    .frame(width: 44)
                    .focused($customFocused)
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
            .background(lit ? Palette.brassSoft.opacity(0.5) : Palette.subtleFill)
            .overlay(RoundedRectangle(cornerRadius: 3)
                .strokeBorder(lit ? Palette.brass : Palette.hairline,
                              lineWidth: customFocused ? 2 : 1))
            .clipShape(RoundedRectangle(cornerRadius: 3))
            .contentShape(RoundedRectangle(cornerRadius: 3))
            .onTapGesture { customFocused = true }
            .help(L("Type any number of questions"))
            .disabled(available == 0)
            .onChange(of: customCount) { value in
                let digits = value.filter(\.isNumber)
                if digits != value { customCount = digits; return }
                if let n = Int(digits), n >= 1 {
                    store.config.questionCount = min(n, max(available, 1))
                }
            }
            Text(L("questions"))
                .font(Face.ui(11))
                .foregroundStyle(Palette.textMuted)
        }
        .onAppear { if isCustom { customCount = String(store.config.questionCount) } }
        .onChange(of: store.config.questionCount) { count in
            let custom = !Self.countPresets.contains(count) && count < max(available, 1)
            if !customFocused { customCount = custom ? String(count) : "" }
        }
    }

    private var customMinutesField: some View {
        let presets = [10, 20, 32, 35, 45, 70]
        let isCustom = !presets.contains(store.config.minutes)
        return HStack(spacing: 6) {
            TextField(L("Custom"), text: $customMinutes)
                .textFieldStyle(.plain)
                .font(Face.ui(12))
                .foregroundStyle(Palette.text)
                .multilineTextAlignment(.center)
                .frame(width: 46)
                .padding(.vertical, 6)
                .background(isCustom ? Palette.brassSoft.opacity(0.5) : Palette.subtleFill)
                .overlay(RoundedRectangle(cornerRadius: 3)
                    .strokeBorder(isCustom ? Palette.brass : Palette.hairline, lineWidth: 1))
                .clipShape(RoundedRectangle(cornerRadius: 3))
                .onChange(of: customMinutes) { value in
                    let digits = value.filter(\.isNumber)
                    if digits != value { customMinutes = digits; return }
                    if let m = Int(digits), m >= 1 {
                        store.config.minutes = min(m, 360)
                    }
                }
            Text(L("min"))
                .font(Face.ui(11))
                .foregroundStyle(Palette.textMuted)
        }
        .onAppear { if isCustom { customMinutes = String(store.config.minutes) } }
    }

    private var sittingNameRow: some View {
        HStack(spacing: 10) {
            SectionLabel(text: L("Name this sitting"))
            HStack(spacing: 6) {
                Image(systemName: "textformat")
                    .font(.system(size: 10))
                    .foregroundStyle(Palette.textMuted)
                TextField(namePlaceholder == L("Name this sitting") ? L("Optional") : namePlaceholder,
                          text: Binding(
                    get: { store.config.sittingName },
                    set: { store.config.sittingName = $0 }))
                    .textFieldStyle(.plain)
                    .font(Face.ui(11))
                    .foregroundStyle(Palette.text)
                    .frame(width: 220)
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
            .background(Palette.subtleFill)
            .overlay(RoundedRectangle(cornerRadius: 3)
                .strokeBorder(Palette.hairline, lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 3))
            .help(L("What to call this sitting at the top of the test screen"))
            Spacer(minLength: 0)
        }
    }

    private var startBar: some View {
        let available = store.availableCount(for: store.config)
        let planned = store.plannedSitting(for: store.config)
        return HStack(alignment: .center, spacing: 14) {
            if let error = store.lastError {
                Text(error).font(Face.ui(11)).foregroundStyle(Palette.wrong)
            } else if store.config.fullTest {
                Text(Lf("%1$d modules · %2$d questions · %3$d min · every module timed as on the test",
                        TestForm.digital.count, TestForm.totalQuestions, TestForm.totalMinutes))
                    .font(Face.ui(11))
                    .foregroundStyle(Palette.textMuted)
                    .fixedSize(horizontal: false, vertical: true)
            } else if available > 0 {
                Text(summary(planned))
                    .font(Face.ui(11))
                    .foregroundStyle(Palette.textMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            BluebookButton(title: store.config.fullTest ? L("Begin full test") : L("Start practice"),
                           enabled: store.config.fullTest
                               ? store.fullTestReadiness(for: store.config).isReady
                               : available > 0,
                           lifts: true) {
                var c = store.config
                if !c.fullTest { c.questionCount = min(c.questionCount, available) }
                store.startSession(config: c)
            }
        }
    }

    private var doubleCard: some View {
        let others = store.profiles.profiles.filter { $0.id != store.profile.id }
        let chosen = store.config.partnerProfileID
        return Panel {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(L("Study together"))
                            .font(Face.display(15, .semibold))
                            .foregroundStyle(Palette.navy)
                        Text(L("Two of you, one computer, taking turns: you answer "
                               + "the first question, they answer the second, and so "
                               + "on to the end. Each answer goes into that "
                               + "student's own record, so neither of you ends up "
                               + "with the other's statistics."))
                            .font(Face.ui(11))
                            .foregroundStyle(Palette.textMuted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 8)
                    Toggle("", isOn: Binding(
                        get: { store.config.isDouble },
                        set: { on in
                            withAnimation(Motion.settle) {
                                store.config.partnerProfileID = on ? (others.first?.id ?? "") : ""
                                if on {
                                    store.config.timed = false
                                    store.config.fullTest = false
                                    store.config.adaptive = false
                                }
                            }
                        }))
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .disabled(others.isEmpty)
                }

                if store.config.isDouble {
                    VStack(alignment: .leading, spacing: 12) {
                        VStack(alignment: .leading, spacing: 8) {
                            SectionLabel(text: L("Who is with you"))
                            FlowRow(spacing: 8, lineSpacing: 8) {
                                ForEach(others) { other in
                                    Chip(title: other.displayName, selected: chosen == other.id,
                                         accent: ProfileAccent.colour(other.accent)) {
                                        store.config.partnerProfileID = other.id
                                    }
                                }
                            }
                        }

                        Rule()

                        VStack(alignment: .leading, spacing: 8) {
                            SectionLabel(text: L("How you want to work"))
                            ForEach(DoubleLayout.allCases, id: \.self) { layout in
                                layoutRow(layout)
                            }
                        }

                        Text(L("Everything below is yours to set as usual — how many "
                               + "questions, which ones, and a clock if you want one. "
                               + "A full test is the one thing a sitting for two "
                               + "cannot be: its second module is chosen by how a "
                               + "single student did in the first."))
                            .font(Face.ui(11))
                            .foregroundStyle(Palette.brass)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .transition(.opacity)
                }
            }
        }
    }

    private func layoutRow(_ layout: DoubleLayout) -> some View {
        let selected = store.config.doubleLayout == layout
        return Button {
            withAnimation(Motion.quick) { store.config.doubleLayout = layout }
        } label: {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: selected ? "largecircle.fill.circle" : "circle")
                    .font(.system(size: 13))
                    .foregroundStyle(selected ? Palette.brass : Palette.border)
                VStack(alignment: .leading, spacing: 2) {
                    Text(layout.title)
                        .font(Face.ui(12, .semibold))
                        .foregroundStyle(Palette.text)
                    Text(layout.detail)
                        .font(Face.ui(10.5))
                        .foregroundStyle(Palette.textMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var fullTestCard: some View {
        let readiness = store.fullTestReadiness(for: store.config)
        let on = store.config.fullTest
        return Panel {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 8) {
                            Text(L("Sit a full test"))
                                .font(Face.display(15, .semibold))
                                .foregroundStyle(Palette.navy)
                            if !readiness.isReady {
                                Text(L("not enough questions"))
                                    .font(Face.ui(9, .semibold))
                                    .tracking(0.6)
                                    .foregroundStyle(Palette.textMuted)
                                    .padding(.horizontal, 7)
                                    .padding(.vertical, 2)
                                    .background(Palette.subtleFill)
                                    .clipShape(RoundedRectangle(cornerRadius: 2))
                            }
                        }
                        Text(Lf("%1$d Reading and Writing and %2$d Math, in four timed modules "
                             + "with a %3$d-minute break — %4$d minutes of testing.",
                             TestForm.readingWritingNeeded, TestForm.mathNeeded,
                             TestForm.breakMinutes, TestForm.totalMinutes))
                            .font(Face.ui(11))
                            .foregroundStyle(Palette.textMuted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 8)
                    Toggle("", isOn: Binding(
                        get: { store.config.fullTest },
                        set: {
                            store.config.fullTest = $0
                            if !$0 { store.config.adaptive = false }
                        }))
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .disabled(!readiness.isReady || store.config.isDouble)
                }

                if let shortfall = readiness.shortfall {
                    Text(shortfall)
                        .font(Face.ui(11))
                        .foregroundStyle(Palette.textMuted)
                        .fixedSize(horizontal: false, vertical: true)
                } else if on {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(Array(TestForm.digital.enumerated()), id: \.offset) { _, part in
                            HStack(spacing: 8) {
                                Rectangle().fill(Palette.brass.opacity(0.55))
                                    .frame(width: 2, height: 13)
                                Text(Lf("%1$@ · %2$d questions · %3$d min", part.subject.sectionLabel,
                                        part.questions, part.minutes))
                                    .font(Face.ui(11))
                                    .foregroundStyle(Palette.text)
                                Spacer(minLength: 0)
                                if part.breakAfter > 0 {
                                    Text(Lf("then a %d min break", part.breakAfter))
                                        .font(Face.ui(10))
                                        .foregroundStyle(Palette.brass)
                                }
                            }
                        }
                        adaptiveRow
                        Text(L("Each module is timed on its own and cannot be reopened "
                             + "once handed in, the same as on the real test."))
                            .font(Face.ui(10))
                            .foregroundStyle(Palette.textMuted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }

    private var adaptiveRow: some View {
        let readiness = store.adaptiveReadiness(for: store.config)
        return VStack(alignment: .leading, spacing: 6) {
            Rule().padding(.vertical, 2)
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(L("Adaptive second module"))
                        .font(Face.ui(12, .semibold))
                        .foregroundStyle(Palette.text)
                    Text(store.config.adaptive
                         ? L("Module 1 is a mix of all three difficulties. How it goes "
                             + "decides whether module 2 is the easier or the harder form, "
                             + "the way the real test routes you.")
                         : L("Module 2 is simply the next set of questions. Turn this on to "
                             + "be routed to an easier or harder module 2 by how module 1 "
                             + "goes."))
                        .font(Face.ui(10))
                        .foregroundStyle(Palette.textMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                Toggle("", isOn: Binding(
                    get: { store.config.adaptive },
                    set: { store.config.adaptive = $0 }))
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .disabled(!readiness.isReady)
            }

            if let shortfall = readiness.shortfall {
                Text(shortfall)
                    .font(Face.ui(10))
                    .foregroundStyle(Palette.textMuted)
                    .fixedSize(horizontal: false, vertical: true)
            } else if store.config.adaptive {
                Text(Lf("The routing cut is %d%% of module 1. The College Board does not publish theirs, so this one is ours.",
                             Int(TestForm.upperThreshold * 100)))
                    .font(Face.ui(10))
                    .foregroundStyle(Palette.textMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var namePlaceholder: String {
        let subjects = store.config.subjects
        if subjects.count > 1 { return L("Name this sitting") }
        guard let subject = subjects.first else { return L("Name this sitting") }
        return Lf("%@ practice", subject.sectionLabel)
    }

    private func summary(_ planned: (readingWriting: Int, math: Int, minutes: Int)) -> String {
        var parts = [String]()
        let total = planned.readingWriting + planned.math
        parts.append(Lp(total, "%d question", "%d questions"))
        if planned.readingWriting > 0 && planned.math > 0 {
            parts.append(Lf("%1$d R&W · %2$d math", planned.readingWriting, planned.math))
        }
        if store.config.hasFilters { parts.append(filterSummary) }
        parts.append(store.config.timed ? Lf("%d min", store.config.minutes) : L("untimed"))
        if store.config.grading == .immediate { parts.append(L("graded as you go")) }
        return parts.joined(separator: " · ")
    }
}

struct PinnedStartBar<Content: View>: View {
    let width: CGFloat
    let padding: CGFloat
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(spacing: 0) {
            content()
                .padding(.horizontal, padding)
                .padding(.vertical, 12)
                .frame(maxWidth: width, alignment: .leading)
                .frame(maxWidth: .infinity)
            Rule()
        }
        .background(Palette.paper)
    }
}
