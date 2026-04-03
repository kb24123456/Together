import Foundation

@MainActor
final class MockItemRepository: ItemRepositoryProtocol {
    private var items: [Item] = MockDataFactory.makeItems()
    private var occurrenceCompletions: [UUID: [ItemOccurrenceCompletion]] = [:]
    private let calendar = Calendar.current

    func fetchActiveItems(spaceID: UUID?) async throws -> [Item] {
        items
            .filter { $0.spaceID == spaceID && $0.isArchived == false }
            .map(hydratedItem)
            .sorted { $0.updatedAt > $1.updatedAt }
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

    func fetchCompletedItems(
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
                guard let completedAt = item.completedAt else { return false }
                let cursorDate = item.archivedAt ?? completedAt
                if let before, cursorDate >= before {
                    return false
                }
                guard let normalizedSearch, normalizedSearch.isEmpty == false else {
                    return true
                }
                return item.title.localizedStandardContains(normalizedSearch)
            }
            .sorted {
                ($0.archivedAt ?? $0.completedAt ?? .distantPast) > ($1.archivedAt ?? $1.completedAt ?? .distantPast)
            }
            .prefix(normalizedLimit)
            .map { $0 }
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
            copy.isPinned = false
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

    func updateItemStatus(itemID: UUID, response: ItemResponseKind?, message: String?, actorID: UUID) async throws -> Item {
        guard let index = items.firstIndex(where: { $0.id == itemID }) else {
            throw RepositoryError.notFound
        }

        var item = items[index]
        if let response {
            guard item.canActorRespond(actorID) else {
                throw RepositoryError.notFound
            }
            let trimmedMessage = message?.trimmingCharacters(in: .whitespacesAndNewlines)
            let record = ItemResponse(
                responderID: actorID,
                kind: response,
                message: trimmedMessage,
                respondedAt: MockDataFactory.now
            )
            item.latestResponse = record
            item.responseHistory.append(record)
            if let trimmedMessage, trimmedMessage.isEmpty == false {
                item.assignmentMessages.append(
                    TaskAssignmentMessage(authorID: actorID, body: trimmedMessage, createdAt: MockDataFactory.now)
                )
            }
            item.assignmentState = ItemStateMachine.nextAssignmentState(
                from: item.assignmentState,
                response: response
            )
            item.status = ItemStateMachine.nextStatus(
                from: item.status,
                executionRole: item.executionRole,
                response: response
            )
        }
        item.lastActionByUserID = actorID
        item.lastActionAt = MockDataFactory.now
        item.updatedAt = MockDataFactory.now
        items[index] = item
        return hydratedItem(item)
    }

    func markCompleted(itemID: UUID, actorID: UUID, referenceDate: Date) async throws -> Item {
        guard let index = items.firstIndex(where: { $0.id == itemID }) else {
            throw RepositoryError.notFound
        }

        var item = items[index]
        if item.repeatRule == nil {
            guard item.canActorComplete(actorID) || item.assigneeMode == .both else {
                throw RepositoryError.notFound
            }
            item.assignmentState = .completed
            item.status = ItemStateMachine.nextStatus(
                from: item.status,
                executionRole: item.executionRole,
                isCompletion: true
            )
            item.completedAt = MockDataFactory.now
        } else {
            upsertOccurrenceCompletion(itemID: itemID, referenceDate: referenceDate, completedAt: MockDataFactory.now)
            item.completedAt = nil
        }
        item.lastActionByUserID = actorID
        item.lastActionAt = MockDataFactory.now
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
            item.assignmentState = .active
            if item.status == .completed {
                item.status = .inProgress
            }
        } else {
            deleteOccurrenceCompletion(itemID: itemID, referenceDate: referenceDate)
            item.completedAt = nil
        }
        item.lastActionByUserID = actorID
        item.lastActionAt = MockDataFactory.now
        item.isArchived = false
        item.archivedAt = nil
        item.updatedAt = MockDataFactory.now
        items[index] = item
        return hydratedItem(item)
    }

    func saveItem(_ item: Item) async throws -> Item {
        if item.isPinned {
            items = items.map { existing in
                var copy = existing
                if existing.spaceID == item.spaceID {
                    copy.isPinned = existing.id == item.id
                }
                return copy
            }
        }

        var updatedItem = item
        updatedItem.updatedAt = MockDataFactory.now
        if let index = items.firstIndex(where: { $0.id == item.id }) {
            items[index] = updatedItem
        } else {
            items.append(updatedItem)
        }
        return hydratedItem(updatedItem)
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
