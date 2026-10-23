import SwiftUI
import AppKit
import ImageIO

enum ExamChrome {
    static var splitFraction: CGFloat = 0.5
    static var eliminatorOn = false
    static var timerHidden = false
    static var bodySize: Double = TypeScale.defaultBodySize
    static var fiveMinuteWarning = false

    static func reset() {
        splitFraction = 0.5
        eliminatorOn = false
        timerHidden = false
        bodySize = TypeScale.defaultBodySize
        fiveMinuteWarning = false
    }
}

private struct ExamPaneWidthKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        let next = nextValue()
        if next > 0 { value = next }
    }
}

struct ExamView: View {
    @EnvironmentObject var store: AppStore

    @State private var splitFraction: CGFloat = ExamChrome.splitFraction
    @State private var eliminatorOn = ExamChrome.eliminatorOn
    @State private var timerHidden = ExamChrome.timerHidden
    @State private var showNavigator = false
    @State private var showSubmitConfirm = false
    @State private var showQuitConfirm = false
    @State private var showReference = false
    @State private var clockWasHidden = false
    @State private var showReviewPage = false
    @State private var showNotes = false
    @State private var selection: (field: AnnotationField, block: Int, range: Range<Int>)?
    @State private var editingNote: Annotation?
    @State private var bodySize: Double = ExamChrome.bodySize
    @State private var paneWidth: CGFloat = 0
    @State private var elapsedTick = Date()
    @State private var timeUp = false
    @State private var fiveMinuteWarning = ExamChrome.fiveMinuteWarning
    @State private var showFiveMinuteNotice = false
    @State private var showDirections = false
    @State private var showMore = false
    @State private var showModuleConfirm = false

    private var lastModule: Bool {
        guard let s = store.session, let i = s.currentModuleIndex else { return true }
        return i == s.modules.count - 1
    }

    private let ticker = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        Group {
            if let session = store.session, !session.questions.isEmpty {
                if session.onBreak {
                    BreakScreen(session: session) { store.endBreak() }
                } else {
                    content(session)
                }
            } else {
                Paper.canvas
            }
        }
        .onReceive(ticker) { _ in tick(); saveElapsedIfUntimed() }
        .onChange(of: splitFraction) { ExamChrome.splitFraction = $0 }
        .onChange(of: eliminatorOn) { ExamChrome.eliminatorOn = $0 }
        .onChange(of: timerHidden) { ExamChrome.timerHidden = $0 }
        .onChange(of: bodySize) { ExamChrome.bodySize = $0 }
        .onChange(of: fiveMinuteWarning) { ExamChrome.fiveMinuteWarning = $0 }
    }

    private var moduleSubmitMessage: String {
        guard let s = store.session, let module = s.currentModule else { return "" }
        let unanswered = module.range.filter {
            s.attempts.indices.contains($0) && !s.attempts[$0].isAnswered
        }.count
        var parts = [String]()
        if unanswered > 0 {
            parts.append(Lp(unanswered, "%d question is unanswered",
                            "%d questions are unanswered"))
        }
        parts.append(lastModule
            ? L("This ends the test and shows your results.")
            : L("You cannot come back to this module once it is handed in, "
                + "the same as on the real test."))
        return parts.joined(separator: ". ")
    }

    private func content(_ session: Session) -> some View {
        VStack(spacing: 0) {
            header(session)
            practiceBanner
            turnBanner(session)
            highlightBar
            if showReviewPage {
                ReviewPageView(session: session) { idx in
                    store.session?.currentIndex = idx
                    store.saveSession()
                    showReviewPage = false
                }
            } else {
                questionArea(session)
            }
            footer(session)
        }
        .onPreferenceChange(ExamPaneWidthKey.self) { paneWidth = $0 }
        .background(Paper.canvas)
        .alert(L("Submit this section?"), isPresented: $showSubmitConfirm) {
            Button(L("Keep working"), role: .cancel) {}
            Button(L("Submit")) { submit() }
        } message: {
            Text(submitMessage(session))
        }
        .alert(L("Leave this test?"), isPresented: $showQuitConfirm) {
            Button(L("Keep working"), role: .cancel) {}
            Button(L("Save and leave")) { store.saveSession(); store.closeSession() }
            Button(L("Discard"), role: .destructive) {
                store.discardSavedSession(for: session.bankID)
                store.closeSession()
            }
        } message: {
            Text(L("Your place is saved, so you can pick this test up later from the home screen."))
        }
        .watchingKeys(handleZoomKey)
        .sheet(isPresented: $showReference) {
            ReferenceSheetView { showReference = false }.pinnedPaperWindow()
                .modifier(TimeUpAlert(isPresented: $timeUp, onResults: resultsOnTime))
        }
        .sheet(isPresented: $showNotes) {
            NotesPanel(question: session.questions[session.currentIndex],
                       bankID: session.bankID) { showNotes = false }
                .environmentObject(store)
                .pinnedPaperWindow()
                .modifier(TimeUpAlert(isPresented: $timeUp, onResults: resultsOnTime))
        }
        .sheet(item: $editingNote) { annotation in
            NoteEditor(annotation: annotation, bankID: session.bankID) { editingNote = nil }
                .environmentObject(store)
                .pinnedPaperWindow()
                .modifier(TimeUpAlert(isPresented: $timeUp, onResults: resultsOnTime))
        }
        .alert(L("5 minutes remaining"), isPresented: $showFiveMinuteNotice) {
            Button(L("OK")) {}
        } message: {
            Text(clockWasHidden ? L("The clock is showing again so you can pace the rest of the section.")
                                : L("Pace the rest of the section by the clock."))
        }
        .alert(lastModule ? L("Finish the test?") : L("Submit this module?"),
               isPresented: $showModuleConfirm) {
            Button(L("Keep working"), role: .cancel) {}
            Button(lastModule ? L("Finish") : L("Submit")) { store.submitCurrentModule() }
        } message: {
            Text(moduleSubmitMessage)
        }
        .modifier(TimeUpAlert(isPresented: $timeUp, onResults: resultsOnTime))
    }

    private func header(_ session: Session) -> some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 3) {
                Text(session.moduleTitle ?? session.displayTitle)
                    .font(Face.display(16, .semibold))
                    .foregroundStyle(Paper.navy)
                    .lineLimit(1)
                HStack(spacing: 9) {
                    Button {
                        showDirections.toggle()
                    } label: {
                        HStack(spacing: 3) {
                            Text(L("Directions")).font(Face.ui(11))
                            Image(systemName: "chevron.down")
                                .font(.system(size: 7, weight: .bold))
                        }
                        .foregroundStyle(Paper.accent)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .popover(isPresented: $showDirections, arrowEdge: .bottom) {
                        DirectionsPanel(session: session) { showDirections = false }
                            .pinnedPaperWindow()
                    }

                    Text([session.moduleProgressLine ?? session.subtitleLine,
                          session.currentModule.map { $0.form == .mixed ? "" : $0.form.label } ?? ""]
                            .filter { !$0.isEmpty }.joined(separator: " · "))
                        .font(Face.ui(10))
                        .foregroundStyle(Paper.textMuted)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            timerBlock(session)
                .frame(maxWidth: .infinity)

            HStack(spacing: 22) {
                zoomControls(session)
                if session.offersReference {
                    headerIcon("function", L("Reference")) { showReference = true }
                        .help(L("Formulas and figures provided on the Math section"))
                }
                headerIcon("highlighter", L("Highlights & Notes")) { showNotes = true }
                    .help(L("Everything you have highlighted or noted on this question"))
                    .overlay(alignment: .topTrailing) {
                        let n = store.annotationCount(
                            for: session.questions[session.currentIndex].id,
                            in: session.bankID)
                        if n > 0 {
                            Text("\(n)")
                                .font(Face.ui(8, .bold))
                                .foregroundStyle(Paper.card)
                                .padding(3)
                                .background(Circle().fill(Paper.brass))
                                .offset(x: 8, y: -4)
                        }
                    }
                headerIcon("ellipsis", L("More")) { showMore.toggle() }
                    .popover(isPresented: $showMore, arrowEdge: .bottom) {
                        moreMenu(session).pinnedPaperWindow()
                    }
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(.horizontal, 24)
        .padding(.top, WindowChrome.trafficLights + 6)
        .padding(.bottom, 11)
        .background(Paper.card)
        .overlay(alignment: .bottom) { Rule(onPaper: true) }
    }

    private func handleZoomKey(_ event: NSEvent) -> Bool {
        let held = event.modifierFlags
        if !held.intersects([.command, .control, .option]), !showNotes, !showReference, editingNote == nil,
           !showReviewPage,
           let s = store.session, !s.isFinished {
            if event.keyCode == Key.leftArrow { move(-1); return true }
            if event.keyCode == Key.rightArrow { move(1); return true }
            let q = s.questions[s.currentIndex]
            let a = s.attempts[s.currentIndex]
            let locked = s.config.grading == .immediate && a.revealed
            if q.kind == .multipleChoice, !locked,
               let key = event.charactersIgnoringModifiers?.uppercased(),
               q.choices.contains(where: { $0.letter == key }) {
                select(key)
                return true
            }
        }
        guard held.contains(.command) || held.contains(.control) else { return false }
        switch event.charactersIgnoringModifiers {
        case "+", "=": bodySize = TypeScale.clampBodySize(bodySize + 1); return true
        case "-":      bodySize = TypeScale.clampBodySize(bodySize - 1); return true
        case "0":      bodySize = TypeScale.defaultBodySize; return true
        default:       return false
        }
    }

    private func moreMenu(_ session: Session) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            moreRow(store.settings.stealthMode ? L("Turn Stealth Mode off")
                                               : L("Turn Stealth Mode on"),
                    store.settings.stealthMode ? "sun.max" : "moon.stars",
                    detail: store.settings.stealthMode
                        ? L("Back to the white screen the real test uses.")
                        : L("Draw this on black, and keep the app quiet.")) {
                showMore = false
                store.settings.stealthMode.toggle()
            }
            Rule(onPaper: true)
            moreRow(L("Save and leave"), "tray.and.arrow.down",
                    detail: L("Keep your place and come back to it later.")) {
                showMore = false
                store.saveSession()
                store.closeSession()
            }
            Rule(onPaper: true)
            if session.isFullTest {
                moreRow(lastModule ? L("Finish test") : L("Submit module"), "checkmark.circle",
                        detail: lastModule ? L("Finish now and see your results.")
                                           : L("Hand in this module and go on to the next.")) {
                    showMore = false
                    showModuleConfirm = true
                }
            } else {
                moreRow(L("Submit section"), "checkmark.circle",
                        detail: L("Finish now and see your results.")) {
                    showMore = false
                    showSubmitConfirm = true
                }
            }
            Rule(onPaper: true)
            moreRow(L("Quit without saving"), "xmark.circle",
                    detail: L("Throw this sitting away."), destructive: true) {
                showMore = false
                showQuitConfirm = true
            }
        }
        .frame(width: 264)
        .background(Paper.card)
    }

    private func moreRow(_ title: String, _ symbol: String, detail: String,
                         destructive: Bool = false,
                         action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 9) {
                Image(systemName: symbol)
                    .font(.system(size: 12))
                    .foregroundStyle(destructive ? Paper.wrong : Paper.accent)
                    .frame(width: 16)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(Face.ui(12, .semibold))
                        .foregroundStyle(destructive ? Paper.wrong : Paper.text)
                    Text(detail)
                        .font(Face.ui(10))
                        .foregroundStyle(Paper.textMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func headerIcon(_ systemName: String, _ label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 3) {
                Image(systemName: systemName).font(.system(size: 13))
                Text(label).font(Face.ui(9)).tracking(0.3)
            }
            .foregroundStyle(Paper.navy)
        }
        .buttonStyle(.plain)
    }

    private func canEnlarge(_ session: Session) -> Bool {
        guard bodySize < TypeScale.bodySizeRange.upperBound else { return false }
        guard paneWidth > 0 else { return true }
        let question = session.questions[session.currentIndex]
        guard !(question.subject == .readingWriting && !question.stimulus.isEmpty)
        else { return true }
        let available = paneWidth - Self.pagePadding * 2
        let body = QuestionLayout.widest(scalePool(question, in: session))
        let choices = QuestionLayout.widest(choices: question.choices)
        let now = QuestionLayout.columnWidth(bodyPoints: body, choicePoints: choices,
                                             bodySize: bodySize, available: available)
        let next = QuestionLayout.columnWidth(bodyPoints: body, choicePoints: choices,
                                              bodySize: bodySize + 1, available: available)
        return next > now
    }

    private func zoomControls(_ session: Session) -> some View {
        let canGrow = canEnlarge(session)
        return HStack(spacing: 6) {
            Button { bodySize = TypeScale.clampBodySize(bodySize - 1) } label: {
                Image(systemName: "textformat.size.smaller").font(.system(size: 12))
                    .foregroundStyle(Paper.navy)
            }
            .buttonStyle(.plain)
            .disabled(bodySize <= TypeScale.bodySizeRange.lowerBound)
            .help(L("Smaller text"))
            .accessibilityLabel(L("Smaller text"))
            Button { bodySize = TypeScale.clampBodySize(bodySize + 1) } label: {
                Image(systemName: "textformat.size.larger").font(.system(size: 12))
                    .foregroundStyle(Paper.navy)
            }
            .buttonStyle(.plain)
            .disabled(!canGrow)
            .accessibilityLabel(L("Larger text"))
            .help(canGrow ? L("Larger text")
                          : L("This question already fills the window — make the window wider to go larger"))
        }
        .opacity(1)
    }

    @ViewBuilder
    private func timerBlock(_ session: Session) -> some View {
        VStack(spacing: 3) {
            if session.isFullTest, let module = session.currentModule {
                if timerHidden {
                    Image(systemName: "clock").font(.system(size: 17, weight: .medium))
                        .foregroundStyle(Paper.textMuted)
                } else {
                    Text(Format.clock(module.secondsRemaining))
                        .font(Face.figures(23, .semibold))
                        .monospacedDigit()
                        .foregroundStyle(module.secondsRemaining <= ExamTimer.warningSeconds
                                         ? Paper.wrong : Paper.navy)
                }
                Button(timerHidden ? L("Show") : L("Hide")) { timerHidden.toggle() }
                    .accessibilityLabel(timerHidden ? L("Show the timer") : L("Hide the timer"))
                    .buttonStyle(.plain)
                    .font(Face.ui(10))
                    .foregroundStyle(Paper.navy)
                    .padding(.horizontal, 13)
                    .padding(.vertical, 3)
                    .overlay(RoundedRectangle(cornerRadius: 2)
                        .strokeBorder(Paper.border, lineWidth: 1))
            } else if session.config.timed {
                if timerHidden {
                    Image(systemName: "clock").font(.system(size: 17, weight: .medium))
                        .foregroundStyle(Paper.textMuted)
                } else {
                    Text(Format.clock(session.secondsRemaining))
                        .font(Face.figures(23, .semibold))
                        .monospacedDigit()
                        .foregroundStyle(session.secondsRemaining <= ExamTimer.warningSeconds
                                         ? Paper.wrong : Paper.navy)
                }
                Button(timerHidden ? L("Show") : L("Hide")) { timerHidden.toggle() }
                    .accessibilityLabel(timerHidden ? L("Show the timer") : L("Hide the timer"))
                    .buttonStyle(.plain)
                    .font(Face.ui(10))
                    .foregroundStyle(Paper.navy)
                    .padding(.horizontal, 13)
                    .padding(.vertical, 3)
                    .overlay(RoundedRectangle(cornerRadius: 2)
                        .strokeBorder(Paper.border, lineWidth: 1))
            } else {
                Text(L("Untimed"))
                    .font(Face.ui(12))
                    .tracking(0.5)
                    .foregroundStyle(Paper.textMuted)
            }
        }
    }

    private var practiceBanner: some View {
        Text(L("THIS IS A PRACTICE TEST"))
            .font(Face.ui(9, .semibold))
            .tracking(1.8)
            .foregroundStyle(Paper.navy.opacity(0.75))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 5)
            .background(Paper.brassSoft)
            .overlay(alignment: .top) { Rectangle().fill(Paper.brass.opacity(0.5)).frame(height: 1) }
            .overlay(alignment: .bottom) { Rectangle().fill(Paper.brass.opacity(0.35)).frame(height: 1) }
    }

    @ViewBuilder
    private func turnBanner(_ session: Session) -> some View {
        if session.isDouble {
            let seat = session.turn(at: session.currentIndex)
            let tint = ProfileAccent.colour(session.turnAccents.indices.contains(seat)
                                            ? session.turnAccents[seat] : seat)
            HStack(spacing: 8) {
                Text(session.turnName(at: session.currentIndex).uppercased())
                    .font(Face.ui(11, .semibold))
                    .tracking(1.2)
                Text("·").opacity(0.5)
                Text(L("your turn"))
                    .font(Face.ui(11))
                    .tracking(0.4)
            }
            .foregroundStyle(Color.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
            .background(tint)
            .id(seat)
            .animation(Motion.quick, value: seat)
        }
    }

    static let pagePadding: CGFloat = 26

    @ViewBuilder
    private func questionArea(_ session: Session) -> some View {
        let index = session.currentIndex
        let question = session.questions[index]
        let imagesDir = store.imagesDir(session.bankID)

        GeometryReader { geo in
            Color.clear
                .frame(height: 0)
                .preference(key: ExamPaneWidthKey.self, value: geo.size.width)
            if question.subject == .readingWriting && !question.stimulus.isEmpty {
                let leftPane = geo.size.width * Split.clamp(splitFraction)
                let rightPane = geo.size.width - leftPane - Split.dividerWidth
                let inset = Self.pagePadding * 2

                SplitPane(fraction: $splitFraction) {
                    ScrollView {
                        annotatable(question.stimulus, field: .stimulus, question: question,
                                    imagesDir: imagesDir,
                                    scale: QuestionLayout.figureScale(
                                        bodyPoints: QuestionLayout.widest(question.stimulus),
                                        choicePoints: 0, bodySize: bodySize,
                                        width: leftPane - inset))
                            .padding(.horizontal, Self.pagePadding)
                            .padding(.vertical, 22)
                    }
                    .id("stim-\(question.id)")
                } right: {
                    ScrollView {
                        questionColumn(session, question: question, imagesDir: imagesDir,
                                       scale: questionScale(question, in: session,
                                                            width: rightPane - inset))
                            .padding(.horizontal, Self.pagePadding)
                            .padding(.vertical, 18)
                    }
                    .id("q-\(question.id)")
                }
            } else {
                let available = geo.size.width - Self.pagePadding * 2
                let column = QuestionLayout.columnWidth(
                    bodyPoints: QuestionLayout.widest(scalePool(question, in: session)),
                    choicePoints: QuestionLayout.widest(choices: question.choices),
                    bodySize: bodySize, available: available)
                let scale = questionScale(question, in: session, width: column)

                ScrollView {
                    HStack {
                        Spacer(minLength: 0)
                        VStack(alignment: .leading, spacing: 0) {
                            if !question.stimulus.isEmpty {
                                annotatable(question.stimulus, field: .stimulus,
                                            question: question, imagesDir: imagesDir,
                                            scale: scale)
                                    .padding(.bottom, 16)
                            }
                            questionColumn(session, question: question,
                                           imagesDir: imagesDir, scale: scale)
                        }
                        .frame(maxWidth: column)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, Self.pagePadding)
                    .padding(.vertical, 18)
                }
                .id("q-\(question.id)")
            }
        }
    }

    private func scalePool(_ q: Question, in session: Session) -> [ContentBlock] {
        q.stimulus + q.prompt
            + (session.config.grading == .immediate ? q.rationale : [])
    }

    private func questionScale(_ q: Question, in session: Session,
                               width: CGFloat) -> Double {
        QuestionLayout.figureScale(
            bodyPoints: QuestionLayout.widest(scalePool(q, in: session)),
            choicePoints: QuestionLayout.widest(choices: q.choices),
            bodySize: bodySize, width: width)
    }

    private func questionColumn(_ session: Session, question: Question, imagesDir: URL,
                                scale: Double) -> some View {
        let attempt = session.attempts[session.currentIndex]
        let graded = session.config.grading == .immediate && attempt.revealed

        return VStack(alignment: .leading, spacing: 14) {
            questionHeaderBar(session)

            annotatable(question.prompt, field: .prompt, question: question,
                        imagesDir: imagesDir, scale: scale)

            if question.kind == .multipleChoice {
                VStack(spacing: 9) {
                    ForEach(question.choices) { choice in
                        ChoiceRow(
                            choice: choice,
                            imagesDirectory: imagesDir,
                            bodySize: bodySize,
                            figureScale: scale,
                            selected: attempt.response == choice.letter,
                            eliminated: attempt.eliminated.contains(choice.letter),
                            eliminatorOn: eliminatorOn,
                            state: graded ? gradeState(question: question, choice: choice, attempt: attempt) : .none,
                            onSelect: { select(choice.letter) },
                            onEliminate: { toggleEliminate(choice.letter) }
                        )
                    }
                }
            } else {
                GridInField(
                    value: Binding(
                        get: { store.session?.attempts[session.currentIndex].response ?? "" },
                        set: { setResponse($0) }
                    ),
                    bodySize: bodySize,
                    locked: graded
                )
            }

            if session.config.grading == .immediate {
                immediateFeedback(session, question: question, attempt: attempt,
                                  imagesDir: imagesDir, scale: scale)
            }
        }
    }

    private func annotatable(_ blocks: [ContentBlock], field: AnnotationField,
                             question: Question, imagesDir: URL,
                             scale: Double) -> some View {
        let bankID = store.session?.bankID ?? ""
        return AnnotatableBlocksView(
            blocks: blocks,
            field: field,
            questionID: question.id,
            annotations: store.annotations(for: question.id, in: bankID),
            imagesDirectory: imagesDir,
            bodySize: bodySize,
            figureScale: scale,
            onSelect: { f, block, range in
                selection = range.map { (f, block, $0) }
            },
            onTapAnnotation: { editingNote = $0 })
    }

    private var highlightBar: some View {
        let showing = selection != nil
        return HStack(spacing: 10) {
                Text(L("Highlight"))
                    .font(Face.ui(11, .semibold))
                    .foregroundStyle(Paper.textMuted)
                ForEach(0..<Paper.highlights.count, id: \.self) { i in
                    Button {
                        addHighlight(colorIndex: i, note: "")
                    } label: {
                        Circle()
                            .fill(Paper.highlight(i))
                            .frame(width: 18, height: 18)
                            .overlay(Circle().strokeBorder(Paper.border, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    .help(L("Highlight the selected text"))
                    .accessibilityLabel(L("Highlight the selected text"))
                }
                Rule(onPaper: true).frame(height: 16)
                Button(L("Add note")) { addHighlight(colorIndex: 0, note: " ") }
                    .buttonStyle(.plain)
                    .font(Face.ui(11, .semibold))
                    .foregroundStyle(Paper.navy)
                Spacer()
                Button(L("Cancel")) { self.selection = nil }
                    .buttonStyle(.plain)
                    .font(Face.ui(11))
                    .foregroundStyle(Paper.textMuted)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(Paper.brassSoft.opacity(0.55))
            .overlay(alignment: .bottom) { Rule(onPaper: true) }
            .opacity(showing ? 1 : 0)
            .allowsHitTesting(showing)
            .accessibilityHidden(!showing)
    }

    private func addHighlight(colorIndex: Int, note: String) {
        guard let selection, let session = store.session else { return }
        let q = session.questions[session.currentIndex]
        let a = Annotation(questionID: q.id, field: selection.field,
                           blockIndex: selection.block,
                           start: selection.range.lowerBound,
                           end: selection.range.upperBound,
                           note: note, colorIndex: colorIndex)
        store.addAnnotation(a, in: session.bankID)
        self.selection = nil
        if !note.isEmpty {
            editingNote = store.annotations(for: q.id, in: session.bankID)
                .first { $0.start == a.start && $0.blockIndex == a.blockIndex }
        }
    }

    private func questionHeaderBar(_ session: Session) -> some View {
        HStack(spacing: 12) {
            Text("\(session.currentIndex - (session.currentModule?.start ?? 0) + 1)")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(Paper.onBrand)
                .frame(width: 24, height: 24)
                .background(Paper.brandFill)

            MarkForReviewToggle(marked: Binding(
                get: { store.session?.attempts[session.currentIndex].markedForReview ?? false },
                set: { v in
                    store.session?.attempts[session.currentIndex].markedForReview = v
                    store.saveSession()
                }
            ))

            SetAsideToggle(setAside: Binding(
                get: { store.isSetAside(session.questions[session.currentIndex].id,
                                        in: session.bankID) },
                set: { _ in
                    store.toggleSetAside(session.questions[session.currentIndex].id,
                                         in: session.bankID)
                }
            ))

            Spacer()

            if session.questions[session.currentIndex].kind == .multipleChoice {
                EliminatorToggle(on: $eliminatorOn)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(Paper.subtleFill)
        .overlay(alignment: .bottom) { Rectangle().fill(Paper.hairline).frame(height: 1) }
    }

    @ViewBuilder
    private func immediateFeedback(_ session: Session, question: Question,
                                   attempt: Attempt, imagesDir: URL,
                                   scale: Double) -> some View {
        if attempt.revealed {
            let correct = AnswerChecker.isCorrect(question: question, response: attempt.response)
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: correct ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .foregroundStyle(correct ? Paper.correct : Paper.wrong)
                    Text(correct ? L("Correct")
                         : Lf("Not quite — the answer is %@", question.correctAnswer))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(correct ? Paper.correct : Paper.wrong)
                }
                if !question.rationale.isEmpty {
                    Rule(onPaper: true)
                    Text(L("Why"))
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Paper.secondaryText)
                    BlocksView(blocks: question.rationale, imagesDirectory: imagesDir,
                               bodySize: bodySize - 1, figureScale: scale)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(correct ? Paper.correctSoft : Paper.wrongSoft)
            .clipShape(RoundedRectangle(cornerRadius: 8))
        } else if attempt.isAnswered {
            BluebookButton(title: L("Check answer"), style: .secondary) { reveal() }
        }
    }

    private func gradeState(question: Question, choice: Choice, attempt: Attempt) -> ChoiceRow.GradeState {
        if choice.letter == question.correctAnswer { return .correct }
        if choice.letter == attempt.response { return .incorrect }
        return .none
    }

    private func footer(_ session: Session) -> some View {
        HStack {
            Text(session.bankName)
                .font(Face.ui(11))
                .foregroundStyle(Paper.textMuted)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)

            Button {
                showNavigator.toggle()
            } label: {
                HStack(spacing: 6) {
                    Text(session.isFullTest
                         ? (session.moduleProgressLine ?? "")
                         : Lf("Question %1$d of %2$d", session.currentIndex + 1,
                              session.questions.count))
                        .font(Face.ui(12, .semibold))
                        .tracking(0.2)
                    Image(systemName: "chevron.up").font(.system(size: 8, weight: .bold))
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 7)
                .background(Paper.brandFill)
                .foregroundStyle(Paper.onBrand)
                .clipShape(RoundedRectangle(cornerRadius: 3))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(L("Go to question") + ", "
                                + (session.isFullTest
                                   ? (session.moduleProgressLine ?? "")
                                   : Lf("Question %1$d of %2$d", session.currentIndex + 1,
                                        session.questions.count)))
            .popover(isPresented: $showNavigator, arrowEdge: .top) {
                NavigatorPanel(session: session, onPick: { idx in
                    store.session?.currentIndex = idx
                    showNavigator = false
                    showReviewPage = false
                    store.saveSession()
                }, onReview: {
                    showNavigator = false
                    showReviewPage = true
                })
                .pinnedPaperWindow()
            }

            HStack(spacing: 10) {
                if showReviewPage {
                    BluebookButton(title: L("Back"), style: .plain) { showReviewPage = false }
                } else if session.canMove(to: session.currentIndex - 1) {
                    BluebookButton(title: L("Back"), style: .plain) { move(-1) }
                }
                if !showReviewPage, session.canMove(to: session.currentIndex + 1) {
                    BluebookButton(title: L("Next"), onCanvas: true) { move(1) }
                } else if !showReviewPage {
                    BluebookButton(title: L("Next"), onCanvas: true) { showReviewPage = true }
                } else if session.isFullTest {
                    BluebookButton(title: lastModule ? L("Finish test") : L("Submit module"),
                                   onCanvas: true) { showModuleConfirm = true }
                } else {
                    BluebookButton(title: L("Submit"), onCanvas: true) { showSubmitConfirm = true }
                }
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 10)
        .background(Paper.chrome)
        .overlay(alignment: .top) { Rectangle().fill(Paper.hairline).frame(height: 1) }
    }

    private func submitMessage(_ session: Session) -> String {
        let unanswered = session.questions.count - session.answeredCount
        let marked = session.attempts.filter(\.markedForReview).count
        var parts = [String]()
        if unanswered > 0 { parts.append(Lf("%d unanswered", unanswered)) }
        if marked > 0 { parts.append(Lf("%d marked for review", marked)) }
        if parts.isEmpty { return L("All questions are answered.") }
        return Lf("You have %@.", parts.joined(separator: L(" and ")))
    }

    private func move(_ delta: Int) {
        guard var s = store.session else { return }
        let next = s.currentIndex + delta
        guard s.canMove(to: next) else { return }
        s.currentIndex = next
        store.session = s
        store.saveSession()
    }

    private func select(_ letter: String) {
        guard var s = store.session else { return }
        s.attempts[s.currentIndex].eliminated.remove(letter)
        s.attempts[s.currentIndex].response = letter
        store.session = s
        store.saveSession()
    }

    private func setResponse(_ value: String) {
        guard var s = store.session else { return }
        s.attempts[s.currentIndex].response = value
        store.session = s
        store.saveSession()
    }

    private func toggleEliminate(_ letter: String) {
        guard var s = store.session else { return }
        var elim = s.attempts[s.currentIndex].eliminated
        if elim.contains(letter) { elim.remove(letter) } else {
            elim.insert(letter)
            if s.attempts[s.currentIndex].response == letter {
                s.attempts[s.currentIndex].response = ""
            }
        }
        s.attempts[s.currentIndex].eliminated = elim
        store.session = s
        store.saveSession()
    }

    private func reveal() {
        guard var s = store.session else { return }
        s.attempts[s.currentIndex].revealed = true
        store.session = s
        store.saveSession()
    }

    private func submit() {
        store.finishSession()
    }

    private func resultsOnTime() {
        showNotes = false
        editingNote = nil
        showReference = false
        submit()
    }

    private func tick() {
        if var s = store.session, s.onBreak {
            s.breakRemaining = max(0, s.breakRemaining - 1)
            store.session = s
            if s.breakRemaining <= 0 { store.endBreak() }
            return
        }

        if var s = store.session, !s.isFinished,
           s.attempts.indices.contains(s.currentIndex) {
            s.attempts[s.currentIndex].secondsSpent += 1
            store.session = s
        }

        if var s = store.session, !s.isFinished, s.isFullTest,
           let index = s.currentModuleIndex {
            guard s.modules[index].secondsRemaining > 0 else { return }
            s.modules[index].secondsRemaining -= 1
            store.session = s

            if ExamTimer.shouldWarn(secondsRemaining: s.modules[index].secondsRemaining,
                                    alreadyWarned: fiveMinuteWarning,
                                    totalSeconds: Double(s.modules[index].minutes * 60)) {
                fiveMinuteWarning = true
                clockWasHidden = timerHidden
                timerHidden = false
                showFiveMinuteNotice = true
            }
            if s.modules[index].secondsRemaining <= 0 {
                fiveMinuteWarning = false
                store.submitCurrentModule()
            } else if Int(s.modules[index].secondsRemaining) % 10 == 0 {
                store.saveSession()
            }
            return
        }

        guard var s = store.session, !s.isFinished, s.config.timed else { return }
        guard s.secondsRemaining > 0 else { return }
        s.secondsRemaining -= 1
        store.session = s

        if ExamTimer.shouldWarn(secondsRemaining: s.secondsRemaining,
                                alreadyWarned: fiveMinuteWarning,
                                totalSeconds: Double(s.config.minutes * 60)) {
            fiveMinuteWarning = true
            clockWasHidden = timerHidden
            timerHidden = false
            showFiveMinuteNotice = true
        }

        if s.secondsRemaining <= 0 {
            timeUp = true
        }
        if Int(s.secondsRemaining) % 10 == 0 { store.saveSession() }
    }

    private func saveElapsedIfUntimed() {
        guard let s = store.session, !s.isFinished, !s.config.timed else { return }
        if Int(s.attempts[s.currentIndex].secondsSpent) % 15 == 0 { store.saveSession() }
    }
}

struct ChoiceRow: View {
    enum GradeState { case none, correct, incorrect }

    static let eliminatorWidth: CGFloat = 38

    let choice: Choice
    let imagesDirectory: URL
    let bodySize: Double
    var figureScale: Double? = nil
    var questionPoints: Double? = nil
    let selected: Bool
    let eliminated: Bool
    let eliminatorOn: Bool
    var eliminable: Bool = true
    var state: GradeState = .none
    let onSelect: () -> Void
    var onEliminate: () -> Void = {}

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            Button(action: onSelect) {
                HStack(alignment: .center, spacing: 11) {
                    letterBubble
                    BlocksView(blocks: choice.blocks, imagesDirectory: imagesDirectory,
                               bodySize: bodySize, spacing: 6, figureScale: figureScale,
                               questionPoints: questionPoints, centresDisplays: false)
                        .alignmentGuide(VerticalAlignment.center) { d in d.height * inkMiddle }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .opacity(eliminated ? 0.4 : 1)
                }
                .padding(.horizontal, 13)
                .padding(.vertical, 11)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(fill)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(borderColor, lineWidth: selected || state != .none ? 2 : 1)
                )
                .overlay(alignment: .leading) {
                    if eliminated {
                        Rectangle().fill(Paper.text.opacity(0.55))
                            .frame(height: 1)
                            .padding(.leading, 12)
                            .padding(.trailing, 12)
                    }
                }
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(answerLabel)
            .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)

            Group {
                if eliminatorOn {
                    Button(action: onEliminate) {
                        Group {
                            if eliminated {
                                Text(L("Undo"))
                                    .font(.system(size: 10, weight: .medium))
                                    .foregroundStyle(Paper.accent)
                                    .frame(width: Self.eliminatorWidth, height: 22)
                            } else {
                                ZStack {
                                    Circle().strokeBorder(Paper.border, lineWidth: 1)
                                        .frame(width: 22, height: 22)
                                    Text(choice.letter).font(.system(size: 10, weight: .semibold))
                                        .foregroundStyle(Paper.text)
                                    Rectangle().fill(Paper.text).frame(width: 18, height: 1)
                                }
                                .frame(width: Self.eliminatorWidth, height: 22)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .help(eliminated ? L("Bring this choice back")
                          : L("Cross out this choice"))
                    .accessibilityLabel(eliminated ? L("Bring this choice back")
                                        : Lf("Cross out choice %@", choice.letter))
                } else if eliminable {
                    Color.clear.frame(width: Self.eliminatorWidth, height: 1)
                }
            }
        }
    }

    private var answerLabel: String {
        let text = choice.plainText.trimmingCharacters(in: .whitespacesAndNewlines)
        let name = text.isEmpty ? Lf("Answer %@", choice.letter)
                                : Lf("Answer %1$@: %2$@", choice.letter, text)
        return eliminated ? name + ", " + L("crossed out") : name
    }

    private var inkMiddle: CGFloat {
        guard choice.blocks.count == 1, let b = choice.blocks.first, b.kind == .image,
              !b.hasWords else { return 0.5 }
        return InkMiddle.fraction(of: imagesDirectory.appendingPathComponent(b.imageName))
    }

    private var letterBubble: some View {
        ZStack {
            Circle()
                .fill(bubbleFill)
                .frame(width: 24, height: 24)
            Circle()
                .strokeBorder(bubbleStroke, lineWidth: 1.5)
                .frame(width: 24, height: 24)
            Text(choice.letter)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(letterColour)
        }
    }

    private var letterColour: Color {
        switch state {
        case .correct, .incorrect: return Paper.canvas
        case .none: return selected ? Paper.onBrand : Paper.text
        }
    }

    private var bubbleFill: Color {
        switch state {
        case .correct: return Paper.correct
        case .incorrect: return Paper.wrong
        case .none: return selected ? Paper.accentFill : .clear
        }
    }
    private var bubbleStroke: Color {
        switch state {
        case .correct: return Paper.correct
        case .incorrect: return Paper.wrong
        case .none: return selected ? Paper.accent : Paper.border
        }
    }
    private var borderColor: Color {
        switch state {
        case .correct: return Paper.correct
        case .incorrect: return Paper.wrong
        case .none: return selected ? Paper.accent : Paper.border
        }
    }
    private var fill: Color {
        switch state {
        case .correct: return Paper.correctSoft
        case .incorrect: return Paper.wrongSoft
        case .none: return selected ? Paper.accentSoft : Paper.canvas
        }
    }
}

struct GridInField: View {
    @Binding var value: String
    let bodySize: Double
    var locked: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            TextField(L("Enter your answer"), text: $value)
                .textFieldStyle(.plain)
                .font(.system(size: bodySize + 3, weight: .medium))
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .frame(maxWidth: 260, alignment: .leading)
                .background(Paper.canvas)
                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Paper.border, lineWidth: 1.5))
                .disabled(locked)

            Text(Lf("Answer preview: %@", value.isEmpty ? "—" : value))
                .font(.system(size: 11))
                .foregroundStyle(Paper.secondaryText)
        }
    }
}

struct NavigatorPanel: View {
    let session: Session
    let onPick: (Int) -> Void
    var onReview: (() -> Void)? = nil
    var onPage = false

    private var visible: [Int] {
        guard let module = session.currentModule, session.isFullTest else {
            return Array(session.questions.indices)
        }
        return Array(module.range)
    }

    private let columns = Array(repeating: GridItem(.fixed(38), spacing: 8), count: 8)

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(L("Go to question"))
                    .font(.system(size: 13, weight: .semibold))
                if session.isFullTest, let module = session.currentModule {
                    Text(module.title)
                        .font(.system(size: 10))
                        .foregroundStyle(Paper.textMuted)
                }
            }

            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(visible, id: \.self) { idx in
                    let a = session.attempts[idx]
                    Button { onPick(idx) } label: {
                        Text("\(idx - (visible.first ?? 0) + 1)")
                            .font(.system(size: 12, weight: .medium))
                            .frame(width: 34, height: 30)
                            .background(a.isAnswered ? Paper.brandFill : Paper.canvas)
                            .foregroundStyle(a.isAnswered ? Paper.onBrand : Paper.text)
                            .overlay(
                                RoundedRectangle(cornerRadius: 4)
                                    .strokeBorder(idx == session.currentIndex ? Paper.accent : Paper.border,
                                                  lineWidth: idx == session.currentIndex ? 2 : 1)
                            )
                            .overlay(alignment: .topTrailing) {
                                if a.markedForReview {
                                    Image(systemName: "bookmark.fill")
                                        .font(.system(size: 8))
                                        .foregroundStyle(Paper.wrong)
                                        .offset(x: 2, y: -3)
                                }
                            }
                    }
                    .buttonStyle(.plain)
                }
            }

            HStack(spacing: 16) {
                legend(color: Paper.brandFill, label: L("Answered"))
                legend(color: Paper.canvas, label: L("Unanswered"))
                HStack(spacing: 4) {
                    Image(systemName: "bookmark.fill").font(.system(size: 9)).foregroundStyle(Paper.wrong)
                    Text(L("For review")).font(.system(size: 11))
                }
            }
            .foregroundStyle(Paper.secondaryText)

            if let onReview {
                Button(action: onReview) {
                    Text(L("Go to Review Page"))
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Paper.accent)
                        .padding(.horizontal, 14).padding(.vertical, 6)
                        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Paper.accent, lineWidth: 1))
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity)
            }
        }
        .padding(16)
        .frame(width: onPage ? 520 : 400)
    }

    private func legend(color: Color, label: String) -> some View {
        HStack(spacing: 4) {
            RoundedRectangle(cornerRadius: 3).fill(color)
                .overlay(RoundedRectangle(cornerRadius: 3).strokeBorder(Paper.border, lineWidth: 1))
                .frame(width: 12, height: 12)
            Text(label).font(.system(size: 11))
        }
    }
}

struct BreakScreen: View {
    let session: Session
    var onEnd: () -> Void

    private var next: ExamModule? { session.currentModule }

    var body: some View {
        VStack(spacing: 26) {
            Spacer()

            Text(L("BREAK"))
                .font(Face.ui(11, .semibold))
                .tracking(3)
                .foregroundStyle(Paper.textMuted)

            Text(Format.clock(session.breakRemaining))
                .font(Face.figures(64, .semibold))
                .monospacedDigit()
                .foregroundStyle(session.breakRemaining <= 60 ? Paper.wrong : Paper.navy)

            VStack(spacing: 7) {
                if let next {
                    Text(Lf("Next: %@", next.title))
                        .font(Face.ui(14, .semibold))
                        .foregroundStyle(Paper.text)
                    Text(Lp(next.count, "%d question", "%d questions") + " · " + Lp(next.minutes, "%d minute", "%d minutes"))
                        .font(Face.ui(12))
                        .foregroundStyle(Paper.textMuted)
                }
                Text(L("The clock starts again when the break ends, whether you are back or not."))
                    .font(Face.ui(11))
                    .foregroundStyle(Paper.textMuted)
                    .padding(.top, 4)
            }

            BluebookButton(title: L("Resume testing"), onCanvas: true) { onEnd() }

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Paper.canvas)
    }
}

enum InkMiddle {
    private static var cache: [URL: CGFloat] = [:]

    static func fraction(of url: URL) -> CGFloat {
        if let known = cache[url] { return known }
        let found = measure(url) ?? 0.5
        cache[url] = found
        return found
    }

    private static func measure(_ url: URL) -> CGFloat? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return nil }
        let w = image.width, h = image.height
        guard w > 0, h > 0,
              let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w,
                                  space: CGColorSpaceCreateDeviceGray(),
                                  bitmapInfo: CGImageAlphaInfo.none.rawValue),
              let data = ctx.data else { return nil }
        ctx.setFillColor(gray: 1, alpha: 1)
        ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        let pixels = data.bindMemory(to: UInt8.self, capacity: w * h)
        func inked(_ row: Int) -> Bool {
            let start = row * w
            for x in 0..<w where pixels[start + x] < 200 { return true }
            return false
        }
        guard let top = (0..<h).first(where: inked),
              let bottom = (0..<h).reversed().first(where: inked) else { return nil }
        return (CGFloat(top) + CGFloat(bottom + 1)) / 2 / CGFloat(h)
    }
}

struct TimeUpAlert: ViewModifier {
    @Binding var isPresented: Bool
    let onResults: () -> Void

    func body(content: Content) -> some View {
        content.alert(L("Time's up"), isPresented: $isPresented) {
            Button(L("See results")) { onResults() }
        } message: {
            Text(L("The timer has run out. Your answers have been kept."))
        }
    }
}

struct ReviewPageView: View {
    let session: Session
    let onPick: (Int) -> Void

    private var range: [Int] {
        session.isFullTest ? Array(session.currentModule?.range ?? 0..<0) : Array(session.questions.indices)
    }

    var body: some View {
        let unanswered = range.filter { !session.attempts[$0].isAnswered }.count
        let marked = range.filter { session.attempts[$0].markedForReview }.count
        ScrollView {
            VStack(spacing: 16) {
                Text(L("Check your work"))
                    .font(Face.display(22, .semibold))
                    .foregroundStyle(Paper.navy)
                Text(L("Every question here, and which ones you have answered. Choose one to go back to it; hand the section in when you are ready."))
                    .font(.system(size: 13))
                    .foregroundStyle(Paper.text)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 520)
                    .fixedSize(horizontal: false, vertical: true)
                if unanswered > 0 || marked > 0 {
                    Text([unanswered > 0 ? Lp(unanswered, "%d question is unanswered", "%d questions are unanswered") : nil,
                          marked > 0 ? Lf("%d marked for review", marked) : nil]
                            .compactMap { $0 }.joined(separator: " · "))
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Paper.wrong)
                }
                NavigatorPanel(session: session, onPick: onPick, onPage: true)
                    .background(Paper.card)
                    .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Paper.border, lineWidth: 1))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            }
            .padding(.vertical, 36)
            .frame(maxWidth: .infinity)
        }
        .background(Paper.canvas)
    }
}
