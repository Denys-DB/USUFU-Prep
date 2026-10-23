import Foundation

enum Subject: String, Codable, CaseIterable, Hashable {
    case readingWriting
    case math

    var displayName: String {
        switch self {
        case .readingWriting: return L("Reading and Writing")
        case .math: return L("Math")
        }
    }

    var sectionLabel: String {
        switch self {
        case .readingWriting: return L("Reading and Writing")
        case .math: return L("Math")
        }
    }

    static func from(testColumn: String) -> Subject {
        let t = testColumn.lowercased()
        if t.contains("math") { return .math }
        return .readingWriting
    }
}

struct ContentBlock: Codable, Hashable {
    enum Kind: String, Codable { case text, image, table }

    var kind: Kind
    var text: String = ""
    var imageName: String = ""
    var pixelWidth: Double = 0
    var pixelHeight: Double = 0
    var pointWidth: Double = 0
    var underlines: [[Int]] = []
    var rows: [[String]] = []
    var centred: Bool = false
    var inline: [InlineParagraph] = []
    var xHeight: Double = 0

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        kind = try c.decode(Kind.self, forKey: .kind)
        text = try c.decodeIfPresent(String.self, forKey: .text) ?? ""
        imageName = try c.decodeIfPresent(String.self, forKey: .imageName) ?? ""
        pixelWidth = try c.decodeIfPresent(Double.self, forKey: .pixelWidth) ?? 0
        pixelHeight = try c.decodeIfPresent(Double.self, forKey: .pixelHeight) ?? 0
        pointWidth = try c.decodeIfPresent(Double.self, forKey: .pointWidth) ?? 0
        underlines = try c.decodeIfPresent([[Int]].self, forKey: .underlines) ?? []
        rows = try c.decodeIfPresent([[String]].self, forKey: .rows) ?? []
        centred = try c.decodeIfPresent(Bool.self, forKey: .centred) ?? false
        inline = (try? c.decodeIfPresent([InlineParagraph].self, forKey: .inline)) ?? []
        xHeight = (try? c.decodeIfPresent(Double.self, forKey: .xHeight)) ?? 0
    }

    init(kind: Kind, text: String = "", imageName: String = "",
         pixelWidth: Double = 0, pixelHeight: Double = 0, pointWidth: Double = 0,
         underlines: [[Int]] = [], rows: [[String]] = [], centred: Bool = false,
         inline: [InlineParagraph] = [], xHeight: Double = 0) {
        self.kind = kind
        self.text = text
        self.imageName = imageName
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
        self.pointWidth = pointWidth
        self.underlines = underlines
        self.rows = rows
        self.centred = centred
        self.inline = inline
        self.xHeight = xHeight
    }

    var hasWords: Bool {
        kind == .image && inline.contains { p in
            p.runs.contains { !($0.text ?? "").trimmingCharacters(in: .whitespaces).isEmpty }
        }
    }

    var inlineImages: [String] {
        Array(Set(inline.flatMap { $0.runs.compactMap(\.image) })).sorted()
    }

    static func text(_ s: String) -> ContentBlock { ContentBlock(kind: .text, text: s) }

    static func table(_ rows: [[String]]) -> ContentBlock {
        ContentBlock(kind: .table, rows: rows)
    }

    static func text(_ s: String, underlines: [Range<Int>]) -> ContentBlock {
        ContentBlock(kind: .text, text: s,
                     underlines: underlines.map { [$0.lowerBound, $0.upperBound] })
    }

    var underlineRanges: [Range<Int>] {
        let n = text.count
        return underlines.compactMap { pair in
            guard pair.count == 2 else { return nil }
            let lo = max(0, min(pair[0], n)), hi = max(0, min(pair[1], n))
            return hi > lo ? lo..<hi : nil
        }
    }

    var attributed: AttributedString {
        var s = AttributedString(text)
        guard !underlines.isEmpty else { return s }
        let n = s.characters.count
        for range in underlineRanges where range.upperBound <= n {
            let lo = s.index(s.startIndex, offsetByCharacters: range.lowerBound)
            let hi = s.index(s.startIndex, offsetByCharacters: range.upperBound)
            guard lo < hi else { continue }
            s[lo..<hi].underlineStyle = .single
        }
        return s
    }

    var isEmpty: Bool {
        switch kind {
        case .text: return text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .image: return imageName.isEmpty
        case .table: return rows.isEmpty
        }
    }
}

struct InlineParagraph: Codable, Hashable {
    var display: Bool
    var runs: [InlineRun]
}

struct InlineRun: Codable, Hashable {
    var text: String?
    var image: String?
    var x = 0, y = 0, w = 0, h = 0
    var width = 0.0, height = 0.0, depth = 0.0

    init(text: String) { self.text = text }
    init(image: String, x: Int, y: Int, w: Int, h: Int,
         width: Double, height: Double, depth: Double) {
        self.image = image
        self.x = x; self.y = y; self.w = w; self.h = h
        self.width = width; self.height = height; self.depth = depth
    }

    enum CodingKeys: String, CodingKey { case text, image, x, y, w, h, width, height, depth }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        if let t = try c.decodeIfPresent(String.self, forKey: .text) {
            text = t
            return
        }
        image = try c.decode(String.self, forKey: .image)
        x = try c.decode(Int.self, forKey: .x)
        y = try c.decode(Int.self, forKey: .y)
        w = try c.decode(Int.self, forKey: .w)
        h = try c.decode(Int.self, forKey: .h)
        width = try c.decode(Double.self, forKey: .width)
        height = try c.decode(Double.self, forKey: .height)
        depth = try c.decode(Double.self, forKey: .depth)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        if let text {
            try c.encode(text, forKey: .text)
            return
        }
        try c.encode(image ?? "", forKey: .image)
        try c.encode(x, forKey: .x); try c.encode(y, forKey: .y)
        try c.encode(w, forKey: .w); try c.encode(h, forKey: .h)
        try c.encode(width, forKey: .width); try c.encode(height, forKey: .height)
        try c.encode(depth, forKey: .depth)
    }
}

struct Choice: Codable, Hashable, Identifiable {
    var letter: String
    var blocks: [ContentBlock]
    var id: String { letter }

    var plainText: String {
        blocks.filter { $0.kind == .text }.map(\.text).joined(separator: " ")
    }
}

enum DoubleLayout: String, Codable, CaseIterable {
    case turns
    case sideBySide = "side_by_side"

    var title: String {
        switch self {
        case .turns: return L("Turn about")
        case .sideBySide: return L("Side by side")
        }
    }

    var detail: String {
        switch self {
        case .turns:
            return L("One question on the screen at a time. You answer the "
                     + "first, they answer the second. You both see every "
                     + "question, and you can highlight and take notes.")
        case .sideBySide:
            return L("The screen is split in two and you both work at the same "
                     + "time, each on your own half of the questions. Faster, "
                     + "and nobody is waiting — but each of you has half the "
                     + "screen, and there are no highlights or notes in this "
                     + "one.")
        }
    }
}

enum QuestionKind: String, Codable {
    case multipleChoice
    case studentResponse
}

struct Question: Codable, Hashable, Identifiable {
    var id: String
    var subject: Subject
    var assessment: String
    var test: String
    var domain: String
    var skill: String
    var difficulty: String
    var kind: QuestionKind

    var stimulus: [ContentBlock]
    var prompt: [ContentBlock]
    var choices: [Choice]
    var correctAnswer: String
    var rationale: [ContentBlock]

    var sourceName: String = ""

    var difficultyRank: Int {
        switch difficulty.lowercased() {
        case "easy": return 0
        case "medium": return 1
        case "hard": return 2
        default: return 1
        }
    }

    var acceptedAnswers: [String] {
        correctAnswer
            .components(separatedBy: CharacterSet(charactersIn: ",;"))
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }
}

enum AnnotationField: String, Codable, Hashable {
    case stimulus
    case prompt
}

extension KeyedDecodingContainer {
    func decodeAnyID(forKey key: Key) -> UUID {
        guard let text = (try? decodeIfPresent(String.self, forKey: key)) ?? nil else { return UUID() }
        if let id = UUID(uuidString: text) { return id }
        let hex = Array(text)
        guard hex.count == 32, hex.allSatisfy(\.isHexDigit) else { return UUID() }
        let dashed = [0..<8, 8..<12, 12..<16, 16..<20, 20..<32].map { String(hex[$0]) }
            .joined(separator: "-")
        return UUID(uuidString: dashed) ?? UUID()
    }
}

extension Question {
    func blocks(_ field: AnnotationField) -> [ContentBlock] {
        field == .stimulus ? stimulus : prompt
    }
}

struct Annotation: Codable, Hashable, Identifiable {
    var id: UUID = UUID()
    var questionID: String
    var field: AnnotationField
    var blockIndex: Int
    var start: Int
    var end: Int
    var note: String = ""
    var colorIndex: Int = 0
    var marked: String? = nil

    var range: Range<Int> { start..<max(start, end) }
    var hasNote: Bool { !note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = c.decodeAnyID(forKey: .id)
        questionID = try c.decode(String.self, forKey: .questionID)
        field = try c.decodeIfPresent(AnnotationField.self, forKey: .field) ?? .stimulus
        blockIndex = try c.decodeIfPresent(Int.self, forKey: .blockIndex) ?? 0
        start = try c.decodeIfPresent(Int.self, forKey: .start) ?? 0
        end = try c.decodeIfPresent(Int.self, forKey: .end) ?? 0
        note = try c.decodeIfPresent(String.self, forKey: .note) ?? ""
        colorIndex = try c.decodeIfPresent(Int.self, forKey: .colorIndex) ?? 0
        marked = try c.decodeIfPresent(String.self, forKey: .marked)
    }

    init(questionID: String, field: AnnotationField, blockIndex: Int,
         start: Int, end: Int, note: String = "", colorIndex: Int = 0) {
        self.questionID = questionID
        self.field = field
        self.blockIndex = blockIndex
        self.start = start
        self.end = end
        self.note = note
        self.colorIndex = colorIndex
    }
}

enum AnswerChecker {
    static func isCorrect(question: Question, response: String) -> Bool {
        let given = response.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !given.isEmpty else { return false }

        if question.kind == .multipleChoice {
            return given.uppercased() == question.correctAnswer
                .trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        }

        let accepted = question.acceptedAnswers
        if accepted.contains(where: { matches(given, $0) }) { return true }

        let parts = given.components(separatedBy: CharacterSet(charactersIn: ",;"))
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        guard parts.count > 1 else { return false }
        return parts.allSatisfy { part in accepted.contains { matches(part, $0) } }
    }

    private static func matches(_ given: String, _ accepted: String) -> Bool {
        if normalize(given) == normalize(accepted) { return true }
        if let a = numericValue(given), let b = numericValue(accepted),
           abs(a - b) <= max(1e-6, abs(b) * 1e-6) { return true }
        return false
    }

    private static func normalize(_ s: String) -> String {
        s.lowercased()
            .replacingOccurrences(of: ",", with: "")
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "$", with: "")
            .replacingOccurrences(of: "%", with: "")
    }

    static func numericValue(_ s: String) -> Double? {
        let t = normalize(s)
        guard !t.isEmpty else { return nil }
        if t.contains("/") {
            let parts = t.components(separatedBy: "/")
            guard parts.count == 2,
                  let n = Double(parts[0]), let d = Double(parts[1]), d != 0 else { return nil }
            return n / d
        }
        return Double(t)
    }
}

enum LabelCase {
    static func key(_ label: String) -> String { label.lowercased() }

    static func canonical(of values: [String]) -> [String: String]? {
        var spellings = [String: [String: Int]]()
        for v in values where !v.isEmpty {
            spellings[key(v), default: [:]][v, default: 0] += 1
        }
        guard spellings.contains(where: { $0.value.count > 1 }) else { return nil }
        return spellings.compactMapValues { forms in
            forms.max { a, b in
                a.value != b.value ? a.value < b.value : a.key > b.key
            }?.key
        }
    }
}

struct Bank: Codable, Identifiable, Hashable {
    var id: String
    var name: String
    var createdAt: Date
    var questions: [Question]
    var parserVersion: Int = 0

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        questions = Bank.unified(
            try c.decodeIfPresent([Question].self, forKey: .questions) ?? [])
        parserVersion = try c.decodeIfPresent(Int.self, forKey: .parserVersion) ?? 0
    }

    init(id: String, name: String, createdAt: Date, questions: [Question],
         parserVersion: Int = QuestionParser.version) {
        self.id = id
        self.name = name
        self.createdAt = createdAt
        self.questions = Bank.unified(questions)
        self.parserVersion = parserVersion
    }

    static func unified(_ questions: [Question]) -> [Question] {
        let skills = LabelCase.canonical(of: questions.map(\.skill))
        let domains = LabelCase.canonical(of: questions.map(\.domain))
        let difficulties = LabelCase.canonical(of: questions.map(\.difficulty))
        let assessments = LabelCase.canonical(of: questions.map(\.assessment))
        guard skills != nil || domains != nil
                || difficulties != nil || assessments != nil else { return questions }
        return questions.map { q in
            var q = q
            if let one = skills?[LabelCase.key(q.skill)] { q.skill = one }
            if let one = domains?[LabelCase.key(q.domain)] { q.domain = one }
            if let one = difficulties?[LabelCase.key(q.difficulty)] { q.difficulty = one }
            if let one = assessments?[LabelCase.key(q.assessment)] { q.assessment = one }
            return q
        }
    }

    var mathCount: Int { questions.filter { $0.subject == .math }.count }
    var readingCount: Int { questions.filter { $0.subject == .readingWriting }.count }

    struct Tally: Identifiable, Hashable {
        var label: String
        var count: Int
        var id: String { label }
    }

    private func tally(_ key: KeyPath<Question, String>,
                       in subjects: Set<Subject>) -> [Tally] {
        var counts = [String: Int]()
        for q in questions where subjects.contains(q.subject) && !q[keyPath: key].isEmpty {
            counts[q[keyPath: key], default: 0] += 1
        }
        return counts.map { Tally(label: $0.key, count: $0.value) }
            .sorted { $0.label < $1.label }
    }

    func difficulties(in subjects: Set<Subject> = Set(Subject.allCases)) -> [Tally] {
        let order = ["Easy": 0, "Medium": 1, "Hard": 2]
        return tally(\.difficulty, in: subjects)
            .sorted { (order[$0.label] ?? 9, $0.label) < (order[$1.label] ?? 9, $1.label) }
    }
    func assessments(in subjects: Set<Subject> = Set(Subject.allCases)) -> [Tally] {
        tally(\.assessment, in: subjects)
    }
    func domains(in subjects: Set<Subject> = Set(Subject.allCases)) -> [Tally] {
        tally(\.domain, in: subjects)
    }
    func skills(in subjects: Set<Subject> = Set(Subject.allCases)) -> [Tally] {
        tally(\.skill, in: subjects)
    }
}

enum Pace {
    static let readingWritingSeconds: Double = 32 * 60 / 27
    static let mathSeconds: Double = 35 * 60 / 22

    static func seconds(for subject: Subject) -> Double {
        subject == .math ? mathSeconds : readingWritingSeconds
    }

    static func minutes(readingWriting: Int, math: Int) -> Int {
        let seconds = Double(readingWriting) * readingWritingSeconds
            + Double(math) * mathSeconds
        return max(1, Int((seconds / 60).rounded()))
    }

    static func describe(seconds: Double) -> String {
        let s = Int(seconds.rounded())
        return s < 60 ? "\(s)s" : String(format: "%d:%02d", s / 60, s % 60)
    }
}

enum GradingMode: String, Codable, CaseIterable {
    case atEnd
    case immediate

    var title: String {
        switch self {
        case .atEnd: return L("Grade at the end")
        case .immediate: return L("Grade each question")
        }
    }
    var detail: String {
        switch self {
        case .atEnd: return L("Feels like the real test. You see all results after you submit.")
        case .immediate: return L("Shows the answer and explanation right after you answer.")
        }
    }
}

enum MixMode: String, Codable, CaseIterable {
    case pdfOrder
    case sequential
    case shuffledInSection
    case mixed

    var title: String {
        switch self {
        case .pdfOrder: return L("PDF order")
        case .sequential: return L("One section after the other")
        case .shuffledInSection: return L("Shuffled inside each section")
        case .mixed: return L("Mixed together")
        }
    }
    var detail: String {
        switch self {
        case .pdfOrder: return L("Keep the order the questions came in.")
        case .sequential: return L("All Reading and Writing, then all Math, in file order.")
        case .shuffledInSection:
            return L("Reading and Writing first, then Math, but shuffled within each.")
        case .mixed: return L("Shuffle both sections together.")
        }
    }
}

enum SelectionMode: String, Codable, CaseIterable {
    case newFirst
    case unseenOnly
    case dueForReview
    case weakestSkills
    case reviewMissed
    case setAside
    case all

    var title: String {
        switch self {
        case .newFirst: return L("Continue where I left off")
        case .unseenOnly: return L("Only questions I have never seen")
        case .dueForReview: return L("Due for review")
        case .weakestSkills: return L("Drill my weakest skills")
        case .reviewMissed: return L("Review my missed questions")
        case .setAside: return L("Questions I set aside")
        case .all: return L("Everything in the bank")
        }
    }
    var detail: String {
        switch self {
        case .newFirst: return L("Unseen questions first, then ones you got wrong.")
        case .unseenOnly:
            return L("Completely fresh ones, skipping anything you set aside.")
        case .dueForReview:
            return L("Spaced practice: questions come back a day after you get one "
                     + "wrong, and at widening gaps while you keep getting it right.")
        case .weakestSkills:
            return L("Drawn from the skills you are scoring lowest on, worst first.")
        case .reviewMissed: return L("Only questions you have answered incorrectly before.")
        case .setAside: return L("The ones you kept back to look at later.")
        case .all: return L("Draw from the whole bank, seen or not.")
        }
    }

    var isDerived: Bool { self == .dueForReview || self == .weakestSkills }
}

enum ReviewSchedule {
    static let days: [Double] = [1, 3, 7, 16, 35]

    static func interval(timesCorrect: Int, lastCorrect: Bool) -> TimeInterval {
        let rung = lastCorrect ? min(max(timesCorrect, 1), days.count) : 1
        return days[rung - 1] * 24 * 60 * 60
    }

    static func isDue(timesSeen: Int, timesCorrect: Int, lastSeen: Date?,
                      lastCorrect: Bool, now: Date = Date()) -> Bool {
        guard timesSeen > 0, let last = lastSeen else { return false }
        return now.timeIntervalSince(last)
            >= interval(timesCorrect: timesCorrect, lastCorrect: lastCorrect)
    }

    static func isDue(_ p: QuestionProgress, now: Date = Date()) -> Bool {
        isDue(timesSeen: p.timesSeen, timesCorrect: p.timesCorrect,
              lastSeen: p.lastSeen, lastCorrect: p.lastCorrect, now: now)
    }

    static func overdueBy(_ p: QuestionProgress, now: Date = Date()) -> TimeInterval {
        guard let last = p.lastSeen else { return 0 }
        return now.timeIntervalSince(last)
            - interval(timesCorrect: p.timesCorrect, lastCorrect: p.lastCorrect)
    }

    static func nextDue(_ records: [QuestionProgress], now: Date = Date()) -> Date? {
        records.compactMap { p -> Date? in
            guard p.timesSeen > 0, let last = p.lastSeen else { return nil }
            return last.addingTimeInterval(interval(timesCorrect: p.timesCorrect,
                                                    lastCorrect: p.lastCorrect))
        }
        .filter { $0 > now }
        .min()
    }
}

struct StudyConfig: Codable, Equatable {
    var bankID: String = ""
    var timed: Bool = false
    var minutes: Int = 32
    var grading: GradingMode = .atEnd
    var mix: MixMode = .pdfOrder
    var selection: SelectionMode = .newFirst
    var questionCount: Int = 20
    var subjects: Set<Subject> = [.readingWriting, .math]
    var difficulties: Set<String> = []
    var assessments: Set<String> = []
    var domains: Set<String> = []
    var skills: Set<String> = []
    var sittingName: String = ""
    var fullTest: Bool = false
    var adaptive: Bool = false
    var partnerProfileID: String = ""

    var doubleLayout: DoubleLayout = .turns

    var isDouble: Bool { !partnerProfileID.isEmpty }

    var sectionCounts: [String: Int] = [:]

    private var skillFilter: String? = nil

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        bankID = try c.decodeIfPresent(String.self, forKey: .bankID) ?? ""
        timed = try c.decodeIfPresent(Bool.self, forKey: .timed) ?? false
        minutes = try c.decodeIfPresent(Int.self, forKey: .minutes) ?? 32
        grading = try c.decodeIfPresent(GradingMode.self, forKey: .grading) ?? .atEnd
        selection = (try? c.decodeIfPresent(SelectionMode.self, forKey: .selection))
            .flatMap { $0 } ?? .newFirst
        mix = (try? c.decodeIfPresent(MixMode.self, forKey: .mix)).flatMap { $0 } ?? .pdfOrder
        questionCount = try c.decodeIfPresent(Int.self, forKey: .questionCount) ?? 20
        subjects = try c.decodeIfPresent(Set<Subject>.self, forKey: .subjects)
            ?? [.readingWriting, .math]
        difficulties = try c.decodeIfPresent(Set<String>.self, forKey: .difficulties) ?? []
        assessments = try c.decodeIfPresent(Set<String>.self, forKey: .assessments) ?? []
        domains = try c.decodeIfPresent(Set<String>.self, forKey: .domains) ?? []
        skills = try c.decodeIfPresent(Set<String>.self, forKey: .skills) ?? []
        sittingName = try c.decodeIfPresent(String.self, forKey: .sittingName) ?? ""
        fullTest = try c.decodeIfPresent(Bool.self, forKey: .fullTest) ?? false
        adaptive = try c.decodeIfPresent(Bool.self, forKey: .adaptive) ?? false
        sectionCounts = try c.decodeIfPresent([String: Int].self, forKey: .sectionCounts) ?? [:]
        partnerProfileID = try c.decodeIfPresent(String.self, forKey: .partnerProfileID) ?? ""
        doubleLayout = (try? c.decodeIfPresent(DoubleLayout.self, forKey: .doubleLayout))
            .flatMap { $0 } ?? .turns
        if skills.isEmpty,
           let one = try c.decodeIfPresent(String.self, forKey: .skillFilter), !one.isEmpty {
            skills = [one]
        }
    }

    var hasFilters: Bool {
        !difficulties.isEmpty || !domains.isEmpty || !skills.isEmpty || !assessments.isEmpty
    }

    var hasSectionSplit: Bool { subjects.count > 1 && !sectionCounts.isEmpty }

    func count(for subject: Subject) -> Int { sectionCounts[subject.rawValue] ?? 0 }

    mutating func setCount(_ n: Int, for subject: Subject) {
        sectionCounts[subject.rawValue] = max(0, n)
        questionCount = max(1, sectionCounts.values.reduce(0, +))
    }

    mutating func clearSectionSplit() {
        sectionCounts = [:]
    }

    mutating func clearFilters() {
        difficulties = []
        assessments = []
        domains = []
        skills = []
    }

    mutating func trim(to bank: Bank) {
        skills = Self.respell(skills, to: bank.questions.map(\.skill))
        domains = Self.respell(domains, to: bank.questions.map(\.domain))
        difficulties = Self.respell(difficulties, to: bank.questions.map(\.difficulty))
        assessments = Self.respell(assessments, to: bank.questions.map(\.assessment))
        skills.formIntersection(Set(bank.questions.map(\.skill)))
        domains.formIntersection(Set(bank.questions.map(\.domain)))
        difficulties.formIntersection(Set(bank.questions.map(\.difficulty)))
        assessments.formIntersection(Set(bank.questions.map(\.assessment)))
        let present = Set(bank.questions.map(\.subject))
        subjects.formIntersection(present)
        if subjects.isEmpty { subjects = present.isEmpty ? [.readingWriting, .math] : present }
    }

    private static func respell(_ chosen: Set<String>, to present: [String]) -> Set<String> {
        guard !chosen.isEmpty else { return chosen }
        var byKey = [String: String]()
        for label in present where !label.isEmpty { byKey[LabelCase.key(label)] = label }
        return Set(chosen.map { byKey[LabelCase.key($0)] ?? $0 })
    }
}

struct StudyPreset: Codable, Identifiable, Hashable {
    var id: UUID = UUID()
    var name: String
    var config: StudyConfig
    var createdAt: Date = Date()

    static func == (a: StudyPreset, b: StudyPreset) -> Bool { a.id == b.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }

    init(name: String, config: StudyConfig) {
        self.name = name
        self.config = config
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = c.decodeAnyID(forKey: .id)
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? "Saved plan"
        config = try c.decodeIfPresent(StudyConfig.self, forKey: .config) ?? StudyConfig()
        createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
    }
}

struct AppSettings: Codable, Equatable {
    var dailyGoal: Int = 20
    var appearance: Appearance = .system
    var language: Language = Language.systemDefault
    var reduceMotion: Bool = false
    var schedule = StudySchedule()
    var flashcardSeconds: Double = 5
    var flashcardTextScale: Double = 1
    var flashcardFlipAnimation: Bool = true
    var trackSkippedCards: Bool = true
    var vocabDaily = DailyPlan()

    var showLearnInSidebar = true
    var showImportButton = true
    var showQuestionStreak = true
    var showVocabularyStreak = true
    var showDoubleMode = true
    var showBackupCard = true
    var showParentSummary = true

    var stealthMode = false

    var excusedDays: [Date] = []
    var welcomeBackFor: Date? = nil
    var restoreOfferedFor: Date? = nil

    var lastBackupAt: Date? = nil
    var backupNudgeFor: Date? = nil

    var showQuestionSets: Bool = true
    var showFlashcards: Bool = true

    var libraryPaneHeight: Double? = nil

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        dailyGoal = try c.decodeIfPresent(Int.self, forKey: .dailyGoal) ?? 20
        schedule = try c.decodeIfPresent(StudySchedule.self, forKey: .schedule)
            ?? { var s = StudySchedule(); s.dailyTarget = dailyGoal; return s }()
        appearance = (try? c.decodeIfPresent(Appearance.self, forKey: .appearance))
            .flatMap { $0 } ?? .system
        reduceMotion = try c.decodeIfPresent(Bool.self, forKey: .reduceMotion) ?? false
        flashcardSeconds = try c.decodeIfPresent(Double.self, forKey: .flashcardSeconds) ?? 5
        flashcardTextScale = try c.decodeIfPresent(Double.self, forKey: .flashcardTextScale) ?? 1
        flashcardFlipAnimation =
            try c.decodeIfPresent(Bool.self, forKey: .flashcardFlipAnimation) ?? true
        trackSkippedCards = try c.decodeIfPresent(Bool.self, forKey: .trackSkippedCards) ?? true
        vocabDaily = try c.decodeIfPresent(DailyPlan.self, forKey: .vocabDaily) ?? DailyPlan()
        language = (try? c.decodeIfPresent(Language.self, forKey: .language))
            .flatMap { $0 } ?? Language.systemDefault
        showLearnInSidebar = try c.decodeIfPresent(Bool.self, forKey: .showLearnInSidebar) ?? true
        showImportButton = try c.decodeIfPresent(Bool.self, forKey: .showImportButton) ?? true
        showQuestionStreak = try c.decodeIfPresent(Bool.self, forKey: .showQuestionStreak) ?? true
        showVocabularyStreak =
            try c.decodeIfPresent(Bool.self, forKey: .showVocabularyStreak) ?? true
        showDoubleMode = try c.decodeIfPresent(Bool.self, forKey: .showDoubleMode) ?? true
        showBackupCard = try c.decodeIfPresent(Bool.self, forKey: .showBackupCard) ?? true
        showParentSummary =
            try c.decodeIfPresent(Bool.self, forKey: .showParentSummary) ?? true
        stealthMode = try c.decodeIfPresent(Bool.self, forKey: .stealthMode) ?? false
        excusedDays = (try? c.decodeIfPresent([Date].self, forKey: .excusedDays))
            .flatMap { $0 } ?? []
        welcomeBackFor = (try? c.decodeIfPresent(Date.self, forKey: .welcomeBackFor))
            .flatMap { $0 }
        restoreOfferedFor = (try? c.decodeIfPresent(Date.self, forKey: .restoreOfferedFor))
            .flatMap { $0 }
        lastBackupAt = (try? c.decodeIfPresent(Date.self, forKey: .lastBackupAt))
            .flatMap { $0 }
        backupNudgeFor = (try? c.decodeIfPresent(Date.self, forKey: .backupNudgeFor))
            .flatMap { $0 }
        libraryPaneHeight =
            (try? c.decodeIfPresent(Double.self, forKey: .libraryPaneHeight)).flatMap { $0 }
        showQuestionSets = try c.decodeIfPresent(Bool.self, forKey: .showQuestionSets) ?? true
        showFlashcards = try c.decodeIfPresent(Bool.self, forKey: .showFlashcards) ?? true
    }
}

struct PracticeRhythm: Equatable {
    var answeredToday = 0
    var streak = 0
    var bestStreak = 0
    var answeredThisWeek = 0
}

enum ExamTimer {
    static let warningSeconds: Double = 300

    static func shouldWarn(secondsRemaining: Double, alreadyWarned: Bool,
                           totalSeconds: Double? = nil) -> Bool {
        if let totalSeconds, totalSeconds <= warningSeconds { return false }
        return secondsRemaining <= warningSeconds && !alreadyWarned
    }
}

struct Attempt: Codable, Hashable {
    var questionID: String
    var response: String = ""
    var markedForReview: Bool = false
    var eliminated: Set<String> = []
    var revealed: Bool = false
    var secondsSpent: Double = 0

    var isAnswered: Bool { !response.trimmingCharacters(in: .whitespaces).isEmpty }
}

struct Session: Codable, Identifiable {
    var id: String = UUID().uuidString
    var bankID: String
    var bankName: String
    var config: StudyConfig
    var questions: [Question]
    var attempts: [Attempt]
    var currentIndex: Int = 0
    var startedAt: Date = Date()
    var lastSavedAt: Date = Date()
    var finishedAt: Date? = nil
    var secondsRemaining: Double = 0
    var modules: [ExamModule] = []
    var onBreak: Bool = false
    var breakRemaining: Double = 0
    var adaptive: [AdaptiveOption] = []

    var partnerID: String = ""
    var turnNames: [String] = []
    var turnAccents: [Int] = []
    var partnerIndex: Int = 1

    var seatsFinished: [Int] = []

    func turn(at index: Int) -> Int { index % 2 }

    var isDouble: Bool { !partnerID.isEmpty && turnNames.count == 2 }

    var isSideBySide: Bool { isDouble && config.doubleLayout == .sideBySide }

    func positions(for seat: Int) -> [Int] {
        questions.indices.filter { turn(at: $0) == seat }
    }

    func index(for seat: Int) -> Int { seat == 0 ? currentIndex : partnerIndex }

    func isFinished(seat: Int) -> Bool { seatsFinished.contains(seat) }

    var bothSeatsFinished: Bool {
        isDouble && isFinished(seat: 0) && isFinished(seat: 1)
    }

    func turnName(at index: Int) -> String {
        let i = turn(at: index)
        return turnNames.indices.contains(i) ? turnNames[i] : ""
    }

    var doubleScores: [(name: String, correct: Int, answered: Int)] {
        guard isDouble else { return [] }
        return (0..<2).map { seat in
            var correct = 0, answered = 0
            for (i, attempt) in attempts.enumerated() where turn(at: i) == seat {
                guard attempt.isAnswered, questions.indices.contains(i) else { continue }
                answered += 1
                if AnswerChecker.isCorrect(question: questions[i], response: attempt.response) {
                    correct += 1
                }
            }
            return (turnNames.indices.contains(seat) ? turnNames[seat] : "", correct, answered)
        }
    }

    init(id: String = UUID().uuidString, bankID: String, bankName: String,
         config: StudyConfig, questions: [Question], attempts: [Attempt],
         currentIndex: Int = 0, modules: [ExamModule] = []) {
        self.id = id
        self.bankID = bankID
        self.bankName = bankName
        self.config = config
        self.questions = questions
        self.attempts = attempts
        self.currentIndex = currentIndex
        self.modules = modules
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
        bankID = try c.decode(String.self, forKey: .bankID)
        bankName = try c.decodeIfPresent(String.self, forKey: .bankName) ?? ""
        config = try c.decodeIfPresent(StudyConfig.self, forKey: .config) ?? StudyConfig()
        questions = try c.decodeIfPresent([Question].self, forKey: .questions) ?? []
        attempts = try c.decodeIfPresent([Attempt].self, forKey: .attempts) ?? []
        currentIndex = try c.decodeIfPresent(Int.self, forKey: .currentIndex) ?? 0
        startedAt = try c.decodeIfPresent(Date.self, forKey: .startedAt) ?? Date()
        lastSavedAt = try c.decodeIfPresent(Date.self, forKey: .lastSavedAt) ?? startedAt
        finishedAt = try c.decodeIfPresent(Date.self, forKey: .finishedAt)
        secondsRemaining = try c.decodeIfPresent(Double.self, forKey: .secondsRemaining) ?? 0
        modules = try c.decodeIfPresent([ExamModule].self, forKey: .modules) ?? []
        onBreak = try c.decodeIfPresent(Bool.self, forKey: .onBreak) ?? false
        breakRemaining = try c.decodeIfPresent(Double.self, forKey: .breakRemaining) ?? 0
        adaptive = try c.decodeIfPresent([AdaptiveOption].self, forKey: .adaptive) ?? []
        partnerID = try c.decodeIfPresent(String.self, forKey: .partnerID) ?? ""
        turnNames = try c.decodeIfPresent([String].self, forKey: .turnNames) ?? []
        turnAccents = try c.decodeIfPresent([Int].self, forKey: .turnAccents) ?? []
        partnerIndex = try c.decodeIfPresent(Int.self, forKey: .partnerIndex) ?? 1
        seatsFinished = try c.decodeIfPresent([Int].self, forKey: .seatsFinished) ?? []
        let last = max(0, questions.count - 1)
        if currentIndex < 0 || currentIndex > last {
            if currentIndex > last, !seatsFinished.contains(0) { seatsFinished.append(0) }
            currentIndex = min(max(0, currentIndex), last)
        }
        if partnerIndex < 0 || partnerIndex > last {
            if partnerIndex > last, !seatsFinished.contains(1) { seatsFinished.append(1) }
            partnerIndex = min(max(0, partnerIndex), last)
        }
    }

    var isFinished: Bool { finishedAt != nil }

    func attempt(at i: Int) -> Attempt {
        i >= 0 && i < attempts.count ? attempts[i] : Attempt(questionID: "")
    }

    var correctCount: Int {
        zip(questions, attempts).filter { AnswerChecker.isCorrect(question: $0.0, response: $0.1.response) }.count
    }
    var answeredCount: Int { attempts.filter(\.isAnswered).count }

    var missedQuestions: [Question] {
        zip(questions, attempts)
            .filter { $0.1.isAnswered
                && !AnswerChecker.isCorrect(question: $0.0, response: $0.1.response) }
            .map(\.0)
    }

    var unansweredQuestions: [Question] {
        zip(questions, attempts).filter { !$0.1.isAnswered }.map(\.0)
    }
}

struct QuestionProgress: Codable {
    var questionID: String
    var timesSeen: Int = 0
    var timesCorrect: Int = 0
    var lastSeen: Date? = nil
    var lastCorrect: Bool = false

    var isMastered: Bool { lastCorrect && timesCorrect >= 2 }
}

struct AttemptRecord: Codable, Hashable, Identifiable {
    var id: UUID = UUID()
    var questionID: String
    var correct: Bool
    var at: Date
    var secondsSpent: Double = 0
    var skill: String = ""
    var domain: String = ""
    var difficulty: String = ""
    var subject: Subject = .readingWriting
    var backfilled: Bool = false

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        questionID = try c.decode(String.self, forKey: .questionID)
        correct = try c.decodeIfPresent(Bool.self, forKey: .correct) ?? false
        at = try c.decodeIfPresent(Date.self, forKey: .at) ?? Date()
        secondsSpent = try c.decodeIfPresent(Double.self, forKey: .secondsSpent) ?? 0
        skill = try c.decodeIfPresent(String.self, forKey: .skill) ?? ""
        domain = try c.decodeIfPresent(String.self, forKey: .domain) ?? ""
        difficulty = try c.decodeIfPresent(String.self, forKey: .difficulty) ?? ""
        subject = try c.decodeIfPresent(Subject.self, forKey: .subject) ?? .readingWriting
        backfilled = try c.decodeIfPresent(Bool.self, forKey: .backfilled) ?? false
    }

    init(question: Question, correct: Bool, at: Date, secondsSpent: Double,
         backfilled: Bool = false) {
        self.backfilled = backfilled
        self.questionID = question.id
        self.correct = correct
        self.at = at
        self.secondsSpent = secondsSpent
        self.skill = question.skill
        self.domain = question.domain
        self.difficulty = question.difficulty
        self.subject = question.subject
    }
}

struct BankProgress: Codable {
    var bankID: String
    var records: [String: QuestionProgress] = [:]
    var setAside: Set<String> = []
    var history: [AttemptRecord] = []
    var historyCleared = false

    mutating func record(questionID: String, correct: Bool) {
        var r = records[questionID] ?? QuestionProgress(questionID: questionID)
        r.timesSeen += 1
        if correct { r.timesCorrect += 1 }
        r.lastCorrect = correct
        r.lastSeen = Date()
        records[questionID] = r
    }

    func seen(_ id: String) -> Bool { records[id]?.timesSeen ?? 0 > 0 }
    func lastWrong(_ id: String) -> Bool {
        guard let r = records[id], r.timesSeen > 0 else { return false }
        return !r.lastCorrect
    }
    var masteredCount: Int { records.values.filter(\.isMastered).count }
    var seenCount: Int { records.values.filter { $0.timesSeen > 0 }.count }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        bankID = try c.decode(String.self, forKey: .bankID)
        records = try c.decodeIfPresent([String: QuestionProgress].self, forKey: .records) ?? [:]
        setAside = try c.decodeIfPresent(Set<String>.self, forKey: .setAside) ?? []
        history = try c.decodeIfPresent([AttemptRecord].self, forKey: .history) ?? []
        historyCleared = try c.decodeIfPresent(Bool.self, forKey: .historyCleared) ?? false
    }

    init(bankID: String, records: [String: QuestionProgress] = [:],
         setAside: Set<String> = [], history: [AttemptRecord] = []) {
        self.bankID = bankID
        self.records = records
        self.setAside = setAside
        self.history = history
    }

    func isSetAside(_ id: String) -> Bool { setAside.contains(id) }
    mutating func toggleSetAside(_ id: String) {
        if setAside.contains(id) { setAside.remove(id) } else { setAside.insert(id) }
    }
}
