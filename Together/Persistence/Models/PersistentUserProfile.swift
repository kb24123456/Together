import Foundation
import TogetherCore

nonisolated extension PersistentUserProfile {
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
