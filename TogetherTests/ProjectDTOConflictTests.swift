import Foundation
import SwiftData
import Testing
@testable import Together

@MainActor
struct ProjectDTOConflictTests {
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

    @Test func older_dto_does_not_overwrite_newer_local() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let id = UUID()
        let spaceID = UUID()
        let now = Date()
        let earlier = now.addingTimeInterval(-60)

        ProjectDTO.fixture(id: id, spaceID: spaceID, name: "newer", updatedAt: now)
            .applyToLocal(context: context)
        try context.save()

        ProjectDTO.fixture(id: id, spaceID: spaceID, name: "older", updatedAt: earlier)
            .applyToLocal(context: context)
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<PersistentProject>())
        #expect(fetched.first?.name == "newer", "older DTO did not overwrite newer local")
    }

    @Test func tombstone_not_resurrected_by_later_remote_upsert() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let id = UUID()
        let spaceID = UUID()
        let base = Date()

        // Seed the record
        ProjectDTO.fixture(id: id, spaceID: spaceID, name: "seed", updatedAt: base)
            .applyToLocal(context: context)
        try context.save()

        // Apply tombstone
        ProjectDTO.fixture(
            id: id, spaceID: spaceID, name: "seed",
            updatedAt: base.addingTimeInterval(60), isDeleted: true
        ).applyToLocal(context: context)
        try context.save()

        // Later remote upsert with DIFFERENT name to prove UPDATE branch executed
        ProjectDTO.fixture(
            id: id, spaceID: spaceID, name: "seed-after-tombstone",
            updatedAt: base.addingTimeInterval(120), isDeleted: false
        ).applyToLocal(context: context)
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<PersistentProject>())
        #expect(fetched.count == 1)

        // UPDATE branch ran and overwrote name
        #expect(fetched.first?.name == "seed-after-tombstone", "UPDATE branch overwrote name")

        // tombstone flag is one-way; remote pull cannot resurrect
        #expect(fetched.first?.isLocallyDeleted == true, "tombstone flag is one-way; remote pull cannot resurrect")
    }
}
