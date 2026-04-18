import Foundation
import SwiftData

@Model
final class PersistentTaskMessage {
    var id: UUID
    var taskID: UUID
    var senderID: UUID
    var type: String
    var createdAt: Date

    init(
        id: UUID,
        taskID: UUID,
        senderID: UUID,
        type: String,
        createdAt: Date
    ) {
        self.id = id
        self.taskID = taskID
        self.senderID = senderID
        self.type = type
        self.createdAt = createdAt
    }
}

extension PersistentTaskMessage {
    convenience init(message: TaskMessage) {
        self.init(
            id: message.id,
            taskID: message.taskID,
            senderID: message.senderID,
            type: message.type,
            createdAt: message.createdAt
        )
    }

    func domainModel() -> TaskMessage {
        TaskMessage(
            id: id,
            taskID: taskID,
            senderID: senderID,
            type: type,
            createdAt: createdAt
        )
    }
}
