import Foundation
import TogetherCore

nonisolated extension PersistentTaskSubtask {
    convenience init(subtask: TaskSubtask) {
        self.init(
            id: subtask.id,
            itemID: subtask.itemID,
            creatorID: subtask.creatorID,
            title: subtask.title,
            isCompleted: subtask.isCompleted,
            sortOrder: subtask.sortOrder,
            updatedAt: subtask.updatedAt,
            sourceTaskID: subtask.sourceTaskID,
            sourceNotes: subtask.sourceNotes,
            sourceDueAt: subtask.sourceDueAt,
            sourceHasExplicitTime: subtask.sourceHasExplicitTime,
            sourceRemindAt: subtask.sourceRemindAt,
            sourceCreatedAt: subtask.sourceCreatedAt,
            sourceCompletedAt: subtask.sourceCompletedAt
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
            updatedAt: updatedAt,
            sourceTaskID: sourceTaskID,
            sourceNotes: sourceNotes,
            sourceDueAt: sourceDueAt,
            sourceHasExplicitTime: sourceHasExplicitTime,
            sourceRemindAt: sourceRemindAt,
            sourceCreatedAt: sourceCreatedAt,
            sourceCompletedAt: sourceCompletedAt
        )
    }

    func update(from subtask: TaskSubtask) {
        itemID = subtask.itemID
        creatorID = subtask.creatorID
        title = subtask.title
        isCompleted = subtask.isCompleted
        sortOrder = subtask.sortOrder
        updatedAt = subtask.updatedAt
        sourceTaskID = subtask.sourceTaskID
        sourceNotes = subtask.sourceNotes
        sourceDueAt = subtask.sourceDueAt
        sourceHasExplicitTime = subtask.sourceHasExplicitTime
        sourceRemindAt = subtask.sourceRemindAt
        sourceCreatedAt = subtask.sourceCreatedAt
        sourceCompletedAt = subtask.sourceCompletedAt
        isLocallyDeleted = false
    }
}
