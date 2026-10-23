import Foundation

struct ExamModule: Codable, Hashable, Identifiable {
    var id: UUID = UUID()
    var subject: Subject
    var number: Int
    var start: Int
    var count: Int
    var minutes: Int
    var secondsRemaining: Double
    var submitted: Bool = false
    var form: ModuleForm = .mixed
    var breakAfter: Int = 0

    var range: Range<Int> { start..<(start + count) }
    var title: String {
        Lf("Section %1$d, Module %2$d: %3$@",
           subject == .readingWriting ? 1 : 2, number, subject.sectionLabel)
    }

    init(subject: Subject, number: Int, start: Int, count: Int, minutes: Int,
         breakAfter: Int = 0) {
        self.subject = subject
        self.number = number
        self.start = start
        self.count = count
        self.minutes = minutes
        self.secondsRemaining = Double(minutes * 60)
        self.breakAfter = breakAfter
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        subject = try c.decodeIfPresent(Subject.self, forKey: .subject) ?? .readingWriting
        number = try c.decodeIfPresent(Int.self, forKey: .number) ?? 1
        start = try c.decodeIfPresent(Int.self, forKey: .start) ?? 0
        count = try c.decodeIfPresent(Int.self, forKey: .count) ?? 0
        minutes = try c.decodeIfPresent(Int.self, forKey: .minutes) ?? 0
        secondsRemaining = try c.decodeIfPresent(Double.self, forKey: .secondsRemaining)
            ?? Double(minutes * 60)
        submitted = try c.decodeIfPresent(Bool.self, forKey: .submitted) ?? false
        form = (try? c.decodeIfPresent(ModuleForm.self, forKey: .form)).flatMap { $0 } ?? .mixed
        breakAfter = try c.decodeIfPresent(Int.self, forKey: .breakAfter) ?? 0
    }
}

enum TestForm {

    struct Part {
        var subject: Subject
        var questions: Int
        var minutes: Int
        var breakAfter: Int
    }

    static let digital: [Part] = [
        Part(subject: .readingWriting, questions: 27, minutes: 32, breakAfter: 0),
        Part(subject: .readingWriting, questions: 27, minutes: 32, breakAfter: 10),
        Part(subject: .math, questions: 22, minutes: 35, breakAfter: 0),
        Part(subject: .math, questions: 22, minutes: 35, breakAfter: 0),
    ]

    static var readingWritingNeeded: Int {
        digital.filter { $0.subject == .readingWriting }.reduce(0) { $0 + $1.questions }
    }
    static var mathNeeded: Int {
        digital.filter { $0.subject == .math }.reduce(0) { $0 + $1.questions }
    }
    static var totalQuestions: Int { readingWritingNeeded + mathNeeded }
    static var totalMinutes: Int { digital.reduce(0) { $0 + $1.minutes } }
    static var breakMinutes: Int { digital.reduce(0) { $0 + $1.breakAfter } }

    struct Readiness {
        var readingWriting: Int
        var math: Int
        var isReady: Bool {
            readingWriting >= readingWritingNeeded && math >= mathNeeded
        }
        var shortfall: String? {
            guard !isReady else { return nil }
            let shortRW = readingWritingNeeded - readingWriting
            let shortMath = mathNeeded - math
            if shortRW > 0 && shortMath > 0 {
                return Lf("A full test needs %1$d Reading and Writing questions and "
                          + "%2$d Math. You need %3$d more Reading and Writing and "
                          + "%4$d more Math.",
                          readingWritingNeeded, mathNeeded, shortRW, shortMath)
            }
            if shortRW > 0 {
                return Lf("A full test needs %1$d Reading and Writing questions and "
                          + "%2$d Math. You need %3$d more Reading and Writing.",
                          readingWritingNeeded, mathNeeded, shortRW)
            }
            return Lf("A full test needs %1$d Reading and Writing questions and "
                      + "%2$d Math. You need %3$d more Math.",
                      readingWritingNeeded, mathNeeded, shortMath)
        }
    }

    static func modules(readingWriting: [Question], math: [Question])
        -> (questions: [Question], modules: [ExamModule])? {
        guard readingWriting.count >= readingWritingNeeded,
              math.count >= mathNeeded else { return nil }

        var questions = [Question]()
        var modules = [ExamModule]()
        var taken = [Subject.readingWriting: 0, Subject.math: 0]
        var numbered = [Subject.readingWriting: 0, Subject.math: 0]

        for part in digital {
            let source = part.subject == .readingWriting ? readingWriting : math
            let from = taken[part.subject] ?? 0
            let slice = Array(source[from..<(from + part.questions)])
            taken[part.subject] = from + part.questions
            numbered[part.subject] = (numbered[part.subject] ?? 0) + 1

            modules.append(ExamModule(subject: part.subject,
                                      number: numbered[part.subject] ?? 1,
                                      start: questions.count,
                                      count: slice.count,
                                      minutes: part.minutes,
                                      breakAfter: part.breakAfter))
            questions += slice
        }
        return (questions, modules)
    }
}

extension Session {

    var isFullTest: Bool { !modules.isEmpty }

    var offersReference: Bool {
        if let module = currentModule { return module.subject == .math }
        return questions.contains { $0.subject == .math }
    }

    var currentModule: ExamModule? {
        modules.first { $0.range.contains(currentIndex) } ?? modules.last
    }

    var currentModuleIndex: Int? {
        modules.firstIndex { $0.range.contains(currentIndex) }
    }

    var moduleProgressLine: String? {
        guard let module = currentModule, let index = currentModuleIndex else { return nil }
        let within = currentIndex - module.start + 1
        return Lf("Question %1$d of %2$d · module %3$d of %4$d",
                  within, module.count, index + 1, modules.count)
    }

    var moduleTitle: String? { currentModule?.title }

    func canMove(to index: Int) -> Bool {
        guard isFullTest else { return index >= 0 && index < questions.count }
        guard let module = currentModule else { return false }
        return module.range.contains(index)
    }

    func score(of module: ExamModule) -> (correct: Int, answered: Int) {
        var correct = 0, answered = 0
        for i in module.range where attempts.indices.contains(i) && questions.indices.contains(i) {
            if attempts[i].isAnswered {
                answered += 1
                if AnswerChecker.isCorrect(question: questions[i], response: attempts[i].response) {
                    correct += 1
                }
            }
        }
        return (correct, answered)
    }
}

enum ModuleForm: String, Codable {
    case mixed
    case lower
    case upper

    var label: String {
        switch self {
        case .mixed: return L("Mixed")
        case .lower: return L("Easier form")
        case .upper: return L("Harder form")
        }
    }
}

extension TestForm {

    static let difficulties = ["Easy", "Medium", "Hard"]

    static func mix(_ form: ModuleForm, total: Int) -> [String: Int] {
        let weights: [Double]
        switch form {
        case .mixed: weights = [0.34, 0.33, 0.33]
        case .lower: weights = [0.52, 0.33, 0.15]
        case .upper: weights = [0.11, 0.33, 0.56]
        }
        var counts = [String: Int]()
        var assigned = 0
        for (i, label) in difficulties.enumerated() {
            let n = i == difficulties.count - 1
                ? total - assigned
                : Int((Double(total) * weights[i]).rounded())
            counts[label] = n
            assigned += n
        }
        return counts
    }

    struct AdaptiveReadiness {
        var counts: [Subject: [String: Int]]

        static func moduleSize(for subject: Subject) -> Int {
            subject == .math ? 22 : 27
        }

        static func needed(for subject: Subject, _ difficulty: String) -> Int {
            let size = moduleSize(for: subject)
            return [ModuleForm.mixed, .lower, .upper].reduce(0) {
                $0 + (TestForm.mix($1, total: size)[difficulty] ?? 0)
            }
        }

        var isReady: Bool {
            Subject.allCases.allSatisfy { subject in
                TestForm.difficulties.allSatisfy {
                    (counts[subject]?[$0] ?? 0) >= Self.needed(for: subject, $0)
                }
            }
        }

        var shortfall: String? {
            guard !isReady else { return nil }
            var lines = [String]()
            for subject in [Subject.readingWriting, .math] {
                let missing = TestForm.difficulties.filter {
                    (counts[subject]?[$0] ?? 0) < Self.needed(for: subject, $0)
                }
                guard !missing.isEmpty else { continue }
                let detail = missing.map {
                    "\($0.lowercased()) (\(counts[subject]?[$0] ?? 0) of \(Self.needed(for: subject, $0)))"
                }.joined(separator: ", ")
                lines.append("\(subject.sectionLabel): \(detail)")
            }
            return L("An adaptive test draws module 1 and both forms of module 2 "
                     + "from the set, so each section needs enough questions at "
                     + "every difficulty. Still short —")
                + " " + lines.joined(separator: "; ") + "."
        }
    }

    static let upperThreshold: Double = 0.65

    static func route(correct: Int, outOf total: Int) -> ModuleForm {
        guard total > 0 else { return .lower }
        return Double(correct) / Double(total) >= upperThreshold ? .upper : .lower
    }

    static func draw(_ form: ModuleForm, total: Int,
                     from pools: inout [String: [Question]]) -> [Question]? {
        var out = [Question]()
        for (label, n) in mix(form, total: total).sorted(by: { $0.key < $1.key }) {
            guard n > 0 else { continue }
            guard let pool = pools[label], pool.count >= n else { return nil }
            out += pool.prefix(n)
            pools[label] = Array(pool.dropFirst(n))
        }
        return out.shuffled()
    }
}

struct AdaptiveOption: Codable, Hashable {
    var moduleID: UUID
    var lower: [Question]
    var upper: [Question]

    init(moduleID: UUID, lower: [Question], upper: [Question]) {
        self.moduleID = moduleID
        self.lower = lower
        self.upper = upper
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        moduleID = try c.decodeIfPresent(UUID.self, forKey: .moduleID) ?? UUID()
        lower = try c.decodeIfPresent([Question].self, forKey: .lower) ?? []
        upper = try c.decodeIfPresent([Question].self, forKey: .upper) ?? []
    }
}
