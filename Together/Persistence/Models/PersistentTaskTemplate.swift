import Foundation
import TogetherCore

nonisolated extension PersistentTaskTemplate {
    convenience init(template: TaskTemplate) {
        self.init(
            id: template.id,
            spaceID: template.spaceID,
            title: template.title,
            notes: template.notes,
            listID: template.listID,
            projectID: template.projectID,
            isPinned: template.isUrgent,
            hasExplicitTime: template.hasExplicitTime,
            timeData: Self.encode(template.time),
            reminderOffset: template.reminderOffset,
            repeatRuleData: nil,
            subtasksData: Self.encode(template.subtasks),
            createdAt: template.createdAt,
            updatedAt: template.updatedAt
        )
    }

    var domainModel: TaskTemplate {
        TaskTemplate(
            id: id,
            spaceID: spaceID,
            title: title,
            notes: notes,
            listID: listID,
            projectID: projectID,
            isUrgent: isPinned,
            hasExplicitTime: hasExplicitTime,
            time: Self.decode(timeData, defaultValue: nil),
            reminderOffset: reminderOffset,
            subtasks: Self.decode(subtasksData, defaultValue: []),
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }

    func update(from template: TaskTemplate) {
        spaceID = template.spaceID
        title = template.title
        notes = template.notes
        listID = template.listID
        projectID = template.projectID
        isPinned = template.isUrgent
        hasExplicitTime = template.hasExplicitTime
        timeData = Self.encode(template.time)
        reminderOffset = template.reminderOffset
        repeatRuleData = nil
        subtasksData = Self.encode(template.subtasks)
        updatedAt = template.updatedAt
    }

    private static func encode<T: Encodable>(_ value: T?) -> Data? {
        guard let value else { return nil }
        return try? JSONEncoder().encode(value)
    }

    private static func decode<T: Decodable>(_ data: Data?, defaultValue: T) -> T {
        guard let data, let decoded = try? JSONDecoder().decode(T.self, from: data) else {
            return defaultValue
        }
        return decoded
    }
}
