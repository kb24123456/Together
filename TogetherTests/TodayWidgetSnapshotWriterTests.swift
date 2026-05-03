import Foundation
import Testing
@testable import Together

@MainActor
@Suite("Today Widget Snapshot Writer")
struct TodayWidgetSnapshotWriterTests {
    @Test("shared context store writes reads and clears context")
    func sharedContextStoreWritesReadsAndClearsContext() throws {
        let suiteName = "today-widget-context-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = TodayWidgetSharedContextStore(defaults: defaults)
        let context = TodayWidgetSharedContext(spaceID: UUID(), actorID: UUID())

        store.write(context)
        #expect(store.read() == context)

        store.clear()
        #expect(store.read() == nil)
    }

    @Test("writes snapshot from active items")
    func writesSnapshotFromActiveItems() async throws {
        let containerURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        let suiteName = "today-widget-writer-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let spaceID = UUID()
        let actorID = UUID()
        let item = makeTask(spaceID: spaceID, actorID: actorID, title: "核对审核备注")
        let repository = MockTodayWidgetItemRepository(items: [item])
        let contextStore = TodayWidgetSharedContextStore(defaults: defaults)
        contextStore.write(TodayWidgetSharedContext(spaceID: spaceID, actorID: actorID))
        let snapshotStore = TodayWidgetSnapshotStore(containerURL: containerURL)
        let writer = TodayWidgetSnapshotWriter(
            itemRepository: repository,
            contextStore: contextStore,
            snapshotStore: snapshotStore,
            builder: TodayWidgetSnapshotBuilder()
        )

        try await writer.refreshTodayWidgetSnapshot()
        let snapshot = try snapshotStore.read()

        #expect(snapshot.remainingCount == 1)
        #expect(snapshot.tasks.map(\.title) == ["核对审核备注"])
    }

    private func makeTask(spaceID: UUID, actorID: UUID, title: String) -> Item {
        Item(
            id: UUID(),
            spaceID: spaceID,
            listID: nil,
            projectID: nil,
            creatorID: actorID,
            title: title,
            notes: nil,
            executionRole: .initiator,
            assigneeMode: .self,
            dueAt: nil,
            hasExplicitTime: false,
            remindAt: nil,
            status: .inProgress,
            responseHistory: [],
            createdAt: .now,
            updatedAt: .now,
            isDraft: false
        )
    }
}

private actor MockTodayWidgetItemRepository: ItemRepositoryProtocol {
    private var items: [Item]

    init(items: [Item]) {
        self.items = items
    }

    func fetchActiveItems(spaceID: UUID?) async throws -> [Item] {
        items.filter { $0.spaceID == spaceID }
    }

    func fetchCompletedItems(
        spaceID: UUID?,
        searchText: String?,
        before: Date?,
        since: Date?,
        limit: Int
    ) async throws -> [Item] {
        []
    }

    func completedItemStats(spaceID: UUID?, referenceDate: Date) async throws -> CompletedItemStats {
        .empty
    }

    func fetchArchivedCompletedItems(
        spaceID: UUID?,
        searchText: String?,
        before: Date?,
        limit: Int
    ) async throws -> [Item] {
        []
    }

    func archiveCompletedItemsIfNeeded(spaceID: UUID?, referenceDate: Date, autoArchiveDays: Int) async throws -> Bool {
        false
    }

    func restoreArchivedItem(itemID: UUID) async throws -> Item {
        try requireItem(itemID: itemID)
    }

    func fetchItem(itemID: UUID) async throws -> Item? {
        items.first { $0.id == itemID }
    }

    func fetchOccurrenceCompletions(itemIDs: [UUID]) async throws -> [UUID: [ItemOccurrenceCompletion]] {
        [:]
    }

    func isCompleted(itemID: UUID, on referenceDate: Date) async throws -> Bool {
        false
    }

    func updateItemStatus(itemID: UUID, response: ItemResponseKind?, message: String?, actorID: UUID) async throws -> Item {
        try requireItem(itemID: itemID)
    }

    func markCompleted(itemID: UUID, actorID: UUID, referenceDate: Date) async throws -> Item {
        try requireItem(itemID: itemID)
    }

    func markIncomplete(itemID: UUID, actorID: UUID, referenceDate: Date) async throws -> Item {
        try requireItem(itemID: itemID)
    }

    func saveItem(_ item: Item) async throws -> Item {
        items.append(item)
        return item
    }

    func reorderItems(itemIDs: [UUID]) async throws -> [Item] {
        items
    }

    func deleteItem(itemID: UUID) async throws {
        items.removeAll { $0.id == itemID }
    }

    private func requireItem(itemID: UUID) throws -> Item {
        guard let item = items.first(where: { $0.id == itemID }) else {
            throw TodayWidgetTestError.missingItem
        }
        return item
    }
}

private enum TodayWidgetTestError: Error {
    case missingItem
}
