import Foundation
import UserNotifications

enum ReminderScheduler {
    private static let followUpMinutes = 30

    static func requestAuthorization() async throws -> Bool {
        try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])
    }

    static func clearAllPendingNotifications() async {
        let center = UNUserNotificationCenter.current()
        let staticIDs = reminderIdentifiers()
        center.removePendingNotificationRequests(withIdentifiers: staticIDs)
        center.removeDeliveredNotifications(withIdentifiers: staticIDs)

        let pending = await pendingNotificationRequests(center: center)
        let dynamicIDs = pending
            .map(\.identifier)
            .filter(isAppManagedIdentifier)
        if !dynamicIDs.isEmpty {
            center.removePendingNotificationRequests(withIdentifiers: dynamicIDs)
            center.removeDeliveredNotifications(withIdentifiers: dynamicIDs)
        }

        let delivered = await deliveredNotifications(center: center)
        let deliveredIDs = delivered
            .map(\.request.identifier)
            .filter(isAppManagedIdentifier)
        if !deliveredIDs.isEmpty {
            center.removeDeliveredNotifications(withIdentifiers: deliveredIDs)
        }
    }

    static func scheduleAll(using store: PregnancyStore) async throws {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: reminderIdentifiers())

        let config = store.currentReminderConfig()
        let minutesBefore = max(config.minutesBefore, 0)
        let medicationSections = store.medicationSectionsForToday()

        for section in medicationSections {
            guard
                let period = TimePeriod.allCases.first(where: { $0.rawValue == section.title }),
                let base = parseHM(store.reminderTime(for: period))
            else {
                continue
            }

            let semantic = semanticAdjustedTime(for: period, baseHour: base.0, baseMinute: base.1)
            let primary = shiftedTime(hour: semantic.hour, minute: semantic.minute, deltaMinutes: -minutesBefore)

            let title = "用药提醒（\(section.title)）"
            let meds = section.rows.map { "\($0.title)\($0.subtitle.isEmpty ? "" : " \($0.subtitle)")" }.joined(separator: "、")
            let body = "请按计划用药：\(meds)"
            let identifier = "medication-\(period.id)"
            try scheduleDaily(
                center: center,
                identifier: identifier,
                title: title,
                body: body,
                hour: semantic.hour,
                minute: semantic.minute,
                minutesBefore: minutesBefore
            )

            let followUpDate = nextDateAt(hour: primary.hour, minute: primary.minute)
                .addingTimeInterval(TimeInterval(followUpMinutes * 60))
            try scheduleOneOff(
                center: center,
                identifier: "medication-\(period.id)-followup",
                title: "用药提醒（追问）",
                body: "刚才的用药完成了吗？如果还没，我可以再提醒一次。",
                date: followUpDate
            )
        }

        if let appt = store.nextPendingAppointment() {
            let dayBefore = Calendar.current.date(byAdding: .day, value: -1, to: appt.dueDate)
            if let dayBefore {
                try scheduleOneOff(
                    center: center,
                    identifier: "appointment-day-before",
                    title: "回诊提醒（明天）",
                    body: "\(appt.title)，请准备资料并确认检查安排。",
                    date: Calendar.current.date(bySettingHour: 20, minute: 0, second: 0, of: dayBefore) ?? dayBefore
                )
            }
            try scheduleOneOff(
                center: center,
                identifier: "appointment-day-of",
                title: "回诊提醒（今天）",
                body: "\(appt.title)，今天记得按时回诊。",
                date: Calendar.current.date(bySettingHour: 8, minute: 0, second: 0, of: appt.dueDate) ?? appt.dueDate
            )
        }
    }

    private static func scheduleDaily(
        center: UNUserNotificationCenter,
        identifier: String,
        title: String,
        body: String,
        hour: Int,
        minute: Int,
        minutesBefore: Int
    ) throws {
        let triggerHM = shiftedTime(hour: hour, minute: minute, deltaMinutes: -minutesBefore)
        var dateComponents = DateComponents()
        dateComponents.hour = triggerHM.hour
        dateComponents.minute = triggerHM.minute

        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default

        let trigger = UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: true)
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
        center.add(request)
    }

    private static func scheduleOneOff(
        center: UNUserNotificationCenter,
        identifier: String,
        title: String,
        body: String,
        date: Date
    ) throws {
        guard date > Date() else { return }
        let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: date)

        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default

        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
        center.add(request)
    }

    private static func parseHM(_ text: String) -> (Int, Int)? {
        let comps = text.split(separator: ":")
        guard comps.count == 2, let h = Int(comps[0]), let m = Int(comps[1]) else { return nil }
        return (h, m)
    }

    private static func shiftedTime(hour: Int, minute: Int, deltaMinutes: Int) -> (hour: Int, minute: Int) {
        let total = ((hour * 60 + minute + deltaMinutes) % (24 * 60) + (24 * 60)) % (24 * 60)
        return (total / 60, total % 60)
    }

    private static func reminderIdentifiers() -> [String] {
        [
            "medication-\(TimePeriod.wakeUp.id)",
            "medication-\(TimePeriod.afterBreakfast.id)",
            "medication-\(TimePeriod.afterLunch.id)",
            "medication-\(TimePeriod.afterDinner.id)",
            "medication-\(TimePeriod.beforeSleep.id)",
            "medication-\(TimePeriod.wakeUp.id)-followup",
            "medication-\(TimePeriod.afterBreakfast.id)-followup",
            "medication-\(TimePeriod.afterLunch.id)-followup",
            "medication-\(TimePeriod.afterDinner.id)-followup",
            "medication-\(TimePeriod.beforeSleep.id)-followup",
            "appointment-day-before",
            "appointment-day-of"
        ]
    }

    private static func pendingNotificationRequests(center: UNUserNotificationCenter) async -> [UNNotificationRequest] {
        await withCheckedContinuation { continuation in
            center.getPendingNotificationRequests { requests in
                continuation.resume(returning: requests)
            }
        }
    }

    private static func deliveredNotifications(center: UNUserNotificationCenter) async -> [UNNotification] {
        await withCheckedContinuation { continuation in
            center.getDeliveredNotifications { notifications in
                continuation.resume(returning: notifications)
            }
        }
    }

    private static func isAppManagedIdentifier(_ identifier: String) -> Bool {
        identifier.hasPrefix("medication-") ||
        identifier.hasPrefix("appointment-") ||
        identifier.hasPrefix("extra-") ||
        identifier.hasPrefix("injection-")
    }

    static func cancelFollowUp(for period: TimePeriod) {
        let id = "medication-\(period.id)-followup"
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [id])
    }

    private static func semanticAdjustedTime(for period: TimePeriod, baseHour: Int, baseMinute: Int) -> (hour: Int, minute: Int) {
        _ = period
        return (baseHour, baseMinute)
    }

    static func semanticAdjustedTimeText(for period: TimePeriod, baseTime: String) -> String {
        guard let (h, m) = parseHM(baseTime) else { return baseTime }
        let adjusted = semanticAdjustedTime(for: period, baseHour: h, baseMinute: m)
        return String(format: "%02d:%02d", adjusted.hour, adjusted.minute)
    }

    private static func nextDateAt(hour: Int, minute: Int) -> Date {
        let calendar = Calendar.current
        var components = calendar.dateComponents([.year, .month, .day], from: Date())
        components.hour = hour
        components.minute = minute
        let today = calendar.date(from: components) ?? Date()
        if today > Date() {
            return today
        }
        return calendar.date(byAdding: .day, value: 1, to: today) ?? today
    }
}
