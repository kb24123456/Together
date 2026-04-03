import Foundation
import SwiftData

actor LocalItemRepository: ItemRepositoryProtocol {
    private let container: ModelContainer
    private let calendar = Calendar.current

    init(container: ModelContainer) {
        self.container = container
    }

    func fetchActiveItems(spaceID: UUID?) async throws -> [Item] {
        let context = ModelContext(container)
        let records = try activeRecords(spaceID: spaceID, context: context)
        return try hydrateItems(from: records, context: context)
    }

    func fetchArchivedCompletedItems(
        spaceID: UUID?,
        searchText: String?,
        before: Date?,
        limit: Int
    ) async throws -> [Item] {
        let context = ModelContext(container)
        let normalizedLimit = max(limit, 1)
        let records = try archivedCompletedRecords(spaceID: spaceID, context: context)

        let filtered = records.filter { record in
            guard record.completedAt != nil else { return false }
            guard let archivedAt = record.archivedAt else { return false }
            if let before, archivedAt >= before {
                return false
            }
            guard let searchText = searchText?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !searchText.isEmpty else {
                return true
            }
            return record.title.localizedStandardContains(searchText)
        }

        return Array(filtered.prefix(normalizedLimit)).map { $0.domainModel() }
    }

    func fetchCompletedItems(
        spaceID: UUID?,
        searchText: String?,
        before: Date?,
        limit: Int
    ) async throws -> [Item] {
        let context = ModelContext(container)
        let normalizedLimit = max(limit, 1)
        let records = try completedRecords(spaceID: spaceID, context: context)

        let filtered = records.filter { record in
            guard let completedAt = record.completedAt else { return false }
            let cursorDate = record.archivedAt ?? completedAt
            if let before, cursorDate >= before {
                return false
            }
            guard let searchText = searchText?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !searchText.isEmpty else {
                return true
            }
            return record.title.localizedStandardContains(searchText)
        }

        return Array(filtered.prefix(normalizedLimit)).map { $0.domainModel() }
    }

    func archiveCompletedItemsIfNeeded(
        spaceID: UUID?,
        referenceDate: Date,
        autoArchiveDays: Int
    ) async throws -> Bool {
        let context = ModelContext(container)
        let thresholdDays = NotificationSettings.normalizedCompletedTaskAutoArchiveDays(autoArchiveDays)
        guard let cutoffDate = calendar.date(byAdding: .day, value: -thresholdDays, to: referenceDate) else {
            return false
        }

        let records = try activeRecords(spaceID: spaceID, context: context)
        var hasChanges = false

        for record in records {
            guard record.repeatRuleData == nil else { continue }
            guard let completedAt = record.completedAt else { continue }
            guard completedAt <= cutoffDate else { continue }
            record.isArchived = true
            record.archivedAt = referenceDate
            record.isPinned = false
            hasChanges = true
        }

        if hasChanges {
            try context.save()
        }

        return hasChanges
    }

    func restoreArchivedItem(itemID: UUID) async throws -> Item {
        let context = ModelContext(container)
        guard let record = try fetchRecord(itemID: itemID, context: context) else {
            throw RepositoryError.notFound
        }

        record.isArchived = false
        record.archivedAt = nil
        try context.save()
        return try hydratedItem(from: record, context: context)
    }

    func fetchItem(itemID: UUID) async throws -> Item? {
        let context = ModelContext(container)
        guard let record = try fetchRecord(itemID: itemID, context: context) else { return nil }
        return try hydratedItem(from: record, context: context)
    }

    func fetchOccurrenceCompletions(itemIDs: [UUID]) async throws -> [UUID: [ItemOccurrenceCompletion]] {
        let context = ModelContext(container)
        let itemRecords = try fetchRecords(itemIDs: itemIDs, context: context)
        return try occurrenceCompletionMap(itemIDs: itemIDs, itemRecords: itemRecords, context: context)
    }

    func isCompleted(itemID: UUID, on referenceDate: Date) async throws -> Bool {
        let context = ModelContext(container)
        guard let record = try fetchRecord(itemID: itemID, context: context) else {
            throw RepositoryError.notFound
        }

        let item = try hydratedItem(from: record, context: context)
        return item.isCompleted(on: referenceDate, calendar: calendar)
    }

    func updateItemStatus(itemID: UUID, response: ItemResponseKind?, message: String?, actorID: UUID) async throws -> Item {
        let context = ModelContext(container)
        guard let record = try fetchRecord(itemID: itemID, context: context) else {
            throw RepositoryError.notFound
        }

        var item = record.domainModel()
        if let response {
            guard item.canActorRespond(actorID) else {
                throw RepositoryError.notFound
            }
            let trimmedMessage = message?.trimmingCharacters(in: .whitespacesAndNewlines)
            let responseRecord = ItemResponse(
                responderID: actorID,
                kind: response,
                message: trimmedMessage,
                respondedAt: .now
            )
            item.latestResponse = responseRecord
            item.responseHistory.append(responseRecord)
            if let trimmedMessage, trimmedMessage.isEmpty == false {
                item.assignmentMessages.append(
                    TaskAssignmentMessage(authorID: actorID, body: trimmedMessage, createdAt: .now)
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
        item.lastActionAt = .now
        item.updatedAt = .now
        record.update(from: item)
        try context.save()
        return try hydratedItem(from: record, context: context)
    }

    func markCompleted(itemID: UUID, actorID: UUID, referenceDate: Date) async throws -> Item {
        let context = ModelContext(container)
        guard let record = try fetchRecord(itemID: itemID, context: context) else {
            throw RepositoryError.notFound
        }

        var item = record.domainModel()
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
            item.completedAt = Date.now
        } else {
            try upsertOccurrenceCompletion(
                itemID: itemID,
                referenceDate: referenceDate,
                completedAt: Date.now,
                context: context
            )
            item.completedAt = nil
        }
        item.lastActionByUserID = actorID
        item.lastActionAt = .now
        item.isArchived = false
        item.archivedAt = nil
        item.updatedAt = .now
        record.update(from: item)
        try context.save()
        return try hydratedItem(from: record, context: context)
    }

    func markIncomplete(itemID: UUID, actorID: UUID, referenceDate: Date) async throws -> Item {
        let context = ModelContext(container)
        guard let record = try fetchRecord(itemID: itemID, context: context) else {
            throw RepositoryError.notFound
        }

        var item = record.domainModel()
        if item.repeatRule == nil {
            item.completedAt = nil
            item.assignmentState = .active
            if item.status == .completed {
                item.status = .inProgress
            }
        } else {
            try deleteOccurrenceCompletion(itemID: itemID, referenceDate: referenceDate, context: context)
            item.completedAt = nil
        }
        item.lastActionByUserID = actorID
        item.lastActionAt = .now
        item.isArchived = false
        item.archivedAt = nil
        item.updatedAt = .now
        record.update(from: item)
        try context.save()
        return try hydratedItem(from: record, context: context)
    }

    func saveItem(_ item: Item) async throws -> Item {
        let context = ModelContext(container)

        if item.isPinned, let spaceID = item.spaceID {
            let pinnedDescriptor = FetchDescriptor<PersistentItem>(
                predicate: #Predicate<PersistentItem> { $0.spaceID == spaceID },
                sortBy: [SortDescriptor(\PersistentItem.updatedAt, order: .reverse)]
            )
            let records = try context.fetch(pinnedDescriptor)
            for record in records {
                if record.id != item.id {
                    record.isPinned = false
                }
            }
        }

        var savedItem = item
        savedItem.updatedAt = .now

        if let record = try fetchRecord(itemID: item.id, context: context) {
            try migrateLegacyRecurringCompletionIfNeeded(record: record, context: context)
            record.update(from: savedItem)
        } else {
            context.insert(PersistentItem(item: savedItem))
        }

        try context.save()
        if let record = try fetchRecord(itemID: item.id, context: context) {
            return try hydratedItem(from: record, context: context)
        }
        return savedItem
    }

    func deleteItem(itemID: UUID) async throws {
        let context = ModelContext(container)
        guard let record = try fetchRecord(itemID: itemID, context: context) else {
            throw RepositoryError.notFound
        }

        let occurrenceRecords = try fetchOccurrenceRecords(itemIDs: [itemID], context: context)
        for occurrenceRecord in occurrenceRecords {
            context.delete(occurrenceRecord)
        }
        context.delete(record)
        try context.save()
    }

    private func fetchRecord(itemID: UUID, context: ModelContext) throws -> PersistentItem? {
        let descriptor = FetchDescriptor<PersistentItem>(
            predicate: #Predicate<PersistentItem> { $0.id == itemID }
        )
        return try context.fetch(descriptor).first
    }

    private func fetchRecords(itemIDs: [UUID], context: ModelContext) throws -> [PersistentItem] {
        guard itemIDs.isEmpty == false else { return [] }
        let descriptor = FetchDescriptor<PersistentItem>(
            predicate: #Predicate<PersistentItem> { itemIDs.contains($0.id) }
        )
        return try context.fetch(descriptor)
    }

    private func activeRecords(spaceID: UUID?, context: ModelContext) throws -> [PersistentItem] {
        let descriptor: FetchDescriptor<PersistentItem>

        if let spaceID {
            descriptor = FetchDescriptor(
                predicate: #Predicate<PersistentItem> { $0.spaceID == spaceID && $0.isArchived == false },
                sortBy: [SortDescriptor(\PersistentItem.updatedAt, order: .reverse)]
            )
        } else {
            descriptor = FetchDescriptor(
                predicate: #Predicate<PersistentItem> { $0.isArchived == false },
                sortBy: [SortDescriptor(\PersistentItem.updatedAt, order: .reverse)]
            )
        }

        return try context.fetch(descriptor)
    }

    private func archivedCompletedRecords(spaceID: UUID?, context: ModelContext) throws -> [PersistentItem] {
        let descriptor: FetchDescriptor<PersistentItem>

        if let spaceID {
            descriptor = FetchDescriptor(
                predicate: #Predicate<PersistentItem> {
                    $0.spaceID == spaceID && $0.isArchived == true && $0.completedAt != nil
                },
                sortBy: [SortDescriptor(\PersistentItem.archivedAt, order: .reverse)]
            )
        } else {
            descriptor = FetchDescriptor(
                predicate: #Predicate<PersistentItem> { $0.isArchived == true && $0.completedAt != nil },
                sortBy: [SortDescriptor(\PersistentItem.archivedAt, order: .reverse)]
            )
        }

        return try context.fetch(descriptor)
    }

    private func completedRecords(spaceID: UUID?, context: ModelContext) throws -> [PersistentItem] {
        let records: [PersistentItem]

        if let spaceID {
            let descriptor = FetchDescriptor<PersistentItem>(
                predicate: #Predicate<PersistentItem> { $0.spaceID == spaceID && $0.completedAt != nil },
                sortBy: [SortDescriptor(\PersistentItem.completedAt, order: .reverse)]
            )
            records = try context.fetch(descriptor)
        } else {
            let descriptor = FetchDescriptor<PersistentItem>(
                predicate: #Predicate<PersistentItem> { $0.completedAt != nil },
                sortBy: [SortDescriptor(\PersistentItem.completedAt, order: .reverse)]
            )
            records = try context.fetch(descriptor)
        }

        return records.sorted { lhs, rhs in
            let lhsDate = lhs.archivedAt ?? lhs.completedAt ?? .distantPast
            let rhsDate = rhs.archivedAt ?? rhs.completedAt ?? .distantPast
            return lhsDate > rhsDate
        }
    }

    private func hydrateItems(
        from records: [PersistentItem],
        context: ModelContext
    ) throws -> [Item] {
        let completions = try occurrenceCompletionMap(
            itemIDs: records.map(\.id),
            itemRecords: records,
            context: context
        )
        return try records.map { record in
            try hydratedItem(from: record, occurrenceCompletions: completions[record.id] ?? [], context: context)
        }
    }

    private func hydratedItem(from record: PersistentItem, context: ModelContext) throws -> Item {
        let completions = try occurrenceCompletionMap(
            itemIDs: [record.id],
            itemRecords: [record],
            context: context
        )
        return try hydratedItem(from: record, occurrenceCompletions: completions[record.id] ?? [], context: context)
    }

    private func hydratedItem(
        from record: PersistentItem,
        occurrenceCompletions: [ItemOccurrenceCompletion],
        context: ModelContext
    ) throws -> Item {
        let migratedLegacyCompletions = try legacyOccurrenceCompletions(for: record, context: context)
        let merged = (occurrenceCompletions + migratedLegacyCompletions)
            .sorted { lhs, rhs in
                if lhs.occurrenceDate != rhs.occurrenceDate {
                    return lhs.occurrenceDate < rhs.occurrenceDate
                }
                return lhs.completedAt < rhs.completedAt
            }
        return record.domainModel(occurrenceCompletions: merged)
    }

    private func occurrenceCompletionMap(
        itemIDs: [UUID],
        itemRecords: [PersistentItem],
        context: ModelContext
    ) throws -> [UUID: [ItemOccurrenceCompletion]] {
        guard itemIDs.isEmpty == false else { return [:] }
        let records = try fetchOccurrenceRecords(itemIDs: itemIDs, context: context)
        var result: [UUID: [ItemOccurrenceCompletion]] = [:]
        for record in records {
            result[record.itemID, default: []].append(
                ItemOccurrenceCompletion(
                    occurrenceDate: record.occurrenceDate,
                    completedAt: record.completedAt
                )
            )
        }
        for itemRecord in itemRecords {
            for legacyCompletion in try legacyOccurrenceCompletions(for: itemRecord, context: context) {
                let existing = result[itemRecord.id, default: []]
                if existing.contains(where: { calendar.isDate($0.occurrenceDate, inSameDayAs: legacyCompletion.occurrenceDate) }) == false {
                    result[itemRecord.id, default: []].append(legacyCompletion)
                }
            }
        }
        return result
    }

    private func fetchOccurrenceRecords(
        itemIDs: [UUID],
        context: ModelContext
    ) throws -> [PersistentItemOccurrenceCompletion] {
        guard itemIDs.isEmpty == false else { return [] }
        let descriptor = FetchDescriptor<PersistentItemOccurrenceCompletion>(
            predicate: #Predicate<PersistentItemOccurrenceCompletion> { itemIDs.contains($0.itemID) }
        )
        return try context.fetch(descriptor)
    }

    private func legacyOccurrenceCompletions(
        for record: PersistentItem,
        context: ModelContext
    ) throws -> [ItemOccurrenceCompletion] {
        guard record.repeatRuleData != nil, let completedAt = record.completedAt else {
            return []
        }

        let dayKey = normalizedOccurrenceDate(for: completedAt)
        let existing = try fetchOccurrenceRecords(itemIDs: [record.id], context: context)
        guard existing.contains(where: { calendar.isDate($0.occurrenceDate, inSameDayAs: dayKey) }) == false else {
            return []
        }
        return [ItemOccurrenceCompletion(occurrenceDate: dayKey, completedAt: completedAt)]
    }

    private func migrateLegacyRecurringCompletionIfNeeded(
        record: PersistentItem,
        context: ModelContext
    ) throws {
        guard record.repeatRuleData != nil, let completedAt = record.completedAt else { return }
        let occurrenceDate = normalizedOccurrenceDate(for: completedAt)
        let existing = try fetchOccurrenceRecords(itemIDs: [record.id], context: context)
        if existing.contains(where: { calendar.isDate($0.occurrenceDate, inSameDayAs: occurrenceDate) }) == false {
            context.insert(
                PersistentItemOccurrenceCompletion(
                    itemID: record.id,
                    occurrenceDate: occurrenceDate,
                    completedAt: completedAt,
                    createdAt: completedAt,
                    updatedAt: completedAt
                )
            )
        }
        record.completedAt = nil
    }

    private func upsertOccurrenceCompletion(
        itemID: UUID,
        referenceDate: Date,
        completedAt: Date,
        context: ModelContext
    ) throws {
        let occurrenceDate = normalizedOccurrenceDate(for: referenceDate)
        let existing = try fetchOccurrenceRecords(itemIDs: [itemID], context: context)
            .first(where: { calendar.isDate($0.occurrenceDate, inSameDayAs: occurrenceDate) })

        if let existing {
            existing.completedAt = completedAt
            existing.updatedAt = completedAt
        } else {
            context.insert(
                PersistentItemOccurrenceCompletion(
                    itemID: itemID,
                    occurrenceDate: occurrenceDate,
                    completedAt: completedAt,
                    createdAt: completedAt,
                    updatedAt: completedAt
                )
            )
        }
    }

    private func deleteOccurrenceCompletion(
        itemID: UUID,
        referenceDate: Date,
        context: ModelContext
    ) throws {
        let occurrenceDate = normalizedOccurrenceDate(for: referenceDate)
        let existing = try fetchOccurrenceRecords(itemIDs: [itemID], context: context)
        for record in existing where calendar.isDate(record.occurrenceDate, inSameDayAs: occurrenceDate) {
            context.delete(record)
        }
    }

    private func normalizedOccurrenceDate(for date: Date) -> Date {
        calendar.startOfDay(for: date)
    }
}
