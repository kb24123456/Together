import Foundation
import TogetherCore

nonisolated extension PersistentPeriodicTask {
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
            deferredUntil: task.deferredUntil,
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
            deferredUntil: deferredUntil,
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
        deferredUntil = task.deferredUntil
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
