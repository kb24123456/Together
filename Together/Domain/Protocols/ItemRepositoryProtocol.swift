import Foundation

/// Scalar aggregates over completed items.
/// Cheaper than fetching every full Item when the user has hundreds of
/// completions — the repository can fetch only the fields it needs and
/// compute counts via a single pass.
struct CompletedItemStats: Equatable, Sendable {
    let totalCount: Int
    let thisMonthCount: Int
    let firstCompletedAt: Date?
    let firstItemTitle: String?
    let lastCompletedAt: Date?

    static let empty = CompletedItemStats(
        totalCount: 0,
        thisMonthCount: 0,
        firstCompletedAt: nil,
        firstItemTitle: nil,
        lastCompletedAt: nil
    )
}

protocol ItemRepositoryProtocol: Sendable {
    func fetchActiveItems(spaceID: UUID?) async throws -> [Item]
    func fetchHomeItems(spaceID: UUID?, completedFrom: Date, completedBefore: Date) async throws -> [Item]
    /// 拉取已完成（非归档）条目。`since != nil` 时只返回 `cursorDate >= since` 的记录，
    func fetchCompletedItems(
        spaceID: UUID?,
        searchText: String?,
        before: Date?,
        since: Date?,
        limit: Int
    ) async throws -> [Item]
    func fetchCompletedItems(
        spaceID: UUID?,
        searchText: String?,
        completedFrom: Date?,
        completedBefore: Date?,
        before: Date?,
        limit: Int
    ) async throws -> [Item]
    func completedItemCount(
        spaceID: UUID?,
        completedFrom: Date?,
        completedBefore: Date?
    ) async throws -> Int
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
    func markCompleted(itemID: UUID, actorID: UUID, referenceDate: Date) async throws -> Item
    func markIncomplete(itemID: UUID, actorID: UUID, referenceDate: Date) async throws -> Item
    func saveItem(_ item: Item) async throws -> Item
    func addSubtask(itemID: UUID, title: String, creatorID: UUID) async throws -> Item
    func toggleSubtask(itemID: UUID, subtaskID: UUID, actorID: UUID) async throws -> Item
    func updateSubtask(itemID: UUID, subtaskID: UUID, title: String, actorID: UUID) async throws -> Item
    func deleteSubtask(itemID: UUID, subtaskID: UUID, actorID: UUID) async throws -> Item
    func reorderItems(itemIDs: [UUID]) async throws -> [Item]
    func deleteItem(itemID: UUID) async throws
}

extension ItemRepositoryProtocol {
    func fetchItems(spaceID: UUID?) async throws -> [Item] {
        try await fetchActiveItems(spaceID: spaceID)
    }

    func fetchHomeItems(spaceID: UUID?, completedFrom: Date, completedBefore: Date) async throws -> [Item] {
        try await fetchActiveItems(spaceID: spaceID).filter { item in
            guard item.isArchived == false else { return false }
            guard item.status == .completed || item.completedAt != nil else { return true }
            guard let completedAt = item.completedAt else { return false }
            return completedAt >= completedFrom && completedAt < completedBefore
        }
    }

    /// 无 `since` 参数的便捷 overload。
    func fetchCompletedItems(
        spaceID: UUID?,
        searchText: String?,
        before: Date?,
        limit: Int
    ) async throws -> [Item] {
        try await fetchCompletedItems(
            spaceID: spaceID,
            searchText: searchText,
            before: before,
            since: nil,
            limit: limit
        )
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
