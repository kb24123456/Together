import Foundation
import Testing
@testable import Together

@MainActor
@Suite("Today Widget Task Completion Gateway")
struct TodayWidgetTaskCompletionGatewayTests {
    @Test("completes task and refreshes snapshot")
    func completesTaskAndRefreshesSnapshot() async throws {
        let taskID = UUID()
        let spaceID = UUID()
        let actorID = UUID()
        let task = Item(
            id: taskID,
            spaceID: spaceID,
            listID: nil,
            projectID: nil,
            creatorID: actorID,
            title: "核对审核备注",
            notes: nil,
            executionRole: .initiator,
            assigneeMode: .self,
            dueAt: nil,
            hasExplicitTime: false,
            remindAt: nil,
            status: .inProgress,
            responseHistory: [],
            createdAt: .now,
            updatedAt: .now,
            isDraft: false
        )
        let service = MockWidgetTaskApplicationService(item: task)
        let snapshotWriter = MockTodayWidgetSnapshotWriter()
        let gateway = TodayWidgetTaskCompletionGateway(
            taskApplicationService: service,
            snapshotWriter: snapshotWriter,
            spaceIDProvider: { spaceID },
            actorIDProvider: { actorID }
        )

        try await gateway.complete(taskID: taskID, referenceDate: .now)

        #expect(await service.completedTaskID() == taskID)
        #expect(await snapshotWriter.writeCount() == 1)
    }

    @Test("fails before completion when shared context is missing")
    func failsBeforeCompletionWhenSharedContextIsMissing() async throws {
        let taskID = UUID()
        let actorID = UUID()
        let task = makeTask(id: taskID, actorID: actorID)
        let service = MockWidgetTaskApplicationService(item: task)
        let snapshotWriter = MockTodayWidgetSnapshotWriter()
        let gateway = TodayWidgetTaskCompletionGateway(
            taskApplicationService: service,
            snapshotWriter: snapshotWriter,
            spaceIDProvider: { nil },
            actorIDProvider: { actorID }
        )

        await #expect(throws: TodayWidgetCompletionError.missingSpace) {
            try await gateway.complete(taskID: taskID, referenceDate: .now)
        }
        #expect(await service.completedTaskID() == nil)
        #expect(await snapshotWriter.writeCount() == 0)
    }

    private func makeTask(id: UUID, actorID: UUID) -> Item {
        Item(
            id: id,
            spaceID: UUID(),
            listID: nil,
            projectID: nil,
            creatorID: actorID,
            title: "核对审核备注",
            notes: nil,
            executionRole: .initiator,
            assigneeMode: .self,
            dueAt: nil,
            hasExplicitTime: false,
            remindAt: nil,
            status: .inProgress,
            responseHistory: [],
            createdAt: .now,
            updatedAt: .now,
            isDraft: false
        )
    }
}

private actor MockWidgetTaskApplicationService: TaskApplicationServiceProtocol {
    private var completedID: UUID?
    private let item: Item

    init(item: Item) {
        self.item = item
    }

    func completedTaskID() -> UUID? {
        completedID
    }

    func tasks(in spaceID: UUID, scope: TaskScope) async throws -> [Item] {
        [item]
    }

    func todaySummary(in spaceID: UUID, referenceDate: Date) async throws -> TaskTodaySummary {
        TaskTodaySummary(
            referenceDate: referenceDate,
            actionableCount: 1,
            overdueCount: 0,
            dueTodayCount: 1,
            completedTodayCount: 0,
            pinnedCount: 0
        )
    }

    func createTask(in spaceID: UUID, actorID: UUID, draft: TaskDraft) async throws -> Item {
        item
    }

    func updateTask(in spaceID: UUID, taskID: UUID, actorID: UUID, draft: TaskDraft) async throws -> Item {
        item
    }

    func moveTask(
        in spaceID: UUID,
        taskID: UUID,
        actorID: UUID,
        listID: UUID?,
        projectID: UUID?
    ) async throws -> Item {
        item
    }

    func rescheduleTask(
        in spaceID: UUID,
        taskID: UUID,
        actorID: UUID,
        dueAt: Date?,
        remindAt: Date?
    ) async throws -> Item {
        item
    }

    func snoozeTask(in spaceID: UUID, taskID: UUID, actorID: UUID, option: TaskSnoozeOption) async throws -> Item {
        item
    }

    func toggleTaskCompletion(
        in spaceID: UUID,
        taskID: UUID,
        actorID: UUID,
        referenceDate: Date
    ) async throws -> Item {
        item
    }

    func completeTask(
        in spaceID: UUID,
        taskID: UUID,
        actorID: UUID,
        referenceDate: Date
    ) async throws -> Item {
        completedID = taskID
        return item
    }

    func archiveTask(in spaceID: UUID, taskID: UUID, actorID: UUID) async throws -> Item {
        item
    }

    func deleteTask(in spaceID: UUID, taskID: UUID, actorID: UUID) async throws {}

    func respondToTask(
        in spaceID: UUID,
        taskID: UUID,
        actorID: UUID,
        response: ItemResponseKind,
        message: String?
    ) async throws -> Item {
        item
    }

    func sendTaskComment(
        in spaceID: UUID,
        taskID: UUID,
        actorID: UUID,
        content: String
    ) async throws -> TaskMessage? {
        nil
    }

    func requeueDeclinedTask(in spaceID: UUID, taskID: UUID, actorID: UUID) async throws -> Item {
        item
    }

    func appendAssignmentMessage(
        in spaceID: UUID,
        taskID: UUID,
        actorID: UUID,
        message: String
    ) async throws -> Item {
        item
    }

    func sendReminderToPartner(in spaceID: UUID, taskID: UUID, actorID: UUID) async throws -> Item {
        item
    }
}

private actor MockTodayWidgetSnapshotWriter: TodayWidgetSnapshotWriting {
    private var count = 0

    func writeCount() -> Int {
        count
    }

    func refreshTodayWidgetSnapshot() async throws {
        count += 1
    }
}
