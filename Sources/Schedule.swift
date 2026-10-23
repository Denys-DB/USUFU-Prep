import Foundation

struct StudySchedule: Codable, Equatable {
    var enabled: Bool = false
    var days: Set<Int> = [2, 3, 4, 5, 6]
    var dailyTarget: Int = 20
    var remindersOn: Bool = false
    var reminderHour: Int = 17
    var reminderMinute: Int = 0
    var warnsWhenStreakAtRisk: Bool = true
    var warningHour: Int = 20

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? false
        days = try c.decodeIfPresent(Set<Int>.self, forKey: .days) ?? [2, 3, 4, 5, 6]
        dailyTarget = try c.decodeIfPresent(Int.self, forKey: .dailyTarget) ?? 20
        remindersOn = try c.decodeIfPresent(Bool.self, forKey: .remindersOn) ?? false
        reminderHour = try c.decodeIfPresent(Int.self, forKey: .reminderHour) ?? 17
        reminderMinute = try c.decodeIfPresent(Int.self, forKey: .reminderMinute) ?? 0
        warnsWhenStreakAtRisk = try c
            .decodeIfPresent(Bool.self, forKey: .warnsWhenStreakAtRisk) ?? true
        warningHour = try c.decodeIfPresent(Int.self, forKey: .warningHour) ?? 20
    }

    var isActive: Bool { enabled && !days.isEmpty && dailyTarget > 0 }

    func isScheduled(_ date: Date, calendar: Calendar = .current) -> Bool {
        guard isActive else { return true }
        return days.contains(calendar.component(.weekday, from: date))
    }

    func target(on date: Date, calendar: Calendar = .current) -> Int {
        guard isActive else { return dailyTarget }
        return isScheduled(date, calendar: calendar) ? dailyTarget : 0
    }

    static func weekdayOrder(calendar: Calendar = .current) -> [Int] {
        (0..<7).map { (calendar.firstWeekday - 1 + $0) % 7 + 1 }
    }

    static func weekdayName(_ weekday: Int, calendar: Calendar = .current) -> String {
        let symbols = calendar.veryShortWeekdaySymbols
        return symbols[(weekday - 1) % symbols.count]
    }

    var summary: String {
        guard isActive else {
            return dailyTarget > 0 ? Lf("No plan — %d a day, every day", dailyTarget)
                                   : L("No plan — every day counts")
        }
        let names = StudySchedule.weekdayOrder()
            .filter { days.contains($0) }
            .map { StudySchedule.weekdayName($0) }
        if days.count == 7 { return Lf("%d a day, every day", dailyTarget) }
        return Lf("%1$d a day on %2$@", dailyTarget, names.joined(separator: " "))
    }
}

struct StreakState: Equatable {
    var current = 0
    var best = 0
    var answeredToday = 0
    var targetToday = 0
    var isRestDay = false
    var atRisk = false
    var keptThisWeek = 0
    var plannedThisWeek = 0
    var runStartedOn: Date? = nil

    var metToday: Bool { targetToday > 0 && answeredToday >= targetToday }
    var remainingToday: Int { max(0, targetToday - answeredToday) }
    var fractionToday: Double {
        targetToday > 0 ? min(1, Double(answeredToday) / Double(targetToday)) : 1
    }
}

enum StreakEngine {

    private enum Day { case kept, missed, rest }

    static func evaluate(answers: [Date: Int], schedule: StudySchedule,
                         excused: Set<Date> = [],
                         now: Date = Date(), calendar: Calendar = .current) -> StreakState {
        var state = StreakState()
        let today = calendar.startOfDay(for: now)
        let byDay = Dictionary(answers.map { (calendar.startOfDay(for: $0.key), $0.value) },
                               uniquingKeysWith: +)
        let excusedDays = Set(excused.map { calendar.startOfDay(for: $0) })

        state.answeredToday = byDay[today] ?? 0
        state.targetToday = schedule.target(on: today, calendar: calendar)
        state.isRestDay = state.targetToday == 0

        func classify(_ day: Date) -> Day {
            let target = schedule.target(on: day, calendar: calendar)
            if target == 0 { return .rest }
            if (byDay[day] ?? 0) >= target { return .kept }
            return excusedDays.contains(day) ? .rest : .missed
        }

        var streak = 0
        var cursor = today
        if classify(today) == .kept { streak = 1; state.runStartedOn = today }
        for _ in 0..<400 {
            guard let previous = calendar.date(byAdding: .day, value: -1, to: cursor) else { break }
            cursor = previous
            switch classify(previous) {
            case .kept: streak += 1; state.runStartedOn = previous
            case .rest: continue
            case .missed: state.current = streak
                          return finish(state, streak, byDay, schedule, excusedDays,
                                        today, calendar)
            }
        }
        return finish(state, streak, byDay, schedule, excusedDays, today, calendar)
    }

    private static func finish(_ partial: StreakState, _ streak: Int,
                               _ byDay: [Date: Int], _ schedule: StudySchedule,
                               _ excused: Set<Date>,
                               _ today: Date, _ calendar: Calendar) -> StreakState {
        var state = partial
        state.current = streak
        state.atRisk = !state.isRestDay && !state.metToday && streak > 0

        let days = byDay.keys.sorted()
        if let first = days.first {
            var run = 0, best = 0
            var cursor = first
            while cursor <= today {
                let target = schedule.target(on: cursor, calendar: calendar)
                if target == 0 {
                } else if (byDay[cursor] ?? 0) >= target {
                    run += 1
                    best = max(best, run)
                } else if excused.contains(cursor) {
                } else if cursor < today {
                    run = 0
                }
                guard let next = calendar.date(byAdding: .day, value: 1, to: cursor) else { break }
                cursor = next
            }
            state.best = max(best, streak)
        } else {
            state.best = streak
        }

        if let week = calendar.dateInterval(of: .weekOfYear, for: today) {
            var cursor = calendar.startOfDay(for: week.start)
            while cursor < week.end {
                let target = schedule.target(on: cursor, calendar: calendar)
                if target > 0 {
                    state.plannedThisWeek += 1
                    if (byDay[cursor] ?? 0) >= target { state.keptThisWeek += 1 }
                }
                guard let next = calendar.date(byAdding: .day, value: 1, to: cursor) else { break }
                cursor = next
            }
        }
        return state
    }

    static func nextScheduledDay(after date: Date, schedule: StudySchedule,
                                 calendar: Calendar = .current) -> Date? {
        guard schedule.isActive else { return nil }
        var cursor = calendar.startOfDay(for: date)
        for _ in 0..<8 {
            guard let next = calendar.date(byAdding: .day, value: 1, to: cursor) else { return nil }
            cursor = next
            if schedule.isScheduled(cursor, calendar: calendar) { return cursor }
        }
        return nil
    }
}

enum Mercy {

    static let longestGap = 31

    static let restoreAfter = 3
    static let welcomeAfter = 7

    struct Gap: Equatable {
        var lastActive: Date
        var daysAway: Int
        var missed: [Date]
        var streakBefore: Int

        var isRestorable: Bool {
            streakBefore > 0 && !missed.isEmpty && daysAway <= Mercy.longestGap
        }
    }

    static func gap(answers: [Date: Int], schedule: StudySchedule,
                    excused: Set<Date> = [],
                    now: Date = Date(), calendar: Calendar = .current) -> Gap? {
        let today = calendar.startOfDay(for: now)
        let byDay = Dictionary(answers.map { (calendar.startOfDay(for: $0.key), $0.value) },
                               uniquingKeysWith: +)
        guard let lastActive = byDay.filter({ $0.value > 0 }).keys.max(), lastActive < today
        else { return nil }

        let daysAway = calendar.dateComponents([.day], from: lastActive, to: today).day ?? 0
        guard daysAway > 0 else { return nil }

        let excusedDays = Set(excused.map { calendar.startOfDay(for: $0) })
        var missed = [Date]()
        var cursor = lastActive
        while let next = calendar.date(byAdding: .day, value: 1, to: cursor), next < today {
            cursor = next
            guard schedule.target(on: cursor, calendar: calendar) > 0 else { continue }
            guard (byDay[cursor] ?? 0) == 0, !excusedDays.contains(cursor) else { continue }
            missed.append(cursor)
        }

        let before = StreakEngine.evaluate(answers: answers, schedule: schedule,
                                           excused: excused, now: lastActive,
                                           calendar: calendar).current

        return Gap(lastActive: lastActive, daysAway: daysAway, missed: missed,
                   streakBefore: before)
    }
}
