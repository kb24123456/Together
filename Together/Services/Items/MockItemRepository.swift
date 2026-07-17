import Foundation

@MainActor
final class MockItemRepository: ItemRepositoryProtocol {
    private var items: [Item]
    private var occurrenceCompletions: [UUID: [ItemOccurrenceCompletion]] = [:]
    private let calendar = Calendar.current
    private let throwsOnCompletedItemCount: Bool
    private let throwsOnFetchCompletedItems: Bool
    var throwsOnFetchHomeItems = false
    var homeItemsFetchTransform: ([Item]) -> [Item] = { $0 }

    init(throwsOnCompletedItemCount: Bool = false, throwsOnFetchCompletedItems: Bool = false) {
        self.items = MockDataFactory.makeItems()
        self.throwsOnCompletedItemCount = throwsOnCompletedItemCount
        self.throwsOnFetchCompletedItems = throwsOnFetchCompletedItems
    }

    init(
        items: [Item],
        throwsOnCompletedItemCount: Bool = false,
        throwsOnFetchCompletedItems: Bool = false
    ) {
        self.items = items
        self.throwsOnCompletedItemCount = throwsOnCompletedItemCount
        self.throwsOnFetchCompletedItems = throwsOnFetchCompletedItems
    }

    func fetchActiveItems(spaceID: UUID?) async throws -> [Item] {
        return items
            .filter { $0.spaceID == spaceID && $0.isArchived == false }
            .map(hydratedItem)
            .sorted { $0.updatedAt > $1.updatedAt }
    }

    func fetchHomeItems(spaceID: UUID?, completedFrom: Date, completedBefore: Date) async throws -> [Item] {
        if throwsOnFetchHomeItems {
            throw RepositoryError.invalidInput("home items failed")
        }

        let fetchedItems = items
            .filter { item in
                guard item.spaceID == spaceID && item.isArchived == false else { return false }
                guard item.status == .completed || item.completedAt != nil else { return true }
                guard let completedAt = item.completedAt else { return false }
                return completedAt >= completedFrom && completedAt < completedBefore
            }
            .map(hydratedItem)
            .sorted { $0.updatedAt > $1.updatedAt }
        return homeItemsFetchTransform(fetchedItems)
    }

    func fetchArchivedCompletedItems(
        spaceID: UUID?,
        searchText: String?,
        before: Date?,
        limit: Int
    ) async throws -> [Item] {
        let normalizedLimit = max(limit, 1)
        let normalizedSearch = searchText?.trimmingCharacters(in: .whitespacesAndNewlines)

        return items
            .filter { item in
                guard item.spaceID == spaceID else { return false }
                guard item.isArchived, item.completedAt != nil, let archivedAt = item.archivedAt else {
                    return false
                }
                if let before, archivedAt >= before {
                    return false
                }
                guard let normalizedSearch, normalizedSearch.isEmpty == false else {
                    return true
                }
                return item.title.localizedStandardContains(normalizedSearch)
            }
            .sorted { ($0.archivedAt ?? .distantPast) > ($1.archivedAt ?? .distantPast) }
            .prefix(normalizedLimit)
            .map { $0 }
    }

    func completedItemStats(spaceID: UUID?, referenceDate: Date) async throws -> CompletedItemStats {
        let spaceItems = items.filter { $0.spaceID == spaceID && $0.completedAt != nil }
        guard spaceItems.isEmpty == false else { return .empty }

        let monthComponents = calendar.dateComponents([.year, .month], from: referenceDate)
        let thisMonthCount = spaceItems.filter { item in
            guard let completedAt = item.completedAt else { return false }
            let comps = calendar.dateComponents([.year, .month], from: completedAt)
            return comps.year == monthComponents.year && comps.month == monthComponents.month
        }.count

        let firstItem = spaceItems.min { a, b in
            (a.completedAt ?? .distantFuture) < (b.completedAt ?? .distantFuture)
        }
        let lastCompletedAt = spaceItems.compactMap(\.completedAt).max()

        return CompletedItemStats(
            totalCount: spaceItems.count,
            thisMonthCount: thisMonthCount,
            firstCompletedAt: firstItem?.completedAt,
            firstItemTitle: firstItem?.title,
            lastCompletedAt: lastCompletedAt
        )
    }

    func fetchCompletedItems(
        spaceID: UUID?,
        searchText: String?,
        before: Date?,
        since: Date?,
        limit: Int
    ) async throws -> [Item] {
        try await fetchCompletedItems(
            spaceID: spaceID,
            searchText: searchText,
            completedFrom: since,
            completedBefore: nil,
            before: before,
            limit: limit
        )
    }

    func fetchCompletedItems(
        spaceID: UUID?,
        searchText: String?,
        completedFrom: Date?,
        completedBefore: Date?,
        before: Date?,
        limit: Int
    ) async throws -> [Item] {
        if throwsOnFetchCompletedItems {
            throw RepositoryError.invalidInput("completed items failed")
        }

        let normalizedLimit = max(limit, 1)
        let normalizedSearch = searchText?.trimmingCharacters(in: .whitespacesAndNewlines)

        return items
            .map(hydratedItem)
            .filter { item in
                guard item.spaceID == spaceID else { return false }
                guard let completedAt = item.completedAt else { return false }
                let cursorDate = item.archivedAt ?? completedAt
                if let before, cursorDate >= before {
                    return false
                }
                if let completedFrom, completedAt < completedFrom {
                    return false
                }
                if let completedBefore, completedAt >= completedBefore {
                    return false
                }
                guard let normalizedSearch, normalizedSearch.isEmpty == false else {
                    return true
                }
                return item.matchesCompletedHistorySearch(normalizedSearch)
            }
            .sorted {
                ($0.archivedAt ?? $0.completedAt ?? .distantPast) > ($1.archivedAt ?? $1.completedAt ?? .distantPast)
            }
            .prefix(normalizedLimit)
            .map { $0 }
    }

    func completedItemCount(
        spaceID: UUID?,
        completedFrom: Date?,
        completedBefore: Date?
    ) async throws -> Int {
        if throwsOnCompletedItemCount {
            throw RepositoryError.invalidInput("completed count failed")
        }

        return items.filter { item in
            guard item.spaceID == spaceID else { return false }
            guard let completedAt = item.completedAt else { return false }
            if let completedFrom, completedAt < completedFrom {
                return false
            }
            if let completedBefore, completedAt >= completedBefore {
                return false
            }
            return true
        }.count
    }

    func archiveCompletedItemsIfNeeded(
        spaceID: UUID?,
        referenceDate: Date,
        autoArchiveDays: Int
    ) async throws -> Bool {
        let thresholdDays = NotificationSettings.normalizedCompletedTaskAutoArchiveDays(autoArchiveDays)
        guard let cutoffDate = calendar.date(byAdding: .day, value: -thresholdDays, to: referenceDate) else {
            return false
        }

        var didArchiveItems = false
        items = items.map { item in
            guard item.spaceID == spaceID else { return item }
            guard item.isArchived == false, let completedAt = item.completedAt else { return item }
            guard completedAt <= cutoffDate else { return item }

            var copy = item
            copy.isArchived = true
            copy.archivedAt = referenceDate
            copy.isUrgent = false
            didArchiveItems = true
            return copy
        }
        return didArchiveItems
    }

    func restoreArchivedItem(itemID: UUID) async throws -> Item {
        guard let index = items.firstIndex(where: { $0.id == itemID }) else {
            throw RepositoryError.notFound
        }

        items[index].isArchived = false
        items[index].archivedAt = nil
        return items[index]
    }

    func fetchItem(itemID: UUID) async throws -> Item? {
        guard let item = items.first(where: { $0.id == itemID }) else { return nil }
        return hydratedItem(item)
    }

    func fetchOccurrenceCompletions(itemIDs: [UUID]) async throws -> [UUID: [ItemOccurrenceCompletion]] {
        var result: [UUID: [ItemOccurrenceCompletion]] = [:]
        for itemID in itemIDs {
            result[itemID] = occurrenceCompletions[itemID, default: []]
        }
        return result
    }

    func isCompleted(itemID: UUID, on referenceDate: Date) async throws -> Bool {
        guard let item = items.first(where: { $0.id == itemID }) else {
            throw RepositoryError.notFound
        }
        return hydratedItem(item).isCompleted(on: referenceDate, calendar: calendar)
    }

    func markCompleted(itemID: UUID, actorID: UUID, referenceDate: Date) async throws -> Item {
        guard let index = items.firstIndex(where: { $0.id == itemID }) else {
            throw RepositoryError.notFound
        }

        var item = items[index]
        if item.repeatRule == nil {
            item.status = ItemStateMachine.nextStatus(
                from: item.status,
                isCompletion: true
            )
            item.completedAt = MockDataFactory.now
        } else {
            upsertOccurrenceCompletion(itemID: itemID, referenceDate: referenceDate, completedAt: MockDataFactory.now)
            item.completedAt = nil
        }
        item.lastActionByUserID = actorID
        item.lastActionAt = MockDataFactory.now
        item.completedByUserID = actorID
        item.isArchived = false
        item.archivedAt = nil
        item.updatedAt = MockDataFactory.now
        items[index] = item
        return hydratedItem(item)
    }

    func markIncomplete(itemID: UUID, actorID: UUID, referenceDate: Date) async throws -> Item {
        guard let index = items.firstIndex(where: { $0.id == itemID }) else {
            throw RepositoryError.notFound
        }

        var item = items[index]
        if item.repeatRule == nil {
            item.completedAt = nil
            if item.status == .completed {
                item.status = .inProgress
            }
        } else {
            deleteOccurrenceCompletion(itemID: itemID, referenceDate: referenceDate)
            item.completedAt = nil
        }
        item.lastActionByUserID = actorID
        item.lastActionAt = MockDataFactory.now
        item.completedByUserID = nil
        item.isArchived = false
        item.archivedAt = nil
        item.updatedAt = MockDataFactory.now
        items[index] = item
        return hydratedItem(item)
    }

    func saveItem(_ item: Item) async throws -> Item {
        var updatedItem = item
        updatedItem.updatedAt = MockDataFactory.now
        if let index = items.firstIndex(where: { $0.id == item.id }) {
            items[index] = updatedItem
        } else {
            items.append(updatedItem)
        }
        return hydratedItem(updatedItem)
    }

    func addSubtask(itemID: UUID, title: String, creatorID: UUID) async throws -> Item {
        guard let index = items.firstIndex(where: { $0.id == itemID }) else {
            throw RepositoryError.notFound
        }
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else {
            throw RepositoryError.invalidInput("子任务标题不能为空")
        }
        let subtask = TaskSubtask(
            itemID: itemID,
            creatorID: creatorID,
            title: trimmed,
            sortOrder: items[index].subtasks.count,
            updatedAt: MockDataFactory.now
        )
        items[index].subtasks.append(subtask)
        items[index].updatedAt = MockDataFactory.now
        return hydratedItem(items[index])
    }

    func toggleSubtask(itemID: UUID, subtaskID: UUID, actorID: UUID) async throws -> Item {
        guard let itemIndex = items.firstIndex(where: { $0.id == itemID }) else {
            throw RepositoryError.notFound
        }
        guard let subtaskIndex = items[itemIndex].subtasks.firstIndex(where: { $0.id == subtaskID }) else {
            throw RepositoryError.notFound
        }
        items[itemIndex].subtasks[subtaskIndex].isCompleted.toggle()
        items[itemIndex].subtasks[subtaskIndex].updatedAt = MockDataFactory.now
        items[itemIndex].updatedAt = MockDataFactory.now
        return hydratedItem(items[itemIndex])
    }

    func updateSubtask(itemID: UUID, subtaskID: UUID, title: String, actorID: UUID) async throws -> Item {
        guard let itemIndex = items.firstIndex(where: { $0.id == itemID }) else {
            throw RepositoryError.notFound
        }
        guard let subtaskIndex = items[itemIndex].subtasks.firstIndex(where: { $0.id == subtaskID }) else {
            throw RepositoryError.notFound
        }
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else {
            throw RepositoryError.invalidInput("子任务标题不能为空")
        }
        items[itemIndex].subtasks[subtaskIndex].title = trimmed
        items[itemIndex].subtasks[subtaskIndex].updatedAt = MockDataFactory.now
        items[itemIndex].updatedAt = MockDataFactory.now
        return hydratedItem(items[itemIndex])
    }

    func deleteSubtask(itemID: UUID, subtaskID: UUID, actorID: UUID) async throws -> Item {
        guard let itemIndex = items.firstIndex(where: { $0.id == itemID }) else {
            throw RepositoryError.notFound
        }
        items[itemIndex].subtasks.removeAll { $0.id == subtaskID }
        for index in items[itemIndex].subtasks.indices {
            items[itemIndex].subtasks[index].sortOrder = index
        }
        items[itemIndex].updatedAt = MockDataFactory.now
        return hydratedItem(items[itemIndex])
    }

    func reorderItems(itemIDs: [UUID]) async throws -> [Item] {
        let now = MockDataFactory.now
        for (order, itemID) in itemIDs.enumerated() {
            guard let index = items.firstIndex(where: { $0.id == itemID }) else { continue }
            items[index].sortOrder = Double(order)
            items[index].updatedAt = now
        }
        return itemIDs.compactMap { itemID in
            items.first(where: { $0.id == itemID }).map(hydratedItem)
        }
    }

    func deleteItem(itemID: UUID) async throws {
        guard let index = items.firstIndex(where: { $0.id == itemID }) else {
            throw RepositoryError.notFound
        }
        occurrenceCompletions[itemID] = nil
        items.remove(at: index)
    }

    private func hydratedItem(_ item: Item) -> Item {
        var copy = item
        if item.repeatRule != nil {
            copy.occurrenceCompletions = occurrenceCompletions[item.id, default: []]
            copy.completedAt = nil
        }
        return copy
    }

    private func upsertOccurrenceCompletion(itemID: UUID, referenceDate: Date, completedAt: Date) {
        let occurrenceDate = calendar.startOfDay(for: referenceDate)
        var completions = occurrenceCompletions[itemID, default: []]
        completions.removeAll { calendar.isDate($0.occurrenceDate, inSameDayAs: occurrenceDate) }
        completions.append(ItemOccurrenceCompletion(occurrenceDate: occurrenceDate, completedAt: completedAt))
        occurrenceCompletions[itemID] = completions.sorted { $0.occurrenceDate < $1.occurrenceDate }
    }

    private func deleteOccurrenceCompletion(itemID: UUID, referenceDate: Date) {
        let occurrenceDate = calendar.startOfDay(for: referenceDate)
        let filtered = occurrenceCompletions[itemID, default: []]
            .filter { calendar.isDate($0.occurrenceDate, inSameDayAs: occurrenceDate) == false }
        occurrenceCompletions[itemID] = filtered.isEmpty ? nil : filtered
    }
}

private extension Item {
    nonisolated func matchesCompletedHistorySearch(_ searchText: String) -> Bool {
        title.localizedStandardContains(searchText)
            || (notes?.localizedStandardContains(searchText) ?? false)
            || subtasks.contains { $0.title.localizedStandardContains(searchText) }
    }
}
