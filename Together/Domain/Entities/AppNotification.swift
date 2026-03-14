import Foundation

struct AppNotification: Identifiable, Hashable, Sendable {
    let id: UUID
    var spaceID: UUID?
    var targetID: UUID
    var targetType: ReminderTargetType
    var channel: ReminderChannel
    var status: ReminderDeliveryStatus
    var title: String
    var body: String
    var scheduledAt: Date
    var deliveredAt: Date?
}
