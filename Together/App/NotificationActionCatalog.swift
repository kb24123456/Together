import Foundation
import UserNotifications

enum NotificationActionCatalog {
    static let taskCategoryIdentifier = "together.notification.task"
    static let genericCategoryIdentifier = "together.notification.generic"
    static let taskNudgeCategoryIdentifier = "TASK_NUDGE"
    static let completeActionIdentifier = "together.notification.complete"
    static let completeNudgeActionIdentifier = "COMPLETE_NUDGE"

    static let snoozeFiveMinutesIdentifier = "together.notification.snooze.5m"
    static let snoozeTenMinutesIdentifier = "together.notification.snooze.10m"
    static let snoozeThirtyMinutesIdentifier = "together.notification.snooze.30m"

    static var categories: Set<UNNotificationCategory> {
        [
            UNNotificationCategory(
                identifier: taskCategoryIdentifier,
                actions: [
                    UNNotificationAction(
                        identifier: completeActionIdentifier,
                        title: "标记已完成"
                    ),
                    UNNotificationAction(
                        identifier: snoozeFiveMinutesIdentifier,
                        title: "5分钟后提醒"
                    ),
                    UNNotificationAction(
                        identifier: snoozeTenMinutesIdentifier,
                        title: "10分钟后提醒"
                    ),
                    UNNotificationAction(
                        identifier: snoozeThirtyMinutesIdentifier,
                        title: "30分钟后提醒"
                    )
                ],
                intentIdentifiers: [],
                options: [.customDismissAction]
            ),
            UNNotificationCategory(
                identifier: genericCategoryIdentifier,
                actions: [],
                intentIdentifiers: [],
                options: [.customDismissAction]
            ),
            UNNotificationCategory(
                identifier: taskNudgeCategoryIdentifier,
                actions: [
                    UNNotificationAction(
                        identifier: completeNudgeActionIdentifier,
                        title: "完成",
                        options: []
                    )
                ],
                intentIdentifiers: [],
                options: [.customDismissAction]
            )
        ]
    }

    static func categoryIdentifier(for targetType: ReminderTargetType) -> String {
        switch targetType {
        case .item:
            return taskCategoryIdentifier
        default:
            return genericCategoryIdentifier
        }
    }

    static func snoozeInterval(for actionIdentifier: String) -> TimeInterval? {
        switch actionIdentifier {
        case snoozeFiveMinutesIdentifier:
            return 5 * 60
        case snoozeTenMinutesIdentifier:
            return 10 * 60
        case snoozeThirtyMinutesIdentifier:
            return 30 * 60
        default:
            return nil
        }
    }
}
