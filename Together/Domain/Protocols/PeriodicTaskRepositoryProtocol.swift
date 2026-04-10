import Foundation

protocol PeriodicTaskRepositoryProtocol: Sendable {
    func fetchActiveTasks(spaceID: UUID?) async throws -> [PeriodicTask]
    func fetchTask(taskID: UUID) async throws -> PeriodicTask?
    func saveTask(_ task: PeriodicTask) async throws -> PeriodicTask
    func deleteTask(taskID: UUID) async throws
    func markCompleted(taskID: UUID, periodKey: String, completedAt: Date) async throws -> PeriodicTask
    func markIncomplete(taskID: UUID, periodKey: String) async throws -> PeriodicTask
}
