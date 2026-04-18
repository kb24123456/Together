import Foundation
import SwiftData
import Testing
@testable import Together

@MainActor
struct TaskMessageRepositoryTests {
    private func makeContainer() throws -> ModelContainer {
        let config = ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        return try ModelContainer(
            for: PersistentUserProfile.self, PersistentSpace.self, PersistentPairSpace.self,
            PersistentPairMembership.self, PersistentInvite.self, PersistentTaskList.self,
            PersistentProject.self, PersistentProjectSubtask.self, PersistentItem.self,
            PersistentItemOccurrenceCompletion.self, PersistentTaskTemplate.self,
            PersistentSyncChange.self, PersistentSyncState.self, PersistentPeriodicTask.self,
            PersistentPairingHistory.self, PersistentTaskMessage.self,
            configurations: config
        )
    }

    @Test func insertNudge_persistsRowWithTypeNudge() async throws {
        let container = try makeContainer()
        let repo = LocalTaskMessageRepository(container: container)

        let messageID = UUID()
        let taskID = UUID()
        let senderID = UUID()
        let createdAt = Date()

        try await repo.insertNudge(
            messageID: messageID,
            taskID: taskID,
            senderID: senderID,
            createdAt: createdAt
        )

        let context = ModelContext(container)
        let fetched = try context.fetch(FetchDescriptor<PersistentTaskMessage>())
        #expect(fetched.count == 1)
        #expect(fetched.first?.id == messageID)
        #expect(fetched.first?.taskID == taskID)
        #expect(fetched.first?.senderID == senderID)
        #expect(fetched.first?.type == "nudge")
    }

    @Test func fetchMessage_returnsInsertedRow() async throws {
        let container = try makeContainer()
        let repo = LocalTaskMessageRepository(container: container)

        let messageID = UUID()
        try await repo.insertNudge(
            messageID: messageID,
            taskID: UUID(),
            senderID: UUID(),
            createdAt: Date()
        )

        let fetched = try await repo.fetchMessage(messageID: messageID)
        #expect(fetched?.id == messageID)
        #expect(fetched?.type == "nudge")
    }
}
