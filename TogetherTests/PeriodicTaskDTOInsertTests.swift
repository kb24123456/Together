import Foundation
import SwiftData
import Testing
@testable import Together

@MainActor
struct PeriodicTaskDTOInsertTests {
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

    @Test func periodicTaskDTO_inserts_new_when_absent() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let id = UUID()
        let spaceID = UUID()
        PeriodicTaskDTO.fixture(id: id, spaceID: spaceID, title: "倒垃圾")
            .applyToLocal(context: context)
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<PersistentPeriodicTask>())
        #expect(fetched.count == 1)
        #expect(fetched.first?.title == "倒垃圾")
        #expect(fetched.first?.isLocallyDeleted == false)
    }

    @Test func periodicTaskDTO_updates_existing() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let id = UUID()
        let spaceID = UUID()
        let base = Date()

        PeriodicTaskDTO.fixture(id: id, spaceID: spaceID, title: "倒垃圾", updatedAt: base)
            .applyToLocal(context: context)
        try context.save()

        PeriodicTaskDTO.fixture(id: id, spaceID: spaceID, title: "倒厨余", updatedAt: base.addingTimeInterval(60))
            .applyToLocal(context: context)
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<PersistentPeriodicTask>())
        #expect(fetched.count == 1)
        #expect(fetched.first?.title == "倒厨余")
    }

    @Test func periodicTaskDTO_marks_tombstone_on_soft_delete() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let id = UUID()
        let spaceID = UUID()
        let base = Date()

        PeriodicTaskDTO.fixture(id: id, spaceID: spaceID, title: "倒垃圾", updatedAt: base)
            .applyToLocal(context: context)
        try context.save()

        PeriodicTaskDTO.fixture(
            id: id, spaceID: spaceID, title: "倒垃圾",
            updatedAt: base.addingTimeInterval(60), isDeleted: true
        ).applyToLocal(context: context)
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<PersistentPeriodicTask>())
        #expect(fetched.count == 1)
        #expect(fetched.first?.isLocallyDeleted == true)
    }
}

extension PeriodicTaskDTO {
    static func fixture(
        id: UUID,
        spaceID: UUID,
        title: String,
        updatedAt: Date = Date(),
        isDeleted: Bool = false
    ) -> PeriodicTaskDTO {
        let persistent = PersistentPeriodicTask(
            id: id,
            spaceID: spaceID,
            creatorID: UUID(),
            title: title,
            notes: nil,
            cycleRawValue: PeriodicCycle.monthly.rawValue,
            reminderRulesData: nil,
            completionsData: Data("{}".utf8),
            sortOrder: 0,
            isActive: true,
            createdAt: updatedAt,
            updatedAt: updatedAt
        )
        var dto = PeriodicTaskDTO(from: persistent, spaceID: spaceID)
        dto.isDeleted = isDeleted
        dto.updatedAt = updatedAt
        return dto
    }
}
