import Foundation
import SwiftData
import Testing
@testable import Together

// MARK: - NoopReminderScheduler

actor NoopReminderScheduler: ReminderSchedulerProtocol {
    func syncTaskReminder(for item: Item) async {}
    func removeTaskReminder(for itemID: UUID) async {}
    func snoozeTaskReminder(itemID: UUID, title: String, body: String, delay: TimeInterval) async {}
    func syncProjectReminder(for project: Project) async {}
    func removeProjectReminder(for projectID: UUID) async {}
    func resync(tasks: [Item], projects: [Project]) async {}
    func syncPeriodicTaskReminder(for task: PeriodicTask, referenceDate: Date) async {}
    func removePeriodicTaskReminder(for taskID: UUID) async {}
}

// MARK: - Tests

@MainActor
struct ProjectSubtaskRepositorySyncTests {
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

    private func makeProject(spaceID: UUID, creatorID: UUID) -> Project {
        Project(
            id: UUID(),
            spaceID: spaceID,
            creatorID: creatorID,
            name: "项目 A",
            notes: nil,
            colorToken: nil,
            status: .active,
            targetDate: nil,
            remindAt: nil,
            taskCount: 0,
            subtasks: [],
            createdAt: Date(),
            updatedAt: Date(),
            completedAt: nil
        )
    }

    @Test func addSubtask_records_upsert() async throws {
        let container = try makeContainer()
        let spy = SpyCoordinator()
        let scheduler = NoopReminderScheduler()
        let repo = LocalProjectRepository(
            container: container,
            reminderScheduler: scheduler,
            syncCoordinator: spy
        )

        let spaceID = UUID()
        let actorID = UUID()
        let project = makeProject(spaceID: spaceID, creatorID: actorID)
        _ = try await repo.saveProject(project, actorID: actorID)

        let withSubtask = try await repo.addSubtask(
            projectID: project.id, title: "步骤一", isCompleted: false,
            creatorID: actorID, actorID: actorID
        )
        let subtaskID = withSubtask.subtasks.first!.id

        let recorded = await spy.recorded
        let subtaskUpserts = recorded.filter {
            $0.entityKind == .projectSubtask && $0.operation == .upsert
        }
        #expect(subtaskUpserts.count == 1)
        #expect(subtaskUpserts.first?.recordID == subtaskID)
        #expect(subtaskUpserts.first?.spaceID == spaceID)
    }

    @Test func toggleSubtask_records_upsert() async throws {
        let container = try makeContainer()
        let spy = SpyCoordinator()
        let scheduler = NoopReminderScheduler()
        let repo = LocalProjectRepository(
            container: container,
            reminderScheduler: scheduler,
            syncCoordinator: spy
        )

        let spaceID = UUID()
        let actorID = UUID()
        let project = makeProject(spaceID: spaceID, creatorID: actorID)
        _ = try await repo.saveProject(project, actorID: actorID)

        let withSubtask = try await repo.addSubtask(
            projectID: project.id, title: "步骤一", isCompleted: false,
            creatorID: actorID, actorID: actorID
        )
        let subtaskID = withSubtask.subtasks.first!.id

        _ = try await repo.toggleSubtask(projectID: project.id, subtaskID: subtaskID, actorID: actorID)

        let recorded = await spy.recorded
        // addSubtask + toggleSubtask each record a subtask upsert
        let subtaskUpserts = recorded.filter {
            $0.entityKind == .projectSubtask && $0.operation == .upsert && $0.recordID == subtaskID
        }
        #expect(subtaskUpserts.count == 2)
    }

    @Test func deleteSubtask_records_delete_and_tombstones() async throws {
        let container = try makeContainer()
        let spy = SpyCoordinator()
        let scheduler = NoopReminderScheduler()
        let repo = LocalProjectRepository(
            container: container,
            reminderScheduler: scheduler,
            syncCoordinator: spy
        )

        let spaceID = UUID()
        let actorID = UUID()
        let project = makeProject(spaceID: spaceID, creatorID: actorID)
        _ = try await repo.saveProject(project, actorID: actorID)

        let withSubtask = try await repo.addSubtask(
            projectID: project.id, title: "子任务", isCompleted: false,
            creatorID: actorID, actorID: actorID
        )
        let subtaskID = withSubtask.subtasks.first!.id

        _ = try await repo.deleteSubtask(projectID: project.id, subtaskID: subtaskID, actorID: actorID)

        let recorded = await spy.recorded
        let subtaskDeletes = recorded.filter {
            $0.entityKind == .projectSubtask && $0.operation == .delete
        }
        #expect(subtaskDeletes.count == 1)
        #expect(subtaskDeletes.first?.recordID == subtaskID)

        // Record is tombstoned, not hard-deleted
        let context = ModelContext(container)
        let remaining = try context.fetch(FetchDescriptor<PersistentProjectSubtask>())
        #expect(remaining.count == 1)
        #expect(remaining.first?.isLocallyDeleted == true)
    }

    @Test func deleteSubtask_resequences_siblings_and_records_upserts() async throws {
        let container = try makeContainer()
        let spy = SpyCoordinator()
        let scheduler = NoopReminderScheduler()
        let repo = LocalProjectRepository(
            container: container,
            reminderScheduler: scheduler,
            syncCoordinator: spy
        )

        let spaceID = UUID()
        let actorID = UUID()
        let project = makeProject(spaceID: spaceID, creatorID: actorID)
        _ = try await repo.saveProject(project, actorID: actorID)

        let after1 = try await repo.addSubtask(
            projectID: project.id, title: "A", isCompleted: false,
            creatorID: actorID, actorID: actorID
        )
        let subtask0ID = after1.subtasks[0].id

        let after2 = try await repo.addSubtask(
            projectID: project.id, title: "B", isCompleted: false,
            creatorID: actorID, actorID: actorID
        )
        let subtask1ID = after2.subtasks[1].id

        // Delete first subtask; sibling (B) should be resequenced to sortOrder=0
        _ = try await repo.deleteSubtask(projectID: project.id, subtaskID: subtask0ID, actorID: actorID)

        let context = ModelContext(container)
        let all = try context.fetch(FetchDescriptor<PersistentProjectSubtask>())
        let live = all.filter { !$0.isLocallyDeleted }
        #expect(live.count == 1)
        #expect(live.first?.id == subtask1ID)
        #expect(live.first?.sortOrder == 0)

        // Sibling upsert should have been recorded
        let recorded = await spy.recorded
        let siblingUpserts = recorded.filter {
            $0.entityKind == .projectSubtask && $0.operation == .upsert && $0.recordID == subtask1ID
        }
        // addSubtask for B + sibling re-upsert after delete
        #expect(siblingUpserts.count >= 2)
    }
}
