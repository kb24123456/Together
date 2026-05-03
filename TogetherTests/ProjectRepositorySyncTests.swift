import Foundation
import SwiftData
import Testing
@testable import Together

@MainActor
struct ProjectRepositorySyncTests {
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
            name: "项目 X",
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

    @Test func saveProject_records_upsert() async throws {
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

        let recorded = await spy.recorded
        #expect(recorded.count == 1)
        #expect(recorded.first?.entityKind == .project)
        #expect(recorded.first?.operation == .upsert)
        #expect(recorded.first?.recordID == project.id)
        #expect(recorded.first?.spaceID == spaceID)
    }

    @Test func saveProject_after_tombstone_resurrects_record() async throws {
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

        // Simulate tombstone via direct SwiftData mutation
        let context = ModelContext(container)
        let records = try context.fetch(FetchDescriptor<PersistentProject>())
        records.first?.isLocallyDeleted = true
        try context.save()

        // Re-save should clear the tombstone
        _ = try await repo.saveProject(project, actorID: actorID)

        let context2 = ModelContext(container)
        let remaining = try context2.fetch(FetchDescriptor<PersistentProject>())
        #expect(remaining.count == 1)
        #expect(remaining.first?.isLocallyDeleted == false, "re-save should clear tombstone")

        let recorded = await spy.recorded
        let upserts = recorded.filter {
            $0.entityKind == .project && $0.operation == .upsert
        }
        #expect(upserts.count == 2, "first saveProject + resurrection saveProject each record .upsert")
        #expect(upserts.allSatisfy { $0.recordID == project.id })
    }

    @Test func deleteProject_tombstones_project_and_all_subtasks() async throws {
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

        // Add 2 subtasks
        let withSubtask1 = try await repo.addSubtask(
            projectID: project.id, title: "子任务 1", isCompleted: false,
            creatorID: actorID, actorID: actorID
        )
        _ = try await repo.addSubtask(
            projectID: project.id, title: "子任务 2", isCompleted: false,
            creatorID: actorID, actorID: actorID
        )
        let subtaskCount = withSubtask1.subtasks.count + 1 // after both adds = 2

        // Delete the project
        try await repo.deleteProject(projectID: project.id, actorID: actorID)

        // Verify persistence state
        let context = ModelContext(container)
        let projectRecords = try context.fetch(FetchDescriptor<PersistentProject>())
        let subtaskRecords = try context.fetch(FetchDescriptor<PersistentProjectSubtask>())

        #expect(projectRecords.first?.isLocallyDeleted == true, "project should be tombstoned")
        #expect(subtaskRecords.allSatisfy { $0.isLocallyDeleted == true }, "all subtasks should be tombstoned")

        // Verify sync recording
        let recorded = await spy.recorded
        let projectDeletes = recorded.filter {
            $0.entityKind == .project && $0.operation == .delete
        }
        let subtaskDeletes = recorded.filter {
            $0.entityKind == .projectSubtask && $0.operation == .delete
        }

        #expect(projectDeletes.count == 1, "exactly 1 project .delete recorded")
        #expect(projectDeletes.first?.recordID == project.id)

        let expectedSubtaskCount = subtaskRecords.count
        #expect(subtaskDeletes.count == expectedSubtaskCount, "\(expectedSubtaskCount) subtask .delete(s) recorded")
    }

    @Test func deleteProject_allows_single_space_owner_when_creator_is_orphaned() async throws {
        let container = try makeContainer()
        let spy = SpyCoordinator()
        let scheduler = NoopReminderScheduler()
        let repo = LocalProjectRepository(
            container: container,
            reminderScheduler: scheduler,
            syncCoordinator: spy
        )

        let spaceID = UUID()
        let ownerID = UUID()
        let orphanCreatorID = UUID()
        let now = Date()
        let context = ModelContext(container)
        let project = makeProject(spaceID: spaceID, creatorID: orphanCreatorID)
        context.insert(PersistentSpace(
            id: spaceID,
            typeRawValue: SpaceType.single.rawValue,
            displayName: "我的空间",
            ownerUserID: ownerID,
            statusRawValue: SpaceStatus.active.rawValue,
            createdAt: now,
            updatedAt: now,
            archivedAt: nil
        ))
        context.insert(PersistentProject(project: project))
        try context.save()

        try await repo.deleteProject(
            projectID: project.id,
            actorID: ownerID
        )

        let verificationContext = ModelContext(container)
        let projects = try verificationContext.fetch(FetchDescriptor<PersistentProject>())
        #expect(projects.first?.isLocallyDeleted == true)

        let recorded = await spy.recorded
        #expect(recorded.contains { $0.entityKind == .project && $0.operation == .delete && $0.spaceID == spaceID })
    }

    @Test func deleteProject_rejects_nonOwner_when_creator_is_orphaned() async throws {
        let container = try makeContainer()
        let spy = SpyCoordinator()
        let scheduler = NoopReminderScheduler()
        let repo = LocalProjectRepository(
            container: container,
            reminderScheduler: scheduler,
            syncCoordinator: spy
        )

        let spaceID = UUID()
        let ownerID = UUID()
        let otherActorID = UUID()
        let orphanCreatorID = UUID()
        let now = Date()
        let context = ModelContext(container)
        let project = makeProject(spaceID: spaceID, creatorID: orphanCreatorID)
        context.insert(PersistentSpace(
            id: spaceID,
            typeRawValue: SpaceType.single.rawValue,
            displayName: "我的空间",
            ownerUserID: ownerID,
            statusRawValue: SpaceStatus.active.rawValue,
            createdAt: now,
            updatedAt: now,
            archivedAt: nil
        ))
        context.insert(PersistentProject(project: project))
        try context.save()

        await #expect(throws: PermissionError.self) {
            try await repo.deleteProject(projectID: project.id, actorID: otherActorID)
        }
    }

    @Test func fetchProjects_excludes_tombstones() async throws {
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

        // Simulate tombstone via direct SwiftData mutation
        let context = ModelContext(container)
        let records = try context.fetch(FetchDescriptor<PersistentProject>())
        records.first?.isLocallyDeleted = true
        try context.save()

        let fetched = try await repo.fetchProjects(spaceID: spaceID)
        #expect(fetched.isEmpty, "tombstoned project must not appear in fetchProjects")
    }
}
