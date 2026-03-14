import Foundation
import Observation

@MainActor
@Observable
final class CalendarViewModel {
    private let sessionStore: SessionStore
    private let itemRepository: ItemRepositoryProtocol
    private let calendar = Calendar.current

    var loadState: LoadableState = .idle
    var selectedDate: Date = MockDataFactory.now
    var scheduledItems: [Item] = []
    var isMonthMode = false

    init(sessionStore: SessionStore, itemRepository: ItemRepositoryProtocol) {
        self.sessionStore = sessionStore
        self.itemRepository = itemRepository
    }

    var selectedDateTitle: String {
        selectedDate.formatted(.dateTime.year().month().day())
    }

    var selectedItems: [Item] {
        scheduledItems.filter { item in
            guard let dueAt = item.dueAt else { return false }
            return calendar.isDate(dueAt, inSameDayAs: selectedDate)
        }
    }

    func load() async {
        loadState = .loading

        do {
            scheduledItems = try await itemRepository.fetchItems(spaceID: sessionStore.currentSpace?.id)
            loadState = .loaded
        } catch {
            loadState = .failed(error.localizedDescription)
        }
    }

    func toggleMode() {
        isMonthMode.toggle()
    }
}
