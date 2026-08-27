import Foundation

actor DefaultTaskApplicationService: TaskApplicationServiceProtocol {
    private let itemRepository: ItemRepositoryProtocol
    private let syncCoordinator: SyncCoordinatorProtocol
    private let reminderScheduler: ReminderSchedulerProtocol
    private let calendar = Calendar.current

    init(
        itemRepository: ItemRepositoryProtocol,
        syncCoordinator: SyncCoordinatorProtocol,
        reminderScheduler: ReminderSchedulerProtocol
    ) {
        self.itemRepository = itemRepository
        self.syncCoordinator = syncCoordinator
        self.reminderScheduler = reminderScheduler
    }

    func tasks(in spaceID: UUID, scope: TaskScope) async throws -> [Item] {
        let items = try await itemRepository.fetchActiveItems(spaceID: spaceID)
        return items
            .filter { matches($0, scope: scope) }
            .sorted { compareItems(lhs: $0, rhs: $1, referenceDate: scope.referenceDate ?? .now) }
    }

    func todaySummary(in spaceID: UUID, referenceDate: Date) async throws -> TaskTodaySummary {
        let items = try await itemRepository.fetchActiveItems(spaceID: spaceID)
        let dayRange = dateRange(for: referenceDate)
        let visibleItems = items.filter { matches($0, scope: .today(referenceDate: referenceDate)) }
        let actionableItems = visibleItems.filter {
            $0.isCompleted(on: referenceDate, calendar: calendar) == false && $0.status != .completed
        }
        let completedTodayCount = items.filter {
            $0.isCompleted(on: referenceDate, calendar: calendar)
                || ($0.completedAt.map(dayRange.contains) ?? false)
        }.count
        let overdueCount = actionableItems.filter { isOverdue($0, on: referenceDate) }.count
        let dueTodayCount = actionableItems.filter { isDueOnReferenceDay($0, referenceDate: referenceDate) }.count
        let urgentCount = actionableItems.filter(\.isUrgent).count

        return TaskTodaySummary(
            referenceDate: referenceDate,
            actionableCount: actionableItems.count,
            overdueCount: overdueCount,
            dueTodayCount: dueTodayCount,
            completedTodayCount: completedTodayCount,
            urgentCount: urgentCount
        )
    }

    func createTask(id itemID: UUID, in spaceID: UUID, actorID: UUID, draft: TaskDraft) async throws -> Item {
        let now = Date.now
        let schedule = normalizedSchedule(
            dueAt: draft.dueAt,
            hasExplicitTime: draft.hasExplicitTime,
            remindAt: draft.remindAt,
            referenceDate: now
        )
        let item = Item(
            id: itemID,
            spaceID: spaceID,
            listID: draft.listID,
            projectID: draft.projectID,
            creatorID: actorID,
            title: draft.title.trimmingCharacters(in: .whitespacesAndNewlines),
            notes: draft.notes,
            locationText: nil,
            dueAt: schedule.dueAt,
            hasExplicitTime: schedule.hasExplicitTime,
            remindAt: schedule.remindAt,
            status: draft.status,
            lastActionByUserID: actorID,
            lastActionAt: now,
            createdAt: now,
            updatedAt: now,
            completedAt: nil,
            subtasks: makeTaskSubtasks(
                itemID: itemID,
                creatorID: actorID,
                drafts: draft.subtasks
            ),
            sortOrder: now.timeIntervalSinceReferenceDate,
            isUrgent: draft.isUrgent,
            isDraft: draft.isDraft,
            repeatRule: nil,
            isFollowed: draft.shouldFollowOnCreation,
            followedAt: draft.shouldFollowOnCreation ? now : nil
        )

        let saved = try await itemRepository.saveItem(item)
        await syncCoordinator.recordLocalChange(
            SyncChange(
                entityKind: .task,
                operation: .upsert,
                recordID: saved.id,
                spaceID: spaceID
            )
        )
        await syncReminderState(for: saved, in: spaceID)
        return saved
    }

    func updateTask(in spaceID: UUID, taskID: UUID, actorID: UUID, draft: TaskDraft) async throws -> Item {
        var item = try await existingTask(in: spaceID, taskID: taskID)
        guard SoloPermissionService.canEditTask(item, actorID: actorID) else {
            throw PermissionError.notCreator
        }
        item.title = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
        item.notes = draft.notes
        item.listID = draft.listID
        item.projectID = draft.projectID
        let schedule = normalizedSchedule(
            dueAt: draft.dueAt,
            hasExplicitTime: draft.hasExplicitTime,
            remindAt: draft.remindAt,
            referenceDate: .now
        )
        item.dueAt = schedule.dueAt
        item.remindAt = schedule.remindAt
        item.status = draft.status
        item.hasExplicitTime = schedule.hasExplicitTime
        item.isUrgent = draft.isUrgent
        item.isDraft = draft.isDraft
        item.repeatRule = nil
        item.subtasks = makeTaskSubtasks(
            itemID: item.id,
            creatorID: item.creatorID,
            drafts: draft.subtasks
        )
        item.lastActionByUserID = actorID
        item.lastActionAt = .now
        item.updatedAt = .now

        let saved = try await itemRepository.saveItem(item)
        await syncCoordinator.recordLocalChange(
            SyncChange(
                entityKind: .task,
                operation: .upsert,
                recordID: saved.id,
                spaceID: spaceID
            )
        )
        await syncReminderState(for: saved, in: spaceID)
        return saved
    }

    func moveTask(
        in spaceID: UUID,
        taskID: UUID,
        actorID: UUID,
        listID: UUID?,
        projectID: UUID?
    ) async throws -> Item {
        var item = try await existingTask(in: spaceID, taskID: taskID)
        guard SoloPermissionService.canEditTask(item, actorID: actorID) else {
            throw PermissionError.notCreator
        }
        item.listID = listID
        item.projectID = projectID
        item.updatedAt = .now

        let saved = try await itemRepository.saveItem(item)
        await syncCoordinator.recordLocalChange(
            SyncChange(
                entityKind: .task,
                operation: .upsert,
                recordID: saved.id,
                spaceID: spaceID
            )
        )
        await syncReminderState(for: saved, in: spaceID)
        return saved
    }

    func rescheduleTask(
        in spaceID: UUID,
        taskID: UUID,
        actorID: UUID,
        dueAt: Date?,
        remindAt: Date?
    ) async throws -> Item {
        var item = try await existingTask(in: spaceID, taskID: taskID)
        guard SoloPermissionService.canEditTask(item, actorID: actorID) else {
            throw PermissionError.notCreator
        }
        let schedule = normalizedSchedule(
            dueAt: dueAt,
            hasExplicitTime: item.hasExplicitTime,
            remindAt: remindAt,
            referenceDate: .now
        )
        item.dueAt = schedule.dueAt
        item.hasExplicitTime = schedule.hasExplicitTime
        item.remindAt = schedule.remindAt
        item.updatedAt = .now

        let saved = try await itemRepository.saveItem(item)
        await syncCoordinator.recordLocalChange(
            SyncChange(
                entityKind: .task,
                operation: .upsert,
                recordID: saved.id,
                spaceID: spaceID
            )
        )
        await syncReminderState(for: saved, in: spaceID)
        return saved
    }

    private func normalizedSchedule(
        dueAt: Date?,
        hasExplicitTime: Bool,
        remindAt: Date?,
        referenceDate: Date
    ) -> (dueAt: Date, hasExplicitTime: Bool, remindAt: Date?) {
        guard let dueAt else {
            return (
                calendar.startOfDay(for: referenceDate),
                false,
                nil
            )
        }
        return (
            dueAt,
            hasExplicitTime,
            remindAt
        )
    }

    func snoozeTask(
        in spaceID: UUID,
        taskID: UUID,
        actorID: UUID,
        option: TaskSnoozeOption
    ) async throws -> Item {
        var item = try await existingTask(in: spaceID, taskID: taskID)
        guard SoloPermissionService.canEditTask(item, actorID: actorID) else {
            throw PermissionError.notCreator
        }
        guard item.status != .completed, item.completedAt == nil else {
            return item
        }

        let now = Date.now
        let targetDueAt = snoozeDueDate(for: item, option: option, now: now)
        let reminderDelta = reminderDelta(for: item)

        item.dueAt = targetDueAt
        item.hasExplicitTime = hasExplicitTime(for: item, option: option)
        if let reminderDelta {
            item.remindAt = targetDueAt?.addingTimeInterval(reminderDelta)
        } else if case let .custom(customDate, _) = option, customDate > now, item.remindAt != nil {
            item.remindAt = customDate
        }
        item.updatedAt = now

        let saved = try await itemRepository.saveItem(item)
        await syncCoordinator.recordLocalChange(
            SyncChange(
                entityKind: .task,
                operation: .upsert,
                recordID: saved.id,
                spaceID: spaceID
            )
        )
        await syncReminderState(for: saved, in: spaceID)
        return saved
    }

    func toggleTaskCompletion(
        in spaceID: UUID,
        taskID: UUID,
        actorID: UUID,
        referenceDate: Date
    ) async throws -> Item {
        let existing = try await existingTask(in: spaceID, taskID: taskID)
        let isCompletedOnReferenceDate = existing.isCompleted(on: referenceDate, calendar: calendar)

        if isCompletedOnReferenceDate || existing.status == .completed {
            let saved = try await itemRepository.markIncomplete(
                itemID: taskID,
                actorID: actorID,
                referenceDate: referenceDate
            )
            await syncCoordinator.recordLocalChange(
                SyncChange(
                    entityKind: .task,
                    operation: .upsert,
                    recordID: saved.id,
                    spaceID: spaceID
                )
            )
            await syncReminderState(for: saved, in: spaceID)
            return saved
        }

        return try await completeTask(
            in: spaceID,
            taskID: taskID,
            actorID: actorID,
            referenceDate: referenceDate
        )
    }

    func completeTask(
        in spaceID: UUID,
        taskID: UUID,
        actorID: UUID,
        referenceDate: Date
    ) async throws -> Item {
        let item = try await itemRepository.markCompleted(
            itemID: taskID,
            actorID: actorID,
            referenceDate: referenceDate
        )
        await syncCoordinator.recordLocalChange(
            SyncChange(
                entityKind: .task,
                operation: .complete,
                recordID: item.id,
                spaceID: spaceID
            )
        )
        await syncReminderState(for: item, in: spaceID)
        return item
    }

    func setTaskFollowed(
        in spaceID: UUID,
        taskID: UUID,
        actorID: UUID,
        isFollowed: Bool
    ) async throws -> Item {
        var item = try await existingTask(in: spaceID, taskID: taskID)
        guard SoloPermissionService.canEditTask(item, actorID: actorID) else {
            throw PermissionError.notCreator
        }
        guard item.repeatRule == nil else {
            throw RepositoryError.invalidInput("定期任务暂不支持关注")
        }
        guard item.status != .completed, item.completedAt == nil else {
            throw RepositoryError.invalidInput("已完成任务不能关注")
        }
        guard item.isFollowed != isFollowed else { return item }

        let now = Date.now
        item.isFollowed = isFollowed
        item.followedAt = isFollowed ? now : nil
        item.lastActionByUserID = actorID
        item.lastActionAt = now
        item.updatedAt = now

        return try await itemRepository.saveItem(item)
    }

    func addTaskSubtask(in spaceID: UUID, taskID: UUID, actorID: UUID, title: String) async throws -> Item {
        let item = try await existingTask(in: spaceID, taskID: taskID)
        guard SoloPermissionService.canEditTask(item, actorID: actorID) else {
            throw PermissionError.notCreator
        }
        let saved = try await itemRepository.addSubtask(itemID: taskID, title: title, creatorID: actorID)
        await syncReminderState(for: saved, in: spaceID)
        return saved
    }

    func toggleTaskSubtask(in spaceID: UUID, taskID: UUID, subtaskID: UUID, actorID: UUID) async throws -> Item {
        let item = try await existingTask(in: spaceID, taskID: taskID)
        guard SoloPermissionService.canEditTask(item, actorID: actorID) else {
            throw PermissionError.notCreator
        }
        let saved = try await itemRepository.toggleSubtask(itemID: taskID, subtaskID: subtaskID, actorID: actorID)
        await syncReminderState(for: saved, in: spaceID)
        return saved
    }

    func updateTaskSubtask(in spaceID: UUID, taskID: UUID, subtaskID: UUID, actorID: UUID, title: String) async throws -> Item {
        let item = try await existingTask(in: spaceID, taskID: taskID)
        guard SoloPermissionService.canEditTask(item, actorID: actorID) else {
            throw PermissionError.notCreator
        }
        let saved = try await itemRepository.updateSubtask(itemID: taskID, subtaskID: subtaskID, title: title, actorID: actorID)
        await syncReminderState(for: saved, in: spaceID)
        return saved
    }

    func deleteTaskSubtask(in spaceID: UUID, taskID: UUID, subtaskID: UUID, actorID: UUID) async throws -> Item {
        let item = try await existingTask(in: spaceID, taskID: taskID)
        guard SoloPermissionService.canEditTask(item, actorID: actorID) else {
            throw PermissionError.notCreator
        }
        let saved = try await itemRepository.deleteSubtask(itemID: taskID, subtaskID: subtaskID, actorID: actorID)
        await syncReminderState(for: saved, in: spaceID)
        return saved
    }

    func archiveTask(in spaceID: UUID, taskID: UUID, actorID: UUID) async throws -> Item {
        var item = try await existingTask(in: spaceID, taskID: taskID)
        guard SoloPermissionService.canDeleteTask(item, actorID: actorID) else {
            throw PermissionError.notCreator
        }
        item.isArchived = true
        item.archivedAt = .now
        item.isUrgent = false
        item.isFollowed = false
        item.followedAt = nil
        item.updatedAt = .now

        let saved = try await itemRepository.saveItem(item)
        await syncCoordinator.recordLocalChange(
            SyncChange(
                entityKind: .task,
                operation: .archive,
                recordID: saved.id,
                spaceID: spaceID
            )
        )
        await reminderScheduler.removeTaskReminder(for: saved.id)
        await syncDailySummary(in: spaceID)
        return saved
    }

    func deleteTask(in spaceID: UUID, taskID: UUID, actorID: UUID) async throws {
        let item = try await existingTask(in: spaceID, taskID: taskID)
        guard SoloPermissionService.canDeleteTask(item, actorID: actorID) else {
            throw PermissionError.notCreator
        }
        try await itemRepository.deleteItem(itemID: taskID)
        await syncCoordinator.recordLocalChange(
            SyncChange(
                entityKind: .task,
                operation: .delete,
                recordID: taskID,
                spaceID: spaceID
            )
        )
        await reminderScheduler.removeTaskReminder(for: taskID)
        await syncDailySummary(in: spaceID)
    }

    private func syncReminderState(for item: Item, in spaceID: UUID) async {
        await reminderScheduler.syncTaskReminder(for: item)
        await syncDailySummary(in: spaceID)
    }

    private func syncDailySummary(in spaceID: UUID) async {
        guard let tasks = try? await itemRepository.fetchActiveItems(spaceID: spaceID) else { return }
        await reminderScheduler.syncDailySummary(for: spaceID, tasks: tasks)
    }

    private func makeTaskSubtasks(
        itemID: UUID,
        creatorID: UUID,
        drafts: [TaskSubtaskDraft]
    ) -> [TaskSubtask] {
        drafts
            .sorted { $0.sortOrder < $1.sortOrder }
            .enumerated()
            .compactMap { index, draft in
                let trimmed = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
                guard trimmed.isEmpty == false else { return nil }
                return TaskSubtask(
                    id: draft.id,
                    itemID: itemID,
                    creatorID: creatorID,
                    title: trimmed,
                    isCompleted: draft.isCompleted,
                    sortOrder: index,
                    sourceTaskID: draft.sourceTaskID,
                    sourceNotes: draft.sourceNotes,
                    sourceDueAt: draft.sourceDueAt,
                    sourceHasExplicitTime: draft.sourceHasExplicitTime,
                    sourceRemindAt: draft.sourceRemindAt,
                    sourceCreatedAt: draft.sourceCreatedAt,
                    sourceCompletedAt: draft.sourceCompletedAt
                )
            }
    }

    private func existingTask(in spaceID: UUID, taskID: UUID) async throws -> Item {
        let items = try await itemRepository.fetchActiveItems(spaceID: spaceID)
        guard let item = items.first(where: { $0.id == taskID }) else {
            throw RepositoryError.notFound
        }
        return item
    }

    private func snoozeDueDate(for item: Item, option: TaskSnoozeOption, now: Date) -> Date? {
        TaskSnoozeDateCalculator.dueDate(
            currentDueAt: item.dueAt,
            hasExplicitTime: item.hasExplicitTime,
            option: option,
            now: now,
            calendar: calendar
        )
    }

    private func hasExplicitTime(for item: Item, option: TaskSnoozeOption) -> Bool {
        switch option {
        case .tomorrow, .nextMonday:
            return item.hasExplicitTime
        case .minutes:
            return true
        case let .custom(_, hasExplicitTime):
            return hasExplicitTime
        }
    }

    private func reminderDelta(for item: Item) -> TimeInterval? {
        guard let dueAt = item.dueAt, let remindAt = item.remindAt else { return nil }
        return remindAt.timeIntervalSince(dueAt)
    }

    private func matches(_ item: Item, scope: TaskScope) -> Bool {
        switch scope {
        case .all:
            return true
        case .urgent:
            return item.isUrgent
        case let .list(listID):
            return item.listID == listID
        case let .project(projectID):
            return item.projectID == projectID
        case let .today(referenceDate):
            return item.appearsOnHome(for: referenceDate, includeOverdue: true, calendar: calendar)
        case let .scheduled(on: date):
            return item.appearsOnHome(for: date, includeOverdue: false, calendar: calendar)
        }
    }

    private func compareItems(lhs: Item, rhs: Item, referenceDate: Date) -> Bool {
        let lhsCompleted = lhs.isCompleted(on: referenceDate, calendar: calendar)
        let rhsCompleted = rhs.isCompleted(on: referenceDate, calendar: calendar)
        if lhsCompleted != rhsCompleted {
            return rhsCompleted
        }

        if lhsCompleted == false, lhs.isUrgent != rhs.isUrgent {
            return lhs.isUrgent && rhs.isUrgent == false
        }

        if lhsCompleted == false, lhs.isUrgent, rhs.isUrgent, lhs.createdAt != rhs.createdAt {
            return lhs.createdAt < rhs.createdAt
        }

        let lhsOverdue = isOverdue(lhs, on: referenceDate)
        let rhsOverdue = isOverdue(rhs, on: referenceDate)
        if lhsOverdue != rhsOverdue {
            return lhsOverdue && rhsOverdue == false
        }

        let lhsDue = lhs.dueAt ?? .distantFuture
        let rhsDue = rhs.dueAt ?? .distantFuture
        if lhsDue != rhsDue {
            return lhsDue < rhsDue
        }

        return lhs.updatedAt > rhs.updatedAt
    }

    private func isDueOnReferenceDay(_ item: Item, referenceDate: Date) -> Bool {
        item.occurs(on: referenceDate, calendar: calendar)
    }

    private func isOverdue(_ item: Item, on referenceDate: Date) -> Bool {
        item.isOverdue(on: referenceDate, calendar: calendar)
    }

    private func dateRange(for date: Date) -> Range<Date> {
        let start = calendar.startOfDay(for: date)
        let end = calendar.date(byAdding: .day, value: 1, to: start) ?? start
        return start..<end
    }
}

private extension TaskScope {
    nonisolated var referenceDate: Date? {
        switch self {
        case let .today(referenceDate):
            return referenceDate
        case let .scheduled(on: date):
            return date
        case .all, .urgent, .list, .project:
            return nil
        }
    }
}
