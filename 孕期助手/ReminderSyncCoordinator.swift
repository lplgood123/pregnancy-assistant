import Foundation
import UserNotifications

enum ReminderSyncOutcome {
    case success
    case permissionDenied
    case failed(String)
}

enum ReminderSyncCoordinator {
    static func sync(using store: PregnancyStore) async -> ReminderSyncOutcome {
        let center = UNUserNotificationCenter.current()

        do {
            let granted = try await ensureAuthorization(center: center)
            guard granted else {
                return .permissionDenied
            }

            try await ReminderScheduler.scheduleAll(using: store)
            return .success
        } catch {
            return .failed(error.localizedDescription)
        }
    }

    private static func ensureAuthorization(center: UNUserNotificationCenter) async throws -> Bool {
        let settings = await notificationSettings(center: center)
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            return true
        case .notDetermined:
            return try await ReminderScheduler.requestAuthorization()
        case .denied:
            return false
        @unknown default:
            return false
        }
    }

    private static func notificationSettings(center: UNUserNotificationCenter) async -> UNNotificationSettings {
        await withCheckedContinuation { continuation in
            center.getNotificationSettings { settings in
                continuation.resume(returning: settings)
            }
        }
    }
}
