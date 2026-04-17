import Foundation
import SwiftData
import Testing
@testable import Together

@MainActor
struct SyncInsertTests {
    private func makeContainer() throws -> ModelContainer {
        // 使用与 PersistenceController.makeContainer 一致的 schema 图；
        // SwiftData 要求整张图的所有实体都在 schema 里，否则 loadIssueModelContainer
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

    @Test func taskDTO_inserts_new_item_when_absent() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let taskID = UUID()
        let spaceID = UUID()
        let dto = TaskDTO.fixture(id: taskID, spaceID: spaceID, title: "买牛奶")
        dto.applyToLocal(context: context)
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<PersistentItem>())
        #expect(fetched.count == 1)
        #expect(fetched.first?.title == "买牛奶")
        #expect(fetched.first?.isLocallyDeleted == false)
    }

    @Test func taskDTO_updates_existing_item() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let taskID = UUID()
        let spaceID = UUID()
        let base = Date()

        TaskDTO.fixture(id: taskID, spaceID: spaceID, title: "买牛奶", updatedAt: base)
            .applyToLocal(context: context)
        try context.save()

        TaskDTO.fixture(id: taskID, spaceID: spaceID, title: "买豆浆", updatedAt: base.addingTimeInterval(60))
            .applyToLocal(context: context)
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<PersistentItem>())
        #expect(fetched.count == 1)
        #expect(fetched.first?.title == "买豆浆")
    }

    @Test func taskDTO_marks_tombstone_on_soft_delete() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let taskID = UUID()
        let spaceID = UUID()
        let base = Date()

        TaskDTO.fixture(id: taskID, spaceID: spaceID, title: "买牛奶", updatedAt: base)
            .applyToLocal(context: context)
        try context.save()

        TaskDTO.fixture(
            id: taskID,
            spaceID: spaceID,
            title: "买牛奶",
            updatedAt: base.addingTimeInterval(60),
            isDeleted: true
        ).applyToLocal(context: context)
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<PersistentItem>())
        #expect(fetched.count == 1)
        #expect(fetched.first?.isLocallyDeleted == true)
    }

    @Test func taskDTO_does_not_reinsert_after_tombstone() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let taskID = UUID()
        let spaceID = UUID()
        let base = Date()

        TaskDTO.fixture(id: taskID, spaceID: spaceID, title: "幽灵", updatedAt: base)
            .applyToLocal(context: context)
        try context.save()

        TaskDTO.fixture(
            id: taskID,
            spaceID: spaceID,
            title: "幽灵",
            updatedAt: base.addingTimeInterval(60),
            isDeleted: true
        ).applyToLocal(context: context)
        try context.save()

        // 对方 stale 消息不应把 tombstoned 记录复活
        TaskDTO.fixture(
            id: taskID,
            spaceID: spaceID,
            title: "幽灵",
            updatedAt: base.addingTimeInterval(120),
            isDeleted: false
        ).applyToLocal(context: context)
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<PersistentItem>())
        #expect(fetched.count == 1)
        #expect(fetched.first?.isLocallyDeleted == true, "tombstone 必须保留")
    }
}

// MARK: - Test fixtures

extension TaskDTO {
    /// 仅用于测试：借助一个临时 PersistentItem 生成 TaskDTO。
    /// 生产代码用 `init(from:spaceID:)`；这里把最常需要改的字段参数化。
    static func fixture(
        id: UUID,
        spaceID: UUID,
        title: String,
        updatedAt: Date = Date(),
        isDeleted: Bool = false
    ) -> TaskDTO {
        let item = PersistentItem(
            id: id,
            spaceID: spaceID,
            listID: nil,
            projectID: nil,
            creatorID: UUID(),
            title: title,
            notes: nil,
            locationText: nil,
            executionRoleRawValue: ItemExecutionRole.initiator.rawValue,
            assigneeModeRawValue: TaskAssigneeMode.`self`.rawValue,
            dueAt: nil,
            hasExplicitTime: false,
            remindAt: nil,
            statusRawValue: ItemStatus.inProgress.rawValue,
            assignmentStateRawValue: TaskAssignmentState.active.rawValue,
            latestResponseData: nil,
            responseHistoryData: Data(),
            assignmentMessagesData: Data(),
            lastActionByUserID: nil,
            lastActionAt: nil,
            createdAt: updatedAt,
            updatedAt: updatedAt,
            completedAt: nil,
            isPinned: false,
            isDraft: false,
            isArchived: false,
            archivedAt: nil,
            repeatRuleData: nil,
            reminderRequestedAt: nil,
            isLocallyDeleted: isDeleted
        )
        return TaskDTO(from: item, spaceID: spaceID)
    }
}
