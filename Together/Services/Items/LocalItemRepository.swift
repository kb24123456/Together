import Foundation
import SwiftData
import TogetherCore

actor LocalItemRepository: ItemRepositoryProtocol {
    private let container: ModelContainer
    private let syncCoordinator: SyncCoordinatorProtocol?
    private let calendar = Calendar.current

    init(container: ModelContainer, syncCoordinator: SyncCoordinatorProtocol? = nil) {
        self.container = container
        self.syncCoordinator = syncCoordinator
    }

    func fetchActiveItems(spaceID: UUID?) async throws -> [Item] {
        let context = ModelContext(container)
        let records = try activeRecords(spaceID: spaceID, context: context)
        return try hydrateItems(from: records, context: context)
    }

    func fetchHomeItems(spaceID: UUID?, completedFrom: Date, completedBefore: Date) async throws -> [Item] {
        let context = ModelContext(container)
        let records = try homeRecords(
            spaceID: spaceID,
            completedFrom: completedFrom,
            completedBefore: completedBefore,
            context: context
        )
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
        let normalizedSearch = searchText?.trimmingCharacters(in: .whitespacesAndNewlines)
        let sourceLimit = normalizedSearch?.isEmpty == false || before != nil ? nil : normalizedLimit
        let records = try archivedCompletedRecords(spaceID: spaceID, context: context, fetchLimit: sourceLimit)

        let filtered = records.filter { record in
            guard record.completedAt != nil else { return false }
            guard let archivedAt = record.archivedAt else { return false }
            if let before, archivedAt >= before {
                return false
            }
            guard let normalizedSearch,
                  !normalizedSearch.isEmpty else {
                return true
            }
            return record.title.localizedStandardContains(normalizedSearch)
        }

        return Array(filtered.prefix(normalizedLimit)).map { $0.domainModel() }
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
        let context = ModelContext(container)
        let normalizedLimit = max(limit, 1)
        let normalizedSearch = searchText?.trimmingCharacters(in: .whitespacesAndNewlines)
        let sourceLimit = normalizedSearch?.isEmpty == false
            || before != nil
            || completedFrom != nil
            || completedBefore != nil
            ? nil
            : normalizedLimit
        let records = try completedRecords(spaceID: spaceID, context: context, fetchLimit: sourceLimit)

        let filtered = records.filter { record in
            guard let completedAt = record.completedAt else { return false }
            let cursorDate = record.archivedAt ?? completedAt
            if let before, cursorDate >= before {
                return false
            }
            if let completedFrom, completedAt < completedFrom {
                return false
            }
            if let completedBefore, completedAt >= completedBefore {
                return false
            }
            return true
        }

        guard let normalizedSearch, normalizedSearch.isEmpty == false else {
            let limitedRecords = Array(filtered.prefix(normalizedLimit))
            do {
                return try hydrateItems(from: limitedRecords, context: context)
            } catch {
                return limitedRecords.map { $0.domainModel() }
            }
        }

        do {
            let hydrated = try hydrateItems(from: filtered, context: context)
            return Array(hydrated.filter { item in
                item.matchesCompletedHistorySearch(normalizedSearch)
            }.prefix(normalizedLimit))
        } catch {
            let fallbackRecords = filtered.filter { record in
                record.title.localizedStandardContains(normalizedSearch)
                    || (record.notes?.localizedStandardContains(normalizedSearch) ?? false)
            }
            return Array(fallbackRecords.prefix(normalizedLimit)).map { $0.domainModel() }
        }
    }

    func completedItemCount(
        spaceID: UUID?,
        completedFrom: Date?,
        completedBefore: Date?
    ) async throws -> Int {
        let context = ModelContext(container)
        return try completedItemCount(
            spaceID: spaceID,
            context: context,
            from: completedFrom,
            to: completedBefore
        )
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

        var archivedIDs: [(id: UUID, spaceID: UUID)] = []

        for record in records {
            guard record.repeatRuleData == nil else { continue }
            guard let completedAt = record.completedAt else { continue }
            guard completedAt <= cutoffDate else { continue }
            record.isArchived = true
            record.archivedAt = referenceDate
            record.updatedAt = .now
            record.isPinned = false
            if let sid = record.spaceID {
                archivedIDs.append((id: record.id, spaceID: sid))
            }
            hasChanges = true
        }

        if hasChanges {
            try context.save()
            for item in archivedIDs {
                await syncCoordinator?.recordLocalChange(
                    SyncChange(entityKind: .task, operation: .archive, recordID: item.id, spaceID: item.spaceID)
                )
            }
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
        record.updatedAt = .now
        try context.save()

        if let sid = record.spaceID {
            await syncCoordinator?.recordLocalChange(
                SyncChange(entityKind: .task, operation: .upsert, recordID: itemID, spaceID: sid)
            )
        }

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

    func markCompleted(itemID: UUID, actorID: UUID, referenceDate: Date) async throws -> Item {
        let context = ModelContext(container)
        guard let record = try fetchRecord(itemID: itemID, context: context) else {
            throw RepositoryError.notFound
        }

        ItemStatusDiagnosisLog.markCompletedBegin(
            itemID: record.id,
            oldStatus: record.statusRawValue,
            oldCompletedAt: record.completedAt,
            actorID: actorID,
            creatorID: record.creatorID,
            hasRepeatRule: record.repeatRuleData != nil
        )

        var item = record.domainModel()
        if item.repeatRule == nil {
            item.status = ItemStateMachine.nextStatus(
                from: item.status,
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
        item.completedByUserID = actorID
        item.isArchived = false
        item.archivedAt = nil
        item.updatedAt = .now
        record.update(from: item)
        try context.save()

        ItemStatusDiagnosisLog.markCompletedSaved(
            itemID: record.id,
            newStatus: record.statusRawValue,
            newCompletedAt: record.completedAt
        )

        let readback = try? fetchRecord(itemID: itemID, context: context)
        ItemStatusDiagnosisLog.markCompletedReadback(
            itemID: itemID,
            readbackStatus: readback?.statusRawValue,
            readbackCompletedAt: readback?.completedAt
        )

        if let sid = record.spaceID {
            await syncCoordinator?.recordLocalChange(
                SyncChange(entityKind: .task, operation: .complete, recordID: itemID, spaceID: sid)
            )
        }

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
            if item.status == .completed {
                item.status = .inProgress
            }
        } else {
            try deleteOccurrenceCompletion(itemID: itemID, referenceDate: referenceDate, context: context)
            item.completedAt = nil
        }
        item.lastActionByUserID = actorID
        item.lastActionAt = .now
        item.completedByUserID = nil
        item.isArchived = false
        item.archivedAt = nil
        item.updatedAt = .now
        record.update(from: item)
        try context.save()

        if let sid = record.spaceID {
            await syncCoordinator?.recordLocalChange(
                SyncChange(entityKind: .task, operation: .upsert, recordID: itemID, spaceID: sid)
            )
        }

        return try hydratedItem(from: record, context: context)
    }

    func saveItem(_ item: Item) async throws -> Item {
        let context = ModelContext(container)

        var savedItem = item
        savedItem.updatedAt = .now

        let subtaskChanges: SubtaskChangeSet
        if let record = try fetchRecord(itemID: item.id, context: context) {
            try migrateLegacyRecurringCompletionIfNeeded(record: record, context: context)
            record.update(from: savedItem)
            subtaskChanges = try replaceSubtasks(for: savedItem, context: context)
        } else {
            context.insert(PersistentItem(item: savedItem))
            subtaskChanges = try replaceSubtasks(for: savedItem, context: context)
        }

        try context.save()

        // 记录到本地同步队列。
        if let sid = savedItem.spaceID {
            for subtaskID in subtaskChanges.upserted {
                await syncCoordinator?.recordLocalChange(
                    SyncChange(entityKind: .taskSubtask, operation: .upsert, recordID: subtaskID, spaceID: sid)
                )
            }
            for subtaskID in subtaskChanges.deleted {
                await syncCoordinator?.recordLocalChange(
                    SyncChange(entityKind: .taskSubtask, operation: .delete, recordID: subtaskID, spaceID: sid)
                )
            }
            await syncCoordinator?.recordLocalChange(
                SyncChange(entityKind: .task, operation: .upsert, recordID: savedItem.id, spaceID: sid)
            )
        }

        if let record = try fetchRecord(itemID: item.id, context: context) {
            return try hydratedItem(from: record, context: context)
        }
        return savedItem
    }

    func addSubtask(itemID: UUID, title: String, creatorID: UUID) async throws -> Item {
        let context = ModelContext(container)
        guard let record = try fetchRecord(itemID: itemID, context: context), record.isLocallyDeleted == false else {
            throw RepositoryError.notFound
        }
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else {
            throw RepositoryError.invalidInput("子任务标题不能为空")
        }

        let existingSubtasks = try subtasks(for: itemID, in: context)
        let subtask = TaskSubtask(
            itemID: itemID,
            creatorID: creatorID,
            title: trimmed,
            sortOrder: existingSubtasks.count
        )
        context.insert(PersistentTaskSubtask(subtask: subtask))
        record.updatedAt = .now
        try context.save()

        if let sid = record.spaceID {
            await syncCoordinator?.recordLocalChange(
                SyncChange(entityKind: .taskSubtask, operation: .upsert, recordID: subtask.id, spaceID: sid)
            )
            await syncCoordinator?.recordLocalChange(
                SyncChange(entityKind: .task, operation: .upsert, recordID: itemID, spaceID: sid)
            )
        }

        return try hydratedItem(from: record, context: context)
    }

    func toggleSubtask(itemID: UUID, subtaskID: UUID, actorID: UUID) async throws -> Item {
        let context = ModelContext(container)
        guard let record = try fetchRecord(itemID: itemID, context: context), record.isLocallyDeleted == false else {
            throw RepositoryError.notFound
        }
        guard let subtaskRecord = try fetchSubtaskRecord(subtaskID: subtaskID, context: context),
              subtaskRecord.itemID == itemID,
              subtaskRecord.isLocallyDeleted == false
        else {
            throw RepositoryError.notFound
        }

        subtaskRecord.isCompleted.toggle()
        subtaskRecord.updatedAt = .now
        record.updatedAt = .now
        try context.save()

        if let sid = record.spaceID {
            await syncCoordinator?.recordLocalChange(
                SyncChange(entityKind: .taskSubtask, operation: .upsert, recordID: subtaskID, spaceID: sid)
            )
            await syncCoordinator?.recordLocalChange(
                SyncChange(entityKind: .task, operation: .upsert, recordID: itemID, spaceID: sid)
            )
        }

        return try hydratedItem(from: record, context: context)
    }

    func updateSubtask(itemID: UUID, subtaskID: UUID, title: String, actorID: UUID) async throws -> Item {
        let context = ModelContext(container)
        guard let record = try fetchRecord(itemID: itemID, context: context), record.isLocallyDeleted == false else {
            throw RepositoryError.notFound
        }
        guard let subtaskRecord = try fetchSubtaskRecord(subtaskID: subtaskID, context: context),
              subtaskRecord.itemID == itemID,
              subtaskRecord.isLocallyDeleted == false
        else {
            throw RepositoryError.notFound
        }

        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else {
            throw RepositoryError.invalidInput("子任务标题不能为空")
        }

        subtaskRecord.title = trimmed
        subtaskRecord.updatedAt = .now
        record.updatedAt = .now
        try context.save()

        if let sid = record.spaceID {
            await syncCoordinator?.recordLocalChange(
                SyncChange(entityKind: .taskSubtask, operation: .upsert, recordID: subtaskID, spaceID: sid)
            )
            await syncCoordinator?.recordLocalChange(
                SyncChange(entityKind: .task, operation: .upsert, recordID: itemID, spaceID: sid)
            )
        }

        return try hydratedItem(from: record, context: context)
    }

    func deleteSubtask(itemID: UUID, subtaskID: UUID, actorID: UUID) async throws -> Item {
        let context = ModelContext(container)
        guard let record = try fetchRecord(itemID: itemID, context: context), record.isLocallyDeleted == false else {
            throw RepositoryError.notFound
        }
        guard let subtaskRecord = try fetchSubtaskRecord(subtaskID: subtaskID, context: context),
              subtaskRecord.itemID == itemID,
              subtaskRecord.isLocallyDeleted == false
        else {
            throw RepositoryError.notFound
        }

        subtaskRecord.isLocallyDeleted = true
        subtaskRecord.updatedAt = .now
        record.updatedAt = .now
        let resequenced = try resequenceSubtasks(itemID: itemID, context: context)
        try context.save()

        if let sid = record.spaceID {
            await syncCoordinator?.recordLocalChange(
                SyncChange(entityKind: .taskSubtask, operation: .delete, recordID: subtaskID, spaceID: sid)
            )
            for siblingID in resequenced {
                await syncCoordinator?.recordLocalChange(
                    SyncChange(entityKind: .taskSubtask, operation: .upsert, recordID: siblingID, spaceID: sid)
                )
            }
            await syncCoordinator?.recordLocalChange(
                SyncChange(entityKind: .task, operation: .upsert, recordID: itemID, spaceID: sid)
            )
        }

        return try hydratedItem(from: record, context: context)
    }

    func reorderItems(itemIDs: [UUID]) async throws -> [Item] {
        guard itemIDs.isEmpty == false else { return [] }

        let context = ModelContext(container)
        let records = try fetchRecords(itemIDs: itemIDs, context: context)
        let recordsByID = Dictionary(uniqueKeysWithValues: records.map { ($0.id, $0) })
        let now = Date.now

        for (index, itemID) in itemIDs.enumerated() {
            guard let record = recordsByID[itemID] else { continue }
            record.sortOrder = Double(index)
            record.updatedAt = now
        }

        try context.save()

        for itemID in itemIDs {
            guard let record = recordsByID[itemID], let sid = record.spaceID else { continue }
            await syncCoordinator?.recordLocalChange(
                SyncChange(entityKind: .task, operation: .upsert, recordID: itemID, spaceID: sid)
            )
        }

        return try hydrateItems(from: records, context: context)
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
        let subtaskRecords = try subtaskRecords(for: itemID, in: context)
        for subtaskRecord in subtaskRecords {
            subtaskRecord.isLocallyDeleted = true
            subtaskRecord.updatedAt = .now
        }
        // 使用 tombstone 代替硬删，避免下次 pull 把已删记录 INSERT 复活
        let spaceID = record.spaceID
        record.isLocallyDeleted = true
        record.updatedAt = .now
        try context.save()

        if let sid = spaceID {
            for subtaskRecord in subtaskRecords {
                await syncCoordinator?.recordLocalChange(
                    SyncChange(entityKind: .taskSubtask, operation: .delete, recordID: subtaskRecord.id, spaceID: sid)
                )
            }
            await syncCoordinator?.recordLocalChange(
                SyncChange(entityKind: .task, operation: .delete, recordID: itemID, spaceID: sid)
            )
        }
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

        return try context.fetch(descriptor).filter { !$0.isLocallyDeleted }
    }

    private func homeRecords(
        spaceID: UUID?,
        completedFrom: Date,
        completedBefore: Date,
        context: ModelContext
    ) throws -> [PersistentItem] {
        let incompleteRecords = try incompleteHomeRecords(spaceID: spaceID, context: context)
        let completedRecords = try completedHomeRecords(
            spaceID: spaceID,
            completedFrom: completedFrom,
            completedBefore: completedBefore,
            context: context
        )

        return (incompleteRecords + completedRecords)
            .sorted { $0.updatedAt > $1.updatedAt }
    }

    private func incompleteHomeRecords(
        spaceID: UUID?,
        context: ModelContext
    ) throws -> [PersistentItem] {
        let completedStatus = ItemStatus.completed.rawValue
        return try activeRecords(spaceID: spaceID, context: context).filter {
            $0.completedAt == nil && $0.statusRawValue != completedStatus
        }
    }

    private func completedHomeRecords(
        spaceID: UUID?,
        completedFrom: Date,
        completedBefore: Date,
        context: ModelContext
    ) throws -> [PersistentItem] {
        let descriptor: FetchDescriptor<PersistentItem>

        if let spaceID {
            descriptor = FetchDescriptor(
                predicate: #Predicate<PersistentItem> { item in
                    if let completedAt = item.completedAt {
                        item.spaceID == spaceID
                        && item.isArchived == false
                        && completedAt >= completedFrom
                        && completedAt < completedBefore
                    } else {
                        false
                    }
                },
                sortBy: [SortDescriptor(\PersistentItem.completedAt, order: .reverse)]
            )
        } else {
            descriptor = FetchDescriptor(
                predicate: #Predicate<PersistentItem> { item in
                    if let completedAt = item.completedAt {
                        item.isArchived == false
                        && completedAt >= completedFrom
                        && completedAt < completedBefore
                    } else {
                        false
                    }
                },
                sortBy: [SortDescriptor(\PersistentItem.completedAt, order: .reverse)]
            )
        }

        return try context.fetch(descriptor).filter { !$0.isLocallyDeleted }
    }

    private func archivedCompletedRecords(
        spaceID: UUID?,
        context: ModelContext,
        fetchLimit: Int? = nil
    ) throws -> [PersistentItem] {
        var descriptor: FetchDescriptor<PersistentItem>

        if let spaceID {
            descriptor = FetchDescriptor(
                predicate: #Predicate<PersistentItem> { item in
                    item.spaceID == spaceID && item.isArchived == true && item.completedAt != nil
                },
                sortBy: [SortDescriptor(\PersistentItem.archivedAt, order: .reverse)]
            )
        } else {
            descriptor = FetchDescriptor(
                predicate: #Predicate<PersistentItem> { item in
                    item.isArchived == true && item.completedAt != nil
                },
                sortBy: [SortDescriptor(\PersistentItem.archivedAt, order: .reverse)]
            )
        }

        if let fetchLimit {
            descriptor.fetchLimit = fetchLimit
        }

        return try context.fetch(descriptor).filter { !$0.isLocallyDeleted }
    }

    func completedItemStats(spaceID: UUID?, referenceDate: Date) async throws -> CompletedItemStats {
        let context = ModelContext(container)
        let totalCount = try completedItemCount(spaceID: spaceID, context: context)
        guard totalCount > 0 else {
            return .empty
        }

        let monthInterval = calendar.dateInterval(of: .month, for: referenceDate)
        let thisMonthCount = try completedItemCount(
            spaceID: spaceID,
            context: context,
            from: monthInterval?.start,
            to: monthInterval?.end
        )
        let firstRecord = try firstCompletedRecord(spaceID: spaceID, context: context)
        let latestRecord = try latestCompletedRecord(spaceID: spaceID, context: context)

        return CompletedItemStats(
            totalCount: totalCount,
            thisMonthCount: thisMonthCount,
            firstCompletedAt: firstRecord?.completedAt,
            firstItemTitle: firstRecord?.title,
            lastCompletedAt: latestRecord?.completedAt
        )
    }

    private func completedRecords(
        spaceID: UUID?,
        context: ModelContext,
        fetchLimit: Int? = nil
    ) throws -> [PersistentItem] {
        let activeRecords = try unarchivedCompletedRecords(
            spaceID: spaceID,
            context: context,
            fetchLimit: fetchLimit
        )
        let archivedRecords = try archivedCompletedRecords(
            spaceID: spaceID,
            context: context,
            fetchLimit: fetchLimit
        )

        return (activeRecords + archivedRecords).sorted { lhs, rhs in
            let lhsDate = lhs.archivedAt ?? lhs.completedAt ?? .distantPast
            let rhsDate = rhs.archivedAt ?? rhs.completedAt ?? .distantPast
            return lhsDate > rhsDate
        }
    }

    private func unarchivedCompletedRecords(
        spaceID: UUID?,
        context: ModelContext,
        fetchLimit: Int?
    ) throws -> [PersistentItem] {
        var descriptor: FetchDescriptor<PersistentItem>

        if let spaceID {
            descriptor = FetchDescriptor(
                predicate: #Predicate<PersistentItem> { item in
                    item.spaceID == spaceID && item.isArchived == false && item.completedAt != nil
                },
                sortBy: [SortDescriptor(\PersistentItem.completedAt, order: .reverse)]
            )
        } else {
            descriptor = FetchDescriptor(
                predicate: #Predicate<PersistentItem> { item in
                    item.isArchived == false && item.completedAt != nil
                },
                sortBy: [SortDescriptor(\PersistentItem.completedAt, order: .reverse)]
            )
        }

        if let fetchLimit {
            descriptor.fetchLimit = fetchLimit
        }

        return try context.fetch(descriptor).filter { !$0.isLocallyDeleted }
    }

    private func completedItemCount(
        spaceID: UUID?,
        context: ModelContext,
        from: Date? = nil,
        to: Date? = nil
    ) throws -> Int {
        let lowerBound = from ?? .distantPast
        let upperBound = to ?? .distantFuture
        let descriptor: FetchDescriptor<PersistentItem>

        if let spaceID {
            descriptor = FetchDescriptor(
                predicate: #Predicate<PersistentItem> { item in
                    if let completedAt = item.completedAt {
                        item.spaceID == spaceID
                            && item.isLocallyDeleted == false
                            && completedAt >= lowerBound
                            && completedAt < upperBound
                    } else {
                        false
                    }
                }
            )
        } else {
            descriptor = FetchDescriptor(
                predicate: #Predicate<PersistentItem> { item in
                    if let completedAt = item.completedAt {
                        item.isLocallyDeleted == false
                            && completedAt >= lowerBound
                            && completedAt < upperBound
                    } else {
                        false
                    }
                }
            )
        }

        return try context.fetchCount(descriptor)
    }

    private func firstCompletedRecord(spaceID: UUID?, context: ModelContext) throws -> PersistentItem? {
        try boundaryCompletedRecord(spaceID: spaceID, context: context, order: .forward)
    }

    private func latestCompletedRecord(spaceID: UUID?, context: ModelContext) throws -> PersistentItem? {
        try boundaryCompletedRecord(spaceID: spaceID, context: context, order: .reverse)
    }

    private func boundaryCompletedRecord(
        spaceID: UUID?,
        context: ModelContext,
        order: SortOrder
    ) throws -> PersistentItem? {
        var descriptor: FetchDescriptor<PersistentItem>

        if let spaceID {
            descriptor = FetchDescriptor(
                predicate: #Predicate<PersistentItem> { item in
                    item.spaceID == spaceID
                    && item.isLocallyDeleted == false
                    && item.completedAt != nil
                },
                sortBy: [SortDescriptor(\PersistentItem.completedAt, order: order)]
            )
        } else {
            descriptor = FetchDescriptor(
                predicate: #Predicate<PersistentItem> { item in
                    item.isLocallyDeleted == false
                    && item.completedAt != nil
                },
                sortBy: [SortDescriptor(\PersistentItem.completedAt, order: order)]
            )
        }

        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    private func hydrateItems(
        from records: [PersistentItem],
        context: ModelContext
    ) throws -> [Item] {
        let itemIDs = records.map(\.id)
        let completions = try occurrenceCompletionMap(
            itemIDs: itemIDs,
            itemRecords: records,
            context: context
        )
        let subtasks = try subtaskMap(itemIDs: itemIDs, context: context)
        return try records.map { record in
            try hydratedItem(
                from: record,
                occurrenceCompletions: completions[record.id] ?? [],
                subtasks: subtasks[record.id] ?? [],
                context: context
            )
        }
    }

    private func hydratedItem(from record: PersistentItem, context: ModelContext) throws -> Item {
        let subtasks = try subtaskMap(itemIDs: [record.id], context: context)
        let completions = try occurrenceCompletionMap(
            itemIDs: [record.id],
            itemRecords: [record],
            context: context
        )
        return try hydratedItem(
            from: record,
            occurrenceCompletions: completions[record.id] ?? [],
            subtasks: subtasks[record.id] ?? [],
            context: context
        )
    }

    private func hydratedItem(
        from record: PersistentItem,
        occurrenceCompletions: [ItemOccurrenceCompletion],
        subtasks: [TaskSubtask],
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
        return record.domainModel(occurrenceCompletions: merged, subtasks: subtasks)
    }

    private struct SubtaskChangeSet {
        var upserted: [UUID] = []
        var deleted: [UUID] = []
    }

    private func replaceSubtasks(for item: Item, context: ModelContext) throws -> SubtaskChangeSet {
        let existingRecords = try subtaskRecords(for: item.id, in: context)
        let recordsByID = Dictionary(uniqueKeysWithValues: existingRecords.map { ($0.id, $0) })
        let activeExistingIDs = Set(existingRecords.filter { $0.isLocallyDeleted == false }.map(\.id))
        var desiredIDs: Set<UUID> = []
        var changes = SubtaskChangeSet()

        let normalizedSubtasks = item.subtasks
            .sorted { $0.sortOrder < $1.sortOrder }
            .enumerated()
            .compactMap { index, subtask -> TaskSubtask? in
                let trimmed = subtask.title.trimmingCharacters(in: .whitespacesAndNewlines)
                guard trimmed.isEmpty == false else { return nil }
                return TaskSubtask(
                    id: subtask.id,
                    itemID: item.id,
                    creatorID: subtask.creatorID,
                    title: trimmed,
                    isCompleted: subtask.isCompleted,
                    sortOrder: index,
                    updatedAt: .now,
                    sourceTaskID: subtask.sourceTaskID,
                    sourceNotes: subtask.sourceNotes,
                    sourceDueAt: subtask.sourceDueAt,
                    sourceHasExplicitTime: subtask.sourceHasExplicitTime,
                    sourceRemindAt: subtask.sourceRemindAt,
                    sourceCreatedAt: subtask.sourceCreatedAt,
                    sourceCompletedAt: subtask.sourceCompletedAt
                )
            }

        for subtask in normalizedSubtasks {
            desiredIDs.insert(subtask.id)
            if let record = recordsByID[subtask.id] {
                if record.title != subtask.title
                    || record.isCompleted != subtask.isCompleted
                    || record.sortOrder != subtask.sortOrder
                    || record.sourceTaskID != subtask.sourceTaskID
                    || record.sourceNotes != subtask.sourceNotes
                    || record.sourceDueAt != subtask.sourceDueAt
                    || record.sourceHasExplicitTime != subtask.sourceHasExplicitTime
                    || record.sourceRemindAt != subtask.sourceRemindAt
                    || record.sourceCreatedAt != subtask.sourceCreatedAt
                    || record.sourceCompletedAt != subtask.sourceCompletedAt
                    || record.isLocallyDeleted
                {
                    record.update(from: subtask)
                    changes.upserted.append(subtask.id)
                }
            } else {
                context.insert(PersistentTaskSubtask(subtask: subtask))
                changes.upserted.append(subtask.id)
            }
        }

        for record in existingRecords where activeExistingIDs.contains(record.id) && desiredIDs.contains(record.id) == false {
            record.isLocallyDeleted = true
            record.updatedAt = .now
            changes.deleted.append(record.id)
        }

        return changes
    }

    private func fetchSubtaskRecord(subtaskID: UUID, context: ModelContext) throws -> PersistentTaskSubtask? {
        let descriptor = FetchDescriptor<PersistentTaskSubtask>(
            predicate: #Predicate<PersistentTaskSubtask> { $0.id == subtaskID }
        )
        return try context.fetch(descriptor).first
    }

    private func subtaskRecords(for itemID: UUID, in context: ModelContext) throws -> [PersistentTaskSubtask] {
        let descriptor = FetchDescriptor<PersistentTaskSubtask>(
            predicate: #Predicate<PersistentTaskSubtask> { $0.itemID == itemID },
            sortBy: [SortDescriptor(\PersistentTaskSubtask.sortOrder, order: .forward)]
        )
        return try context.fetch(descriptor)
    }

    private func subtasks(for itemID: UUID, in context: ModelContext) throws -> [TaskSubtask] {
        try subtaskRecords(for: itemID, in: context)
            .filter { $0.isLocallyDeleted == false }
            .map { $0.domainModel() }
    }

    private func subtaskMap(itemIDs: [UUID], context: ModelContext) throws -> [UUID: [TaskSubtask]] {
        guard itemIDs.isEmpty == false else { return [:] }
        let itemIDSet = Set(itemIDs)
        let records = try context.fetch(
            FetchDescriptor<PersistentTaskSubtask>(
                predicate: #Predicate<PersistentTaskSubtask> { $0.isLocallyDeleted == false },
                sortBy: [SortDescriptor(\PersistentTaskSubtask.sortOrder, order: .forward)]
            )
        )
        return records.reduce(into: [:]) { result, record in
            guard itemIDSet.contains(record.itemID) else { return }
            result[record.itemID, default: []].append(record.domainModel())
        }
    }

    @discardableResult
    private func resequenceSubtasks(itemID: UUID, context: ModelContext) throws -> [UUID] {
        let records = try subtaskRecords(for: itemID, in: context)
            .filter { $0.isLocallyDeleted == false }
        var changedIDs: [UUID] = []
        for (index, record) in records.enumerated() where record.sortOrder != index {
            record.sortOrder = index
            record.updatedAt = .now
            changedIDs.append(record.id)
        }
        return changedIDs
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

private extension Item {
    nonisolated func matchesCompletedHistorySearch(_ searchText: String) -> Bool {
        title.localizedStandardContains(searchText)
            || (notes?.localizedStandardContains(searchText) ?? false)
            || subtasks.contains { $0.title.localizedStandardContains(searchText) }
    }
}
