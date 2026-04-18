import Foundation
import SwiftData
import Testing
@testable import Together

@MainActor
struct TaskListDTOConflictTests {
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

        TaskListDTO.fixture(id: id, spaceID: spaceID, name: "newer", updatedAt: now)
            .applyToLocal(context: context)
        try context.save()

        TaskListDTO.fixture(id: id, spaceID: spaceID, name: "older", updatedAt: earlier)
            .applyToLocal(context: context)
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<PersistentTaskList>())
        #expect(fetched.first?.name == "newer")
    }

    @Test func tombstone_not_resurrected_by_later_remote_upsert() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let id = UUID()
        let spaceID = UUID()
        let base = Date()

        TaskListDTO.fixture(id: id, spaceID: spaceID, name: "x", updatedAt: base)
            .applyToLocal(context: context)
        try context.save()

        TaskListDTO.fixture(
            id: id, spaceID: spaceID, name: "x",
            updatedAt: base.addingTimeInterval(60), isDeleted: true
        ).applyToLocal(context: context)
        try context.save()

        // 对方 stale 消息不能复活 tombstone
        TaskListDTO.fixture(
            id: id, spaceID: spaceID, name: "x",
            updatedAt: base.addingTimeInterval(120), isDeleted: false
        ).applyToLocal(context: context)
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<PersistentTaskList>())
        #expect(fetched.first?.isLocallyDeleted == true)
    }
}
