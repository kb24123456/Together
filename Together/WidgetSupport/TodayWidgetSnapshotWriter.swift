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

        let referenceDate = Date.now
        let completedFrom = Calendar.current.startOfDay(for: referenceDate)
        let completedBefore = Calendar.current.date(byAdding: .day, value: 1, to: completedFrom) ?? referenceDate
        let items = try await itemRepository.fetchHomeItems(
            spaceID: context.spaceID,
            completedFrom: completedFrom,
            completedBefore: completedBefore
        )
        let snapshot = builder.build(items: items, referenceDate: referenceDate, limit: .max)
        try snapshotStore.write(snapshot)
    }
}
