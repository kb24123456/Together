import Foundation

protocol TaskMessageRepositoryProtocol: Sendable {
    func insertComment(
        messageID: UUID,
        taskID: UUID,
        senderID: UUID,
        content: String,
        createdAt: Date
    ) async throws

    func insertNudge(
        messageID: UUID,
        taskID: UUID,
        senderID: UUID,
        createdAt: Date
    ) async throws

    func fetchMessages(taskID: UUID, limit: Int, before cursor: TaskMessageCursor?) async throws -> [TaskMessage]
    func fetchLatestComments(taskIDs: [UUID]) async throws -> [UUID: TaskMessage]
    func fetchMessage(messageID: UUID) async throws -> TaskMessage?
    func markRead(taskID: UUID, through createdAt: Date) async throws
    func fetchReadState(taskID: UUID) async throws -> TaskChatReadState?
}
