import SwiftUI

struct DailyPane: View {
    @EnvironmentObject var store: AppStore
    let deck: Deck
    let onStart: () -> Void

    @State private var todaySet = DailySet()
    @State private var typedCount = ""
    @State private var confirmClearToday = false
    @State private var confirmClearRun = false
    @State private var confirmClearAll = false

    private var plan: DailyPlan { store.settings.vocabDaily }
    private var streak: DailyPractice.Streak { store.dailyStreak() }
    private var done: Int { todaySet.answeredCount(on: Date()) }
    private var fraction: Double {
        todaySet.total > 0 ? Double(done) / Double(todaySet.total) : 0
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if plan.enabled { today } else { invitation }
                statistics
                settingsPanel
                resetPanel
            }
            .padding(24)
        }
        .background(Palette.paper)
        .alert(L("Put today's new words back?"), isPresented: $confirmClearToday) {
            Button(L("Cancel"), role: .cancel) {}
            Button(L("Put them back")) {
                store.clearTodaysDeal(in: deck.id)
                refresh()
            }
        } message: {
            Text(L("Today's set is dealt again from the top of the deck. Nothing you "
                   + "have already answered is lost — those words keep their record."))
        }
        .alert(L("Clear your run?"), isPresented: $confirmClearRun) {
            Button(L("Cancel"), role: .cancel) {}
            Button(L("Clear the run"), role: .destructive) { store.clearDailyHistory() }
        } message: {
            Text(L("The streak and the list of days you finished are forgotten. The "
                   + "words themselves keep everything they know."))
        }
        .alert(L("Start this deck over?"), isPresented: $confirmClearAll) {
            Button(L("Cancel"), role: .cancel) {}
            Button(L("Start over"), role: .destructive) {
                store.clearAllVocabularyProgress(in: deck.id)
                refresh()
            }
        } message: {
            Text(Lf("Every word in \"%@\" goes back to never having been seen: the "
                    + "times right, the times skipped, the review dates and your run. "
                    + "The words, their meanings and your stars are kept.", deck.name))
        }
        .onAppear { refresh() }
        .onChange(of: deck.cards.count) { _ in refresh() }
        .onChange(of: plan.wordsPerDay) { _ in refresh() }
        .onChange(of: plan.enabled) { _ in refresh() }
    }

    private func refresh() {
        guard plan.enabled else { todaySet = store.dailySet(for: deck); return }
        todaySet = store.dealDaily(in: deck.id)
    }

    private var invitation: some View {
        Panel(title: L("A few words a day")) {
            VStack(alignment: .leading, spacing: 14) {
                Text(L("Ten new words a day, with everything that has come back round "
                       + "for review, is about a quarter of an hour and adds up to more "
                       + "than any amount of cramming the week before. Words you get "
                       + "wrong come back tomorrow; words you keep getting right come "
                       + "back at widening gaps."))
                    .font(Face.ui(12))
                    .foregroundStyle(Palette.text)
                    .fixedSize(horizontal: false, vertical: true)
                BluebookButton(title: L("Start a daily set"), lifts: true) {
                    store.settings.vocabDaily.enabled = true
                }
            }
        }
    }

    private var today: some View {
        VStack(alignment: .leading, spacing: 18) {
            Panel(title: L("Today")) {
                HStack(alignment: .top, spacing: 26) {
                    GoalRing(fraction: fraction, size: 84, lineWidth: 7)
                        .overlay {
                            VStack(spacing: 0) {
                                Text("\(done)")
                                    .font(Face.figures(21, .semibold))
                                    .foregroundStyle(Palette.navy)
                                    .monospacedDigit()
                                Text("/\(todaySet.total)")
                                    .font(Face.ui(10))
                                    .foregroundStyle(Palette.textMuted)
                                    .monospacedDigit()
                            }
                        }

                    VStack(alignment: .leading, spacing: 9) {
                        Text(headline)
                            .font(Face.display(17))
                            .foregroundStyle(Palette.navy)
                            .fixedSize(horizontal: false, vertical: true)

                        if todaySet.total > 0 {
                            Text(breakdown)
                                .font(Face.ui(12))
                                .foregroundStyle(Palette.textMuted)
                        }

                        if todaySet.heldBack > 0 {
                            Text(Lf("No new words today: %d are already waiting to be "
                                    + "reviewed. They come back as soon as you have "
                                    + "cleared some — this is deliberate, and it is the "
                                    + "thing that keeps a daily set from turning into a "
                                    + "backlog nobody finishes.", todaySet.due.count))
                                .font(Face.ui(11))
                                .foregroundStyle(Palette.brass)
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        HStack(spacing: 10) {
                            BluebookButton(title: done == todaySet.total && todaySet.total > 0
                                           ? L("Go through them again")
                                           : L("Start today's words"),
                                           enabled: todaySet.total > 0, lifts: true, action: onStart)
                            if todaySet.remainingInDeck > 0 {
                                Text(Lp(todaySet.remainingInDeck,
                                        "%d word left in this deck",
                                        "%d words left in this deck"))
                                    .font(Face.ui(10.5))
                                    .foregroundStyle(Palette.textMuted)
                            }
                        }
                        .padding(.top, 2)
                    }
                    Spacer(minLength: 0)
                }
            }

            Panel(title: store.settings.showVocabularyStreak
                  ? L("Your run") : L("Days you have practiced")) {
                HStack(spacing: 34) {
                    if store.settings.showVocabularyStreak {
                        figure("\(streak.current)",
                               Lp(streak.current, "day in a row", "days in a row"))
                        figure("\(streak.best)", L("best run"))
                    }
                    figure("\(plan.completedDays.count)", L("days done in all"))
                    Spacer(minLength: 0)
                }
                if !store.settings.showVocabularyStreak {
                    EmptyView()
                } else if streak.atRisk && todaySet.total > 0 {
                    Text(streak.current > 0
                         ? Lp(streak.current + 1,
                              "Finish today's words to make it %d day.",
                              "Finish today's words to make it %d days.")
                         : L("Finish today's words to start a run."))
                        .font(Face.ui(11))
                        .foregroundStyle(Palette.textMuted)
                        .padding(.top, 8)
                } else if streak.doneToday {
                    Text(L("Today is done. Come back tomorrow — the gap is the part "
                           + "that does the work."))
                        .font(Face.ui(11))
                        .foregroundStyle(Palette.correct)
                        .padding(.top, 8)
                }
            }
        }
    }

    private var headline: String {
        if todaySet.total == 0 {
            return todaySet.remainingInDeck > 0
                ? L("Nothing due, and nothing new dealt yet.")
                : L("Nothing due today. Every word in this deck is resting.")
        }
        if done == todaySet.total { return L("Today's words are done.") }
        return Lf("%1$d of %2$d words to go today.", todaySet.total - done, todaySet.total)
    }

    private var breakdown: String {
        var parts = [String]()
        if !todaySet.due.isEmpty { parts.append(Lp(todaySet.due.count, "%d to review", "%d to review")) }
        if !todaySet.fresh.isEmpty { parts.append(Lp(todaySet.fresh.count, "%d new", "%d new")) }
        return parts.joined(separator: " · ")
    }

    private func figure(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(Face.figures(24, .semibold))
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

    private var stats: DeckStatistics { store.deckStatistics(deck) }

    private var statistics: some View {
        Panel(title: L("This deck")) {
            VStack(alignment: .leading, spacing: 16) {
                FlowRow(spacing: 30, lineSpacing: 14) {
                    figure("\(stats.total)", L("words"))
                    figure("\(stats.known)", L("known"))
                    figure("\(stats.learning)", L("still learning"))
                    figure("\(stats.new)", L("not met yet"))
                    if let accuracy = stats.accuracy {
                        figure("\(Int((accuracy * 100).rounded()))%", L("answered right"))
                    }
                }

                GeometryReader { geo in
                    HStack(spacing: 2) {
                        band(stats.known, of: stats.total, geo.size.width, Palette.correct)
                        band(stats.learning, of: stats.total, geo.size.width, Palette.brass)
                        band(stats.new, of: stats.total, geo.size.width, Palette.hairline)
                    }
                }
                .frame(height: 8)

                Text(knownLine)
                    .font(Face.ui(11))
                    .foregroundStyle(Palette.textMuted)
                    .fixedSize(horizontal: false, vertical: true)

                Rule()

                FlowRow(spacing: 30, lineSpacing: 14) {
                    figure("\(stats.dueToday)", L("due now"))
                    figure("\(stats.dueThisWeek)", L("due this week"))
                    figure("\(stats.starred)", L("starred"))
                    if stats.withoutDefinition > 0 {
                        figure("\(stats.withoutDefinition)", L("no definition"))
                    }
                }

                if plan.enabled {
                    Rule()
                    activityStrip
                }
            }
        }
    }

    private func band(_ n: Int, of total: Int, _ width: CGFloat, _ colour: Color) -> some View {
        Rectangle()
            .fill(colour)
            .frame(width: total > 0 ? max(0, width * CGFloat(n) / CGFloat(total)) : 0)
    }

    private var knownLine: String {
        guard stats.withDefinition > 0 else {
            return L("None of these words has a definition yet, so none of them can be "
                     + "tested. Open Cards and sort by \"Without a definition first\".")
        }
        return Lf("%1$d of the %2$d words with a definition have been answered right "
                  + "four times running, which is where the schedule leaves them alone "
                  + "for a fortnight.", stats.known, stats.withDefinition)
    }

    private var activityStrip: some View {
        let days = DeckStatistics.recentDays(plan.completedDays, weeks: range.weeks)
        let columns = max(1, Int((Double(days.count) / 7).rounded(.up)))
        return VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                SectionLabel(text: L("Turning up"))
                Spacer(minLength: 8)
                ForEach(DeckStatistics.ActivityRange.allCases) { option in
                    Chip(title: option.title, selected: range == option) {
                        withAnimation(Motion.settle) { range = option }
                    }
                }
            }

            HStack(alignment: .top, spacing: 28) {
                GeometryReader { geo in
                    let gap: CGFloat = columns > 20 ? 3 : 5
                    let fit = (geo.size.width - gap * CGFloat(columns - 1)) / CGFloat(columns)
                    let size = max(6, min(range.maximumSquare, fit))
                    HStack(spacing: gap) {
                        ForEach(Array(stride(from: 0, to: days.count, by: 7)), id: \.self) { start in
                            VStack(spacing: gap) {
                                ForEach(start..<min(start + 7, days.count), id: \.self) { i in
                                    RoundedRectangle(cornerRadius: size / 5)
                                        .fill(days[i].1 ? Palette.brass : Palette.subtleFill)
                                        .frame(width: size, height: size)
                                        .help(Format.day(days[i].0))
                                }
                            }
                        }
                        Spacer(minLength: 0)
                    }
                }
                .frame(width: gridWidth(columns: columns),
                       height: gridHeight(columns: columns))

                VStack(alignment: .leading, spacing: 14) {
                    figure(String(daysInStrip(days)), L("days finished"))
                    figure("\(percentInStrip(days))%", L("of this period"))
                }
                Spacer(minLength: 0)
            }
        }
    }

    @State private var range: DeckStatistics.ActivityRange = .month

    private func percentInStrip(_ days: [(Date, Bool)]) -> Int {
        guard !days.isEmpty else { return 0 }
        return Int((Double(daysInStrip(days)) / Double(days.count) * 100).rounded())
    }

    private func gridWidth(columns: Int) -> CGFloat {
        let gap: CGFloat = columns > 20 ? 3 : 5
        return range.maximumSquare * CGFloat(columns) + gap * CGFloat(columns - 1)
    }

    private func gridHeight(columns: Int) -> CGFloat {
        let gap: CGFloat = columns > 20 ? 3 : 5
        let assumed: CGFloat = gridWidth(columns: columns)
        let fit = (assumed - gap * CGFloat(columns - 1)) / CGFloat(columns)
        let size = max(6, min(range.maximumSquare, fit))
        return size * 7 + gap * 6
    }

    private func daysInStrip(_ days: [(Date, Bool)]) -> Int {
        days.filter(\.1).count
    }

    private var resetPanel: some View {
        Panel(title: L("Starting over")) {
            VStack(alignment: .leading, spacing: 10) {
                resetRow(L("Deal today's words again"),
                         L("Puts today's new words back and takes the next ones instead. "
                           + "Nothing answered is lost."),
                         L("Deal again")) { confirmClearToday = true }
                resetRow(L("Clear your run"),
                         L("Forgets the streak and the days you finished. The words keep "
                           + "what they know."),
                         L("Clear")) { confirmClearRun = true }
                resetRow(L("Start this deck over"),
                         L("Every word back to never having been seen — times right, "
                           + "times skipped, review dates and your run. The words and "
                           + "their meanings are kept."),
                         L("Start over"), destructive: true) { confirmClearAll = true }
            }
        }
    }

    private func resetRow(_ title: String, _ detail: String, _ button: String,
                          destructive: Bool = false,
                          action: @escaping () -> Void) -> some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(Face.ui(12, .medium))
                    .foregroundStyle(Palette.text)
                Text(detail)
                    .font(Face.ui(10.5))
                    .foregroundStyle(Palette.textMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 10)
            BluebookButton(title: button, style: .secondary, action: action)
                .foregroundStyle(destructive ? Palette.wrong : Palette.text)
        }
    }

    private var settingsPanel: some View {
        Panel(title: L("How many new words a day")) {
            VStack(alignment: .leading, spacing: 10) {
                FlowRow(spacing: 8, lineSpacing: 8) {
                    ForEach(DailyPlan.presets, id: \.self) { n in
                        Chip(title: "\(n)", selected: plan.wordsPerDay == n) {
                            store.settings.vocabDaily.wordsPerDay = n
                            typedCount = ""
                        }
                    }
                }
                HStack(spacing: 10) {
                    TextField(L("or type a number"), text: $typedCount)
                        .textFieldStyle(.plain)
                        .font(Face.ui(12))
                        .multilineTextAlignment(.center)
                        .frame(width: 130)
                        .padding(.vertical, 6)
                        .background(DailyPlan.presets.contains(plan.wordsPerDay)
                                    ? Palette.subtleFill : Palette.brassSoft)
                        .overlay(RoundedRectangle(cornerRadius: 3)
                            .strokeBorder(Palette.hairline, lineWidth: 1))
                        .clipShape(RoundedRectangle(cornerRadius: 3))
                        .onChange(of: typedCount) { value in
                            let digits = value.filter(\.isNumber)
                            if digits != value { typedCount = digits }
                            guard let n = Int(digits) else { return }
                            store.settings.vocabDaily.wordsPerDay =
                                min(DailyPlan.range.upperBound,
                                    max(DailyPlan.range.lowerBound, n))
                        }
                    Text(Lf("Between %1$d and %2$d.",
                            DailyPlan.range.lowerBound, DailyPlan.range.upperBound))
                        .font(Face.ui(10.5))
                        .foregroundStyle(Palette.textMuted)
                }
                Text(L("Published advice for an adult learner lands between five and "
                       + "twenty new words a day, and the reason is always the same: "
                       + "the limit is not how many you can read but how many reviews "
                       + "they make for you over the next month. Ten is a good place to "
                       + "start. Changing it does not disturb words already dealt."))
                    .font(Face.ui(10.5))
                    .foregroundStyle(Palette.textMuted)
                    .fixedSize(horizontal: false, vertical: true)

                if plan.enabled {
                    Button(L("Stop daily practice")) {
                        store.settings.vocabDaily.enabled = false
                    }
                    .buttonStyle(.plain)
                    .font(Face.ui(11))
                    .foregroundStyle(Palette.textMuted)
                    .padding(.top, 2)
                }
            }
        }
    }
}
