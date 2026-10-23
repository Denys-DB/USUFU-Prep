import SwiftUI
import AppKit

struct ReviewView: View {
    @EnvironmentObject var store: AppStore
    let session: Session

    @State private var filter: Filter = .missed
    @State private var expanded: Set<String> = []
    @State private var exportMessage: String?

    init(session: Session, filter: Filter = .missed, expanded: Set<String> = []) {
        self.session = session
        _filter = State(initialValue: filter)
        _expanded = State(initialValue: expanded)
    }

    enum Filter: String, CaseIterable {
        case missed = "Got wrong"
        case unanswered = "Not answered"
        case correct = "Got right"
        case all = "All"
    }

    var body: some View {
        VStack(spacing: 0) {
            scoreHeader
            Divider()
            listing
            Divider()
            footer
        }
        .background(Palette.paper)
    }

    private var attempted: Int { session.answeredCount }
    private var correct: Int { session.correctCount }
    private var missed: [Question] { session.missedQuestions }

    private var scoreHeader: some View {
        HStack(alignment: .center, spacing: 26) {
            VStack(alignment: .leading, spacing: 9) {
                Text(session.isFullTest ? L("Test complete") : L("Section complete"))
                    .font(Face.display(25, .semibold))
                    .foregroundStyle(Palette.navy)
                Rule(brass: true).frame(width: 40)
                Text(Lf("%1$@ · %2$@", session.bankName,
                        Format.duration((session.finishedAt ?? Date()).timeIntervalSince(session.startedAt))))
                    .font(Face.ui(11)).foregroundStyle(Palette.textMuted)
            }

            Spacer()

            if session.isDouble {
                ForEach(Array(session.doubleScores.enumerated()), id: \.offset) { seat, row in
                    scoreTile("\(row.correct)/\(row.answered)", row.name, color: Palette.navy,
                              accent: ProfileAccent.colour(
                                  session.turnAccents.indices.contains(seat)
                                  ? session.turnAccents[seat] : seat))
                }
            } else {
                scoreTile("\(correct)/\(session.questions.count)",
                          percentText + " " + L("correct"), color: Palette.correct)
                scoreTile("\(session.questions.count - attempted)", L("left blank"),
                          color: Palette.textMuted)
            }
        }
        .padding(.horizontal, 30)
        .padding(.top, WindowChrome.trafficLights + 12)
        .padding(.bottom, 24)
        .background(Palette.card)
        .overlay(alignment: .bottom) { Rule() }
    }

    private func row(_ item: (offset: Int, question: Question, attempt: Attempt),
                     width: CGFloat) -> some View {
        ReviewRow(
            index: item.offset + 1,
            question: item.question,
            attempt: item.attempt,
            imagesDirectory: store.imagesDir(session.bankID),
            expanded: expanded.contains(item.question.id),
            toggle: {
                if expanded.contains(item.question.id) {
                    expanded.remove(item.question.id)
                } else {
                    expanded.insert(item.question.id)
                }
            },
            setAside: store.isSetAside(item.question.id, in: session.bankID),
            onSetAside: { store.toggleSetAside(item.question.id, in: session.bankID) },
            answeredBy: answeredBy(item.offset),
            answeredByAccent: answeredByAccent(item.offset),
            width: width)
    }

    private func answeredBy(_ index: Int) -> String {
        session.isDouble ? session.turnName(at: index) : ""
    }

    private func answeredByAccent(_ index: Int) -> Int {
        let seat = session.turn(at: index)
        return session.turnAccents.indices.contains(seat) ? session.turnAccents[seat] : seat
    }

    private var percentText: String {
        guard !session.questions.isEmpty else { return "—" }
        return "\(Int((Double(correct) / Double(session.questions.count) * 100).rounded()))%"
    }

    private func scoreTile(_ value: String, _ label: String, color: Color,
                           accent: Color? = nil) -> some View {
        VStack(spacing: 4) {
            Text(value).font(Face.figures(29, .semibold)).foregroundStyle(color)
            HStack(spacing: 5) {
                if let accent {
                    Circle().fill(accent).frame(width: 7, height: 7)
                        .overlay(Circle().strokeBorder(Palette.border, lineWidth: 0.5))
                }
                Text(label.uppercased())
                    .font(Face.ui(9, .medium)).tracking(1.0)
                    .foregroundStyle(Palette.textMuted)
            }
        }
        .frame(minWidth: 96)
    }

    private var shown: [(offset: Int, question: Question, attempt: Attempt)] {
        zip(session.questions, session.attempts).enumerated().compactMap { idx, pair in
            let ok = AnswerChecker.isCorrect(question: pair.0, response: pair.1.response)
            let answered = pair.1.isAnswered
            switch filter {
            case .missed where ok || !answered: return nil
            case .unanswered where answered: return nil
            case .correct where !ok: return nil
            default: return (idx, pair.0, pair.1)
            }
        }
    }

    private var listing: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Picker("", selection: $filter) {
                    ForEach(Filter.allCases, id: \.self) { f in
                        Text(label(for: f)).tag(f)
                    }
                }
                .pickerStyle(.segmented)
                .fixedSize()
                Spacer(minLength: 10)
                if !expanded.isEmpty {
                    Button(L("Collapse all")) { expanded.removeAll() }
                        .buttonStyle(.plain).font(.system(size: 12)).foregroundStyle(Palette.accent)
                } else {
                    Button(L("Expand all")) { expanded = Set(shown.map(\.question.id)) }
                        .buttonStyle(.plain).font(.system(size: 12)).foregroundStyle(Palette.accent)
                }
            }
            .padding(.horizontal, 26)
            .padding(.vertical, 12)

            if shown.isEmpty {
                let earned = filter == .missed && answeredAny
                VStack(spacing: 8) {
                    Image(systemName: earned ? "checkmark.seal.fill" : "tray")
                        .font(.system(size: 34))
                        .foregroundStyle(earned ? Palette.correct : Palette.secondaryText)
                    Text(emptyLine)
                        .font(.system(size: 14, weight: .medium))
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                GeometryReader { geo in
                    ScrollView {
                        LazyVStack(spacing: 10) {
                            ForEach(shown, id: \.question.id) { item in
                                row(item, width: max(0, geo.size.width - 52))
                            }
                        }
                        .padding(.horizontal, 26)
                        .padding(.bottom, 24)
                    }
                }
            }
        }
    }

    private var answeredAny: Bool {
        session.attempts.contains { !$0.response.isEmpty }
    }

    private var emptyLine: String {
        switch filter {
        case .missed:
            return answeredAny
                ? L("Nothing wrong — every question you answered was correct.")
                : L("Nothing to mark: every question was left blank.")
        case .unanswered: return L("Every question was answered.")
        default: return L("Nothing to show here.")
        }
    }

    private func label(for f: Filter) -> String {
        switch f {
        case .missed: return Lf("Got wrong (%d)", missed.count)
        case .unanswered: return Lf("Not answered (%d)", session.unansweredQuestions.count)
        case .correct: return Lf("Got right (%d)", correct)
        case .all: return Lf("All (%d)", session.questions.count)
        }
    }

    private var footer: some View {
        HStack(spacing: 12) {
            if let msg = exportMessage {
                Label(msg, systemImage: "checkmark.circle.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(Palette.correct)
            }
            Spacer()
            Button(L("Done")) { store.closeSession() }
                .buttonStyle(.plain)
                .font(.system(size: 13))
                .padding(.horizontal, 14).padding(.vertical, 8)

            BluebookButton(title: setAsideAllTitle, style: .plain,
                           enabled: !missed.isEmpty) { setAsideAllMissed() }

            BluebookButton(title: L("Export missed questions as PDF…"),
                           style: .secondary,
                           enabled: !missed.isEmpty) { exportMissed() }

            BluebookButton(title: L("Practice these again"), enabled: !missed.isEmpty) {
                practiseAgain()
            }
        }
        .padding(.horizontal, 26)
        .padding(.vertical, 14)
        .background(Palette.card)
    }

    private var allMissedSetAside: Bool {
        !missed.isEmpty && missed.allSatisfy { store.isSetAside($0.id, in: session.bankID) }
    }

    private var setAsideAllTitle: String {
        allMissedSetAside ? L("Remove these from set aside") : L("Set aside all I got wrong")
    }

    private func setAsideAllMissed() {
        let putBack = allMissedSetAside
        for q in missed where store.isSetAside(q.id, in: session.bankID) == putBack {
            store.toggleSetAside(q.id, in: session.bankID)
        }
    }

    private func exportMissed() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.pdf]
        panel.nameFieldStringValue = Lf("SAT review — %@.pdf", session.bankName)
        panel.message = Lf("This PDF can be read or printed, and imported back into "
                           + "%@ to practice again.", Brand.appName)
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try store.exportMissed(from: session, to: url)
            exportMessage = Lp(missed.count, "Saved %d question", "Saved %d questions")
        } catch {
            exportMessage = nil
            store.lastError = error.localizedDescription
        }
    }

    private func practiseAgain() {
        var c = session.config
        c.selection = .reviewMissed
        c.questionCount = missed.count
        store.closeSession()
        store.startSession(config: c)
    }
}

struct ReviewRow: View {
    let index: Int
    let question: Question
    let attempt: Attempt
    let imagesDirectory: URL
    let expanded: Bool
    let toggle: () -> Void
    var setAside: Bool = false
    var onSetAside: () -> Void = {}
    var answeredBy: String = ""
    var answeredByAccent: Int = 0
    var width: CGFloat = 0

    private var sheetWidth: CGFloat? { width > 0 ? max(0, width - 32) : nil }

    private var isCorrect: Bool { AnswerChecker.isCorrect(question: question, response: attempt.response) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button(action: toggle) {
                HStack(alignment: .top, spacing: 12) {
                    ZStack {
                        Circle().fill(isCorrect ? Palette.correct : Palette.wrong)
                            .frame(width: 22, height: 22)
                        Image(systemName: isCorrect ? "checkmark" : "xmark")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.white)
                    }

                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 7) {
                            Text(Lf("Question %d", index))
                                .font(.system(size: 13, weight: .semibold))
                            if !answeredBy.isEmpty {
                                Text(answeredBy)
                                    .font(Face.ui(9, .semibold))
                                    .tracking(0.5)
                                    .foregroundStyle(Color.white)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(ProfileAccent.colour(answeredByAccent))
                                    .clipShape(RoundedRectangle(cornerRadius: 3))
                            }
                        }
                        Text(metaLine)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                        HStack(spacing: 14) {
                            answerPill(L("Your answer"),
                                       attempt.isAnswered ? attempt.response : L("blank"),
                                       color: isCorrect ? Palette.correct : Palette.wrong)
                            if !isCorrect {
                                answerPill(L("Correct"), question.correctAnswer, color: Palette.correct)
                            }
                        }
                        .padding(.top, 2)
                    }
                    Spacer()
                    Button(action: onSetAside) {
                        HStack(spacing: 5) {
                            Image(systemName: setAside ? "tray.full.fill" : "tray")
                                .font(.system(size: 11))
                            Text(L("Set aside"))
                                .font(Face.ui(11, setAside ? .semibold : .regular))
                        }
                        .foregroundStyle(setAside ? Palette.brass : Palette.textMuted)
                    }
                    .buttonStyle(.plain)
                    .help(L("Keep this question to look at again at the end of your study time"))

                    Image(systemName: expanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                .padding(14)
            }
            .buttonStyle(.plain)

            if expanded {
                Divider()
                VStack(alignment: .leading, spacing: 14) {
                    let points = QuestionLayout.widest(
                        question.stimulus + question.prompt + question.rationale
                        + question.choices.flatMap(\.blocks))

                    if !question.stimulus.isEmpty {
                        BlocksView(blocks: question.stimulus, imagesDirectory: imagesDirectory,
                                   bodySize: 14, questionPoints: points, fixedWidth: sheetWidth)
                    }
                    BlocksView(blocks: question.prompt, imagesDirectory: imagesDirectory,
                               bodySize: 14, questionPoints: points, fixedWidth: sheetWidth)

                    ForEach(question.choices) { choice in
                        ChoiceRow(choice: choice, imagesDirectory: imagesDirectory, bodySize: 14,
                                  questionPoints: points,
                                  selected: attempt.response == choice.letter,
                                  eliminated: false, eliminatorOn: false, eliminable: false,
                                  state: choice.letter == question.correctAnswer ? .correct
                                       : (choice.letter == attempt.response ? .incorrect : .none),
                                  onSelect: {})
                            .allowsHitTesting(false)
                    }

                    if !question.rationale.isEmpty {
                        Text(L("Why"))
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.secondary)
                        BlocksView(blocks: question.rationale, imagesDirectory: imagesDirectory,
                                   bodySize: 13, questionPoints: points, fixedWidth: sheetWidth)
                    }
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Paper.canvas)
                .pinnedPaper()

                if !question.skill.isEmpty {
                    ArticleLink(skill: question.skill)
                        .padding(.horizontal, 16)
                        .padding(.bottom, 14)
                }
            }
        }
        .frame(width: width > 0 ? width : nil)
        .background(Palette.card)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Palette.hairline, lineWidth: 1))
    }

    private var metaLine: String {
        [question.test, question.domain, question.skill, question.difficulty]
            .filter { !$0.isEmpty }
            .joined(separator: " · ")
    }

    private func answerPill(_ label: String, _ value: String, color: Color) -> some View {
        HStack(spacing: 5) {
            Text(label).font(.system(size: 10)).foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(color)
        }
    }
}
