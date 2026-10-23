import Foundation

enum Directions {

    struct Passage: Identifiable {
        var id: String { heading }
        var heading: String
        var lines: [String]
    }

    static func passages(subjects: Set<Subject>, hasGridIns: Bool,
                         timed: Bool, minutes: Int) -> [Passage] {
        var out = [Passage]()

        if subjects.contains(.readingWriting) {
            out.append(Passage(heading: L("Reading and Writing"), lines: [
                L("Each question is based on one or more passages, which may include "
                + "a table or a graph. Read the passage and the question, then "
                + "choose the best answer."),
                L("Every question has four choices and exactly one best answer."),
                L("You can highlight text in one of four colors and attach a note to it. "
                + "Highlighting works on Reading and Writing passages and on Math text "
                + "that contains no formulas. Highlights are kept with the question."),
            ]))
        }

        if subjects.contains(.math) {
            var lines = [
                L("You may use a calculator on any question. This app does not "
                + "provide one, so use whatever you will have on test day."),
                L("Reference — the formulas and figures the test provides — is in "
                + "the toolbar and can be opened at any time."),
                L("Unless a question says otherwise: all variables and expressions "
                + "stand for real numbers, figures are drawn to scale, every "
                + "figure lies in a plane, and the domain of a function is every "
                + "real number for which the function is real."),
            ]
            if hasGridIns {
                lines.append(L("Some questions ask you to type the answer rather "
                             + "than choose one. See \"Typing an answer\" below."))
            }
            out.append(Passage(heading: L("Math"), lines: lines))
        }

        if hasGridIns {
            out.append(Passage(heading: L("Typing an answer"), lines: [
                L("Enter a fraction as 3/4, or its decimal as 0.75 — either counts. "
                + "You do not have to reduce it."),
                L("A negative answer keeps its minus sign: −3/5 or −0.6."),
                L("A repeating decimal is right if you give enough of it: 2/3 can be "
                + "entered as 2/3, .6666 or 0.667."),
                L("You can type up to 5 characters for a positive answer and 6 for a "
                + "negative one; the minus sign counts."),
                L("Type a mixed number such as 3½ as 7/2 or 3.5. Typed as 3 1/2, it "
                + "reads as 31/2 and is marked wrong."),
                L("Do not type a comma, units, a percent sign, or a dollar sign."),
            ]))
        }

        out.append(Passage(heading: L("Working through the section"), lines: [
            timed
                ? Lp(minutes, "You have %d minute. The clock can be hidden, and it "
                              + "comes back on its own with five minutes left.",
                     "You have %d minutes. The clock can be hidden, and it comes "
                     + "back on its own with five minutes left.")
                : L("There is no clock on this sitting. Take the time you need."),
            L("Mark for Review flags a question so you can find it again; the list "
              + "at the foot of the screen jumps to any question."),
            L("Set aside keeps a question in a pile you can practice or export "
              + "later. Unlike Mark for Review, it outlives this sitting."),
            L("The answer eliminator — ABC — crosses out choices you have ruled out."),
            L("A−/A+ resize the question, and so do Ctrl or Command with + and −."),
        ]))

        return out
    }

    static func plain(subjects: Set<Subject>, hasGridIns: Bool,
                      timed: Bool, minutes: Int) -> String {
        passages(subjects: subjects, hasGridIns: hasGridIns, timed: timed, minutes: minutes)
            .map { "\($0.heading)\n\n" + $0.lines.joined(separator: "\n\n") }
            .joined(separator: "\n\n")
    }
}

extension Session {

    var displayTitle: String {
        let named = config.sittingName.trimmingCharacters(in: .whitespacesAndNewlines)
        return named.isEmpty ? defaultTitle : named
    }

    var defaultTitle: String {
        let subjects = Set(questions.map(\.subject))
        guard subjects.count == 1, let subject = subjects.first else {
            return L("Mixed practice")
        }
        let label = subject.sectionLabel
        if isModuleShaped { return Lf("Module 1: %@", label) }
        return Lf("%@ practice", label)
    }

    var isModuleShaped: Bool {
        let subjects = Set(questions.map(\.subject))
        guard subjects.count == 1, let subject = subjects.first, config.timed else { return false }
        let expected = subject == .math ? (22, 35) : (27, 32)
        return questions.count == expected.0 && config.minutes == expected.1
    }

    var subtitleLine: String {
        var parts = [Lp(questions.count, "%d question", "%d questions")]
        let subjects = Set(questions.map(\.subject))
        if subjects.count > 1 {
            let rw = questions.count { $0.subject == .readingWriting }
            parts = [Lf("%1$d Reading and Writing · %2$d Math", rw, questions.count - rw)]
        }
        parts.append(config.timed ? Lp(config.minutes, "%d minute", "%d minutes")
                                  : L("untimed"))
        return parts.joined(separator: " · ")
    }

    var hasGridIns: Bool { questions.contains { $0.kind == .studentResponse } }
}

extension Session {

    var resumeTitle: String {
        isFullTest ? (moduleTitle ?? displayTitle) : displayTitle
    }

    var resumePosition: String {
        let safe = min(max(0, currentIndex), max(0, questions.count - 1))
        if isFullTest, let module = currentModule {
            return Lf("Question %1$d of %2$d · %3$d answered",
                      max(1, safe - module.start + 1), module.count,
                      score(of: module).answered)
        }
        return Lf("Question %1$d of %2$d · %3$d answered",
                  safe + 1, questions.count, answeredCount)
    }

    var resumeClock: String? {
        let seconds = isFullTest ? (currentModule?.secondsRemaining ?? 0)
                                 : (config.timed ? secondsRemaining : 0)
        guard seconds > 0 else { return nil }
        let minutes = Int(seconds) / 60
        guard minutes >= 1 else { return L("under a minute left") }
        return Lp(minutes, "%d minute left", "%d minutes left")
    }

    func resumeAge(now: Date = Date(), calendar: Calendar = .current) -> String {
        let days = calendar.dateComponents([.day],
                                           from: calendar.startOfDay(for: lastSavedAt),
                                           to: calendar.startOfDay(for: now)).day ?? 0
        if days <= 0 { return L("left off today") }
        if days == 1 { return L("left off yesterday") }
        return Lp(days, "left off %d day ago", "left off %d days ago")
    }

    func resumeDetail(now: Date = Date(), calendar: Calendar = .current) -> String {
        var parts = [resumePosition]
        if let clock = resumeClock { parts.append(clock) }
        parts.append(resumeAge(now: now, calendar: calendar))
        return parts.joined(separator: " · ")
    }
}

import SwiftUI
import AppKit

struct DirectionsPanel: View {
    let session: Session
    var onClose: () -> Void

    private var passages: [Directions.Passage] {
        Directions.passages(subjects: Set(session.questions.map(\.subject)),
                            hasGridIns: session.hasGridIns,
                            timed: session.config.timed,
                            minutes: session.config.minutes)
    }

    static var height: CGFloat {
        let window = NSApp.keyWindow?.contentLayoutRect.height ?? 900
        return max(460, window - 150)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(L("Directions"))
                        .font(Face.display(15, .semibold))
                        .foregroundStyle(Paper.navy)
                    Text(session.displayTitle + " · " + session.subtitleLine)
                        .font(Face.ui(10))
                        .foregroundStyle(Paper.textMuted)
                }
                Spacer(minLength: 12)
                Button(L("Close"), action: onClose)
                    .buttonStyle(.plain)
                    .font(Face.ui(11, .semibold))
                    .foregroundStyle(Paper.accent)
            }
            .padding(.horizontal, 18)
            .padding(.top, 16)
            .padding(.bottom, 12)

            Rule(onPaper: true)

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    ForEach(passages) { passage in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(passage.heading.uppercased())
                                .font(Face.ui(9, .semibold))
                                .tracking(1.2)
                                .foregroundStyle(Paper.textMuted)
                            ForEach(Array(passage.lines.enumerated()), id: \.offset) { _, line in
                                Text(line)
                                    .font(.system(size: 12))
                                    .foregroundStyle(Paper.text)
                                    .lineSpacing(3)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                }
                .padding(18)
            }
        }
        .frame(width: 420, height: Self.height)
        .background(Paper.card)
    }
}
