import Foundation

protocol PeriodicTaskApplicationServiceProtocol: Sendable {
    func fetchTasks(in spaceID: UUID) async throws -> [PeriodicTask]
    func createTask(in spaceID: UUID, actorID: UUID, draft: PeriodicTaskDraft) async throws -> PeriodicTask
    func updateTask(in spaceID: UUID, taskID: UUID, actorID: UUID, draft: PeriodicTaskDraft) async throws -> PeriodicTask
    func reorderTasks(in spaceID: UUID, taskIDs: [UUID]) async throws -> [PeriodicTask]
    func toggleCompletion(in spaceID: UUID, taskID: UUID, referenceDate: Date) async throws -> PeriodicTask
    func deferTaskUntilTomorrow(in spaceID: UUID, taskID: UUID, referenceDate: Date) async throws -> PeriodicTask
    func deleteTask(in spaceID: UUID, taskID: UUID, actorID: UUID) async throws
    func alarmAuthorizationStatus() async -> RoutineAlarmAuthorizationStatus
    func requestAlarmAuthorization() async throws -> RoutineAlarmAuthorizationStatus
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

        // Periodic tasks are personal data in the current single-user model. Older
        // records can retain a previous local identity after account restoration,
        // so creatorID is not a valid authorization boundary here. The active
        // space remains the boundary and prevents cross-space mutation.
        guard task.spaceID == spaceID else { throw PeriodicTaskError.notFound }
        _ = actorID

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

    func reorderTasks(in spaceID: UUID, taskIDs: [UUID]) async throws -> [PeriodicTask] {
        let updated = try await repository.reorderTasks(taskIDs: taskIDs)
        for taskID in taskIDs {
            await syncCoordinator.recordLocalChange(
                SyncChange(entityKind: .periodicTask, operation: .upsert, recordID: taskID, spaceID: spaceID)
            )
        }
        return updated
    }

    /// No actorID permission check: periodic tasks are personal routines in the current single-user model.
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

    func deferTaskUntilTomorrow(
        in spaceID: UUID,
        taskID: UUID,
        referenceDate: Date
    ) async throws -> PeriodicTask {
        guard var task = try await repository.fetchTask(taskID: taskID),
              task.spaceID == spaceID else {
            throw PeriodicTaskError.notFound
        }

        let startOfReferenceDay = Calendar.current.startOfDay(for: referenceDate)
        guard let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: startOfReferenceDay) else {
            throw PeriodicTaskError.notSupported
        }

        task.deferredUntil = tomorrow
        task.updatedAt = .now
        let saved = try await repository.saveTask(task)
        await syncCoordinator.recordLocalChange(
            SyncChange(entityKind: .periodicTask, operation: .upsert, recordID: saved.id, spaceID: spaceID)
        )
        await reminderScheduler.syncPeriodicTaskReminder(for: saved, referenceDate: referenceDate)
        return saved
    }

    func deleteTask(in spaceID: UUID, taskID: UUID, actorID: UUID) async throws {
        guard let task = try await repository.fetchTask(taskID: taskID),
              task.spaceID == spaceID else {
            throw PeriodicTaskError.notFound
        }
        _ = actorID
        await reminderScheduler.removePeriodicTaskReminder(for: taskID)
        try await repository.deleteTask(taskID: taskID)
        await syncCoordinator.recordLocalChange(
            SyncChange(entityKind: .periodicTask, operation: .delete, recordID: taskID, spaceID: spaceID)
        )
    }

    func alarmAuthorizationStatus() async -> RoutineAlarmAuthorizationStatus {
        await reminderScheduler.periodicAlarmAuthorizationStatus()
    }

    func requestAlarmAuthorization() async throws -> RoutineAlarmAuthorizationStatus {
        try await reminderScheduler.requestPeriodicAlarmAuthorization()
    }
}
