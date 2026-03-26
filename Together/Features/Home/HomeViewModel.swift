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
    private let quickCaptureParser: QuickCaptureParserProtocol
    private let taskTemplateRepository: TaskTemplateRepositoryProtocol

    private var detailSaveTask: Task<Void, Never>?
    private var savedDetailDraft: TaskDraft?
    private(set) var selectedDateTransitionEdge: Edge = .trailing
    private(set) var selectedDateTransitionStyle: HomeDateTransitionStyle = .sameWeek

    var selectedDate: Date = Date()
    var items: [Item] = []
    var currentUserAvatar: HomeAvatar
    var pairPreviewAvatar: HomeAvatar
    var showsPairAvatarPreview = false
    var selectedItemID: UUID?
    var detailDraft: TaskDraft?
    var detailDetent: PresentationDetent = .height(316)
    var isPerformingCompletion = false
    var recentCompletedItemID: UUID?
    var showsCompletedItems = true
    var isPerformingSnooze = false

    init(
        sessionStore: SessionStore,
        taskApplicationService: TaskApplicationServiceProtocol,
        quickCaptureParser: QuickCaptureParserProtocol,
        taskTemplateRepository: TaskTemplateRepositoryProtocol
    ) {
        self.sessionStore = sessionStore
        self.taskApplicationService = taskApplicationService
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

    func returnToToday() {
        selectDate(Date())
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
            items = try await taskApplicationService.tasks(
                in: spaceID,
                scope: scope(for: selectedDate)
            )
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
        guard isPerformingCompletion == false else { return }
        isPerformingCompletion = true
        recentCompletedItemID = trigger == .inlineControl ? itemID : nil

        do {
            let saved = try await taskApplicationService.toggleTaskCompletion(
                in: spaceID,
                taskID: itemID,
                actorID: actorID
            )
            switch trigger {
            case .inlineControl:
                if saved.status == .completed || saved.completedAt != nil {
                    try? await Task.sleep(for: .milliseconds(280))
                    withAnimation(.bouncy(duration: 0.62, extraBounce: 0.08)) {
                        replaceItemPreservingOrder(saved)
                    }
                    try? await Task.sleep(for: .milliseconds(120))
                    recentCompletedItemID = nil
                } else {
                    withAnimation(.spring(response: 0.34, dampingFraction: 0.86)) {
                        replaceItemPreservingOrder(saved)
                    }
                    recentCompletedItemID = nil
                }
            case .swipeAction:
                if saved.status == .completed || saved.completedAt != nil {
                    try? await Task.sleep(for: .milliseconds(220))
                    withAnimation(.bouncy(duration: 0.58, extraBounce: 0.04)) {
                        replaceItemPreservingOrder(saved)
                    }
                    recentCompletedItemID = nil
                } else {
                    try? await Task.sleep(for: .milliseconds(220))
                    withAnimation(.bouncy(duration: 0.56, extraBounce: 0.03)) {
                        replaceItemPreservingOrder(saved)
                    }
                    recentCompletedItemID = nil
                }
            }
        } catch {
            recentCompletedItemID = nil
        }

        isPerformingCompletion = false
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
        sortedItemsForTimeline.filter { $0.isCompleted(on: selectedDate, calendar: calendar) || $0.status == .completed }.count
    }

    var hasCompletedEntries: Bool {
        completedEntryCount > 0
    }

    var completedVisibilityButtonTitle: String {
        showsCompletedItems ? "隐藏已完成" : "显示已完成"
    }

    var activeTimelineEntries: [HomeTimelineEntry] {
        incompleteTimelineItems.map(makeTimelineEntry)
    }

    var completedTimelineEntries: [HomeTimelineEntry] {
        guard showsCompletedItems else { return [] }
        return completedTimelineItems.map(makeTimelineEntry)
    }

    var timelineEntries: [HomeTimelineEntry] {
        activeTimelineEntries + completedTimelineEntries
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
        return sortedItems.filter { !($0.isCompleted(on: selectedDate, calendar: calendar) || $0.status == .completed) }
    }

    private var incompleteTimelineItems: [Item] {
        visibleTimelineItems.filter { !($0.isCompleted(on: selectedDate, calendar: calendar) || $0.status == .completed) }
    }

    private var completedTimelineItems: [Item] {
        guard showsCompletedItems else { return [] }
        return visibleTimelineItems.filter { $0.isCompleted(on: selectedDate, calendar: calendar) || $0.status == .completed }
    }

    private var sortedItemsForTimeline: [Item] {
        items.sorted { lhs, rhs in
            let lhsCompleted = lhs.isCompleted(on: selectedDate, calendar: calendar) || lhs.status == .completed
            let rhsCompleted = rhs.isCompleted(on: selectedDate, calendar: calendar) || rhs.status == .completed

            if lhsCompleted != rhsCompleted {
                return lhsCompleted == false
            }

            if lhsCompleted {
                let lhsCompletedAt = lhs.completedAt ?? .distantPast
                let rhsCompletedAt = rhs.completedAt ?? .distantPast
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
        let isCompleted = item.isCompleted(on: selectedDate, calendar: calendar) || item.status == .completed

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
