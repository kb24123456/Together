import Foundation
import SwiftData
import Testing
@testable import Together

@MainActor
struct ProjectSubtaskDTOInsertTests {
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

    @Test func subtaskDTO_inserts_new_when_absent() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let id = UUID()
        let projectID = UUID()

        ProjectSubtaskDTO.fixture(id: id, projectID: projectID, title: "步骤一")
            .applyToLocal(context: context)
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<PersistentProjectSubtask>())
        #expect(fetched.count == 1)
        #expect(fetched.first?.title == "步骤一")
        #expect(fetched.first?.isLocallyDeleted == false)
    }

    @Test func subtaskDTO_updates_existing() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let id = UUID()
        let projectID = UUID()
        let base = Date()

        ProjectSubtaskDTO.fixture(id: id, projectID: projectID, title: "a", updatedAt: base)
            .applyToLocal(context: context)
        try context.save()

        ProjectSubtaskDTO.fixture(id: id, projectID: projectID, title: "b", updatedAt: base.addingTimeInterval(60))
            .applyToLocal(context: context)
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<PersistentProjectSubtask>())
        #expect(fetched.count == 1)
        #expect(fetched.first?.title == "b")
    }

    @Test func subtaskDTO_marks_tombstone_on_soft_delete() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let id = UUID()
        let projectID = UUID()
        let base = Date()

        ProjectSubtaskDTO.fixture(id: id, projectID: projectID, title: "a", updatedAt: base)
            .applyToLocal(context: context)
        try context.save()

        ProjectSubtaskDTO.fixture(
            id: id, projectID: projectID, title: "a",
            updatedAt: base.addingTimeInterval(60), isDeleted: true
        ).applyToLocal(context: context)
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<PersistentProjectSubtask>())
        #expect(fetched.count == 1)
        #expect(fetched.first?.isLocallyDeleted == true)
    }
}

extension ProjectSubtaskDTO {
    static func fixture(
        id: UUID,
        projectID: UUID,
        title: String,
        updatedAt: Date = Date(),
        isDeleted: Bool = false
    ) -> ProjectSubtaskDTO {
        let persistent = PersistentProjectSubtask(
            id: id, projectID: projectID, creatorID: UUID(),
            title: title, isCompleted: false, sortOrder: 0, updatedAt: updatedAt
        )
        var dto = ProjectSubtaskDTO(from: persistent, spaceID: UUID())
        dto.isDeleted = isDeleted
        dto.updatedAt = updatedAt
        return dto
    }
}
