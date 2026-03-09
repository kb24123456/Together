import Foundation

@MainActor
final class MockItemRepository: ItemRepositoryProtocol {
    private var items: [Item] = MockDataFactory.makeItems()

    func fetchItems(relationshipID: UUID?) async throws -> [Item] {
        items
            .filter { $0.relationshipID == relationshipID }
            .sorted { $0.updatedAt > $1.updatedAt }
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
        item.status = ItemStateMachine.nextStatus(
            from: item.status,
            executionRole: item.executionRole,
            isCompletion: true
        )
        item.completedAt = MockDataFactory.now
        item.updatedAt = MockDataFactory.now
        items[index] = item
        return item
    }
}
