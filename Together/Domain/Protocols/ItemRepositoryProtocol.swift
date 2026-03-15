import Foundation

protocol ItemRepositoryProtocol: Sendable {
    func fetchItems(spaceID: UUID?) async throws -> [Item]
    func fetchItem(itemID: UUID) async throws -> Item?
    func updateItemStatus(itemID: UUID, response: ItemResponseKind?, actorID: UUID) async throws -> Item
    func markCompleted(itemID: UUID, actorID: UUID) async throws -> Item
    func saveItem(_ item: Item) async throws -> Item
    func deleteItem(itemID: UUID) async throws
}
