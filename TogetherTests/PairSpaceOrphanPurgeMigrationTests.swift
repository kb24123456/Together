import Testing
import SwiftData
import Foundation
@testable import Together

@Suite("PairSpaceOrphanPurgeMigration")
struct PairSpaceOrphanPurgeMigrationTests {

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

    @Test("purges orphan rows whose spaceID does not match any PersistentSpace")
    func purgesOrphanRows() throws {
        let container = try makeContainer()
        let ctx = ModelContext(container)

        let livingSpaceID = UUID()
        let orphanSpaceID = UUID()

        ctx.insert(PersistentSpace(space: Space(
            id: livingSpaceID,
            type: .pair,
            displayName: "存活空间",
            ownerUserID: UUID(),
            status: .active,
            createdAt: .now,
            updatedAt: .now,
            archivedAt: nil
        )))

        // Living rows — should survive.
        ctx.insert(PersistentImportantDate(
            id: UUID(),
            spaceID: livingSpaceID,
            creatorID: UUID(),
            kindRawValue: "anniversary",
            title: "活-纪念日",
            dateValue: .now,
            recurrenceRawValue: "yearly"
        ))
        let livingItemID = UUID()
        ctx.insert(PersistentItem(item: Item(
            id: livingItemID,
            spaceID: livingSpaceID,
            listID: nil,
            projectID: nil,
            creatorID: UUID(),
            title: "活-任务",
            notes: nil,
            locationText: nil,
            executionRole: .initiator,
            assigneeMode: .both,
            dueAt: nil,
            hasExplicitTime: false,
            remindAt: nil,
            status: .inProgress,
            assignmentState: .accepted,
            latestResponse: nil,
            responseHistory: [],
            assignmentMessages: [],
            lastActionByUserID: nil,
            lastActionAt: nil,
            createdAt: .now,
            updatedAt: .now,
            completedAt: nil,
            occurrenceCompletions: [],
            isPinned: false,
            isDraft: false,
            isArchived: false,
            archivedAt: nil,
            repeatRule: nil,
            reminderRequestedAt: nil
        )))
        ctx.insert(PersistentTaskMessage(message: TaskMessage(
            id: UUID(),
            taskID: livingItemID,
            senderID: UUID(),
            type: "nudge",
            createdAt: .now
        )))

        // Orphan rows — should be purged.
        ctx.insert(PersistentImportantDate(
            id: UUID(),
            spaceID: orphanSpaceID,
            creatorID: UUID(),
            kindRawValue: "anniversary",
            title: "孤-纪念日",
            dateValue: .now,
            recurrenceRawValue: "yearly"
        ))
        let orphanItemID = UUID()
        ctx.insert(PersistentItem(item: Item(
            id: orphanItemID,
            spaceID: orphanSpaceID,
            listID: nil,
            projectID: nil,
            creatorID: UUID(),
            title: "孤-任务",
            notes: nil,
            locationText: nil,
            executionRole: .initiator,
            assigneeMode: .both,
            dueAt: nil,
            hasExplicitTime: false,
            remindAt: nil,
            status: .inProgress,
            assignmentState: .accepted,
            latestResponse: nil,
            responseHistory: [],
            assignmentMessages: [],
            lastActionByUserID: nil,
            lastActionAt: nil,
            createdAt: .now,
            updatedAt: .now,
            completedAt: nil,
            occurrenceCompletions: [],
            isPinned: false,
            isDraft: false,
            isArchived: false,
            archivedAt: nil,
            repeatRule: nil,
            reminderRequestedAt: nil
        )))
        ctx.insert(PersistentTaskMessage(message: TaskMessage(
            id: UUID(),
            taskID: orphanItemID,
            senderID: UUID(),
            type: "nudge",
            createdAt: .now
        )))
        try ctx.save()

        UserDefaults.standard.removeObject(forKey: "migration_pair_space_orphan_purged_v1")
        PairSpaceOrphanPurgeMigration.runIfNeeded(context: ctx)

        let survivingDates = try ctx.fetch(FetchDescriptor<PersistentImportantDate>())
        #expect(survivingDates.count == 1)
        #expect(survivingDates.first?.spaceID == livingSpaceID)

        let survivingItems = try ctx.fetch(FetchDescriptor<PersistentItem>())
        #expect(survivingItems.count == 1)
        #expect(survivingItems.first?.id == livingItemID)

        let survivingMessages = try ctx.fetch(FetchDescriptor<PersistentTaskMessage>())
        #expect(survivingMessages.count == 1)
        #expect(survivingMessages.first?.taskID == livingItemID)
    }

    @Test("is idempotent — second run does nothing")
    func idempotent() throws {
        let container = try makeContainer()
        let ctx = ModelContext(container)
        UserDefaults.standard.removeObject(forKey: "migration_pair_space_orphan_purged_v1")
        PairSpaceOrphanPurgeMigration.runIfNeeded(context: ctx)
        #expect(UserDefaults.standard.bool(forKey: "migration_pair_space_orphan_purged_v1") == true)
        PairSpaceOrphanPurgeMigration.runIfNeeded(context: ctx)
        #expect(UserDefaults.standard.bool(forKey: "migration_pair_space_orphan_purged_v1") == true)
    }

    @Test("skips purge on fresh install with no PersistentSpace rows")
    func skipsWhenNoSpaces() throws {
        let container = try makeContainer()
        let ctx = ModelContext(container)
        let orphanSpaceID = UUID()
        ctx.insert(PersistentImportantDate(
            id: UUID(),
            spaceID: orphanSpaceID,
            creatorID: UUID(),
            kindRawValue: "anniversary",
            title: "纪念日",
            dateValue: .now,
            recurrenceRawValue: "yearly"
        ))
        try ctx.save()

        UserDefaults.standard.removeObject(forKey: "migration_pair_space_orphan_purged_v1")
        PairSpaceOrphanPurgeMigration.runIfNeeded(context: ctx)

        // No PersistentSpace seeded → migration must not purge anything.
        #expect(try ctx.fetch(FetchDescriptor<PersistentImportantDate>()).count == 1)
    }
}
