import Foundation

extension AppStore {

    func portableProfile() -> PortableProfile {
        var file = PortableProfile()
        file.profileName = profile.name
        file.accent = profile.accent
        file.settings = settings

        for bank in banks {
            var block = PortableProfile.BankBlock()
            block.name = bank.name
            block.questionCount = bank.questions.count
            let ids = bank.questions.map(\.id)
            block.questionIDs = ids
            block.fingerprint = BankFingerprint.of(ids)
            if let p = progress[bank.id] {
                block.records = p.records
                block.setAside = p.setAside.sorted()
                block.history = p.history
            }
            block.notes = annotations[bank.id] ?? []
            file.banks.append(block)
        }

        file.decks = decks
        file.plans = presets
        return file
    }

    @discardableResult
    func exportProfile(to url: URL) -> Int? {
        guard let data = try? PortableProfile.encoder().encode(portableProfile()),
              (try? data.write(to: url, options: .atomic)) != nil else {
            lastError = L("The student file could not be written.")
            return nil
        }
        settings.lastBackupAt = Date()
        settings.backupNudgeFor = nil
        return data.count
    }

    func backupIsWorthMentioning(now: Date = Date(), calendar: Calendar = .current) -> Bool {
        let answered = progress.values.reduce(0) { $0 + $1.history.filter { !$0.backfilled }.count }
        guard answered >= AppStore.backupNudgeAfterAnswers else { return false }
        if let dismissed = settings.backupNudgeFor,
           (calendar.dateComponents([.day], from: dismissed, to: now).day ?? 0) < 14 {
            return false
        }
        guard let last = settings.lastBackupAt else { return true }
        let days = calendar.dateComponents([.day], from: last, to: now).day ?? 0
        guard days >= AppStore.backupNudgeAfterDays else { return false }
        let newest = progress.values.flatMap(\.history).filter { !$0.backfilled }.map(\.at).max()
        return newest.map { $0 > last } ?? false
    }

    static let backupNudgeAfterAnswers = 25
    static let backupNudgeAfterDays = 30

    func daysSinceBackup(now: Date = Date(), calendar: Calendar = .current) -> Int? {
        settings.lastBackupAt.map {
            max(0, calendar.dateComponents([.day], from: $0, to: now).day ?? 0)
        }
    }

    func dismissBackupNudge() { settings.backupNudgeFor = Date() }

    func readPortableProfile(at url: URL) -> PortableProfile? {
        guard let data = try? Data(contentsOf: url) else {
            lastError = L("That file could not be opened.")
            return nil
        }
        guard let file = try? PortableProfile.decoder().decode(PortableProfile.self, from: data),
              file.isRecognised else {
            lastError = L("That is not a student file exported from this app.")
            return nil
        }
        return file
    }

    func importPlan(for file: PortableProfile) -> ImportPlan {
        PortableMatcher.plan(for: file, banks: banks)
    }

    enum ImportMode { case merge, newProfile }

    @discardableResult
    func importProfile(_ file: PortableProfile, using plan: ImportPlan,
                       mode: ImportMode) -> ImportReport {
        var report = ImportReport()

        if mode == .newProfile {
            let name = file.profileName.isEmpty ? profiles.unusedName() : file.profileName
            let made = addProfile(named: name)
            setProfileAccent(made.id, to: file.accent)
            use(profile: profiles.profiles.first { $0.id == made.id } ?? made)
            if let incoming = file.settings {
                settings = incoming
                report.settingsApplied = true
            }
        }

        let byName = Dictionary(file.banks.map { ($0.name, $0) }, uniquingKeysWith: { a, _ in a })

        for match in plan.matches {
            guard let block = byName[match.exportedName] else { continue }
            guard let bankID = match.localBankID, let bank = bank(bankID) else {
                pending.append(block)
                report.setAside += 1
                continue
            }
            let known = Set(bank.questions.map(\.id))
            var p = progress[bankID] ?? BankProgress(bankID: bankID)
            let before = p.records.count
            ProgressMerge.merge(into: &p, from: block, keeping: known)
            progress[bankID] = p
            saveProgress(bankID)

            var notes = annotations[bankID] ?? []
            let notesBefore = notes.count
            ProgressMerge.merge(notes: &notes, from: block.notes, keeping: known)
            annotations[bankID] = notes
            saveAnnotations(bankID)

            report.sets += 1
            report.records += max(0, p.records.count - before)
            report.notes += max(0, notes.count - notesBefore)
            report.unmatchedQuestions += block.records.keys.filter { !known.contains($0) }.count
        }

        report.decks = mergeDecks(file.decks)
        report.plans = mergePlans(file.plans)
        savePending()
        return report
    }

    struct ImportReport {
        var summary: [String] {
            var lines: [String] = []
            if sets > 0 {
                lines.append([Lp(sets, "%d question set updated", "%d question sets updated"),
                              Lp(records, "%d question record", "%d question records"),
                              Lp(notes, "%d highlight", "%d highlights")].joined(separator: " · "))
            }
            if decks > 0 { lines.append(Lp(decks, "%d deck", "%d decks")) }
            if plans > 0 { lines.append(Lp(plans, "%d study plan", "%d study plans")) }
            if setAside > 0 {
                lines.append(Lp(setAside,
                                "%d set is waiting for its question PDF.",
                                "%d sets are waiting for their question PDFs."))
            }
            return lines
        }

        var sets = 0
        var records = 0
        var notes = 0
        var decks = 0
        var plans = 0
        var setAside = 0
        var unmatchedQuestions = 0
        var settingsApplied = false

        var landedAnything: Bool { sets > 0 || decks > 0 || plans > 0 }
    }

    private func mergeDecks(_ incoming: [Deck]) -> Int {
        var touched = 0
        for deck in incoming {
            if var mine = self.deck(deck.id) {
                let have = Set(mine.cards.map { Vocabulary.key($0.term) })
                let new = deck.cards.filter { !have.contains(Vocabulary.key($0.term)) }
                guard !new.isEmpty else { continue }
                mine.cards.append(contentsOf: new)
                saveDeck(mine)
                touched += 1
            } else {
                saveDeck(deck)
                touched += 1
            }
        }
        if touched > 0 { loadDecks() }
        return touched
    }

    private func mergePlans(_ incoming: [StudyPreset]) -> Int {
        let have = Set(presets.map(\.name))
        let new = incoming.filter { !have.contains($0.name) }
        guard !new.isEmpty else { return 0 }
        presets.append(contentsOf: new)
        return new.count
    }

    private var pendingFile: URL { profileRoot.appendingPathComponent("Pending.json") }

    func loadPending() {
        pending = DamagedFile.load([PortableProfile.BankBlock].self, from: pendingFile,
                                   decoder: PortableProfile.decoder(),
                                   damaged: noteDamaged) ?? []
    }

    func savePending() {
        guard !pending.isEmpty else {
            try? FileManager.default.removeItem(at: pendingFile)
            return
        }
        try? PortableProfile.encoder().encode(pending).write(to: pendingFile, options: .atomic)
    }

    @discardableResult
    func applyPendingIfPossible() -> Int {
        guard !pending.isEmpty else { return 0 }
        var file = PortableProfile()
        file.banks = pending
        let plan = PortableMatcher.plan(for: file, banks: banks)
        var landed = 0
        var stillWaiting: [PortableProfile.BankBlock] = []

        let byName = Dictionary(pending.map { ($0.name, $0) }, uniquingKeysWith: { a, _ in a })
        for match in plan.matches {
            guard let block = byName[match.exportedName] else { continue }
            guard let bankID = match.localBankID, let bank = bank(bankID) else {
                stillWaiting.append(block)
                continue
            }
            let known = Set(bank.questions.map(\.id))
            var p = progress[bankID] ?? BankProgress(bankID: bankID)
            ProgressMerge.merge(into: &p, from: block, keeping: known)
            progress[bankID] = p
            saveProgress(bankID)

            var notes = annotations[bankID] ?? []
            ProgressMerge.merge(notes: &notes, from: block.notes, keeping: known)
            annotations[bankID] = notes
            saveAnnotations(bankID)
            landed += 1
        }
        pending = stillWaiting
        savePending()
        return landed
    }
}
