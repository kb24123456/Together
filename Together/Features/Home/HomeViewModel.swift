import Foundation
import Observation

struct HomeAvatar: Identifiable, Hashable {
    let id: UUID
    let displayName: String
    let systemImageName: String
}

struct HomeTimelineEntry: Identifiable, Hashable {
    let id: UUID
    let title: String
    let notes: String?
    let locationText: String?
    let timeText: String
    let statusText: String
    let executionLabel: String
    let symbolName: String
    let accentColorName: String
    let showsSolidSymbol: Bool
    let isMuted: Bool
}

@MainActor
@Observable
final class HomeViewModel {
    private let calendar = Calendar.current
    private let sessionStore: SessionStore
    private let itemRepository: ItemRepositoryProtocol
    private let anniversaryRepository: AnniversaryRepositoryProtocol

    var selectedDate: Date = MockDataFactory.now
    var items: [Item] = []
    var currentUserAvatar: HomeAvatar
    var partnerAvatar: HomeAvatar

    init(
        sessionStore: SessionStore,
        itemRepository: ItemRepositoryProtocol,
        anniversaryRepository: AnniversaryRepositoryProtocol
    ) {
        self.sessionStore = sessionStore
        self.itemRepository = itemRepository
        self.anniversaryRepository = anniversaryRepository
        let currentUser = sessionStore.currentUser ?? MockDataFactory.makeCurrentUser()
        let partner = MockDataFactory.makePartnerUser()
        self.currentUserAvatar = HomeAvatar(
            id: currentUser.id,
            displayName: currentUser.displayName,
            systemImageName: currentUser.avatarSystemName ?? "person.crop.circle.fill"
        )
        self.partnerAvatar = HomeAvatar(
            id: partner.id,
            displayName: partner.displayName,
            systemImageName: partner.avatarSystemName ?? "heart.circle.fill"
        )
    }

    var headerDateText: String {
        let components = calendar.dateComponents([.month, .day], from: selectedDate)
        let month = components.month ?? 1
        let day = components.day ?? 1
        return "\(month)月\(day)日"
    }

    var selectedDateTitle: String {
        let components = calendar.dateComponents([.month, .day], from: selectedDate)
        let month = components.month ?? 1
        let day = components.day ?? 1
        return "\(month)月\(day)日"
    }

    var weekDates: [Date] {
        let interval = calendar.dateInterval(of: .weekOfYear, for: selectedDate)
            ?? DateInterval(start: selectedDate, duration: 86_400 * 7)

        return (0..<7).compactMap {
            calendar.date(byAdding: .day, value: $0, to: interval.start)
        }
    }

    func selectDate(_ date: Date) {
        selectedDate = date
    }

    func loadIfNeeded() async {
        guard items.isEmpty else { return }
        await reload()
    }

    func reload() async {
        do {
            items = try await itemRepository.fetchItems(
                relationshipID: sessionStore.currentPairSpace?.id
            )
        } catch {
            items = []
        }
    }

    func isSelectedDate(_ date: Date) -> Bool {
        calendar.isDate(date, inSameDayAs: selectedDate)
    }

    func weekdayLabel(for date: Date) -> String {
        switch calendar.component(.weekday, from: date) {
        case 1: return "周日"
        case 2: return "周一"
        case 3: return "周二"
        case 4: return "周三"
        case 5: return "周四"
        case 6: return "周五"
        case 7: return "周六"
        default: return ""
        }
    }

    var timelineEntries: [HomeTimelineEntry] {
        let viewerID = sessionStore.currentUser?.id ?? MockDataFactory.currentUserID

        return items
            .filter { item in
                guard let dueAt = item.dueAt else { return false }
                return calendar.isDate(dueAt, inSameDayAs: selectedDate)
            }
            .sorted(by: compareItems)
            .map { item in
                HomeTimelineEntry(
                    id: item.id,
                    title: item.title,
                    notes: item.notes,
                    locationText: item.locationText,
                    timeText: timeText(for: item.dueAt),
                    statusText: item.status.title,
                    executionLabel: item.executionRole.label(for: viewerID, creatorID: item.creatorID),
                    symbolName: symbolName(for: item),
                    accentColorName: accentColorName(for: item),
                    showsSolidSymbol: item.isPinned || item.priority == .critical,
                    isMuted: item.priority == .normal && item.isPinned == false
                )
            }
    }

    private func compareItems(lhs: Item, rhs: Item) -> Bool {
        if lhs.isPinned != rhs.isPinned {
            return lhs.isPinned && rhs.isPinned == false
        }

        let lhsDue = lhs.dueAt ?? .distantFuture
        let rhsDue = rhs.dueAt ?? .distantFuture
        if lhsDue != rhsDue {
            return lhsDue < rhsDue
        }

        if priorityRank(lhs.priority) != priorityRank(rhs.priority) {
            return priorityRank(lhs.priority) > priorityRank(rhs.priority)
        }

        return lhs.createdAt < rhs.createdAt
    }

    private func priorityRank(_ priority: ItemPriority) -> Int {
        switch priority {
        case .critical:
            return 3
        case .important:
            return 2
        case .normal:
            return 1
        }
    }

    private func timeText(for date: Date?) -> String {
        guard let date else { return "--:--" }
        return date.formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits))
    }

    private func symbolName(for item: Item) -> String {
        switch item.title {
        case "起床":
            return "sun.max.fill"
        case "放松":
            return "moon.fill"
        default:
            return item.isPinned ? "sparkles" : "circle"
        }
    }

    private func accentColorName(for item: Item) -> String {
        if item.isPinned || item.priority == .critical {
            return "coral"
        }

        switch item.title {
        case "起床":
            return "sun"
        case "放松":
            return "violet"
        default:
            return "neutral"
        }
    }
}
