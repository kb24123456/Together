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

@MainActor
@Observable
final class HomeViewModel {
    private let calendar = Calendar.current
    private let sessionStore: SessionStore
    private let taskApplicationService: TaskApplicationServiceProtocol

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
    var detailDetent: PresentationDetent = .height(340)
    var isPerformingCompletion = false
    var recentCompletedItemID: UUID?
    var showsCompletedItems = true

    init(
        sessionStore: SessionStore,
        taskApplicationService: TaskApplicationServiceProtocol
    ) {
        self.sessionStore = sessionStore
        self.taskApplicationService = taskApplicationService
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

    var quickTimePresetMinutes: [Int] {
        NotificationSettings.normalizedQuickTimePresetMinutes(
            sessionStore.currentUser?.preferences.quickTimePresetMinutes
            ?? NotificationSettings.defaultQuickTimePresetMinutes
        )
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
        guard let shiftedDate = calendar.date(byAdding: .day, value: offset * 7, to: selectedDate) else {
            return
        }
        selectDate(shiftedDate)
    }

    func toggleAvatarPreview() {
        showsPairAvatarPreview.toggle()
    }

    func createQuickCaptureTask(title: String) async -> Bool {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else { return false }
        guard
            let spaceID = sessionStore.currentSpace?.id,
            let actorID = sessionStore.currentUser?.id
        else {
            return false
        }

        let dueAt = calendar.date(
            bySettingHour: 18,
            minute: 0,
            second: 0,
            of: selectedDate
        ) ?? selectedDate

        let draft = TaskDraft(
            title: trimmedTitle,
            dueAt: dueAt,
            hasExplicitTime: false
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
        detailDetent = .height(340)
    }

    func dismissItemDetail() {
        detailSaveTask?.cancel()
        detailSaveTask = nil
        selectedItemID = nil
        detailDraft = nil
        savedDetailDraft = nil
        detailDetent = .height(340)
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
            draft.hasExplicitTime = false
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
        draft.hasExplicitTime = true
        detailDraft = draft
        scheduleDetailSave(immediately: true)
    }

    func clearDraftDueTime() {
        guard var draft = detailDraft, let dueAt = draft.dueAt else { return }
        draft.dueAt = calendar.date(
            bySettingHour: 18,
            minute: 0,
            second: 0,
            of: dueAt
        ) ?? dueAt
        draft.hasExplicitTime = false
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

    func updateDraftRepeatRule(_ rule: ItemRepeatRule?) {
        detailDraft?.repeatRule = rule
        scheduleDetailSave(immediately: true)
    }

    func saveDetailDraft() async {
        detailSaveTask?.cancel()
        await persistDetailDraft()
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
            withAnimation(.spring(response: 0.34, dampingFraction: 0.86)) {
                replaceItemPreservingOrder(saved)
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
        withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) {
            showsCompletedItems.toggle()
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

    var completedEntryCount: Int {
        sortedItemsForTimeline.filter { $0.isCompleted(on: selectedDate, calendar: calendar) || $0.status == .completed }.count
    }

    var hasCompletedEntries: Bool {
        completedEntryCount > 0
    }

    var completedVisibilityButtonTitle: String {
        showsCompletedItems ? "隐藏已完成" : "显示已完成"
    }

    var timelineEntries: [HomeTimelineEntry] {
        visibleTimelineItems.map { item in
            let isCompleted = item.isCompleted(on: selectedDate, calendar: calendar) || item.status == .completed

            return HomeTimelineEntry(
                id: item.id,
                title: item.title,
                notes: item.notes,
                timeText: timeText(for: item),
                accentColorName: accentColorName(for: item),
                isMuted: isCompleted,
                isCompleted: isCompleted,
                urgency: urgency(for: item, isCompleted: isCompleted)
            )
        }
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
            let refreshedDraft = TaskDraft(item: saved)
            self.detailDraft = refreshedDraft
            self.savedDetailDraft = refreshedDraft
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

            if lhs.createdAt != rhs.createdAt {
                return lhs.createdAt < rhs.createdAt
            }

            return lhs.id.uuidString < rhs.id.uuidString
        }
    }

    private func urgency(for item: Item, isCompleted: Bool) -> HomeTimelineUrgency {
        guard isCompleted == false, let dueAt = item.dueAt else { return .normal }
        if dueAt <= .now {
            return .overdue
        }

        let imminentThreshold = TimeInterval(
            (sessionStore.currentUser?.preferences.taskUrgencyWindowMinutes ?? 30) * 60
        )
        if dueAt.timeIntervalSinceNow <= imminentThreshold {
            return .imminent
        }

        return .normal
    }
}
