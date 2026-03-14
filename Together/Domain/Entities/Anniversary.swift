import Foundation

enum AnniversaryKind: String, Hashable, Sendable {
    case relationshipStart
    case wedding
    case trip
    case custom
}

struct ReminderRule: Hashable, Sendable {
    var leadDays: Int
    var remindAtHour: Int
    var remindAtMinute: Int
}

struct Anniversary: Identifiable, Hashable, Sendable {
    let id: UUID
    var spaceID: UUID?
    var name: String
    var kind: AnniversaryKind
    var eventDate: Date
    var reminderRule: ReminderRule?
    let createdAt: Date
    var updatedAt: Date
}
