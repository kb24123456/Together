import Foundation
import Observation

struct CompletedHistorySection: Identifiable, Hashable {
    let id: String
    let title: String
    let items: [Item]
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

    var items: [Item] = []
    var searchText = ""
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
        projectRepository: ProjectRepositoryProtocol
    ) {
        self.sessionStore = sessionStore
        self.itemRepository = itemRepository
        self.taskApplicationService = taskApplicationService
        self.taskListRepository = taskListRepository
        self.projectRepository = projectRepository
    }

    var sections: [CompletedHistorySection] {
        let grouped = Dictionary(grouping: items) { item in
            monthKey(for: item.archivedAt ?? item.completedAt ?? item.updatedAt)
        }

        return grouped.keys.sorted(by: >).compactMap { key in
            guard let sectionItems = grouped[key] else { return nil }
            let sortedItems = sectionItems.sorted {
                ($0.archivedAt ?? $0.completedAt ?? .distantPast) > ($1.archivedAt ?? $1.completedAt ?? .distantPast)
            }

            return CompletedHistorySection(
                id: key,
                title: monthTitle(for: key),
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
            let fetched = try await itemRepository.fetchArchivedCompletedItems(
                spaceID: spaceID,
                searchText: normalizedSearchText,
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
        do {
            let restored = try await itemRepository.restoreArchivedItem(itemID: item.id)
            items.removeAll { $0.id == restored.id }
            canLoadMore = true
        } catch {
            return
        }
    }

    func delete(_ item: Item) async {
        guard
            let spaceID = sessionStore.currentSpace?.id,
            let actorID = sessionStore.currentUser?.id
        else {
            return
        }

        do {
            try await taskApplicationService.deleteTask(
                in: spaceID,
                taskID: item.id,
                actorID: actorID
            )
            items.removeAll { $0.id == item.id }
            canLoadMore = true
        } catch {
            return
        }
    }

    func subtitle(for item: Item) -> String {
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
        return "完成于 \(completedAt.formatted(date: .abbreviated, time: .shortened))"
    }

    func archivedDateText(for item: Item) -> String {
        guard let archivedAt = item.archivedAt else { return "尚未归档" }
        return "归档于 \(archivedAt.formatted(date: .abbreviated, time: .omitted))"
    }

    private var normalizedSearchText: String? {
        let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func loadMore() async {
        guard let spaceID = sessionStore.currentSpace?.id else { return }
        let cursor = items.last?.archivedAt ?? items.last?.completedAt

        isLoading = true
        defer { isLoading = false }

        do {
            let fetched = try await itemRepository.fetchArchivedCompletedItems(
                spaceID: spaceID,
                searchText: normalizedSearchText,
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
}
