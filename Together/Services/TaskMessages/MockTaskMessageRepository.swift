import Foundation

actor MockTaskMessageRepository: TaskMessageRepositoryProtocol {
    private var messages: [TaskMessage] = []
    private var readStates: [UUID: TaskChatReadState] = [:]

    func insertComment(
        messageID: UUID,
        taskID: UUID,
        senderID: UUID,
        content: String,
        createdAt: Date
    ) async throws {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else { return }

        messages.append(
            TaskMessage(
                id: messageID,
                taskID: taskID,
                senderID: senderID,
                type: .comment,
                content: trimmed,
                createdAt: createdAt
            )
        )
    }

    func insertNudge(messageID: UUID, taskID: UUID, senderID: UUID, createdAt: Date) async throws {
        messages.append(
            TaskMessage(
                id: messageID,
                taskID: taskID,
                senderID: senderID,
                type: .nudge,
                content: nil,
                createdAt: createdAt
            )
        )
    }

    func fetchMessages(taskID: UUID, limit: Int, before cursor: TaskMessageCursor?) async throws -> [TaskMessage] {
        let effectiveLimit = max(1, min(limit, 100))

        return Array(
            messages
                .filter { message in
                    message.taskID == taskID
                        && cursor.map { Self.isOlder(message, than: $0) } ?? true
                }
                .sorted { lhs, rhs in
                    if lhs.createdAt == rhs.createdAt {
                        return lhs.id > rhs.id
                    }
                    return lhs.createdAt > rhs.createdAt
                }
                .prefix(effectiveLimit)
                .sorted { lhs, rhs in
                    if lhs.createdAt == rhs.createdAt {
                        return lhs.id < rhs.id
                    }
                    return lhs.createdAt < rhs.createdAt
                }
        )
    }

    func fetchLatestComments(taskIDs: [UUID]) async throws -> [UUID: TaskMessage] {
        guard taskIDs.isEmpty == false else { return [:] }

        let taskIDSet = Set(taskIDs)
        var result: [UUID: TaskMessage] = [:]
        for message in messages
            .filter({ taskIDSet.contains($0.taskID) && $0.type == .comment })
            .sorted(by: { lhs, rhs in
                if lhs.createdAt == rhs.createdAt {
                    return lhs.id > rhs.id
                }
                return lhs.createdAt > rhs.createdAt
            }) where result.keys.contains(message.taskID) == false {
            result[message.taskID] = message
        }
        return result
    }

    func fetchMessage(messageID: UUID) async throws -> TaskMessage? {
        messages.first { $0.id == messageID }
    }

    func markRead(taskID: UUID, through createdAt: Date) async throws {
        if let existing = readStates[taskID] {
            readStates[taskID] = TaskChatReadState(
                taskID: taskID,
                lastReadMessageCreatedAt: max(existing.lastReadMessageCreatedAt, createdAt),
                updatedAt: Date()
            )
        } else {
            readStates[taskID] = TaskChatReadState(
                taskID: taskID,
                lastReadMessageCreatedAt: createdAt,
                updatedAt: Date()
            )
        }
    }

    func fetchReadState(taskID: UUID) async throws -> TaskChatReadState? {
        readStates[taskID]
    }

    nonisolated private static func isOlder(_ message: TaskMessage, than cursor: TaskMessageCursor) -> Bool {
        message.createdAt < cursor.createdAt
            || (message.createdAt == cursor.createdAt && message.id < cursor.id)
    }
}
