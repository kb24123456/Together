import Foundation
import SwiftData
import Testing
@testable import Together

@MainActor
struct ProjectDTOInsertTests {
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

    @Test func projectDTO_inserts_new_when_absent() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let id = UUID()
        let spaceID = UUID()

        ProjectDTO.fixture(id: id, spaceID: spaceID, name: "项目 A")
            .applyToLocal(context: context)
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<PersistentProject>())
        #expect(fetched.count == 1)
        #expect(fetched.first?.name == "项目 A")
        #expect(fetched.first?.isLocallyDeleted == false)
    }

    @Test func projectDTO_updates_existing() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let id = UUID()
        let spaceID = UUID()
        let base = Date()

        ProjectDTO.fixture(id: id, spaceID: spaceID, name: "项目 A", updatedAt: base)
            .applyToLocal(context: context)
        try context.save()

        ProjectDTO.fixture(id: id, spaceID: spaceID, name: "项目 B", updatedAt: base.addingTimeInterval(60))
            .applyToLocal(context: context)
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<PersistentProject>())
        #expect(fetched.count == 1)
        #expect(fetched.first?.name == "项目 B")
    }

    @Test func projectDTO_marks_tombstone_on_soft_delete() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let id = UUID()
        let spaceID = UUID()
        let base = Date()

        ProjectDTO.fixture(id: id, spaceID: spaceID, name: "项目 A", updatedAt: base)
            .applyToLocal(context: context)
        try context.save()

        ProjectDTO.fixture(
            id: id, spaceID: spaceID, name: "项目 A",
            updatedAt: base.addingTimeInterval(60), isDeleted: true
        ).applyToLocal(context: context)
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<PersistentProject>())
        #expect(fetched.count == 1)
        #expect(fetched.first?.isLocallyDeleted == true)
    }
}

extension ProjectDTO {
    static func fixture(
        id: UUID,
        spaceID: UUID,
        name: String,
        updatedAt: Date = Date(),
        isDeleted: Bool = false
    ) -> ProjectDTO {
        let persistent = PersistentProject(
            id: id, spaceID: spaceID, creatorID: UUID(),
            name: name, notes: nil, colorToken: nil,
            statusRawValue: ProjectStatus.active.rawValue,
            targetDate: nil, remindAt: nil,
            createdAt: updatedAt, updatedAt: updatedAt, completedAt: nil
        )
        var dto = ProjectDTO(from: persistent, spaceID: spaceID)
        dto.isDeleted = isDeleted
        dto.updatedAt = updatedAt
        return dto
    }
}
