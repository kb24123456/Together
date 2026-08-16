import Foundation

protocol TaskApplicationServiceProtocol: Sendable {
    func tasks(in spaceID: UUID, scope: TaskScope) async throws -> [Item]
    func todaySummary(in spaceID: UUID, referenceDate: Date) async throws -> TaskTodaySummary
    func createTask(id: UUID, in spaceID: UUID, actorID: UUID, draft: TaskDraft) async throws -> Item
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
    func setTaskFollowed(
        in spaceID: UUID,
        taskID: UUID,
        actorID: UUID,
        isFollowed: Bool
    ) async throws -> Item
    func addTaskSubtask(in spaceID: UUID, taskID: UUID, actorID: UUID, title: String) async throws -> Item
    func toggleTaskSubtask(in spaceID: UUID, taskID: UUID, subtaskID: UUID, actorID: UUID) async throws -> Item
    func updateTaskSubtask(in spaceID: UUID, taskID: UUID, subtaskID: UUID, actorID: UUID, title: String) async throws -> Item
    func deleteTaskSubtask(in spaceID: UUID, taskID: UUID, subtaskID: UUID, actorID: UUID) async throws -> Item
    func archiveTask(in spaceID: UUID, taskID: UUID, actorID: UUID) async throws -> Item
    func deleteTask(in spaceID: UUID, taskID: UUID, actorID: UUID) async throws
}

extension TaskApplicationServiceProtocol {
    func createTask(in spaceID: UUID, actorID: UUID, draft: TaskDraft) async throws -> Item {
        try await createTask(id: UUID(), in: spaceID, actorID: actorID, draft: draft)
    }

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
