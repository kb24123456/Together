import Foundation
import SwiftData

@Model
final class PersistentProject {
    var id: UUID
    var spaceID: UUID
    var name: String
    var notes: String?
    var colorToken: String?
    var statusRawValue: String
    var targetDate: Date?
    var remindAt: Date?
    var priorityRawValue: String
    var createdAt: Date
    var updatedAt: Date
    var completedAt: Date?

    init(
        id: UUID,
        spaceID: UUID,
        name: String,
        notes: String?,
        colorToken: String?,
        statusRawValue: String,
        targetDate: Date?,
        remindAt: Date?,
        priorityRawValue: String,
        createdAt: Date,
        updatedAt: Date,
        completedAt: Date?
    ) {
        self.id = id
        self.spaceID = spaceID
        self.name = name
        self.notes = notes
        self.colorToken = colorToken
        self.statusRawValue = statusRawValue
        self.targetDate = targetDate
        self.remindAt = remindAt
        self.priorityRawValue = priorityRawValue
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.completedAt = completedAt
    }
}

extension PersistentProject {
    convenience init(project: Project) {
        self.init(
            id: project.id,
            spaceID: project.spaceID,
            name: project.name,
            notes: project.notes,
            colorToken: project.colorToken,
            statusRawValue: project.status.rawValue,
            targetDate: project.targetDate,
            remindAt: project.remindAt,
            priorityRawValue: project.priority.rawValue,
            createdAt: project.createdAt,
            updatedAt: project.updatedAt,
            completedAt: project.completedAt
        )
    }

    func domainModel(taskCount: Int) -> Project {
        Project(
            id: id,
            spaceID: spaceID,
            name: name,
            notes: notes,
            colorToken: colorToken,
            status: ProjectStatus(rawValue: statusRawValue) ?? .active,
            targetDate: targetDate,
            remindAt: remindAt,
            priority: ItemPriority(rawValue: priorityRawValue) ?? .normal,
            taskCount: taskCount,
            subtasks: [],
            createdAt: createdAt,
            updatedAt: updatedAt,
            completedAt: completedAt
        )
    }

    func update(from project: Project) {
        spaceID = project.spaceID
        name = project.name
        notes = project.notes
        colorToken = project.colorToken
        statusRawValue = project.status.rawValue
        targetDate = project.targetDate
        remindAt = project.remindAt
        priorityRawValue = project.priority.rawValue
        updatedAt = project.updatedAt
        completedAt = project.completedAt
    }
}
