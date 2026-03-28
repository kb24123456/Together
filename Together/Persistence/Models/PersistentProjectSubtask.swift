import Foundation
import SwiftData

@Model
final class PersistentProjectSubtask {
    var id: UUID
    var projectID: UUID
    var title: String
    var isCompleted: Bool
    var sortOrder: Int

    init(
        id: UUID,
        projectID: UUID,
        title: String,
        isCompleted: Bool,
        sortOrder: Int
    ) {
        self.id = id
        self.projectID = projectID
        self.title = title
        self.isCompleted = isCompleted
        self.sortOrder = sortOrder
    }
}

extension PersistentProjectSubtask {
    convenience init(subtask: ProjectSubtask) {
        self.init(
            id: subtask.id,
            projectID: subtask.projectID,
            title: subtask.title,
            isCompleted: subtask.isCompleted,
            sortOrder: subtask.sortOrder
        )
    }

    func domainModel() -> ProjectSubtask {
        ProjectSubtask(
            id: id,
            projectID: projectID,
            title: title,
            isCompleted: isCompleted,
            sortOrder: sortOrder
        )
    }

    func update(from subtask: ProjectSubtask) {
        title = subtask.title
        isCompleted = subtask.isCompleted
        sortOrder = subtask.sortOrder
    }
}
