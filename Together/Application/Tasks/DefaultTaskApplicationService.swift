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
        let pinnedCount = actionableItems.filter(\.isPinned).count

        return TaskTodaySummary(
            referenceDate: referenceDate,
            actionableCount: actionableItems.count,
            overdueCount: overdueCount,
            dueTodayCount: dueTodayCount,
            completedTodayCount: completedTodayCount,
            pinnedCount: pinnedCount
        )
    }

    func createTask(in spaceID: UUID, actorID: UUID, draft: TaskDraft) async throws -> Item {
        let now = Date.now
        let assignmentState = draft.assigneeMode == .partner
            ? .pendingResponse
            : ItemStateMachine.initialAssignmentState(for: draft.assigneeMode)
        let assignmentMessages: [TaskAssignmentMessage] = draft.assignmentNote
            .flatMap { note in
                let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
                return trimmed.isEmpty ? nil : [TaskAssignmentMessage(authorID: actorID, body: trimmed, createdAt: now)]
            } ?? []
        let item = Item(
            id: UUID(),
            spaceID: spaceID,
            listID: draft.listID,
            projectID: draft.projectID,
            creatorID: actorID,
            title: draft.title.trimmingCharacters(in: .whitespacesAndNewlines),
            notes: draft.notes,
            locationText: nil,
            executionRole: draft.assigneeMode.legacyExecutionRole,
            assigneeMode: draft.assigneeMode,
            dueAt: draft.dueAt,
            hasExplicitTime: draft.hasExplicitTime,
            remindAt: draft.remindAt,
            status: assignmentState.legacyStatus,
            assignmentState: assignmentState,
            latestResponse: nil,
            responseHistory: [],
            assignmentMessages: assignmentMessages,
            lastActionByUserID: actorID,
            lastActionAt: now,
            createdAt: now,
            updatedAt: now,
            completedAt: nil,
            isPinned: draft.isPinned,
            isDraft: draft.isDraft
            ,
            repeatRule: draft.repeatRule
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
        await reminderScheduler.syncTaskReminder(for: saved)
        return saved
    }

    func updateTask(in spaceID: UUID, taskID: UUID, actorID: UUID, draft: TaskDraft) async throws -> Item {
        var item = try await existingTask(in: spaceID, taskID: taskID)
        guard PairPermissionService.canEditTask(item, actorID: actorID) else {
            throw PermissionError.notCreator
        }
        item.title = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
        item.notes = draft.notes
        item.listID = draft.listID
        item.projectID = draft.projectID
        item.dueAt = draft.dueAt
        item.remindAt = draft.remindAt
        item.executionRole = draft.assigneeMode.legacyExecutionRole
        item.assigneeMode = draft.assigneeMode
        item.assignmentState = draft.assigneeMode == .partner && item.responseHistory.isEmpty
            ? .pendingResponse
            : draft.assignmentState
        item.status = item.assignmentState.legacyStatus
        item.hasExplicitTime = draft.hasExplicitTime
        item.isPinned = draft.isPinned
        item.isDraft = draft.isDraft
        item.repeatRule = draft.repeatRule
        if let note = draft.assignmentNote?.trimmingCharacters(in: .whitespacesAndNewlines), note.isEmpty == false {
            item.assignmentMessages.append(TaskAssignmentMessage(authorID: actorID, body: note, createdAt: .now))
        }
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
        await reminderScheduler.syncTaskReminder(for: saved)
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
        guard PairPermissionService.canEditTask(item, actorID: actorID) else {
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
        await reminderScheduler.syncTaskReminder(for: saved)
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
        guard PairPermissionService.canEditTask(item, actorID: actorID) else {
            throw PermissionError.notCreator
        }
        item.dueAt = dueAt
        item.remindAt = remindAt
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
        await reminderScheduler.syncTaskReminder(for: saved)
        return saved
    }

    func snoozeTask(
        in spaceID: UUID,
        taskID: UUID,
        actorID: UUID,
        option: TaskSnoozeOption
    ) async throws -> Item {
        var item = try await existingTask(in: spaceID, taskID: taskID)
        guard PairPermissionService.canEditTask(item, actorID: actorID) else {
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
        await reminderScheduler.syncTaskReminder(for: saved)
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
            await reminderScheduler.syncTaskReminder(for: saved)
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
        await reminderScheduler.syncTaskReminder(for: item)
        return item
    }

    func archiveTask(in spaceID: UUID, taskID: UUID, actorID: UUID) async throws -> Item {
        var item = try await existingTask(in: spaceID, taskID: taskID)
        guard PairPermissionService.canDeleteTask(item, actorID: actorID) else {
            throw PermissionError.notCreator
        }
        item.isArchived = true
        item.archivedAt = .now
        item.isPinned = false
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
        return saved
    }

    func deleteTask(in spaceID: UUID, taskID: UUID, actorID: UUID) async throws {
        let item = try await existingTask(in: spaceID, taskID: taskID)
        guard PairPermissionService.canDeleteTask(item, actorID: actorID) else {
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
    }

    func respondToTask(
        in spaceID: UUID,
        taskID: UUID,
        actorID: UUID,
        response: ItemResponseKind,
        message: String?
    ) async throws -> Item {
        let item = try await itemRepository.updateItemStatus(
            itemID: taskID,
            response: response,
            message: message,
            actorID: actorID
        )
        await syncCoordinator.recordLocalChange(
            SyncChange(
                entityKind: .task,
                operation: .upsert,
                recordID: item.id,
                spaceID: spaceID
            )
        )
        return item
    }

    func requeueDeclinedTask(
        in spaceID: UUID,
        taskID: UUID,
        actorID: UUID
    ) async throws -> Item {
        var item = try await existingTask(in: spaceID, taskID: taskID)
        guard item.creatorID == actorID else { throw RepositoryError.notFound }
        guard item.assigneeMode == .partner else { throw RepositoryError.notFound }
        guard item.assignmentState == .declined else { throw RepositoryError.notFound }

        item.assignmentState = .pendingResponse
        item.status = .pendingConfirmation
        item.latestResponse = nil
        item.responseHistory = []
        item.assignmentMessages.removeAll { $0.authorID != actorID }
        // 添加"再次发送"系统消息，让对方看到有意义的上下文
        item.assignmentMessages.append(
            TaskAssignmentMessage(authorID: actorID, body: "再次发送了这个任务", createdAt: .now)
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
        return saved
    }

    /// No creatorID permission check: both task creator and assignee can exchange messages.
    func appendAssignmentMessage(
        in spaceID: UUID,
        taskID: UUID,
        actorID: UUID,
        message: String
    ) async throws -> Item {
        var item = try await existingTask(in: spaceID, taskID: taskID)
        let trimmedMessage = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedMessage.isEmpty == false else { return item }

        item.assignmentMessages.append(
            TaskAssignmentMessage(authorID: actorID, body: trimmedMessage, createdAt: .now)
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
        return saved
    }

    /// No creatorID permission check: task creator sends reminders to the assignee (partner).
    func sendReminderToPartner(
        in spaceID: UUID,
        taskID: UUID,
        actorID: UUID
    ) async throws -> Item {
        var item = try await existingTask(in: spaceID, taskID: taskID)
        guard item.assigneeMode == .partner else { throw RepositoryError.notFound }

        // 冷却检查：30 秒内不允许重复催促
        if let lastReminder = item.reminderRequestedAt,
           Date.now.timeIntervalSince(lastReminder) < 30 {
            return item
        }

        item.reminderRequestedAt = .now
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
        return saved
    }

    private func existingTask(in spaceID: UUID, taskID: UUID) async throws -> Item {
        let items = try await itemRepository.fetchActiveItems(spaceID: spaceID)
        guard let item = items.first(where: { $0.id == taskID }) else {
            throw RepositoryError.notFound
        }
        return item
    }

    private func snoozeDueDate(for item: Item, option: TaskSnoozeOption, now: Date) -> Date? {
        switch option {
        case .tomorrow:
            let baseDate = item.dueAt ?? now
            if item.hasExplicitTime, let dueAt = item.dueAt {
                return calendar.date(byAdding: .day, value: 1, to: dueAt) ?? dueAt
            }
            let tomorrow = calendar.date(byAdding: .day, value: 1, to: baseDate) ?? baseDate
            return calendar.startOfDay(for: tomorrow)
        case let .minutes(minutes):
            let baseDate = item.dueAt.map { max($0, now) } ?? now
            let future = baseDate.addingTimeInterval(TimeInterval(minutes * 60))
            let roundedMinute = Int((Double(calendar.component(.minute, from: future)) / 5.0).rounded()) * 5
            let minuteOverflow = roundedMinute / 60
            let normalizedMinute = roundedMinute % 60
            let normalizedHour = (calendar.component(.hour, from: future) + minuteOverflow) % 24
            return calendar.date(
                bySettingHour: normalizedHour,
                minute: normalizedMinute,
                second: 0,
                of: future
            ) ?? future
        case let .custom(date, _):
            return date
        }
    }

    private func hasExplicitTime(for item: Item, option: TaskSnoozeOption) -> Bool {
        switch option {
        case .tomorrow:
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
        case .pinned:
            return item.isPinned
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
        if lhs.isPinned != rhs.isPinned {
            return lhs.isPinned && rhs.isPinned == false
        }

        let lhsCompleted = lhs.isCompleted(on: referenceDate, calendar: calendar)
        let rhsCompleted = rhs.isCompleted(on: referenceDate, calendar: calendar)
        if lhsCompleted != rhsCompleted {
            return rhsCompleted
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
        case .all, .pinned, .list, .project:
            return nil
        }
    }
}
