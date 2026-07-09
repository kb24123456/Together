import Foundation
import Observation
import SwiftUI

struct HomeAvatar: Identifiable, Hashable {
    let id: UUID
    let displayName: String
    let avatarAsset: UserAvatarAsset
    let overrideImage: UIImage?

    static func == (lhs: HomeAvatar, rhs: HomeAvatar) -> Bool {
        lhs.id == rhs.id
            && lhs.displayName == rhs.displayName
            && lhs.avatarAsset == rhs.avatarAsset
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
        hasher.combine(displayName)
        hasher.combine(avatarAsset)
    }
}

struct HomeTimelineEntry: Identifiable, Hashable {
    let id: UUID
    let presentationID: String
    let title: String
    let notes: String?
    let timeText: String
    let reminderText: String
    let statusText: String
    let isUrgent: Bool
    let isMuted: Bool
    let isCompleted: Bool
    let timingUrgency: HomeTimelineTimingUrgency
    let relationText: String?
    let primaryAvatar: HomeAvatar?
    let secondaryAvatar: HomeAvatar?
    let lastActionAt: Date?
    let subtasks: [TaskSubtask]
    let subtaskCompletedCount: Int

    var itemID: UUID { id }
}

struct HomeTimelineSection: Identifiable, Hashable {
    let id: String
    let dayStart: Date
    let title: String
    let subtitle: String
    let isUnscheduled: Bool
    let entries: [HomeTimelineEntry]
}

struct HomeOverdueEntry: Identifiable, Hashable {
    let id: UUID
    let title: String
    let detailText: String
    let timeText: String
}

enum HomeTimelineTimingUrgency: Hashable {
    case normal
    case imminent
    case overdue
}

enum HomeReloadReason {
    case userInitiated
    case dateChange
    case modeSwitch
    case sync
    case startupRestore
    case userInserted

    var animatesItemChanges: Bool {
        switch self {
        case .userInitiated, .dateChange, .userInserted:
            true
        case .modeSwitch, .sync, .startupRestore:
            false
        }
    }
}

private struct HomeItemOccurrenceKey: Hashable {
    let itemID: UUID
    let dayStart: Date
}

struct TaskTemplateSaveResult: Sendable, Equatable {
    let templateID: UUID
    let isNewlyCreated: Bool
}

@MainActor
@Observable
final class HomeViewModel {
    private let calendar = Calendar.current
    private let sessionStore: SessionStore
    private let taskApplicationService: TaskApplicationServiceProtocol
    private let itemRepository: ItemRepositoryProtocol
    private let taskTemplateRepository: TaskTemplateRepositoryProtocol

    /// 任务操作完成后的回调，参数为 spaceID，用于刷新外部依赖。
    var onTaskMutated: ((UUID) -> Void)?
    var onTodayDataChanged: (@MainActor @Sendable () -> Void)?
    /// 将当前任务转为例行事务时的回调（传递任务标题）
    var onConvertToPeriodicTask: ((String) -> Void)?
    /// 将当前任务转为项目时的回调（传递任务标题）
    var onConvertToProject: ((String) -> Void)?

    private var detailSaveTask: Task<Void, Never>?
    private var savedDetailDraft: TaskDraft?
    private var hasCompletedDeferredMaintenance = false
    private var insertedItemIDs: Set<UUID> = []
    var selectedDate: Date = Date()
    var items: [Item] = []
    private(set) var reloadRevision = 0
    var selectedItemID: UUID?
    var detailDraft: TaskDraft?
    var detailDetent: PresentationDetent = .height(316)
    private var completingOccurrenceKeys: Set<HomeItemOccurrenceKey> = []
    private var animatingCompletionOccurrenceKeys: Set<HomeItemOccurrenceKey> = []
    private var animatingReopeningOccurrenceKeys: Set<HomeItemOccurrenceKey> = []
    var isWeeklyCompletedSheetPresented = false
    var isWeeklyCompletedSheetLoading = false
    var didFailLoadingWeeklyCompletedSheet = false
    var weeklyCompletedSheetItems: [Item] = []
    var weeklyCompletedEntryCount = 0
    var isPerformingSnooze = false
    var isOverdueSheetPresented = false
    var isDockHidden = false

    init(
        sessionStore: SessionStore,
        taskApplicationService: TaskApplicationServiceProtocol,
        itemRepository: ItemRepositoryProtocol,
        taskTemplateRepository: TaskTemplateRepositoryProtocol
    ) {
        self.sessionStore = sessionStore
        self.taskApplicationService = taskApplicationService
        self.itemRepository = itemRepository
        self.taskTemplateRepository = taskTemplateRepository
    }

    var currentUserID: UUID? {
        sessionStore.currentUser?.id
    }

    var selectedDateKey: String {
        String(Int(calendar.startOfDay(for: selectedDate).timeIntervalSince1970))
    }

    var selectedItem: Item? {
        guard let selectedItemID else { return nil }
        return items.first(where: { $0.id == selectedItemID })
    }

    var expandedDetailItemID: UUID? {
        selectedItemID
    }

    var inlineDetailDraft: TaskDraft? {
        detailDraft
    }

    var canEditSelectedItem: Bool {
        guard let item = selectedItem, let userID = sessionStore.currentUser?.id else { return true }
        return SoloPermissionService.canEditTask(item, actorID: userID)
    }

    var canDeleteSelectedItem: Bool {
        guard let item = selectedItem, let userID = sessionStore.currentUser?.id else { return true }
        return SoloPermissionService.canDeleteTask(item, actorID: userID)
    }

    func canDeleteItem(_ itemID: UUID) -> Bool {
        guard let item = items.first(where: { $0.id == itemID }),
              let userID = sessionStore.currentUser?.id else { return true }
        return SoloPermissionService.canDeleteTask(item, actorID: userID)
    }

    func isAnimatingInsertion(for itemID: UUID) -> Bool {
        insertedItemIDs.contains(itemID)
    }

    func completeInsertionAnimation(for itemID: UUID) {
        insertedItemIDs.remove(itemID)
    }

    var hasUnsavedDetailChanges: Bool {
        guard let detailDraft else { return false }
        return detailDraft != savedDetailDraft
    }

    var quickTimePresetMinutes: [Int] {
        NotificationSettings.normalizedQuickTimePresetMinutes(
            sessionStore.currentUser?.preferences.quickTimePresetMinutes
            ?? NotificationSettings.defaultQuickTimePresetMinutes
        )
    }

    var isViewingToday: Bool {
        calendar.isDate(selectedDate, inSameDayAs: .now)
    }

    var currentUserAvatar: HomeAvatar {
        let currentUser = sessionStore.currentUser ?? MockDataFactory.makeCurrentUser()
        return HomeAvatar(
            id: currentUser.id,
            displayName: currentUser.displayName,
            avatarAsset: currentUser.avatarAsset,
            overrideImage: nil
        )
    }

    func selectDate(_ date: Date) {
        selectedDate = date
        isOverdueSheetPresented = false
    }

    func presentOverdueSheet() {
        guard showsOverdueCapsule else { return }
        isOverdueSheetPresented = true
    }

    func dismissOverdueSheet() {
        isOverdueSheetPresented = false
    }

    func loadIfNeeded() async {
        guard items.isEmpty else { return }
        await reload()
    }

    func performDeferredMaintenanceIfNeeded() async {
        guard hasCompletedDeferredMaintenance == false else { return }
        hasCompletedDeferredMaintenance = true

        await Task.yield()

        guard let spaceID = sessionStore.currentSpace?.id else { return }

        do {
            let didArchiveItems = try await archiveCompletedItemsIfNeeded(in: spaceID)
            if didArchiveItems {
                await reload()
            }
        } catch {
            return
        }
    }

    func reload(
        insertedItemIDs expectedInsertedItemIDs: Set<UUID> = [],
        reason: HomeReloadReason = .userInitiated
    ) async {
        guard let spaceID = sessionStore.currentSpace?.id else {
            items = []
            weeklyCompletedSheetItems = []
            weeklyCompletedEntryCount = 0
            insertedItemIDs = []
            reloadRevision += 1
            return
        }

        do {
            // 记录刷新前的 ID 集合，用于检测同步到达的新任务
            let previousIDs = Set(items.map(\.id))

            let completedRange = CompletedTaskRange.today.bounds(for: .now, calendar: calendar)
            let fetchedItems = try await itemRepository.fetchHomeItems(
                spaceID: spaceID,
                completedFrom: completedRange.lowerBound ?? .distantPast,
                completedBefore: completedRange.upperBound ?? .distantFuture
            )
            await refreshWeeklyCompletedEntryCount(spaceID: spaceID)
            let visibleItemIDs = Set(fetchedItems.map(\.id))
            let persistedInsertedIDs = insertedItemIDs.intersection(visibleItemIDs)
            let nextInsertedIDs = expectedInsertedItemIDs.intersection(visibleItemIDs)

            // 同步到达的新任务也标记为 inserted，触发入场动画
            let arrivedIDs = visibleItemIDs.subtracting(previousIDs).subtracting(expectedInsertedItemIDs)

            if reason.animatesItemChanges {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                    items = fetchedItems
                }
            } else {
                items = fetchedItems
            }
            insertedItemIDs = persistedInsertedIDs.union(nextInsertedIDs).union(arrivedIDs)
            reloadRevision += 1
            if overdueEntryCount == 0 {
                isOverdueSheetPresented = false
            }
        } catch {
            items = []
            weeklyCompletedSheetItems = []
            weeklyCompletedEntryCount = 0
            insertedItemIDs = []
            reloadRevision += 1
        }
    }

    func item(for itemID: UUID) -> Item? {
        items.first { $0.id == itemID }
    }

    func presentItemDetail(_ itemID: UUID) {
        guard let item = items.first(where: { $0.id == itemID }) else { return }
        selectedItemID = itemID
        let draft = TaskDraft(item: item)
        detailDraft = draft
        savedDetailDraft = draft
        detailDetent = .height(316)
    }

    func toggleInlineDetail(_ itemID: UUID) async {
        if selectedItemID == itemID {
            _ = await collapseInlineDetail()
            return
        }

        if selectedItemID != nil {
            _ = await collapseInlineDetail()
            return
        }

        presentItemDetail(itemID)
        markDetailForExpandedEditing()
    }

    @discardableResult
    func collapseInlineDetail() async -> Bool {
        await saveDetailDraftAndDismiss()
    }

    func dismissItemDetail() {
        detailSaveTask?.cancel()
        detailSaveTask = nil
        selectedItemID = nil
        detailDraft = nil
        savedDetailDraft = nil
        detailDetent = .height(316)
    }

    func markDetailForExpandedEditing() {
        detailDetent = .large
    }

    func updateDraftTitle(_ title: String) {
        detailDraft?.title = title
    }

    func updateDraftNotes(_ notes: String) {
        detailDraft?.notes = notes.isEmpty ? nil : notes
    }

    func setDraftDueDateEnabled(_ enabled: Bool) {
        guard var draft = detailDraft else { return }
        if enabled {
            if draft.hasExplicitTime {
                let current = draft.dueAt ?? defaultDueDate()
                draft.dueAt = calendar.date(
                    bySettingHour: calendar.component(.hour, from: current),
                    minute: calendar.component(.minute, from: current),
                    second: 0,
                    of: selectedDate
                )
            } else {
                draft.dueAt = dateOnlyDueDate(for: selectedDate)
            }
        } else {
            draft.dueAt = nil
            draft.hasExplicitTime = false
        }
        detailDraft = draft
    }

    func updateDraftDueDate(_ dueDate: Date) {
        guard var draft = detailDraft else { return }
        if draft.hasExplicitTime {
            let existing = draft.dueAt ?? defaultDueDate()
            draft.dueAt = merge(date: dueDate, timeSource: existing)
        } else {
            draft.dueAt = dateOnlyDueDate(for: dueDate)
        }
        detailDraft = draft
    }

    func updateDraftDueTime(_ dueTime: Date) {
        guard var draft = detailDraft else { return }
        let existing = draft.dueAt ?? defaultDueDate()
        draft.dueAt = merge(date: existing, timeSource: dueTime)
        draft.hasExplicitTime = true
        detailDraft = draft
    }

    func clearDraftDueTime() {
        guard var draft = detailDraft, let dueAt = draft.dueAt else { return }
        draft.dueAt = dateOnlyDueDate(for: dueAt)
        draft.hasExplicitTime = false
        draft.remindAt = nil
        detailDraft = draft
    }

    func setDraftReminderEnabled(_ enabled: Bool) {
        guard var draft = detailDraft else { return }
        draft.remindAt = enabled ? defaultReminderDate(for: draft) : nil
        detailDraft = draft
    }

    func updateDraftReminder(_ remindAt: Date) {
        detailDraft?.remindAt = remindAt
    }

    func updateDraftUrgent(_ isUrgent: Bool) {
        detailDraft?.isUrgent = isUrgent
    }

    func addDetailDraftSubtask(title: String) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false, var draft = detailDraft else { return }
        draft.subtasks.append(TaskSubtaskDraft(title: trimmed, sortOrder: draft.subtasks.count))
        detailDraft = draft
    }

    func toggleDetailDraftSubtask(_ subtaskID: UUID) {
        guard var draft = detailDraft,
              let index = draft.subtasks.firstIndex(where: { $0.id == subtaskID })
        else { return }
        draft.subtasks[index].isCompleted.toggle()
        detailDraft = draft
    }

    func updateDetailDraftSubtask(_ subtaskID: UUID, title: String) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false, var draft = detailDraft,
              let index = draft.subtasks.firstIndex(where: { $0.id == subtaskID })
        else { return }
        draft.subtasks[index].title = trimmed
        detailDraft = draft
    }

    func deleteDetailDraftSubtask(_ subtaskID: UUID) {
        guard var draft = detailDraft else { return }
        draft.subtasks.removeAll { $0.id == subtaskID }
        for index in draft.subtasks.indices {
            draft.subtasks[index].sortOrder = index
        }
        detailDraft = draft
    }

    func saveDetailDraft() async {
        detailSaveTask?.cancel()
        _ = await persistDetailDraft()
    }

    func saveInlineDetailDraft() async -> Bool {
        detailSaveTask?.cancel()
        guard hasUnsavedDetailChanges else { return true }
        return await persistDetailDraft()
    }

    @discardableResult
    func saveDetailDraftAndDismiss() async -> Bool {
        detailSaveTask?.cancel()

        if hasUnsavedDetailChanges {
            let didPersist = await persistDetailDraft()
            guard didPersist else { return false }
        }

        dismissItemDetail()
        return true
    }

    func saveCurrentDraftAsTemplate() async -> Bool {
        await saveCurrentDraftAsTemplateResult() != nil
    }

    func fetchTaskTemplates() async -> [TaskTemplate] {
        guard let spaceID = sessionStore.currentSpace?.id else { return [] }

        do {
            return try await taskTemplateRepository.fetchTaskTemplates(spaceID: spaceID)
        } catch {
            return []
        }
    }

    func createTask(from template: TaskTemplate) async -> Bool {
        guard
            let spaceID = sessionStore.currentSpace?.id,
            let actorID = sessionStore.currentUser?.id
        else {
            return false
        }

        do {
            let item = try await taskApplicationService.createTask(
                in: spaceID,
                actorID: actorID,
                draft: template.makeTaskDraft(for: selectedDate, calendar: calendar)
            )
            await reload(insertedItemIDs: [item.id])
            emitTaskMutation(spaceID: spaceID)
            return true
        } catch {
            return false
        }
    }

    func saveCurrentDraftAsTemplateResult() async -> TaskTemplateSaveResult? {
        guard
            let detailDraft,
            let spaceID = sessionStore.currentSpace?.id
        else {
            return nil
        }

        return await saveTaskTemplate(from: detailDraft, in: spaceID)
    }

    func saveItemAsTemplateResult(_ itemID: UUID) async -> TaskTemplateSaveResult? {
        guard let spaceID = sessionStore.currentSpace?.id else { return nil }

        let draft: TaskDraft?
        if selectedItemID == itemID {
            await saveDetailDraft()
            draft = detailDraft
        } else {
            draft = item(for: itemID).map(TaskDraft.init(item:))
        }

        guard let draft else { return nil }
        return await saveTaskTemplate(from: draft, in: spaceID)
    }

    private func saveTaskTemplate(from draft: TaskDraft, in spaceID: UUID) async -> TaskTemplateSaveResult? {
        let trimmedTitle = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedTitle.isEmpty == false else { return nil }

        let template = TaskTemplate(spaceID: spaceID, draft: draft, calendar: calendar)

        do {
            let existing = try await taskTemplateRepository.fetchTaskTemplates(spaceID: spaceID)
                .first { $0.isSemanticallyEquivalent(to: template) }

            if let existing {
                return TaskTemplateSaveResult(templateID: existing.id, isNewlyCreated: false)
            }

            let saved = try await taskTemplateRepository.saveTaskTemplate(template)
            return TaskTemplateSaveResult(templateID: saved.id, isNewlyCreated: true)
        } catch {
            return nil
        }
    }

    func deleteTaskTemplate(_ templateID: UUID) async -> Bool {
        do {
            try await taskTemplateRepository.deleteTaskTemplate(templateID: templateID)
            return true
        } catch {
            return false
        }
    }

    func setItemUrgent(_ itemID: UUID, isUrgent: Bool) async {
        guard
            let spaceID = sessionStore.currentSpace?.id,
            let actorID = sessionStore.currentUser?.id,
            let item = item(for: itemID)
        else { return }

        var draft = TaskDraft(item: item)
        draft.isUrgent = isUrgent

        do {
            let saved = try await taskApplicationService.updateTask(
                in: spaceID,
                taskID: itemID,
                actorID: actorID,
                draft: draft
            )
            withAnimation(.smooth(duration: 0.2)) {
                replaceItemPreservingOrder(saved)
            }
            emitTaskMutation(spaceID: spaceID)
        } catch {}
    }

    func completeItem(_ itemID: UUID, trigger: CompletionTrigger = .inlineControl) async {
        guard let spaceID = sessionStore.currentSpace?.id, let actorID = sessionStore.currentUser?.id else { return }
        let referenceDate = selectedDate
        let occurrenceKey = occurrenceKey(for: itemID, on: referenceDate)
        guard completingOccurrenceKeys.contains(occurrenceKey) == false else { return }
        completingOccurrenceKeys.insert(occurrenceKey)

        do {
            let saved = try await taskApplicationService.toggleTaskCompletion(
                in: spaceID,
                taskID: itemID,
                actorID: actorID,
                referenceDate: referenceDate
            )
            let didCompleteTimelineItem = isTimelineCompleted(saved, on: referenceDate)
            switch trigger {
            case .inlineControl:
                if didCompleteTimelineItem {
                    animatingCompletionOccurrenceKeys.insert(occurrenceKey)
                    try? await Task.sleep(for: .milliseconds(320))
                    withAnimation(.smooth(duration: 0.28, extraBounce: 0)) {
                        replaceItemPreservingOrder(saved)
                    }
                    try? await Task.sleep(for: .milliseconds(140))
                } else {
                    animatingReopeningOccurrenceKeys.insert(occurrenceKey)
                    try? await Task.sleep(for: .milliseconds(220))
                    var transaction = Transaction()
                    transaction.animation = nil
                    withTransaction(transaction) {
                        replaceItemPreservingOrder(saved)
                    }
                    try? await Task.sleep(for: .milliseconds(90))
                }
            case .expandedControl:
                if didCompleteTimelineItem {
                    animatingCompletionOccurrenceKeys.insert(occurrenceKey)
                    try? await Task.sleep(for: .milliseconds(680))
                    withAnimation(.smooth(duration: 0.28, extraBounce: 0)) {
                        replaceItemPreservingOrder(saved)
                    }
                } else {
                    animatingReopeningOccurrenceKeys.insert(occurrenceKey)
                    try? await Task.sleep(for: .milliseconds(580))
                    var transaction = Transaction()
                    transaction.animation = nil
                    withTransaction(transaction) {
                        replaceItemPreservingOrder(saved)
                    }
                }
            case .swipeAction:
                if didCompleteTimelineItem {
                    try? await Task.sleep(for: .milliseconds(220))
                    withAnimation(.smooth(duration: 0.26, extraBounce: 0)) {
                        replaceItemPreservingOrder(saved)
                    }
                } else {
                    try? await Task.sleep(for: .milliseconds(220))
                    withAnimation(.smooth(duration: 0.26, extraBounce: 0)) {
                        replaceItemPreservingOrder(saved)
                    }
                }
            }
            emitTaskMutation(spaceID: spaceID)
            await reconcileHomeItems(spaceID: spaceID)
        } catch {
            #if DEBUG
            print("[HomeViewModel] completeItem failed for itemID=\(itemID): \(error)")
            #endif
        }

        completingOccurrenceKeys.remove(occurrenceKey)
        animatingCompletionOccurrenceKeys.remove(occurrenceKey)
        animatingReopeningOccurrenceKeys.remove(occurrenceKey)
    }

    func isAnimatingCompletion(for itemID: UUID, on referenceDate: Date) -> Bool {
        animatingCompletionOccurrenceKeys.contains(occurrenceKey(for: itemID, on: referenceDate))
    }

    func isAnimatingReopening(for itemID: UUID, on referenceDate: Date) -> Bool {
        animatingReopeningOccurrenceKeys.contains(occurrenceKey(for: itemID, on: referenceDate))
    }

    func deleteSelectedItem() async {
        guard
            let itemID = selectedItemID,
            let spaceID = sessionStore.currentSpace?.id,
            let actorID = sessionStore.currentUser?.id
        else { return }

        do {
            try await taskApplicationService.deleteTask(
                in: spaceID,
                taskID: itemID,
                actorID: actorID
            )
            items.removeAll { $0.id == itemID }
            dismissItemDetail()
            emitTaskMutation(spaceID: spaceID)
        } catch {
            return
        }
    }

    func convertCurrentTaskToPeriodicTask() async {
        guard let draft = detailDraft else { return }
        let title = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
        await deleteSelectedItem()
        onConvertToPeriodicTask?(title)
    }

    func convertItemToPeriodicTask(_ itemID: UUID) async {
        let fallbackTitle = item(for: itemID)?.title.trimmingCharacters(in: .whitespacesAndNewlines)

        if selectedItemID == itemID {
            await saveDetailDraft()
        }

        let draftTitle = selectedItemID == itemID
            ? detailDraft?.title.trimmingCharacters(in: .whitespacesAndNewlines)
            : nil
        let title = [draftTitle, fallbackTitle].compactMap { $0 }.first { $0.isEmpty == false } ?? ""

        await deleteItem(itemID)
        guard title.isEmpty == false else { return }
        onConvertToPeriodicTask?(title)
    }

    func convertCurrentTaskToProject() async {
        guard let draft = detailDraft else { return }
        let title = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
        await deleteSelectedItem()
        onConvertToProject?(title)
    }

    func deleteItem(_ itemID: UUID) async {
        guard
            let spaceID = sessionStore.currentSpace?.id,
            let actorID = sessionStore.currentUser?.id
        else { return }

        do {
            try await taskApplicationService.deleteTask(
                in: spaceID,
                taskID: itemID,
                actorID: actorID
            )
            items.removeAll { $0.id == itemID }
            if selectedItemID == itemID {
                dismissItemDetail()
            }
            if overdueEntryCount == 0 {
                isOverdueSheetPresented = false
            }
            emitTaskMutation(spaceID: spaceID)
        } catch {
            return
        }
    }

    func presentWeeklyCompletedSheet() async {
        isWeeklyCompletedSheetPresented = true
        await loadWeeklyCompletedSheet()
    }

    func dismissWeeklyCompletedSheet() {
        isWeeklyCompletedSheetPresented = false
    }

    func loadWeeklyCompletedSheet() async {
        guard let spaceID = sessionStore.currentSpace?.id else {
            weeklyCompletedSheetItems = []
            weeklyCompletedEntryCount = 0
            didFailLoadingWeeklyCompletedSheet = false
            return
        }

        isWeeklyCompletedSheetLoading = true
        defer { isWeeklyCompletedSheetLoading = false }

        let range = CompletedTaskRange.workweekExcludingToday.bounds(for: .now, calendar: calendar)
        didFailLoadingWeeklyCompletedSheet = false

        do {
            weeklyCompletedSheetItems = try await itemRepository.fetchCompletedItems(
                spaceID: spaceID,
                searchText: nil,
                completedFrom: range.lowerBound,
                completedBefore: range.upperBound,
                before: nil,
                limit: 60
            )
        } catch {
            weeklyCompletedSheetItems = []
            didFailLoadingWeeklyCompletedSheet = true
        }

        do {
            weeklyCompletedEntryCount = try await itemRepository.completedItemCount(
                spaceID: spaceID,
                completedFrom: range.lowerBound,
                completedBefore: range.upperBound
            )
        } catch {
            weeklyCompletedEntryCount = weeklyCompletedSheetItems.count
        }
    }

    private func refreshWeeklyCompletedEntryCount(spaceID: UUID) async {
        let weeklyRange = CompletedTaskRange.workweekExcludingToday.bounds(for: .now, calendar: calendar)

        do {
            weeklyCompletedEntryCount = try await itemRepository.completedItemCount(
                spaceID: spaceID,
                completedFrom: weeklyRange.lowerBound,
                completedBefore: weeklyRange.upperBound
            )
        } catch {
            do {
                let fallbackItems = try await itemRepository.fetchCompletedItems(
                    spaceID: spaceID,
                    searchText: nil,
                    completedFrom: weeklyRange.lowerBound,
                    completedBefore: weeklyRange.upperBound,
                    before: nil,
                    limit: 60
                )
                weeklyCompletedEntryCount = fallbackItems.count
            } catch {
                weeklyCompletedEntryCount = 0
            }
        }
    }

    func snoozeItem(_ itemID: UUID) async {
        await snoozeItem(itemID, using: .tomorrow)
    }

    func rescheduleOverdueItemToToday(_ itemID: UUID) async {
        guard
            let spaceID = sessionStore.currentSpace?.id,
            let actorID = sessionStore.currentUser?.id,
            let item = item(for: itemID)
        else { return }

        do {
            let saved = try await taskApplicationService.rescheduleTask(
                in: spaceID,
                taskID: itemID,
                actorID: actorID,
                dueAt: returnToTodayDueDate(for: item),
                remindAt: nil
            )
            withAnimation(.spring(response: 0.34, dampingFraction: 0.86)) {
                replaceItemPreservingOrder(saved)
            }
            emitTaskMutation(spaceID: spaceID)
        } catch {}
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

    var completedEntryCount: Int {
        sortedItemsForTimeline.filter(isTimelineCompleted).count
    }

    var todayCompletedEntryCount: Int {
        completedEntryCount
    }

    var hasWeeklyCompletedEntries: Bool {
        weeklyCompletedEntryCount > 0
    }

    var overdueEntryCount: Int {
        return incompleteTimelineItems.filter { $0.isOverdue(on: selectedDate, calendar: calendar) }.count
    }

    var showsOverdueCapsule: Bool {
        isViewingToday && overdueEntryCount > 0
    }

    var overdueCapsuleTitle: String {
        return "有 \(overdueEntryCount) 件任务已逾期"
    }

    var overdueSummaryEntries: [HomeOverdueEntry] {
        guard isViewingToday else { return [] }
        return overdueTimelineItems.map(makeOverdueEntry)
    }

    var hasCompletedEntries: Bool {
        completedEntryCount > 0
    }

    var completedVisibilityButtonTitle: String {
        "本周已完成"
    }

    var activeTimelineEntries: [HomeTimelineEntry] {
        primaryIncompleteTimelineItems.map(makeTimelineEntry)
    }

    var activeTimelineSections: [HomeTimelineSection] {
        makeActiveTimelineSections(from: primaryIncompleteTimelineItems)
    }

    var completedTimelineEntries: [HomeTimelineEntry] {
        return completedTimelineItems.map(makeTimelineEntry)
    }

    var timelineEntries: [HomeTimelineEntry] {
        activeTimelineEntries + completedTimelineEntries
    }

    var hasAnyTimelineEntriesForSelectedDate: Bool {
        sortedItemsForTimeline.isEmpty == false
    }

    var timelineEntryIDs: [UUID] {
        timelineEntries.map(\.id)
    }

    func reorderTimelineEntries(_ entries: [HomeTimelineEntry], fromOffsets: IndexSet, toOffset: Int) async {
        var reorderedIDs = entries.map(\.itemID)
        reorderedIDs.move(fromOffsets: fromOffsets, toOffset: toOffset)

        do {
            let updatedItems = try await itemRepository.reorderItems(itemIDs: reorderedIDs)
            for item in updatedItems {
                replaceItemPreservingOrder(item)
            }
            onTodayDataChanged?()
        } catch {
            await reload()
        }
    }

    @discardableResult
    private func persistDetailDraft() async -> Bool {
        guard
            let spaceID = sessionStore.currentSpace?.id,
            let actorID = sessionStore.currentUser?.id,
            let selectedItemID,
            let detailDraft
        else { return false }

        let previousDueAt = savedDetailDraft?.dueAt

        do {
            let saved = try await taskApplicationService.updateTask(
                in: spaceID,
                taskID: selectedItemID,
                actorID: actorID,
                draft: detailDraft
            )
            let refreshedDraft = TaskDraft(item: saved)
            self.detailDraft = refreshedDraft
            self.savedDetailDraft = refreshedDraft
            replaceItem(saved)
            emitTaskMutation(spaceID: spaceID)

            // dueAt 跨天变化时，原日期视图需要重新拉取以移除/纳入该任务
            if dueDateScopeChanged(from: previousDueAt, to: saved.dueAt) {
                await reload()
            }
            return true
        } catch {
            return false
        }
    }

    private func dueDateScopeChanged(from previous: Date?, to current: Date?) -> Bool {
        switch (previous, current) {
        case (nil, nil):
            return false
        case (nil, _), (_, nil):
            return true
        case let (.some(p), .some(c)):
            return calendar.isDate(p, inSameDayAs: c) == false
        }
    }

    private func replaceItem(_ item: Item) {
        if let index = items.firstIndex(where: { $0.id == item.id }) {
            items[index] = item
        } else {
            items.append(item)
        }
    }

    private func replaceItemPreservingOrder(_ item: Item) {
        if let index = items.firstIndex(where: { $0.id == item.id }) {
            items[index] = item
        } else {
            items.append(item)
        }
    }

    private func reconcileHomeItems(spaceID: UUID) async {
        let completedRange = CompletedTaskRange.today.bounds(for: .now, calendar: calendar)
        guard let fetchedItems = try? await itemRepository.fetchHomeItems(
            spaceID: spaceID,
            completedFrom: completedRange.lowerBound ?? .distantPast,
            completedBefore: completedRange.upperBound ?? .distantFuture
        ) else { return }

        var transaction = Transaction()
        transaction.animation = nil
        withTransaction(transaction) {
            items = fetchedItems
        }
        reloadRevision += 1
    }

    private func scope(for date: Date) -> TaskScope {
        .all
    }

    private func defaultDueDate() -> Date {
        calendar.date(bySettingHour: 18, minute: 0, second: 0, of: selectedDate) ?? selectedDate
    }

    private func returnToTodayDueDate(for item: Item) -> Date {
        guard item.hasExplicitTime, let dueAt = item.dueAt else {
            return dateOnlyDueDate(for: selectedDate)
        }

        let candidate = merge(date: selectedDate, timeSource: dueAt)
        guard candidate <= Date.now else { return candidate }

        let selectedDayStart = calendar.startOfDay(for: selectedDate)
        let nextHour = calendar.dateInterval(of: .hour, for: Date.now)?.end
            ?? Date.now.addingTimeInterval(3_600)
        if calendar.isDate(nextHour, inSameDayAs: selectedDate) {
            return nextHour
        }

        let selectedDayEnd = calendar
            .date(byAdding: .day, value: 1, to: selectedDayStart)
            .flatMap { calendar.date(byAdding: .second, value: -1, to: $0) }
        if let selectedDayEnd, selectedDayEnd > Date.now {
            return selectedDayEnd
        }

        return calendar.date(byAdding: .day, value: 1, to: selectedDayStart) ?? defaultDueDate()
    }

    private func dateOnlyDueDate(for date: Date) -> Date {
        calendar.startOfDay(for: date)
    }

    private func defaultReminderDate(for draft: TaskDraft? = nil) -> Date {
        let currentDraft = draft ?? detailDraft
        let reminderTarget: Date
        if let dueAt = currentDraft?.dueAt {
            reminderTarget = reminderTargetDate(for: dueAt, hasExplicitTime: currentDraft?.hasExplicitTime ?? false)
        } else {
            reminderTarget = defaultDueDate()
        }
        return calendar.date(byAdding: .minute, value: -30, to: reminderTarget) ?? reminderTarget
    }

    private func merge(date: Date, timeSource: Date) -> Date {
        let dayComponents = calendar.dateComponents([.year, .month, .day], from: date)
        let timeComponents = calendar.dateComponents([.hour, .minute], from: timeSource)
        return calendar.date(from: DateComponents(
            year: dayComponents.year,
            month: dayComponents.month,
            day: dayComponents.day,
            hour: timeComponents.hour,
            minute: timeComponents.minute
        )) ?? date
    }

    private func reminderTargetDate(for dueAt: Date, hasExplicitTime: Bool) -> Date {
        guard hasExplicitTime == false else { return dueAt }
        return calendar.date(bySettingHour: 9, minute: 0, second: 0, of: dueAt) ?? dueAt
    }

    private func timeText(for item: Item) -> String {
        HomeTaskDateLabel.text(for: item, calendar: calendar)
    }

    private func timelineTimeText(for item: Item, isCompleted: Bool) -> String {
        guard isCompleted == false,
              item.hasExplicitTime,
              let dueAt = item.occurrenceDueDate(on: selectedDate, calendar: calendar) ?? item.dueAt
        else { return "" }
        return hourMinuteText(for: dueAt)
    }

    private func timelineReminderText(for item: Item, isCompleted: Bool) -> String {
        guard isCompleted == false,
              item.remindAt != nil
        else { return "" }
        return "提醒"
    }

    private func completionTimestamp(for item: Item) -> Date? {
        item.completionDate(on: selectedDate, calendar: calendar) ?? item.completedAt
    }

    private var visibleTimelineItems: [Item] {
        sortedItemsForTimeline.filter(shouldDisplayInCurrentTimeline)
    }

    private var incompleteTimelineItems: [Item] {
        visibleTimelineItems.filter { !isCompleted($0, on: selectedDate) }
    }

    private var overdueTimelineItems: [Item] {
        guard isViewingToday else { return [] }
        return incompleteTimelineItems.filter { $0.isOverdue(on: selectedDate, calendar: calendar) }
    }

    private var primaryIncompleteTimelineItems: [Item] {
        guard showsOverdueCapsule else { return incompleteTimelineItems }
        return incompleteTimelineItems.filter { $0.isOverdue(on: selectedDate, calendar: calendar) == false }
    }

    private var completedTimelineItems: [Item] {
        return Array(visibleTimelineItems
            .filter(isTimelineCompleted)
            .sorted { lhs, rhs in
                let lhsCompletedAt = completionTimestamp(for: lhs) ?? .distantPast
                let rhsCompletedAt = completionTimestamp(for: rhs) ?? .distantPast
                if lhsCompletedAt != rhsCompletedAt {
                    return lhsCompletedAt > rhsCompletedAt
                }
                if lhs.updatedAt != rhs.updatedAt {
                    return lhs.updatedAt > rhs.updatedAt
                }
                return lhs.id.uuidString < rhs.id.uuidString
            }
            .prefix(6))
    }

    private struct ActiveTimelineSectionKey: Hashable {
        let dayStart: Date
        let isUnscheduled: Bool
    }

    private func makeActiveTimelineSections(from items: [Item]) -> [HomeTimelineSection] {
        let grouped = Dictionary(grouping: items) { item in
            activeTimelineSectionKey(for: item)
        }

        let keys = grouped.keys.sorted { lhs, rhs in
            if lhs.isUnscheduled != rhs.isUnscheduled {
                return lhs.isUnscheduled == false
            }
            if lhs.dayStart != rhs.dayStart {
                return lhs.dayStart < rhs.dayStart
            }
            return lhs.isUnscheduled.description < rhs.isUnscheduled.description
        }

        return keys.compactMap { key in
            guard let sectionItems = grouped[key], sectionItems.isEmpty == false else { return nil }
            let entries = sectionItems
                .sorted(by: timelineItemSortPrecedes)
                .map(makeTimelineEntry)

            return HomeTimelineSection(
                id: "\(key.isUnscheduled ? "created" : "scheduled")-\(Int(key.dayStart.timeIntervalSince1970))",
                dayStart: key.dayStart,
                title: timelineSectionTitle(for: key.dayStart),
                subtitle: timelineSectionSubtitle(
                    for: key.dayStart,
                    isUnscheduled: key.isUnscheduled,
                    count: entries.count
                ),
                isUnscheduled: key.isUnscheduled,
                entries: entries
            )
        }
    }

    private func activeTimelineSectionKey(for item: Item) -> ActiveTimelineSectionKey {
        if let scheduledDate = item.occurrenceDueDate(on: selectedDate, calendar: calendar) ?? item.dueAt {
            return ActiveTimelineSectionKey(
                dayStart: calendar.startOfDay(for: scheduledDate),
                isUnscheduled: false
            )
        }

        return ActiveTimelineSectionKey(
            dayStart: calendar.startOfDay(for: item.createdAt),
            isUnscheduled: true
        )
    }

    private func timelineSectionTitle(for dayStart: Date) -> String {
        if calendar.isDateInToday(dayStart) {
            return "今天"
        }
        if calendar.isDateInTomorrow(dayStart) {
            return "明天"
        }
        if calendar.isDateInYesterday(dayStart) {
            return "昨天"
        }

        let currentYear = calendar.component(.year, from: .now)
        let sectionYear = calendar.component(.year, from: dayStart)
        if currentYear != sectionYear {
            return dayStart.formatted(.dateTime.locale(Locale(identifier: "zh_CN")).year().month().day())
        }
        return dayStart.formatted(.dateTime.locale(Locale(identifier: "zh_CN")).month().day())
    }

    private func timelineSectionSubtitle(for dayStart: Date, isUnscheduled: Bool, count: Int) -> String {
        let weekday = weekdayLabel(for: dayStart)
        let countText = "\(count)项"
        guard isUnscheduled else {
            return "\(weekday)·\(countText)"
        }
        return "创建·\(weekday)·\(countText)"
    }

    private func timelineItemSortPrecedes(_ lhs: Item, _ rhs: Item) -> Bool {
        if lhs.isUrgent != rhs.isUrgent {
            return lhs.isUrgent && rhs.isUrgent == false
        }

        if lhs.isUrgent, rhs.isUrgent {
            if lhs.createdAt != rhs.createdAt {
                return lhs.createdAt < rhs.createdAt
            }
            return lhs.id.uuidString < rhs.id.uuidString
        }

        let lhsDueAt = timelineSortDate(for: lhs)
        let rhsDueAt = timelineSortDate(for: rhs)
        if lhsDueAt != rhsDueAt {
            return lhsDueAt < rhsDueAt
        }

        if lhs.sortOrder != rhs.sortOrder {
            return lhs.sortOrder < rhs.sortOrder
        }

        if lhs.createdAt != rhs.createdAt {
            return lhs.createdAt < rhs.createdAt
        }

        return lhs.id.uuidString < rhs.id.uuidString
    }

    private var sortedItemsForTimeline: [Item] {
        items.sorted { lhs, rhs in
            let lhsCompleted = isCompleted(lhs, on: selectedDate)
            let rhsCompleted = isCompleted(rhs, on: selectedDate)

            if lhsCompleted != rhsCompleted {
                return lhsCompleted == false
            }

            if lhsCompleted {
                let lhsCompletedAt = lhs.completionDate(on: selectedDate, calendar: calendar) ?? .distantPast
                let rhsCompletedAt = rhs.completionDate(on: selectedDate, calendar: calendar) ?? .distantPast
                if lhsCompletedAt != rhsCompletedAt {
                    return lhsCompletedAt < rhsCompletedAt
                }
            } else {
                let lhsDueAt = timelineSortDate(for: lhs)
                let rhsDueAt = timelineSortDate(for: rhs)
                if lhsDueAt != rhsDueAt {
                    return lhsDueAt < rhsDueAt
                }
            }

            if lhs.sortOrder != rhs.sortOrder {
                return lhs.sortOrder < rhs.sortOrder
            }

            if lhs.createdAt != rhs.createdAt {
                return lhs.createdAt < rhs.createdAt
            }

            return lhs.id.uuidString < rhs.id.uuidString
        }
    }

    private func shouldDisplayInCurrentTimeline(_ item: Item) -> Bool {
        return true
    }

    private func timingUrgency(for item: Item, isCompleted: Bool) -> HomeTimelineTimingUrgency {
        guard isCompleted == false else { return .normal }
        guard sessionStore.currentUser?.preferences.taskReminderEnabled ?? true else {
            return .normal
        }
        let dueAt = item.occurrenceDueDate(on: selectedDate, calendar: calendar) ?? item.dueAt
        guard let dueAt else { return .normal }
        guard item.hasExplicitTime else { return .normal }
        let selectedDayStart = calendar.startOfDay(for: selectedDate)
        let todayStart = calendar.startOfDay(for: .now)
        let referenceMoment: Date
        if selectedDayStart < todayStart {
            referenceMoment = calendar.date(byAdding: .day, value: 1, to: selectedDayStart) ?? selectedDate
        } else if calendar.isDate(selectedDate, inSameDayAs: .now) {
            referenceMoment = Date.now
        } else {
            referenceMoment = selectedDayStart
        }
        if dueAt <= referenceMoment {
            return .overdue
        }

        let imminentThreshold = TimeInterval(
            (sessionStore.currentUser?.preferences.taskUrgencyWindowMinutes ?? 30) * 60
        )
        if dueAt.timeIntervalSince(referenceMoment) <= imminentThreshold {
            return .imminent
        }

        return .normal
    }

    private func statusText(for item: Item, isCompleted: Bool) -> String {
        guard isCompleted == false else { return ItemStatus.completed.title }
        guard item.repeatRule != nil else {
            guard item.isOverdue(on: selectedDate, calendar: calendar) else {
                return ItemStatus.inProgress.title
            }

            if calendar.isDate(selectedDate, inSameDayAs: .now) {
                return item.hasExplicitTime ? "已超时" : "已逾期"
            }

            return "已逾期"
        }

        if item.isOverdue(on: selectedDate, calendar: calendar) {
            if calendar.isDate(selectedDate, inSameDayAs: .now) {
                return item.hasExplicitTime ? "已超时" : "已逾期"
            }
            return "已逾期"
        }

        return "待完成"
    }

    private func makeTimelineEntry(for item: Item) -> HomeTimelineEntry {
        let isCompleted = isTimelineCompleted(item)
        let sortedSubtasks = item.subtasks.sorted { $0.sortOrder < $1.sortOrder }
        return HomeTimelineEntry(
            id: item.id,
            presentationID: timelinePresentationID(for: item, isCompleted: isCompleted),
            title: item.title,
            notes: item.notes,
            timeText: timelineTimeText(for: item, isCompleted: isCompleted),
            reminderText: timelineReminderText(for: item, isCompleted: isCompleted),
            statusText: statusText(for: item, isCompleted: isCompleted),
            isUrgent: item.isUrgent,
            isMuted: isCompleted,
            isCompleted: isCompleted,
            timingUrgency: timingUrgency(for: item, isCompleted: isCompleted),
            relationText: nil,
            primaryAvatar: nil,
            secondaryAvatar: nil,
            lastActionAt: item.lastActionAt,
            subtasks: sortedSubtasks,
            subtaskCompletedCount: sortedSubtasks.filter(\.isCompleted).count
        )
    }

    private func timelinePresentationID(for item: Item, isCompleted: Bool) -> String {
        let state = isCompleted ? "completed" : "active"
        let sectionKey = activeTimelineSectionKey(for: item)
        let sectionKind = sectionKey.isUnscheduled ? "created" : "scheduled"
        let sectionTimestamp = Int(sectionKey.dayStart.timeIntervalSince1970)
        return "\(state)-\(sectionKind)-\(sectionTimestamp)-\(item.id.uuidString)"
    }

    private func makeOverdueEntry(for item: Item) -> HomeOverdueEntry {
        HomeOverdueEntry(
            id: item.id,
            title: item.title,
            detailText: overdueDetailText(for: item),
            timeText: timeText(for: item)
        )
    }

    private func timelineSortDate(for item: Item) -> Date {
        item.occurrenceDueDate(on: selectedDate, calendar: calendar) ?? item.dueAt ?? .distantFuture
    }

    private func hourMinuteText(for date: Date) -> String {
        date.formatted(
            .dateTime
                .locale(Locale(identifier: "zh_CN"))
                .hour(.twoDigits(amPM: .omitted))
                .minute(.twoDigits)
        )
    }

    private func overdueDetailText(for item: Item) -> String {
        guard let dueAt = item.dueAt else {
            return item.hasExplicitTime ? "已超时" : "已逾期"
        }

        let dueDay = calendar.startOfDay(for: dueAt)
        let todayStart = calendar.startOfDay(for: selectedDate)
        let overdueText = item.hasExplicitTime ? "已超时" : "已逾期"
        let dayOffset = calendar.dateComponents([.day], from: dueDay, to: todayStart).day ?? 0

        let dayText: String
        switch dayOffset {
        case 1:
            dayText = "昨天"
        case 2:
            dayText = "前天"
        default:
            dayText = dueAt.formatted(
                .dateTime
                    .locale(Locale(identifier: "zh_CN"))
                    .month(.defaultDigits)
                    .day()
            )
        }

        return "\(dayText) · \(overdueText)"
    }

    private func avatarMetadata(id: UUID, displayName: String, user: User?) -> HomeAvatar {
        HomeAvatar(
            id: id,
            displayName: displayName,
            avatarAsset: user?.avatarAsset ?? .system("person.crop.circle.fill"),
            overrideImage: nil
        )
    }

    private func removeItem(withID itemID: UUID) {
        items.removeAll { $0.id == itemID }
    }

    private func occurrenceKey(for itemID: UUID, on referenceDate: Date) -> HomeItemOccurrenceKey {
        HomeItemOccurrenceKey(
            itemID: itemID,
            dayStart: calendar.startOfDay(for: referenceDate)
        )
    }

    private func isCompleted(_ item: Item, on referenceDate: Date) -> Bool {
        item.isCompleted(on: referenceDate, calendar: calendar) || item.status == .completed
    }

    private func isTimelineCompleted(_ item: Item, on referenceDate: Date) -> Bool {
        isCompleted(item, on: referenceDate) || item.completedAt != nil
    }

    private func isTimelineCompleted(_ item: Item) -> Bool {
        isTimelineCompleted(item, on: selectedDate)
    }

    private func archiveCompletedItemsIfNeeded(in spaceID: UUID) async throws -> Bool {
        guard sessionStore.currentUser?.preferences.completedTaskAutoArchiveEnabled ?? true else {
            return false
        }

        let days = NotificationSettings.normalizedCompletedTaskAutoArchiveDays(
            sessionStore.currentUser?.preferences.completedTaskAutoArchiveDays
            ?? NotificationSettings.defaultCompletedTaskAutoArchiveDays
        )
        return try await itemRepository.archiveCompletedItemsIfNeeded(
            spaceID: spaceID,
            referenceDate: .now,
            autoArchiveDays: days
        )
    }

    private func snoozeItem(_ itemID: UUID, using option: TaskSnoozeOption) async {
        guard
            let spaceID = sessionStore.currentSpace?.id,
            let actorID = sessionStore.currentUser?.id
        else { return }
        guard isPerformingSnooze == false else { return }

        isPerformingSnooze = true
        defer { isPerformingSnooze = false }

        do {
            let saved = try await taskApplicationService.snoozeTask(
                in: spaceID,
                taskID: itemID,
                actorID: actorID,
                option: option
            )
            withAnimation(.spring(response: 0.34, dampingFraction: 0.86)) {
                let shouldRemainVisible = shouldDisplayInCurrentTimeline(saved)
                if shouldRemainVisible {
                    replaceItemPreservingOrder(saved)
                } else {
                    removeItem(withID: saved.id)
                }
            }
            emitTaskMutation(spaceID: spaceID)
        } catch {}
    }

    private func emitTaskMutation(spaceID: UUID) {
        onTaskMutated?(spaceID)
        onTodayDataChanged?()
    }
}

extension HomeViewModel {
    enum CompletionTrigger {
        case inlineControl
        case expandedControl
        case swipeAction
    }
}
