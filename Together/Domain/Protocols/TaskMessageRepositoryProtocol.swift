import Foundation

protocol TaskMessageRepositoryProtocol: Sendable {
    func insertNudge(
        messageID: UUID,
        taskID: UUID,
        senderID: UUID,
        createdAt: Date
    ) async throws

    func fetchMessage(messageID: UUID) async throws -> TaskMessage?
}
