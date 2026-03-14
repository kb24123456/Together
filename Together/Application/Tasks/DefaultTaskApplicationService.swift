import Foundation

actor DefaultTaskApplicationService: TaskApplicationServiceProtocol {
    private let itemRepository: ItemRepositoryProtocol
    private let syncCoordinator: SyncCoordinatorProtocol
    private let calendar = Calendar.current

    init(
        itemRepository: ItemRepositoryProtocol,
        syncCoordinator: SyncCoordinatorProtocol
    ) {
        self.itemRepository = itemRepository
        self.syncCoordinator = syncCoordinator
    }

    func tasks(in spaceID: UUID, scope: TaskScope) async throws -> [Item] {
        let items = try await itemRepository.fetchItems(spaceID: spaceID)
        return items
            .filter { matches($0, scope: scope) }
            .sorted { compareItems(lhs: $0, rhs: $1, referenceDate: scope.referenceDate ?? .now) }
    }

    func todaySummary(in spaceID: UUID, referenceDate: Date) async throws -> TaskTodaySummary {
        let items = try await itemRepository.fetchItems(spaceID: spaceID)
        let dayRange = dateRange(for: referenceDate)
        let actionableItems = items.filter { matches($0, scope: .today(referenceDate: referenceDate)) }
        let completedTodayCount = items.filter {
            guard let completedAt = $0.completedAt else { return false }
            return dayRange.contains(completedAt)
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
        let item = Item(
            id: UUID(),
            spaceID: spaceID,
            listID: draft.listID,
            projectID: draft.projectID,
            creatorID: actorID,
            title: draft.title.trimmingCharacters(in: .whitespacesAndNewlines),
            notes: draft.notes,
            locationText: nil,
            executionRole: draft.executionRole,
            priority: draft.priority,
            dueAt: draft.dueAt,
            remindAt: draft.remindAt,
            status: draft.status,
            latestResponse: nil,
            responseHistory: [],
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
        return saved
    }

    func updateTask(in spaceID: UUID, taskID: UUID, actorID: UUID, draft: TaskDraft) async throws -> Item {
        var item = try await existingTask(in: spaceID, taskID: taskID)
        item.title = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
        item.notes = draft.notes
        item.listID = draft.listID
        item.projectID = draft.projectID
        item.dueAt = draft.dueAt
        item.remindAt = draft.remindAt
        item.priority = draft.priority
        item.executionRole = draft.executionRole
        item.status = draft.status
        item.isPinned = draft.isPinned
        item.isDraft = draft.isDraft
        item.repeatRule = draft.repeatRule
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

    func moveTask(
        in spaceID: UUID,
        taskID: UUID,
        actorID: UUID,
        listID: UUID?,
        projectID: UUID?
    ) async throws -> Item {
        var item = try await existingTask(in: spaceID, taskID: taskID)
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
        return saved
    }

    func toggleTaskCompletion(in spaceID: UUID, taskID: UUID, actorID: UUID) async throws -> Item {
        let existing = try await existingTask(in: spaceID, taskID: taskID)

        if existing.completedAt != nil || existing.status == .completed {
            var restored = existing
            restored.completedAt = nil
            restored.updatedAt = .now
            if restored.status == .completed {
                restored.status = .inProgress
            }

            let saved = try await itemRepository.saveItem(restored)
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

        return try await completeTask(in: spaceID, taskID: taskID, actorID: actorID)
    }

    func completeTask(in spaceID: UUID, taskID: UUID, actorID: UUID) async throws -> Item {
        let item = try await itemRepository.markCompleted(itemID: taskID, actorID: actorID)
        await syncCoordinator.recordLocalChange(
            SyncChange(
                entityKind: .task,
                operation: .complete,
                recordID: item.id,
                spaceID: spaceID
            )
        )
        return item
    }

    func archiveTask(in spaceID: UUID, taskID: UUID, actorID: UUID) async throws -> Item {
        var item = try await existingTask(in: spaceID, taskID: taskID)
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
        return saved
    }

    func respondToTask(in spaceID: UUID, taskID: UUID, actorID: UUID, response: ItemResponseKind) async throws -> Item {
        let item = try await itemRepository.updateItemStatus(itemID: taskID, response: response, actorID: actorID)
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

    private func existingTask(in spaceID: UUID, taskID: UUID) async throws -> Item {
        let items = try await itemRepository.fetchItems(spaceID: spaceID)
        guard let item = items.first(where: { $0.id == taskID }) else {
            throw RepositoryError.notFound
        }
        return item
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

        if lhs.priority != rhs.priority {
            return priorityRank(lhs.priority) > priorityRank(rhs.priority)
        }

        return lhs.updatedAt > rhs.updatedAt
    }

    private func priorityRank(_ priority: ItemPriority) -> Int {
        switch priority {
        case .critical:
            return 3
        case .important:
            return 2
        case .normal:
            return 1
        }
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
    var referenceDate: Date? {
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
