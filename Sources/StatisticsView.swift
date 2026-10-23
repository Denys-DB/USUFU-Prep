import SwiftUI

struct StatisticsView: View {
    let bank: Bank

    var body: some View {
        ScrollView {
            StatisticsContent(bank: bank)
        }
        .background(Palette.paper)
    }
}

struct StatisticsContent: View {
    @EnvironmentObject var store: AppStore
    let bank: Bank
    var opensOn: StatisticsFilter = .everything

    @State private var confirmClear = false
    @State private var confirmReset = false
    @State private var filter: StatisticsFilter
    @State private var sort: SkillSort = .weakest

    init(bank: Bank, opensOn: StatisticsFilter = .everything) {
        self.bank = bank
        self.opensOn = opensOn
        _filter = State(initialValue: opensOn)
    }

    enum SkillSort: String, CaseIterable, Identifiable {
        case weakest, mostAnswered, leastCovered, slowest, alphabetical
        var id: String { rawValue }
        var title: String {
            switch self {
            case .weakest: return L("Worst first")
            case .mostAnswered: return L("Most answered")
            case .leastCovered: return L("Least covered")
            case .slowest: return L("Slowest")
            case .alphabetical: return L("A–Z")
            }
        }
    }

    private var stats: Statistics { store.statistics(for: bank.id, filter: filter) }
    private var everything: Statistics { store.builtStatistics(for: bank.id) }

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            header.entrance(0)
            if !stats.hasData && filter.narrowsAnything {
                coverPanel.entrance(1)
                emptySlice.entrance(2)
                if everything.bySection.filter({ $0.attempts > 0 }).count > 1 {
                    sectionPanel.entrance(3)
                }
            } else if !stats.hasData {
                empty.entrance(1)
                if !elsewhere.isEmpty {
                    otherSets.entrance(2)
                    if store.settings.showParentSummary {
                        Rule()
                        ParentSummaryView().entrance(3)
                    }
                }
            } else {
                if sectionsInBank.count > 1 || filter.narrowsAnything {
                    coverPanel.entrance(1)
                }
                if everything.bySection.filter({ $0.attempts > 0 }).count > 1 {
                    sectionPanel.entrance(1)
                }
                weakestPanel.entrance(1)
                domainPanel.entrance(2)
                if stats.byDifficulty.filter({ $0.attempts > 0 }).count >= 2 {
                    difficultyPanel.entrance(3)
                }
                coveragePanel.entrance(4)
                if stats.trend.count >= 2 { trendPanel.entrance(5) }
                pacePanel.entrance(6)
                Rule()
                if store.settings.showParentSummary {
                    ParentSummaryView().entrance(7)
                }
                footer.entrance(8)
            }
        }
        .padding(30)
        .frame(maxWidth: 820, alignment: .leading)
        .frame(maxWidth: .infinity)
        .background(Palette.paper)
        .alert(L("Practice this set from the beginning?"), isPresented: $confirmReset) {
            Button(L("Cancel"), role: .cancel) {}
            Button(L("Start over"), role: .destructive) { store.resetProgress(in: bank.id) }
        } message: {
            let cost = store.resetCost(in: bank.id)
            Text(Lf("All %1$d questions in \"%2$@\" go back to unseen, and the %3$d "
                    + "answers behind these charts are forgotten. Your highlights, your "
                    + "notes and the questions you set aside are all kept.",
                    bank.questions.count, bank.name, cost.answers))
        }
        .alert(L("Clear the statistics?"), isPresented: $confirmClear) {
            Button(L("Cancel"), role: .cancel) {}
            Button(L("Clear"), role: .destructive) { store.clearHistory(in: bank.id) }
        } message: {
            Text(L("This clears the record of every answer you have given, so the "
                 + "charts start over. Which questions you have seen, your "
                 + "set-aside list, and your notes are all kept."))
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L("Statistics"))
                .font(Face.display(27, .semibold))
                .foregroundStyle(Palette.navy)
            Rule(brass: true).frame(width: 46)
            if stats.hasData {
                HStack(spacing: 26) {
                    countingStat(stats.accuracy * 100, L("overall")) { "\(Int($0.rounded()))%" }
                    stat("\(stats.totalCorrect)/\(stats.totalAttempts)", L("answered"))
                    countingStat(Double(stats.questionsSeen),
                                 Lf("of %d seen", stats.questionsAvailable))
                    if stats.medianSeconds > 0 {
                        stat(Format.pace(stats.medianSeconds), L("typical question"))
                    }
                }
            }
        }
    }

    private func countingStat(_ value: Double, _ label: String,
                              format: @escaping (Double) -> String
                                = { "\(Int($0.rounded()))" }) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Counter(value: value, format: format)
                .font(Face.figures(22, .semibold))
                .foregroundStyle(Palette.navy)
                .monospacedDigit()
            Text(label.uppercased())
                .font(Face.ui(9, .medium)).tracking(0.9)
                .foregroundStyle(Palette.textMuted)
        }
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(Face.figures(22, .semibold))
                .foregroundStyle(Palette.navy)
            Text(label.uppercased())
                .font(Face.ui(9, .medium)).tracking(0.9)
                .foregroundStyle(Palette.textMuted)
        }
    }

    private var elsewhere: [Bank] {
        store.banks.filter { $0.id != bank.id && store.statistics(for: $0.id).hasData }
    }

    private var otherSets: some View {
        Panel(title: L("Your other sets")) {
            VStack(alignment: .leading, spacing: 8) {
                Text(L("You have answered questions in these. Statistics are kept "
                       + "per set, so choose one to see how it is going."))
                    .font(Face.ui(11.5))
                    .foregroundStyle(Palette.textMuted)
                    .fixedSize(horizontal: false, vertical: true)
                ForEach(elsewhere, id: \.id) { other in
                    let s = store.statistics(for: other.id)
                    Button {
                        store.config.bankID = other.id
                        store.selectedDeckID = nil
                    } label: {
                        HStack(spacing: 10) {
                            Text(other.name)
                                .font(Face.ui(12, .semibold))
                                .foregroundStyle(Palette.navy)
                            Spacer(minLength: 8)
                            Text(Lf("%1$d/%2$d correct", s.totalCorrect, s.totalAttempts))
                                .font(Face.ui(11))
                                .foregroundStyle(Palette.textMuted)
                            Image(systemName: "chevron.right")
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundStyle(Palette.textMuted)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var emptySlice: some View {
        VStack(spacing: 10) {
            Image(systemName: "line.3.horizontal.decrease.circle")
                .font(.system(size: 28))
                .foregroundStyle(Palette.border)
            Text(L("Nothing answered in this slice yet"))
                .font(Face.display(16, .semibold))
                .foregroundStyle(Palette.navy)
            Text(narrowedTo)
                .font(Face.ui(12))
                .foregroundStyle(Palette.textMuted)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 460)
            HStack(spacing: 10) {
                Button(L("Show everything")) {
                    withAnimation(Motion.settle) { filter = .everything }
                }
                .buttonStyle(.plain)
                .font(Face.ui(11, .semibold))
                .foregroundStyle(Palette.navy)
                .padding(.horizontal, 14).padding(.vertical, 7)
                .overlay(RoundedRectangle(cornerRadius: 3)
                    .strokeBorder(Palette.border, lineWidth: 1))
                if let subject = onlySubject {
                    Button(Lf("Practice %@", subject.displayName)) {
                        store.practiseSection(subject, in: bank.id)
                    }
                    .buttonStyle(.plain)
                    .font(Face.ui(11, .semibold))
                    .foregroundStyle(Palette.navy)
                    .padding(.horizontal, 14).padding(.vertical, 7)
                    .overlay(RoundedRectangle(cornerRadius: 3)
                        .strokeBorder(Palette.border, lineWidth: 1))
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 34)
    }

    private var narrowedTo: String {
        var parts = [String]()
        if let subjects = filter.subjects {
            parts += Subject.allCases.filter { subjects.contains($0) }.map(\.displayName)
        }
        if let domain = filter.domain { parts.append(domain) }
        if let skill = filter.skill { parts.append(skill) }
        guard !parts.isEmpty else { return L("Nothing has been answered here yet.") }
        return Lf("You have not answered anything in %@ in this set yet. Widen it above, or practice some.",
                  parts.joined(separator: " · "))
    }

    private var onlySubject: Subject? {
        guard let subjects = filter.subjects, subjects.count == 1 else { return nil }
        return subjects.first
    }

    private var empty: some View {
        VStack(spacing: 10) {
            Image(systemName: "chart.bar")
                .font(.system(size: 30))
                .foregroundStyle(Palette.border)
            Text(L("Nothing to show yet"))
                .font(Face.display(16, .semibold))
                .foregroundStyle(Palette.navy)
            Text(L("Finish a practice section and this fills in: which skills you "
                 + "are strongest and weakest at, how you do by difficulty, and "
                 + "whether you are improving."))
                .font(Face.ui(12))
                .foregroundStyle(Palette.textMuted)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 50)
    }

    private var sectionsInBank: [Subject] {
        Subject.allCases.filter { s in bank.questions.contains { $0.subject == s } }
    }
    private var domainsInBank: [String] {
        Set(bank.questions
            .filter { filter.subjects?.contains($0.subject) ?? true }
            .map(\.domain).filter { !$0.isEmpty }).sorted()
    }
    private var skillsInBank: [String] {
        Set(bank.questions
            .filter { (filter.subjects?.contains($0.subject) ?? true)
                      && (filter.domain == nil || $0.domain == filter.domain) }
            .map(\.skill).filter { !$0.isEmpty }).sorted()
    }

    private func questionsIn(_ predicate: (Question) -> Bool) -> Int {
        bank.questions.filter(predicate).count
    }

    private var coverPanel: some View {
        Panel(title: L("What these figures cover")) {
            VStack(alignment: .leading, spacing: 14) {
                if sectionsInBank.count > 1 {
                    filterRow(L("Section")) {
                        Chip(title: L("Both"), selected: filter.subjects == nil,
                             accent: Palette.brass) { narrow { $0.subjects = nil } }
                        ForEach(sectionsInBank, id: \.self) { subject in
                            Chip(title: subject.displayName,
                                 selected: filter.subjects == [subject],
                                 count: questionsIn { $0.subject == subject },
                                 accent: Palette.brass) {
                                narrow { $0.subjects = [subject] }
                            }
                        }
                    }
                }
                if domainsInBank.count > 1 {
                    filterRow(L("Domain")) {
                        Chip(title: L("All domains"), selected: filter.domain == nil,
                             accent: Palette.brass) { narrow { $0.domain = nil } }
                        ForEach(domainsInBank, id: \.self) { domain in
                            Chip(title: domain, selected: filter.domain == domain,
                                 count: questionsIn { $0.domain == domain },
                                 accent: Palette.brass) {
                                narrow { $0.domain = domain }
                            }
                        }
                    }
                }
                if skillsInBank.count > 1 {
                    filterRow(L("Skill")) {
                        Chip(title: L("All skills"), selected: filter.skill == nil,
                             accent: Palette.brass) { narrow { $0.skill = nil } }
                        ForEach(skillsInBank, id: \.self) { skill in
                            Chip(title: skill, selected: filter.skill == skill,
                                 count: questionsIn { $0.skill == skill },
                                 accent: Palette.brass) {
                                narrow { $0.skill = skill }
                            }
                        }
                    }
                }
                if filter.narrowsAnything {
                    HStack(spacing: 10) {
                        Button(L("Show everything")) {
                            withAnimation(Motion.settle) { filter = .everything }
                        }
                        .buttonStyle(.plain)
                        .font(Face.ui(11, .semibold))
                        .foregroundStyle(Palette.brass)
                        Text(stats.hasData
                             ? Lp(stats.totalAttempts, "%d answer in this slice",
                                  "%d answers in this slice")
                             : L("Nothing answered in this slice yet."))
                            .font(Face.ui(10.5))
                            .foregroundStyle(Palette.textMuted)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func filterRow<Content: View>(_ title: String,
                                          @ViewBuilder chips: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title)
                .font(Face.ui(11, .semibold))
                .foregroundStyle(Palette.text)
            FlowRow(spacing: 8, lineSpacing: 8) { chips() }
        }
    }

    private func narrow(_ change: (inout StatisticsFilter) -> Void) {
        var next = filter
        change(&next)
        if let domain = next.domain,
           !bank.questions.contains(where: {
               (next.subjects?.contains($0.subject) ?? true) && $0.domain == domain }) {
            next.domain = nil
        }
        if let skill = next.skill,
           !bank.questions.contains(where: {
               (next.subjects?.contains($0.subject) ?? true)
               && (next.domain == nil || $0.domain == next.domain)
               && $0.skill == skill }) {
            next.skill = nil
        }
        withAnimation(Motion.settle) { filter = next }
    }

    private var sectionPanel: some View {
        Panel(title: L("By section")) {
            VStack(spacing: 12) {
                ForEach(everything.bySection.filter { $0.attempts > 0 }) { row in
                    let subject = Subject.allCases.first { $0.displayName == row.label }
                    Button {
                        if let subject { narrow { $0.subjects = [subject] } }
                    } label: {
                        HStack(spacing: 12) {
                            Text(row.label)
                                .font(Face.ui(12, .semibold))
                                .foregroundStyle(Palette.text)
                                .frame(width: 190, alignment: .leading)
                            AccuracyBar(value: row.accuracy, tint: accuracyColour(row.accuracy))
                            Text("\(row.correct)/\(row.attempts)")
                                .font(Face.ui(11))
                                .foregroundStyle(Palette.textMuted)
                                .frame(width: 54, alignment: .trailing)
                            Text(percent(row.accuracy))
                                .font(Face.ui(12, .semibold))
                                .foregroundStyle(accuracyColour(row.accuracy))
                                .frame(width: 44, alignment: .trailing)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help(L("Show only this section"))
                }
            }
            if let gap = sectionGap {
                Text(gap)
                    .font(Face.ui(11))
                    .foregroundStyle(Palette.textMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var sectionGap: String? {
        let rows = everything.bySection.filter { $0.isConfident }
        guard rows.count == 2 else { return nil }
        let sorted = rows.sorted { $0.accuracy < $1.accuracy }
        let gap = sorted[1].accuracy - sorted[0].accuracy
        guard gap >= 0.08 else {
            return L("The two sections are running at about the same accuracy.")
        }
        return Lf("%1$@ is %2$d points behind %3$@ — that is where the marks are going.",
                  sorted[0].label, Int((gap * 100).rounded()), sorted[1].label)
    }

    private var rankedSkills: [Breakdown] {
        let rows = stats.weakest
        switch sort {
        case .weakest: return rows
        case .mostAnswered: return rows.sorted { $0.attempts > $1.attempts }
        case .leastCovered: return rows.sorted { $0.coverage < $1.coverage }
        case .slowest: return rows.sorted { $0.averageSeconds > $1.averageSeconds }
        case .alphabetical: return rows.sorted { $0.label < $1.label }
        }
    }

    private var weakestPanel: some View {
        Panel(title: L("Where you are losing marks")) {
            let ranked = rankedSkills
            if ranked.count > 1 {
                HStack(spacing: 8) {
                    Text(L("Order"))
                        .font(Face.ui(10.5))
                        .foregroundStyle(Palette.textMuted)
                    FlowRow(spacing: 6, lineSpacing: 6) {
                        ForEach(SkillSort.allCases) { option in
                            Chip(title: option.title, selected: sort == option,
                                 accent: Palette.brass) {
                                withAnimation(Motion.settle) { sort = option }
                            }
                        }
                    }
                }
            }
            if ranked.isEmpty {
                Text(Lf("Answer at least %d questions in a skill and it will be ranked here. Below that a percentage says more about luck than about you.", Breakdown.confidentAt))
                    .font(Face.ui(12))
                    .foregroundStyle(Palette.textMuted)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                VStack(spacing: 0) {
                    let weakest = ranked.min { $0.accuracy < $1.accuracy }.map(\.id)
                    ForEach(Array(ranked.enumerated()), id: \.element.id) { i, row in
                        if i > 0 { Rule() }
                        skillRow(row, worst: row.id == weakest && row.accuracy < 0.85)
                    }
                }
            }

            if !stats.untested.isEmpty {
                Rule()
                VStack(alignment: .leading, spacing: 7) {
                    SectionLabel(text: L("Not enough attempts to judge"))
                    Text(stats.untested.map { "\($0.label) (\($0.attempts))" }
                            .joined(separator: " · "))
                        .font(Face.ui(11))
                        .foregroundStyle(Palette.textMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private func skillRow(_ row: Breakdown, worst: Bool) -> some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Text(row.label)
                        .font(Face.ui(13, worst ? .semibold : .regular))
                        .foregroundStyle(Palette.text)
                    if worst {
                        Text(L("Weakest").uppercased())
                            .font(Face.ui(8, .bold)).tracking(0.8)
                            .foregroundStyle(Palette.card)
                            .padding(.horizontal, 5).padding(.vertical, 2)
                            .background(Palette.brass)
                    }
                    Spacer(minLength: 4)
                    Text("\(row.correct)/\(row.attempts)")
                        .font(Face.ui(11))
                        .foregroundStyle(Palette.textMuted)
                    Text(percent(row.accuracy))
                        .font(Face.ui(12, .semibold))
                        .foregroundStyle(accuracyColour(row.accuracy))
                        .frame(width: 44, alignment: .trailing)
                }
                AccuracyBar(value: row.accuracy, tint: accuracyColour(row.accuracy))
            }
            VStack(alignment: .trailing, spacing: 5) {
                Button(L("Practice")) {
                    store.practiseSkill(row.label, in: bank.id,
                                        count: min(10, max(5, row.available)))
                }
                .buttonStyle(.plain)
                .font(Face.ui(11, .semibold))
                .foregroundStyle(Palette.navy)
                .padding(.horizontal, 12).padding(.vertical, 6)
                .overlay(RoundedRectangle(cornerRadius: 3)
                    .strokeBorder(Palette.border, lineWidth: 1))
                ArticleLink(skill: row.label, compact: true)
            }
        }
        .padding(.vertical, 10)
    }

    private var domainPanel: some View {
        Panel(title: L("By domain")) {
            VStack(spacing: 12) {
                ForEach(stats.byDomain.filter { $0.attempts > 0 }) { row in
                    HStack(spacing: 12) {
                        Text(row.label)
                            .font(Face.ui(12))
                            .foregroundStyle(Palette.text)
                            .frame(width: 190, alignment: .leading)
                        AccuracyBar(value: row.accuracy, tint: accuracyColour(row.accuracy))
                        Text("\(row.correct)/\(row.attempts)")
                            .font(Face.ui(11))
                            .foregroundStyle(Palette.textMuted)
                            .frame(width: 54, alignment: .trailing)
                        Text(percent(row.accuracy))
                            .font(Face.ui(12, .semibold))
                            .foregroundStyle(accuracyColour(row.accuracy))
                            .frame(width: 44, alignment: .trailing)
                    }
                }
            }
        }
    }

    private var difficultyPanel: some View {
        Panel(title: L("By difficulty")) {
            let rows = stats.byDifficulty.filter { $0.attempts > 0 }
            HStack(alignment: .bottom, spacing: 26) {
                ForEach(rows) { row in
                    VStack(spacing: 8) {
                        Text(percent(row.accuracy))
                            .font(Face.figures(17, .semibold))
                            .foregroundStyle(accuracyColour(row.accuracy))
                        GrowingColumn(value: row.accuracy,
                                      tint: accuracyColour(row.accuracy).opacity(0.75))
                        Text(row.label)
                            .font(Face.ui(11, .medium))
                            .foregroundStyle(Palette.text)
                        Text("\(row.correct)/\(row.attempts)")
                            .font(Face.ui(10))
                            .foregroundStyle(Palette.textMuted)
                    }
                }
                Spacer()
                if let easy = rows.first(where: { $0.label == "Easy" }),
                   let hard = rows.first(where: { $0.label == "Hard" }),
                   easy.isConfident, hard.isConfident {
                    Text(reading(easy: easy, hard: hard))
                        .font(Face.ui(11))
                        .foregroundStyle(Palette.textMuted)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: 210, alignment: .leading)
                }
            }
        }
    }

    private func reading(easy: Breakdown, hard: Breakdown) -> String {
        let gap = easy.accuracy - hard.accuracy
        if easy.accuracy < 0.8 {
            return L("Marks are going missing on easy questions too, which usually "
                     + "means care rather than knowledge.")
        }
        if gap > 0.3 {
            return L("Solid on easy questions and dropping sharply on hard ones — "
                     + "the gap is knowledge, not carelessness.")
        }
        return L("Your accuracy holds up as the questions get harder.")
    }

    private var coveragePanel: some View {
        Panel(title: L("How much of the bank you have covered")) {
            VStack(spacing: 10) {
                ForEach(stats.bySkill.filter { $0.available > 0 }
                    .sorted { $0.coverage < $1.coverage }) { row in
                    HStack(spacing: 12) {
                        Text(row.label)
                            .font(Face.ui(11))
                            .foregroundStyle(Palette.text)
                            .frame(width: 190, alignment: .leading)
                        GrowingBar(value: row.coverage, tint: Palette.navy.opacity(0.55),
                                   height: 6)
                        Text("\(row.seen)/\(row.available)")
                            .font(Face.ui(10))
                            .foregroundStyle(Palette.textMuted)
                            .frame(width: 60, alignment: .trailing)
                    }
                }
            }
        }
    }

    private var trendPanel: some View {
        Panel(title: L("Accuracy over your last sittings")) {
            TrendChart(points: stats.trend)
                .frame(height: 150)
            Text(L("Each point is one sitting: answers separated by more than half "
                 + "an hour start a new one."))
                .font(Face.ui(10))
                .foregroundStyle(Palette.textMuted)
        }
    }

    private var pacePanel: some View {
        Panel(title: L("Pace")) {
            let rows = stats.bySkill.filter { $0.averageSeconds > 0 && $0.isConfident }
                .sorted { $0.averageSeconds > $1.averageSeconds }
            if rows.isEmpty {
                Text(L("Once you have answered a few more questions this shows which "
                     + "kinds take you longest."))
                    .font(Face.ui(12))
                    .foregroundStyle(Palette.textMuted)
            } else {
                let slowest = rows[0].averageSeconds
                VStack(spacing: 10) {
                    ForEach(rows) { row in
                        HStack(spacing: 12) {
                            Text(row.label)
                                .font(Face.ui(11))
                                .foregroundStyle(Palette.text)
                                .frame(width: 190, alignment: .leading)
                            GrowingBar(value: slowest == 0 ? 0 : row.averageSeconds / slowest,
                                       tint: Palette.brass.opacity(0.65), height: 6)
                            Text(Format.pace(row.averageSeconds))
                                .font(Face.ui(10))
                                .foregroundStyle(Palette.textMuted)
                                .frame(width: 60, alignment: .trailing)
                        }
                    }
                }
            }
        }
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 12) {
            Rule()
            HStack(alignment: .top, spacing: 24) {
                footerAction(L("Clear statistics"),
                             L("Forgets every answer behind these charts. Which "
                               + "questions you have seen is kept, so your place in "
                               + "the set does not move.")) { confirmClear = true }
                footerAction(L("Practice this set from the beginning"),
                             L("Puts all of it back to unseen so you can work through "
                               + "the same questions again. Highlights, notes and "
                               + "set-aside are kept.")) { confirmReset = true }
            }
        }
    }

    private func footerAction(_ title: String, _ detail: String,
                              action: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Button(title, action: action)
                .buttonStyle(.plain)
                .font(Face.ui(11, .medium))
                .foregroundStyle(Palette.wrong)
            Text(detail)
                .font(Face.ui(10))
                .foregroundStyle(Palette.textMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func percent(_ v: Double) -> String { "\(Int((v * 100).rounded()))%" }

    private func accuracyColour(_ v: Double) -> Color {
        if v >= 0.85 { return Palette.correct }
        if v >= 0.65 { return Palette.brass }
        return Palette.wrong
    }
}

struct AccuracyBar: View {
    let value: Double
    var tint: Color

    var body: some View {
        GrowingBar(value: value, tint: tint.opacity(0.8), height: 8, marker: 0.85)
    }
}

struct GrowingColumn: View {
    var value: Double
    var tint: Color
    var maxHeight: CGFloat = 90

    @State private var shown: Double = 0

    var body: some View {
        Rectangle()
            .fill(tint)
            .frame(width: 46, height: max(4, maxHeight * shown))
            .onAppear {
                guard Motion.enabled else { shown = value; return }
                withAnimation(Motion.fill) { shown = value }
            }
            .onChange(of: value) { new in
                withAnimation(Motion.standard) { shown = new }
            }
    }
}

struct TrendChart: View {
    let points: [TrendPoint]

    @State private var drawn: Double = 0

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .trailing, spacing: 0) {
                Text("100%")
                Spacer(minLength: 0)
                Text("0%")
            }
            .font(Face.ui(9))
            .foregroundStyle(Palette.textMuted)
            .fixedSize(horizontal: true, vertical: false)
            .padding(.vertical, 6)

            VStack(alignment: .trailing, spacing: 2) {
                TrendCanvas(points: points, progress: drawn)
                Text(L("latest"))
                    .font(Face.ui(9))
                    .foregroundStyle(Palette.textMuted)
                    .fixedSize(horizontal: true, vertical: false)
            }
        }
        .onAppear {
            guard Motion.enabled else { drawn = 1; return }
            withAnimation(Motion.enabled ? .easeInOut(duration: 0.9) : nil) { drawn = 1 }
        }
    }
}

private struct TrendCanvas: View, Animatable {
    let points: [TrendPoint]
    var progress: Double

    var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    var body: some View {
        Canvas { ctx, size in
            guard points.count >= 2 else { return }
            let inset: CGFloat = 6
            let w = size.width - inset * 2
            let h = size.height - inset * 2

            for fraction in [0.0, 0.5, 1.0] {
                let y = inset + h * (1 - fraction)
                var line = Path()
                line.move(to: CGPoint(x: inset, y: y))
                line.addLine(to: CGPoint(x: inset + w, y: y))
                ctx.stroke(line, with: .color(Palette.hairline),
                           style: StrokeStyle(lineWidth: 1,
                                              dash: fraction == 0 ? [] : [3, 3]))
            }

            func point(_ i: Int) -> CGPoint {
                let x = inset + w * (points.count == 1 ? 0.5
                                     : CGFloat(i) / CGFloat(points.count - 1))
                let y = inset + h * (1 - CGFloat(points[i].accuracy))
                return CGPoint(x: x, y: y)
            }

            var path = Path()
            path.move(to: point(0))
            for i in 1..<points.count { path.addLine(to: point(i)) }
            let shown = min(max(progress, 0), 1)
            ctx.stroke(path.trimmedPath(from: 0, to: shown), with: .color(Palette.navy),
                       style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))

            for i in points.indices {
                let reached = points.count == 1 ? 1 : Double(i) / Double(points.count - 1)
                guard shown >= reached - 0.001 else { continue }
                let p = point(i)
                let dot = Path(ellipseIn: CGRect(x: p.x - 3.5, y: p.y - 3.5,
                                                 width: 7, height: 7))
                ctx.fill(dot, with: .color(Palette.card))
                ctx.stroke(dot, with: .color(Palette.navy), lineWidth: 2)
            }
        }
    }
}
