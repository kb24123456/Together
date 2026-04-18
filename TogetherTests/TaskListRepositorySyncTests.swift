import Foundation
import SwiftData
import Testing
@testable import Together

@MainActor
struct TaskListRepositorySyncTests {
    private func makeContainer() throws -> ModelContainer {
        let config = ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        return try ModelContainer(
            for: PersistentUserProfile.self, PersistentSpace.self, PersistentPairSpace.self,
            PersistentPairMembership.self, PersistentInvite.self, PersistentTaskList.self,
            PersistentProject.self, PersistentProjectSubtask.self, PersistentItem.self,
            PersistentItemOccurrenceCompletion.self, PersistentTaskTemplate.self,
            PersistentSyncChange.self, PersistentSyncState.self, PersistentPeriodicTask.self,
            PersistentPairingHistory.self,
            configurations: config
        )
    }

    private func makeTaskList(spaceID: UUID, actorID: UUID) -> TaskList {
        TaskList(
            id: UUID(),
            spaceID: spaceID,
            creatorID: actorID,
            name: "测试列表",
            kind: .custom,
            colorToken: nil,
            sortOrder: 0,
            isArchived: false,
            taskCount: 0,
            createdAt: Date(),
            updatedAt: Date()
        )
    }

    @Test func saveTaskList_records_upsert() async throws {
        let container = try makeContainer()
        let spy = SpyCoordinator()
        let repo = LocalTaskListRepository(container: container, syncCoordinator: spy)

        let spaceID = UUID()
        let actorID = UUID()
        let list = makeTaskList(spaceID: spaceID, actorID: actorID)
        _ = try await repo.saveTaskList(list, actorID: actorID)

        let recorded = await spy.recorded
        #expect(recorded.count == 1)
        #expect(recorded.first?.entityKind == .taskList)
        #expect(recorded.first?.operation == .upsert)
        #expect(recorded.first?.recordID == list.id)
        #expect(recorded.first?.spaceID == spaceID)
    }

    @Test func saveTaskList_after_tombstone_resurrects_record() async throws {
        let container = try makeContainer()
        let spy = SpyCoordinator()
        let repo = LocalTaskListRepository(container: container, syncCoordinator: spy)

        let spaceID = UUID()
        let actorID = UUID()
        let list = makeTaskList(spaceID: spaceID, actorID: actorID)
        _ = try await repo.saveTaskList(list, actorID: actorID)

        // Simulate tombstone via direct SwiftData mutation
        let context = ModelContext(container)
        let records = try context.fetch(FetchDescriptor<PersistentTaskList>())
        records.first?.isLocallyDeleted = true
        try context.save()

        // Re-save should clear the tombstone
        _ = try await repo.saveTaskList(list, actorID: actorID)

        let context2 = ModelContext(container)
        let remaining = try context2.fetch(FetchDescriptor<PersistentTaskList>())
        #expect(remaining.count == 1)
        #expect(remaining.first?.isLocallyDeleted == false, "re-save should clear tombstone")
    }

    @Test func archiveTaskList_records_archive() async throws {
        let container = try makeContainer()
        let spy = SpyCoordinator()
        let repo = LocalTaskListRepository(container: container, syncCoordinator: spy)

        let spaceID = UUID()
        let actorID = UUID()
        let list = makeTaskList(spaceID: spaceID, actorID: actorID)
        _ = try await repo.saveTaskList(list, actorID: actorID)

        _ = try await repo.archiveTaskList(listID: list.id, actorID: actorID)

        let recorded = await spy.recorded
        let archives = recorded.filter { $0.operation == .archive }
        #expect(archives.count == 1)
        #expect(archives.first?.entityKind == .taskList)
        #expect(archives.first?.recordID == list.id)
        #expect(archives.first?.spaceID == spaceID)
    }

    @Test func fetchTaskLists_excludes_tombstones() async throws {
        let container = try makeContainer()
        let spy = SpyCoordinator()
        let repo = LocalTaskListRepository(container: container, syncCoordinator: spy)

        let spaceID = UUID()
        let actorID = UUID()
        let list = makeTaskList(spaceID: spaceID, actorID: actorID)
        _ = try await repo.saveTaskList(list, actorID: actorID)

        // Simulate tombstone via direct SwiftData mutation
        let context = ModelContext(container)
        let records = try context.fetch(FetchDescriptor<PersistentTaskList>())
        records.first?.isLocallyDeleted = true
        try context.save()

        let fetched = try await repo.fetchTaskLists(spaceID: spaceID)
        #expect(fetched.isEmpty, "tombstoned list must not appear in fetchTaskLists")
    }
}
