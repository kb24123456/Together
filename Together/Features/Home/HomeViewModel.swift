import Foundation
import Observation
import SwiftUI

struct HomeAvatar: Identifiable, Hashable {
    let id: UUID
    let displayName: String
    let systemImageName: String
}

struct HomeTimelineEntry: Identifiable, Hashable {
    let id: UUID
    let title: String
    let notes: String?
    let timeText: String
    let statusText: String
    let accentColorName: String
    let isMuted: Bool
    let isCompleted: Bool
    let urgency: HomeTimelineUrgency
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

    private var detailSaveTask: Task<Void, Never>?
    private var savedDetailDraft: TaskDraft?
    private(set) var selectedDateTransitionEdge: Edge = .trailing
    private(set) var selectedDateTransitionStyle: HomeDateTransitionStyle = .sameWeek

    var calendarDisplayMode: HomeCalendarDisplayMode = .week
    var selectedDate: Date = Date()
    var displayedMonth: Date = Calendar.current.dateInterval(of: .month, for: .now)?.start ?? .now
    var items: [Item] = []
    var currentUserAvatar: HomeAvatar
    var pairPreviewAvatar: HomeAvatar
    var showsPairAvatarPreview = false
    var selectedItemID: UUID?
    var detailDraft: TaskDraft?
    var detailDetent: PresentationDetent = .height(316)
    private var completingOccurrenceKeys: Set<HomeItemOccurrenceKey> = []
    private var animatingCompletionOccurrenceKeys: Set<HomeItemOccurrenceKey> = []
    var showsCompletedItems = true
    var isPerformingSnooze = false
    var showsOverdueOnly = false

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
        let currentUser = sessionStore.currentUser ?? MockDataFactory.makeCurrentUser()
        self.currentUserAvatar = HomeAvatar(
            id: currentUser.id,
            displayName: currentUser.displayName,
            systemImageName: currentUser.avatarSystemName ?? "person.crop.circle.fill"
        )
        let pairPreviewUser = MockDataFactory.makePartnerUser()
        self.pairPreviewAvatar = HomeAvatar(
            id: pairPreviewUser.id,
            displayName: pairPreviewUser.displayName,
            systemImageName: pairPreviewUser.avatarSystemName ?? "person.2.circle.fill"
        )
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

    var headerAvatars: [HomeAvatar] {
        if showsPairAvatarPreview {
            return [currentUserAvatar, pairPreviewAvatar]
        }

        return [currentUserAvatar]
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
        showsOverdueOnly = false
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
        showsPairAvatarPreview.toggle()
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
        showsOverdueOnly = false
    }

    func returnToToday() {
        selectDate(Date())
    }

    func toggleOverdueFocus() {
        guard overdueEntryCount > 0 else { return }
        showsOverdueOnly.toggle()
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
            _ = try await taskApplicationService.createTask(
                in: spaceID,
                actorID: actorID,
                draft: draft
            )
            await reload()
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
            _ = try await taskApplicationService.createTask(
                in: spaceID,
                actorID: actorID,
                draft: draft
            )
            await reload()
            return true
        } catch {
            return false
        }
    }

    func loadIfNeeded() async {
        guard items.isEmpty else { return }
        await reload()
    }

    func reload() async {
        guard let spaceID = sessionStore.currentSpace?.id else {
            items = []
            return
        }

        do {
            try await archiveCompletedItemsIfNeeded(in: spaceID)
            items = try await taskApplicationService.tasks(
                in: spaceID,
                scope: scope(for: selectedDate)
            )
            if overdueEntryCount == 0 {
                showsOverdueOnly = false
            }
        } catch {
            items = []
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

    func updateDraftPriority(_ priority: ItemPriority) {
        detailDraft?.priority = priority
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
                    withAnimation(.spring(response: 0.34, dampingFraction: 0.86)) {
                        replaceItemPreservingOrder(saved)
                    }
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
        } catch {}

        completingOccurrenceKeys.remove(occurrenceKey)
        animatingCompletionOccurrenceKeys.remove(occurrenceKey)
    }

    func isAnimatingCompletion(for itemID: UUID, on referenceDate: Date) -> Bool {
        animatingCompletionOccurrenceKeys.contains(occurrenceKey(for: itemID, on: referenceDate))
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
        } catch {
            return
        }
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
                showsOverdueOnly = false
            }
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
            item.appearsOnHome(
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
        guard isViewingToday else { return 0 }
        return incompleteTimelineItems.filter { $0.isOverdue(on: selectedDate, calendar: calendar) }.count
    }

    var showsOverdueCapsule: Bool {
        overdueEntryCount > 0
    }

    var overdueCapsuleTitle: String {
        if showsOverdueOnly {
            return "显示全部任务"
        }
        return "有 \(overdueEntryCount) 件任务已逾期"
    }

    var hasCompletedEntries: Bool {
        completedEntryCount > 0
    }

    var completedVisibilityButtonTitle: String {
        showsCompletedItems ? "隐藏已完成" : "显示已完成"
    }

    var activeTimelineEntries: [HomeTimelineEntry] {
        filteredIncompleteTimelineItems.map(makeTimelineEntry)
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
        if calendar.isDate(date, inSameDayAs: MockDataFactory.now) {
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
        if item.isPinned || item.priority == .critical {
            return "coral"
        }

        return "neutral"
    }

    private var visibleTimelineItems: [Item] {
        let sortedItems = sortedItemsForTimeline
        guard showsCompletedItems == false else { return sortedItems }
        return sortedItems.filter { !isCompleted($0, on: selectedDate) }
    }

    private var incompleteTimelineItems: [Item] {
        visibleTimelineItems.filter { !isCompleted($0, on: selectedDate) }
    }

    private var filteredIncompleteTimelineItems: [Item] {
        guard showsOverdueOnly else { return incompleteTimelineItems }
        return incompleteTimelineItems.filter { $0.isOverdue(on: selectedDate, calendar: calendar) }
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

            if lhs.priority != rhs.priority {
                return priorityRank(lhs.priority) > priorityRank(rhs.priority)
            }

            if lhs.createdAt != rhs.createdAt {
                return lhs.createdAt < rhs.createdAt
            }

            return lhs.id.uuidString < rhs.id.uuidString
        }
    }

    private func urgency(for item: Item, isCompleted: Bool) -> HomeTimelineUrgency {
        guard isCompleted == false else { return .normal }
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

        return HomeTimelineEntry(
            id: item.id,
            title: item.title,
            notes: item.notes,
            timeText: timeText(for: item),
            statusText: statusText(for: item, isCompleted: isCompleted),
            accentColorName: accentColorName(for: item),
            isMuted: isCompleted,
            isCompleted: isCompleted,
            urgency: urgency(for: item, isCompleted: isCompleted)
        )
    }

    private func timelineSortDate(for item: Item) -> Date {
        item.occurrenceDueDate(on: selectedDate, calendar: calendar) ?? item.dueAt ?? .distantFuture
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

    private func archiveCompletedItemsIfNeeded(in spaceID: UUID) async throws {
        guard sessionStore.currentUser?.preferences.completedTaskAutoArchiveEnabled ?? true else {
            return
        }

        let days = NotificationSettings.normalizedCompletedTaskAutoArchiveDays(
            sessionStore.currentUser?.preferences.completedTaskAutoArchiveDays
            ?? NotificationSettings.defaultCompletedTaskAutoArchiveDays
        )
        try await itemRepository.archiveCompletedItemsIfNeeded(
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
        } catch {}
    }

}

extension HomeViewModel {
    enum CompletionTrigger {
        case inlineControl
        case swipeAction
    }
}
