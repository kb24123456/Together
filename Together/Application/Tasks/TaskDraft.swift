import Foundation

struct TaskDraft: Hashable, Sendable {
    var title: String
    var notes: String?
    var listID: UUID?
    var projectID: UUID?
    var dueAt: Date?
    var hasExplicitTime: Bool
    var remindAt: Date?
    var status: ItemStatus
    var isPinned: Bool
    var isDraft: Bool
    var repeatRule: ItemRepeatRule?
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
        isPinned: Bool = false,
        isDraft: Bool = false,
        repeatRule: ItemRepeatRule? = nil,
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
        self.isPinned = isPinned
        self.isDraft = isDraft
        self.repeatRule = repeatRule
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
            isPinned: item.isPinned,
            isDraft: item.isDraft,
            repeatRule: item.repeatRule,
            subtasks: item.subtasks.map {
                TaskSubtaskDraft(
                    id: $0.id,
                    title: $0.title,
                    isCompleted: $0.isCompleted,
                    sortOrder: $0.sortOrder
                )
            }
        )
    }
}
