import Foundation
import Observation
import SwiftUI

enum PeriodicTaskUrgency: Hashable, Sendable {
    case normal
    case approaching
    case pastReminder
    case completed
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
    var editorDefaultCycle: PeriodicCycle = .monthly

    // Detail sheet (two-stage: compact → expanded)
    var isDetailPresented = false
    var detailTask: PeriodicTask?
    var detailDetent: PresentationDetent = .height(316)
    private var loadedSpaceID: UUID?
    private var tasksBySpaceID: [UUID: [PeriodicTask]] = [:]

    /// Fired after Repository/ApplicationService has already called recordLocalChange.
    /// AppContext wires this to flushRecordedSharedMutation to trigger a Supabase push.
    var onSharedMutationRecorded: ((SyncChange) -> Void)?

    init(
        sessionStore: SessionStore,
        periodicTaskApplicationService: PeriodicTaskApplicationServiceProtocol,
        taskTemplateRepository: TaskTemplateRepositoryProtocol
    ) {
        self.sessionStore = sessionStore
        self.periodicTaskApplicationService = periodicTaskApplicationService
        self.taskTemplateRepository = taskTemplateRepository
    }

    private func emitMutationRecorded(taskID: UUID, operation: SyncOperationKind, spaceID: UUID) {
        onSharedMutationRecorded?(
            SyncChange(entityKind: .periodicTask, operation: operation, recordID: taskID, spaceID: spaceID)
        )
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

    var monthlyTasks: [PeriodicTask] {
        tasks.filter { $0.cycle == .monthly }
    }

    var quarterlyTasks: [PeriodicTask] {
        tasks.filter { $0.cycle == .quarterly }
    }

    var yearlyTasks: [PeriodicTask] {
        tasks.filter { $0.cycle == .yearly }
    }

    // MARK: - Summary

    var hasPendingTasks: Bool {
        !pendingSummary(referenceDate: referenceDate).isEmpty
    }

    func pendingSummary(referenceDate: Date) -> [(PeriodicCycle, Int)] {
        PeriodicCycle.allCases.compactMap { cycle in
            let cycleTasks = tasks.filter { $0.cycle == cycle }
            let periodKey = PeriodicCycleCalculator.periodKey(for: cycle, date: referenceDate, calendar: calendar)
            let pendingCount = cycleTasks.filter { !$0.isCompleted(forPeriodKey: periodKey) }.count
            return pendingCount > 0 ? (cycle, pendingCount) : nil
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
            emitMutationRecorded(taskID: taskID, operation: .upsert, spaceID: spaceID)
        } catch {
            // Reload to ensure consistency
            await load()
        }
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
            emitMutationRecorded(taskID: created.id, operation: .upsert, spaceID: spaceID)
        } catch {
            await load()
        }
    }

    func updateTask(taskID: UUID, draft: PeriodicTaskDraft) async {
        guard let spaceID = sessionStore.currentSpace?.id,
              let actorID = sessionStore.currentUser?.id else { return }
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
            emitMutationRecorded(taskID: taskID, operation: .upsert, spaceID: spaceID)
        } catch {
            await load()
        }
    }

    func canDeletePeriodicTask(_ task: PeriodicTask) -> Bool {
        guard let userID = sessionStore.currentUser?.id else { return true }
        return PairPermissionService.canDeletePeriodicTask(task, actorID: userID)
    }

    func canEditPeriodicTask(_ task: PeriodicTask) -> Bool {
        guard let userID = sessionStore.currentUser?.id else { return true }
        return PairPermissionService.canEditPeriodicTask(task, actorID: userID)
    }

    func deleteTask(taskID: UUID) async {
        guard let spaceID = sessionStore.currentSpace?.id,
              let actorID = sessionStore.currentUser?.id else { return }
        do {
            try await periodicTaskApplicationService.deleteTask(in: spaceID, taskID: taskID, actorID: actorID)
            tasks.removeAll { $0.id == taskID }
            cacheCurrentTasks()
            emitMutationRecorded(taskID: taskID, operation: .delete, spaceID: spaceID)
        } catch {
            await load()
        }
    }

    func presentEditor(for task: PeriodicTask? = nil, defaultCycle: PeriodicCycle? = nil) {
        editingTask = task
        editorDefaultCycle = task?.cycle ?? defaultCycle ?? .monthly
        isEditorPresented = true
    }

    func dismissEditor() {
        isEditorPresented = false
        editingTask = nil
        editorDefaultCycle = .monthly
    }

    func presentDetail(for task: PeriodicTask) {
        detailTask = task
        detailDetent = .height(316)
        isDetailPresented = true
    }

    func dismissDetail() {
        isDetailPresented = false
        detailTask = nil
        detailDetent = .height(316)
    }

    func expandDetailToEdit() {
        detailDetent = .large
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
}
