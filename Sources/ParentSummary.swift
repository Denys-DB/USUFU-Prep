import Foundation

struct ParentSummary {

    var studentName: String = ""
    var generatedAt: Date = Date()
    var days: Int = 30

    var lines: [String] = []
    var tiles: [(value: String, label: String)] = []
    var strengths: [String] = []
    var struggles: [String] = []
    var caveats: [String] = []

    var isEmpty: Bool { tiles.isEmpty }
}

extension AppStore {

    func parentSummary(days: Int = 30, now: Date = Date(),
                       calendar: Calendar = .current) -> ParentSummary {
        var out = ParentSummary()
        out.studentName = profile.name
        out.generatedAt = now
        out.days = days

        guard let since = calendar.date(byAdding: .day, value: -days, to: now) else { return out }
        let rows = progress.values.flatMap(\.history)
            .filter { !$0.backfilled && $0.at >= since }
        guard !rows.isEmpty else {
            out.lines = [L("There is no practice recorded in this period yet.")]
            return out
        }

        let answered = rows.count
        let correct = rows.count(where: \.correct)
        let daysPractised = Set(rows.map { calendar.startOfDay(for: $0.at) }).count
        let accuracy = Int((Double(correct) / Double(answered) * 100).rounded())

        out.tiles = [
            (String(answered), Lp(answered, "question answered", "questions answered")),
            (String(daysPractised), Lp(daysPractised, "day practiced", "days practiced")),
            ("\(accuracy)%", L("answered correctly")),
        ]

        out.lines.append(Lf("%1$@ practiced on %2$d of the last %3$d days and answered %4$d questions.",
                            profile.name, daysPractised, days, answered))
        out.lines.append(Lf("Of those, %1$d answered correctly — %2$d%%.", correct, accuracy))

        var strong: [Breakdown] = [], weak: [Breakdown] = []
        var judged = 0
        for bank in banks {
            let stats = builtStatistics(for: bank.id)
            for row in stats.bySkill where row.attempts >= Breakdown.confidentAt {
                judged += 1
                if row.accuracy >= 0.8 { strong.append(row) }
                if row.accuracy < 0.6 { weak.append(row) }
            }
        }
        out.strengths = strong.sorted { $0.accuracy > $1.accuracy }.prefix(3).map(\.label)
        out.struggles = weak.sorted { $0.accuracy < $1.accuracy }.prefix(3).map(\.label)

        if !out.strengths.isEmpty {
            out.lines.append(Lf("Going well: %@.", out.strengths.joined(separator: ", ")))
        }
        if !out.struggles.isEmpty {
            out.lines.append(Lf("Finding harder: %@.", out.struggles.joined(separator: ", ")))
            out.lines.append(L("These are the topics where help would make the most difference right now."))
        }
        if out.strengths.isEmpty && out.struggles.isEmpty {
            out.lines.append(judged > 0
                ? L("No topic stands out as much stronger or weaker than the rest yet.")
                : L("There is not yet enough practice in any one topic to say which are going well and which are not."))
        }

        let rhythm = self.rhythm(now: now)
        if rhythm.streak >= 2 {
            out.lines.append(Lp(rhythm.streak,
                                "%d day in a row so far.", "%d days in a row so far."))
        }

        out.caveats = [
            L("These figures come from practice in this app only. They are not a predicted SAT score, and this app cannot produce one — a question bank is not a scored test."),
            L("Nothing here is compared with other students. Everything stays on this computer."),
        ]
        return out
    }
}
