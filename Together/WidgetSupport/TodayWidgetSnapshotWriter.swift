import Foundation

actor TodayWidgetSnapshotWriter: TodayWidgetSnapshotWriting {
    private let itemRepository: ItemRepositoryProtocol
    private let contextStore: TodayWidgetSharedContextStore
    private let snapshotStore: TodayWidgetSnapshotStore
    private let builder: TodayWidgetSnapshotBuilder

    init(
        itemRepository: ItemRepositoryProtocol,
        contextStore: TodayWidgetSharedContextStore? = nil,
        snapshotStore: TodayWidgetSnapshotStore? = nil,
        builder: TodayWidgetSnapshotBuilder? = nil
    ) {
        self.itemRepository = itemRepository
        self.contextStore = contextStore ?? TodayWidgetSharedContextStore()
        self.snapshotStore = snapshotStore ?? TodayWidgetSnapshotStore()
        self.builder = builder ?? TodayWidgetSnapshotBuilder()
    }

    func refreshTodayWidgetSnapshot() async throws {
        guard let context = contextStore.read() else {
            try snapshotStore.write(.empty)
            return
        }

        let items = try await itemRepository.fetchActiveItems(spaceID: context.spaceID)
        let snapshot = builder.build(items: items, referenceDate: .now, limit: 3)
        try snapshotStore.write(snapshot)
    }
}
