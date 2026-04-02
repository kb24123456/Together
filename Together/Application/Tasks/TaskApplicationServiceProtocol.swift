import Foundation

protocol TaskApplicationServiceProtocol: Sendable {
    func tasks(in spaceID: UUID, scope: TaskScope) async throws -> [Item]
    func todaySummary(in spaceID: UUID, referenceDate: Date) async throws -> TaskTodaySummary
    func createTask(in spaceID: UUID, actorID: UUID, draft: TaskDraft) async throws -> Item
    func updateTask(in spaceID: UUID, taskID: UUID, actorID: UUID, draft: TaskDraft) async throws -> Item
    func moveTask(
        in spaceID: UUID,
        taskID: UUID,
        actorID: UUID,
        listID: UUID?,
        projectID: UUID?
    ) async throws -> Item
    func rescheduleTask(
        in spaceID: UUID,
        taskID: UUID,
        actorID: UUID,
        dueAt: Date?,
        remindAt: Date?
    ) async throws -> Item
    func snoozeTask(
        in spaceID: UUID,
        taskID: UUID,
        actorID: UUID,
        option: TaskSnoozeOption
    ) async throws -> Item
    func toggleTaskCompletion(
        in spaceID: UUID,
        taskID: UUID,
        actorID: UUID,
        referenceDate: Date
    ) async throws -> Item
    func completeTask(
        in spaceID: UUID,
        taskID: UUID,
        actorID: UUID,
        referenceDate: Date
    ) async throws -> Item
    func archiveTask(in spaceID: UUID, taskID: UUID, actorID: UUID) async throws -> Item
    func deleteTask(in spaceID: UUID, taskID: UUID, actorID: UUID) async throws
    func respondToTask(
        in spaceID: UUID,
        taskID: UUID,
        actorID: UUID,
        response: ItemResponseKind,
        message: String?
    ) async throws -> Item
}

extension TaskApplicationServiceProtocol {
    func toggleTaskCompletion(in spaceID: UUID, taskID: UUID, actorID: UUID) async throws -> Item {
        try await toggleTaskCompletion(
            in: spaceID,
            taskID: taskID,
            actorID: actorID,
            referenceDate: .now
        )
    }

    func completeTask(in spaceID: UUID, taskID: UUID, actorID: UUID) async throws -> Item {
        try await completeTask(
            in: spaceID,
            taskID: taskID,
            actorID: actorID,
            referenceDate: .now
        )
    }
}
