import Foundation

enum UserAvatarAsset: Hashable, Sendable {
    case system(String)
    case photo(fileName: String)
}

struct User: Identifiable, Hashable, Sendable {
    let id: UUID
    var appleUserID: String?
    var displayName: String
    var avatarSystemName: String?
    var avatarPhotoFileName: String? = nil
    var avatarAssetID: String? = nil
    var avatarVersion: Int = 0
    var createdAt: Date
    var updatedAt: Date
    var preferences: NotificationSettings

    var avatarCacheFileName: String? {
        // Prefer the explicit filename stored on the record — partner avatars
        // carry a versioned name (`asset-{id}-v{N}.jpg`) that breaks UIImage's
        // URL cache on each remote update. Fall back to the legacy
        // assetID-derived name when avatarPhotoFileName is absent.
        if let avatarPhotoFileName, !avatarPhotoFileName.isEmpty {
            return avatarPhotoFileName
        }
        if let avatarAssetID {
            return UserAvatarStorage.fileName(forAssetID: avatarAssetID)
        }
        return nil
    }

    var avatarAsset: UserAvatarAsset {
        if let avatarCacheFileName {
            return .photo(fileName: avatarCacheFileName)
        }
        return .system(avatarSystemName ?? "person.crop.circle.fill")
    }
}

struct NotificationSettings: Hashable, Sendable {
    nonisolated static let defaultQuickTimePresetMinutes: [Int] = [5, 30, 60]
    nonisolated static let defaultPairQuickReplyMessages: [String] = ["不想做", "没时间", "有点忙"]
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
    var pairQuickReplyMessages: [String] = NotificationSettings.defaultPairQuickReplyMessages
    var completedTaskAutoArchiveEnabled: Bool = true
    var completedTaskAutoArchiveDays: Int = NotificationSettings.defaultCompletedTaskAutoArchiveDays
    var appLockEnabled: Bool = false

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

    nonisolated static func normalizedPairQuickReplyMessages(_ values: [String]) -> [String] {
        let trimmed = values.map {
            $0.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        let filtered = trimmed.filter { !$0.isEmpty }
        var normalized = Array(filtered.prefix(3))
        if normalized.count < 3 {
            normalized.append(contentsOf: defaultPairQuickReplyMessages.dropFirst(normalized.count))
        }
        return normalized
    }

    nonisolated static func normalizedCompletedTaskAutoArchiveDays(_ value: Int) -> Int {
        completedTaskAutoArchiveDayOptions.contains(value)
            ? value
            : defaultCompletedTaskAutoArchiveDays
    }
}
