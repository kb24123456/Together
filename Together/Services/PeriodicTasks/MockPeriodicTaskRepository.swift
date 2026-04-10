import Foundation

@MainActor
final class MockPeriodicTaskRepository: PeriodicTaskRepositoryProtocol {
    private var tasks: [PeriodicTask] = MockDataFactory.makePeriodicTasks()

    func fetchActiveTasks(spaceID: UUID?) async throws -> [PeriodicTask] {
        tasks
            .filter { $0.isActive }
            .sorted { $0.sortOrder < $1.sortOrder }
    }

    func fetchTask(taskID: UUID) async throws -> PeriodicTask? {
        tasks.first { $0.id == taskID }
    }

    func saveTask(_ task: PeriodicTask) async throws -> PeriodicTask {
        if let index = tasks.firstIndex(where: { $0.id == task.id }) {
            tasks[index] = task
        } else {
            tasks.append(task)
        }
        return task
    }

    func deleteTask(taskID: UUID) async throws {
        tasks.removeAll { $0.id == taskID }
    }

    func markCompleted(taskID: UUID, periodKey: String, completedAt: Date) async throws -> PeriodicTask {
        guard let index = tasks.firstIndex(where: { $0.id == taskID }) else {
            throw PeriodicTaskError.notFound
        }
        if !tasks[index].isCompleted(forPeriodKey: periodKey) {
            tasks[index].completions.append(PeriodicCompletion(periodKey: periodKey, completedAt: completedAt))
            tasks[index].updatedAt = completedAt
        }
        return tasks[index]
    }

    func markIncomplete(taskID: UUID, periodKey: String) async throws -> PeriodicTask {
        guard let index = tasks.firstIndex(where: { $0.id == taskID }) else {
            throw PeriodicTaskError.notFound
        }
        tasks[index].completions.removeAll { $0.periodKey == periodKey }
        tasks[index].updatedAt = .now
        return tasks[index]
    }
}
