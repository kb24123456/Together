import Foundation
import SwiftData

@Model
final class PersistentProjectSubtask {
    var id: UUID
    var projectID: UUID
    var creatorID: UUID
    var title: String
    var isCompleted: Bool
    var sortOrder: Int
    var updatedAt: Date
    var isLocallyDeleted: Bool = false

    init(
        id: UUID,
        projectID: UUID,
        creatorID: UUID,
        title: String,
        isCompleted: Bool,
        sortOrder: Int,
        updatedAt: Date = .now,
        isLocallyDeleted: Bool = false
    ) {
        self.id = id
        self.projectID = projectID
        self.creatorID = creatorID
        self.title = title
        self.isCompleted = isCompleted
        self.sortOrder = sortOrder
        self.updatedAt = updatedAt
        self.isLocallyDeleted = isLocallyDeleted
    }
}

extension PersistentProjectSubtask {
    convenience init(subtask: ProjectSubtask) {
        self.init(
            id: subtask.id,
            projectID: subtask.projectID,
            creatorID: subtask.creatorID,
            title: subtask.title,
            isCompleted: subtask.isCompleted,
            sortOrder: subtask.sortOrder,
            updatedAt: subtask.updatedAt
        )
    }

    func domainModel() -> ProjectSubtask {
        ProjectSubtask(
            id: id,
            projectID: projectID,
            creatorID: creatorID,
            title: title,
            isCompleted: isCompleted,
            sortOrder: sortOrder,
            updatedAt: updatedAt
        )
    }

    func update(from subtask: ProjectSubtask) {
        title = subtask.title
        isCompleted = subtask.isCompleted
        sortOrder = subtask.sortOrder
        updatedAt = subtask.updatedAt
    }
}
