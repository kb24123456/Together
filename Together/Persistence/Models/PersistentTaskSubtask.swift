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
    var sourceTaskID: UUID?
    var sourceNotes: String?
    var sourceDueAt: Date?
    var sourceHasExplicitTime: Bool = false
    var sourceRemindAt: Date?
    var sourceCreatedAt: Date?
    var sourceCompletedAt: Date?
    var isLocallyDeleted: Bool = false

    init(
        id: UUID,
        itemID: UUID,
        creatorID: UUID,
        title: String,
        isCompleted: Bool,
        sortOrder: Int,
        updatedAt: Date = Date.now,
        sourceTaskID: UUID? = nil,
        sourceNotes: String? = nil,
        sourceDueAt: Date? = nil,
        sourceHasExplicitTime: Bool = false,
        sourceRemindAt: Date? = nil,
        sourceCreatedAt: Date? = nil,
        sourceCompletedAt: Date? = nil,
        isLocallyDeleted: Bool = false
    ) {
        self.id = id
        self.itemID = itemID
        self.creatorID = creatorID
        self.title = title
        self.isCompleted = isCompleted
        self.sortOrder = sortOrder
        self.updatedAt = updatedAt
        self.sourceTaskID = sourceTaskID
        self.sourceNotes = sourceNotes
        self.sourceDueAt = sourceDueAt
        self.sourceHasExplicitTime = sourceHasExplicitTime
        self.sourceRemindAt = sourceRemindAt
        self.sourceCreatedAt = sourceCreatedAt
        self.sourceCompletedAt = sourceCompletedAt
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
