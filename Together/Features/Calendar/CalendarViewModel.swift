import Foundation
import Observation

enum CalendarPairTaskFilter: String, CaseIterable, Hashable {
    case all
    case mine
    case partner
    case both
    case awaitingResponse

    var title: String {
        switch self {
        case .all: return "全部"
        case .mine: return "我负责"
        case .partner: return "对方负责"
        case .both: return "一起"
        case .awaitingResponse: return "待我回应"
        }
    }
}

@MainActor
@Observable
final class CalendarViewModel {
    private let sessionStore: SessionStore
    private let itemRepository: ItemRepositoryProtocol
    private let calendar = Calendar.current

    var loadState: LoadableState = .idle
    var selectedDate: Date = Date()
    var scheduledItems: [Item] = []
    var isMonthMode = false
    var pairTaskFilter: CalendarPairTaskFilter = .all

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
            guard calendar.isDate(dueAt, inSameDayAs: selectedDate) else { return false }
            return matchesPairFilter(item)
        }
    }

    var isPairModeActive: Bool {
        sessionStore.activeMode == .pair
    }

    var spaceSummary: String {
        sessionStore.currentSpace?.displayName ?? (isPairModeActive ? "双人空间" : "我的任务空间")
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

    func setPairTaskFilter(_ filter: CalendarPairTaskFilter) {
        pairTaskFilter = filter
    }

    private func matchesPairFilter(_ item: Item) -> Bool {
        guard isPairModeActive else { return true }
        let viewerID = sessionStore.currentUser?.id ?? item.creatorID

        switch pairTaskFilter {
        case .all:
            return true
        case .mine:
            return item.executionRole.label(for: viewerID, creatorID: item.creatorID) == "我负责"
        case .partner:
            return item.executionRole.label(for: viewerID, creatorID: item.creatorID) == "对方负责"
        case .both:
            return item.assigneeMode == .both
        case .awaitingResponse:
            return item.requiresResponse && item.canActorRespond(viewerID)
        }
    }
}
