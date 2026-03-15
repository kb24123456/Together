import Foundation

@MainActor
final class MockItemRepository: ItemRepositoryProtocol {
    private var items: [Item] = MockDataFactory.makeItems()

    func fetchItems(spaceID: UUID?) async throws -> [Item] {
        items
            .filter { $0.spaceID == spaceID && $0.isArchived == false }
            .sorted { $0.updatedAt > $1.updatedAt }
    }

    func fetchItem(itemID: UUID) async throws -> Item? {
        items.first(where: { $0.id == itemID })
    }

    func updateItemStatus(itemID: UUID, response: ItemResponseKind?, actorID: UUID) async throws -> Item {
        guard let index = items.firstIndex(where: { $0.id == itemID }) else {
            throw RepositoryError.notFound
        }

        var item = items[index]
        if let response {
            let record = ItemResponse(
                responderID: actorID,
                kind: response,
                message: nil,
                respondedAt: MockDataFactory.now
            )
            item.latestResponse = record
            item.responseHistory.append(record)
            item.status = ItemStateMachine.nextStatus(
                from: item.status,
                executionRole: item.executionRole,
                response: response
            )
        }
        item.updatedAt = MockDataFactory.now
        items[index] = item
        return item
    }

    func markCompleted(itemID: UUID, actorID: UUID) async throws -> Item {
        guard let index = items.firstIndex(where: { $0.id == itemID }) else {
            throw RepositoryError.notFound
        }

        var item = items[index]
        if item.repeatRule == nil {
            item.status = ItemStateMachine.nextStatus(
                from: item.status,
                executionRole: item.executionRole,
                isCompletion: true
            )
        }
        item.completedAt = MockDataFactory.now
        item.updatedAt = MockDataFactory.now
        items[index] = item
        return item
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
        return updatedItem
    }

    func deleteItem(itemID: UUID) async throws {
        guard let index = items.firstIndex(where: { $0.id == itemID }) else {
            throw RepositoryError.notFound
        }
        items.remove(at: index)
    }
}
