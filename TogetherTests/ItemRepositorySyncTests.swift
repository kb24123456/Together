import Foundation
import SwiftData
import Testing
@testable import Together

// MARK: - Test double for SyncCoordinatorProtocol

actor SpyCoordinator: SyncCoordinatorProtocol {
    private(set) var recorded: [SyncChange] = []

    func recordLocalChange(_ change: SyncChange) async {
        recorded.append(change)
    }

    func pendingChanges() async -> [SyncChange] { [] }

    func mutationLog(for spaceID: UUID) async -> [SyncMutationSnapshot] { [] }

    func clearPendingChanges(recordIDs: [UUID]) async {}

    func syncState(for spaceID: UUID) async -> SyncState? { nil }

    func markPushSuccess(
        for spaceID: UUID,
        cursor: SyncCursor?,
        clearedRecordIDs: [UUID],
        syncedAt: Date
    ) async {}

    func markSyncFailure(
        for spaceID: UUID,
        errorMessage: String,
        failedAt: Date
    ) async {}
}

// MARK: - Tests

@MainActor
struct ItemRepositorySyncTests {
    private func makeContainer() throws -> ModelContainer {
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
            configurations: config
        )
    }

    private func makeItem(id: UUID = UUID(), spaceID: UUID = UUID()) -> Item {
        Item(
            id: id,
            spaceID: spaceID,
            listID: nil,
            projectID: nil,
            creatorID: UUID(),
            title: "测试",
            notes: nil,
            locationText: nil,
            executionRole: .initiator,
            assigneeMode: .`self`,
            dueAt: nil,
            hasExplicitTime: false,
            remindAt: nil,
            status: .inProgress,
            assignmentState: .active,
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

    @Test func saveItem_records_upsert() async throws {
        let container = try makeContainer()
        let spy = SpyCoordinator()
        let repo = LocalItemRepository(container: container, syncCoordinator: spy)

        let spaceID = UUID()
        let item = makeItem(spaceID: spaceID)
        _ = try await repo.saveItem(item)

        let recorded = await spy.recorded
        #expect(recorded.count == 1)
        #expect(recorded.first?.entityKind == .task)
        #expect(recorded.first?.operation == .upsert)
        #expect(recorded.first?.recordID == item.id)
        #expect(recorded.first?.spaceID == spaceID)
    }

    @Test func deleteItem_records_delete_and_tombstones() async throws {
        let container = try makeContainer()
        let spy = SpyCoordinator()
        let repo = LocalItemRepository(container: container, syncCoordinator: spy)

        let spaceID = UUID()
        let item = makeItem(spaceID: spaceID)
        _ = try await repo.saveItem(item)

        try await repo.deleteItem(itemID: item.id)

        let recorded = await spy.recorded
        let deletes = recorded.filter { $0.operation == .delete }
        #expect(deletes.count == 1)
        #expect(deletes.first?.recordID == item.id)
        #expect(deletes.first?.spaceID == spaceID)

        // 本地记录被 tombstone 而非硬删，防止下次 pull 被复活
        let context = ModelContext(container)
        let remaining = try context.fetch(FetchDescriptor<PersistentItem>())
        #expect(remaining.count == 1)
        #expect(remaining.first?.isLocallyDeleted == true)
    }

    @Test func updateItemStatus_records_upsert() async throws {
        let container = try makeContainer()
        let spy = SpyCoordinator()
        let repo = LocalItemRepository(container: container, syncCoordinator: spy)

        let spaceID = UUID()
        let actorID = UUID()
        let item = makeItem(spaceID: spaceID)
        _ = try await repo.saveItem(item)

        _ = try await repo.updateItemStatus(
            itemID: item.id,
            response: nil,
            message: nil,
            actorID: actorID
        )

        let recorded = await spy.recorded
        let upserts = recorded.filter {
            $0.entityKind == .task && $0.operation == .upsert
        }
        #expect(upserts.count == 2, "saveItem + updateItemStatus each record .upsert")
        #expect(upserts.allSatisfy { $0.recordID == item.id })
        #expect(upserts.allSatisfy { $0.spaceID == spaceID })
    }

    @Test func markCompleted_records_complete() async throws {
        let container = try makeContainer()
        let spy = SpyCoordinator()
        let repo = LocalItemRepository(container: container, syncCoordinator: spy)

        let spaceID = UUID()
        let actorID = UUID()
        let item = makeItem(spaceID: spaceID)
        _ = try await repo.saveItem(item)

        _ = try await repo.markCompleted(itemID: item.id, actorID: actorID, referenceDate: Date())

        let recorded = await spy.recorded
        let completes = recorded.filter { $0.operation == .complete }
        #expect(completes.count == 1)
        #expect(completes.first?.entityKind == .task)
        #expect(completes.first?.recordID == item.id)
        #expect(completes.first?.spaceID == spaceID)
    }

    @Test func markIncomplete_records_upsert() async throws {
        let container = try makeContainer()
        let spy = SpyCoordinator()
        let repo = LocalItemRepository(container: container, syncCoordinator: spy)

        let spaceID = UUID()
        let actorID = UUID()
        let item = makeItem(spaceID: spaceID)
        _ = try await repo.saveItem(item)
        _ = try await repo.markCompleted(itemID: item.id, actorID: actorID, referenceDate: Date())

        _ = try await repo.markIncomplete(itemID: item.id, actorID: actorID, referenceDate: Date())

        let recorded = await spy.recorded
        // saveItem (.upsert) + markCompleted (.complete) + markIncomplete (.upsert)
        let taskUpserts = recorded.filter {
            $0.entityKind == .task && $0.operation == .upsert && $0.recordID == item.id
        }
        #expect(taskUpserts.count == 2, "saveItem + markIncomplete each record .upsert")
    }
}
