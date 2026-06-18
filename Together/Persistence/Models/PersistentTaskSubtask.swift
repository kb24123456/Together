import Foundation
import SwiftData

@Model
final class PersistentTaskSubtask {
    var id: UUID = UUID()
    var itemID: UUID = UUID()
    var creatorID: UUID = UUID()
    var title: String = ""
    var isCompleted: Bool = false
    var sortOrder: Int = 0
    var updatedAt: Date = Date.now
    var isLocallyDeleted: Bool = false

    init(
        id: UUID,
        itemID: UUID,
        creatorID: UUID,
        title: String,
        isCompleted: Bool,
        sortOrder: Int,
        updatedAt: Date = Date.now,
        isLocallyDeleted: Bool = false
    ) {
        self.id = id
        self.itemID = itemID
        self.creatorID = creatorID
        self.title = title
        self.isCompleted = isCompleted
        self.sortOrder = sortOrder
        self.updatedAt = updatedAt
        self.isLocallyDeleted = isLocallyDeleted
    }
}

extension PersistentTaskSubtask {
    convenience init(subtask: TaskSubtask) {
        self.init(
            id: subtask.id,
            itemID: subtask.itemID,
            creatorID: subtask.creatorID,
            title: subtask.title,
            isCompleted: subtask.isCompleted,
            sortOrder: subtask.sortOrder,
            updatedAt: subtask.updatedAt
        )
    }

    func domainModel() -> TaskSubtask {
        TaskSubtask(
            id: id,
            itemID: itemID,
            creatorID: creatorID,
            title: title,
            isCompleted: isCompleted,
            sortOrder: sortOrder,
            updatedAt: updatedAt
        )
    }

    func update(from subtask: TaskSubtask) {
        itemID = subtask.itemID
        creatorID = subtask.creatorID
        title = subtask.title
        isCompleted = subtask.isCompleted
        sortOrder = subtask.sortOrder
        updatedAt = subtask.updatedAt
        isLocallyDeleted = false
    }
}
