import Foundation

protocol ItemRepositoryProtocol: Sendable {
    func fetchActiveItems(spaceID: UUID?) async throws -> [Item]
    func fetchArchivedCompletedItems(
        spaceID: UUID?,
        searchText: String?,
        before: Date?,
        limit: Int
    ) async throws -> [Item]
    func archiveCompletedItemsIfNeeded(
        spaceID: UUID?,
        referenceDate: Date,
        autoArchiveDays: Int
    ) async throws -> Bool
    func restoreArchivedItem(itemID: UUID) async throws -> Item
    func fetchItem(itemID: UUID) async throws -> Item?
    func fetchOccurrenceCompletions(itemIDs: [UUID]) async throws -> [UUID: [ItemOccurrenceCompletion]]
    func isCompleted(itemID: UUID, on referenceDate: Date) async throws -> Bool
    func updateItemStatus(itemID: UUID, response: ItemResponseKind?, actorID: UUID) async throws -> Item
    func markCompleted(itemID: UUID, actorID: UUID, referenceDate: Date) async throws -> Item
    func markIncomplete(itemID: UUID, actorID: UUID, referenceDate: Date) async throws -> Item
    func saveItem(_ item: Item) async throws -> Item
    func deleteItem(itemID: UUID) async throws
}

extension ItemRepositoryProtocol {
    func fetchItems(spaceID: UUID?) async throws -> [Item] {
        try await fetchActiveItems(spaceID: spaceID)
    }

    func markCompleted(itemID: UUID, actorID: UUID) async throws -> Item {
        try await markCompleted(itemID: itemID, actorID: actorID, referenceDate: .now)
    }

    func markIncomplete(itemID: UUID, actorID: UUID) async throws -> Item {
        try await markIncomplete(itemID: itemID, actorID: actorID, referenceDate: .now)
    }
}
