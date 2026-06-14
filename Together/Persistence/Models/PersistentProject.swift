import Foundation
import SwiftData

@Model
final class PersistentProject {
    var id: UUID = UUID()
    var spaceID: UUID = UUID()
    var creatorID: UUID = UUID()
    var name: String = ""
    var notes: String?
    var colorToken: String?
    var statusRawValue: String = ProjectStatus.active.rawValue
    var targetDate: Date?
    var remindAt: Date?
    var sortOrder: Double = 0
    var createdAt: Date = Date.now
    var updatedAt: Date = Date.now
    var completedAt: Date?
    var isLocallyDeleted: Bool = false

    init(
        id: UUID,
        spaceID: UUID,
        creatorID: UUID = UUID(),
        name: String,
        notes: String?,
        colorToken: String?,
        statusRawValue: String,
        targetDate: Date?,
        remindAt: Date?,
        sortOrder: Double = 0,
        createdAt: Date,
        updatedAt: Date,
        completedAt: Date?,
        isLocallyDeleted: Bool = false
    ) {
        self.id = id
        self.spaceID = spaceID
        self.creatorID = creatorID
        self.name = name
        self.notes = notes
        self.colorToken = colorToken
        self.statusRawValue = statusRawValue
        self.targetDate = targetDate
        self.remindAt = remindAt
        self.sortOrder = sortOrder
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.completedAt = completedAt
        self.isLocallyDeleted = isLocallyDeleted
    }
}

extension PersistentProject {
    convenience init(project: Project) {
        self.init(
            id: project.id,
            spaceID: project.spaceID,
            creatorID: project.creatorID,
            name: project.name,
            notes: project.notes,
            colorToken: project.colorToken,
            statusRawValue: project.status.rawValue,
            targetDate: project.targetDate,
            remindAt: project.remindAt,
            sortOrder: project.sortOrder,
            createdAt: project.createdAt,
            updatedAt: project.updatedAt,
            completedAt: project.completedAt
        )
    }

    func domainModel(taskCount: Int) -> Project {
        Project(
            id: id,
            spaceID: spaceID,
            creatorID: creatorID,
            name: name,
            notes: notes,
            colorToken: colorToken,
            status: ProjectStatus(rawValue: statusRawValue) ?? .active,
            targetDate: targetDate,
            remindAt: remindAt,
            taskCount: taskCount,
            subtasks: [],
            sortOrder: sortOrder,
            createdAt: createdAt,
            updatedAt: updatedAt,
            completedAt: completedAt
        )
    }

    func update(from project: Project) {
        spaceID = project.spaceID
        creatorID = project.creatorID
        name = project.name
        notes = project.notes
        colorToken = project.colorToken
        statusRawValue = project.status.rawValue
        targetDate = project.targetDate
        remindAt = project.remindAt
        sortOrder = project.sortOrder
        updatedAt = project.updatedAt
        completedAt = project.completedAt
    }
}
