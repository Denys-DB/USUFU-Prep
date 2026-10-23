import Foundation

struct Breakdown: Identifiable, Hashable {
    var label: String
    var attempts: Int
    var correct: Int
    var available: Int = 0
    var seen: Int = 0
    var averageSeconds: Double = 0

    var id: String { label }
    var accuracy: Double { attempts == 0 ? 0 : Double(correct) / Double(attempts) }
    var coverage: Double { available == 0 ? 0 : Double(seen) / Double(available) }

    static let confidentAt = 5
    var isConfident: Bool { attempts >= Self.confidentAt }
}

struct TrendPoint: Identifiable, Hashable {
    var index: Int
    var date: Date
    var attempts: Int
    var correct: Int

    var id: Int { index }
    var accuracy: Double { attempts == 0 ? 0 : Double(correct) / Double(attempts) }
}

struct StatisticsFilter: Equatable {
    var subjects: Set<Subject>? = nil
    var domain: String? = nil
    var skill: String? = nil

    static let everything = StatisticsFilter()
    var narrowsAnything: Bool { subjects != nil || domain != nil || skill != nil }

    func admits(subject: Subject, domain: String, skill: String) -> Bool {
        if let subjects, !subjects.contains(subject) { return false }
        if let want = self.domain, LabelCase.key(want) != LabelCase.key(domain) { return false }
        if let want = self.skill, LabelCase.key(want) != LabelCase.key(skill) { return false }
        return true
    }
}

struct Statistics {
    var totalAttempts = 0
    var totalCorrect = 0
    var questionsSeen = 0
    var questionsAvailable = 0
    var bySkill: [Breakdown] = []
    var byDomain: [Breakdown] = []
    var byDifficulty: [Breakdown] = []
    var bySection: [Breakdown] = []
    var trend: [TrendPoint] = []
    var medianSeconds: Double = 0

    var accuracy: Double { totalAttempts == 0 ? 0 : Double(totalCorrect) / Double(totalAttempts) }
    var hasData: Bool { totalAttempts > 0 }

    var weakest: [Breakdown] {
        bySkill.filter(\.isConfident).sorted { $0.accuracy < $1.accuracy }
    }

    var untested: [Breakdown] {
        bySkill.filter { !$0.isConfident && $0.available > 0 }
            .sorted { $0.attempts < $1.attempts }
    }
}

enum StatisticsBuilder {
    private static let difficultyOrder = ["Easy": 0, "Medium": 1, "Hard": 2]

    static func build(history: [AttemptRecord], bank: Bank,
                      subjects: Set<Subject>? = nil) -> Statistics {
        build(history: history, bank: bank, filter: StatisticsFilter(subjects: subjects))
    }

    static func build(history: [AttemptRecord], bank: Bank,
                      filter: StatisticsFilter) -> Statistics {
        let questions = bank.questions.filter {
            filter.admits(subject: $0.subject, domain: $0.domain, skill: $0.skill)
        }
        let records = respelled(history.filter {
            filter.admits(subject: $0.subject, domain: $0.domain, skill: $0.skill)
        }, like: questions)

        var stats = Statistics()
        stats.totalAttempts = records.count
        stats.totalCorrect = records.filter(\.correct).count
        stats.questionsSeen = Set(records.map(\.questionID)).count
        stats.questionsAvailable = questions.count

        stats.bySkill = group(records, questions, by: \.skill, \.skill)
            .sorted { $0.label < $1.label }
        stats.byDomain = group(records, questions, by: \.domain, \.domain)
            .sorted { $0.label < $1.label }
        stats.byDifficulty = group(records, questions, by: \.difficulty, \.difficulty)
            .sorted { (difficultyOrder[$0.label] ?? 9) < (difficultyOrder[$1.label] ?? 9) }
        let sectionOrder = Subject.allCases
        stats.bySection = group(records, questions,
                                by: { $0.subject }, { $0.subject },
                                label: { $0.displayName })
            .sorted { (sectionOrder.firstIndex(of: $0.order) ?? 9)
                    < (sectionOrder.firstIndex(of: $1.order) ?? 9) }
            .map(\.breakdown)

        stats.trend = sittings(records.filter { !$0.backfilled })

        let times = records.filter { !$0.backfilled }
            .map(\.secondsSpent).filter { $0 > 0 }.sorted()
        if !times.isEmpty { stats.medianSeconds = times[times.count / 2] }
        return stats
    }

    private static func group<Key: Hashable>(
        _ records: [AttemptRecord], _ questions: [Question],
        by recordKey: (AttemptRecord) -> Key, _ questionKey: (Question) -> Key,
        label: (Key) -> String) -> [(order: Key, breakdown: Breakdown)] {
        var attempts = [Key: [AttemptRecord]]()
        for r in records { attempts[recordKey(r), default: []].append(r) }
        var available = [Key: Int]()
        for q in questions { available[questionKey(q), default: 0] += 1 }

        return Set(attempts.keys).union(available.keys).map { key in
            let rs = attempts[key] ?? []
            let times = rs.filter { !$0.backfilled }
                .map(\.secondsSpent).filter { $0 > 0 }
            return (key, Breakdown(
                label: label(key),
                attempts: rs.count,
                correct: rs.filter(\.correct).count,
                available: available[key] ?? 0,
                seen: Set(rs.map(\.questionID)).count,
                averageSeconds: times.isEmpty ? 0 : times.reduce(0, +) / Double(times.count)))
        }
    }

    private static func respelled(_ records: [AttemptRecord],
                                  like questions: [Question]) -> [AttemptRecord] {
        func spellings(_ key: KeyPath<Question, String>) -> [String: String] {
            var byKey = [String: String]()
            for q in questions where !q[keyPath: key].isEmpty {
                byKey[LabelCase.key(q[keyPath: key])] = q[keyPath: key]
            }
            return byKey
        }
        let skills = spellings(\.skill)
        let domains = spellings(\.domain)
        let difficulties = spellings(\.difficulty)
        let needed = records.contains { r in
            (skills[LabelCase.key(r.skill)].map { $0 != r.skill } ?? false)
            || (domains[LabelCase.key(r.domain)].map { $0 != r.domain } ?? false)
            || (difficulties[LabelCase.key(r.difficulty)].map { $0 != r.difficulty } ?? false)
        }
        guard needed else { return records }
        return records.map { r in
            var r = r
            if let one = skills[LabelCase.key(r.skill)] { r.skill = one }
            if let one = domains[LabelCase.key(r.domain)] { r.domain = one }
            if let one = difficulties[LabelCase.key(r.difficulty)] { r.difficulty = one }
            return r
        }
    }

    private static func group(_ records: [AttemptRecord], _ questions: [Question],
                              by recordKey: KeyPath<AttemptRecord, String>,
                              _ questionKey: KeyPath<Question, String>) -> [Breakdown] {
        var attempts = [String: [AttemptRecord]]()
        for r in records where !r[keyPath: recordKey].isEmpty {
            attempts[r[keyPath: recordKey], default: []].append(r)
        }
        var available = [String: Int]()
        for q in questions where !q[keyPath: questionKey].isEmpty {
            available[q[keyPath: questionKey], default: 0] += 1
        }

        let labels = Set(attempts.keys).union(available.keys)
        return labels.map { label in
            let rs = attempts[label] ?? []
            let times = rs.filter { !$0.backfilled }
                .map(\.secondsSpent).filter { $0 > 0 }
            return Breakdown(
                label: label,
                attempts: rs.count,
                correct: rs.filter(\.correct).count,
                available: available[label] ?? 0,
                seen: Set(rs.map(\.questionID)).count,
                averageSeconds: times.isEmpty ? 0 : times.reduce(0, +) / Double(times.count))
        }
    }

    static let sittingGap: TimeInterval = 30 * 60

    static func sittings(_ records: [AttemptRecord]) -> [TrendPoint] {
        let sorted = records.sorted { $0.at < $1.at }
        guard !sorted.isEmpty else { return [] }
        var out = [TrendPoint]()
        var current = TrendPoint(index: 0, date: sorted[0].at, attempts: 0, correct: 0)
        var previous = sorted[0].at
        for r in sorted {
            if r.at.timeIntervalSince(previous) > sittingGap {
                out.append(current)
                current = TrendPoint(index: out.count, date: r.at, attempts: 0, correct: 0)
            }
            current.attempts += 1
            if r.correct { current.correct += 1 }
            previous = r.at
        }
        out.append(current)
        return out
    }
}
