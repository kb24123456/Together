import Foundation
import SwiftData

@Model
final class PersistentTaskTemplate {
    @Attribute(.unique) var id: UUID
    var spaceID: UUID?
    var title: String
    var notes: String?
    var listID: UUID?
    var projectID: UUID?
    var priorityRawValue: String
    var isPinned: Bool
    var hasExplicitTime: Bool
    var timeData: Data?
    var reminderOffset: TimeInterval?
    var repeatRuleData: Data?
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID,
        spaceID: UUID?,
        title: String,
        notes: String?,
        listID: UUID?,
        projectID: UUID?,
        priorityRawValue: String,
        isPinned: Bool,
        hasExplicitTime: Bool,
        timeData: Data?,
        reminderOffset: TimeInterval?,
        repeatRuleData: Data?,
        createdAt: Date,
        updatedAt: Date
    ) {
        self.id = id
        self.spaceID = spaceID
        self.title = title
        self.notes = notes
        self.listID = listID
        self.projectID = projectID
        self.priorityRawValue = priorityRawValue
        self.isPinned = isPinned
        self.hasExplicitTime = hasExplicitTime
        self.timeData = timeData
        self.reminderOffset = reminderOffset
        self.repeatRuleData = repeatRuleData
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

extension PersistentTaskTemplate {
    convenience init(template: TaskTemplate) {
        self.init(
            id: template.id,
            spaceID: template.spaceID,
            title: template.title,
            notes: template.notes,
            listID: template.listID,
            projectID: template.projectID,
            priorityRawValue: template.priority.rawValue,
            isPinned: template.isPinned,
            hasExplicitTime: template.hasExplicitTime,
            timeData: Self.encode(template.time),
            reminderOffset: template.reminderOffset,
            repeatRuleData: Self.encode(template.repeatRule),
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
            priority: ItemPriority(rawValue: priorityRawValue) ?? .normal,
            isPinned: isPinned,
            hasExplicitTime: hasExplicitTime,
            time: Self.decode(timeData, defaultValue: nil),
            reminderOffset: reminderOffset,
            repeatRule: Self.decode(repeatRuleData, defaultValue: nil),
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
        priorityRawValue = template.priority.rawValue
        isPinned = template.isPinned
        hasExplicitTime = template.hasExplicitTime
        timeData = Self.encode(template.time)
        reminderOffset = template.reminderOffset
        repeatRuleData = Self.encode(template.repeatRule)
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
