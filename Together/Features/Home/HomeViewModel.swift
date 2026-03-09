import Foundation
import Observation

enum HomeFilter: String, CaseIterable, Hashable {
    case all
    case mine
    case partner
    case shared
    case important

    var title: String {
        switch self {
        case .all:
            return "全部"
        case .mine:
            return "我负责"
        case .partner:
            return "对方负责"
        case .shared:
            return "一起做"
        case .important:
            return "重要"
        }
    }
}

@MainActor
@Observable
final class HomeViewModel {
    private let sessionStore: SessionStore
    private let itemRepository: ItemRepositoryProtocol
    private let anniversaryRepository: AnniversaryRepositoryProtocol

    var loadState: LoadableState = .idle
    var selectedDate: Date = MockDataFactory.now
    var selectedFilter: HomeFilter = .all
    var pendingItems: [Item] = []
    var inProgressItems: [Item] = []
    var highlightedAnniversary: Anniversary?

    init(
        sessionStore: SessionStore,
        itemRepository: ItemRepositoryProtocol,
        anniversaryRepository: AnniversaryRepositoryProtocol
    ) {
        self.sessionStore = sessionStore
        self.itemRepository = itemRepository
        self.anniversaryRepository = anniversaryRepository
    }

    var currentUserID: UUID? { sessionStore.currentUser?.id }
    var bindingState: BindingState { sessionStore.bindingState }
    var partnerName: String { "TA" }

    var filteredInProgressItems: [Item] {
        guard let currentUserID else { return inProgressItems }

        switch selectedFilter {
        case .all:
            return inProgressItems
        case .mine:
            return inProgressItems.filter {
                $0.executionRole.label(for: currentUserID, creatorID: $0.creatorID) == "我负责"
            }
        case .partner:
            return inProgressItems.filter {
                $0.executionRole.label(for: currentUserID, creatorID: $0.creatorID) == "对方负责"
            }
        case .shared:
            return inProgressItems.filter { $0.executionRole == .both }
        case .important:
            return inProgressItems.filter { $0.priority != .normal }
        }
    }

    func load() async {
        loadState = .loading

        do {
            let relationshipID = sessionStore.currentPairSpace?.id
            let items = try await itemRepository.fetchItems(relationshipID: relationshipID)
            pendingItems = items.filter { $0.status == .pendingConfirmation }
            inProgressItems = items.filter { $0.status == .inProgress }

            let anniversaries = try await anniversaryRepository.fetchAnniversaries(relationshipID: relationshipID)
            highlightedAnniversary = anniversaries.first
            loadState = .loaded
        } catch {
            loadState = .failed(error.localizedDescription)
        }
    }

    func availableResponses(for item: Item) -> [ItemResponseKind] {
        switch item.executionRole {
        case .initiator:
            return [.acknowledged]
        case .recipient, .both:
            return [.willing, .notAvailableNow, .notSuitable]
        }
    }

    func submitResponse(for item: Item, response: ItemResponseKind) async {
        guard let currentUserID else { return }
        _ = try? await itemRepository.updateItemStatus(
            itemID: item.id,
            response: response,
            actorID: currentUserID
        )
        await load()
    }

    func markCompleted(_ item: Item) async {
        guard let currentUserID else { return }
        _ = try? await itemRepository.markCompleted(itemID: item.id, actorID: currentUserID)
        await load()
    }
}
