import SwiftUI

struct DoubleExamView: View {
    @EnvironmentObject var store: AppStore

    @State private var showQuitConfirm = false
    @State private var showSubmitConfirm = false
    @State private var showReference = false
    @State private var timeUp = false
    @State private var showBothDone = false
    @State private var bodySize: Double = TypeScale.defaultBodySize

    private let ticker = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        Group {
            if let session = store.session, !session.questions.isEmpty {
                content(session)
            } else {
                Paper.canvas
            }
        }
        .onReceive(ticker) { _ in tick() }
    }

    private func content(_ session: Session) -> some View {
        VStack(spacing: 0) {
            header(session)
            practiceBanner
            GeometryReader { geometry in
                let half = max(120, (geometry.size.width - 1) / 2)
                HStack(spacing: 0) {
                    seat(session, 0, width: half)
                    Rectangle().fill(Paper.border).frame(width: 1)
                    seat(session, 1, width: half)
                }
                .frame(width: geometry.size.width, height: geometry.size.height)
            }
            .frame(maxHeight: .infinity)
            footer(session)
        }
        .background(Paper.canvas)
        .sheet(isPresented: $showReference) {
            ReferenceSheetView { showReference = false }.pinnedPaperWindow()
        }
        .alert(L("Submit this section?"), isPresented: $showSubmitConfirm) {
            Button(L("Keep working"), role: .cancel) {}
            Button(L("Submit")) { submit() }
        } message: {
            Text(L("Both of you will see your own results, and each answer goes "
                   + "into that student's own record."))
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
        .alert(L("You have both finished"), isPresented: $showBothDone) {
            Button(L("Keep working"), role: .cancel) {}
            Button(L("See results")) { submit() }
        } message: {
            Text(L("Every question has been answered or passed over. Keep working "
                   + "to go back over any of them, or end the test now."))
        }
        .alert(L("Time's up"), isPresented: $timeUp) {
            Button(L("See results")) { submit() }
        } message: {
            Text(L("The timer has run out. Your answers have been kept."))
        }
    }

    private func header(_ session: Session) -> some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 3) {
                Text(session.displayTitle)
                    .font(Face.display(16, .semibold))
                    .foregroundStyle(Paper.navy)
                    .lineLimit(1)
                Text(L("Side by side"))
                    .font(Face.ui(10))
                    .foregroundStyle(Paper.textMuted)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if session.config.timed {
                VStack(spacing: 1) {
                    Text(Format.clock(session.secondsRemaining))
                        .font(Face.figures(22, .semibold))
                        .monospacedDigit()
                        .foregroundStyle(session.secondsRemaining <= 300
                                         ? Paper.wrong : Paper.navy)
                    Text(L("for both of you"))
                        .font(Face.ui(9))
                        .foregroundStyle(Paper.textMuted)
                }
                .frame(maxWidth: .infinity)
            } else {
                Text(L("Untimed"))
                    .font(Face.ui(12))
                    .foregroundStyle(Paper.textMuted)
                    .frame(maxWidth: .infinity)
            }

            HStack(spacing: 18) {
                zoomControls
                if session.offersReference {
                    headerIcon("function", L("Reference")) { showReference = true }
                }
                headerIcon("tray.and.arrow.down", L("Leave")) { showQuitConfirm = true }
                headerIcon("checkmark.circle", L("Submit")) { showSubmitConfirm = true }
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(.horizontal, 24)
        .padding(.top, WindowChrome.trafficLights + 6)
        .padding(.bottom, 11)
        .background(Paper.card)
        .overlay(alignment: .bottom) { Rule(onPaper: true) }
    }

    private var practiceBanner: some View {
        Text(L("THIS IS A PRACTICE TEST"))
            .font(Face.ui(9, .semibold))
            .tracking(1.8)
            .foregroundStyle(Paper.navy.opacity(0.75))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 5)
            .background(Paper.brassSoft)
    }

    private var zoomControls: some View {
        HStack(spacing: 8) {
            Button { bodySize = TypeScale.clampBodySize(bodySize - 1) } label: {
                Text("A").font(.system(size: 11))
            }
            .buttonStyle(.plain)
            Button { bodySize = TypeScale.clampBodySize(bodySize + 1) } label: {
                Text("A").font(.system(size: 15))
            }
            .buttonStyle(.plain)
        }
        .foregroundStyle(Paper.navy)
    }

    private func headerIcon(_ symbol: String, _ label: String,
                            action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 3) {
                Image(systemName: symbol).font(.system(size: 13))
                Text(label).font(Face.ui(9)).tracking(0.3).lineLimit(1)
            }
            .foregroundStyle(Paper.navy)
        }
        .buttonStyle(.plain)
    }

    private func footer(_ session: Session) -> some View {
        HStack {
            Text(session.bankName)
                .font(Face.ui(11))
                .foregroundStyle(Paper.textMuted)
                .lineLimit(1)
            Spacer(minLength: 0)
            Text(L("Each answer goes into that student's own record."))
                .font(Face.ui(10))
                .foregroundStyle(Paper.textMuted)
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 10)
        .background(Paper.chrome)
        .overlay(alignment: .top) { Rectangle().fill(Paper.hairline).frame(height: 1) }
    }

    @ViewBuilder
    private func seat(_ session: Session, _ number: Int, width: CGFloat) -> some View {
        let positions = session.positions(for: number)
        let index = session.index(for: number)
        let finished = session.isFinished(seat: number)
        let tint = ProfileAccent.colour(session.turnAccents.indices.contains(number)
                                        ? session.turnAccents[number] : number)
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Text(session.turnNames.indices.contains(number)
                     ? session.turnNames[number].uppercased() : "")
                    .font(Face.ui(11, .semibold))
                    .tracking(1.2)
                    .lineLimit(1)
                Spacer(minLength: 0)
                Text(finished
                     ? L("done")
                     : Lf("%1$d of %2$d",
                          (positions.firstIndex(of: index) ?? 0) + 1, positions.count))
                    .font(Face.ui(10, .semibold))
            }
            .foregroundStyle(Color.white)
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            .background(tint)

            if !finished, session.questions.indices.contains(index) {
                questionColumn(session, index: index, number: number, tint: tint,
                               width: width)
            } else {
                VStack(spacing: 10) {
                    Image(systemName: "checkmark.circle")
                        .font(.system(size: 26, weight: .light))
                        .foregroundStyle(tint)
                    Text(session.bothSeatsFinished
                         ? L("Both of you are done.")
                         : L("All done — waiting for the other one to finish."))
                        .font(Face.ui(12))
                        .foregroundStyle(Paper.textMuted)
                        .multilineTextAlignment(.center)
                    BluebookButton(title: L("Back"), style: .plain) { move(-1, seat: number) }
                        .disabled(!canMove(-1, seat: number))
                        .opacity(canMove(-1, seat: number) ? 1 : 0.35)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(16)
            }
        }
        .frame(width: width, alignment: .top)
        .clipped()
    }

    private func questionColumn(_ session: Session, index: Int, number: Int,
                                tint: Color, width: CGFloat) -> some View {
        let question = session.questions[index]
        let attempt = session.attempt(at: index)
        let imagesDir = store.imagesDir(session.bankID)
        return VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if !question.stimulus.isEmpty {
                        BlocksView(blocks: question.stimulus, imagesDirectory: imagesDir,
                                   bodySize: bodySize, fixedWidth: width - 32)
                    }
                    BlocksView(blocks: question.prompt, imagesDirectory: imagesDir,
                               bodySize: bodySize, fixedWidth: width - 32)

                    if question.kind == .studentResponse {
                        GridInField(value: Binding(
                            get: { store.session?.attempts[index].response ?? "" },
                            set: { set($0, at: index) }), bodySize: bodySize)
                    } else {
                        ForEach(question.choices) { choice in
                            ChoiceRow(choice: choice, imagesDirectory: imagesDir,
                                      bodySize: bodySize,
                                      selected: attempt.response == choice.letter,
                                      eliminated: false, eliminatorOn: false,
                                      eliminable: false, state: .none,
                                      onSelect: { set(choice.letter, at: index) })
                        }
                    }
                }
                .padding(16)
                .frame(width: width, alignment: .leading)
            }
            .frame(width: width)

            HStack(spacing: 10) {
                BluebookButton(title: L("Back"), style: .plain) { move(-1, seat: number) }
                    .disabled(!canMove(-1, seat: number))
                    .opacity(canMove(-1, seat: number) ? 1 : 0.35)
                Spacer(minLength: 0)
                BluebookButton(title: L("Next"), onCanvas: true) { move(1, seat: number) }
                    .disabled(!canMove(1, seat: number))
                    .opacity(canMove(1, seat: number) ? 1 : 0.35)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(Paper.chrome)
            .overlay(alignment: .top) { Rectangle().fill(Paper.hairline).frame(height: 1) }
        }
    }

    private func set(_ value: String, at index: Int) {
        guard var s = store.session, s.attempts.indices.contains(index) else { return }
        s.attempts[index].response = value
        store.session = s
        store.saveSession()
    }

    private func canMove(_ delta: Int, seat: Int) -> Bool {
        guard let s = store.session else { return false }
        let positions = s.positions(for: seat)
        guard let at = positions.firstIndex(of: s.index(for: seat)) else { return false }
        if s.isFinished(seat: seat) { return delta < 0 }
        let next = at + delta
        return next >= 0 && next <= positions.count - (delta > 0 ? 0 : 1)
    }

    private func move(_ delta: Int, seat: Int) {
        guard var s = store.session else { return }
        let positions = s.positions(for: seat)
        guard let at = positions.firstIndex(of: s.index(for: seat)) else { return }
        let next = at + delta

        if next >= positions.count {
            if !s.seatsFinished.contains(seat) { s.seatsFinished.append(seat) }
        } else if next >= 0 {
            s.seatsFinished.removeAll { $0 == seat }
            let target = positions[next]
            if seat == 0 { s.currentIndex = target } else { s.partnerIndex = target }
        } else {
            return
        }
        store.session = s
        store.saveSession()
        if s.bothSeatsFinished { showBothDone = true }
    }

    private func submit() {
        store.finishSession()
    }

    private func tick() {
        guard var s = store.session, !s.isFinished, s.config.timed else { return }
        guard s.secondsRemaining > 0 else { return }
        s.secondsRemaining -= 1
        store.session = s
        if s.secondsRemaining <= 0 { timeUp = true }
        if Int(s.secondsRemaining) % 10 == 0 { store.saveSession() }
    }
}
