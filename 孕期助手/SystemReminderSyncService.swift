import EventKit
import Foundation

enum SystemReminderSyncStatus: Equatable {
    case skippedDisabled
    case success
    case permissionDenied
    case failed(String)
}

enum SystemReminderSyncService {
    private static let appCalendarTitle = "孕期助手"
    private static let keyPrefix = "pregassistant://reminder/"

    private struct ReminderDraft {
        var key: String
        var title: String
        var notes: String
        var dueDateComponents: DateComponents
        var recurrenceRule: EKRecurrenceRule?
    }

    static func sync(using store: PregnancyStore) async -> SystemReminderSyncStatus {
        let config = store.currentReminderConfig()
        guard config.enableSystemReminders else {
            return .skippedDisabled
        }

        let eventStore = EKEventStore()

        do {
            let granted = try await ensureAuthorization(eventStore)
            guard granted else {
                return .permissionDenied
            }

            let calendar = try appCalendar(using: eventStore)
            let drafts = buildDrafts(using: store)
            try await upsertDrafts(drafts, in: calendar, using: eventStore)
            return .success
        } catch {
            return .failed(error.localizedDescription)
        }
    }

    static func clearAppManagedReminders() async -> SystemReminderSyncStatus {
        let eventStore = EKEventStore()

        do {
            let granted = try await ensureAuthorization(eventStore)
            guard granted else {
                return .permissionDenied
            }

            var remindersByID: [String: EKReminder] = [:]

            if let appCalendar = eventStore.calendars(for: .reminder).first(where: { $0.title == appCalendarTitle }) {
                let appPredicate = eventStore.predicateForReminders(in: [appCalendar])
                let appReminders = await fetchReminders(matching: appPredicate, eventStore: eventStore)
                for reminder in appReminders {
                    remindersByID[reminder.calendarItemIdentifier] = reminder
                }
            }

            let allPredicate = eventStore.predicateForReminders(in: nil)
            let allReminders = await fetchReminders(matching: allPredicate, eventStore: eventStore)
            for reminder in allReminders where key(from: reminder) != nil {
                remindersByID[reminder.calendarItemIdentifier] = reminder
            }

            if remindersByID.isEmpty {
                return .success
            }

            for reminder in remindersByID.values {
                try eventStore.remove(reminder, commit: false)
            }
            try eventStore.commit()
            return .success
        } catch {
            return .failed(error.localizedDescription)
        }
    }

    private static func ensureAuthorization(_ eventStore: EKEventStore) async throws -> Bool {
        let status = EKEventStore.authorizationStatus(for: .reminder)

        if #available(iOS 17.0, *) {
            switch status {
            case .fullAccess, .writeOnly, .authorized:
                return true
            case .notDetermined:
                return try await eventStore.requestFullAccessToReminders()
            case .restricted, .denied:
                return false
            @unknown default:
                return false
            }
        } else {
            switch status {
            case .authorized, .fullAccess, .writeOnly:
                return true
            case .notDetermined:
                return try await withCheckedThrowingContinuation { continuation in
                    eventStore.requestAccess(to: .reminder) { granted, error in
                        if let error {
                            continuation.resume(throwing: error)
                        } else {
                            continuation.resume(returning: granted)
                        }
                    }
                }
            case .restricted, .denied:
                return false
            @unknown default:
                return false
            }
        }
    }

    private static func appCalendar(using eventStore: EKEventStore) throws -> EKCalendar {
        if let existing = eventStore.calendars(for: .reminder).first(where: { $0.title == appCalendarTitle }) {
            return existing
        }

        let calendar = EKCalendar(for: .reminder, eventStore: eventStore)
        calendar.title = appCalendarTitle

        if let defaultSource = eventStore.defaultCalendarForNewReminders()?.source {
            calendar.source = defaultSource
        } else if let localSource = eventStore.sources.first(where: { $0.sourceType == .local }) {
            calendar.source = localSource
        } else if let fallback = eventStore.sources.first {
            calendar.source = fallback
        } else {
            throw NSError(domain: "SystemReminderSyncService", code: 1, userInfo: [NSLocalizedDescriptionKey: "未找到可用的提醒事项来源"])
        }

        try eventStore.saveCalendar(calendar, commit: true)
        return calendar
    }

    private static func upsertDrafts(_ drafts: [ReminderDraft], in calendar: EKCalendar, using eventStore: EKEventStore) async throws {
        let predicate = eventStore.predicateForReminders(in: [calendar])
        let existing = await fetchReminders(matching: predicate, eventStore: eventStore)

        var existingByKey: [String: EKReminder] = [:]
        for reminder in existing {
            guard let key = key(from: reminder) else { continue }
            existingByKey[key] = reminder
        }

        for draft in drafts {
            let reminder = existingByKey[draft.key] ?? EKReminder(eventStore: eventStore)
            reminder.calendar = calendar
            reminder.title = draft.title
            reminder.notes = draft.notes
            reminder.dueDateComponents = draft.dueDateComponents
            reminder.recurrenceRules = draft.recurrenceRule.map { [$0] }
            reminder.priority = 5
            reminder.url = URL(string: keyPrefix + draft.key)
            try eventStore.save(reminder, commit: false)
            existingByKey.removeValue(forKey: draft.key)
        }

        for stale in existingByKey.values {
            try eventStore.remove(stale, commit: false)
        }

        try eventStore.commit()
    }

    private static func fetchReminders(matching predicate: NSPredicate, eventStore: EKEventStore) async -> [EKReminder] {
        await withCheckedContinuation { continuation in
            eventStore.fetchReminders(matching: predicate) { reminders in
                continuation.resume(returning: reminders ?? [])
            }
        }
    }

    private static func key(from reminder: EKReminder) -> String? {
        guard let absolute = reminder.url?.absoluteString, absolute.hasPrefix(keyPrefix) else { return nil }
        return String(absolute.dropFirst(keyPrefix.count))
    }

    private static func buildDrafts(using store: PregnancyStore) -> [ReminderDraft] {
        var drafts: [ReminderDraft] = []
        let config = store.currentReminderConfig()
        let minutesBefore = max(config.minutesBefore, 0)

        let dailyRule = EKRecurrenceRule(recurrenceWith: .daily, interval: 1, end: nil)

        for section in store.medicationSectionsForToday() {
            guard
                let period = TimePeriod.allCases.first(where: { $0.rawValue == section.title }),
                !section.rows.isEmpty
            else {
                continue
            }

            let baseTime = store.reminderTime(for: period)
            let semantic = ReminderScheduler.semanticAdjustedTimeText(for: period, baseTime: baseTime)
            guard let hm = parseHM(semantic) else { continue }
            let trigger = shifted(hour: hm.hour, minute: hm.minute, deltaMinutes: -minutesBefore)
            let meds = section.rows.map { "\($0.title)\($0.subtitle.isEmpty ? "" : " \($0.subtitle)")" }.joined(separator: "、")

            drafts.append(
                ReminderDraft(
                    key: "medication-\(period.id)",
                    title: "用药提醒（\(period.rawValue)）",
                    notes: "请按计划用药：\(meds)",
                    dueDateComponents: dailyDueDate(hour: trigger.hour, minute: trigger.minute),
                    recurrenceRule: dailyRule
                )
            )
        }

        for item in store.state.extraDailyItems {
            let baseTime = store.reminderTime(for: item.period)
            let semantic = ReminderScheduler.semanticAdjustedTimeText(for: item.period, baseTime: baseTime)
            guard let hm = parseHM(semantic) else { continue }
            let trigger = shifted(hour: hm.hour, minute: hm.minute, deltaMinutes: -minutesBefore)
            let detail = item.detail.trimmingCharacters(in: .whitespacesAndNewlines)
            let notes = detail.isEmpty ? item.title : "\(item.title)：\(detail)"

            drafts.append(
                ReminderDraft(
                    key: "extra-\(item.id)",
                    title: "自定义提醒（\(item.period.rawValue)）",
                    notes: notes,
                    dueDateComponents: dailyDueDate(hour: trigger.hour, minute: trigger.minute),
                    recurrenceRule: dailyRule
                )
            )
        }

        if let appointment = store.nextPendingAppointment() {
            if let dayBefore = Calendar.current.date(byAdding: .day, value: -1, to: appointment.dueDate) {
                drafts.append(
                    ReminderDraft(
                        key: "appointment-day-before-\(appointment.id)",
                        title: "回诊提醒（明天）",
                        notes: "\(appointment.title)，请提前准备资料。",
                        dueDateComponents: dateDueDate(dayBefore, hour: 20, minute: 0),
                        recurrenceRule: nil
                    )
                )
            }

            drafts.append(
                ReminderDraft(
                    key: "appointment-day-of-\(appointment.id)",
                    title: "回诊提醒（今天）",
                    notes: "\(appointment.title)，今天记得按时就诊。",
                    dueDateComponents: dateDueDate(appointment.dueDate, hour: 8, minute: 0),
                    recurrenceRule: nil
                )
            )
        }

        return drafts
    }

    private static func dailyDueDate(hour: Int, minute: Int) -> DateComponents {
        var components = Calendar.current.dateComponents([.year, .month, .day], from: Date())
        components.hour = hour
        components.minute = minute
        components.timeZone = .current
        return components
    }

    private static func dateDueDate(_ date: Date, hour: Int, minute: Int) -> DateComponents {
        var components = Calendar.current.dateComponents([.year, .month, .day], from: date)
        components.hour = hour
        components.minute = minute
        components.timeZone = .current
        return components
    }

    private static func parseHM(_ text: String) -> (hour: Int, minute: Int)? {
        let comps = text.split(separator: ":")
        guard comps.count == 2, let h = Int(comps[0]), let m = Int(comps[1]) else { return nil }
        return (h, m)
    }

    private static func shifted(hour: Int, minute: Int, deltaMinutes: Int) -> (hour: Int, minute: Int) {
        let total = ((hour * 60 + minute + deltaMinutes) % (24 * 60) + (24 * 60)) % (24 * 60)
        return (total / 60, total % 60)
    }
}
