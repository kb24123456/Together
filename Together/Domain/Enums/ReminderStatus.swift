import Foundation

enum ReminderTargetType: String, Hashable, Sendable {
    case item
    case project
    case decision
    case anniversary
    case invite
    case binding
    case periodicTask
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
