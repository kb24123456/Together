import Testing
import SwiftData
import Foundation
@testable import Together

@Suite("PairPeriodicPurgeMigration")
struct PairPeriodicPurgeMigrationTests {

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
            PersistentTaskMessage.self,
            PersistentImportantDate.self,
            configurations: config
        )
    }

    private func makeTask(spaceID: UUID, title: String) -> PersistentPeriodicTask {
        PersistentPeriodicTask(
            id: UUID(),
            spaceID: spaceID,
            creatorID: UUID(),
            title: title,
            notes: nil,
            cycleRawValue: "weekly",
            reminderRulesData: nil,
            completionsData: Data(),
            sortOrder: 0,
            isActive: true,
            createdAt: .now,
            updatedAt: .now
        )
    }

    @Test("purges periodic_tasks in pair space, leaves solo-space untouched")
    func purgesPairOnly() throws {
        let container = try makeContainer()
        let ctx = ModelContext(container)

        let pairSpaceID = UUID()
        let soloSpaceID = UUID()

        ctx.insert(PersistentPairSpace(
            id: UUID(),
            sharedSpaceID: pairSpaceID,
            statusRawValue: "active",
            createdAt: .now,
            activatedAt: .now,
            endedAt: nil
        ))

        ctx.insert(makeTask(spaceID: pairSpaceID, title: "Pair chore"))
        ctx.insert(makeTask(spaceID: soloSpaceID, title: "Solo habit"))
        try ctx.save()

        UserDefaults.standard.removeObject(forKey: "migration_pair_periodic_purged_v1")

        PairPeriodicPurgeMigration.runIfNeeded(context: ctx)

        let remaining = try ctx.fetch(FetchDescriptor<PersistentPeriodicTask>())
        #expect(remaining.count == 1)
        #expect(remaining.first?.spaceID == soloSpaceID)
    }

    @Test("is idempotent — second run does nothing")
    func idempotent() throws {
        let container = try makeContainer()
        let ctx = ModelContext(container)
        UserDefaults.standard.removeObject(forKey: "migration_pair_periodic_purged_v1")
        PairPeriodicPurgeMigration.runIfNeeded(context: ctx)
        #expect(UserDefaults.standard.bool(forKey: "migration_pair_periodic_purged_v1") == true)
        PairPeriodicPurgeMigration.runIfNeeded(context: ctx)
        #expect(UserDefaults.standard.bool(forKey: "migration_pair_periodic_purged_v1") == true)
    }
}
