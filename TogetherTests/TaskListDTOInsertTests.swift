import Foundation
import SwiftData
import Testing
@testable import Together

@MainActor
struct TaskListDTOInsertTests {
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

    @Test func taskListDTO_inserts_new_when_absent() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let id = UUID()
        let spaceID = UUID()

        TaskListDTO.fixture(id: id, spaceID: spaceID, name: "购物清单")
            .applyToLocal(context: context)
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<PersistentTaskList>())
        #expect(fetched.count == 1)
        #expect(fetched.first?.name == "购物清单")
        #expect(fetched.first?.isLocallyDeleted == false)
    }

    @Test func taskListDTO_updates_existing() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let id = UUID()
        let spaceID = UUID()
        let base = Date()

        TaskListDTO.fixture(id: id, spaceID: spaceID, name: "购物清单", updatedAt: base)
            .applyToLocal(context: context)
        try context.save()

        TaskListDTO.fixture(id: id, spaceID: spaceID, name: "日用清单", updatedAt: base.addingTimeInterval(60))
            .applyToLocal(context: context)
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<PersistentTaskList>())
        #expect(fetched.count == 1)
        #expect(fetched.first?.name == "日用清单")
    }

    @Test func taskListDTO_marks_tombstone_on_soft_delete() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let id = UUID()
        let spaceID = UUID()
        let base = Date()

        TaskListDTO.fixture(id: id, spaceID: spaceID, name: "购物清单", updatedAt: base)
            .applyToLocal(context: context)
        try context.save()

        TaskListDTO.fixture(
            id: id, spaceID: spaceID, name: "购物清单",
            updatedAt: base.addingTimeInterval(60), isDeleted: true
        ).applyToLocal(context: context)
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<PersistentTaskList>())
        #expect(fetched.count == 1)
        #expect(fetched.first?.isLocallyDeleted == true)
    }
}

extension TaskListDTO {
    static func fixture(
        id: UUID,
        spaceID: UUID,
        name: String,
        updatedAt: Date = Date(),
        isDeleted: Bool = false
    ) -> TaskListDTO {
        let persistent = PersistentTaskList(
            id: id, spaceID: spaceID, creatorID: UUID(),
            name: name, kindRawValue: TaskListKind.custom.rawValue,
            colorToken: nil, sortOrder: 0, isArchived: false,
            createdAt: updatedAt, updatedAt: updatedAt
        )
        var dto = TaskListDTO(from: persistent, spaceID: spaceID)
        dto.isDeleted = isDeleted
        dto.updatedAt = updatedAt
        return dto
    }
}
