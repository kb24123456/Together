import Foundation

protocol ItemRepositoryProtocol: Sendable {
    func fetchItems(relationshipID: UUID?) async throws -> [Item]
    func updateItemStatus(itemID: UUID, response: ItemResponseKind?, actorID: UUID) async throws -> Item
    func markCompleted(itemID: UUID, actorID: UUID) async throws -> Item
}
