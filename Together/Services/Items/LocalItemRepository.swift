import Foundation
import SwiftData

actor LocalItemRepository: ItemRepositoryProtocol {
    private let container: ModelContainer

    init(container: ModelContainer) {
        self.container = container
    }

    func fetchItems(spaceID: UUID?) async throws -> [Item] {
        let context = ModelContext(container)
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

        return try context.fetch(descriptor).map(\.domainModel)
    }

    func fetchItem(itemID: UUID) async throws -> Item? {
        let context = ModelContext(container)
        return try fetchRecord(itemID: itemID, context: context)?.domainModel
    }

    func updateItemStatus(itemID: UUID, response: ItemResponseKind?, actorID: UUID) async throws -> Item {
        let context = ModelContext(container)
        guard let record = try fetchRecord(itemID: itemID, context: context) else {
            throw RepositoryError.notFound
        }

        var item = record.domainModel
        if let response {
            let responseRecord = ItemResponse(
                responderID: actorID,
                kind: response,
                message: nil,
                respondedAt: .now
            )
            item.latestResponse = responseRecord
            item.responseHistory.append(responseRecord)
            item.status = ItemStateMachine.nextStatus(
                from: item.status,
                executionRole: item.executionRole,
                response: response
            )
        }

        item.updatedAt = .now
        record.update(from: item)
        try context.save()
        return record.domainModel
    }

    func markCompleted(itemID: UUID, actorID: UUID) async throws -> Item {
        let context = ModelContext(container)
        guard let record = try fetchRecord(itemID: itemID, context: context) else {
            throw RepositoryError.notFound
        }

        var item = record.domainModel
        if item.repeatRule == nil {
            item.status = ItemStateMachine.nextStatus(
                from: item.status,
                executionRole: item.executionRole,
                isCompletion: true
            )
        }
        item.completedAt = .now
        item.updatedAt = .now
        record.update(from: item)
        try context.save()
        return record.domainModel
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
            record.update(from: savedItem)
        } else {
            context.insert(PersistentItem(item: savedItem))
        }

        try context.save()
        return savedItem
    }

    func deleteItem(itemID: UUID) async throws {
        let context = ModelContext(container)
        guard let record = try fetchRecord(itemID: itemID, context: context) else {
            throw RepositoryError.notFound
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
}
