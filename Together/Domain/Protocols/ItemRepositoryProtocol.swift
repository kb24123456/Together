import Foundation

/// Scalar aggregates over completed items for pair-mode Logbook hero.
/// Cheaper than fetching every full Item when the user has hundreds of
/// completions — the repository can fetch only the fields it needs and
/// compute counts via a single pass.
struct CompletedItemStats: Equatable, Sendable {
    let totalCount: Int
    let thisMonthCount: Int
    let firstItemTitle: String?
    let lastCompletedAt: Date?

    static let empty = CompletedItemStats(
        totalCount: 0,
        thisMonthCount: 0,
        firstItemTitle: nil,
        lastCompletedAt: nil
    )
}

protocol ItemRepositoryProtocol: Sendable {
    func fetchActiveItems(spaceID: UUID?) async throws -> [Item]
    func fetchCompletedItems(
        spaceID: UUID?,
        searchText: String?,
        before: Date?,
        limit: Int
    ) async throws -> [Item]
    /// Aggregate stats (count, this-month count, first title, last date)
    /// over all completed items in the given space. Used by the Logbook
    /// hero; faster than a full-item fetch because no occurrence
    /// hydration / sort is needed.
    func completedItemStats(spaceID: UUID?, referenceDate: Date) async throws -> CompletedItemStats
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
    func updateItemStatus(itemID: UUID, response: ItemResponseKind?, message: String?, actorID: UUID) async throws -> Item
    func markCompleted(itemID: UUID, actorID: UUID, referenceDate: Date) async throws -> Item
    func markIncomplete(itemID: UUID, actorID: UUID, referenceDate: Date) async throws -> Item
    func saveItem(_ item: Item) async throws -> Item
    func deleteItem(itemID: UUID) async throws
}

extension ItemRepositoryProtocol {
    func fetchItems(spaceID: UUID?) async throws -> [Item] {
        try await fetchActiveItems(spaceID: spaceID)
    }

    func completedItemStats(spaceID: UUID?) async throws -> CompletedItemStats {
        try await completedItemStats(spaceID: spaceID, referenceDate: .now)
    }

    func markCompleted(itemID: UUID, actorID: UUID) async throws -> Item {
        try await markCompleted(itemID: itemID, actorID: actorID, referenceDate: .now)
    }

    func markIncomplete(itemID: UUID, actorID: UUID) async throws -> Item {
        try await markIncomplete(itemID: itemID, actorID: actorID, referenceDate: .now)
    }
}
