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
            PersistentTaskChatReadState.self,
            PersistentImportantDate.self,
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
        #expect(fetched?.type == .nudge)
    }

    @Test func domainModel_withUnknownStoredType_returnsUnknownType() throws {
        let persistent = PersistentTaskMessage(
            id: UUID(),
            taskID: UUID(),
            senderID: UUID(),
            type: "future_type",
            createdAt: Date()
        )

        let message = persistent.domainModel()

        #expect(message.type == .unknown)
    }

    @Test func insertComment_trimsAndPersistsContentAndType() async throws {
        let container = try makeContainer()
        let repo = LocalTaskMessageRepository(container: container)

        let messageID = UUID()
        let taskID = UUID()
        let senderID = UUID()
        let createdAt = Date()

        try await repo.insertComment(
            messageID: messageID,
            taskID: taskID,
            senderID: senderID,
            content: "  买低脂牛奶\n",
            createdAt: createdAt
        )

        let context = ModelContext(container)
        let fetched = try #require(try context.fetch(FetchDescriptor<PersistentTaskMessage>()).first)
        #expect(fetched.id == messageID)
        #expect(fetched.taskID == taskID)
        #expect(fetched.senderID == senderID)
        #expect(fetched.type == TaskMessageType.comment.rawValue)
        #expect(fetched.content == "买低脂牛奶")
    }

    @Test func insertComment_emptyContentDoesNotInsert() async throws {
        let container = try makeContainer()
        let repo = LocalTaskMessageRepository(container: container)
        let context = ModelContext(container)

        try await repo.insertComment(
            messageID: UUID(),
            taskID: UUID(),
            senderID: UUID(),
            content: " \n\t ",
            createdAt: Date()
        )

        let fetched = try context.fetch(FetchDescriptor<PersistentTaskMessage>())
        #expect(fetched.isEmpty)
    }

    @Test func fetchMessages_returnsLimitedAscendingPageBeforeCutoff() async throws {
        let container = try makeContainer()
        let repo = LocalTaskMessageRepository(container: container)
        let taskID = UUID()
        let otherTaskID = UUID()
        let senderID = UUID()
        let firstID = try #require(UUID(uuidString: "00000000-0000-0000-0000-000000000001"))
        let secondID = try #require(UUID(uuidString: "00000000-0000-0000-0000-000000000002"))
        let thirdID = try #require(UUID(uuidString: "00000000-0000-0000-0000-000000000003"))
        let fourthID = try #require(UUID(uuidString: "00000000-0000-0000-0000-000000000004"))
        let base = Date(timeIntervalSince1970: 1_800)

        try await repo.insertComment(
            messageID: firstID,
            taskID: taskID,
            senderID: senderID,
            content: "first",
            createdAt: base
        )
        try await repo.insertNudge(
            messageID: secondID,
            taskID: taskID,
            senderID: senderID,
            createdAt: base.addingTimeInterval(10)
        )
        try await repo.insertComment(
            messageID: thirdID,
            taskID: taskID,
            senderID: senderID,
            content: "third",
            createdAt: base.addingTimeInterval(20)
        )
        try await repo.insertComment(
            messageID: fourthID,
            taskID: taskID,
            senderID: senderID,
            content: "fourth",
            createdAt: base.addingTimeInterval(30)
        )
        try await repo.insertComment(
            messageID: UUID(),
            taskID: otherTaskID,
            senderID: senderID,
            content: "other",
            createdAt: base.addingTimeInterval(25)
        )

        let fetched = try await repo.fetchMessages(
            taskID: taskID,
            limit: 2,
            before: TaskMessageCursor(createdAt: base.addingTimeInterval(30), id: fourthID)
        )

        #expect(fetched.map(\.id) == [secondID, thirdID])
    }

    @Test func fetchMessages_pagesTiedTimestampsWithoutSkippingIDs() async throws {
        let container = try makeContainer()
        let repo = LocalTaskMessageRepository(container: container)
        let taskID = UUID()
        let senderID = UUID()
        let sharedCreatedAt = Date(timeIntervalSince1970: 2_000)
        let ids = try [
            #require(UUID(uuidString: "00000000-0000-0000-0000-000000000001")),
            #require(UUID(uuidString: "00000000-0000-0000-0000-000000000002")),
            #require(UUID(uuidString: "00000000-0000-0000-0000-000000000003")),
            #require(UUID(uuidString: "00000000-0000-0000-0000-000000000004")),
            #require(UUID(uuidString: "00000000-0000-0000-0000-000000000005"))
        ]

        for id in ids {
            try await repo.insertComment(
                messageID: id,
                taskID: taskID,
                senderID: senderID,
                content: id.uuidString,
                createdAt: sharedCreatedAt
            )
        }

        let latestPage = try await repo.fetchMessages(taskID: taskID, limit: 2, before: nil)
        let nextPage = try await repo.fetchMessages(
            taskID: taskID,
            limit: 2,
            before: TaskMessageCursor(message: try #require(latestPage.first))
        )
        let finalPage = try await repo.fetchMessages(
            taskID: taskID,
            limit: 2,
            before: TaskMessageCursor(message: try #require(nextPage.first))
        )

        #expect(latestPage.map(\.id) == [ids[3], ids[4]])
        #expect(nextPage.map(\.id) == [ids[1], ids[2]])
        #expect(finalPage.map(\.id) == [ids[0]])
        #expect((latestPage + nextPage + finalPage).map(\.id).sorted() == ids)
    }

    @Test func fetchLatestComments_returnsNewestCommentPerTask() async throws {
        let container = try makeContainer()
        let repo = LocalTaskMessageRepository(container: container)
        let firstTaskID = UUID()
        let secondTaskID = UUID()
        let senderID = UUID()
        let oldCommentID = UUID()
        let tiedOlderCommentID = try #require(UUID(uuidString: "00000000-0000-0000-0000-000000000010"))
        let tiedLatestCommentID = try #require(UUID(uuidString: "00000000-0000-0000-0000-000000000011"))
        let secondTaskCommentID = UUID()
        let base = Date(timeIntervalSince1970: 2_000)

        try await repo.insertComment(
            messageID: oldCommentID,
            taskID: firstTaskID,
            senderID: senderID,
            content: "old",
            createdAt: base
        )
        try await repo.insertNudge(
            messageID: UUID(),
            taskID: firstTaskID,
            senderID: senderID,
            createdAt: base.addingTimeInterval(20)
        )
        try await repo.insertComment(
            messageID: tiedOlderCommentID,
            taskID: firstTaskID,
            senderID: senderID,
            content: "tied older",
            createdAt: base.addingTimeInterval(10)
        )
        try await repo.insertComment(
            messageID: tiedLatestCommentID,
            taskID: firstTaskID,
            senderID: senderID,
            content: "tied latest",
            createdAt: base.addingTimeInterval(10)
        )
        try await repo.insertComment(
            messageID: secondTaskCommentID,
            taskID: secondTaskID,
            senderID: senderID,
            content: "second",
            createdAt: base.addingTimeInterval(5)
        )

        let fetched = try await repo.fetchLatestComments(taskIDs: [firstTaskID, secondTaskID])

        #expect(fetched[firstTaskID]?.id == tiedLatestCommentID)
        #expect(fetched[firstTaskID]?.content == "tied latest")
        #expect(fetched[secondTaskID]?.id == secondTaskCommentID)
    }

    @Test func markRead_keepsLatestReadCreatedAt() async throws {
        let container = try makeContainer()
        let repo = LocalTaskMessageRepository(container: container)
        let taskID = UUID()
        let earlier = Date(timeIntervalSince1970: 2_000)
        let later = Date(timeIntervalSince1970: 3_000)

        try await repo.markRead(taskID: taskID, through: later)
        try await repo.markRead(taskID: taskID, through: earlier)

        let fetched = try #require(try await repo.fetchReadState(taskID: taskID))
        #expect(fetched.taskID == taskID)
        #expect(fetched.lastReadMessageCreatedAt == later)
    }

    @Test func readState_persistsLastReadCreatedAt() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let taskID = UUID()
        let readAt = Date()

        context.insert(PersistentTaskChatReadState(taskID: taskID, lastReadMessageCreatedAt: readAt, updatedAt: readAt))
        try context.save()

        let fetched = try #require(try context.fetch(FetchDescriptor<PersistentTaskChatReadState>()).first)
        #expect(fetched.taskID == taskID)
        #expect(fetched.lastReadMessageCreatedAt == readAt)
    }
}
