import Foundation

enum TaskCreationPersistenceResult: Equatable, Sendable {
    case saved(UUID)
    case failed(message: String)
}

struct TaskDraft: Hashable, Sendable {
    var title: String
    var notes: String?
    var listID: UUID?
    var projectID: UUID?
    var dueAt: Date?
    var hasExplicitTime: Bool
    var remindAt: Date?
    var status: ItemStatus
    var isUrgent: Bool
    var shouldFollowOnCreation: Bool
    var isDraft: Bool
    var subtasks: [TaskSubtaskDraft]

    nonisolated init(
        title: String,
        notes: String? = nil,
        listID: UUID? = nil,
        projectID: UUID? = nil,
        dueAt: Date? = nil,
        hasExplicitTime: Bool = false,
        remindAt: Date? = nil,
        status: ItemStatus = .inProgress,
        isUrgent: Bool = false,
        shouldFollowOnCreation: Bool = false,
        isDraft: Bool = false,
        subtasks: [TaskSubtaskDraft] = []
    ) {
        self.title = title
        self.notes = notes
        self.listID = listID
        self.projectID = projectID
        self.dueAt = dueAt
        self.hasExplicitTime = hasExplicitTime
        self.remindAt = remindAt
        self.status = status
        self.isUrgent = isUrgent
        self.shouldFollowOnCreation = shouldFollowOnCreation
        self.isDraft = isDraft
        self.subtasks = subtasks
    }
}

extension TaskDraft {
    nonisolated init(item: Item) {
        self.init(
            title: item.title,
            notes: item.notes,
            listID: item.listID,
            projectID: item.projectID,
            dueAt: item.dueAt,
            hasExplicitTime: item.hasExplicitTime,
            remindAt: item.remindAt,
            status: item.status,
            isUrgent: item.isUrgent,
            isDraft: item.isDraft,
            subtasks: item.subtasks.map {
                TaskSubtaskDraft(
                    id: $0.id,
                    title: $0.title,
                    isCompleted: $0.isCompleted,
                    sortOrder: $0.sortOrder,
                    sourceTaskID: $0.sourceTaskID,
                    sourceNotes: $0.sourceNotes,
                    sourceDueAt: $0.sourceDueAt,
                    sourceHasExplicitTime: $0.sourceHasExplicitTime,
                    sourceRemindAt: $0.sourceRemindAt,
                    sourceCreatedAt: $0.sourceCreatedAt,
                    sourceCompletedAt: $0.sourceCompletedAt
                )
            }
        )
    }
}
