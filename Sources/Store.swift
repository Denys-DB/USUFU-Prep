import Foundation
import SwiftUI
import AppKit

@MainActor
final class AppStore: ObservableObject {

    @Published var banks: [Bank] = []
    @Published var progress: [String: BankProgress] = [:]
    @Published var config = StudyConfig()
    @Published var session: Session? {
        didSet { updateSittingQuiet() }
    }
    @Published private(set) var savedSessionsRevision = 0
    @Published var lastError: String?
    @Published var importWarnings: [String] = []

    @Published var decks: [Deck] = []
    @Published var selectedDeckID: UUID?
    @Published var deckSessions: [UUID: DeckSession] = [:]
    @Published var deckTab: DeckView.Tab = .flashcards
    @Published var focus: DeckFocus?

    @Published var learning: String?

    @Published var lastArticleRead: String?

    func openArticle(_ id: String) {
        selectedDeckID = nil
        focus = nil
        lastArticleRead = id
        learning = id
    }

    func openLearn() {
        selectedDeckID = nil
        focus = nil
        learning = ""
    }

    func closeLearn() { learning = nil }

    var learnCoversResults: Bool {
        guard learning != nil else { return false }
        if let s = session { return s.isFinished }
        return false
    }

    let root: URL

    private(set) var profileRoot: URL

    @Published private(set) var profiles: ProfileStore
    @Published private(set) var profile: Profile

    init(root overrideRoot: URL? = nil) {
        if let overrideRoot {
            root = overrideRoot
        } else {
            let base = FileManager.default.urls(for: .applicationSupportDirectory,
                                                in: .userDomainMask).first!
            root = base.appendingPathComponent("SAT Prep", isDirectory: true)
        }
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let suggested = NSFullUserName().split(separator: " ").first.map(String.init)
        let book = ProfileStore.open(sharedRoot: root,
                                     defaultName: suggested?.isEmpty == false
                                         ? suggested! : L("Student"))
        profiles = book
        profile = book.current
        profileRoot = book.directory(of: book.current.id)
        try? FileManager.default.createDirectory(at: profileRoot, withIntermediateDirectories: true)
        loadAll()
        if let moved = book.recoveredFrom { noteDamaged(moved) }
    }

    func use(profile new: Profile) {
        guard new.id != profile.id else { return }
        saveSession()
        session = nil
        focus = nil
        deckSessions = [:]
        selectedDeckID = nil
        profiles.markUsed(new.id)
        profile = new
        profileRoot = profiles.directory(of: new.id)
        try? FileManager.default.createDirectory(at: profileRoot, withIntermediateDirectories: true)
        config = StudyConfig()
        loadAll()
        refreshReminders()
    }

    func addProfile(named name: String) -> Profile { profiles.add(named: name) }
    func renameProfile(_ id: String, to name: String) {
        profiles.rename(id, to: name)
        if id == profile.id, let updated = profiles.profiles.first(where: { $0.id == id }) {
            profile = updated
        }
    }
    func setProfileAccent(_ id: String, to accent: Int) {
        profiles.setAccent(id, to: accent)
        if id == profile.id, let updated = profiles.profiles.first(where: { $0.id == id }) {
            profile = updated
        }
    }
    func deleteProfile(_ id: String) {
        let wasCurrent = id == profile.id
        guard profiles.remove(id) else { return }
        if wasCurrent, let next = profiles.profiles.first {
            profile = next
            profileRoot = profiles.directory(of: next.id)
            session = nil
            focus = nil
            deckSessions = [:]
            selectedDeckID = nil
            config = StudyConfig()
            loadAll()
        }
    }

    private var banksDir: URL { root.appendingPathComponent("Banks", isDirectory: true) }
    private var progressDir: URL { profileRoot.appendingPathComponent("Progress", isDirectory: true) }
    private var sessionsDir: URL { profileRoot.appendingPathComponent("Sessions", isDirectory: true) }
    private var notesDir: URL { profileRoot.appendingPathComponent("Notes", isDirectory: true) }
    var decksDir: URL { profileRoot.appendingPathComponent("Decks", isDirectory: true) }

    func bankDir(_ id: String) -> URL { banksDir.appendingPathComponent(id, isDirectory: true) }
    func imagesDir(_ bankID: String) -> URL {
        bankDir(bankID).appendingPathComponent("images", isDirectory: true)
    }
    func sourcesDir(_ bankID: String) -> URL {
        bankDir(bankID).appendingPathComponent("sources", isDirectory: true)
    }
    func exportsDir(_ bankID: String) -> URL {
        bankDir(bankID).appendingPathComponent("exports", isDirectory: true)
    }

    @Published var loadFailures: [String] = []

    @Published var damagedFiles: [String] = []

    func noteDamaged(_ url: URL) {
        let base = root.standardizedFileURL.path + "/"
        let path = url.standardizedFileURL.path
        let shown = path.hasPrefix(base) ? String(path.dropFirst(base.count)) : url.lastPathComponent
        if !damagedFiles.contains(shown) { damagedFiles.append(shown) }
    }

    @Published var pending: [PortableProfile.BankBlock] = []

    @Published var annotations: [String: [Annotation]] = [:]

    private func loadAll() {
        loadFailures = []
        let pending = profileRoot.appendingPathComponent(Self.takenOffFile)
        highlightsTakenOff = (try? String(contentsOf: pending, encoding: .utf8))
            .flatMap { Int($0.trimmingCharacters(in: .whitespacesAndNewlines)) } ?? 0
        try? FileManager.default.removeItem(at: pending)
        for dir in [banksDir, progressDir, sessionsDir, notesDir, decksDir] {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        banks = (try? FileManager.default.contentsOfDirectory(at: banksDir,
                                                              includingPropertiesForKeys: nil))?
            .compactMap { dir -> Bank? in
                let file = dir.appendingPathComponent("bank.json")
                guard FileManager.default.fileExists(atPath: file.path) else {
                    if Self.holdsSetAside(dir) { loadFailures.append(dir.lastPathComponent) }
                    return nil
                }
                do {
                    return try JSONDecoder().decode(Bank.self, from: Data(contentsOf: file))
                } catch {
                    loadFailures.append(dir.lastPathComponent)
                    noteDamaged(DamagedFile.setAside(file) ?? file)
                    return nil
                }
            }
            .sorted { $0.createdAt > $1.createdAt } ?? []

        for bank in banks {
            progress[bank.id] = loadProgress(bank.id)
            annotations[bank.id] = loadAnnotations(bank.id)
            _ = DamagedFile.load(Session.self,
                                 from: sessionsDir.appendingPathComponent("\(bank.id).json"),
                                 damaged: noteDamaged)
        }
        removeAbandonedImports()
        loadDecks()
        loadSettings()
        loadLayout()
        loadPending()
        if let waiting = setsWithSavedSittings().first {
            config.bankID = waiting.bank.id
        }
        if config.bankID.isEmpty { config.bankID = banks.first?.id ?? "" }
    }

    nonisolated static func holdsSetAside(_ dir: URL) -> Bool {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []
        return names.contains { DamagedFile.isSetAside($0) }
    }

    private func removeAbandonedImports() {
        let fm = FileManager.default
        guard let dirs = try? fm.contentsOfDirectory(at: banksDir,
                                                     includingPropertiesForKeys: nil) else { return }
        for dir in dirs {
            guard dir.hasDirectoryPath,
                  !fm.fileExists(atPath: dir.appendingPathComponent("bank.json").path),
                  !Self.holdsSetAside(dir) else { continue }
            let sources = (try? fm.contentsOfDirectory(
                at: dir.appendingPathComponent("sources"),
                includingPropertiesForKeys: nil)) ?? []
            guard sources.isEmpty else { continue }
            try? fm.removeItem(at: dir)
        }
    }

    private func loadProgress(_ bankID: String) -> BankProgress {
        let file = progressDir.appendingPathComponent("\(bankID).json")
        return DamagedFile.load(BankProgress.self, from: file, damaged: noteDamaged)
            ?? BankProgress(bankID: bankID)
    }

    func saveProgress(_ bankID: String) {
        guard let p = progress[bankID] else { return }
        let file = progressDir.appendingPathComponent("\(bankID).json")
        try? JSONEncoder().encode(p).write(to: file, options: .atomic)
    }

    private func saveBank(_ bank: Bank) {
        let dir = bankDir(bank.id)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try? JSONEncoder().encode(bank).write(to: dir.appendingPathComponent("bank.json"),
                                              options: .atomic)
    }

    struct ImportProgress: Equatable {
        var fraction: Double
        var message: String
    }
    @Published var importing: ImportProgress?
    var importNoticeBankID: String?

    func importPDFs(urls: [URL], into existingBankID: String? = nil,
                    progressHandler: @escaping (Double, String) -> Void = { _, _ in }) async {
        guard !urls.isEmpty else { return }
        lastError = nil
        importWarnings = []
        importing = ImportProgress(fraction: 0, message: L("Reading…"))
        defer { importing = nil }

        let bankID = existingBankID ?? UUID().uuidString
        let imagesDirectory = imagesDir(bankID)
        var collected = [Question]()
        var warnings = [String]()

        for (i, url) in urls.enumerated() {
            let share = 1.0 / Double(urls.count)
            do {
                ExportedBankReader.restoreImages(url: url, into: imagesDirectory)
                let result = try await Self.read(url, into: imagesDirectory) { p, msg in
                    Task { @MainActor in
                        let done = Double(i) * share + p * share
                        self.importing = ImportProgress(fraction: done, message: msg)
                        progressHandler(done, msg)
                    }
                }
                collected += result.questions
                warnings += result.warnings
                archiveSource(url, bankID: bankID)
            } catch {
                lastError = error.localizedDescription
                warnings.append(error.localizedDescription)
            }
        }

        guard !collected.isEmpty else {
            if existingBankID == nil { try? FileManager.default.removeItem(at: bankDir(bankID)) }
            if lastError == nil { lastError = L("No questions could be read from those files.") }
            importWarnings = warnings
            importNoticeBankID = config.bankID
            return
        }

        var bank: Bank
        if let existing = existingBankID, let idx = banks.firstIndex(where: { $0.id == existing }) {
            let previous = banks[idx]
            let known = Set(previous.questions.map(\.id))
            bank = Bank(id: previous.id, name: previous.name, createdAt: previous.createdAt,
                        questions: previous.questions + collected.filter { !known.contains($0.id) },
                        parserVersion: previous.parserVersion)
            banks[idx] = bank
        } else {
            let name = urls.count == 1
                ? urls[0].deletingPathExtension().lastPathComponent
                : Lp(urls.count, "%d file", "%d files") + " — " + Self.dateStamp()
            var seen = Set<String>()
            let unique = collected.filter { seen.insert($0.id).inserted }
            if let twin = banks.first(where: { Set($0.questions.map(\.id)) == seen }) {
                try? FileManager.default.removeItem(at: bankDir(bankID))
                lastError = Lf("Every question in that file is already in “%@”, so no new set was made.", twin.name)
                importNoticeBankID = twin.id
                config.bankID = twin.id
                importWarnings = warnings
                return
            }
            bank = Bank(id: bankID, name: name, createdAt: Date(), questions: unique)
            banks.insert(bank, at: 0)
        }

        saveBank(bank)
        if progress[bank.id] == nil { progress[bank.id] = BankProgress(bankID: bank.id) }
        var next = layout
        next.reconcile(with: banks)
        layout = next
        importNoticeBankID = bank.id
        config.bankID = bank.id
        importWarnings = warnings
    }

    private nonisolated static func read(
        _ url: URL, into imagesDirectory: URL,
        progress: @escaping @Sendable (Double, String) -> Void) async throws -> ImportResult {
        try await Task.detached(priority: .userInitiated) {
            try Importer.importPDF(at: url, imagesDirectory: imagesDirectory,
                                   progress: progress)
        }.value
    }

    private static func dateStamp() -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: Localisation.current.localeIdentifier)
        f.dateFormat = "d MMM"
        return f.string(from: Date())
    }

    func deleteBank(_ bank: Bank) {
        banks.removeAll { $0.id == bank.id }
        var next = layout
        next.remove(bank.id)
        layout = next
        progress[bank.id] = nil
        try? FileManager.default.removeItem(at: bankDir(bank.id))
        try? FileManager.default.removeItem(at: progressDir.appendingPathComponent("\(bank.id).json"))
        try? FileManager.default.removeItem(at: sessionsDir.appendingPathComponent("\(bank.id).json"))
        if config.bankID == bank.id { config.bankID = banks.first?.id ?? "" }
    }

    func renameBank(_ bank: Bank, to name: String) {
        guard let idx = banks.firstIndex(where: { $0.id == bank.id }) else { return }
        banks[idx].name = name
        saveBank(banks[idx])

        if session?.bankID == bank.id { session?.bankName = name }
        if var saved = savedSession(for: bank.id), saved.bankName != name {
            saved.bankName = name
            write(session: saved)
        }
        renameSourceBank(id: bank.id, to: name)
    }

    func bank(_ id: String) -> Bank? { banks.first { $0.id == id } }

    @Published var settings = AppSettings() {
        didSet {
            guard settings != oldValue else { return }
            Motion.reducedByChoice = settings.reduceMotion
            Localisation.use(settings.language)
            Paper.stealth = settings.stealthMode
            Reminders.silent = settings.stealthMode
            updateSittingQuiet()
            saveSettings()
        }
    }

    @Published var layout = LibraryLayout() {
        didSet {
            guard layout != oldValue else { return }
            layout.reconcile(with: banks)
            saveLayout()
        }
    }

    private var layoutFile: URL { profileRoot.appendingPathComponent("Library.json") }

    private func loadLayout() {
        layout = DamagedFile.load(LibraryLayout.self, from: layoutFile, damaged: noteDamaged)
            ?? LibraryLayout()
        layout.reconcile(with: banks)
    }

    private func saveLayout() {
        try? JSONEncoder().encode(layout).write(to: layoutFile, options: .atomic)
    }

    struct Shelved: Identifiable {
        var shelf: Shelf?
        var banks: [Bank]
        var id: String { shelf?.id.uuidString ?? "unshelved" }
        var title: String { shelf?.name ?? L("Unshelved") }
    }

    func shelved() -> [Shelved] {
        let byID = Dictionary(banks.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        var out = layout.shelves.map {
            Shelved(shelf: $0,
                    banks: ShelfSorter.arrange($0.bankIDs, order: layout.order,
                                               banks: byID, progress: progress))
        }
        let loose = ShelfSorter.arrange(layout.unshelved, order: layout.order,
                                        banks: byID, progress: progress)
        if !loose.isEmpty || layout.shelves.isEmpty {
            out.append(Shelved(shelf: nil, banks: loose))
        }
        return out
    }

    func addShelf(named name: String? = nil) {
        var next = layout
        _ = next.addShelf(named: name ?? layout.freshShelfName())
        layout = next
    }

    func renameShelf(_ id: UUID, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let index = layout.shelves.firstIndex(where: { $0.id == id })
        else { return }
        var next = layout
        next.shelves[index].name = trimmed
        layout = next
    }

    func removeShelf(_ id: UUID) {
        var next = layout
        next.removeShelf(id)
        layout = next
    }

    func moveShelf(_ id: UUID, by delta: Int) {
        var next = layout
        next.moveShelf(id, by: delta)
        layout = next
    }

    func setShelfCollapsed(_ id: UUID, _ collapsed: Bool) {
        guard let index = layout.shelves.firstIndex(where: { $0.id == id }) else { return }
        var next = layout
        next.shelves[index].collapsed = collapsed
        layout = next
    }

    func move(bank bankID: String, toShelf shelfID: UUID?, at position: Int? = nil) {
        var next = layout
        next.move(bankID, to: shelfID, at: position)
        layout = next
    }

    func move(bank bankID: String, by delta: Int) {
        var next = layout
        let shelfID = next.shelf(of: bankID)?.id
        var list = shelfID.flatMap { id in next.shelves.first { $0.id == id }?.bankIDs }
            ?? next.unshelved
        guard let index = list.firstIndex(of: bankID) else { return }
        let target = min(max(0, index + delta), list.count - 1)
        guard target != index else { return }
        list.remove(at: index)
        list.insert(bankID, at: target)
        if let shelfID, let i = next.shelves.firstIndex(where: { $0.id == shelfID }) {
            next.shelves[i].bankIDs = list
        } else {
            next.unshelved = list
        }
        layout = next
    }
    @Published var presets: [StudyPreset] = []

    private var settingsFile: URL { profileRoot.appendingPathComponent("Settings.json") }
    private var presetsFile: URL { profileRoot.appendingPathComponent("Plans.json") }

    private func loadSettings() {
        settings = DamagedFile.load(AppSettings.self, from: settingsFile, damaged: noteDamaged)
            ?? AppSettings()
        Motion.reducedByChoice = settings.reduceMotion
        Localisation.use(settings.language)
        Paper.stealth = settings.stealthMode
        Reminders.silent = settings.stealthMode
        presets = DamagedFile.load([StudyPreset].self, from: presetsFile, damaged: noteDamaged) ?? []
    }

    private func saveSettings() {
        try? JSONEncoder().encode(settings).write(to: settingsFile, options: .atomic)
    }

    func savePresets() {
        try? JSONEncoder().encode(presets).write(to: presetsFile, options: .atomic)
    }

    func savePreset(named name: String, config: StudyConfig) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        var stored = config
        stored.bankID = ""
        if let idx = presets.firstIndex(where: {
            $0.name.caseInsensitiveCompare(trimmed) == .orderedSame
        }) {
            presets[idx].config = stored
        } else {
            presets.append(StudyPreset(name: trimmed, config: stored))
        }
        savePresets()
    }

    func deletePreset(_ preset: StudyPreset) {
        presets.removeAll { $0.id == preset.id }
        savePresets()
    }

    func applyPreset(_ preset: StudyPreset) {
        config = resolved(preset)
    }

    func isApplied(_ preset: StudyPreset) -> Bool {
        resolved(preset) == config
    }

    private func resolved(_ preset: StudyPreset) -> StudyConfig {
        var c = preset.config
        c.bankID = config.bankID
        if let bank = bank(config.bankID) { c.trim(to: bank) }
        return c
    }

    func answersByDay(calendar: Calendar = .current) -> [Date: Int] {
        var out = [Date: Int]()
        for row in progress.values.flatMap(\.history) where !row.backfilled {
            out[calendar.startOfDay(for: row.at), default: 0] += 1
        }
        return out
    }

    func streak(now: Date = Date()) -> StreakState {
        StreakEngine.evaluate(answers: answersByDay(), schedule: settings.schedule,
                              excused: Set(settings.excusedDays), now: now)
    }

    func returnGap(now: Date = Date()) -> Mercy.Gap? {
        Mercy.gap(answers: answersByDay(), schedule: settings.schedule,
                  excused: Set(settings.excusedDays), now: now)
    }

    func restorableGap(now: Date = Date()) -> Mercy.Gap? {
        guard settings.showQuestionStreak else { return nil }
        guard let gap = returnGap(now: now), gap.isRestorable,
              gap.daysAway >= Mercy.restoreAfter else { return nil }
        guard settings.restoreOfferedFor.map({ !Calendar.current.isDate($0, inSameDayAs: gap.lastActive) }) ?? true
        else { return nil }
        return gap
    }

    @discardableResult
    func restoreStreak(_ gap: Mercy.Gap) -> Int {
        var days = settings.excusedDays
        let known = Set(days.map { Calendar.current.startOfDay(for: $0) })
        let added = gap.missed.filter { !known.contains($0) }
        days.append(contentsOf: added)
        days.sort()
        if days.count > 600 { days.removeFirst(days.count - 600) }
        settings.excusedDays = days
        settings.restoreOfferedFor = gap.lastActive
        return added.count
    }

    func declineRestore(_ gap: Mercy.Gap) {
        settings.restoreOfferedFor = gap.lastActive
    }

    func lastActiveDay(calendar: Calendar = .current) -> Date? {
        var days = answersByDay(calendar: calendar).filter { $0.value > 0 }.keys.map { $0 }
        days.append(contentsOf: settings.vocabDaily.completedDays.map { calendar.startOfDay(for: $0) })
        return days.max()
    }

    struct WelcomeBack: Equatable {
        var lastActive: Date
        var daysAway: Int
        var skills: [String]
    }

    func welcomeBack(now: Date = Date(), calendar: Calendar = .current) -> WelcomeBack? {
        guard let last = lastActiveDay(calendar: calendar) else { return nil }
        let today = calendar.startOfDay(for: now)
        let away = calendar.dateComponents([.day], from: last, to: today).day ?? 0
        guard away >= Mercy.welcomeAfter else { return nil }
        guard settings.welcomeBackFor.map({ !calendar.isDate($0, inSameDayAs: last) }) ?? true
        else { return nil }

        var worst: [(String, Double)] = []
        for bank in banks {
            for row in builtStatistics(for: bank.id).weakest where row.attempts >= 3 {
                worst.append((row.label, row.accuracy))
            }
        }
        var seen = Set<String>()
        let skills = worst.sorted { $0.1 < $1.1 }
            .filter { seen.insert($0.0).inserted }
            .prefix(2)
            .map(\.0)
        return WelcomeBack(lastActive: last, daysAway: away, skills: Array(skills))
    }

    func dismissWelcomeBack(_ welcome: WelcomeBack) {
        settings.welcomeBackFor = welcome.lastActive
    }

    private var sittingIsQuiet = false

    private func updateSittingQuiet() {
        let wanted = settings.stealthMode && (session.map { !$0.isFinished } ?? false)
        guard wanted != sittingIsQuiet else { return }
        sittingIsQuiet = wanted
        if wanted {
            Reminders.hold()
        } else {
            Reminders.release()
            refreshReminders()
        }
    }

    func refreshReminders() {
        let schedule = settings.schedule
        let state = streak()
        Task {
            await Reminders.refreshPermission()
            await Reminders.reschedule(for: schedule)
            await Reminders.updateStreakWarning(state, schedule: schedule)
        }
    }

    func rhythm(now: Date = Date()) -> PracticeRhythm {
        let calendar = Calendar.current
        let rows = progress.values.flatMap(\.history).filter { !$0.backfilled }
        guard !rows.isEmpty else { return PracticeRhythm() }

        var out = PracticeRhythm()
        let today = calendar.startOfDay(for: now)
        out.answeredToday = rows.count { calendar.isDate($0.at, inSameDayAs: now) }
        if let weekAgo = calendar.date(byAdding: .day, value: -6, to: today) {
            out.answeredThisWeek = rows.count { $0.at >= weekAgo }
        }

        let days = Set(rows.map { calendar.startOfDay(for: $0.at) }).sorted()
        guard let last = days.last else { return out }

        var run = 1, best = 1
        for (a, b) in zip(days, days.dropFirst()) {
            let gap = calendar.dateComponents([.day], from: a, to: b).day ?? 0
            run = gap == 1 ? run + 1 : 1
            best = max(best, run)
        }
        out.bestStreak = best

        let sinceLast = calendar.dateComponents([.day], from: last, to: today).day ?? 99
        guard sinceLast <= 1 else { return out }
        var streak = 1
        var cursor = last
        for day in days.dropLast().reversed() {
            let gap = calendar.dateComponents([.day], from: day, to: cursor).day ?? 0
            if gap == 1 { streak += 1; cursor = day } else { break }
        }
        out.streak = streak
        return out
    }

    func availableCount(for config: StudyConfig) -> Int {
        selectPool(for: config).count
    }

    func splitDraw(for config: StudyConfig) -> Int {
        drawSplit(for: config, shuffled: false).count
    }

    func plannedSitting(for config: StudyConfig) -> (readingWriting: Int, math: Int, minutes: Int) {
        if config.hasSectionSplit {
            let drawn = drawSplit(for: config, shuffled: false)
            let rw = drawn.count { $0.subject == .readingWriting }
            return (rw, drawn.count - rw, Pace.minutes(readingWriting: rw, math: drawn.count - rw))
        }
        let pool = selectPool(for: config)
        let drawn = pool.prefix(max(1, min(config.questionCount, pool.count)))
        let rw = drawn.count { $0.subject == .readingWriting }
        let math = drawn.count { $0.subject == .math }
        return (rw, math, Pace.minutes(readingWriting: rw, math: math))
    }

    private func selectTiers(for config: StudyConfig) -> [[Question]] {
        guard let bank = bank(config.bankID) else { return [] }
        let prog = progress[bank.id] ?? BankProgress(bankID: bank.id)
        let subjectFiltered = bank.questions.filter { q in
            config.subjects.contains(q.subject)
                && (config.difficulties.isEmpty || config.difficulties.contains(q.difficulty))
                && (config.assessments.isEmpty || config.assessments.contains(q.assessment))
                && (config.domains.isEmpty || config.domains.contains(q.domain))
                && (config.skills.isEmpty || config.skills.contains(q.skill))
        }

        switch config.selection {
        case .all:
            return [subjectFiltered]
        case .reviewMissed:
            return [subjectFiltered.filter { prog.lastWrong($0.id) }]
        case .setAside:
            return [subjectFiltered.filter { prog.isSetAside($0.id) }]
        case .unseenOnly:
            return [subjectFiltered.filter { !prog.seen($0.id) && !prog.isSetAside($0.id) }]
        case .dueForReview:
            let now = Date()
            let due = subjectFiltered.compactMap { q -> (Question, TimeInterval)? in
                guard let r = prog.records[q.id], ReviewSchedule.isDue(r, now: now) else { return nil }
                return (q, ReviewSchedule.overdueBy(r, now: now))
            }
            return [due.sorted { $0.1 > $1.1 }.map(\.0)]
        case .weakestSkills:
            let weak = Set(weakestSkills(in: bank.id))
            guard !weak.isEmpty else { return [] }
            let pool = subjectFiltered.filter { weak.contains($0.skill) }
            let missed = pool.filter { prog.lastWrong($0.id) }
            let unseen = pool.filter { !prog.seen($0.id) }
            let rest = pool.filter { prog.seen($0.id) && !prog.lastWrong($0.id) }
            return [missed, unseen, rest]
        case .newFirst:
            let unseen = subjectFiltered.filter { !prog.seen($0.id) }
            let missed = subjectFiltered.filter { prog.seen($0.id) && prog.lastWrong($0.id) }
            let rest = subjectFiltered.filter { prog.seen($0.id) && !prog.lastWrong($0.id) }
            return [unseen, missed, rest]
        }
    }

    func weakestSkills(in bankID: String, limit: Int = 3,
                       below: Double = 0.9) -> [String] {
        builtStatistics(for: bankID).weakest
            .filter { $0.accuracy < below }
            .prefix(limit)
            .map(\.label)
    }

    func nextReviewDue(in bankID: String) -> Date? {
        guard let bank = bank(bankID), let prog = progress[bankID] else { return nil }
        let ids = Set(bank.questions.map(\.id))
        return ReviewSchedule.nextDue(prog.records.filter { ids.contains($0.key) }.map(\.value))
    }

    private func selectPool(for config: StudyConfig) -> [Question] {
        selectTiers(for: config).flatMap { $0 }
    }

    private func drawSplit(for config: StudyConfig, shuffled: Bool) -> [Question] {
        var out = [Question]()
        for subject in [Subject.readingWriting, Subject.math]
        where config.subjects.contains(subject) {
            let want = config.count(for: subject)
            guard want > 0 else { continue }
            var one = config
            one.subjects = [subject]
            var tiers = selectTiers(for: one)
            if shuffled { tiers = tiers.map { $0.shuffled() } }
            out += tiers.flatMap { $0 }.prefix(want)
        }
        return out
    }

    func available(for config: StudyConfig, in subject: Subject) -> Int {
        var one = config
        one.subjects = [subject]
        one.sectionCounts = [:]
        return selectPool(for: one).count
    }

    @Published var rereadingBankIDs: Set<String> = []
    @Published var highlightsTakenOff = 0

    func rereadStaleBanks() async {
        defer { importing = nil }
        for bank in banks where needsReread(bank) {
            rereadingBankIDs.insert(bank.id)
            await reread(bankID: bank.id) { _, _ in }
            rereadingBankIDs.remove(bank.id)
        }
    }

    func needsReread(_ bank: Bank) -> Bool {
        bank.parserVersion < QuestionParser.version && !archivedSources(bank.id).isEmpty
    }

    func offersReadAgain(_ bank: Bank) -> Bool {
        needsReread(bank) && rereadingBankIDs.isEmpty
    }

    func archivedSources(_ bankID: String) -> [URL] {
        let dir = sourcesDir(bankID)
        let files = (try? FileManager.default.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: nil)) ?? []
        return files.filter { $0.pathExtension.lowercased() == "pdf" }.sorted {
            $0.lastPathComponent < $1.lastPathComponent
        }
    }

    func reread(bankID: String, progressHandler: @escaping (Double, String) -> Void) async {
        guard let index = banks.firstIndex(where: { $0.id == bankID }) else { return }
        let sources = archivedSources(bankID)
        guard !sources.isEmpty else { return }

        let name = banks[index].name
        let imagesDirectory = imagesDir(bankID)
        var collected = [Question]()
        var seen = Set<String>()
        var warnings = [String]()

        for (i, url) in sources.enumerated() {
            let share = 1.0 / Double(sources.count)
            do {
                let result = try await Self.read(url, into: imagesDirectory) { fraction, message in
                    Task { @MainActor in
                        let done = Double(i) * share + fraction * share
                        self.importing = ImportProgress(fraction: done, message: message)
                        progressHandler(done, message)
                    }
                }
                warnings += result.warnings
                for q in result.questions where !seen.contains(q.id) {
                    seen.insert(q.id)
                    collected.append(q)
                }
            } catch {
                warnings.append("\(url.lastPathComponent): \(error.localizedDescription)")
            }
        }

        guard !collected.isEmpty else {
            lastError = L("Could not read that set again; it has been left as it was.")
            return
        }
        let carried = Self.rehomed(annotations[bankID] ?? [], from: banks[index].questions,
                                   to: collected)
        annotations[bankID] = carried.notes
        highlightsTakenOff += carried.takenOff
        saveAnnotations(bankID)
        rehomeOtherProfiles(bankID, from: banks[index].questions, to: collected)
        banks[index] = Bank(id: bankID, name: name, createdAt: banks[index].createdAt,
                            questions: collected, parserVersion: QuestionParser.version)
        importWarnings = warnings
        saveBank(banks[index])

        if let open = session, open.bankID == bankID {
            session = refreshed(open)
        }
        if let saved = savedSession(for: bankID) {
            var updated = refreshed(saved)
            updated.bankName = banks[index].name
            write(session: updated)
        }
    }

    static func rehomed(_ list: [Annotation], from old: [Question],
                        to new: [Question]) -> (notes: [Annotation], takenOff: Int) {
        let before = Dictionary(old.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let after = Dictionary(new.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        var out = [Annotation](), takenOff = 0
        for a in list {
            guard a.start < a.end, let now = after[a.questionID],
                  let marked = a.marked ?? before[a.questionID].flatMap({ markedWords(a, in: $0) })
            else { out.append(a); continue }
            let fresh = now.blocks(a.field)
            var kept = a
            kept.marked = marked
            if markedWords(a, in: now) == marked {
                out.append(kept)
                continue
            }
            var places = [(block: Int, start: Int)]()
            let want = Array(marked)
            for (i, b) in fresh.enumerated() where b.kind == .text {
                let text = Array(b.text)
                guard want.count <= text.count else { continue }
                for at in 0...(text.count - want.count) where Array(text[at..<(at + want.count)]) == want {
                    places.append((i, at))
                }
            }
            if places.count == 1 {
                kept.blockIndex = places[0].block
                kept.start = places[0].start
                kept.end = places[0].start + want.count
                out.append(kept)
                continue
            }
            takenOff += 1
            if a.hasNote {
                kept.blockIndex = fresh.count
                kept.start = 0
                kept.end = 0
                kept.marked = nil
                out.append(kept)
            }
        }
        return (out, takenOff)
    }

    func rehomeOtherProfiles(_ bankID: String, from old: [Question], to new: [Question]) {
        for other in profiles.profiles where other.id != profile.id {
            let dir = profiles.directory(of: other.id)
            let file = dir.appendingPathComponent("Notes", isDirectory: true)
                .appendingPathComponent("\(bankID).json")
            guard let data = try? Data(contentsOf: file),
                  let list = try? JSONDecoder().decode([Annotation].self, from: data),
                  !list.isEmpty else { continue }
            let carried = Self.rehomed(list, from: old, to: new)
            if let out = try? JSONEncoder().encode(carried.notes) {
                try? out.write(to: file, options: .atomic)
            }
            if carried.takenOff > 0 {
                let pending = dir.appendingPathComponent(Self.takenOffFile)
                let was = (try? String(contentsOf: pending, encoding: .utf8))
                    .flatMap { Int($0.trimmingCharacters(in: .whitespacesAndNewlines)) } ?? 0
                try? String(was + carried.takenOff).write(to: pending, atomically: true, encoding: .utf8)
            }
        }
    }

    static let takenOffFile = "HighlightsTakenOff.txt"

    static func markedWords(_ a: Annotation, in q: Question) -> String? {
        let b = q.blocks(a.field)
        guard a.blockIndex >= 0, a.blockIndex < b.count, b[a.blockIndex].kind == .text else { return nil }
        let chars = Array(b[a.blockIndex].text)
        guard a.start >= 0, a.end <= chars.count, a.start < a.end else { return nil }
        return String(chars[a.start..<a.end])
    }

    func annotations(for questionID: String, in bankID: String) -> [Annotation] {
        (annotations[bankID] ?? []).filter { $0.questionID == questionID }
            .sorted { ($0.blockIndex, $0.start) < ($1.blockIndex, $1.start) }
    }

    func annotationCount(for questionID: String, in bankID: String) -> Int {
        (annotations[bankID] ?? []).count { $0.questionID == questionID }
    }

    func addAnnotation(_ a: Annotation, in bankID: String) {
        var list = annotations[bankID] ?? []
        var merged = a
        list.removeAll { other in
            guard other.questionID == a.questionID, other.field == a.field,
                  other.blockIndex == a.blockIndex,
                  other.start <= merged.end, other.end >= merged.start else { return false }
            merged.start = min(merged.start, other.start)
            merged.end = max(merged.end, other.end)
            if merged.note.isEmpty { merged.note = other.note }
            return true
        }
        if let q = bank(bankID)?.questions.first(where: { $0.id == a.questionID }) {
            merged.marked = Self.markedWords(merged, in: q)
        }
        list.append(merged)
        annotations[bankID] = list
        saveAnnotations(bankID)
    }

    func updateAnnotation(_ a: Annotation, in bankID: String) {
        guard var list = annotations[bankID], let i = list.firstIndex(where: { $0.id == a.id })
        else { return }
        list[i] = a
        annotations[bankID] = list
        saveAnnotations(bankID)
    }

    func removeAnnotation(_ id: UUID, in bankID: String) {
        guard var list = annotations[bankID] else { return }
        list.removeAll { $0.id == id }
        annotations[bankID] = list
        saveAnnotations(bankID)
    }

    func clearAnnotations(for questionID: String, in bankID: String) {
        guard var list = annotations[bankID] else { return }
        list.removeAll { $0.questionID == questionID }
        annotations[bankID] = list
        saveAnnotations(bankID)
    }

    private func loadAnnotations(_ bankID: String) -> [Annotation] {
        let file = notesDir.appendingPathComponent("\(bankID).json")
        return DamagedFile.load([Annotation].self, from: file, damaged: noteDamaged) ?? []
    }

    func saveAnnotations(_ bankID: String) {
        try? FileManager.default.createDirectory(at: notesDir, withIntermediateDirectories: true)
        guard let data = try? JSONEncoder().encode(annotations[bankID] ?? []) else { return }
        try? data.write(to: notesDir.appendingPathComponent("\(bankID).json"), options: .atomic)
    }

    func backfillHistoryIfNeeded(_ bankID: String) {
        guard let bank = bank(bankID), var p = progress[bankID],
              p.history.isEmpty, !p.historyCleared, !p.records.isEmpty else { return }
        let byID = Dictionary(bank.questions.map { ($0.id, $0) },
                              uniquingKeysWith: { a, _ in a })
        var rows = [AttemptRecord]()
        for (id, record) in p.records where record.timesSeen > 0 {
            guard let q = byID[id] else { continue }
            let when = record.lastSeen ?? Date()
            for i in 0..<record.timesSeen {
                rows.append(AttemptRecord(question: q, correct: i < record.timesCorrect,
                                          at: when, secondsSpent: 0, backfilled: true))
            }
        }
        guard !rows.isEmpty else { return }
        p.history = rows.sorted { $0.at < $1.at }
        progress[bankID] = p
        saveProgress(bankID)
    }

    func statistics(for bankID: String, subjects: Set<Subject>? = nil) -> Statistics {
        statistics(for: bankID, filter: StatisticsFilter(subjects: subjects))
    }

    func statistics(for bankID: String, filter: StatisticsFilter) -> Statistics {
        backfillHistoryIfNeeded(bankID)
        return builtStatistics(for: bankID, filter: filter)
    }

    func builtStatistics(for bankID: String,
                                 subjects: Set<Subject>? = nil) -> Statistics {
        builtStatistics(for: bankID, filter: StatisticsFilter(subjects: subjects))
    }

    func builtStatistics(for bankID: String, filter: StatisticsFilter) -> Statistics {
        guard let bank = bank(bankID) else { return Statistics() }
        return StatisticsBuilder.build(history: progress[bankID]?.history ?? [],
                                       bank: bank, filter: filter)
    }

    func practiseSkill(_ skill: String, in bankID: String, count: Int = 10) {
        var c = config
        c.bankID = bankID
        c.selection = .all
        c.clearFilters()
        c.clearSectionSplit()
        c.skills = [skill]
        c.subjects = Set(Subject.allCases)
        c.questionCount = count
        c.mix = .mixed
        startSession(config: c)
    }

    func practiseSection(_ subject: Subject, in bankID: String, count: Int = 10) {
        var c = config
        c.bankID = bankID
        c.selection = .all
        c.clearFilters()
        c.subjects = [subject]
        c.clearSectionSplit()
        c.questionCount = count
        c.mix = .mixed
        startSession(config: c)
    }

    func clearHistory(in bankID: String) {
        guard var p = progress[bankID] else { return }
        p.history = []
        p.historyCleared = true
        progress[bankID] = p
        saveProgress(bankID)
    }

    func resetProgress(in bankID: String) {
        guard var p = progress[bankID] else { return }
        p.records = [:]
        p.history = []
        progress[bankID] = p
        saveProgress(bankID)
        if session?.bankID == bankID { closeSession() }
        discardSavedSession(for: bankID)
        refreshReminders()
    }

    func resetCost(in bankID: String) -> (seen: Int, answers: Int) {
        guard let p = progress[bankID] else { return (0, 0) }
        return (p.seenCount, p.history.count)
    }

    func isSetAside(_ questionID: String, in bankID: String) -> Bool {
        progress[bankID]?.isSetAside(questionID) ?? false
    }

    func toggleSetAside(_ questionID: String, in bankID: String) {
        var p = progress[bankID] ?? BankProgress(bankID: bankID)
        p.toggleSetAside(questionID)
        progress[bankID] = p
        saveProgress(bankID)
    }

    func setAsideCount(in bankID: String) -> Int {
        guard let bank = bank(bankID), let p = progress[bankID] else { return 0 }
        let ids = Set(bank.questions.map(\.id))
        return p.setAside.filter(ids.contains).count
    }

    func setAsideQuestions(in bankID: String) -> [Question] {
        guard let bank = bank(bankID), let p = progress[bankID] else { return [] }
        return bank.questions.filter { p.setAside.contains($0.id) }
    }

    func clearSetAside(in bankID: String) {
        guard var p = progress[bankID] else { return }
        p.setAside.removeAll()
        progress[bankID] = p
        saveProgress(bankID)
    }

    static func fullTestConfig(_ config: StudyConfig) -> StudyConfig {
        var c = config
        c.subjects = [.readingWriting, .math]
        c.selection = .newFirst
        c.difficulties = []
        c.assessments = []
        c.domains = []
        c.skills = []
        c.grading = .atEnd
        return c
    }

    func fullTestReadiness(for config: StudyConfig) -> TestForm.Readiness {
        let c = Self.fullTestConfig(config)
        let pool = selectPool(for: c)
        return TestForm.Readiness(
            readingWriting: pool.count { $0.subject == .readingWriting },
            math: pool.count { $0.subject == .math })
    }

    func adaptiveReadiness(for config: StudyConfig) -> TestForm.AdaptiveReadiness {
        let c = Self.fullTestConfig(config)
        let pool = selectPool(for: c)
        var counts = [Subject: [String: Int]]()
        for subject in Subject.allCases {
            var byDifficulty = [String: Int]()
            for label in TestForm.difficulties {
                byDifficulty[label] = pool.count { $0.subject == subject && $0.difficulty == label }
            }
            counts[subject] = byDifficulty
        }
        return TestForm.AdaptiveReadiness(counts: counts)
    }

    private func startAdaptiveTest(config: StudyConfig, bank: Bank) {
        let c = Self.fullTestConfig(config)

        let readiness = adaptiveReadiness(for: config)
        guard readiness.isReady else {
            lastError = readiness.shortfall
            return
        }

        func pools(_ subject: Subject) -> [String: [Question]] {
            var one = c
            one.subjects = [subject]
            let ordered = selectTiers(for: one).map { $0.shuffled() }.flatMap { $0 }
            var out = [String: [Question]]()
            for label in TestForm.difficulties {
                out[label] = ordered.filter { $0.difficulty == label }
            }
            return out
        }

        var firsts = [Subject: [Question]]()
        var options = [Subject: (lower: [Question], upper: [Question])]()
        for part in [Subject.readingWriting, Subject.math] {
            var pool = pools(part)
            let size = TestForm.AdaptiveReadiness.moduleSize(for: part)
            guard let one = TestForm.draw(.mixed, total: size, from: &pool),
                  let lower = TestForm.draw(.lower, total: size, from: &pool),
                  let upper = TestForm.draw(.upper, total: size, from: &pool) else {
                lastError = readiness.shortfall
                    ?? L("There are not enough questions at each difficulty for an "
                         + "adaptive test.")
                return
            }
            firsts[part] = one
            options[part] = (lower, upper)
        }

        guard let laid = TestForm.modules(
            readingWriting: (firsts[.readingWriting] ?? []) + (options[.readingWriting]?.lower ?? []),
            math: (firsts[.math] ?? []) + (options[.math]?.lower ?? [])) else { return }

        var s = Session(bankID: bank.id, bankName: bank.name, config: c,
                        questions: laid.questions,
                        attempts: laid.questions.map { Attempt(questionID: $0.id) },
                        modules: laid.modules)
        s.adaptive = laid.modules.filter { $0.number == 2 }.compactMap { module in
            guard let option = options[module.subject] else { return nil }
            return AdaptiveOption(moduleID: module.id, lower: option.lower, upper: option.upper)
        }
        ExamChrome.reset()
        session = s
        saveSession()
    }

    private func startFullTest(config: StudyConfig, bank: Bank) {
        let c = Self.fullTestConfig(config)

        func draw(_ subject: Subject) -> [Question] {
            var one = c
            one.subjects = [subject]
            var tiers = selectTiers(for: one)
            tiers = tiers.map { $0.shuffled() }
            return tiers.flatMap { $0 }
        }

        guard let laid = TestForm.modules(readingWriting: draw(.readingWriting),
                                          math: draw(.math)) else {
            lastError = fullTestReadiness(for: config).shortfall
                ?? L("There are not enough questions for a full test.")
            return
        }

        var s = Session(bankID: bank.id, bankName: bank.name, config: c,
                        questions: laid.questions,
                        attempts: laid.questions.map { Attempt(questionID: $0.id) },
                        modules: laid.modules)
        s.secondsRemaining = 0
        ExamChrome.reset()
        session = s
        saveSession()
    }

    func submitCurrentModule() {
        guard var s = session, let index = s.currentModuleIndex else { return }
        s.modules[index].submitted = true

        guard index + 1 < s.modules.count else {
            session = s
            finishSession()
            return
        }

        let next = index + 1
        if s.modules[next].number == 2, s.modules[next].subject == s.modules[index].subject {
            route(&s, first: index, second: next)
        }

        if s.modules[index].breakAfter > 0 {
            s.onBreak = true
            s.breakRemaining = Double(s.modules[index].breakAfter * 60)
        }
        s.currentIndex = s.modules[index + 1].start
        session = s
        saveSession()
    }

    private func route(_ s: inout Session, first: Int, second: Int) {
        guard let option = s.adaptive.first(where: { $0.moduleID == s.modules[second].id })
        else { return }
        let module = s.modules[first]
        let scored = s.score(of: module)
        let form = TestForm.route(correct: scored.correct, outOf: module.count)
        s.modules[second].form = form

        let questions = form == .upper ? option.upper : option.lower
        let range = s.modules[second].range
        guard questions.count == range.count else { return }
        for (offset, question) in questions.enumerated() {
            s.questions[range.lowerBound + offset] = question
            s.attempts[range.lowerBound + offset] = Attempt(questionID: question.id)
        }
    }

    func endBreak() {
        guard var s = session, s.onBreak else { return }
        s.onBreak = false
        s.breakRemaining = 0
        session = s
        saveSession()
    }

    func startSession(config: StudyConfig) {
        guard let bank = bank(config.bankID) else { return }
        var config = config
        if config.isDouble {
            guard partner(config.partnerProfileID) != nil else {
                lastError = L("That student is no longer on this computer.")
                return
            }
            config.fullTest = false
            config.adaptive = false
        }
        if config.fullTest {
            if config.adaptive { startAdaptiveTest(config: config, bank: bank) }
            else { startFullTest(config: config, bank: bank) }
            return
        }
        let shuffling = config.mix == .mixed || config.mix == .shuffledInSection

        if config.hasSectionSplit {
            let chosen = drawSplit(for: config, shuffled: shuffling)
            guard !chosen.isEmpty else {
                lastError = L("There are no questions matching those settings.")
                return
            }
            startSitting(config: config, bank: bank, chosen: chosen)
            return
        }

        var tiers = selectTiers(for: config)
        if config.mix == .mixed || config.mix == .shuffledInSection {
            tiers = tiers.map { $0.shuffled() }
        }
        let pool = tiers.flatMap { $0 }
        guard !pool.isEmpty else {
            lastError = L("There are no questions matching those settings.")
            return
        }

        let chosen = Array(pool.prefix(max(1, min(config.questionCount, pool.count))))
        startSitting(config: config, bank: bank, chosen: chosen)
    }

    private func startSitting(config: StudyConfig, bank: Bank, chosen drawn: [Question]) {
        var chosen = drawn

        switch config.mix {
        case .pdfOrder:
            let order = Dictionary(uniqueKeysWithValues: bank.questions.enumerated().map { ($0.element.id, $0.offset) })
            chosen.sort { (order[$0.id] ?? 0) < (order[$1.id] ?? 0) }
        case .sequential:
            let order = Dictionary(uniqueKeysWithValues: bank.questions.enumerated().map { ($0.element.id, $0.offset) })
            chosen.sort {
                if $0.subject != $1.subject { return $0.subject == .readingWriting }
                return (order[$0.id] ?? 0) < (order[$1.id] ?? 0)
            }
        case .shuffledInSection:
            chosen.shuffle()
            chosen = chosen.filter { $0.subject == .readingWriting }
                + chosen.filter { $0.subject == .math }
        case .mixed:
            chosen.shuffle()
        }

        var s = Session(bankID: bank.id, bankName: bank.name, config: config,
                        questions: chosen,
                        attempts: chosen.map { Attempt(questionID: $0.id) })
        s.secondsRemaining = config.timed ? Double(config.minutes * 60) : 0
        if config.isDouble, let other = partner(config.partnerProfileID) {
            s.partnerID = other.id
            s.turnNames = [profile.displayName, other.displayName]
            s.turnAccents = [profile.accent, other.accent]
            s.partnerIndex = s.positions(for: 1).first ?? 1
        }
        ExamChrome.reset()
        session = s
        saveSession()
    }

    func saveSession() {
        guard let s = session, !s.isFinished else { return }
        write(session: s)
    }

    private func write(session s: Session) {
        var s = s
        s.lastSavedAt = Date()
        let file = sessionsDir.appendingPathComponent("\(s.bankID).json")
        try? JSONEncoder().encode(s).write(to: file, options: .atomic)
    }

    func sizeOnDisk(of bankID: String) -> Int64 {
        let dir = banksDir.appendingPathComponent(bankID, isDirectory: true)
        guard let walker = FileManager.default.enumerator(
            at: dir, includingPropertiesForKeys: [.fileSizeKey]) else { return 0 }
        var total: Int64 = 0
        for case let url as URL in walker {
            total += Int64((try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0)
        }
        return total
    }

    func sizeOnDisk() -> Int64 {
        guard let walker = FileManager.default.enumerator(
            at: root, includingPropertiesForKeys: [.fileSizeKey]) else { return 0 }
        var total: Int64 = 0
        for case let url as URL in walker {
            total += Int64((try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0)
        }
        return total
    }

    func setsWithSavedSittings() -> [(bank: Bank, session: Session)] {
        banks.compactMap { bank in
            savedSession(for: bank.id).map { (bank: bank, session: $0) }
        }
        .sorted { $0.session.lastSavedAt > $1.session.lastSavedAt }
    }

    func savedSession(for bankID: String) -> Session? {
        let file = sessionsDir.appendingPathComponent("\(bankID).json")
        guard let data = try? Data(contentsOf: file),
              let s = try? JSONDecoder().decode(Session.self, from: data),
              !s.isFinished else { return nil }
        return refreshed(s)
    }

    func refreshed(_ s: Session) -> Session {
        guard let bank = bank(s.bankID) else { return s }
        let current = Dictionary(bank.questions.map { ($0.id, $0) },
                                 uniquingKeysWith: { a, _ in a })
        var out = s
        out.questions = s.questions.map { current[$0.id] ?? $0 }
        return out
    }

    func resumeSession(_ s: Session) { session = refreshed(s) }

    func discardSavedSession(for bankID: String) {
        try? FileManager.default.removeItem(at: sessionsDir.appendingPathComponent("\(bankID).json"))
        savedSessionsRevision += 1
    }

    func partner(_ id: String) -> Profile? {
        guard id != profile.id else { return nil }
        return profiles.profiles.first { $0.id == id }
    }

    private func recordForPartner(_ id: String, rows: [(Question, Attempt)], at now: Date) {
        let root = profiles.directory(of: id).appendingPathComponent("Progress",
                                                                     isDirectory: true)
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let file = root.appendingPathComponent("\(session?.bankID ?? "").json")
        var prog = DamagedFile.load(BankProgress.self, from: file, damaged: noteDamaged)
            ?? BankProgress(bankID: session?.bankID ?? "")
        for (q, a) in rows {
            let correct = AnswerChecker.isCorrect(question: q, response: a.response)
            prog.record(questionID: q.id, correct: correct)
            prog.history.append(AttemptRecord(question: q, correct: correct,
                                              at: now, secondsSpent: a.secondsSpent))
        }
        try? JSONEncoder().encode(prog).write(to: file, options: .atomic)
    }

    func finishSession() {
        guard var s = session else { return }
        s.finishedAt = Date()
        var prog = progress[s.bankID] ?? BankProgress(bankID: s.bankID)
        let now = Date()
        var partnerRows = [(Question, Attempt)]()
        for (i, (q, a)) in zip(s.questions, s.attempts).enumerated() where a.isAnswered {
            if s.isDouble && s.turn(at: i) == 1 {
                partnerRows.append((q, a))
                continue
            }
            let correct = AnswerChecker.isCorrect(question: q, response: a.response)
            prog.record(questionID: q.id, correct: correct)
            prog.history.append(AttemptRecord(question: q, correct: correct,
                                              at: now, secondsSpent: a.secondsSpent))
        }
        progress[s.bankID] = prog
        saveProgress(s.bankID)
        if s.isDouble, !partnerRows.isEmpty {
            recordForPartner(s.partnerID, rows: partnerRows, at: now)
        }
        discardSavedSession(for: s.bankID)
        session = s
        recordSitting(s)
        refreshReminders()
    }

    func closeSession() { session = nil }

    struct StoredFile: Identifiable, Hashable {
        enum Kind: String { case source, export }
        var url: URL
        var kind: Kind
        var bytes: Int
        var modified: Date
        var id: String { url.path }
        var name: String { url.lastPathComponent }

        var sizeText: String {
            ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
        }
        var dateText: String {
            DateFormatter.localizedString(from: modified, dateStyle: .medium, timeStyle: .short)
        }
    }

    func storedFiles(for bankID: String) -> [StoredFile] {
        var out = [StoredFile]()
        for (dir, kind) in [(sourcesDir(bankID), StoredFile.Kind.source),
                            (exportsDir(bankID), StoredFile.Kind.export)] {
            let urls = (try? FileManager.default.contentsOfDirectory(
                at: dir, includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey])) ?? []
            for url in urls where url.pathExtension.lowercased() == "pdf" {
                let values = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
                out.append(StoredFile(url: url, kind: kind,
                                      bytes: values?.fileSize ?? 0,
                                      modified: values?.contentModificationDate ?? .distantPast))
            }
        }
        return out.sorted { $0.modified > $1.modified }
    }

    private func archiveSource(_ url: URL, bankID: String) {
        let dir = sourcesDir(bankID)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        var destination = dir.appendingPathComponent(url.lastPathComponent)
        if FileManager.default.fileExists(atPath: destination.path) {
            if (try? Data(contentsOf: destination))?.count == (try? Data(contentsOf: url))?.count { return }
            let base = url.deletingPathExtension().lastPathComponent
            destination = dir.appendingPathComponent("\(base)-\(Int(Date().timeIntervalSince1970)).pdf")
        }
        try? FileManager.default.copyItem(at: url, to: destination)
    }

    func deleteStoredFile(_ file: StoredFile) {
        try? FileManager.default.removeItem(at: file.url)
        objectWillChange.send()
    }

    func saveCopy(of file: StoredFile) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.pdf]
        panel.nameFieldStringValue = file.name
        panel.message = L("Save a copy of this PDF")
        guard panel.runModal() == .OK, let destination = panel.url else { return }
        try? FileManager.default.removeItem(at: destination)
        do { try FileManager.default.copyItem(at: file.url, to: destination) }
        catch { lastError = Lf("Could not save the copy: %@", error.localizedDescription) }
    }

    func exportSetAside(in bankID: String, to url: URL) throws {
        let questions = setAsideQuestions(in: bankID)
        guard !questions.isEmpty else { return }
        var options = PDFExporter.Options()
        options.title = L("SAT Practice — Set Aside")
        options.subtitle = Lp(questions.count, "%d question set aside from",
                              "%d questions set aside from")
            + " \(bank(bankID)?.name ?? L("your bank")) · "
            + DateFormatter.localizedString(from: Date(), dateStyle: .long, timeStyle: .none)
        try PDFExporter.export(questions: questions,
                               imagesDirectory: imagesDir(bankID),
                               options: options, to: url)
        archiveExport(url, for: bankID)
    }

    private func archiveExport(_ url: URL, for bankID: String) {
        let dir = exportsDir(bankID)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let archived = dir.appendingPathComponent(url.lastPathComponent)
        try? FileManager.default.removeItem(at: archived)
        try? FileManager.default.copyItem(at: url, to: archived)
    }

    func exportMissed(from s: Session, to url: URL) throws {
        let missed = s.missedQuestions
        let attempted = s.attempts.filter(\.isAnswered).count
        let subtitle = Lp(missed.count, "%d question to review", "%d questions to review")
            + " · " + Lf("from %@", s.bankName)
            + " · " + Lf("%1$d/%2$d correct", s.correctCount, attempted)
            + " · " + DateFormatter.localizedString(from: Date(), dateStyle: .long,
                                                    timeStyle: .none)

        var options = PDFExporter.Options()
        options.subtitle = subtitle
        try PDFExporter.export(questions: missed,
                               imagesDirectory: imagesDir(s.bankID),
                               options: options, to: url)

        archiveExport(url, for: s.bankID)
    }
}
