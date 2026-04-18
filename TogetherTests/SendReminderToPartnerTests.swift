import Foundation
import SwiftData
import Testing
@testable import Together

@MainActor
struct SendReminderToPartnerTests {
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

    private func makePartnerItem(spaceID: UUID, actorID: UUID) -> Item {
        Item(
            id: UUID(),
            spaceID: spaceID,
            listID: nil,
            projectID: nil,
            creatorID: actorID,
            title: "倒垃圾",
            notes: nil,
            locationText: nil,
            executionRole: .initiator,
            assigneeMode: .partner,
            dueAt: nil,
            hasExplicitTime: false,
            remindAt: nil,
            status: .inProgress,
            assignmentState: .pendingResponse,
            latestResponse: nil,
            responseHistory: [],
            assignmentMessages: [],
            lastActionByUserID: nil,
            lastActionAt: nil,
            createdAt: Date(),
            updatedAt: Date(),
            completedAt: nil,
            occurrenceCompletions: [],
            isPinned: false,
            isDraft: false,
            isArchived: false,
            archivedAt: nil,
            repeatRule: nil,
            reminderRequestedAt: nil
        )
    }

    @Test func sendReminder_recordsTaskUpsertAndTaskMessageUpsert() async throws {
        let container = try makeContainer()
        let spy = SpyCoordinator()
        let itemRepo = LocalItemRepository(container: container, syncCoordinator: spy)
        let messageRepo = LocalTaskMessageRepository(container: container)
        let scheduler = NoopReminderScheduler()
        let service = DefaultTaskApplicationService(
            itemRepository: itemRepo,
            taskMessageRepository: messageRepo,
            syncCoordinator: spy,
            reminderScheduler: scheduler
        )

        let spaceID = UUID()
        let actorID = UUID()
        let item = makePartnerItem(spaceID: spaceID, actorID: actorID)
        _ = try await itemRepo.saveItem(item)

        _ = try await service.sendReminderToPartner(in: spaceID, taskID: item.id, actorID: actorID)

        let recorded = await spy.recorded
        let taskUpserts = recorded.filter { $0.entityKind == .task && $0.operation == .upsert && $0.recordID == item.id }
        let nudgeRecords = recorded.filter { $0.entityKind == .taskMessage && $0.operation == .upsert && $0.spaceID == spaceID }

        #expect(taskUpserts.count >= 1, "saveItem bumps reminder_requested_at → task .upsert recorded")
        #expect(nudgeRecords.count == 1, "exactly one task_message .upsert recorded")
    }

    @Test func sendReminder_withinCooldown_doesNotInsertSecondMessage() async throws {
        let container = try makeContainer()
        let spy = SpyCoordinator()
        let itemRepo = LocalItemRepository(container: container, syncCoordinator: spy)
        let messageRepo = LocalTaskMessageRepository(container: container)
        let service = DefaultTaskApplicationService(
            itemRepository: itemRepo,
            taskMessageRepository: messageRepo,
            syncCoordinator: spy,
            reminderScheduler: NoopReminderScheduler()
        )

        let spaceID = UUID()
        let actorID = UUID()
        let item = makePartnerItem(spaceID: spaceID, actorID: actorID)
        _ = try await itemRepo.saveItem(item)

        _ = try await service.sendReminderToPartner(in: spaceID, taskID: item.id, actorID: actorID)
        _ = try await service.sendReminderToPartner(in: spaceID, taskID: item.id, actorID: actorID)

        let context = ModelContext(container)
        let messages = try context.fetch(FetchDescriptor<PersistentTaskMessage>())
        #expect(messages.count == 1, "second tap within 30s cooldown is a no-op")
    }
}
