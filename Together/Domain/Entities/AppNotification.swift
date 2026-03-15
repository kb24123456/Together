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

    nonisolated var identifier: String {
        Self.identifier(for: targetType, targetID: targetID)
    }
}

extension AppNotification {
    nonisolated static func identifier(for targetType: ReminderTargetType, targetID: UUID) -> String {
        "local.\(targetType.rawValue).\(targetID.uuidString)"
    }

    nonisolated static func parseIdentifier(_ identifier: String) -> (targetType: ReminderTargetType, targetID: UUID)? {
        let components = identifier.split(separator: ".", omittingEmptySubsequences: false)
        guard components.count == 3, components[0] == "local" else {
            return nil
        }
        guard
            let targetType = ReminderTargetType(rawValue: String(components[1])),
            let targetID = UUID(uuidString: String(components[2]))
        else {
            return nil
        }
        return (targetType, targetID)
    }
}
