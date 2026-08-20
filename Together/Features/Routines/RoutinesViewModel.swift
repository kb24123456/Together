import Foundation
import Observation
import SwiftUI

enum PeriodicTaskUrgency: Hashable, Sendable {
    case normal
    case approaching
    case pastReminder
    case completed
}

struct RoutineDimensionSummary: Equatable {
    let cycle: PeriodicCycle
    let totalCount: Int
    let completedCount: Int
    let pendingCount: Int
    let attentionCount: Int
    let periodProgress: Double
    let daysRemaining: Int

    var completionProgress: Double {
        guard totalCount > 0 else { return 0 }
        return Double(completedCount) / Double(totalCount)
    }

}

struct RoutineTaskDisplayText: Equatable {
    let primarySubtitle: String
    let propertyText: String?

    static func text(
        for task: PeriodicTask,
        isCompleted: Bool,
        calendar: Calendar = .current
    ) -> RoutineTaskDisplayText {
        let trimmedNotes = task.notes?.trimmingCharacters(in: .whitespacesAndNewlines)
        let noteText = trimmedNotes?.isEmpty == false ? trimmedNotes : nil
        let targetText = RoutineTaskPropertyText.text(for: task, calendar: calendar)
        return RoutineTaskDisplayText(
            primarySubtitle: noteText ?? (targetText.isEmpty ? (isCompleted ? "已完成" : "进行中") : targetText),
            propertyText: noteText != nil && targetText.isEmpty == false ? targetText : nil
        )
    }
}

enum RoutineReminderText {
    static func text(for rule: PeriodicReminderRule) -> String {
        guard let leadMinutes = rule.reminderLeadMinutes else { return "" }
        let timing: String
        switch leadMinutes {
        case 0: timing = "目标时刻"
        case 5: timing = "提前 5 分钟"
        case 15: timing = "提前 15 分钟"
        case 30: timing = "提前 30 分钟"
        case 60: timing = "提前 1 小时"
        case 1_440: timing = "提前 1 天"
        default: timing = "提前 \(leadMinutes) 分钟"
        }
        let delivery = rule.reminderDelivery == .alarm ? "闹钟" : "提醒"
        return "\(timing) · \(delivery)"
    }
}

enum RoutineTaskPropertyText {
    static func text(for task: PeriodicTask, calendar: Calendar = .current) -> String {
        guard let rule = task.reminderRules.first else { return "" }
        return text(for: rule, cycle: task.cycle, calendar: calendar)
    }

    static func text(
        for rule: PeriodicReminderRule,
        cycle: PeriodicCycle,
        calendar: Calendar = .current
    ) -> String {
        [
            RoutineTargetText.text(for: rule, cycle: cycle, calendar: calendar),
            RoutineReminderText.text(for: rule)
        ]
        .filter { $0.isEmpty == false }
        .joined(separator: " · ")
    }
}

struct RoutineInlineDraft: Equatable {
    var title: String
    var notes: String
    var cycle: PeriodicCycle
    var reminderRules: [PeriodicReminderRule]

    init(task: PeriodicTask) {
        title = task.title
        notes = task.notes ?? ""
        cycle = task.cycle
        reminderRules = task.reminderRules
    }

    var periodicTaskDraft: PeriodicTaskDraft {
        PeriodicTaskDraft(
            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
            notes: notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : notes,
            cycle: cycle,
            reminderRules: reminderRules
        )
    }
}

enum RoutineTargetText {
    static func text(for task: PeriodicTask, calendar: Calendar = .current) -> String {
        guard let rule = task.reminderRules.first else {
            return ""
        }

        return text(for: rule, cycle: task.cycle, calendar: calendar)
    }

    static func text(for rule: PeriodicReminderRule, cycle: PeriodicCycle, calendar: Calendar = .current) -> String {
        let time: String? = if let hour = rule.hour, let minute = rule.minute {
            String(format: "%02d:%02d", hour, minute)
        } else {
            nil
        }

        switch cycle {
        case .daily:
            return time.map { "目标 \($0)" } ?? ""
        case .weekly:
            let dayText: String? = if case .dayOfPeriod(let day)? = rule.timing {
                weekdayText(for: day, calendar: calendar)
            } else {
                nil
            }
            return combinedTargetText(dayText: dayText, timeText: time)
        case .monthly:
            let dayText: String? = switch rule.timing {
            case .dayOfPeriod(let day)? where day >= 31: "每月最后一天"
            case .dayOfPeriod(let day)?: "每月 \(day) 号"
            case .businessDayOfPeriod(let day)?: "每月第 \(day) 个工作日"
            case .daysBeforeEnd(let days)?: "月底前 \(days) 天"
            case nil: nil
            }
            return combinedTargetText(dayText: dayText, timeText: time)
        case .quarterly, .yearly:
            let dayText: String? = switch rule.timing {
            case .dayOfPeriod(let day)?: "第 \(day) 天"
            case .businessDayOfPeriod(let day)?: "第 \(day) 个工作日"
            case .daysBeforeEnd(let days)?: "周期结束前 \(days) 天"
            case nil: nil
            }
            return combinedTargetText(dayText: dayText, timeText: time)
        }
    }

    private static func combinedTargetText(dayText: String?, timeText: String?) -> String {
        switch (dayText, timeText) {
        case let (.some(day), .some(time)): "\(day) \(time)"
        case let (.some(day), nil): day
        case let (nil, .some(time)): "目标 \(time)"
        case (nil, nil): ""
        }
    }

    static func weekdayText(for dayOfPeriod: Int, calendar: Calendar = .current) -> String {
        let names = ["周日", "周一", "周二", "周三", "周四", "周五", "周六"]
        let clamped = max(1, min(7, dayOfPeriod))
        let weekday = ((calendar.firstWeekday - 1 + clamped - 1) % 7) + 1
        return names[weekday - 1]
    }
}

enum PeriodicTaskCreationPhase: Equatable, Sendable {
    case editing
    case committing
    case committed
}

struct PeriodicTaskCreationSession: Equatable, Sendable, Identifiable {
    let id: UUID
    var draft: PeriodicTaskDraft
    var phase: PeriodicTaskCreationPhase
    var errorMessage: String?
}

@MainActor
@Observable
final class RoutinesViewModel {
    private let sessionStore: SessionStore
    private let periodicTaskApplicationService: PeriodicTaskApplicationServiceProtocol
    private let calendar = Calendar.current

    var tasks: [PeriodicTask] = []
    var loadState: LoadableState = .idle
    var operationErrorMessage: String?
    var referenceDate: Date = .now
    var selectedCycle: PeriodicCycle = .daily
    var expandedTaskID: UUID?
    var detailDraft: RoutineInlineDraft?
    var creationSession: PeriodicTaskCreationSession?
    var showsAlarmAuthorizationDeniedAlert = false
    private(set) var persistedVisibleCycles: Set<PeriodicCycle>
    private var pendingCompletedTask: PeriodicTask?
    private var completingTaskIDs: Set<UUID> = []
    private var animatingCompletionTaskIDs: Set<UUID> = []
    private var animatingReopeningTaskIDs: Set<UUID> = []
    private var temporaryVisibleCycle: PeriodicCycle?

    private var loadedSpaceID: UUID?
    private var tasksBySpaceID: [UUID: [PeriodicTask]] = [:]
    private static let visibleCyclesStorageKey = "together.routines.visibleCycles.v2"
    private static let legacyOptionalCyclesStorageKey = "together.routines.visibleOptionalCycles"

    enum TaskStreamPresentation: Equatable {
        case loading
        case failure
        case allEmpty
        case cycleEmpty
        case content
    }

    var taskStreamPresentation: TaskStreamPresentation {
        if tasks.isEmpty {
            switch loadState {
            case .idle, .loading:
                return .loading
            case .failed:
                return .failure
            case .loaded:
                return .allEmpty
            }
        }
        return currentTasks.isEmpty ? .cycleEmpty : .content
    }

    func dismissOperationError() {
        operationErrorMessage = nil
    }

    func beginMorphCreation(defaultCycle: PeriodicCycle? = nil) {
        guard creationSession == nil, expandedTaskID == nil else { return }
        creationSession = PeriodicTaskCreationSession(
            id: UUID(),
            draft: PeriodicTaskDraft(cycle: defaultCycle ?? selectedCycle),
            phase: .editing,
            errorMessage: nil
        )
    }

    func updateCreationDraft(_ mutation: (inout PeriodicTaskDraft) -> Void) {
        guard var session = creationSession, session.phase == .editing else { return }
        mutation(&session.draft)
        session.errorMessage = nil
        creationSession = session
    }

    func discardMorphCreation() {
        guard creationSession?.phase == .editing else { return }
        creationSession = nil
    }

    func commitMorphCreation() async -> TaskMorphPersistenceResult {
        guard var session = creationSession, session.phase == .editing else {
            return .failed(message: "当前无法创建定期任务。")
        }
        let title = session.draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard title.isEmpty == false else { return .failed(message: "请输入事务名称。") }
        session.draft.title = title
        session.phase = .committing
        session.errorMessage = nil
        creationSession = session

        guard let created = await createTask(id: session.id, draft: session.draft) else {
            session.phase = .editing
            session.errorMessage = operationErrorMessage ?? "定期任务创建失败，请重试。"
            creationSession = session
            return .failed(message: session.errorMessage ?? "定期任务创建失败，请重试。")
        }

        session.phase = .committed
        creationSession = session
        guard let descriptor = morphPlacement(for: created.id) else {
            return .failed(message: "任务已保存，但暂时无法定位到列表。")
        }
        return .saved(descriptor)
    }

    func finalizeMorphCreation() {
        guard creationSession?.phase == .committed else { return }
        creationSession = nil
    }

    init(
        sessionStore: SessionStore,
        periodicTaskApplicationService: PeriodicTaskApplicationServiceProtocol
    ) {
        self.sessionStore = sessionStore
        self.periodicTaskApplicationService = periodicTaskApplicationService
        self.persistedVisibleCycles = Self.loadPersistedVisibleCycles(
            storageKey: Self.visibleCyclesStorageKey,
            legacyStorageKey: Self.legacyOptionalCyclesStorageKey
        )
        if persistedVisibleCycles.contains(selectedCycle) == false,
           let firstVisibleCycle = PeriodicCycle.allCases.first(where: persistedVisibleCycles.contains) {
            selectedCycle = firstVisibleCycle
        }
    }

    private func replaceTask(_ updated: PeriodicTask) {
        if let index = tasks.firstIndex(where: { $0.id == updated.id }) {
            tasks[index] = updated
        } else {
            tasks.append(updated)
        }
        cacheCurrentTasks()
    }

    // MARK: - Grouped Tasks

    var weeklyTasks: [PeriodicTask] {
        tasks.filter { $0.cycle == .weekly }
    }

    var dailyTasks: [PeriodicTask] {
        tasks.filter { $0.cycle == .daily }
    }

    var monthlyTasks: [PeriodicTask] {
        tasks.filter { $0.cycle == .monthly }
    }

    var quarterlyTasks: [PeriodicTask] {
        tasks.filter { $0.cycle == .quarterly }
    }

    var yearlyTasks: [PeriodicTask] {
        tasks.filter { $0.cycle == .yearly }
    }

    var visibleCycles: [PeriodicCycle] {
        return PeriodicCycle.allCases.filter { cycle in
            persistedVisibleCycles.contains(cycle) || temporaryVisibleCycle == cycle
        }
    }

    var hiddenCycles: [PeriodicCycle] {
        PeriodicCycle.allCases.filter { persistedVisibleCycles.contains($0) == false }
    }

    var currentTasks: [PeriodicTask] {
        sortedTasks(for: selectedCycle)
    }

    var nextDeferredTaskResumeDate: Date? {
        tasks.compactMap(\.deferredUntil).filter { $0 > referenceDate }.min()
    }

    private func activeTasks(for cycle: PeriodicCycle, referenceDate: Date) -> [PeriodicTask] {
        tasks.filter {
            $0.cycle == cycle && isDeferred($0, referenceDate: referenceDate) == false
        }
    }

    private func isDeferred(_ task: PeriodicTask, referenceDate: Date) -> Bool {
        guard let deferredUntil = task.deferredUntil else { return false }
        return deferredUntil > referenceDate
    }

    // MARK: - Summary

    var hasPendingTasks: Bool {
        !pendingSummary(referenceDate: referenceDate).isEmpty
    }

    var hasAttentionTasks: Bool {
        !attentionSummary(referenceDate: referenceDate).isEmpty
    }

    func pendingSummary(referenceDate: Date) -> [(PeriodicCycle, Int)] {
        PeriodicCycle.allCases.compactMap { cycle in
            let cycleTasks = activeTasks(for: cycle, referenceDate: referenceDate)
            let periodKey = PeriodicCycleCalculator.periodKey(for: cycle, date: referenceDate, calendar: calendar)
            let pendingCount = cycleTasks.filter { !$0.isCompleted(forPeriodKey: periodKey) }.count
            return pendingCount > 0 ? (cycle, pendingCount) : nil
        }
    }

    func attentionSummary(referenceDate: Date) -> [(PeriodicCycle, Int)] {
        PeriodicCycle.allCases.compactMap { cycle in
            let count = tasks.filter { task in
                guard task.cycle == cycle else { return false }
                guard isDeferred(task, referenceDate: referenceDate) == false else { return false }
                let periodKey = PeriodicCycleCalculator.periodKey(for: task.cycle, date: referenceDate, calendar: calendar)
                guard task.isCompleted(forPeriodKey: periodKey) == false else { return false }
                let urgency = urgencyState(task)
                return urgency == .approaching || urgency == .pastReminder
            }.count
            return count > 0 ? (cycle, count) : nil
        }
    }

    func summary(for cycle: PeriodicCycle) -> RoutineDimensionSummary {
        let cycleTasks = activeTasks(for: cycle, referenceDate: referenceDate)
        let periodKey = PeriodicCycleCalculator.periodKey(for: cycle, date: referenceDate, calendar: calendar)
        let completedCount = cycleTasks.filter { $0.isCompleted(forPeriodKey: periodKey) }.count
        let attentionCount = cycleTasks.filter { task in
            let urgency = urgencyState(task)
            return task.isCompleted(forPeriodKey: periodKey) == false
                && (urgency == .approaching || urgency == .pastReminder)
        }.count
        return RoutineDimensionSummary(
            cycle: cycle,
            totalCount: cycleTasks.count,
            completedCount: completedCount,
            pendingCount: max(0, cycleTasks.count - completedCount),
            attentionCount: attentionCount,
            periodProgress: periodProgress(for: cycle),
            daysRemaining: daysRemaining(for: cycle)
        )
    }

    func sortedTasks(for cycle: PeriodicCycle) -> [PeriodicTask] {
        tasks
            .filter { $0.cycle == cycle && isDeferred($0, referenceDate: referenceDate) == false }
            .sorted { lhs, rhs in
                let lhsCompleted = isCompleted(lhs)
                let rhsCompleted = isCompleted(rhs)
                if lhsCompleted != rhsCompleted { return !lhsCompleted }
                return lhs.sortOrder < rhs.sortOrder
            }
    }

    func pendingCount(for cycle: PeriodicCycle) -> Int {
        let cycleTasks = activeTasks(for: cycle, referenceDate: referenceDate)
        let periodKey = PeriodicCycleCalculator.periodKey(for: cycle, date: referenceDate, calendar: calendar)
        return cycleTasks.filter { !$0.isCompleted(forPeriodKey: periodKey) }.count
    }

    func sectionSummary(for cycle: PeriodicCycle) -> String {
        let cycleTasks = activeTasks(for: cycle, referenceDate: referenceDate)
        let periodKey = PeriodicCycleCalculator.periodKey(for: cycle, date: referenceDate, calendar: calendar)
        let completedCount = cycleTasks.filter { $0.isCompleted(forPeriodKey: periodKey) }.count
        return "\(completedCount)/\(cycleTasks.count) 已完成"
    }

    func reorderTasks(_ orderedTasks: [PeriodicTask], fromOffsets: IndexSet, toOffset: Int) async {
        guard let spaceID = sessionStore.currentSpace?.id else { return }

        var reorderedIDs = orderedTasks.map(\.id)
        reorderedIDs.move(fromOffsets: fromOffsets, toOffset: toOffset)

        do {
            let updatedTasks = try await periodicTaskApplicationService.reorderTasks(in: spaceID, taskIDs: reorderedIDs)
            for task in updatedTasks {
                replaceTask(task)
            }
        } catch {
            operationErrorMessage = "定期任务排序失败，请重试。"
        }
    }

    func daysRemaining(for cycle: PeriodicCycle) -> Int {
        PeriodicCycleCalculator.daysRemainingInPeriod(for: cycle, date: referenceDate, calendar: calendar)
    }

    func periodProgress(for cycle: PeriodicCycle) -> Double {
        PeriodicCycleCalculator.periodProgress(for: cycle, date: referenceDate, calendar: calendar)
    }

    func selectCycle(_ cycle: PeriodicCycle) {
        guard expandedTaskID == nil else { return }
        guard visibleCycles.contains(cycle) else { return }
        if temporaryVisibleCycle != cycle {
            temporaryVisibleCycle = nil
        }
        selectedCycle = cycle
    }

    func setCycle(_ cycle: PeriodicCycle, isVisible: Bool) {
        guard expandedTaskID == nil else { return }
        if isVisible {
            persistedVisibleCycles.insert(cycle)
            if temporaryVisibleCycle == cycle {
                temporaryVisibleCycle = nil
            }
        } else {
            guard persistedVisibleCycles.contains(cycle), persistedVisibleCycles.count > 1 else { return }
            persistedVisibleCycles.remove(cycle)
            if selectedCycle == cycle,
               let fallback = PeriodicCycle.allCases.first(where: persistedVisibleCycles.contains) {
                selectedCycle = fallback
            }
        }
        Self.savePersistedVisibleCycles(persistedVisibleCycles, storageKey: Self.visibleCyclesStorageKey)
    }

    func canHideCycle(_ cycle: PeriodicCycle) -> Bool {
        persistedVisibleCycles.contains(cycle) && persistedVisibleCycles.count > 1
    }

    func selectCycleTemporarily(_ cycle: PeriodicCycle) {
        guard expandedTaskID == nil else { return }
        temporaryVisibleCycle = persistedVisibleCycles.contains(cycle) ? nil : cycle
        selectedCycle = cycle
    }

    func clearTemporaryCycleIfNeeded() {
        guard let temporaryVisibleCycle else { return }
        self.temporaryVisibleCycle = nil
        if selectedCycle == temporaryVisibleCycle,
           let fallback = PeriodicCycle.allCases.first(where: persistedVisibleCycles.contains) {
            selectedCycle = fallback
        }
    }

    // MARK: - Task State

    func isCompleted(_ task: PeriodicTask) -> Bool {
        let periodKey = PeriodicCycleCalculator.periodKey(for: task.cycle, date: referenceDate, calendar: calendar)
        return task.isCompleted(forPeriodKey: periodKey)
    }

    func urgencyState(_ task: PeriodicTask) -> PeriodicTaskUrgency {
        let periodKey = PeriodicCycleCalculator.periodKey(for: task.cycle, date: referenceDate, calendar: calendar)
        if task.isCompleted(forPeriodKey: periodKey) {
            return .completed
        }

        let now = Date.now
        for rule in task.reminderRules {
            guard let triggerDate = PeriodicCycleCalculator.reminderTriggerDate(
                rule: rule,
                cycle: task.cycle,
                date: referenceDate,
                calendar: calendar
            ) else { continue }

            if now >= triggerDate {
                return .pastReminder
            }

            let twoDaysBefore = triggerDate.addingTimeInterval(-2 * 24 * 3600)
            if now >= twoDaysBefore {
                return .approaching
            }
        }

        return .normal
    }

    // MARK: - Actions

    func load() async {
        await load(showsLoading: true)
    }

    func loadIfNeeded() async {
        referenceDate = .now
        guard loadState != .loading else {
            StartupTrace.mark("RoutinesViewModel.loadIfNeeded.coalesced")
            return
        }
        guard let spaceID = sessionStore.currentSpace?.id else {
            clearLoadedSpace()
            return
        }
        if loadedSpaceID != spaceID {
            restoreCachedTasks(for: spaceID)
            await load(showsLoading: tasks.isEmpty)
            return
        }
        guard loadState == .idle else { return }
        await load(showsLoading: tasks.isEmpty)
    }

    func reload(showsLoading: Bool = false) async {
        await load(showsLoading: showsLoading)
    }

    func restoreCachedTasksForCurrentSpace() {
        guard let spaceID = sessionStore.currentSpace?.id else {
            clearLoadedSpace()
            return
        }
        guard loadedSpaceID != spaceID else { return }
        restoreCachedTasks(for: spaceID)
    }

    private func load(showsLoading: Bool) async {
        guard let spaceID = sessionStore.currentSpace?.id else {
            clearLoadedSpace()
            return
        }
        StartupTrace.mark("RoutinesViewModel.load.fetch.begin")
        if showsLoading {
            loadState = .loading
        }
        do {
            let fetchedTasks = try await periodicTaskApplicationService.fetchTasks(in: spaceID)
            StartupTrace.mark("RoutinesViewModel.load.fetch.end count=\(fetchedTasks.count)")
            tasksBySpaceID[spaceID] = fetchedTasks
            guard sessionStore.currentSpace?.id == spaceID else { return }
            tasks = fetchedTasks
            loadedSpaceID = spaceID
            loadState = .loaded
        } catch {
            StartupTrace.mark("RoutinesViewModel.load.failed error=\(error.localizedDescription)")
            loadState = .failed(error.localizedDescription)
        }
    }

    private func restoreCachedTasks(for spaceID: UUID) {
        if let cachedTasks = tasksBySpaceID[spaceID] {
            tasks = cachedTasks
            loadedSpaceID = spaceID
            loadState = .loaded
        } else {
            tasks = []
            loadedSpaceID = nil
            loadState = .idle
        }
    }

    private func clearLoadedSpace() {
        tasks = []
        loadedSpaceID = nil
        loadState = .idle
    }

    private func cacheCurrentTasks() {
        guard let spaceID = loadedSpaceID ?? sessionStore.currentSpace?.id else { return }
        tasksBySpaceID[spaceID] = tasks
    }

    func toggleCompletion(taskID: UUID) async {
        guard let spaceID = sessionStore.currentSpace?.id else { return }
        guard completingTaskIDs.contains(taskID) == false else { return }
        completingTaskIDs.insert(taskID)
        defer {
            completingTaskIDs.remove(taskID)
            animatingCompletionTaskIDs.remove(taskID)
            animatingReopeningTaskIDs.remove(taskID)
        }

        do {
            let updated = try await periodicTaskApplicationService.toggleCompletion(
                in: spaceID,
                taskID: taskID,
                referenceDate: referenceDate
            )

            if isCompleted(updated) {
                animatingCompletionTaskIDs.insert(taskID)
                try? await Task.sleep(for: .milliseconds(320))
                withAnimation(.smooth(duration: 0.28, extraBounce: 0)) {
                    replaceTask(updated)
                }
                try? await Task.sleep(for: .milliseconds(140))
            } else {
                animatingReopeningTaskIDs.insert(taskID)
                try? await Task.sleep(for: .milliseconds(220))
                var transaction = Transaction()
                transaction.animation = nil
                withTransaction(transaction) {
                    replaceTask(updated)
                }
                try? await Task.sleep(for: .milliseconds(90))
            }
            cacheCurrentTasks()
        } catch {
            operationErrorMessage = "定期任务状态更新失败，请重试。"
            await load()
        }
    }

    func prepareExpandedCompletion(taskID: UUID) async -> Bool {
        guard completingTaskIDs.contains(taskID) == false else { return false }
        guard await saveInlineDetailDraft() else { return false }
        guard let spaceID = sessionStore.currentSpace?.id else { return false }
        completingTaskIDs.insert(taskID)
        do {
            pendingCompletedTask = try await periodicTaskApplicationService.toggleCompletion(
                in: spaceID,
                taskID: taskID,
                referenceDate: referenceDate
            )
            if let pendingCompletedTask, isCompleted(pendingCompletedTask) {
                animatingCompletionTaskIDs.insert(taskID)
            } else {
                animatingReopeningTaskIDs.insert(taskID)
            }
            return true
        } catch {
            completingTaskIDs.remove(taskID)
            animatingCompletionTaskIDs.remove(taskID)
            animatingReopeningTaskIDs.remove(taskID)
            pendingCompletedTask = nil
            operationErrorMessage = "定期任务状态更新失败，请重试。"
            return false
        }
    }

    func finishExpandedCompletion(taskID: UUID) {
        guard let pendingCompletedTask, pendingCompletedTask.id == taskID else { return }
        if isCompleted(pendingCompletedTask) {
            withAnimation(.smooth(duration: 0.28, extraBounce: 0)) {
                replaceTask(pendingCompletedTask)
            }
        } else {
            var transaction = Transaction()
            transaction.animation = nil
            withTransaction(transaction) {
                replaceTask(pendingCompletedTask)
            }
        }
        self.pendingCompletedTask = nil
        completingTaskIDs.remove(taskID)
        animatingCompletionTaskIDs.remove(taskID)
        animatingReopeningTaskIDs.remove(taskID)
        cacheCurrentTasks()
    }

    func isAnimatingCompletion(taskID: UUID) -> Bool {
        animatingCompletionTaskIDs.contains(taskID)
    }

    func isAnimatingReopening(taskID: UUID) -> Bool {
        animatingReopeningTaskIDs.contains(taskID)
    }

    func toggleInlineDetail(_ taskID: UUID) async {
        if expandedTaskID == taskID {
            await collapseInlineDetail()
            return
        }

        if expandedTaskID != nil {
            await collapseInlineDetail()
            return
        }

        guard let task = tasks.first(where: { $0.id == taskID }),
              isCompleted(task) == false
        else { return }
        expandedTaskID = taskID
        detailDraft = RoutineInlineDraft(task: task)
    }

    @discardableResult
    func presentDetailForMorph(_ taskID: UUID) -> Bool {
        guard expandedTaskID == nil,
              let task = tasks.first(where: { $0.id == taskID }),
              isCompleted(task) == false
        else { return false }
        expandedTaskID = taskID
        detailDraft = RoutineInlineDraft(task: task)
        return true
    }

    func finishMorphDetail() {
        expandedTaskID = nil
        detailDraft = nil
    }

    func updateDraftTitle(_ title: String) {
        detailDraft?.title = title
    }

    func updateDraftNotes(_ notes: String) {
        detailDraft?.notes = notes
    }

    func updateDraftCycle(_ cycle: PeriodicCycle) {
        detailDraft?.cycle = cycle
        if let first = detailDraft?.reminderRules.first {
            let normalized = Self.normalizedRule(first, for: cycle)
            detailDraft?.reminderRules = normalized.isEmpty ? [] : [normalized]
        }
    }

    func updateDraftReminderRule(_ rule: PeriodicReminderRule) {
        detailDraft?.reminderRules = rule.isEmpty ? [] : [rule]
    }

    func updateDraftTargetDay(_ timing: PeriodicReminderRule.Timing) {
        mutateDraftRule { $0.timing = timing }
    }

    func clearDraftTargetDay() {
        mutateDraftRule { $0.timing = nil }
    }

    func updateDraftTargetTime(hour: Int, minute: Int) {
        mutateDraftRule {
            $0.hour = hour
            $0.minute = minute
        }
    }

    func clearDraftTargetTime() {
        mutateDraftRule {
            $0.hour = nil
            $0.minute = nil
        }
    }

    func updateDraftReminder(leadMinutes: Int?) {
        mutateDraftRule {
            $0.reminderLeadMinutes = leadMinutes
            if leadMinutes == nil {
                $0.reminderDelivery = nil
            } else if $0.reminderDelivery == nil {
                $0.reminderDelivery = .notification
            }
        }
    }

    func updateDraftReminderDelivery(_ delivery: PeriodicReminderDelivery) async {
        if delivery == .alarm {
            guard await canUseAlarmDelivery() else { return }
        }

        mutateDraftRule {
            guard $0.reminderLeadMinutes != nil else { return }
            $0.reminderDelivery = delivery
        }
    }

    func canUseAlarmDelivery() async -> Bool {
        do {
            let status = await periodicTaskApplicationService.alarmAuthorizationStatus()
            let resolvedStatus = status == .notDetermined
                ? try await periodicTaskApplicationService.requestAlarmAuthorization()
                : status
            guard resolvedStatus == .authorized else {
                showsAlarmAuthorizationDeniedAlert = true
                return false
            }
            return true
        } catch {
            showsAlarmAuthorizationDeniedAlert = true
            return false
        }
    }

    func hasUnsavedInlineChanges(for task: PeriodicTask) -> Bool {
        guard expandedTaskID == task.id, let detailDraft else { return false }
        return detailDraft != RoutineInlineDraft(task: task)
    }

    func clearDraftReminderRule() {
        detailDraft?.reminderRules = []
    }

    private func mutateDraftRule(_ mutation: (inout PeriodicReminderRule) -> Void) {
        var rule = detailDraft?.reminderRules.first ?? PeriodicReminderRule()
        mutation(&rule)
        detailDraft?.reminderRules = rule.isEmpty ? [] : [rule]
    }

    @discardableResult
    func collapseInlineDetail() async -> Bool {
        guard let expandedTaskID, let draft = detailDraft else {
            expandedTaskID = nil
            detailDraft = nil
            return true
        }
        let originalTask = tasks.first { $0.id == expandedTaskID }
        if draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false,
           originalTask.map({ RoutineInlineDraft(task: $0) }) != draft {
            guard await updateTask(taskID: expandedTaskID, draft: draft.periodicTaskDraft) else {
                return false
            }
        }
        self.expandedTaskID = nil
        detailDraft = nil
        return true
    }

    func saveInlineDetailDraft() async -> Bool {
        guard let expandedTaskID, let draft = detailDraft else { return true }
        guard draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else {
            return false
        }
        let originalTask = tasks.first { $0.id == expandedTaskID }
        guard originalTask.map({ RoutineInlineDraft(task: $0) }) != draft else { return true }
        return await updateTask(taskID: expandedTaskID, draft: draft.periodicTaskDraft)
    }

    func saveDetailForMorph() async -> TaskMorphPersistenceResult {
        guard let expandedTaskID else { return .failed(message: "暂时无法定位定期任务。") }
        guard await saveInlineDetailDraft() else {
            return .failed(message: operationErrorMessage ?? "定期任务保存失败，请重试。")
        }
        guard let descriptor = morphPlacement(for: expandedTaskID) else {
            return .failed(message: "暂时无法定位定期任务。")
        }
        return .saved(descriptor)
    }

    func completeDetailForMorph() async -> TaskMorphPersistenceResult {
        guard let expandedTaskID,
              await saveInlineDetailDraft(),
              let spaceID = sessionStore.currentSpace?.id
        else { return .failed(message: operationErrorMessage ?? "定期任务保存失败，请重试。") }
        do {
            let updated = try await periodicTaskApplicationService.toggleCompletion(
                in: spaceID,
                taskID: expandedTaskID,
                referenceDate: referenceDate
            )
            replaceTask(updated)
            guard let descriptor = morphPlacement(for: expandedTaskID) else {
                return .failed(message: "暂时无法定位定期任务。")
            }
            return .saved(descriptor)
        } catch {
            operationErrorMessage = "定期任务状态更新失败，请重试。"
            return .failed(message: operationErrorMessage ?? "定期任务状态更新失败，请重试。")
        }
    }

    func morphPlacement(for taskID: UUID) -> TaskMorphPlacement? {
        guard let task = tasks.first(where: { $0.id == taskID }) else { return nil }
        let sorted = sortedTasks(for: task.cycle)
        guard let index = sorted.firstIndex(where: { $0.id == taskID }) else { return nil }
        let section = TaskMorphSection.periodic(cycle: task.cycle)
        return TaskMorphPlacement(
            provisionalSection: section,
            index: index,
            presentationID: task.id.uuidString
        )
    }

    func relocateMorphTask(_ taskID: UUID) {
        guard let cycle = tasks.first(where: { $0.id == taskID })?.cycle else { return }
        if persistedVisibleCycles.contains(cycle) {
            selectCycle(cycle)
        } else {
            selectCycleTemporarily(cycle)
        }
    }

    @discardableResult
    func createTask(id: UUID = UUID(), draft: PeriodicTaskDraft) async -> PeriodicTask? {
        guard let spaceID = sessionStore.currentSpace?.id,
              let actorID = sessionStore.currentUser?.id else { return nil }
        do {
            let created = try await periodicTaskApplicationService.createTask(
                id: id,
                in: spaceID,
                actorID: actorID,
                draft: draft
            )
            tasks.append(created)
            cacheCurrentTasks()
            return created
        } catch {
            operationErrorMessage = "定期任务创建失败，请重试。"
            return nil
        }
    }

    @discardableResult
    func updateTask(taskID: UUID, draft: PeriodicTaskDraft) async -> Bool {
        guard let spaceID = sessionStore.currentSpace?.id,
              let actorID = sessionStore.currentUser?.id else { return false }
        do {
            let updated = try await periodicTaskApplicationService.updateTask(
                in: spaceID,
                taskID: taskID,
                actorID: actorID,
                draft: draft
            )
            if let index = tasks.firstIndex(where: { $0.id == taskID }) {
                tasks[index] = updated
            }
            cacheCurrentTasks()
            loadState = .loaded
            return true
        } catch {
            operationErrorMessage = "定期任务保存失败，请重试。"
            return false
        }
    }

    func canDeletePeriodicTask(_ task: PeriodicTask) -> Bool {
        guard let userID = sessionStore.currentUser?.id else { return true }
        return SoloPermissionService.canDeletePeriodicTask(task, actorID: userID)
    }

    func canEditPeriodicTask(_ task: PeriodicTask) -> Bool {
        guard let userID = sessionStore.currentUser?.id else { return true }
        return SoloPermissionService.canEditPeriodicTask(task, actorID: userID)
    }

    func deferTaskUntilTomorrow(taskID: UUID) async {
        guard let spaceID = sessionStore.currentSpace?.id else { return }
        do {
            let updated = try await periodicTaskApplicationService.deferTaskUntilTomorrow(
                in: spaceID,
                taskID: taskID,
                referenceDate: .now
            )
            referenceDate = .now
            replaceTask(updated)
        } catch {
            operationErrorMessage = "定期任务推迟失败，请重试。"
            await load()
        }
    }

    func deleteTask(taskID: UUID) async {
        guard let spaceID = sessionStore.currentSpace?.id,
              let actorID = sessionStore.currentUser?.id else { return }
        do {
            try await periodicTaskApplicationService.deleteTask(in: spaceID, taskID: taskID, actorID: actorID)
            tasks.removeAll { $0.id == taskID }
            if expandedTaskID == taskID {
                expandedTaskID = nil
                detailDraft = nil
            }
            cacheCurrentTasks()
        } catch {
            operationErrorMessage = "定期任务删除失败，请重试。"
            await load()
        }
    }

    func refreshReferenceDate() {
        referenceDate = .now
    }

    static func defaultRule(for cycle: PeriodicCycle) -> PeriodicReminderRule {
        _ = cycle
        return PeriodicReminderRule()
    }

    static func normalizedRule(_ rule: PeriodicReminderRule, for cycle: PeriodicCycle) -> PeriodicReminderRule {
        var normalized = rule
        normalized.timing = normalizedTiming(rule.timing, for: cycle)
        return normalized
    }

    private static func normalizedTiming(
        _ timing: PeriodicReminderRule.Timing?,
        for cycle: PeriodicCycle
    ) -> PeriodicReminderRule.Timing? {
        guard let timing else { return nil }
        switch (cycle, timing) {
        case (.daily, _): return nil
        case let (.weekly, .dayOfPeriod(day)): return .dayOfPeriod(max(1, min(7, day)))
        case let (.monthly, .dayOfPeriod(day)): return .dayOfPeriod(max(1, min(31, day)))
        case let (.monthly, .businessDayOfPeriod(day)): return .businessDayOfPeriod(max(1, min(20, day)))
        case let (.monthly, .daysBeforeEnd(days)): return .daysBeforeEnd(max(1, min(30, days)))
        case let (.quarterly, .dayOfPeriod(day)): return .dayOfPeriod(max(1, min(90, day)))
        case let (.quarterly, .businessDayOfPeriod(day)): return .businessDayOfPeriod(max(1, min(20, day)))
        case let (.quarterly, .daysBeforeEnd(days)): return .daysBeforeEnd(max(1, min(89, days)))
        case let (.yearly, .dayOfPeriod(day)): return .dayOfPeriod(max(1, min(365, day)))
        case let (.yearly, .businessDayOfPeriod(day)): return .businessDayOfPeriod(max(1, min(260, day)))
        case let (.yearly, .daysBeforeEnd(days)): return .daysBeforeEnd(max(1, min(364, days)))
        default: return nil
        }
    }

    private static func loadPersistedVisibleCycles(
        storageKey: String,
        legacyStorageKey: String
    ) -> Set<PeriodicCycle> {
        if UserDefaults.standard.object(forKey: storageKey) != nil {
            let stored = Set(
                (UserDefaults.standard.stringArray(forKey: storageKey) ?? [])
                    .compactMap(PeriodicCycle.init(rawValue:))
            )
            if stored.isEmpty == false {
                return stored
            }
        }

        let legacyOptionalCycles = Set(
            (UserDefaults.standard.stringArray(forKey: legacyStorageKey) ?? [])
                .compactMap(PeriodicCycle.init(rawValue:))
        )
        let migrated = Set(PeriodicCycle.defaultVisibleCases).union(legacyOptionalCycles)
        savePersistedVisibleCycles(migrated, storageKey: storageKey)
        return migrated
    }

    private static func savePersistedVisibleCycles(_ cycles: Set<PeriodicCycle>, storageKey: String) {
        let orderedRawValues = PeriodicCycle.allCases
            .filter(cycles.contains)
            .map(\.rawValue)
        UserDefaults.standard.set(orderedRawValues, forKey: storageKey)
    }
}
