import SwiftUI

struct VocabTestPane: View {
    @EnvironmentObject var store: AppStore
    let deck: Deck

    private var session: DeckSession { store.deckSession(deck.id) }
    private func edit(_ change: @escaping (inout DeckSession) -> Void) {
        store.updateDeckSession(deck.id, change)
    }

    private var side: VocabAnswerSide { session.testSide }
    private var scope: CardScope { session.testScope }
    private var count: Int { session.testCount }
    private var sitting: VocabSitting? { session.sitting }

    @State private var typedCount = ""
    @State private var typedMinutes = ""

    private var pool: [Flashcard] {
        scope.filter(deck.cards, wordsPerDay: store.settings.vocabDaily.wordsPerDay)
    }
    private var available: Int { VocabTest.availableCount(in: pool) }

    var body: some View {
        Group {
            if let sitting {
                if sitting.finished { results(sitting) } else { running(sitting) }
            } else {
                setup
            }
        }
        .onAppear { clampCount() }
        .onChange(of: available) { _ in clampCount() }
        .onReceive(clock) { _ in tick() }
    }

    private func clampCount() {
        guard available > 0, count > available else { return }
        edit { $0.testCount = available }
    }

    private var setup: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Panel(title: L("What the four answers are")) {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(VocabAnswerSide.allCases, id: \.self) { s in
                            OptionRow(title: s.title, detail: s.detail, selected: side == s) {
                                withAnimation(Motion.settle) { edit { $0.testSide = s } }
                            }
                        }
                    }
                }

                Panel(title: L("Which words")) {
                    VStack(alignment: .leading, spacing: 12) {
                        FlowRow(spacing: 8, lineSpacing: 8) {
                            ForEach(CardScope.allCases, id: \.self) { s in
                                let n = VocabTest.availableCount(in: s.filter(
                                    deck.cards,
                                    wordsPerDay: store.settings.vocabDaily.wordsPerDay))
                                Chip(title: s.title, selected: scope == s,
                                     enabled: n >= VocabTest.minimumCards,
                                     count: n, accent: Palette.brass) {
                                    edit { $0.testScope = s }
                                }
                            }
                        }
                        Text(L("A word needs a definition before it can be tested — a card "
                               + "with only a word on it has no right answer to offer."))
                            .font(Face.ui(11))
                            .foregroundStyle(Palette.textMuted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                Panel(title: L("How many questions")) {
                    VStack(alignment: .leading, spacing: 10) {
                        FlowRow(spacing: 8, lineSpacing: 8) {
                            ForEach(countPresets, id: \.self) { n in
                                Chip(title: "\(n)", selected: count == n,
                                     enabled: n <= available) {
                                    edit { $0.testCount = n }
                                    typedCount = ""
                                }
                            }
                            Chip(title: L("All"), selected: count == available,
                                 enabled: available > 0) {
                                edit { $0.testCount = available }
                                typedCount = ""
                            }
                        }
                        NumberField(placeholder: L("or type a number"),
                                    text: $typedCount,
                                    active: !countPresets.contains(count) && count != available,
                                    width: 130) { typed in
                            edit { $0.testCount = max(1, min(typed, max(1, available))) }
                        }
                        Text(Lf("%d of these words have a definition and can be asked about.",
                                available))
                            .font(Face.ui(10.5))
                            .foregroundStyle(Palette.textMuted)
                    }
                }

                Panel(title: L("A clock, if you want one")) {
                    VStack(alignment: .leading, spacing: 10) {
                        FlowRow(spacing: 8, lineSpacing: 8) {
                            Chip(title: L("No clock"), selected: session.testMinutes == nil) {
                                edit { $0.testMinutes = nil }
                                typedMinutes = ""
                            }
                            ForEach(minutePresets, id: \.self) { m in
                                Chip(title: Lf("%d min", m),
                                     selected: session.testMinutes == m) {
                                    edit { $0.testMinutes = m }
                                    typedMinutes = ""
                                }
                            }
                        }
                        NumberField(placeholder: L("or type minutes"),
                                    text: $typedMinutes,
                                    active: session.testMinutes.map {
                                        !minutePresets.contains($0) } ?? false,
                                    width: 130) { typed in
                            edit { $0.testMinutes = max(1, min(typed, 180)) }
                        }
                        Text(L("Vocabulary has no official pace — the SAT does not test words "
                               + "on their own. A clock here is for making yourself answer "
                               + "from memory instead of working it out.")) 
                            .font(Face.ui(10.5))
                            .foregroundStyle(Palette.textMuted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                if available < VocabTest.minimumCards {
                    Text(Lf("A test needs at least %d words with definitions. "
                            + "This selection has %d.",
                            VocabTest.minimumCards, available))
                        .font(Face.ui(12))
                        .foregroundStyle(Palette.wrong)
                        .fixedSize(horizontal: false, vertical: true)
                }

                HStack {
                    BluebookButton(title: L("Start the test"),
                                   enabled: available >= VocabTest.minimumCards,
                                   lifts: true) { start() }
                    Spacer()
                }
                .padding(.top, 2)
            }
            .padding(24)
        }
        .background(Palette.paper)
    }

    private var countPresets: [Int] { [10, 20, 30, 50] }
    private var minutePresets: [Int] { [2, 5, 10, 20] }

    private func start() {
        var rng = SystemRandomNumberGenerator()
        let wanted = count > 0 ? count : available
        let built = VocabTest.build(from: pool, side: side, count: wanted, using: &rng)
        guard !built.isEmpty else { return }
        begin(built)
    }

    private func begin(_ questions: [VocabQuestion]) {
        let minutes = session.testMinutes
        edit { s in
            s.sitting = VocabSitting(
                side: s.testSide, scope: s.testScope,
                questions: questions,
                attempts: Array(repeating: VocabAttempt(), count: questions.count),
                secondsRemaining: minutes.map { Double($0) * 60 })
        }
    }

    @State private var clock = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    private func tick() {
        guard let sitting, !sitting.finished, let left = sitting.secondsRemaining else { return }
        let next = left - 1
        if next <= 0 {
            submit()
        } else {
            edit { $0.sitting?.secondsRemaining = next }
        }
    }

    private func running(_ sitting: VocabSitting) -> some View {
        let i = min(sitting.index, sitting.questions.count - 1)
        return VocabQuestionScreen(
            question: sitting.questions[i],
            index: i,
            total: sitting.questions.count,
            answeredCount: sitting.answeredCount,
            chosen: sitting.attempts[i].chosen,
            secondsRemaining: sitting.secondsRemaining,
            onChoose: { choice in edit { $0.sitting?.attempts[i].chosen = choice } },
            onBack: { edit { $0.sitting?.index = max(0, i - 1) } },
            onNext: { edit { $0.sitting?.index = min(sitting.questions.count - 1, i + 1) } },
            onSubmit: submit,
            onStop: { edit { $0.sitting = nil } })
    }

    private func submit() {
        guard let sitting else { return }
        var results = [UUID: Bool]()
        for (q, a) in zip(sitting.questions, sitting.attempts) {
            results[q.cardID] = a.chosen == q.answerIndex
        }
        store.recordTest(results, in: deck.id)
        store.noteDailyProgress(in: deck.id)
        edit {
            $0.sitting?.finished = true
            $0.sitting?.secondsRemaining = nil
        }
    }

    private func results(_ sitting: VocabSitting) -> some View {
        VocabResultsScreen(questions: sitting.questions, attempts: sitting.attempts,
                           canRetryMissed: !sitting.missedCardIDs.isEmpty
                               && VocabTest.availableCount(in: deck.cards)
                                   >= VocabTest.minimumCards,
                           hasMissed: !sitting.missedCardIDs.isEmpty,
                           onAgain: start, onRetryMissed: retryMissed,
                           onStarMissed: starMissed,
                           onBack: { edit { $0.sitting = nil } })
    }

    private func starMissed() {
        guard let sitting else { return }
        let missed = Set(sitting.missedCardIDs)
        store.setStarred(true, on: missed, in: deck.id)
    }

    private func retryMissed() {
        guard let sitting else { return }
        let missed = Set(sitting.missedCardIDs)
        let cards = deck.cards.filter { missed.contains($0.id) }
        guard !cards.isEmpty else { return }
        var rng = SystemRandomNumberGenerator()
        let built = VocabTest.build(from: deck.cards, asking: cards,
                                    side: sitting.side, count: cards.count, using: &rng)
        guard !built.isEmpty else { return }
        begin(built)
    }
}

private struct NumberField: View {
    let placeholder: String
    @Binding var text: String
    let active: Bool
    var width: CGFloat = 130
    let commit: (Int) -> Void

    var body: some View {
        TextField(placeholder, text: $text)
            .textFieldStyle(.plain)
            .font(Face.ui(12))
            .multilineTextAlignment(.center)
            .frame(width: width)
            .padding(.vertical, 6)
            .background(active ? Palette.brassSoft : Palette.subtleFill)
            .overlay(RoundedRectangle(cornerRadius: 3)
                .strokeBorder(active ? Palette.brass : Palette.hairline, lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 3))
            .onSubmit(send)
            .onChange(of: text) { _ in send() }
    }

    private func send() {
        let digits = text.filter(\.isNumber)
        if digits != text { text = digits }
        guard let n = Int(digits), n > 0 else { return }
        commit(n)
    }
}

private let answerLetters = ["A", "B", "C", "D"]

struct VocabQuestionScreen: View {
    let question: VocabQuestion
    let index: Int
    let total: Int
    let answeredCount: Int
    let chosen: Int?
    var secondsRemaining: Double? = nil
    let onChoose: (Int) -> Void
    let onBack: () -> Void
    let onNext: () -> Void
    let onSubmit: () -> Void
    let onStop: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            progressBar
            Rule()
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    Text(question.asksForDefinition
                         ? L("What does this word mean?")
                         : L("Which word means this?"))
                        .font(Face.ui(11, .semibold))
                        .tracking(1.2)
                        .foregroundStyle(Palette.textMuted)

                    Text(question.prompt)
                        .font(question.asksForDefinition ? Face.display(30) : Face.ui(19))
                        .foregroundStyle(Palette.navy)
                        .fixedSize(horizontal: false, vertical: true)

                    VStack(spacing: 8) {
                        ForEach(Array(question.options.enumerated()), id: \.offset) { i, option in
                            AnswerRow(letter: answerLetters[i], text: option,
                                      selected: chosen == i) { onChoose(i) }
                        }
                    }
                }
                .padding(24)
                .frame(maxWidth: 720, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
            Rule()
            footer
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Palette.paper)
    }

    private var progressBar: some View {
        HStack(spacing: 14) {
            Text(Lf("Question %1$d of %2$d", index + 1, total))
                .font(Face.ui(12, .medium))
                .foregroundStyle(Palette.text)
                .monospacedDigit()
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Rectangle().fill(Palette.subtleFill)
                    Rectangle().fill(Palette.brass)
                        .frame(width: geo.size.width
                               * CGFloat(index + 1) / CGFloat(max(1, total)))
                }
            }
            .frame(height: 3)
            Text(Lf("%d answered", answeredCount))
                .font(Face.ui(11))
                .foregroundStyle(Palette.textMuted)
            if let secondsRemaining {
                Text(Format.duration(secondsRemaining))
                    .font(Face.ui(12.5, .semibold))
                    .monospacedDigit()
                    .foregroundStyle(secondsRemaining <= 60 ? Palette.wrong : Palette.navy)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 3)
                    .background(secondsRemaining <= 60 ? Palette.wrongSoft : Palette.subtleFill)
                    .clipShape(Capsule())
                    .help(L("Time left in this test"))
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 12)
        .background(Palette.card)
    }

    private var footer: some View {
        HStack(spacing: 10) {
            BluebookButton(title: L("Back"), style: .secondary, enabled: index > 0, action: onBack)
            Spacer()
            QuietLink(title: L("Stop this test"), action: onStop)
            if index == total - 1 {
                BluebookButton(title: L("Submit"), lifts: true, action: onSubmit)
            } else {
                BluebookButton(title: L("Next"), lifts: true, action: onNext)
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 14)
        .background(Palette.card)
    }
}

struct VocabResultsScreen: View {
    let questions: [VocabQuestion]
    let attempts: [VocabAttempt]
    let canRetryMissed: Bool
    let hasMissed: Bool
    let onAgain: () -> Void
    let onRetryMissed: () -> Void
    let onStarMissed: () -> Void
    let onBack: () -> Void

    private var correctCount: Int {
        zip(questions, attempts).count { $0.1.chosen == $0.0.answerIndex }
    }
    private var percentage: Int {
        questions.isEmpty ? 0
            : Int((Double(correctCount) / Double(questions.count) * 100).rounded())
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 10) {
                    Text(Lf("%1$d of %2$d", correctCount, questions.count))
                        .font(Face.figures(38))
                        .foregroundStyle(Palette.navy)
                    Rule(brass: true).frame(width: 44)
                    Text(Lf("%d%% right", percentage))
                        .font(Face.ui(13))
                        .foregroundStyle(Palette.textMuted)
                }

                FlowRow(spacing: 10, lineSpacing: 10) {
                    BluebookButton(title: L("Test again"), lifts: true, action: onAgain)
                    if canRetryMissed {
                        BluebookButton(title: L("Test only what I missed"),
                                       style: .secondary, lifts: true, action: onRetryMissed)
                    }
                    if hasMissed {
                        BluebookButton(title: L("Star what I missed"),
                                       style: .plain, lifts: true, action: onStarMissed)
                    }
                    BluebookButton(title: L("Back to setup"), style: .plain, action: onBack)
                }

                Rule()

                VStack(spacing: 0) {
                    ForEach(Array(zip(questions, attempts).enumerated()), id: \.offset) { i, pair in
                        ResultRow(number: i + 1, question: pair.0, attempt: pair.1)
                        Rule()
                    }
                }
            }
            .padding(24)
            .frame(maxWidth: 760, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Palette.paper)
    }
}

private struct AnswerRow: View {
    let letter: String
    let text: String
    let selected: Bool
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(alignment: .center, spacing: 12) {
                Text(letter)
                    .font(Face.ui(11.5, .semibold))
                    .foregroundStyle(selected ? Palette.card : Palette.text)
                    .frame(width: 22, height: 22)
                    .background(Circle().fill(selected ? Palette.navy : .clear))
                    .overlay(Circle().strokeBorder(selected ? .clear : Palette.border,
                                                   lineWidth: 1))
                Text(text)
                    .font(Face.ui(13))
                    .foregroundStyle(Palette.text)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 6)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(selected ? Palette.brassSoft.opacity(0.5)
                        : (hovering ? Palette.paperDeep.opacity(0.6) : Palette.card))
            .overlay(RoundedRectangle(cornerRadius: 4)
                .strokeBorder(selected ? Palette.brass : Palette.hairline,
                              lineWidth: selected ? 1.5 : 1))
            .clipShape(RoundedRectangle(cornerRadius: 4))
        }
        .buttonStyle(.plain)
        .animation(Motion.quick, value: hovering)
        .onHover { hovering = $0 }
    }
}

private struct ResultRow: View {
    let number: Int
    let question: VocabQuestion
    let attempt: VocabAttempt

    private var right: Bool { attempt.chosen == question.answerIndex }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: right ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundStyle(right ? Palette.correct : Palette.wrong)
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: 4) {
                Text(question.prompt)
                    .font(Face.ui(13, .semibold))
                    .foregroundStyle(Palette.navy)
                    .fixedSize(horizontal: false, vertical: true)
                Text(Lf("Answer: %@", question.answer))
                    .font(Face.ui(12))
                    .foregroundStyle(Palette.text)
                    .fixedSize(horizontal: false, vertical: true)
                if !right {
                    Text(attempt.chosen == nil
                         ? L("You left this one blank.")
                         : Lf("You chose: %@", question.options[attempt.chosen ?? 0]))
                        .font(Face.ui(11.5))
                        .foregroundStyle(Palette.wrong)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 6)
            Text("\(number)")
                .font(Face.ui(11))
                .foregroundStyle(Palette.textMuted)
        }
        .padding(.vertical, 10)
    }
}
