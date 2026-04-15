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

    // Detail sheet (two-stage: compact → expanded)
    var isDetailPresented = false
    var detailTask: PeriodicTask?
    var detailDetent: PresentationDetent = .height(316)

    init(
        sessionStore: SessionStore,
        periodicTaskApplicationService: PeriodicTaskApplicationServiceProtocol,
        taskTemplateRepository: TaskTemplateRepositoryProtocol
    ) {
        self.sessionStore = sessionStore
        self.periodicTaskApplicationService = periodicTaskApplicationService
        self.taskTemplateRepository = taskTemplateRepository
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
        guard let spaceID = sessionStore.currentSpace?.id else { return }
        loadState = .loading
        do {
            tasks = try await periodicTaskApplicationService.fetchTasks(in: spaceID)
            loadState = .loaded
        } catch {
            loadState = .failed(error.localizedDescription)
        }
    }

    func reload() async {
        await load()
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
        } catch {
            await load()
        }
    }

    func presentEditor(for task: PeriodicTask? = nil) {
        editingTask = task
        isEditorPresented = true
    }

    func dismissEditor() {
        isEditorPresented = false
        editingTask = nil
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
