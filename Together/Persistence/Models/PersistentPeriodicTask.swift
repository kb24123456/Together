import Foundation
import SwiftData

@Model
final class PersistentPeriodicTask {
    var id: UUID
    var spaceID: UUID?
    var creatorID: UUID
    var title: String
    var notes: String?
    var cycleRawValue: String
    var reminderRulesData: Data?
    var completionsData: Data
    var subtasksData: Data?
    var sortOrder: Double
    var isActive: Bool
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID,
        spaceID: UUID?,
        creatorID: UUID,
        title: String,
        notes: String?,
        cycleRawValue: String,
        reminderRulesData: Data?,
        completionsData: Data,
        subtasksData: Data?,
        sortOrder: Double,
        isActive: Bool,
        createdAt: Date,
        updatedAt: Date
    ) {
        self.id = id
        self.spaceID = spaceID
        self.creatorID = creatorID
        self.title = title
        self.notes = notes
        self.cycleRawValue = cycleRawValue
        self.reminderRulesData = reminderRulesData
        self.completionsData = completionsData
        self.subtasksData = subtasksData
        self.sortOrder = sortOrder
        self.isActive = isActive
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

extension PersistentPeriodicTask {
    convenience init(task: PeriodicTask) {
        self.init(
            id: task.id,
            spaceID: task.spaceID,
            creatorID: task.creatorID,
            title: task.title,
            notes: task.notes,
            cycleRawValue: task.cycle.rawValue,
            reminderRulesData: Self.encode(task.reminderRules),
            completionsData: Self.encode(task.completions),
            subtasksData: Self.encode(task.subtasks),
            sortOrder: task.sortOrder,
            isActive: task.isActive,
            createdAt: task.createdAt,
            updatedAt: task.updatedAt
        )
    }

    func domainModel() -> PeriodicTask {
        PeriodicTask(
            id: id,
            spaceID: spaceID,
            creatorID: creatorID,
            title: title,
            notes: notes,
            cycle: PeriodicCycle(rawValue: cycleRawValue) ?? .monthly,
            reminderRules: Self.decode(reminderRulesData, defaultValue: []),
            completions: Self.decode(completionsData, defaultValue: []),
            subtasks: Self.decode(subtasksData, defaultValue: []),
            sortOrder: sortOrder,
            isActive: isActive,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }

    func update(from task: PeriodicTask) {
        spaceID = task.spaceID
        title = task.title
        notes = task.notes
        cycleRawValue = task.cycle.rawValue
        reminderRulesData = Self.encode(task.reminderRules)
        completionsData = Self.encode(task.completions)
        subtasksData = Self.encode(task.subtasks)
        sortOrder = task.sortOrder
        isActive = task.isActive
        updatedAt = task.updatedAt
    }

    private static func encode<T: Encodable>(_ value: T?) -> Data? {
        guard let value else { return nil }
        return try? JSONEncoder().encode(value)
    }

    private static func encode<T: Encodable>(_ value: T) -> Data {
        (try? JSONEncoder().encode(value)) ?? Data()
    }

    private static func decode<T: Decodable>(_ data: Data?, defaultValue: T) -> T {
        guard let data, let decoded = try? JSONDecoder().decode(T.self, from: data) else {
            return defaultValue
        }
        return decoded
    }
}
