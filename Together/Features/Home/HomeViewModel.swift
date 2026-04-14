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
    let title: String
    let notes: String?
    let timeText: String
    let statusText: String
    let assigneeText: String?
    let messagePreview: String?
    let responseStateText: String?
    let needsResponse: Bool
    let accentColorName: String
    let isMuted: Bool
    let isCompleted: Bool
    let urgency: HomeTimelineUrgency
    let pairCardStyle: HomePairCardStyle
    let relationText: String?
    let primaryAvatar: HomeAvatar?
    let secondaryAvatar: HomeAvatar?
    let latestMessageAuthorName: String?
    let reminderRequestedAt: Date?
}

enum HomePairCardStyle: Hashable {
    case standard
    case request
    case assigned
    case shared
    case sent
}

struct HomeTimelineSection: Identifiable, Hashable {
    let title: String
    let entries: [HomeTimelineEntry]

    var id: String { title }
}

struct HomeOverdueEntry: Identifiable, Hashable {
    let id: UUID
    let title: String
    let detailText: String
    let timeText: String
}

enum HomeTimelineUrgency: Hashable {
    case normal
    case imminent
    case overdue
}

enum HomeDateTransitionStyle: Hashable {
    case sameWeek
    case crossWeek
}

enum HomeCalendarDisplayMode: Hashable {
    case week
    case month
}

struct HomeMonthDay: Identifiable, Hashable {
    let date: Date
    let isInDisplayedMonth: Bool

    var id: TimeInterval {
        date.timeIntervalSince1970
    }
}

private struct HomeItemOccurrenceKey: Hashable {
    let itemID: UUID
    let dayStart: Date
}

struct QuickCapturePendingConfirmation: Identifiable, Hashable, Sendable {
    let id: UUID
    let rawInput: String
    let title: String
    let suggestedReminderAt: Date
    let confirmationKind: QuickCaptureConfirmationKind
}

enum QuickCaptureTaskCreationResult: Sendable, Equatable {
    case saved
    case needsTimeConfirmation(QuickCapturePendingConfirmation)
    case suggestPeriodicTask(title: String)
    case failed
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
    private let quickCaptureParser: QuickCaptureParserProtocol
    private let taskTemplateRepository: TaskTemplateRepositoryProtocol

    /// 任务操作完成后的回调，参数为 spaceID，用于触发同步
    var onTaskMutated: ((UUID) -> Void)?
    /// 共享任务 mutation 已记录后的精确回调，供 AppContext 走一等 shared mutation 发送路径。
    var onSharedMutationRecorded: ((SyncChange) -> Void)?
    /// 将当前任务转为例行事务时的回调（传递任务标题）
    var onConvertToPeriodicTask: ((String) -> Void)?
    /// 将当前任务转为项目时的回调（传递任务标题）
    var onConvertToProject: ((String) -> Void)?

    private var detailSaveTask: Task<Void, Never>?
    private var savedDetailDraft: TaskDraft?
    private var hasCompletedDeferredMaintenance = false
    private var insertedItemIDs: Set<UUID> = []
    private(set) var selectedDateTransitionEdge: Edge = .trailing
    private(set) var selectedDateTransitionStyle: HomeDateTransitionStyle = .sameWeek

    var calendarDisplayMode: HomeCalendarDisplayMode = .week
    var selectedDate: Date = Date()
    var displayedMonth: Date = Calendar.current.dateInterval(of: .month, for: .now)?.start ?? .now
    var items: [Item] = []
    var showsPairAvatarPreview = false
    var selectedItemID: UUID?
    var detailDraft: TaskDraft?
    var detailDetent: PresentationDetent = .height(316)
    private var completingOccurrenceKeys: Set<HomeItemOccurrenceKey> = []
    private var animatingCompletionOccurrenceKeys: Set<HomeItemOccurrenceKey> = []
    private var animatingReopeningOccurrenceKeys: Set<HomeItemOccurrenceKey> = []
    var showsCompletedItems = true
    var isPerformingSnooze = false
    var isOverdueSheetPresented = false
    var isDockHidden = false

    init(
        sessionStore: SessionStore,
        taskApplicationService: TaskApplicationServiceProtocol,
        itemRepository: ItemRepositoryProtocol,
        quickCaptureParser: QuickCaptureParserProtocol,
        taskTemplateRepository: TaskTemplateRepositoryProtocol
    ) {
        self.sessionStore = sessionStore
        self.taskApplicationService = taskApplicationService
        self.itemRepository = itemRepository
        self.quickCaptureParser = quickCaptureParser
        self.taskTemplateRepository = taskTemplateRepository
    }

    var currentUserRevision: UUID {
        sessionStore.userProfileRevision
    }

    var currentUserID: UUID? {
        sessionStore.currentUser?.id
    }

    var headerDateText: String {
        if isViewingToday {
            return "Today"
        }

        let components = calendar.dateComponents([.month, .day], from: selectedDate)
        let month = components.month ?? 1
        let day = components.day ?? 1
        return "\(month)月\(day)日"
    }

    var selectedDayNumberText: String {
        let day = calendar.component(.day, from: selectedDate)
        return "\(day)"
    }

    var selectedWeekdayAndDateText: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "EEEE\nM月d日"
        return formatter.string(from: selectedDate)
    }

    var weekDates: [Date] {
        weekDates(shiftedByWeeks: 0)
    }

    var isMonthMode: Bool {
        calendarDisplayMode == .month
    }

    var weekdaySymbols: [String] {
        ["日", "一", "二", "三", "四", "五", "六"]
    }

    var displayedMonthTitle: String {
        displayedMonth.formatted(
            .dateTime
            .locale(Locale(identifier: "zh_CN"))
            .month(.wide)
        )
    }

    var displayedMonthKey: String {
        let components = calendar.dateComponents([.year, .month], from: displayedMonth)
        return "\(components.year ?? 0)-\(components.month ?? 0)"
    }

    var monthDays: [HomeMonthDay] {
        monthDays(shiftedByMonths: 0)
    }

    var monthRowCount: Int {
        monthRowCount(shiftedByMonths: 0)
    }

    func monthDays(shiftedByMonths offset: Int) -> [HomeMonthDay] {
        let targetMonth = monthDate(shiftedByMonths: offset)

        guard
            let monthInterval = calendar.dateInterval(of: .month, for: targetMonth),
            let firstWeek = calendar.dateInterval(of: .weekOfMonth, for: monthInterval.start),
            let lastWeek = calendar.dateInterval(
                of: .weekOfMonth,
                for: monthInterval.end.addingTimeInterval(-1)
            )
        else {
            return []
        }

        var days: [HomeMonthDay] = []
        var current = firstWeek.start

        while current < lastWeek.end {
            days.append(
                HomeMonthDay(
                    date: current,
                    isInDisplayedMonth: calendar.isDate(current, equalTo: targetMonth, toGranularity: .month)
                )
            )

            guard let nextDay = calendar.date(byAdding: .day, value: 1, to: current) else { break }
            current = nextDay
        }

        return days
    }

    func monthRowCount(shiftedByMonths offset: Int) -> Int {
        max(monthDays(shiftedByMonths: offset).count / 7, 1)
    }

    func weekDates(shiftedByWeeks offset: Int) -> [Date] {
        let anchorDate: Date
        if offset == 0 {
            anchorDate = selectedDate
        } else {
            anchorDate = calendar.date(byAdding: .day, value: offset * 7, to: selectedDate) ?? selectedDate
        }

        let interval = calendar.dateInterval(of: .weekOfYear, for: anchorDate)
            ?? DateInterval(start: anchorDate, duration: 86_400 * 7)

        return (0..<7).compactMap {
            calendar.date(byAdding: .day, value: $0, to: interval.start)
        }
    }

    var selectedDateKey: String {
        String(Int(calendar.startOfDay(for: selectedDate).timeIntervalSince1970))
    }

    var selectedItem: Item? {
        guard let selectedItemID else { return nil }
        return items.first(where: { $0.id == selectedItemID })
    }

    func isAnimatingInsertion(for itemID: UUID) -> Bool {
        insertedItemIDs.contains(itemID)
    }

    func completeInsertionAnimation(for itemID: UUID) {
        insertedItemIDs.remove(itemID)
    }

    var hasUnsavedDetailChanges: Bool {
        guard detailDetent == .large, let detailDraft else { return false }
        return detailDraft != savedDetailDraft
    }

    var defaultSnoozeMinutes: Int {
        NotificationSettings.normalizedSnoozeMinutes(
            sessionStore.currentUser?.preferences.defaultSnoozeMinutes
            ?? NotificationSettings.defaultSnoozeMinutes
        )
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

    var isPairModeActive: Bool {
        sessionStore.isViewingPairSpace
    }

    var hasPairModeAvailable: Bool {
        sessionStore.availableModeStates.contains(.pair)
    }

    var partnerDisplayName: String? {
        sessionStore.pairSpaceSummary?.partner?.displayName
    }

    var spaceDisplayName: String {
        sessionStore.currentSpace?.displayName ?? (isPairModeActive ? "双人模式" : "我的任务空间")
    }

    var pairBannerText: String? {
        nil
    }

    var headerAvatars: [HomeAvatar] {
        if isPairModeActive {
            return [currentUserAvatar, pairPreviewAvatar]
        }

        return [currentUserAvatar]
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

    var pairPreviewAvatar: HomeAvatar {
        let pairPreviewUser = sessionStore.pairSpaceSummary?.partner ?? MockDataFactory.makePartnerUser()
        return HomeAvatar(
            id: pairPreviewUser.id,
            displayName: pairPreviewUser.displayName,
            avatarAsset: pairPreviewUser.avatarAsset,
            overrideImage: nil
        )
    }

    func selectDate(_ date: Date) {
        let oldDay = calendar.startOfDay(for: selectedDate)
        let newDay = calendar.startOfDay(for: date)
        selectedDateTransitionEdge = newDay >= oldDay ? .trailing : .leading
        selectedDateTransitionStyle = calendar.isDate(oldDay, equalTo: newDay, toGranularity: .weekOfYear)
            ? .sameWeek
            : .crossWeek
        selectedDate = date
        syncDisplayedMonthToSelectedDate()
        isOverdueSheetPresented = false
    }

    func shiftSelectedWeek(by offset: Int) {
        guard offset != 0 else { return }
        let shiftedWeekDates = weekDates(shiftedByWeeks: offset)
        let middleIndex = shiftedWeekDates.count / 2
        guard shiftedWeekDates.indices.contains(middleIndex) else {
            return
        }
        selectDate(shiftedWeekDates[middleIndex])
    }

    func toggleAvatarPreview() {
        guard hasPairModeAvailable else { return }
        sessionStore.switchMode(to: isPairModeActive ? .single : .pair)
        showsPairAvatarPreview = sessionStore.isViewingPairSpace
        Task {
            await reload()
        }
    }

    func updateDraftAssigneeMode(_ assigneeMode: TaskAssigneeMode) {
        guard var draft = detailDraft else { return }
        draft.assigneeMode = assigneeMode
        draft.executionRole = assigneeMode.legacyExecutionRole
        draft.assignmentState = assigneeMode == .partner ? .pendingResponse : .active
        draft.status = draft.assignmentState.legacyStatus
        detailDraft = draft
        scheduleDetailSave(immediately: true)
    }

    func updateDraftAssignmentNote(_ note: String) {
        detailDraft?.assignmentNote = note
        scheduleDetailSave()
    }

    func respondToSelectedItem(response: ItemResponseKind, message: String?) async {
        guard
            let selectedItemID
        else { return }

        await respondToItem(selectedItemID, response: response, message: message, updatesDetailDraft: true)
    }

    func respondToItem(
        _ itemID: UUID,
        response: ItemResponseKind,
        message: String?,
        updatesDetailDraft: Bool = false
    ) async {
        guard
            let spaceID = sessionStore.currentSpace?.id,
            let actorID = sessionStore.currentUser?.id
        else { return }

        do {
            let saved = try await taskApplicationService.respondToTask(
                in: spaceID,
                taskID: itemID,
                actorID: actorID,
                response: response,
                message: message
            )
            if updatesDetailDraft || selectedItemID == itemID {
                let refreshedDraft = TaskDraft(item: saved)
                detailDraft = refreshedDraft
                savedDetailDraft = refreshedDraft
            }
            replaceItem(saved)
            emitSharedTaskMutation(.upsert, taskID: saved.id, spaceID: spaceID)
        } catch {}
    }

    func appendAssignmentMessage(to itemID: UUID, message: String) async {
        guard
            let spaceID = sessionStore.currentSpace?.id,
            let actorID = sessionStore.currentUser?.id
        else { return }

        do {
            let saved = try await taskApplicationService.appendAssignmentMessage(
                in: spaceID,
                taskID: itemID,
                actorID: actorID,
                message: message
            )
            if selectedItemID == itemID {
                let refreshedDraft = TaskDraft(item: saved)
                detailDraft = refreshedDraft
                savedDetailDraft = refreshedDraft
            }
            replaceItem(saved)
            emitSharedTaskMutation(.upsert, taskID: saved.id, spaceID: spaceID)
        } catch {}
    }

    func requeueDeclinedItem(_ itemID: UUID) async {
        guard
            let spaceID = sessionStore.currentSpace?.id,
            let actorID = sessionStore.currentUser?.id
        else { return }

        do {
            let saved = try await taskApplicationService.requeueDeclinedTask(
                in: spaceID,
                taskID: itemID,
                actorID: actorID
            )
            if selectedItemID == itemID {
                let refreshedDraft = TaskDraft(item: saved)
                detailDraft = refreshedDraft
                savedDetailDraft = refreshedDraft
            }
            replaceItem(saved)
            emitSharedTaskMutation(.upsert, taskID: saved.id, spaceID: spaceID)
        } catch {}
    }

    func toggleCalendarDisplayMode() {
        if isMonthMode {
            calendarDisplayMode = .week
        } else {
            syncDisplayedMonthToSelectedDate()
            calendarDisplayMode = .month
        }
    }

    func setCalendarDisplayMode(_ mode: HomeCalendarDisplayMode) {
        guard calendarDisplayMode != mode else { return }
        if mode == .month {
            syncDisplayedMonthToSelectedDate()
        }
        calendarDisplayMode = mode
    }

    func shiftDisplayedMonth(by offset: Int) {
        guard offset != 0 else { return }
        guard let nextMonth = calendar.date(byAdding: .month, value: offset, to: displayedMonth) else { return }
        let nextStart = startOfMonth(for: nextMonth)
        displayedMonth = nextStart
        selectedDateTransitionEdge = offset > 0 ? .trailing : .leading
        selectedDateTransitionStyle = .crossWeek
        selectedDate = nextStart
        isOverdueSheetPresented = false
    }

    func returnToToday() {
        selectDate(Date())
    }

    func presentOverdueSheet() {
        guard showsOverdueCapsule else { return }
        isOverdueSheetPresented = true
    }

    func dismissOverdueSheet() {
        isOverdueSheetPresented = false
    }

    func createQuickCaptureTask(title: String) async -> QuickCaptureTaskCreationResult {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else { return .failed }
        guard
            let spaceID = sessionStore.currentSpace?.id,
            let actorID = sessionStore.currentUser?.id
        else {
            return .failed
        }

        let parseResult = quickCaptureParser.parse(trimmedTitle, now: .now, calendar: calendar)

        if parseResult.saveDecision == .suggestPeriodicTask {
            return .suggestPeriodicTask(title: parseResult.title)
        }

        if parseResult.saveDecision == .confirmTime,
           let suggestedReminderAt = parseResult.parsedDate {
            return .needsTimeConfirmation(
                QuickCapturePendingConfirmation(
                    id: UUID(),
                    rawInput: parseResult.rawInput,
                    title: parseResult.title,
                    suggestedReminderAt: suggestedReminderAt,
                    confirmationKind: parseResult.confirmationKind
                )
            )
        }

        let draft = quickCaptureDraft(
            title: parseResult.title,
            scheduledAt: parseResult.parsedDate,
            hasExplicitTime: parseResult.timeStatus == .exact
        )

        do {
            let item = try await taskApplicationService.createTask(
                in: spaceID,
                actorID: actorID,
                draft: draft
            )
            await reload(insertedItemIDs: [item.id])
            emitSharedTaskMutation(.upsert, taskID: item.id, spaceID: spaceID)
            return .saved
        } catch {
            return .failed
        }
    }

    func confirmQuickCaptureTask(
        _ confirmation: QuickCapturePendingConfirmation,
        reminderAt: Date
    ) async -> Bool {
        guard
            let spaceID = sessionStore.currentSpace?.id,
            let actorID = sessionStore.currentUser?.id
        else {
            return false
        }

        let draft = quickCaptureDraft(
            title: confirmation.title,
            scheduledAt: reminderAt,
            hasExplicitTime: true
        )

        do {
            let item = try await taskApplicationService.createTask(
                in: spaceID,
                actorID: actorID,
                draft: draft
            )
            await reload(insertedItemIDs: [item.id])
            emitSharedTaskMutation(.upsert, taskID: item.id, spaceID: spaceID)
            return true
        } catch {
            return false
        }
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

    func reload(insertedItemIDs expectedInsertedItemIDs: Set<UUID> = []) async {
        guard let spaceID = sessionStore.currentSpace?.id else {
            items = []
            insertedItemIDs = []
            return
        }

        do {
            // 记录刷新前的 ID 集合，用于检测同步到达的新任务
            let previousIDs = Set(items.map(\.id))

            let fetchedItems = try await taskApplicationService.tasks(
                in: spaceID,
                scope: scope(for: selectedDate)
            )
            let visibleItemIDs = Set(fetchedItems.map(\.id))
            let persistedInsertedIDs = insertedItemIDs.intersection(visibleItemIDs)
            let nextInsertedIDs = expectedInsertedItemIDs.intersection(visibleItemIDs)

            // 同步到达的新任务也标记为 inserted，触发入场动画
            let arrivedIDs = visibleItemIDs.subtracting(previousIDs).subtracting(expectedInsertedItemIDs)

            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                items = fetchedItems
            }
            insertedItemIDs = persistedInsertedIDs.union(nextInsertedIDs).union(arrivedIDs)
            if overdueEntryCount == 0 {
                isOverdueSheetPresented = false
            }
        } catch {
            items = []
            insertedItemIDs = []
        }
    }

    func presentItemDetail(_ itemID: UUID) {
        guard let item = items.first(where: { $0.id == itemID }) else { return }
        selectedItemID = itemID
        let draft = TaskDraft(item: item)
        detailDraft = draft
        savedDetailDraft = draft
        detailDetent = .height(316)
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
        scheduleDetailSave()
    }

    func updateDraftNotes(_ notes: String) {
        detailDraft?.notes = notes.isEmpty ? nil : notes
        scheduleDetailSave()
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
        scheduleDetailSave(immediately: true)
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
        scheduleDetailSave(immediately: true)
    }

    func updateDraftDueTime(_ dueTime: Date) {
        guard var draft = detailDraft else { return }
        let existing = draft.dueAt ?? defaultDueDate()
        draft.dueAt = merge(date: existing, timeSource: dueTime)
        draft.hasExplicitTime = true
        detailDraft = draft
        scheduleDetailSave(immediately: true)
    }

    func clearDraftDueTime() {
        guard var draft = detailDraft, let dueAt = draft.dueAt else { return }
        draft.dueAt = dateOnlyDueDate(for: dueAt)
        draft.hasExplicitTime = false
        draft.remindAt = nil
        detailDraft = draft
        scheduleDetailSave(immediately: true)
    }

    func setDraftReminderEnabled(_ enabled: Bool) {
        guard var draft = detailDraft else { return }
        draft.remindAt = enabled ? defaultReminderDate(for: draft) : nil
        detailDraft = draft
        scheduleDetailSave(immediately: true)
    }

    func updateDraftReminder(_ remindAt: Date) {
        detailDraft?.remindAt = remindAt
        scheduleDetailSave(immediately: true)
    }

    func updateDraftPinned(_ isPinned: Bool) {
        detailDraft?.isPinned = isPinned
        scheduleDetailSave(immediately: true)
    }

    func updateDraftRepeatRule(_ rule: ItemRepeatRule?) {
        detailDraft?.repeatRule = rule
        scheduleDetailSave(immediately: true)
    }

    func saveDetailDraft() async {
        detailSaveTask?.cancel()
        _ = await persistDetailDraft()
    }

    func saveDetailDraftAndDismiss() async {
        detailSaveTask?.cancel()

        if hasUnsavedDetailChanges {
            let didPersist = await persistDetailDraft()
            guard didPersist else { return }
        }

        dismissItemDetail()
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
            emitSharedTaskMutation(.upsert, taskID: item.id, spaceID: spaceID)
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

        let trimmedTitle = detailDraft.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedTitle.isEmpty == false else { return nil }

        let template = TaskTemplate(spaceID: spaceID, draft: detailDraft, calendar: calendar)

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

    func updateDraftRepeatRule(_ frequency: ItemRepeatFrequency?) {
        guard var draft = detailDraft else { return }
        guard let frequency else {
            updateDraftRepeatRule(nil as ItemRepeatRule?)
            return
        }

        let anchor = draft.dueAt ?? selectedDate
        switch frequency {
        case .daily:
            draft.repeatRule = ItemRepeatRule(frequency: .daily)
        case .weekly:
            draft.repeatRule = ItemRepeatRule(
                frequency: .weekly,
                weekday: calendar.component(.weekday, from: anchor)
            )
        case .monthly:
            draft.repeatRule = ItemRepeatRule(
                frequency: .monthly,
                dayOfMonth: calendar.component(.day, from: anchor)
            )
        }

        detailDraft = draft
        scheduleDetailSave(immediately: true)
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
            let didCompleteOccurrence = saved.isCompleted(on: referenceDate, calendar: calendar)
            switch trigger {
            case .inlineControl:
                if didCompleteOccurrence {
                    animatingCompletionOccurrenceKeys.insert(occurrenceKey)
                    try? await Task.sleep(for: .milliseconds(320))
                    withAnimation(.bouncy(duration: 0.68, extraBounce: 0.14)) {
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
            case .swipeAction:
                if didCompleteOccurrence {
                    try? await Task.sleep(for: .milliseconds(220))
                    withAnimation(.bouncy(duration: 0.58, extraBounce: 0.04)) {
                        replaceItemPreservingOrder(saved)
                    }
                } else {
                    try? await Task.sleep(for: .milliseconds(220))
                    withAnimation(.bouncy(duration: 0.56, extraBounce: 0.03)) {
                        replaceItemPreservingOrder(saved)
                    }
                }
            }
            emitSharedTaskMutation(
                didCompleteOccurrence ? .complete : .upsert,
                taskID: saved.id,
                spaceID: spaceID
            )
        } catch {}

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
            emitSharedTaskMutation(.delete, taskID: itemID, spaceID: spaceID)
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
            emitSharedTaskMutation(.delete, taskID: itemID, spaceID: spaceID)
        } catch {
            return
        }
    }

    func sendReminderToPartner(_ itemID: UUID) async {
        guard
            let spaceID = sessionStore.currentSpace?.id,
            let actorID = sessionStore.currentUser?.id
        else { return }

        do {
            let updated = try await taskApplicationService.sendReminderToPartner(
                in: spaceID,
                taskID: itemID,
                actorID: actorID
            )
            if let index = items.firstIndex(where: { $0.id == itemID }) {
                items[index] = updated
            }
            emitSharedTaskMutation(.upsert, taskID: updated.id, spaceID: spaceID)
        } catch {
            return
        }
    }

    func toggleCompletedVisibility() {
        withAnimation(.bouncy(duration: 0.74, extraBounce: 0.08)) {
            showsCompletedItems.toggle()
        }
    }

    func setCompletedVisibility(_ isVisible: Bool) {
        showsCompletedItems = isVisible
    }

    func snoozeItem(_ itemID: UUID) async {
        await snoozeItem(itemID, using: .minutes(defaultSnoozeMinutes))
    }

    func isSelectedDate(_ date: Date) -> Bool {
        calendar.isDate(date, inSameDayAs: selectedDate)
    }

    func hasItems(on date: Date) -> Bool {
        items.contains { item in
            guard shouldDisplayInCurrentTimeline(item) else { return false }
            return item.appearsOnHome(
                for: date,
                includeOverdue: calendar.isDate(date, inSameDayAs: .now),
                calendar: calendar
            )
        }
    }

    func hasNonRecurringItems(on date: Date) -> Bool {
        items.contains { item in
            guard item.repeatRule == nil, let dueAt = item.dueAt else { return false }
            return calendar.isDate(dueAt, inSameDayAs: date)
        }
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
        sortedItemsForTimeline.filter { isCompleted($0, on: selectedDate) }.count
    }

    var overdueEntryCount: Int {
        return incompleteTimelineItems.filter { $0.isOverdue(on: selectedDate, calendar: calendar) }.count
    }

    var showsOverdueCapsule: Bool {
        isViewingToday && overdueEntryCount > 0 && !isPairModeActive
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
        showsCompletedItems ? "隐藏已完成" : "显示已完成"
    }

    var activeTimelineEntries: [HomeTimelineEntry] {
        primaryIncompleteTimelineItems.map(makeTimelineEntry)
    }

    var pairTimelineSections: [HomeTimelineSection] {
        guard isPairModeActive else { return [] }

        let activeEntries = activeTimelineEntries
        guard activeEntries.isEmpty == false else { return [] }

        let sections: [(String, [HomeTimelineEntry])] = [
            ("等你回应", activeEntries.filter { $0.pairCardStyle == .request }),
            ("你负责", activeEntries.filter { $0.pairCardStyle == .assigned }),
            ("一起做", activeEntries.filter { $0.pairCardStyle == .shared }),
            ("你发出的", activeEntries.filter { $0.pairCardStyle == .sent })
        ]

        return sections.compactMap { title, entries in
            guard entries.isEmpty == false else { return nil }
            return HomeTimelineSection(title: title, entries: entries)
        }
    }

    var completedTimelineEntries: [HomeTimelineEntry] {
        guard showsCompletedItems else { return [] }
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

    private func scheduleDetailSave(immediately: Bool = false) {
        guard detailDetent != .large else { return }
        detailSaveTask?.cancel()
        detailSaveTask = Task { [weak self] in
            guard let self else { return }
            if immediately == false {
                try? await Task.sleep(for: .milliseconds(300))
            }
            guard Task.isCancelled == false else { return }
            await self.persistDetailDraft()
        }
    }

    private func quickCaptureDraft(
        title: String,
        scheduledAt: Date?,
        hasExplicitTime: Bool
    ) -> TaskDraft {
        if let scheduledAt {
            return TaskDraft(
                title: title,
                dueAt: scheduledAt,
                hasExplicitTime: hasExplicitTime,
                remindAt: scheduledAt
            )
        }

        return TaskDraft(
            title: title,
            dueAt: dateOnlyDueDate(for: selectedDate),
            hasExplicitTime: false
        )
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
            emitSharedTaskMutation(.upsert, taskID: saved.id, spaceID: spaceID)
            return true
        } catch {
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

    private func scope(for date: Date) -> TaskScope {
        if calendar.isDate(date, inSameDayAs: .now) {
            return .today(referenceDate: date)
        }
        return .scheduled(on: date)
    }

    private func defaultDueDate() -> Date {
        calendar.date(bySettingHour: 18, minute: 0, second: 0, of: selectedDate) ?? selectedDate
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
        guard let dueAt = item.dueAt else {
            return item.repeatRule?.title(anchorDate: item.anchorDateForRepeatRule, calendar: calendar) ?? "--:--"
        }
        guard item.hasExplicitTime else {
            return item.repeatRule?.title(anchorDate: item.anchorDateForRepeatRule, calendar: calendar) ?? "当天"
        }
        return dueAt.formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits))
    }

    private func accentColorName(for item: Item) -> String {
        if item.isPinned {
            return "coral"
        }

        return "neutral"
    }

    private var visibleTimelineItems: [Item] {
        let sortedItems = sortedItemsForTimeline.filter(shouldDisplayInCurrentTimeline)
        guard showsCompletedItems == false else { return sortedItems }
        return sortedItems.filter { !isCompleted($0, on: selectedDate) }
    }

    private var incompleteTimelineItems: [Item] {
        visibleTimelineItems.filter { !isCompleted($0, on: selectedDate) }
    }

    private var overdueTimelineItems: [Item] {
        guard isViewingToday else { return [] }
        return incompleteTimelineItems.filter { $0.isOverdue(on: selectedDate, calendar: calendar) }
    }

    private var primaryIncompleteTimelineItems: [Item] {
        guard isViewingToday else { return incompleteTimelineItems }
        return incompleteTimelineItems.filter { $0.isOverdue(on: selectedDate, calendar: calendar) == false }
    }

    private var completedTimelineItems: [Item] {
        guard showsCompletedItems else { return [] }
        return visibleTimelineItems.filter { isCompleted($0, on: selectedDate) }
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
            }

            let lhsDueAt = timelineSortDate(for: lhs)
            let rhsDueAt = timelineSortDate(for: rhs)
            if lhsDueAt != rhsDueAt {
                return lhsDueAt < rhsDueAt
            }

            if lhs.createdAt != rhs.createdAt {
                return lhs.createdAt < rhs.createdAt
            }

            return lhs.id.uuidString < rhs.id.uuidString
        }
    }

    private func shouldDisplayInCurrentTimeline(_ item: Item) -> Bool {
        guard isPairModeActive else { return true }
        guard let viewerID = sessionStore.currentUser?.id else { return true }
        guard item.assigneeMode == .partner else { return true }

        if item.assignmentState == .declined {
            return item.creatorID == viewerID
        }

        return true
    }

    private func urgency(for item: Item, isCompleted: Bool) -> HomeTimelineUrgency {
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
        let isCompleted = isCompleted(item, on: selectedDate)
        let viewerID = sessionStore.currentUser?.id ?? item.creatorID
        let isPairMode = isPairModeActive
        let pairCardStyle = pairCardStyle(for: item, viewerID: viewerID, isCompleted: isCompleted)
        let relationship = pairRelationship(for: item, viewerID: viewerID)

        return HomeTimelineEntry(
            id: item.id,
            title: item.title,
            notes: item.notes,
            timeText: timeText(for: item),
            statusText: statusText(for: item, isCompleted: isCompleted),
            assigneeText: isPairMode
                ? item.executionRole.label(for: viewerID, creatorID: item.creatorID)
                : nil,
            messagePreview: isPairMode ? item.assignmentMessages.last?.body : nil,
            responseStateText: responseStateText(for: item),
            needsResponse: isPairMode && item.requiresResponse && item.canActorRespond(viewerID),
            accentColorName: accentColorName(for: item),
            isMuted: isCompleted,
            isCompleted: isCompleted,
            urgency: urgency(for: item, isCompleted: isCompleted),
            pairCardStyle: pairCardStyle,
            relationText: relationship.relationText,
            primaryAvatar: relationship.primaryAvatar,
            secondaryAvatar: relationship.secondaryAvatar,
            latestMessageAuthorName: latestMessageAuthorName(for: item),
            reminderRequestedAt: item.reminderRequestedAt
        )
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

    private func responseStateText(for item: Item) -> String? {
        guard isPairModeActive else { return nil }
        switch item.assignmentState {
        case .pendingResponse:
            return item.canActorRespond(sessionStore.currentUser?.id ?? item.creatorID) ? "待我回应" : "等待对方回应"
        case .accepted:
            return "已接受"
        case .snoozed:
            return "已推迟"
        case .declined:
            return "已拒绝"
        case .active:
            return item.assigneeMode == .both ? "一起处理中" : "进行中"
        case .completed:
            return "已完成"
        }
    }

    private func pairCardStyle(for item: Item, viewerID: UUID, isCompleted: Bool) -> HomePairCardStyle {
        guard isPairModeActive, isCompleted == false else { return .standard }

        if item.assigneeMode == .partner {
            if item.requiresResponse {
                return item.canActorRespond(viewerID) ? .request : .sent
            }

            if item.creatorID == viewerID {
                return .sent
            }

            return .assigned
        }

        if item.assigneeMode == .both {
            return .shared
        }

        return .standard
    }

    private func pairRelationship(for item: Item, viewerID: UUID) -> (
        relationText: String?,
        primaryAvatar: HomeAvatar?,
        secondaryAvatar: HomeAvatar?
    ) {
        guard isPairModeActive else {
            return (nil, nil, nil)
        }

        let currentUser = sessionStore.currentUser
        let partner = sessionStore.pairSpaceSummary?.partner
        let currentUserAvatar = avatarMetadata(
            id: currentUser?.id ?? viewerID,
            displayName: currentUser?.displayName ?? "我",
            user: currentUser
        )
        let partnerAvatar = partner.map {
            avatarMetadata(id: $0.id, displayName: $0.displayName, user: $0)
        }
        let creatorAvatar: HomeAvatar? = {
            if item.creatorID == currentUser?.id {
                return currentUserAvatar
            }
            return partnerAvatar
        }()

        switch item.assigneeMode {
        case .partner:
            if item.creatorID == viewerID {
                return ("\(partner?.displayName ?? "对方")待处理", partnerAvatar, nil)
            }
            return ("\(partner?.displayName ?? "对方")发给你", currentUserAvatar, nil)
        case .both:
            return (nil, currentUserAvatar, partnerAvatar)
        case .self:
            return (nil, creatorAvatar, nil)
        }
    }

    private func latestMessageAuthorName(for item: Item) -> String? {
        guard let message = item.assignmentMessages.last else { return nil }
        let currentUserID = sessionStore.currentUser?.id
        if message.authorID == currentUserID {
            return "你"
        }
        if let partner = sessionStore.pairSpaceSummary?.partner, message.authorID == partner.id {
            return partner.displayName
        }
        return nil
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

    private func syncDisplayedMonthToSelectedDate() {
        displayedMonth = startOfMonth(for: selectedDate)
    }

    private func startOfMonth(for date: Date) -> Date {
        calendar.dateInterval(of: .month, for: date)?.start ?? date
    }

    private func monthDate(shiftedByMonths offset: Int) -> Date {
        guard offset != 0 else { return displayedMonth }
        guard let date = calendar.date(byAdding: .month, value: offset, to: displayedMonth) else {
            return displayedMonth
        }
        return startOfMonth(for: date)
    }

    private func isCompleted(_ item: Item, on referenceDate: Date) -> Bool {
        item.isCompleted(on: referenceDate, calendar: calendar) || item.status == .completed
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
                let shouldRemainVisible = saved.appearsOnHome(
                    for: selectedDate,
                    includeOverdue: calendar.isDate(selectedDate, inSameDayAs: .now),
                    calendar: calendar
                )
                if shouldRemainVisible {
                    replaceItemPreservingOrder(saved)
                } else {
                    removeItem(withID: saved.id)
                }
            }
            emitSharedTaskMutation(.upsert, taskID: saved.id, spaceID: spaceID)
        } catch {}
    }

    private func emitSharedTaskMutation(
        _ operation: SyncOperationKind,
        taskID: UUID,
        spaceID: UUID
    ) {
        let change = SyncChange(
            entityKind: .task,
            operation: operation,
            recordID: taskID,
            spaceID: spaceID
        )
        if let onSharedMutationRecorded {
            onSharedMutationRecorded(change)
        } else {
            onTaskMutated?(spaceID)
        }
    }
}

extension HomeViewModel {
    enum CompletionTrigger {
        case inlineControl
        case swipeAction
    }
}
