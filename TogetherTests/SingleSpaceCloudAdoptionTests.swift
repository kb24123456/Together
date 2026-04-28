import Foundation
import SwiftData
import Testing
@testable import Together

@MainActor
struct SingleSpaceCloudAdoptionTests {
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

    @Test("Cloud-restored single space with tasks wins over empty reinstall space")
    func cloudRestoredSingleSpaceWithTasksWinsOverEmptyReinstallSpace() async throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let oldUserID = UUID()
        let newUserID = UUID()
        let cloudSpaceID = UUID()
        let reinstallSpaceID = UUID()
        let baseDate = Date(timeIntervalSince1970: 1_700_000_000)

        context.insert(PersistentSpace(
            id: cloudSpaceID,
            typeRawValue: SpaceType.single.rawValue,
            displayName: "我的空间",
            ownerUserID: oldUserID,
            statusRawValue: SpaceStatus.active.rawValue,
            createdAt: baseDate,
            updatedAt: baseDate,
            archivedAt: nil
        ))
        context.insert(PersistentSpace(
            id: reinstallSpaceID,
            typeRawValue: SpaceType.single.rawValue,
            displayName: "我的空间",
            ownerUserID: newUserID,
            statusRawValue: SpaceStatus.active.rawValue,
            createdAt: baseDate.addingTimeInterval(120),
            updatedAt: baseDate.addingTimeInterval(120),
            archivedAt: nil
        ))
        context.insert(PersistentItem(item: Item(
            id: UUID(),
            spaceID: cloudSpaceID,
            listID: nil,
            projectID: nil,
            creatorID: oldUserID,
            title: "云端恢复任务",
            notes: nil,
            locationText: nil,
            executionRole: .initiator,
            assigneeMode: .self,
            dueAt: nil,
            hasExplicitTime: false,
            remindAt: nil,
            status: .inProgress,
            assignmentState: .active,
            latestResponse: nil,
            responseHistory: [],
            assignmentMessages: [],
            lastActionByUserID: nil,
            lastActionAt: nil,
            createdAt: baseDate,
            updatedAt: baseDate,
            completedAt: nil,
            completedByUserID: nil,
            occurrenceCompletions: [],
            isPinned: false,
            isDraft: false,
            isArchived: false,
            archivedAt: nil,
            repeatRule: nil,
            reminderRequestedAt: nil
        )))
        try context.save()

        let service = LocalSpaceService(container: container)
        let spaceContext = await service.currentSpaceContext(for: newUserID)

        #expect(spaceContext.singleSpace?.id == cloudSpaceID)

        let cloudRecord = try #require(try context.fetch(FetchDescriptor<PersistentSpace>(
            predicate: #Predicate<PersistentSpace> { $0.id == cloudSpaceID }
        )).first)
        #expect(cloudRecord.ownerUserID == newUserID)

        let restoredTask = try #require(try context.fetch(FetchDescriptor<PersistentItem>(
            predicate: #Predicate<PersistentItem> { $0.spaceID == cloudSpaceID }
        )).first)
        #expect(restoredTask.creatorID == newUserID)
    }
}
