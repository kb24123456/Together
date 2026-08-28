import Foundation

actor MockReminderScheduler: ReminderSchedulerProtocol {
    func syncTaskReminder(for item: Item) async {}

    func removeTaskReminder(for itemID: UUID) async {}

    func snoozeTaskReminder(itemID: UUID, title: String, body: String, delay: TimeInterval) async {}

    func syncProjectReminder(for project: Project) async {}

    func removeProjectReminder(for projectID: UUID) async {}

    func syncDailySummary(for spaceID: UUID, tasks: [Item]) async {}

    func resync(
        spaceID: UUID?,
        tasks: [Item],
        projects: [Project],
        includeTaskReminders: Bool,
        includeDailySummary: Bool
    ) async {}

    func syncPeriodicTaskReminder(for task: PeriodicTask, referenceDate: Date) async {}

    func removePeriodicTaskReminder(for taskID: UUID) async {}

    func reminderDeliveryPreference() async -> PeriodicReminderDelivery { .alarm }

    func updateReminderDeliveryPreference(_ delivery: PeriodicReminderDelivery) async {}

    func alarmAuthorizationStatus() async -> RoutineAlarmAuthorizationStatus { .authorized }

    func requestAlarmAuthorization() async throws -> RoutineAlarmAuthorizationStatus { .authorized }

    func periodicAlarmAuthorizationStatus() async -> RoutineAlarmAuthorizationStatus { .authorized }

    func requestPeriodicAlarmAuthorization() async throws -> RoutineAlarmAuthorizationStatus { .authorized }
}
