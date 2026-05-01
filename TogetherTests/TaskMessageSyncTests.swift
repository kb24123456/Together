import Foundation
import SwiftData
import Testing
@testable import Together

@MainActor
struct TaskMessageSyncTests {
    @Test func pullDTOIgnoresEmbeddedTaskJoinAndDecodesContent() throws {
        let json = """
        {
          "id": "11111111-1111-1111-1111-111111111111",
          "task_id": "22222222-2222-2222-2222-222222222222",
          "sender_id": "33333333-3333-3333-3333-333333333333",
          "sender_supabase_user_id": "44444444-4444-4444-4444-444444444444",
          "type": "comment",
          "content": "买低脂牛奶",
          "created_at": "2023-11-14T22:13:20Z",
          "tasks": { "space_id": "55555555-5555-5555-5555-555555555555" }
        }
        """

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let dto = try decoder.decode(TaskMessagePullDTO.self, from: Data(json.utf8))

        #expect(dto.id == UUID(uuidString: "11111111-1111-1111-1111-111111111111"))
        #expect(dto.taskId == UUID(uuidString: "22222222-2222-2222-2222-222222222222"))
        #expect(dto.senderId == UUID(uuidString: "33333333-3333-3333-3333-333333333333"))
        #expect(dto.senderSupabaseUserID == UUID(uuidString: "44444444-4444-4444-4444-444444444444"))
        #expect(dto.type == TaskMessageType.comment.rawValue)
        #expect(dto.content == "买低脂牛奶")
    }

    @Test func pullDTOAppliesInsertAndUpdateToLocalStore() throws {
        let container = try makeInMemoryContainer()
        let context = ModelContext(container)
        let messageID = UUID()
        let taskID = UUID()
        let originalSenderID = UUID()
        let updatedSenderID = UUID()
        let originalDate = Date(timeIntervalSince1970: 1_700_000_000)
        let updatedDate = Date(timeIntervalSince1970: 1_700_000_100)

        TaskMessagePullDTO(
            id: messageID,
            taskId: taskID,
            senderId: originalSenderID,
            senderSupabaseUserID: nil,
            type: TaskMessageType.comment.rawValue,
            content: "first",
            createdAt: originalDate
        ).applyToLocal(context: context)
        try context.save()

        TaskMessagePullDTO(
            id: messageID,
            taskId: taskID,
            senderId: updatedSenderID,
            senderSupabaseUserID: nil,
            type: TaskMessageType.comment.rawValue,
            content: "updated",
            createdAt: updatedDate
        ).applyToLocal(context: context)
        try context.save()

        let rows = try context.fetch(FetchDescriptor<PersistentTaskMessage>())
        #expect(rows.count == 1)
        #expect(rows.first?.id == messageID)
        #expect(rows.first?.taskID == taskID)
        #expect(rows.first?.senderID == updatedSenderID)
        #expect(rows.first?.type == TaskMessageType.comment.rawValue)
        #expect(rows.first?.content == "updated")
        #expect(rows.first?.createdAt == updatedDate)
    }

    private func makeInMemoryContainer() throws -> ModelContainer {
        let config = ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        return try ModelContainer(
            for: PersistentUserProfile.self,
            PersistentSpace.self,
            PersistentPairSpace.self,
            PersistentPairMembership.self,
            PersistentInvite.self,
            PersistentTaskList.self,
            PersistentProject.self,
            PersistentProjectSubtask.self,
            PersistentItem.self,
            PersistentItemOccurrenceCompletion.self,
            PersistentTaskTemplate.self,
            PersistentSyncChange.self,
            PersistentSyncState.self,
            PersistentPeriodicTask.self,
            PersistentPairingHistory.self,
            PersistentTaskMessage.self,
            PersistentTaskChatReadState.self,
            PersistentImportantDate.self,
            configurations: config
        )
    }
}
