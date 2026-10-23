import Foundation
import UserNotifications

@MainActor
enum Reminders {

    static var isAvailable: Bool { Bundle.main.bundleIdentifier != nil }

    enum Permission { case unknown, granted, denied }
    private(set) static var permission: Permission = .unknown

    static var silent = false

    private(set) static var heldForSitting = false

    private static let dailyPrefix = "usufu.daily."
    private static let atRiskID = "usufu.streak-at-risk"

    static func requestAuthorization() async -> Bool {
        guard isAvailable else { return false }
        do {
            let granted = try await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .sound])
            permission = granted ? .granted : .denied
            return granted
        } catch {
            permission = .denied
            return false
        }
    }

    static func refreshPermission() async {
        guard isAvailable else { return }
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional: permission = .granted
        case .denied: permission = .denied
        default: permission = .unknown
        }
    }

    static func hold() {
        heldForSitting = true
        guard isAvailable else { return }
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
    }

    static func release() { heldForSitting = false }

    static func reschedule(for schedule: StudySchedule) async {
        guard isAvailable, !heldForSitting else { return }
        let center = UNUserNotificationCenter.current()
        let stale = await center.pendingNotificationRequests()
            .map(\.identifier)
            .filter { $0.hasPrefix(dailyPrefix) }
        center.removePendingNotificationRequests(withIdentifiers: stale)

        guard schedule.isActive, schedule.remindersOn, permission == .granted else { return }

        for weekday in schedule.days.sorted() {
            let content = UNMutableNotificationContent()
            content.title = L("Time to practice")
            content.body = Lp(schedule.dailyTarget, "Today's plan is %d question.",
                              "Today's plan is %d questions.")
            content.sound = silent ? nil : .default

            var when = DateComponents()
            when.weekday = weekday
            when.hour = schedule.reminderHour
            when.minute = schedule.reminderMinute

            let request = UNNotificationRequest(
                identifier: dailyPrefix + String(weekday),
                content: content,
                trigger: UNCalendarNotificationTrigger(dateMatching: when, repeats: true))
            try? await center.add(request)
        }
    }

    static func updateStreakWarning(_ state: StreakState, schedule: StudySchedule,
                                    now: Date = Date()) async {
        guard isAvailable, !heldForSitting else { return }
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [atRiskID])

        guard schedule.isActive, schedule.remindersOn, schedule.warnsWhenStreakAtRisk,
              permission == .granted, state.atRisk else { return }

        let calendar = Calendar.current
        var components = calendar.dateComponents([.year, .month, .day], from: now)
        components.hour = schedule.warningHour
        components.minute = 0
        guard let fireAt = calendar.date(from: components), fireAt > now else { return }

        let content = UNMutableNotificationContent()
        content.title = state.current == 1
            ? L("Your streak ends tonight")
            : Lp(state.current, "%d-day streak ends tonight", "%d-day streak ends tonight")
        content.body = Lp(state.remainingToday, "%d more question keeps it.",
                          "%d more questions keep it.")
        content.sound = silent ? nil : .default

        let interval = fireAt.timeIntervalSince(now)
        let request = UNNotificationRequest(
            identifier: atRiskID, content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: max(1, interval),
                                                       repeats: false))
        try? await center.add(request)
    }

    static func cancelAll() {
        guard isAvailable else { return }
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
    }
}
