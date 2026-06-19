import Foundation
import Observation

struct CompletedHistorySection: Identifiable, Hashable {
    let id: String
    let title: String
    let items: [Item]
}

enum CompletedHistoryFilter: String, CaseIterable, Identifiable, Hashable {
    case week
    case month
    case all

    var id: String { rawValue }

    var title: String {
        switch self {
        case .week: return "本周"
        case .month: return "本月"
        case .all: return "所有"
        }
    }

    var range: CompletedTaskRange {
        switch self {
        case .week: return .workweek
        case .month: return .month
        case .all: return .all
        }
    }
}

@MainActor
@Observable
final class CompletedHistoryViewModel {
    private let calendar = Calendar.current
    private let sessionStore: SessionStore
    private let itemRepository: ItemRepositoryProtocol
    private let taskApplicationService: TaskApplicationServiceProtocol
    private let taskListRepository: TaskListRepositoryProtocol
    private let projectRepository: ProjectRepositoryProtocol
    private let pageSize = 30

    var onTaskMutated: ((UUID) -> Void)?
    var items: [Item] = []
    var searchText = ""
    var selectedFilter: CompletedHistoryFilter
    var isLoading = false
    var hasLoaded = false
    var canLoadMore = true

    private var projectNames: [UUID: String] = [:]
    private var taskListNames: [UUID: String] = [:]

    init(
        sessionStore: SessionStore,
        itemRepository: ItemRepositoryProtocol,
        taskApplicationService: TaskApplicationServiceProtocol,
        taskListRepository: TaskListRepositoryProtocol,
        projectRepository: ProjectRepositoryProtocol,
        initialFilter: CompletedHistoryFilter = .week
    ) {
        self.sessionStore = sessionStore
        self.itemRepository = itemRepository
        self.taskApplicationService = taskApplicationService
        self.taskListRepository = taskListRepository
        self.projectRepository = projectRepository
        self.selectedFilter = initialFilter
    }

    var sections: [CompletedHistorySection] {
        let grouped = Dictionary(grouping: items) { item in
            sectionKey(for: item.historySortDate)
        }

        return grouped.keys.sorted(by: >).compactMap { key in
            guard let sectionItems = grouped[key] else { return nil }
            let sortedItems = sectionItems.sorted {
                $0.historySortDate > $1.historySortDate
            }

            return CompletedHistorySection(
                id: key,
                title: sectionTitle(for: key),
                items: sortedItems
            )
        }
    }

    var isEmpty: Bool {
        hasLoaded && items.isEmpty
    }

    func loadIfNeeded() async {
        guard hasLoaded == false else { return }
        await reload()
    }

    func reload() async {
        guard let spaceID = sessionStore.currentSpace?.id else {
            items = []
            canLoadMore = false
            hasLoaded = true
            return
        }

        isLoading = true
        defer { isLoading = false }

        await refreshReferenceNames(spaceID: spaceID)
        await runAutoArchiveIfNeeded(spaceID: spaceID)

        do {
            let bounds = selectedFilter.range.bounds(for: .now, calendar: calendar)
            let fetched = try await itemRepository.fetchCompletedItems(
                spaceID: spaceID,
                searchText: normalizedSearchText,
                completedFrom: bounds.lowerBound,
                completedBefore: bounds.upperBound,
                before: nil,
                limit: pageSize
            )
            items = fetched
            canLoadMore = fetched.count == pageSize
            hasLoaded = true
        } catch {
            items = []
            canLoadMore = false
            hasLoaded = true
        }

    }

    func loadMoreIfNeeded(currentItem item: Item) async {
        guard canLoadMore, isLoading == false else { return }
        guard item.id == items.last?.id else { return }
        await loadMore()
    }

    func restore(_ item: Item) async {
        guard let actorID = sessionStore.currentUser?.id else { return }

        do {
            let restored = try await itemRepository.markIncomplete(
                itemID: item.id,
                actorID: actorID,
                referenceDate: item.completedAt ?? .now
            )
            items.removeAll { $0.id == restored.id }
            canLoadMore = true
            if let spaceID = restored.spaceID ?? sessionStore.currentSpace?.id {
                onTaskMutated?(spaceID)
            }
        } catch {
            return
        }
    }

    func delete(_ item: Item) async {
        guard let actorID = sessionStore.currentUser?.id else {
            return
        }
        guard let spaceID = item.spaceID ?? sessionStore.currentSpace?.id else { return }

        do {
            try await taskApplicationService.deleteTask(
                in: spaceID,
                taskID: item.id,
                actorID: actorID
            )
        } catch {
            do {
                // Historical rows can outlive profile repair. Tombstone the
                // current history row directly so users can clean stale entries.
                try await itemRepository.deleteItem(itemID: item.id)
            } catch {
                return
            }
        }

        items.removeAll { $0.id == item.id }
        canLoadMore = true
        onTaskMutated?(spaceID)
    }

    func subtitle(for item: Item) -> String {
        if item.subtasks.isEmpty == false {
            return "\(item.subtasks.filter(\.isCompleted).count)/\(item.subtasks.count) 子任务"
        }
        if let notes = item.notes, notes.isEmpty == false {
            return notes
        }
        let projectName = item.projectID.flatMap { projectNames[$0] }
        let listName = item.listID.flatMap { taskListNames[$0] }
        let parts = [projectName, listName].compactMap { $0 }
        if parts.isEmpty {
            return "未归类任务"
        }
        return parts.joined(separator: " · ")
    }

    func completedDateText(for item: Item) -> String {
        guard let completedAt = item.completedAt else { return "完成时间未知" }
        return completedAt.formatted(date: .abbreviated, time: .shortened)
    }

    func archivedDateText(for item: Item) -> String {
        guard let archivedAt = item.archivedAt else { return "尚未归档" }
        return archivedAt.formatted(date: .abbreviated, time: .omitted)
    }

    func isArchived(_ item: Item) -> Bool {
        item.isArchived && item.archivedAt != nil
    }

    func avatarAsset(forUserID userID: UUID?) -> UserAvatarAsset {
        guard let userID else { return .system("person.fill") }
        if userID == sessionStore.currentUser?.id {
            return sessionStore.currentUser?.avatarAsset ?? .system("person.crop.circle.fill")
        }
        return .system("person.fill")
    }

    func displayName(forUserID userID: UUID?) -> String {
        guard let userID else { return "未知完成者" }
        if userID == sessionStore.currentUser?.id {
            return sessionStore.currentUser?.displayName ?? "我"
        }
        return "未知完成者"
    }

    private var normalizedSearchText: String? {
        let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func loadMore() async {
        guard let spaceID = sessionStore.currentSpace?.id else { return }
        let cursor = items.last?.historySortDate

        isLoading = true
        defer { isLoading = false }

        do {
            let bounds = selectedFilter.range.bounds(for: .now, calendar: calendar)
            let fetched = try await itemRepository.fetchCompletedItems(
                spaceID: spaceID,
                searchText: normalizedSearchText,
                completedFrom: bounds.lowerBound,
                completedBefore: bounds.upperBound,
                before: cursor,
                limit: pageSize
            )
            items.append(contentsOf: fetched)
            canLoadMore = fetched.count == pageSize
        } catch {
            canLoadMore = false
        }
    }

    private func refreshReferenceNames(spaceID: UUID) async {
        async let taskLists = taskListRepository.fetchTaskLists(spaceID: spaceID)
        async let projects = projectRepository.fetchProjects(spaceID: spaceID)

        if let lists = try? await taskLists {
            taskListNames = Dictionary(uniqueKeysWithValues: lists.map { ($0.id, $0.name) })
        }
        if let projects = try? await projects {
            projectNames = Dictionary(uniqueKeysWithValues: projects.map { ($0.id, $0.name) })
        }
    }

    private func runAutoArchiveIfNeeded(spaceID: UUID) async {
        guard sessionStore.currentUser?.preferences.completedTaskAutoArchiveEnabled ?? true else {
            return
        }

        let days = NotificationSettings.normalizedCompletedTaskAutoArchiveDays(
            sessionStore.currentUser?.preferences.completedTaskAutoArchiveDays
            ?? NotificationSettings.defaultCompletedTaskAutoArchiveDays
        )
        _ = try? await itemRepository.archiveCompletedItemsIfNeeded(
            spaceID: spaceID,
            referenceDate: .now,
            autoArchiveDays: days
        )
    }

    private func monthKey(for date: Date) -> String {
        let components = calendar.dateComponents([.year, .month], from: date)
        let year = components.year ?? 0
        let month = components.month ?? 1
        let monthText = month.formatted(.number.precision(.integerLength(2)))
        return "\(year)-\(monthText)"
    }

    private func monthTitle(for key: String) -> String {
        let parts = key.split(separator: "-")
        guard parts.count == 2 else { return key }
        return "\(parts[0])年\(parts[1])月"
    }

    private func dayKey(for date: Date) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        let year = components.year ?? 0
        let month = (components.month ?? 1).formatted(.number.precision(.integerLength(2)))
        let day = (components.day ?? 1).formatted(.number.precision(.integerLength(2)))
        return "\(year)-\(month)-\(day)"
    }

    private func sectionKey(for date: Date) -> String {
        switch selectedFilter {
        case .week:
            return weekdaySortKey(for: date)
        case .month:
            return dayKey(for: date)
        case .all:
            return monthKey(for: date)
        }
    }

    private func sectionTitle(for key: String) -> String {
        switch selectedFilter {
        case .week:
            return weekdayTitle(forSortKey: key)
        case .month:
            return dayTitle(for: key)
        case .all:
            return monthTitle(for: key)
        }
    }

    private func weekdaySortKey(for date: Date) -> String {
        let weekday = calendar.component(.weekday, from: date)
        let order: Int
        switch weekday {
        case 6: order = 5
        case 5: order = 4
        case 4: order = 3
        case 3: order = 2
        case 2: order = 1
        default: order = 0
        }
        return order.formatted(.number.precision(.integerLength(2)))
    }

    private func weekdayTitle(forSortKey key: String) -> String {
        switch Int(key) ?? 0 {
        case 5: return "周五"
        case 4: return "周四"
        case 3: return "周三"
        case 2: return "周二"
        case 1: return "周一"
        default: return "其他"
        }
    }

    private func dayTitle(for key: String) -> String {
        let parts = key.split(separator: "-")
        guard parts.count == 3,
              let month = Int(parts[1]),
              let day = Int(parts[2]) else {
            return key
        }
        return "\(month)月\(day)日"
    }
}

private extension Item {
    var historySortDate: Date {
        archivedAt ?? completedAt ?? updatedAt
    }
}
