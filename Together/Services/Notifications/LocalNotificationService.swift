import Foundation
import UserNotifications

struct LocalNotificationService: NotificationServiceProtocol {
    private let center: UNUserNotificationCenter
    private let calendar: Calendar

    init(
        center: UNUserNotificationCenter = .current(),
        calendar: Calendar = .current
    ) {
        self.center = center
        self.calendar = calendar
    }

    func authorizationStatus() async -> NotificationAuthorizationStatus {
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            return .authorized
        case .denied:
            return .denied
        case .notDetermined:
            return .notDetermined
        @unknown default:
            return .notDetermined
        }
    }

    func requestAuthorization() async throws -> NotificationAuthorizationStatus {
        let granted = try await center.requestAuthorization(options: [.alert, .badge, .sound])
        return granted ? .authorized : .denied
    }

    func schedule(_ notifications: [AppNotification]) async throws {
        for notification in notifications {
            if notification.recurrence == .none, notification.scheduledAt <= .now {
                await cancel([notification.identifier])
                continue
            }

            let content = UNMutableNotificationContent()
            content.title = notification.title
            content.body = notification.body
            content.sound = .default
            content.categoryIdentifier = NotificationActionCatalog.categoryIdentifier(for: notification.targetType)

            let trigger: UNCalendarNotificationTrigger
            switch notification.recurrence {
            case .none:
                let components = calendar.dateComponents(
                    [.year, .month, .day, .hour, .minute, .second],
                    from: notification.scheduledAt
                )
                trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
            case .daily:
                let components = calendar.dateComponents(
                    [.hour, .minute],
                    from: notification.scheduledAt
                )
                trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
            }
            let request = UNNotificationRequest(
                identifier: notification.identifier,
                content: content,
                trigger: trigger
            )

            center.removePendingNotificationRequests(withIdentifiers: [notification.identifier])
            try await center.add(request)
        }
    }

    func cancel(_ identifiers: [String]) async {
        guard identifiers.isEmpty == false else { return }
        center.removePendingNotificationRequests(withIdentifiers: identifiers)
        center.removeDeliveredNotifications(withIdentifiers: identifiers)
    }
}
