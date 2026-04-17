import Foundation
import SwiftData
import Testing
@testable import Together

@MainActor
struct SyncConflictTests {
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

    @Test func older_dto_does_not_overwrite_newer_local() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let taskID = UUID()
        let spaceID = UUID()
        let now = Date()
        let earlier = now.addingTimeInterval(-60)

        // 1) 本地应用一个 "newer" 版本
        TaskDTO.fixture(id: taskID, spaceID: spaceID, title: "newer", updatedAt: now)
            .applyToLocal(context: context)
        try context.save()

        // 2) 然后收到一个 updatedAt 更早的 DTO（网络乱序 / 时钟漂移）
        TaskDTO.fixture(id: taskID, spaceID: spaceID, title: "older", updatedAt: earlier)
            .applyToLocal(context: context)
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<PersistentItem>())
        #expect(fetched.count == 1)
        #expect(fetched.first?.title == "newer", "旧版 DTO 不应覆盖本地新版")
    }

    @Test func same_updated_at_applies_as_update() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let taskID = UUID()
        let spaceID = UUID()
        let ts = Date()

        TaskDTO.fixture(id: taskID, spaceID: spaceID, title: "a", updatedAt: ts)
            .applyToLocal(context: context)
        try context.save()

        // updatedAt 相等（非严格小于）允许应用
        TaskDTO.fixture(id: taskID, spaceID: spaceID, title: "b", updatedAt: ts)
            .applyToLocal(context: context)
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<PersistentItem>())
        #expect(fetched.first?.title == "b")
    }
}
