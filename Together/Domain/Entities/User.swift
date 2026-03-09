import Foundation

struct User: Identifiable, Hashable, Sendable {
    let id: UUID
    var appleUserID: String?
    var displayName: String
    var avatarSystemName: String?
    var createdAt: Date
    var updatedAt: Date
    var preferences: NotificationSettings
}

struct NotificationSettings: Hashable, Sendable {
    var newItemEnabled: Bool
    var decisionEnabled: Bool
    var anniversaryEnabled: Bool
    var deadlineEnabled: Bool
}
