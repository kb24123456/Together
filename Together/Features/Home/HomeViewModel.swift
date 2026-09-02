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
    let createdAt: Date
    let subtasks: [TaskSubtask]
    let subtaskCompletedCount: Int

    var itemID: UUID { id }
}

struct HomeTimelineSection: Identifiable, Hashable {
    let id: String
    let dayStart: Date
    let title: String
    let context: String
    let count: Int
    let isUnscheduled: Bool
    let entries: [HomeTimelineEntry]

    var subtitle: String {
        "\(context)·\(count)项"
    }
}

struct HomeOverdueEntry: Identifiable, Hashable {
    let id: UUID
    let title: String
    let detailText: String
    let timeText: String
    let createdAt: Date
}

struct HomeOverdueBatchRescheduleResult: Equatable, Sendable {
    let succeededIDs: [UUID]
    let failedIDs: [UUID]

    var isCompleteSuccess: Bool {
        failedIDs.isEmpty
    }
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

enum HomeTaskCreationPhase: Equatable, Sendable {
    case editing
    case committing
    case committed
}

struct HomeTaskCreationSession: Equatable, Sendable, Identifiable {
    let id: UUID
    var draft: TaskDraft
    var phase: HomeTaskCreationPhase
    var errorMessage: String?
}

private struct HomeItemOccurrenceKey: Hashable {
    let itemID: UUID
    let dayStart: Date
}

@MainActor
@Observable
final class HomeViewModel {
    private let calendar = Calendar.current
    private let sessionStore: SessionStore
    private let taskApplicationService: TaskApplicationServiceProtocol
    private let itemRepository: ItemRepositoryProtocol

    /// 任务操作完成后的回调，参数为 spaceID，用于刷新外部依赖。
    var onTaskMutated: ((UUID) -> Void)?
    var onTaskFollowChanged: ((UUID) -> Void)?
    var onTodayDataChanged: (@MainActor @Sendable () -> Void)?
    /// 将当前任务转为定期任务时的回调（传递任务标题）
    var onConvertToPeriodicTask: ((String) -> Void)?
    /// 将当前任务转为项目时的回调（传递任务标题）
    var onConvertToProject: ((String) -> Void)?

    private var detailSaveTask: Task<Void, Never>?
    private var savedDetailDraft: TaskDraft?
    private var hasCompletedDeferredMaintenance = false
    private var insertedItemIDs: Set<UUID> = []
    var selectedDate: Date = Date()
    var items: [Item] = []
    var loadState: LoadableState = .idle
    var operationErrorMessage: String?
    var externalRouteErrorMessage: String?
    var failedExternalRouteTaskID: UUID?
    var onRetryExternalTaskRoute: ((UUID) -> Void)?
    private(set) var reloadRevision = 0
    var selectedItemID: UUID?
    var detailDraft: TaskDraft?
    var taskCreationSession: HomeTaskCreationSession?
    var detailDetent: PresentationDetent = .height(316)
    private var completingOccurrenceKeys: Set<HomeItemOccurrenceKey> = []
    private var animatingCompletionOccurrenceKeys: Set<HomeItemOccurrenceKey> = []
    private var animatingReopeningOccurrenceKeys: Set<HomeItemOccurrenceKey> = []
    private var taskFollowMutationIDs: Set<UUID> = []
    var isWeeklyCompletedSheetPresented = false
    var isWeeklyCompletedSheetLoading = false
    var didFailLoadingWeeklyCompletedSheet = false
    var weeklyCompletedSheetItems: [Item] = []
    var weeklyCompletedEntryCount = 0
    var isPerformingSnooze = false
    var isOverdueSheetPresented = false

    init(
        sessionStore: SessionStore,
        taskApplicationService: TaskApplicationServiceProtocol,
        itemRepository: ItemRepositoryProtocol
    ) {
        self.sessionStore = sessionStore
        self.taskApplicationService = taskApplicationService
        self.itemRepository = itemRepository
    }

    var currentUserID: UUID? {
        sessionStore.currentUser?.id
    }

    func beginTaskCreation() {
        guard taskCreationSession == nil, selectedItemID == nil else { return }
        let day = calendar.startOfDay(for: .now)
        selectedDate = day
        let draft = TaskDraft(title: "", dueAt: day)
        taskCreationSession = HomeTaskCreationSession(
            id: UUID(),
            draft: draft,
            phase: .editing,
            errorMessage: nil
        )
    }

    func updateTaskCreationDraft(_ update: (inout TaskDraft) -> Void) {
        guard var session = taskCreationSession, session.phase == .editing else { return }
        update(&session.draft)
        session.errorMessage = nil
        taskCreationSession = session
    }

    func updateTaskCreationSchedule(
        date: Date,
        time: Date?,
        reminderOffset: TimeInterval?
    ) {
        updateTaskCreationDraft { draft in
            applySchedule(
                date: date,
                time: time,
                reminderOffset: reminderOffset,
                to: &draft
            )
        }
    }

    func discardTaskCreation() {
        guard taskCreationSession?.phase == .editing else { return }
        taskCreationSession = nil
    }

    func commitTaskCreation() async -> TaskCreationPersistenceResult {
        guard
            var session = taskCreationSession,
            session.phase == .editing,
            let spaceID = sessionStore.currentSpace?.id,
            let actorID = sessionStore.currentUser?.id
        else { return .failed(message: "当前无法创建任务。") }

        let title = session.draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard title.isEmpty == false else { return .failed(message: "请输入任务标题。") }
        session.draft.title = title
        session.phase = .committing
        session.errorMessage = nil
        taskCreationSession = session

        do {
            let created = try await taskApplicationService.createTask(
                id: session.id,
                in: spaceID,
                actorID: actorID,
                draft: session.draft
            )
            replaceItem(created)
            emitTaskMutation(spaceID: spaceID)
            if created.isFollowed {
                onTaskFollowChanged?(spaceID)
            }
            session.phase = .committed
            taskCreationSession = session
            return .saved(created.id)
        } catch {
            session.phase = .editing
            session.errorMessage = "保存失败，请重试。"
            taskCreationSession = session
            return .failed(message: session.errorMessage ?? "保存失败，请重试。")
        }
    }

    func finalizeCommittedTaskCreation() {
        guard taskCreationSession?.phase == .committed else { return }
        taskCreationSession = nil
    }

    func saveDetailForMorph() async -> TaskMorphPersistenceResult {
        detailSaveTask?.cancel()
        if hasUnsavedDetailChanges, await persistDetailDraft() == false {
            return .failed(message: operationErrorMessage ?? "任务保存失败，请重试。")
        }
        guard let selectedItemID,
              let descriptor = morphPlacement(for: selectedItemID)
        else { return .failed(message: "暂时无法定位任务。") }
        return .saved(descriptor)
    }

    func completeDetailForMorph() async -> TaskMorphPersistenceResult {
        guard let selectedItemID else { return .failed(message: "暂时无法定位任务。") }
        if hasUnsavedDetailChanges, await persistDetailDraft() == false {
            return .failed(message: operationErrorMessage ?? "任务保存失败，请重试。")
        }
        await completeItem(selectedItemID, trigger: .taskExpansion)
        guard let descriptor = morphPlacement(for: selectedItemID) else {
            return .failed(message: operationErrorMessage ?? "任务状态更新失败，请重试。")
        }
        return .saved(descriptor)
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
        taskCreationSession?.draft ?? detailDraft
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

    func revealCommittedTaskCreation(_ itemID: UUID) {
        guard taskCreationSession == nil, item(for: itemID) != nil else { return }
        relocateMorphItem(itemID)
        insertedItemIDs.insert(itemID)
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
        guard loadState == .idle else { return }
        StartupTrace.mark("HomeViewModel.loadIfNeeded.reload.begin")
        await reload()
        StartupTrace.mark("HomeViewModel.loadIfNeeded.reload.end")
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
            loadState = .loaded
            reloadRevision += 1
            return
        }

        loadState = .loading
        StartupTrace.mark("HomeViewModel.reload.fetch.begin reason=\(reason)")
        do {
            // 记录刷新前的 ID 集合，用于检测同步到达的新任务
            let previousIDs = Set(items.map(\.id))

            let completedRange = CompletedTaskRange.today.bounds(for: .now, calendar: calendar)
            let fetchedItems = try await itemRepository.fetchHomeItems(
                spaceID: spaceID,
                completedFrom: completedRange.lowerBound ?? .distantPast,
                completedBefore: completedRange.upperBound ?? .distantFuture
            )
            StartupTrace.mark("HomeViewModel.reload.fetch.end reason=\(reason) count=\(fetchedItems.count)")
            await refreshWeeklyCompletedEntryCount(spaceID: spaceID)
            StartupTrace.mark("HomeViewModel.reload.weeklyCount.end reason=\(reason)")
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
            loadState = .loaded
            reloadRevision += 1
            if overdueEntryCount == 0 {
                isOverdueSheetPresented = false
            }
            StartupTrace.mark("HomeViewModel.reload.end reason=\(reason)")
        } catch {
            StartupTrace.mark("HomeViewModel.reload.failed reason=\(reason) error=\(error.localizedDescription)")
            loadState = .failed("任务加载失败，请重试。")
            reloadRevision += 1
        }
    }

    func dismissOperationError() {
        operationErrorMessage = nil
    }

    func presentOperationStatus(_ message: String) {
        operationErrorMessage = message
    }

    func presentExternalRouteFailure(taskID: UUID) {
        failedExternalRouteTaskID = taskID
        externalRouteErrorMessage = "未找到该任务，可能已删除或已归档。你可以重试刷新。"
    }

    func clearExternalRouteFailure() {
        failedExternalRouteTaskID = nil
        externalRouteErrorMessage = nil
    }

    func retryExternalTaskRoute() {
        guard let failedExternalRouteTaskID else { return }
        onRetryExternalTaskRoute?(failedExternalRouteTaskID)
    }

    private func presentOperationError(_ message: String) {
        operationErrorMessage = message
    }

    func item(for itemID: UUID) -> Item? {
        items.first { $0.id == itemID }
    }

    func presentItemDetail(_ itemID: UUID) {
        guard let item = items.first(where: { $0.id == itemID }),
              isTimelineCompleted(item) == false
        else { return }
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
        mutateInlineDraft { $0.title = title }
    }

    func updateDraftNotes(_ notes: String) {
        mutateInlineDraft { $0.notes = notes.isEmpty ? nil : notes }
    }

    func updateDraftDueDate(_ dueDate: Date) {
        guard var draft = inlineDetailDraft else { return }
        if draft.hasExplicitTime {
            let existing = draft.dueAt ?? defaultDueDate()
            draft.dueAt = merge(date: dueDate, timeSource: existing)
        } else {
            draft.dueAt = dateOnlyDueDate(for: dueDate)
        }
        replaceInlineDraft(draft)
    }

    func updateDraftDueTime(_ dueTime: Date) {
        guard var draft = inlineDetailDraft else { return }
        let existing = draft.dueAt ?? defaultDueDate()
        draft.dueAt = merge(date: existing, timeSource: dueTime)
        draft.hasExplicitTime = true
        replaceInlineDraft(draft)
    }

    func updateDraftSchedule(date: Date, time: Date?) {
        guard var draft = inlineDetailDraft else { return }

        let reminderLeadTime: TimeInterval? = {
            guard
                draft.hasExplicitTime,
                let currentDueAt = draft.dueAt,
                let remindAt = draft.remindAt
            else {
                return nil
            }
            return currentDueAt.timeIntervalSince(remindAt)
        }()

        let updatedDueAt: Date
        if let time {
            updatedDueAt = merge(date: date, timeSource: time)
            draft.hasExplicitTime = true
        } else {
            updatedDueAt = dateOnlyDueDate(for: date)
            draft.hasExplicitTime = false
        }

        draft.dueAt = updatedDueAt
        if let reminderLeadTime, time != nil {
            draft.remindAt = updatedDueAt.addingTimeInterval(-reminderLeadTime)
        } else if time == nil {
            draft.remindAt = nil
        }
        replaceInlineDraft(draft)
    }

    func updateDraftSchedule(
        date: Date,
        time: Date?,
        reminderOffset: TimeInterval?
    ) {
        guard var draft = inlineDetailDraft else { return }
        applySchedule(
            date: date,
            time: time,
            reminderOffset: reminderOffset,
            to: &draft
        )
        replaceInlineDraft(draft)
    }

    func clearDraftDueTime() {
        guard var draft = inlineDetailDraft, let dueAt = draft.dueAt else { return }
        draft.dueAt = dateOnlyDueDate(for: dueAt)
        draft.hasExplicitTime = false
        draft.remindAt = nil
        replaceInlineDraft(draft)
    }

    func updateDraftReminder(_ remindAt: Date) {
        mutateInlineDraft { $0.remindAt = remindAt }
    }

    func updateDraftUrgent(_ isUrgent: Bool) {
        mutateInlineDraft { $0.isUrgent = isUrgent }
    }

    func isUpdatingTaskFollow(_ itemID: UUID) -> Bool {
        taskFollowMutationIDs.contains(itemID)
    }

    func toggleTaskFollow(_ itemID: UUID) async {
        guard
            taskFollowMutationIDs.contains(itemID) == false,
            let spaceID = sessionStore.currentSpace?.id,
            let actorID = sessionStore.currentUser?.id,
            let original = item(for: itemID),
            original.repeatRule == nil,
            original.status != .completed,
            original.completedAt == nil
        else { return }

        let nextIsFollowed = original.isFollowed == false
        var optimistic = original
        optimistic.isFollowed = nextIsFollowed
        optimistic.followedAt = nextIsFollowed ? .now : nil
        taskFollowMutationIDs.insert(itemID)
        replaceItemPreservingOrder(optimistic)

        defer { taskFollowMutationIDs.remove(itemID) }
        do {
            let saved = try await taskApplicationService.setTaskFollowed(
                in: spaceID,
                taskID: itemID,
                actorID: actorID,
                isFollowed: nextIsFollowed
            )
            replaceItemPreservingOrder(saved)
            emitTaskMutation(spaceID: spaceID)
            onTaskFollowChanged?(spaceID)
        } catch {
            replaceItemPreservingOrder(original)
            presentOperationError("关注状态保存失败，请重试。")
        }
    }

    func addDetailDraftSubtask(title: String) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false, var draft = inlineDetailDraft else { return }
        draft.subtasks.append(TaskSubtaskDraft(title: trimmed, sortOrder: draft.subtasks.count))
        replaceInlineDraft(draft)
    }

    func toggleDetailDraftSubtask(_ subtaskID: UUID) {
        guard var draft = inlineDetailDraft,
              let index = draft.subtasks.firstIndex(where: { $0.id == subtaskID })
        else { return }
        draft.subtasks[index].isCompleted.toggle()
        replaceInlineDraft(draft)
    }

    func updateDetailDraftSubtask(_ subtaskID: UUID, title: String) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false, var draft = inlineDetailDraft,
              let index = draft.subtasks.firstIndex(where: { $0.id == subtaskID })
        else { return }
        draft.subtasks[index].title = trimmed
        replaceInlineDraft(draft)
    }

    func deleteDetailDraftSubtask(_ subtaskID: UUID) {
        guard var draft = inlineDetailDraft else { return }
        draft.subtasks.removeAll { $0.id == subtaskID }
        for index in draft.subtasks.indices {
            draft.subtasks[index].sortOrder = index
        }
        replaceInlineDraft(draft)
    }

    private func mutateInlineDraft(_ mutation: (inout TaskDraft) -> Void) {
        guard var draft = inlineDetailDraft else { return }
        mutation(&draft)
        replaceInlineDraft(draft)
    }

    private func replaceInlineDraft(_ draft: TaskDraft) {
        if taskCreationSession != nil {
            updateTaskCreationDraft { $0 = draft }
        } else {
            detailDraft = draft
        }
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
        } catch {
            presentOperationError("任务更新失败，请重试。")
        }
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
                    // Let Draw On finish, then hold the completed mark briefly before migration.
                    try? await Task.sleep(for: .milliseconds(680))
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
            case .taskExpansion:
                var transaction = Transaction()
                transaction.animation = nil
                withTransaction(transaction) {
                    replaceItemPreservingOrder(saved)
                }
            }
            emitTaskMutation(spaceID: spaceID)
            await reconcileHomeItems(spaceID: spaceID)
        } catch {
            presentOperationError("任务状态更新失败，请重试。")
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
            presentOperationError("任务删除失败，请重试。")
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

    func deleteItem(
        _ itemID: UUID,
        removalAnimation: Animation? = nil
    ) async {
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
            let removeFromPresentation = {
                self.items.removeAll { $0.id == itemID }
                if self.selectedItemID == itemID {
                    self.dismissItemDetail()
                }
                if self.overdueEntryCount == 0 {
                    self.isOverdueSheetPresented = false
                }
            }
            if let removalAnimation {
                withAnimation(removalAnimation, removeFromPresentation)
            } else {
                removeFromPresentation()
            }
            emitTaskMutation(spaceID: spaceID)
        } catch {
            presentOperationError("任务删除失败，请重试。")
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
        await snoozeItem(itemID, using: primarySnoozeOption)
    }

    func snoozeItemToTomorrow(_ itemID: UUID) async {
        await snoozeItem(itemID, using: .tomorrow)
    }

    func snoozeItemToNextMonday(_ itemID: UUID) async {
        await snoozeItem(itemID, using: .nextMonday)
    }

    var primarySnoozeTitle: String {
        isFriday ? "推迟到下周一" : "推迟到明天"
    }

    var isFriday: Bool {
        calendar.component(.weekday, from: .now) == 6
    }

    private var primarySnoozeOption: TaskSnoozeOption {
        isFriday ? .nextMonday : .tomorrow
    }

    @discardableResult
    func rescheduleOverdueItemToToday(_ itemID: UUID) async -> Bool {
        guard
            let spaceID = sessionStore.currentSpace?.id,
            let actorID = sessionStore.currentUser?.id,
            let item = item(for: itemID)
        else { return false }

        do {
            let schedule = returnToTodaySchedule(for: item)
            let saved = try await taskApplicationService.rescheduleTask(
                in: spaceID,
                taskID: itemID,
                actorID: actorID,
                dueAt: schedule.dueAt,
                remindAt: schedule.remindAt
            )
            withAnimation(.smooth(duration: 0.28)) {
                replaceItemPreservingOrder(saved)
            }
            emitTaskMutation(spaceID: spaceID)
            return true
        } catch {
            presentOperationError("任务时间调整失败，请重试。")
            return false
        }
    }

    func rescheduleAllOverdueItemsToToday(
        onProgress: (_ completedCount: Int, _ totalCount: Int) -> Void = { _, _ in }
    ) async -> HomeOverdueBatchRescheduleResult {
        guard
            let spaceID = sessionStore.currentSpace?.id,
            let actorID = sessionStore.currentUser?.id
        else {
            return HomeOverdueBatchRescheduleResult(succeededIDs: [], failedIDs: [])
        }

        let candidates = overdueTimelineItems
        let totalCount = candidates.count
        var savedItems: [Item] = []
        var failedIDs: [UUID] = []

        for (index, item) in candidates.enumerated() {
            do {
                let schedule = returnToTodaySchedule(for: item)
                let saved = try await taskApplicationService.rescheduleTask(
                    in: spaceID,
                    taskID: item.id,
                    actorID: actorID,
                    dueAt: schedule.dueAt,
                    remindAt: schedule.remindAt
                )
                savedItems.append(saved)
            } catch {
                failedIDs.append(item.id)
            }
            onProgress(index + 1, totalCount)
        }

        if savedItems.isEmpty == false {
            withAnimation(.smooth(duration: 0.28)) {
                for saved in savedItems {
                    replaceItemPreservingOrder(saved)
                }
            }
            emitTaskMutation(spaceID: spaceID)
        }

        return HomeOverdueBatchRescheduleResult(
            succeededIDs: savedItems.map(\.id),
            failedIDs: failedIDs
        )
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

    func timelineEntry(for itemID: UUID) -> HomeTimelineEntry? {
        timelineEntries.first { $0.itemID == itemID }
    }

    var hasAnyTimelineEntriesForSelectedDate: Bool {
        sortedItemsForTimeline.isEmpty == false
    }

    var timelineEntryIDs: [UUID] {
        timelineEntries.map(\.id)
    }

    func morphPlacement(for itemID: UUID) -> TaskMorphPlacement? {
        for section in activeTimelineSections {
            if let index = section.entries.firstIndex(where: { $0.itemID == itemID }) {
                let entry = section.entries[index]
                let section = TaskMorphSection.todo(
                        dayStart: section.isUnscheduled ? nil : section.dayStart,
                        isUnscheduled: section.isUnscheduled
                    )
                return TaskMorphPlacement(
                    provisionalSection: section,
                    index: index,
                    presentationID: entry.presentationID
                )
            }
        }
        if let index = completedTimelineEntries.firstIndex(where: { $0.itemID == itemID }) {
            let entry = completedTimelineEntries[index]
            let section = TaskMorphSection.todoCompleted(dayStart: calendar.startOfDay(for: selectedDate))
            return TaskMorphPlacement(
                provisionalSection: section,
                index: index,
                presentationID: entry.presentationID
            )
        }
        return nil
    }

    private func selectLandingDate(for item: Item) {
        guard let dueAt = item.dueAt else { return }
        selectedDate = calendar.startOfDay(for: dueAt)
    }

    func relocateMorphItem(_ itemID: UUID) {
        guard let item = item(for: itemID) else { return }
        selectLandingDate(for: item)
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
            presentOperationError("任务排序保存失败，请重试。")
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

            return true
        } catch {
            presentOperationError("任务保存失败，请重试。")
            return false
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

    private func returnToTodaySchedule(
        for item: Item,
        now: Date = .now
    ) -> (dueAt: Date, remindAt: Date?) {
        let dueAt = returnToTodayDueDate(for: item, now: now)
        guard item.hasExplicitTime,
              let previousDueAt = item.dueAt,
              let previousRemindAt = item.remindAt
        else { return (dueAt, nil) }

        let recalculatedReminder = dueAt.addingTimeInterval(
            previousRemindAt.timeIntervalSince(previousDueAt)
        )
        return (dueAt, recalculatedReminder > now ? recalculatedReminder : nil)
    }

    private func returnToTodayDueDate(for item: Item, now: Date = .now) -> Date {
        guard item.hasExplicitTime, let dueAt = item.dueAt else {
            return dateOnlyDueDate(for: selectedDate)
        }

        let candidate = merge(date: selectedDate, timeSource: dueAt)
        guard candidate <= now else { return candidate }

        let selectedDayStart = calendar.startOfDay(for: selectedDate)
        let nextHour = calendar.dateInterval(of: .hour, for: now)?.end
            ?? now.addingTimeInterval(3_600)
        if calendar.isDate(nextHour, inSameDayAs: selectedDate) {
            return nextHour
        }

        let selectedDayEnd = calendar
            .date(byAdding: .day, value: 1, to: selectedDayStart)
            .flatMap { calendar.date(byAdding: .second, value: -1, to: $0) }
        if let selectedDayEnd, selectedDayEnd > now {
            return selectedDayEnd
        }

        return calendar.date(byAdding: .day, value: 1, to: selectedDayStart) ?? defaultDueDate()
    }

    private func dateOnlyDueDate(for date: Date) -> Date {
        calendar.startOfDay(for: date)
    }

    private func applySchedule(
        date: Date,
        time: Date?,
        reminderOffset: TimeInterval?,
        to draft: inout TaskDraft
    ) {
        let updatedDueAt: Date
        if let time {
            updatedDueAt = merge(date: date, timeSource: time)
            draft.hasExplicitTime = true
        } else {
            updatedDueAt = dateOnlyDueDate(for: date)
            draft.hasExplicitTime = false
        }

        draft.dueAt = updatedDueAt
        if time != nil, let reminderOffset {
            draft.remindAt = updatedDueAt.addingTimeInterval(-max(0, reminderOffset))
        } else {
            draft.remindAt = nil
        }
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
              let remindAt = item.remindAt
        else { return "" }
        let dueAt = item.occurrenceDueDate(on: selectedDate, calendar: calendar) ?? item.dueAt
        return TaskSharedAttributeText.reminderLead(
            dueAt: dueAt,
            hasExplicitTime: item.hasExplicitTime,
            remindAt: remindAt,
            calendar: calendar
        )
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
        return incompleteTimelineItems.filter {
            $0.isOverdue(on: selectedDate, calendar: calendar) == false
        }
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
                context: timelineSectionContext(
                    for: key.dayStart,
                    isUnscheduled: key.isUnscheduled
                ),
                count: entries.count,
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

        // `dueAt == nil` 仅作为旧数据/同步窗口的防御性兼容；产品语义中
        // 普通任务始终属于今天，不再生成“未排期”分组。
        return ActiveTimelineSectionKey(
            dayStart: calendar.startOfDay(for: selectedDate),
            isUnscheduled: false
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

    private func timelineSectionContext(for dayStart: Date, isUnscheduled: Bool) -> String {
        let weekday = weekdayLabel(for: dayStart)
        return isUnscheduled ? "创建·\(weekday)" : weekday
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
            createdAt: item.createdAt,
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
            timeText: timeText(for: item),
            createdAt: item.createdAt
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
        } catch {
            presentOperationError("任务推迟失败，请重试。")
        }
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
        case taskExpansion
    }
}
