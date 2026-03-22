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
    static let defaultQuickTimePresetMinutes: [Int] = [30, 60, 120]

    var taskReminderEnabled: Bool
    var dailySummaryEnabled: Bool
    var calendarReminderEnabled: Bool
    var futureCollaborationInviteEnabled: Bool
    var taskUrgencyWindowMinutes: Int = 30
    var quickTimePresetMinutes: [Int] = NotificationSettings.defaultQuickTimePresetMinutes

    static func normalizedQuickTimePresetMinutes(_ values: [Int]) -> [Int] {
        let sanitized = values.map { value in
            let clamped = min(max(value, 5), 180)
            let rounded = Int((Double(clamped) / 5.0).rounded()) * 5
            return max(5, rounded)
        }

        var normalized = Array(sanitized.prefix(3))
        if normalized.count < 3 {
            normalized.append(contentsOf: defaultQuickTimePresetMinutes.dropFirst(normalized.count))
        }
        return normalized
    }
}
