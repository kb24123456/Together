import Foundation
import TogetherCore

nonisolated extension PersistentProjectSubtask {
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
