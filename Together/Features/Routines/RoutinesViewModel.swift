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
        let targetText = RoutineTargetText.text(for: task, calendar: calendar)
        return RoutineTaskDisplayText(
            primarySubtitle: noteText ?? (targetText.isEmpty ? (isCompleted ? "已完成" : "进行中") : targetText),
            propertyText: noteText != nil && targetText.isEmpty == false ? targetText : nil
        )
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

struct RoutinesTemplateSaveResult: Sendable, Equatable {
    let templateID: UUID
    let isNewlyCreated: Bool
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

@MainActor
@Observable
final class RoutinesViewModel {
    private let sessionStore: SessionStore
    private let periodicTaskApplicationService: PeriodicTaskApplicationServiceProtocol
    private let taskTemplateRepository: TaskTemplateRepositoryProtocol
    private let calendar = Calendar.current

    var tasks: [PeriodicTask] = []
    var loadState: LoadableState = .idle
    var referenceDate: Date = .now
    var isEditorPresented = false
    var editingTask: PeriodicTask?
    var editorDefaultCycle: PeriodicCycle = .daily
    var selectedCycle: PeriodicCycle = .daily
    var expandedTaskID: UUID?
    var detailDraft: RoutineInlineDraft?

    private var loadedSpaceID: UUID?
    private var tasksBySpaceID: [UUID: [PeriodicTask]] = [:]
    private let optionalCyclesStorageKey = "together.routines.visibleOptionalCycles"
    @ObservationIgnored private var userEnabledOptionalCycles: Set<PeriodicCycle> = []

    init(
        sessionStore: SessionStore,
        periodicTaskApplicationService: PeriodicTaskApplicationServiceProtocol,
        taskTemplateRepository: TaskTemplateRepositoryProtocol
    ) {
        self.sessionStore = sessionStore
        self.periodicTaskApplicationService = periodicTaskApplicationService
        self.taskTemplateRepository = taskTemplateRepository
        self.userEnabledOptionalCycles = Self.loadUserEnabledOptionalCycles(storageKey: optionalCyclesStorageKey)
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
        let cyclesWithTasks = Set(tasks.map(\.cycle))
        return PeriodicCycle.allCases.filter { cycle in
            PeriodicCycle.defaultVisibleCases.contains(cycle)
                || userEnabledOptionalCycles.contains(cycle)
                || cyclesWithTasks.contains(cycle)
        }
    }

    var optionalHiddenCycles: [PeriodicCycle] {
        PeriodicCycle.optionalVisibleCases.filter { visibleCycles.contains($0) == false }
    }

    var currentTasks: [PeriodicTask] {
        sortedTasks(for: selectedCycle)
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
            let cycleTasks = tasks.filter { $0.cycle == cycle }
            let periodKey = PeriodicCycleCalculator.periodKey(for: cycle, date: referenceDate, calendar: calendar)
            let pendingCount = cycleTasks.filter { !$0.isCompleted(forPeriodKey: periodKey) }.count
            return pendingCount > 0 ? (cycle, pendingCount) : nil
        }
    }

    func attentionSummary(referenceDate: Date) -> [(PeriodicCycle, Int)] {
        PeriodicCycle.allCases.compactMap { cycle in
            let count = tasks.filter { task in
                guard task.cycle == cycle else { return false }
                let periodKey = PeriodicCycleCalculator.periodKey(for: task.cycle, date: referenceDate, calendar: calendar)
                guard task.isCompleted(forPeriodKey: periodKey) == false else { return false }
                let urgency = urgencyState(task)
                return urgency == .approaching || urgency == .pastReminder
            }.count
            return count > 0 ? (cycle, count) : nil
        }
    }

    func summary(for cycle: PeriodicCycle) -> RoutineDimensionSummary {
        let cycleTasks = tasks.filter { $0.cycle == cycle }
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
            .filter { $0.cycle == cycle }
            .sorted { lhs, rhs in
                let lhsCompleted = isCompleted(lhs)
                let rhsCompleted = isCompleted(rhs)
                if lhsCompleted != rhsCompleted { return !lhsCompleted }
                return lhs.sortOrder < rhs.sortOrder
            }
    }

    func pendingCount(for cycle: PeriodicCycle) -> Int {
        let cycleTasks = tasks.filter { $0.cycle == cycle }
        let periodKey = PeriodicCycleCalculator.periodKey(for: cycle, date: referenceDate, calendar: calendar)
        return cycleTasks.filter { !$0.isCompleted(forPeriodKey: periodKey) }.count
    }

    func sectionSummary(for cycle: PeriodicCycle) -> String {
        let cycleTasks = tasks.filter { $0.cycle == cycle }
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
            loadState = .failed(error.localizedDescription)
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
        selectedCycle = cycle
    }

    func addOptionalCycle(_ cycle: PeriodicCycle) {
        guard expandedTaskID == nil else { return }
        guard PeriodicCycle.optionalVisibleCases.contains(cycle) else { return }
        userEnabledOptionalCycles.insert(cycle)
        Self.saveUserEnabledOptionalCycles(userEnabledOptionalCycles, storageKey: optionalCyclesStorageKey)
        selectedCycle = cycle
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
        if showsLoading {
            loadState = .loading
        }
        do {
            let fetchedTasks = try await periodicTaskApplicationService.fetchTasks(in: spaceID)
            tasksBySpaceID[spaceID] = fetchedTasks
            guard sessionStore.currentSpace?.id == spaceID else { return }
            tasks = fetchedTasks
            loadedSpaceID = spaceID
            loadState = .loaded
        } catch {
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
        do {
            let updated = try await periodicTaskApplicationService.toggleCompletion(
                in: spaceID,
                taskID: taskID,
                referenceDate: referenceDate
            )
            if let index = tasks.firstIndex(where: { $0.id == taskID }) {
                tasks[index] = updated
            }
            cacheCurrentTasks()
        } catch {
            // Reload to ensure consistency
            await load()
        }
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

        guard let task = tasks.first(where: { $0.id == taskID }) else { return }
        expandedTaskID = taskID
        detailDraft = RoutineInlineDraft(task: task)
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

    func createTask(draft: PeriodicTaskDraft) async {
        guard let spaceID = sessionStore.currentSpace?.id,
              let actorID = sessionStore.currentUser?.id else { return }
        do {
            let created = try await periodicTaskApplicationService.createTask(
                in: spaceID,
                actorID: actorID,
                draft: draft
            )
            tasks.append(created)
            cacheCurrentTasks()
        } catch {
            await load()
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
            loadState = .failed(error.localizedDescription)
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
            await load()
        }
    }

    func presentEditor(for task: PeriodicTask? = nil, defaultCycle: PeriodicCycle? = nil) {
        editingTask = task
        editorDefaultCycle = task?.cycle ?? defaultCycle ?? selectedCycle
        isEditorPresented = true
    }

    func dismissEditor() {
        isEditorPresented = false
        editingTask = nil
        editorDefaultCycle = .daily
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

    // MARK: - Templates

    func saveAsTemplate(task: PeriodicTask) async -> RoutinesTemplateSaveResult? {
        guard let spaceID = sessionStore.currentSpace?.id else { return nil }
        let trimmedTitle = task.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else { return nil }

        let template = TaskTemplate(
            spaceID: spaceID,
            title: trimmedTitle,
            notes: task.notes
        )

        do {
            let existing = try await taskTemplateRepository.fetchTaskTemplates(spaceID: spaceID)
                .first { $0.title == template.title }

            if let existing {
                return RoutinesTemplateSaveResult(templateID: existing.id, isNewlyCreated: false)
            }

            let saved = try await taskTemplateRepository.saveTaskTemplate(template)
            return RoutinesTemplateSaveResult(templateID: saved.id, isNewlyCreated: true)
        } catch {
            return nil
        }
    }

    func deleteTemplate(templateID: UUID) async {
        do {
            try await taskTemplateRepository.deleteTaskTemplate(templateID: templateID)
        } catch {
            // silently ignore
        }
    }

    private static func loadUserEnabledOptionalCycles(storageKey: String) -> Set<PeriodicCycle> {
        let rawValues = UserDefaults.standard.stringArray(forKey: storageKey) ?? []
        return Set(rawValues.compactMap(PeriodicCycle.init(rawValue:)))
    }

    private static func saveUserEnabledOptionalCycles(_ cycles: Set<PeriodicCycle>, storageKey: String) {
        UserDefaults.standard.set(cycles.map(\.rawValue), forKey: storageKey)
    }
}
