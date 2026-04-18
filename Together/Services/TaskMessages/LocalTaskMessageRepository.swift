import Foundation
import SwiftData

actor LocalTaskMessageRepository: TaskMessageRepositoryProtocol {
    private let container: ModelContainer

    init(container: ModelContainer) {
        self.container = container
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
                type: "nudge",
                createdAt: createdAt
            )
        )
        try context.save()
    }

    func fetchMessage(messageID: UUID) async throws -> TaskMessage? {
        let context = ModelContext(container)
        let descriptor = FetchDescriptor<PersistentTaskMessage>(
            predicate: #Predicate<PersistentTaskMessage> { $0.id == messageID }
        )
        return try context.fetch(descriptor).first?.domainModel()
    }
}
