import Foundation
import TogetherCore

nonisolated extension PersistentProject {
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
