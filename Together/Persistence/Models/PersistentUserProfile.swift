import Foundation
import SwiftData

@Model
final class PersistentUserProfile {
    var userID: UUID
    var displayName: String
    var avatarSystemName: String?
    var avatarPhotoFileName: String?
    var avatarAssetID: String?
    var avatarVersion: Int = 0
    // Legacy/local repair payload only. Shared-authority avatar semantics must rely on
    // avatarAssetID/avatarVersion, while disk files remain a rebuildable runtime cache.
    @Attribute(.externalStorage) var avatarPhotoData: Data?
    var taskReminderEnabled: Bool
    var dailySummaryEnabled: Bool
    var calendarReminderEnabled: Bool
    var futureCollaborationInviteEnabled: Bool
    var taskUrgencyWindowMinutes: Int
    var defaultSnoozeMinutes: Int
    var quickTimePresetMinutes: [Int]
    var completedTaskAutoArchiveEnabled: Bool
    var completedTaskAutoArchiveDays: Int
    var updatedAt: Date

    init(
        userID: UUID,
        displayName: String,
        avatarSystemName: String?,
        avatarPhotoFileName: String?,
        avatarAssetID: String?,
        avatarVersion: Int,
        avatarPhotoData: Data?,
        taskReminderEnabled: Bool,
        dailySummaryEnabled: Bool,
        calendarReminderEnabled: Bool,
        futureCollaborationInviteEnabled: Bool,
        taskUrgencyWindowMinutes: Int,
        defaultSnoozeMinutes: Int,
        quickTimePresetMinutes: [Int],
        completedTaskAutoArchiveEnabled: Bool,
        completedTaskAutoArchiveDays: Int,
        updatedAt: Date
    ) {
        self.userID = userID
        self.displayName = displayName
        self.avatarSystemName = avatarSystemName
        self.avatarPhotoFileName = avatarPhotoFileName
        self.avatarAssetID = avatarAssetID
        self.avatarVersion = avatarVersion
        self.avatarPhotoData = avatarPhotoData
        self.taskReminderEnabled = taskReminderEnabled
        self.dailySummaryEnabled = dailySummaryEnabled
        self.calendarReminderEnabled = calendarReminderEnabled
        self.futureCollaborationInviteEnabled = futureCollaborationInviteEnabled
        self.taskUrgencyWindowMinutes = taskUrgencyWindowMinutes
        self.defaultSnoozeMinutes = defaultSnoozeMinutes
        self.quickTimePresetMinutes = quickTimePresetMinutes
        self.completedTaskAutoArchiveEnabled = completedTaskAutoArchiveEnabled
        self.completedTaskAutoArchiveDays = completedTaskAutoArchiveDays
        self.updatedAt = updatedAt
    }
}

extension PersistentUserProfile {
    convenience init(user: User) {
        self.init(
            userID: user.id,
            displayName: user.displayName,
            avatarSystemName: user.avatarSystemName,
            avatarPhotoFileName: user.avatarPhotoFileName,
            avatarAssetID: user.avatarAssetID,
            avatarVersion: user.avatarVersion,
            avatarPhotoData: nil,
            taskReminderEnabled: user.preferences.taskReminderEnabled,
            dailySummaryEnabled: user.preferences.dailySummaryEnabled,
            calendarReminderEnabled: user.preferences.calendarReminderEnabled,
            futureCollaborationInviteEnabled: user.preferences.futureCollaborationInviteEnabled,
            taskUrgencyWindowMinutes: user.preferences.taskUrgencyWindowMinutes,
            defaultSnoozeMinutes: user.preferences.defaultSnoozeMinutes,
            quickTimePresetMinutes: user.preferences.quickTimePresetMinutes,
            completedTaskAutoArchiveEnabled: user.preferences.completedTaskAutoArchiveEnabled,
            completedTaskAutoArchiveDays: user.preferences.completedTaskAutoArchiveDays,
            updatedAt: user.updatedAt
        )
    }

    func apply(to user: User) -> User {
        var updatedUser = user
        updatedUser.displayName = displayName
        updatedUser.avatarSystemName = avatarSystemName
        updatedUser.avatarPhotoFileName = avatarPhotoFileName
        updatedUser.avatarAssetID = avatarAssetID
        updatedUser.avatarVersion = avatarVersion
        updatedUser.preferences = NotificationSettings(
            taskReminderEnabled: taskReminderEnabled,
            dailySummaryEnabled: dailySummaryEnabled,
            calendarReminderEnabled: calendarReminderEnabled,
            futureCollaborationInviteEnabled: futureCollaborationInviteEnabled,
            taskUrgencyWindowMinutes: NotificationSettings.normalizedSnoozeMinutes(taskUrgencyWindowMinutes),
            defaultSnoozeMinutes: NotificationSettings.normalizedSnoozeMinutes(defaultSnoozeMinutes),
            quickTimePresetMinutes: NotificationSettings.normalizedQuickTimePresetMinutes(quickTimePresetMinutes),
            completedTaskAutoArchiveEnabled: completedTaskAutoArchiveEnabled,
            completedTaskAutoArchiveDays: NotificationSettings.normalizedCompletedTaskAutoArchiveDays(
                completedTaskAutoArchiveDays
            ),
            appLockEnabled: UserDefaults.standard.bool(forKey: "together.appLockEnabled")
        )
        updatedUser.updatedAt = updatedAt
        return updatedUser
    }

    func update(from user: User) {
        displayName = user.displayName
        avatarSystemName = user.avatarSystemName
        avatarPhotoFileName = user.avatarPhotoFileName
        avatarAssetID = user.avatarAssetID
        avatarVersion = user.avatarVersion
        taskReminderEnabled = user.preferences.taskReminderEnabled
        dailySummaryEnabled = user.preferences.dailySummaryEnabled
        calendarReminderEnabled = user.preferences.calendarReminderEnabled
        futureCollaborationInviteEnabled = user.preferences.futureCollaborationInviteEnabled
        taskUrgencyWindowMinutes = NotificationSettings.normalizedSnoozeMinutes(user.preferences.taskUrgencyWindowMinutes)
        defaultSnoozeMinutes = NotificationSettings.normalizedSnoozeMinutes(user.preferences.defaultSnoozeMinutes)
        quickTimePresetMinutes = NotificationSettings.normalizedQuickTimePresetMinutes(user.preferences.quickTimePresetMinutes)
        completedTaskAutoArchiveEnabled = user.preferences.completedTaskAutoArchiveEnabled
        completedTaskAutoArchiveDays = NotificationSettings.normalizedCompletedTaskAutoArchiveDays(
            user.preferences.completedTaskAutoArchiveDays
        )
        UserDefaults.standard.set(user.preferences.appLockEnabled, forKey: "together.appLockEnabled")
        updatedAt = user.updatedAt
    }
}
