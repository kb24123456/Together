import Foundation
import SwiftData

actor LocalPeriodicTaskRepository: PeriodicTaskRepositoryProtocol {
    private let container: ModelContainer
    private let syncCoordinator: SyncCoordinatorProtocol?

    init(container: ModelContainer, syncCoordinator: SyncCoordinatorProtocol? = nil) {
        self.container = container
        self.syncCoordinator = syncCoordinator
    }

    func fetchActiveTasks(spaceID: UUID?) async throws -> [PeriodicTask] {
        let context = ModelContext(container)
        let records = try context.fetch(
            FetchDescriptor<PersistentPeriodicTask>(
                predicate: #Predicate<PersistentPeriodicTask> {
                    $0.isActive == true && $0.isLocallyDeleted == false
                }
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
                predicate: #Predicate<PersistentPeriodicTask> {
                    $0.id == taskID && $0.isLocallyDeleted == false
                }
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

        var savedTask = task
        savedTask.updatedAt = .now

        if let record = existing.first {
            record.update(from: savedTask)
            record.isLocallyDeleted = false   // 重新保存即恢复
        } else {
            context.insert(PersistentPeriodicTask(task: savedTask))
        }

        try context.save()

        if let sid = savedTask.spaceID {
            await syncCoordinator?.recordLocalChange(
                SyncChange(entityKind: .periodicTask, operation: .upsert, recordID: savedTask.id, spaceID: sid)
            )
        }
        return savedTask
    }

    func reorderTasks(taskIDs: [UUID]) async throws -> [PeriodicTask] {
        guard taskIDs.isEmpty == false else { return [] }

        let context = ModelContext(container)
        let descriptor = FetchDescriptor<PersistentPeriodicTask>(
            predicate: #Predicate<PersistentPeriodicTask> { $0.isLocallyDeleted == false }
        )
        let records = try context.fetch(descriptor)
        let recordsByID = Dictionary(uniqueKeysWithValues: records.map { ($0.id, $0) })
        let now = Date.now

        for (index, taskID) in taskIDs.enumerated() {
            guard let record = recordsByID[taskID] else { continue }
            record.sortOrder = Double(index)
            record.updatedAt = now
        }

        try context.save()

        for taskID in taskIDs {
            guard let record = recordsByID[taskID], let sid = record.spaceID else { continue }
            await syncCoordinator?.recordLocalChange(
                SyncChange(entityKind: .periodicTask, operation: .upsert, recordID: taskID, spaceID: sid)
            )
        }

        return taskIDs.compactMap { taskID in
            recordsByID[taskID]?.domainModel()
        }
    }

    func deleteTask(taskID: UUID) async throws {
        let context = ModelContext(container)
        let records = try context.fetch(
            FetchDescriptor<PersistentPeriodicTask>(
                predicate: #Predicate<PersistentPeriodicTask> { $0.id == taskID }
            )
        )
        guard let record = records.first else { throw PeriodicTaskError.notFound }

        let spaceID = record.spaceID
        record.isLocallyDeleted = true
        record.updatedAt = .now
        try context.save()

        if let sid = spaceID {
            await syncCoordinator?.recordLocalChange(
                SyncChange(entityKind: .periodicTask, operation: .delete, recordID: taskID, spaceID: sid)
            )
        }
    }

    func markCompleted(taskID: UUID, periodKey: String, completedAt: Date) async throws -> PeriodicTask {
        let context = ModelContext(container)
        let records = try context.fetch(
            FetchDescriptor<PersistentPeriodicTask>(
                predicate: #Predicate<PersistentPeriodicTask> {
                    $0.id == taskID && $0.isLocallyDeleted == false
                }
            )
        )
        guard let record = records.first else { throw PeriodicTaskError.notFound }

        var task = record.domainModel()
        if !task.isCompleted(forPeriodKey: periodKey) {
            task.completions.append(PeriodicCompletion(periodKey: periodKey, completedAt: completedAt))
            task.updatedAt = completedAt
            record.update(from: task)
            try context.save()

            if let sid = record.spaceID {
                await syncCoordinator?.recordLocalChange(
                    SyncChange(entityKind: .periodicTask, operation: .complete, recordID: taskID, spaceID: sid)
                )
            }
        }
        return task
    }

    func markIncomplete(taskID: UUID, periodKey: String) async throws -> PeriodicTask {
        let context = ModelContext(container)
        let records = try context.fetch(
            FetchDescriptor<PersistentPeriodicTask>(
                predicate: #Predicate<PersistentPeriodicTask> {
                    $0.id == taskID && $0.isLocallyDeleted == false
                }
            )
        )
        guard let record = records.first else { throw PeriodicTaskError.notFound }

        var task = record.domainModel()
        task.completions.removeAll { $0.periodKey == periodKey }
        task.updatedAt = .now
        record.update(from: task)
        try context.save()

        if let sid = record.spaceID {
            await syncCoordinator?.recordLocalChange(
                SyncChange(entityKind: .periodicTask, operation: .upsert, recordID: taskID, spaceID: sid)
            )
        }
        return task
    }
}

enum PeriodicTaskError: Error, Equatable {
    case notFound
    case notSupported
}
