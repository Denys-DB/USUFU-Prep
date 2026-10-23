import SwiftUI

extension AppStore {

    static let sittingsKept = 300

    var sittingsDir: URL { profileRoot.appendingPathComponent("Sittings", isDirectory: true) }

    struct SittingSummary: Identifiable, Hashable {
        let id: String
        let file: URL
        let bankID: String
        let title: String
        let startedAt: Date
        let finishedAt: Date
        let correct: Int
        let total: Int
    }

    static func sittingFileName(_ s: Session) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyyyMMdd-HHmmss"
        return "\(f.string(from: s.finishedAt ?? Date()))-\(s.id).json"
    }

    func recordSitting(_ s: Session) {
        guard s.isFinished else { return }
        let fm = FileManager.default
        try? fm.createDirectory(at: sittingsDir, withIntermediateDirectories: true)
        guard let data = try? JSONEncoder().encode(s) else { return }
        try? data.write(to: sittingsDir.appendingPathComponent(Self.sittingFileName(s)),
                        options: .atomic)
        let files = sittingFiles()
        for old in files.dropFirst(Self.sittingsKept) { try? fm.removeItem(at: old) }
    }

    private func sittingFiles() -> [URL] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: sittingsDir.path)) ?? []
        return names.filter { $0.hasSuffix(".json") }.sorted(by: >)
            .map { sittingsDir.appendingPathComponent($0) }
    }

    private func loadSitting(_ file: URL) -> Session? {
        DamagedFile.load(Session.self, from: file, damaged: { [weak self] in self?.noteDamaged($0) })
    }

    func sittings(for bankID: String) -> [SittingSummary] {
        sittingFiles().compactMap { file -> SittingSummary? in
            guard let s = loadSitting(file), s.bankID == bankID, let done = s.finishedAt else { return nil }
            let correct = zip(s.questions, s.attempts).filter { q, a in
                AnswerChecker.isCorrect(question: q, response: a.response)
            }.count
            return SittingSummary(id: s.id, file: file, bankID: s.bankID, title: s.displayTitle,
                                  startedAt: s.startedAt, finishedAt: done,
                                  correct: correct, total: s.questions.count)
        }
    }

    func openSitting(_ summary: SittingSummary) {
        guard let s = loadSitting(summary.file), s.isFinished else {
            lastError = L("That practice could not be opened.")
            return
        }
        session = s
    }
}

struct HistoryView: View {
    @EnvironmentObject var store: AppStore
    let bank: Bank
    @State private var rows: [AppStore.SittingSummary] = []

    var body: some View {
        Group {
            if rows.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.system(size: 30))
                        .foregroundStyle(Palette.secondaryText)
                    Text(L("No finished practice in this set yet. Each test you finish is kept here, with every answer."))
                        .font(.system(size: 14))
                        .foregroundStyle(Palette.secondaryText)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 380)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(rows) { row in
                            Button { store.openSitting(row) } label: { line(row) }
                                .buttonStyle(.plain)
                                .accessibilityLabel(row.title + ", " + Format.stamp(row.finishedAt) + ", "
                                                    + "\(row.correct)/\(row.total) " + L("correct"))
                        }
                    }
                    .padding(.horizontal, 26)
                    .padding(.vertical, 20)
                    .frame(maxWidth: 820)
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .onAppear { rows = store.sittings(for: bank.id) }
    }

    private func line(_ row: AppStore.SittingSummary) -> some View {
        let percent = row.total > 0 ? Int((Double(row.correct) / Double(row.total) * 100).rounded()) : 0
        return HStack(spacing: 18) {
            VStack(alignment: .leading, spacing: 4) {
                Text(row.title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Palette.text)
                Text(Format.stamp(row.finishedAt) + " · "
                     + Format.duration(row.finishedAt.timeIntervalSince(row.startedAt)))
                    .font(.system(size: 12))
                    .foregroundStyle(Palette.secondaryText)
            }
            Spacer(minLength: 12)
            VStack(alignment: .trailing, spacing: 2) {
                Text("\(row.correct)/\(row.total)")
                    .font(Face.figures(20, .semibold))
                    .foregroundStyle(Palette.correct)
                Text("\(percent)% " + L("correct").uppercased())
                    .font(Face.ui(9, .medium)).tracking(1.0)
                    .foregroundStyle(Palette.textMuted)
            }
            Image(systemName: "chevron.right")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Palette.card)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Palette.hairline, lineWidth: 1))
        .contentShape(Rectangle())
    }
}
