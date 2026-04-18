import Foundation
import SwiftData
import Testing
@testable import Together

@MainActor
struct PeriodicTaskRepositorySyncTests {
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

    private func makeTask(spaceID: UUID) -> PeriodicTask {
        PeriodicTask(
            id: UUID(),
            spaceID: spaceID,
            creatorID: UUID(),
            title: "每月体检",
            notes: nil,
            cycle: .monthly,
            reminderRules: [],
            completions: [],
            sortOrder: 0,
            isActive: true,
            createdAt: Date(),
            updatedAt: Date()
        )
    }

    @Test func saveTask_records_upsert() async throws {
        let container = try makeContainer()
        let spy = SpyCoordinator()
        let repo = LocalPeriodicTaskRepository(container: container, syncCoordinator: spy)

        let spaceID = UUID()
        let task = makeTask(spaceID: spaceID)
        _ = try await repo.saveTask(task)

        let recorded = await spy.recorded
        #expect(recorded.count == 1)
        #expect(recorded.first?.entityKind == .periodicTask)
        #expect(recorded.first?.operation == .upsert)
        #expect(recorded.first?.recordID == task.id)
        #expect(recorded.first?.spaceID == spaceID)
    }

    @Test func deleteTask_records_delete_and_tombstones() async throws {
        let container = try makeContainer()
        let spy = SpyCoordinator()
        let repo = LocalPeriodicTaskRepository(container: container, syncCoordinator: spy)

        let spaceID = UUID()
        let task = makeTask(spaceID: spaceID)
        _ = try await repo.saveTask(task)

        try await repo.deleteTask(taskID: task.id)

        let recorded = await spy.recorded
        let deletes = recorded.filter { $0.operation == .delete }
        #expect(deletes.count == 1)
        #expect(deletes.first?.entityKind == .periodicTask)
        #expect(deletes.first?.recordID == task.id)

        let context = ModelContext(container)
        let remaining = try context.fetch(FetchDescriptor<PersistentPeriodicTask>())
        #expect(remaining.count == 1)
        #expect(remaining.first?.isLocallyDeleted == true)
    }

    @Test func fetchActiveTasks_excludes_tombstones() async throws {
        let container = try makeContainer()
        let spy = SpyCoordinator()
        let repo = LocalPeriodicTaskRepository(container: container, syncCoordinator: spy)

        let spaceID = UUID()
        let task = makeTask(spaceID: spaceID)
        _ = try await repo.saveTask(task)
        try await repo.deleteTask(taskID: task.id)

        let active = try await repo.fetchActiveTasks(spaceID: spaceID)
        #expect(active.isEmpty)
    }
}
