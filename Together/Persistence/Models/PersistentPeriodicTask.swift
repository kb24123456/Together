import Foundation
import SwiftData

@Model
final class PersistentPeriodicTask {
    var id: UUID = UUID()
    var spaceID: UUID?
    var creatorID: UUID = UUID()
    var title: String = ""
    var notes: String?
    var cycleRawValue: String = PeriodicCycle.monthly.rawValue
    var reminderRulesData: Data?
    var completionsData: Data = Data()
    var sortOrder: Double = 0
    var isActive: Bool = true
    var createdAt: Date = Date.now
    var updatedAt: Date = Date.now
    var isLocallyDeleted: Bool = false

    init(
        id: UUID,
        spaceID: UUID?,
        creatorID: UUID,
        title: String,
        notes: String?,
        cycleRawValue: String,
        reminderRulesData: Data?,
        completionsData: Data,
        sortOrder: Double,
        isActive: Bool,
        createdAt: Date,
        updatedAt: Date,
        isLocallyDeleted: Bool = false
    ) {
        self.id = id
        self.spaceID = spaceID
        self.creatorID = creatorID
        self.title = title
        self.notes = notes
        self.cycleRawValue = cycleRawValue
        self.reminderRulesData = reminderRulesData
        self.completionsData = completionsData
        self.sortOrder = sortOrder
        self.isActive = isActive
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.isLocallyDeleted = isLocallyDeleted
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
