import Foundation

enum TaskMessageType: String, Codable, Hashable, Sendable {
    case comment
    case nudge
    case rpsResult = "rps_result"
    case unknown
}

struct TaskMessage: Identifiable, Hashable, Sendable {
    let id: UUID
    let taskID: UUID
    let senderID: UUID
    let type: TaskMessageType
    let content: String?
    let createdAt: Date
}

struct TaskMessageCursor: Hashable, Sendable {
    let createdAt: Date
    let id: UUID

    init(createdAt: Date, id: UUID) {
        self.createdAt = createdAt
        self.id = id
    }

    init(message: TaskMessage) {
        self.init(createdAt: message.createdAt, id: message.id)
    }
}

struct TaskChatReadState: Hashable, Sendable {
    let taskID: UUID
    let lastReadMessageCreatedAt: Date
    let updatedAt: Date
}
