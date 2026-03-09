import Foundation

enum NotificationAuthorizationStatus: String, Hashable, Sendable {
    case notDetermined
    case denied
    case authorized
}

protocol NotificationServiceProtocol: Sendable {
    func authorizationStatus() async -> NotificationAuthorizationStatus
    func requestAuthorization() async throws -> NotificationAuthorizationStatus
    func schedule(_ notifications: [AppNotification]) async throws
}
