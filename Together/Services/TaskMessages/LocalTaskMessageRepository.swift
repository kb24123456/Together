import Foundation
import SwiftData

actor LocalTaskMessageRepository: TaskMessageRepositoryProtocol {
    private let container: ModelContainer

    init(container: ModelContainer) {
        self.container = container
    }

    func insertComment(
        messageID: UUID,
        taskID: UUID,
        senderID: UUID,
        content: String,
        createdAt: Date
    ) async throws {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else { return }

        let context = ModelContext(container)
        context.insert(
            PersistentTaskMessage(
                id: messageID,
                taskID: taskID,
                senderID: senderID,
                type: TaskMessageType.comment.rawValue,
                content: trimmed,
                createdAt: createdAt
            )
        )
        try context.save()
    }

    func insertNudge(
        messageID: UUID,
        taskID: UUID,
        senderID: UUID,
        createdAt: Date
    ) async throws {
        let context = ModelContext(container)
        context.insert(
            PersistentTaskMessage(
                id: messageID,
                taskID: taskID,
                senderID: senderID,
                type: TaskMessageType.nudge.rawValue,
                content: nil,
                createdAt: createdAt
            )
        )
        try context.save()
    }

    func fetchMessages(taskID: UUID, limit: Int, before cursor: TaskMessageCursor?) async throws -> [TaskMessage] {
        let context = ModelContext(container)
        let effectiveLimit = max(1, min(limit, 100))
        let descriptor: FetchDescriptor<PersistentTaskMessage>

        if let cursor {
            let cursorCreatedAt = cursor.createdAt
            let cursorID = cursor.id
            descriptor = FetchDescriptor<PersistentTaskMessage>(
                predicate: #Predicate<PersistentTaskMessage> { message in
                    message.taskID == taskID
                        && (message.createdAt < cursorCreatedAt || (message.createdAt == cursorCreatedAt && message.id < cursorID))
                },
                sortBy: [
                    SortDescriptor(\.createdAt, order: .reverse),
                    SortDescriptor(\.id, order: .reverse)
                ]
            )
        } else {
            descriptor = FetchDescriptor<PersistentTaskMessage>(
                predicate: #Predicate<PersistentTaskMessage> { message in
                    message.taskID == taskID
                },
                sortBy: [
                    SortDescriptor(\.createdAt, order: .reverse),
                    SortDescriptor(\.id, order: .reverse)
                ]
            )
        }

        var limited = descriptor
        limited.fetchLimit = effectiveLimit

        return try context.fetch(limited)
            .map { $0.domainModel() }
            .sorted { lhs, rhs in
                if lhs.createdAt == rhs.createdAt {
                    return lhs.id < rhs.id
                }
                return lhs.createdAt < rhs.createdAt
            }
    }

    func fetchLatestComments(taskIDs: [UUID]) async throws -> [UUID: TaskMessage] {
        guard taskIDs.isEmpty == false else { return [:] }

        let commentType = TaskMessageType.comment.rawValue
        let context = ModelContext(container)
        var result: [UUID: TaskMessage] = [:]
        for taskID in Set(taskIDs) {
            var descriptor = FetchDescriptor<PersistentTaskMessage>(
                predicate: #Predicate<PersistentTaskMessage> { message in
                    message.taskID == taskID && message.type == commentType
                },
                sortBy: [
                    SortDescriptor(\.createdAt, order: .reverse),
                    SortDescriptor(\.id, order: .reverse)
                ]
            )
            descriptor.fetchLimit = 1
            if let message = try context.fetch(descriptor).first {
                result[taskID] = message.domainModel()
            }
        }
        return result
    }

    func fetchMessage(messageID: UUID) async throws -> TaskMessage? {
        let context = ModelContext(container)
        let descriptor = FetchDescriptor<PersistentTaskMessage>(
            predicate: #Predicate<PersistentTaskMessage> { $0.id == messageID }
        )
        return try context.fetch(descriptor).first?.domainModel()
    }

    func markRead(taskID: UUID, through createdAt: Date) async throws {
        let context = ModelContext(container)
        let descriptor = FetchDescriptor<PersistentTaskChatReadState>(
            predicate: #Predicate<PersistentTaskChatReadState> { $0.taskID == taskID }
        )

        if let existing = try context.fetch(descriptor).first {
            existing.lastReadMessageCreatedAt = max(existing.lastReadMessageCreatedAt, createdAt)
            existing.updatedAt = Date()
        } else {
            context.insert(
                PersistentTaskChatReadState(
                    taskID: taskID,
                    lastReadMessageCreatedAt: createdAt,
                    updatedAt: Date()
                )
            )
        }

        try context.save()
    }

    func fetchReadState(taskID: UUID) async throws -> TaskChatReadState? {
        let context = ModelContext(container)
        let descriptor = FetchDescriptor<PersistentTaskChatReadState>(
            predicate: #Predicate<PersistentTaskChatReadState> { $0.taskID == taskID }
        )

        return try context.fetch(descriptor).first.map {
            TaskChatReadState(
                taskID: $0.taskID,
                lastReadMessageCreatedAt: $0.lastReadMessageCreatedAt,
                updatedAt: $0.updatedAt
            )
        }
    }
}
