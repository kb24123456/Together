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
    nonisolated static let defaultQuickTimePresetMinutes: [Int] = [5, 30, 60]
    nonisolated static let defaultSnoozeMinutes: Int = 30
    nonisolated static let defaultCompletedTaskAutoArchiveDays: Int = 30
    nonisolated static let completedTaskAutoArchiveDayOptions: [Int] = [7, 14, 30, 90]

    var taskReminderEnabled: Bool
    var dailySummaryEnabled: Bool
    var calendarReminderEnabled: Bool
    var futureCollaborationInviteEnabled: Bool
    var taskUrgencyWindowMinutes: Int = 30
    var defaultSnoozeMinutes: Int = NotificationSettings.defaultSnoozeMinutes
    var quickTimePresetMinutes: [Int] = NotificationSettings.defaultQuickTimePresetMinutes
    var completedTaskAutoArchiveEnabled: Bool = true
    var completedTaskAutoArchiveDays: Int = NotificationSettings.defaultCompletedTaskAutoArchiveDays

    nonisolated static func normalizedSnoozeMinutes(_ value: Int) -> Int {
        let clamped = min(max(value, 5), 180)
        let rounded = Int((Double(clamped) / 5.0).rounded()) * 5
        return max(5, rounded)
    }

    nonisolated static func normalizedQuickTimePresetMinutes(_ values: [Int]) -> [Int] {
        let sanitized = values.map { value in
            normalizedSnoozeMinutes(value)
        }

        var normalized = Array(sanitized.prefix(3))
        if normalized.count < 3 {
            normalized.append(contentsOf: defaultQuickTimePresetMinutes.dropFirst(normalized.count))
        }
        return normalized
    }

    nonisolated static func normalizedCompletedTaskAutoArchiveDays(_ value: Int) -> Int {
        completedTaskAutoArchiveDayOptions.contains(value)
            ? value
            : defaultCompletedTaskAutoArchiveDays
    }
}
