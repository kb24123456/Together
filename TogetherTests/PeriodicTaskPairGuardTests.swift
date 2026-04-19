import Testing
import SwiftData
import Foundation
@testable import Together

@Suite("LocalPeriodicTaskRepository pair-space guard")
struct PeriodicTaskPairGuardTests {

    private func makeContainer() throws -> ModelContainer {
        let config = ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        return try ModelContainer(
            for: PersistentUserProfile.self,
            PersistentSpace.self, PersistentPairSpace.self,
            PersistentPairMembership.self, PersistentInvite.self,
            PersistentTaskList.self, PersistentProject.self,
            PersistentProjectSubtask.self, PersistentItem.self,
            PersistentItemOccurrenceCompletion.self,
            PersistentTaskTemplate.self, PersistentSyncChange.self,
            PersistentSyncState.self, PersistentPeriodicTask.self,
            PersistentPairingHistory.self, PersistentTaskMessage.self,
            PersistentImportantDate.self,
            configurations: config
        )
    }

    private func sampleTask(spaceID: UUID?) -> PeriodicTask {
        PeriodicTask(
            id: UUID(),
            spaceID: spaceID,
            creatorID: UUID(),
            title: "Chore",
            notes: nil,
            cycle: .weekly,
            reminderRules: [],
            completions: [],
            sortOrder: 0,
            isActive: true,
            createdAt: .now,
            updatedAt: .now
        )
    }

    @Test("saveTask throws notSupportedInPairMode when space is pair")
    func rejectsPairSpace() async throws {
        let container = try makeContainer()
        let pairSpaceID = UUID()

        let ctx = ModelContext(container)
        ctx.insert(PersistentPairSpace(
            id: UUID(),
            sharedSpaceID: pairSpaceID,
            statusRawValue: "active",
            createdAt: .now,
            activatedAt: .now,
            endedAt: nil
        ))
        try ctx.save()

        let repo = LocalPeriodicTaskRepository(container: container)
        let task = sampleTask(spaceID: pairSpaceID)

        do {
            _ = try await repo.saveTask(task)
            Issue.record("expected notSupportedInPairMode, got success")
        } catch let error as PeriodicTaskError {
            #expect(error == .notSupportedInPairMode)
        }
    }

    @Test("saveTask succeeds when no pair space exists for that spaceID")
    func allowsSoloSpace() async throws {
        let container = try makeContainer()
        let soloSpaceID = UUID()

        let repo = LocalPeriodicTaskRepository(container: container)
        let task = sampleTask(spaceID: soloSpaceID)
        let saved = try await repo.saveTask(task)
        #expect(saved.id == task.id)
    }

    @Test("saveTask succeeds when spaceID is nil (global)")
    func allowsNilSpace() async throws {
        let container = try makeContainer()
        let repo = LocalPeriodicTaskRepository(container: container)
        let task = sampleTask(spaceID: nil)
        let saved = try await repo.saveTask(task)
        #expect(saved.id == task.id)
    }
}
