import Foundation

protocol ReminderSchedulerProtocol: Sendable {
    func syncTaskReminder(for item: Item) async
    func removeTaskReminder(for itemID: UUID) async
    func snoozeTaskReminder(itemID: UUID, title: String, body: String, delay: TimeInterval) async
    func syncProjectReminder(for project: Project) async
    func removeProjectReminder(for projectID: UUID) async
    func resync(tasks: [Item], projects: [Project]) async
    func syncPeriodicTaskReminder(for task: PeriodicTask, referenceDate: Date) async
    func removePeriodicTaskReminder(for taskID: UUID) async
}
