import Foundation
import SwiftData

actor LocalPeriodicTaskRepository: PeriodicTaskRepositoryProtocol {
    private let container: ModelContainer

    init(container: ModelContainer) {
        self.container = container
    }

    func fetchActiveTasks(spaceID: UUID?) async throws -> [PeriodicTask] {
        let context = ModelContext(container)
        let records = try context.fetch(
            FetchDescriptor<PersistentPeriodicTask>(
                predicate: #Predicate<PersistentPeriodicTask> { $0.isActive == true }
            )
        )
        return records
            .filter { $0.spaceID == spaceID }
            .map { $0.domainModel() }
            .sorted { $0.sortOrder < $1.sortOrder }
    }

    func fetchTask(taskID: UUID) async throws -> PeriodicTask? {
        let context = ModelContext(container)
        let records = try context.fetch(
            FetchDescriptor<PersistentPeriodicTask>(
                predicate: #Predicate<PersistentPeriodicTask> { $0.id == taskID }
            )
        )
        return records.first?.domainModel()
    }

    func saveTask(_ task: PeriodicTask) async throws -> PeriodicTask {
        let context = ModelContext(container)
        let existing = try context.fetch(
            FetchDescriptor<PersistentPeriodicTask>(
                predicate: #Predicate<PersistentPeriodicTask> { $0.id == task.id }
            )
        )

        if let record = existing.first {
            record.update(from: task)
        } else {
            context.insert(PersistentPeriodicTask(task: task))
        }

        try context.save()
        return task
    }

    func deleteTask(taskID: UUID) async throws {
        let context = ModelContext(container)
        let records = try context.fetch(
            FetchDescriptor<PersistentPeriodicTask>(
                predicate: #Predicate<PersistentPeriodicTask> { $0.id == taskID }
            )
        )
        for record in records {
            context.delete(record)
        }
        try context.save()
    }

    func markCompleted(taskID: UUID, periodKey: String, completedAt: Date) async throws -> PeriodicTask {
        let context = ModelContext(container)
        let records = try context.fetch(
            FetchDescriptor<PersistentPeriodicTask>(
                predicate: #Predicate<PersistentPeriodicTask> { $0.id == taskID }
            )
        )

        guard let record = records.first else {
            throw PeriodicTaskError.notFound
        }

        var task = record.domainModel()
        if !task.isCompleted(forPeriodKey: periodKey) {
            task.completions.append(PeriodicCompletion(periodKey: periodKey, completedAt: completedAt))
            task.updatedAt = completedAt
            record.update(from: task)
            try context.save()
        }

        return task
    }

    func markIncomplete(taskID: UUID, periodKey: String) async throws -> PeriodicTask {
        let context = ModelContext(container)
        let records = try context.fetch(
            FetchDescriptor<PersistentPeriodicTask>(
                predicate: #Predicate<PersistentPeriodicTask> { $0.id == taskID }
            )
        )

        guard let record = records.first else {
            throw PeriodicTaskError.notFound
        }

        var task = record.domainModel()
        task.completions.removeAll { $0.periodKey == periodKey }
        task.updatedAt = .now
        record.update(from: task)
        try context.save()

        return task
    }
}

enum PeriodicTaskError: Error {
    case notFound
}
