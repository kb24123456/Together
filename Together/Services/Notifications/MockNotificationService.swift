import Foundation

struct MockNotificationService: NotificationServiceProtocol {
    func authorizationStatus() async -> NotificationAuthorizationStatus {
        .authorized
    }

    func requestAuthorization() async throws -> NotificationAuthorizationStatus {
        .authorized
    }

    func schedule(_ notifications: [AppNotification]) async throws {}
}
