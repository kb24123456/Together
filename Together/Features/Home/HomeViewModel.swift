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
    let locationText: String?
    let timeText: String
    let statusText: String
    let executionLabel: String
    let symbolName: String
    let accentColorName: String
    let showsSolidSymbol: Bool
    let isMuted: Bool
    let isCompleted: Bool
    let repeatText: String?
}

@MainActor
@Observable
final class HomeViewModel {
    private let calendar = Calendar.current
    private let sessionStore: SessionStore
    private let taskApplicationService: TaskApplicationServiceProtocol

    private var detailSaveTask: Task<Void, Never>?
    private(set) var selectedDateTransitionEdge: Edge = .trailing

    var selectedDate: Date = MockDataFactory.now
    var items: [Item] = []
    var currentUserAvatar: HomeAvatar
    var pairPreviewAvatar: HomeAvatar
    var showsPairAvatarPreview = false
    var selectedItemID: UUID?
    var detailDraft: TaskDraft?
    var detailDetent: PresentationDetent = .medium
    var isPerformingCompletion = false
    var recentCompletedItemID: UUID?

    init(
        sessionStore: SessionStore,
        taskApplicationService: TaskApplicationServiceProtocol
    ) {
        self.sessionStore = sessionStore
        self.taskApplicationService = taskApplicationService
        let currentUser = sessionStore.currentUser ?? MockDataFactory.makeCurrentUser()
        let currentSpace = sessionStore.currentSpace ?? MockDataFactory.makeSingleSpace()
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
        let interval = calendar.dateInterval(of: .weekOfYear, for: selectedDate)
            ?? DateInterval(start: selectedDate, duration: 86_400 * 7)

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
        selectedDate = date
    }

    func toggleAvatarPreview() {
        showsPairAvatarPreview.toggle()
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
        detailDraft = TaskDraft(item: item)
        detailDetent = .medium
    }

    func dismissItemDetail() {
        detailSaveTask?.cancel()
        detailSaveTask = nil
        selectedItemID = nil
        detailDraft = nil
        detailDetent = .medium
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
            let current = draft.dueAt ?? defaultDueDate()
            draft.dueAt = calendar.date(
                bySettingHour: calendar.component(.hour, from: current),
                minute: calendar.component(.minute, from: current),
                second: 0,
                of: selectedDate
            )
        } else {
            draft.dueAt = nil
        }
        detailDraft = draft
        scheduleDetailSave(immediately: true)
    }

    func updateDraftDueDate(_ dueDate: Date) {
        guard var draft = detailDraft else { return }
        let existing = draft.dueAt ?? defaultDueDate()
        draft.dueAt = merge(date: dueDate, timeSource: existing)
        detailDraft = draft
        scheduleDetailSave(immediately: true)
    }

    func updateDraftDueTime(_ dueTime: Date) {
        guard var draft = detailDraft else { return }
        let existing = draft.dueAt ?? defaultDueDate()
        draft.dueAt = merge(date: existing, timeSource: dueTime)
        detailDraft = draft
        scheduleDetailSave(immediately: true)
    }

    func setDraftReminderEnabled(_ enabled: Bool) {
        guard var draft = detailDraft else { return }
        draft.remindAt = enabled ? (draft.dueAt ?? defaultReminderDate()) : nil
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

    func updateDraftRepeatRule(_ frequency: ItemRepeatFrequency?) {
        guard var draft = detailDraft else { return }
        guard let frequency else {
            draft.repeatRule = nil
            detailDraft = draft
            scheduleDetailSave(immediately: true)
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

    func completeItem(_ itemID: UUID) async {
        guard let spaceID = sessionStore.currentSpace?.id, let actorID = sessionStore.currentUser?.id else { return }
        guard isPerformingCompletion == false else { return }
        isPerformingCompletion = true
        recentCompletedItemID = itemID

        do {
            let saved = try await taskApplicationService.toggleTaskCompletion(
                in: spaceID,
                taskID: itemID,
                actorID: actorID
            )
            replaceItemPreservingOrder(saved)
        } catch {
            recentCompletedItemID = nil
        }

        isPerformingCompletion = false
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

        return items.map { item in
            let isCompleted = item.isCompleted(on: selectedDate, calendar: calendar) || item.status == .completed

            return HomeTimelineEntry(
                id: item.id,
                title: item.title,
                notes: item.notes,
                locationText: item.locationText,
                timeText: timeText(for: item),
                statusText: statusText(for: item, isCompleted: isCompleted),
                executionLabel: executionLabel(for: item, viewerID: viewerID),
                symbolName: symbolName(for: item),
                accentColorName: accentColorName(for: item),
                showsSolidSymbol: item.isPinned || item.priority == .critical || isCompleted,
                isMuted: isCompleted || (item.priority == .normal && item.isPinned == false),
                isCompleted: isCompleted,
                repeatText: item.repeatRule?.title(anchorDate: item.anchorDateForRepeatRule, calendar: calendar)
            )
        }
    }

    private func scheduleDetailSave(immediately: Bool = false) {
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

    private func persistDetailDraft() async {
        guard
            let spaceID = sessionStore.currentSpace?.id,
            let actorID = sessionStore.currentUser?.id,
            let selectedItemID,
            let detailDraft
        else { return }

        do {
            let saved = try await taskApplicationService.updateTask(
                in: spaceID,
                taskID: selectedItemID,
                actorID: actorID,
                draft: detailDraft
            )
            replaceItem(saved)
        } catch {
            return
        }
    }

    private func replaceItem(_ item: Item) {
        if let index = items.firstIndex(where: { $0.id == item.id }) {
            items[index] = item
        } else {
            items.append(item)
        }
        items.sort { lhs, rhs in
            lhs.updatedAt > rhs.updatedAt
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

    private func defaultReminderDate() -> Date {
        calendar.date(byAdding: .minute, value: -30, to: defaultDueDate()) ?? defaultDueDate()
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
        guard let dueAt = item.dueAt else {
            return item.repeatRule?.title(anchorDate: item.anchorDateForRepeatRule, calendar: calendar) ?? "--:--"
        }
        return dueAt.formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits))
    }

    private func executionLabel(for item: Item, viewerID: UUID) -> String {
        if let repeatRule = item.repeatRule {
            return repeatRule.title(anchorDate: item.anchorDateForRepeatRule, calendar: calendar)
        }
        if item.isPinned || item.priority == .critical {
            return "今日重点"
        }
        if item.creatorID != viewerID {
            return "共享输入"
        }

        switch item.status {
        case .pendingConfirmation:
            return "待整理"
        case .inProgress:
            return "正在推进"
        case .completed:
            return "已收尾"
        case .declinedOrBlocked:
            return "已搁置"
        }
    }

    private func statusText(for item: Item, isCompleted: Bool) -> String {
        if isCompleted {
            return "已完成"
        }
        if item.isOverdue(on: selectedDate, calendar: calendar) {
            return "已逾期"
        }

        switch item.status {
        case .pendingConfirmation:
            return "待整理"
        case .inProgress:
            return "进行中"
        case .completed:
            return "已完成"
        case .declinedOrBlocked:
            return "已搁置"
        }
    }

    private func symbolName(for item: Item) -> String {
        if item.repeatRule != nil {
            return "repeat"
        }

        switch item.title {
        case let title where title.localizedStandardContains("晨会"):
            return "sun.max.fill"
        case let title where title.localizedStandardContains("复盘"):
            return "moon.fill"
        default:
            return item.isPinned ? "sparkles" : "circle"
        }
    }

    private func accentColorName(for item: Item) -> String {
        if item.isPinned || item.priority == .critical {
            return "coral"
        }
        if item.repeatRule != nil {
            return "neutral"
        }

        switch item.title {
        case let title where title.localizedStandardContains("晨会"):
            return "sun"
        case let title where title.localizedStandardContains("复盘"):
            return "violet"
        default:
            return "neutral"
        }
    }
}
