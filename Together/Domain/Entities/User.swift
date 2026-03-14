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
    var taskReminderEnabled: Bool
    var dailySummaryEnabled: Bool
    var calendarReminderEnabled: Bool
    var futureCollaborationInviteEnabled: Bool
}
