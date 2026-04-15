import Foundation

protocol PeriodicTaskApplicationServiceProtocol: Sendable {
    func fetchTasks(in spaceID: UUID) async throws -> [PeriodicTask]
    func createTask(in spaceID: UUID, actorID: UUID, draft: PeriodicTaskDraft) async throws -> PeriodicTask
    func updateTask(in spaceID: UUID, taskID: UUID, actorID: UUID, draft: PeriodicTaskDraft) async throws -> PeriodicTask
    func toggleCompletion(in spaceID: UUID, taskID: UUID, referenceDate: Date) async throws -> PeriodicTask
    func deleteTask(in spaceID: UUID, taskID: UUID, actorID: UUID) async throws
}

actor DefaultPeriodicTaskApplicationService: PeriodicTaskApplicationServiceProtocol {
    private let repository: PeriodicTaskRepositoryProtocol
    private let reminderScheduler: ReminderSchedulerProtocol
    private let syncCoordinator: SyncCoordinatorProtocol

    init(
        repository: PeriodicTaskRepositoryProtocol,
        reminderScheduler: ReminderSchedulerProtocol,
        syncCoordinator: SyncCoordinatorProtocol
    ) {
        self.repository = repository
        self.reminderScheduler = reminderScheduler
        self.syncCoordinator = syncCoordinator
    }

    func fetchTasks(in spaceID: UUID) async throws -> [PeriodicTask] {
        try await repository.fetchActiveTasks(spaceID: spaceID)
    }

    func createTask(in spaceID: UUID, actorID: UUID, draft: PeriodicTaskDraft) async throws -> PeriodicTask {
        let now = Date.now
        let task = PeriodicTask(
            id: UUID(),
            spaceID: spaceID,
            creatorID: actorID,
            title: draft.title,
            notes: draft.notes,
            cycle: draft.cycle,
            reminderRules: draft.reminderRules,
            completions: [],
            sortOrder: now.timeIntervalSinceReferenceDate,
            isActive: true,
            createdAt: now,
            updatedAt: now
        )

        let saved = try await repository.saveTask(task)
        await syncCoordinator.recordLocalChange(
            SyncChange(entityKind: .periodicTask, operation: .upsert, recordID: saved.id, spaceID: spaceID)
        )
        await reminderScheduler.syncPeriodicTaskReminder(for: saved, referenceDate: now)
        return saved
    }

    func updateTask(in spaceID: UUID, taskID: UUID, actorID: UUID, draft: PeriodicTaskDraft) async throws -> PeriodicTask {
        guard var task = try await repository.fetchTask(taskID: taskID) else {
            throw PeriodicTaskError.notFound
        }

        guard PairPermissionService.canEditPeriodicTask(task, actorID: actorID) else {
            throw PermissionError.notCreator
        }

        task.title = draft.title
        task.notes = draft.notes
        task.cycle = draft.cycle
        task.reminderRules = draft.reminderRules
        task.updatedAt = .now

        let saved = try await repository.saveTask(task)
        await syncCoordinator.recordLocalChange(
            SyncChange(entityKind: .periodicTask, operation: .upsert, recordID: saved.id, spaceID: spaceID)
        )
        await reminderScheduler.syncPeriodicTaskReminder(for: saved, referenceDate: .now)
        return saved
    }

    /// No actorID permission check: both partners can toggle periodic task completion.
    /// Periodic tasks represent shared routines (e.g. "daily cleaning") where either party marks done.
    func toggleCompletion(in spaceID: UUID, taskID: UUID, referenceDate: Date) async throws -> PeriodicTask {
        guard let task = try await repository.fetchTask(taskID: taskID) else {
            throw PeriodicTaskError.notFound
        }

        let periodKey = PeriodicCycleCalculator.periodKey(for: task.cycle, date: referenceDate)

        let updated: PeriodicTask
        if task.isCompleted(forPeriodKey: periodKey) {
            updated = try await repository.markIncomplete(taskID: taskID, periodKey: periodKey)
        } else {
            updated = try await repository.markCompleted(taskID: taskID, periodKey: periodKey, completedAt: .now)
        }

        await syncCoordinator.recordLocalChange(
            SyncChange(entityKind: .periodicTask, operation: .upsert, recordID: updated.id, spaceID: spaceID)
        )
        await reminderScheduler.syncPeriodicTaskReminder(for: updated, referenceDate: referenceDate)
        return updated
    }

    func deleteTask(in spaceID: UUID, taskID: UUID, actorID: UUID) async throws {
        guard let task = try await repository.fetchTask(taskID: taskID) else {
            throw PeriodicTaskError.notFound
        }
        guard PairPermissionService.canDeletePeriodicTask(task, actorID: actorID) else {
            throw PermissionError.notCreator
        }
        await reminderScheduler.removePeriodicTaskReminder(for: taskID)
        try await repository.deleteTask(taskID: taskID)
        await syncCoordinator.recordLocalChange(
            SyncChange(entityKind: .periodicTask, operation: .delete, recordID: taskID, spaceID: spaceID)
        )
    }
}
