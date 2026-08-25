import Foundation

protocol ReminderSchedulerProtocol: Sendable {
    func syncTaskReminder(for item: Item) async
    func removeTaskReminder(for itemID: UUID) async
    func snoozeTaskReminder(itemID: UUID, title: String, body: String, delay: TimeInterval) async
    func syncProjectReminder(for project: Project) async
    func removeProjectReminder(for projectID: UUID) async
    func syncDailySummary(for spaceID: UUID, tasks: [Item]) async
    func resync(
        spaceID: UUID?,
        tasks: [Item],
        projects: [Project],
        includeTaskReminders: Bool,
        includeDailySummary: Bool
    ) async
    func syncPeriodicTaskReminder(for task: PeriodicTask, referenceDate: Date) async
    func removePeriodicTaskReminder(for taskID: UUID) async
    func alarmAuthorizationStatus() async -> RoutineAlarmAuthorizationStatus
    func requestAlarmAuthorization() async throws -> RoutineAlarmAuthorizationStatus
    func periodicAlarmAuthorizationStatus() async -> RoutineAlarmAuthorizationStatus
    func requestPeriodicAlarmAuthorization() async throws -> RoutineAlarmAuthorizationStatus
}

extension ReminderSchedulerProtocol {
    func resync(tasks: [Item], projects: [Project]) async {
        await resync(
            spaceID: tasks.compactMap(\.spaceID).first ?? projects.compactMap(\.spaceID).first,
            tasks: tasks,
            projects: projects,
            includeTaskReminders: true,
            includeDailySummary: true
        )
    }

    func resync(
        tasks: [Item],
        projects: [Project],
        includeTaskReminders: Bool,
        includeDailySummary: Bool
    ) async {
        await resync(
            spaceID: tasks.compactMap(\.spaceID).first ?? projects.compactMap(\.spaceID).first,
            tasks: tasks,
            projects: projects,
            includeTaskReminders: includeTaskReminders,
            includeDailySummary: includeDailySummary
        )
    }
}
