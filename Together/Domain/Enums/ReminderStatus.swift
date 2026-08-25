import Foundation

enum ReminderTargetType: String, Hashable, Sendable {
    case item
    case project
    case periodicTask
    /// Kept so upgrades can remove the single 18:00 summary request used by older builds.
    case dailySummary
    case dailyMorningSummary
    case dailyEveningSummary

    nonisolated var isDailySummary: Bool {
        switch self {
        case .dailySummary, .dailyMorningSummary, .dailyEveningSummary:
            return true
        case .item, .project, .periodicTask:
            return false
        }
    }
}

enum NotificationRecurrence: Hashable, Sendable {
    case none
    case daily
}

enum ReminderChannel: String, Hashable, Sendable {
    case localNotification
    case inApp
}

enum ReminderDeliveryStatus: String, Hashable, Sendable {
    case draft
    case scheduled
    case delivered
    case cancelled
    case failed
}
