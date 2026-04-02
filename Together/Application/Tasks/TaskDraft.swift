import Foundation

struct TaskDraft: Hashable, Sendable {
    var title: String
    var notes: String?
    var listID: UUID?
    var projectID: UUID?
    var dueAt: Date?
    var hasExplicitTime: Bool
    var remindAt: Date?
    var priority: ItemPriority
    var executionRole: ItemExecutionRole
    var assigneeMode: TaskAssigneeMode
    var status: ItemStatus
    var assignmentState: TaskAssignmentState
    var assignmentNote: String?
    var isPinned: Bool
    var isDraft: Bool
    var repeatRule: ItemRepeatRule?

    nonisolated init(
        title: String,
        notes: String? = nil,
        listID: UUID? = nil,
        projectID: UUID? = nil,
        dueAt: Date? = nil,
        hasExplicitTime: Bool = false,
        remindAt: Date? = nil,
        priority: ItemPriority = .normal,
        executionRole: ItemExecutionRole = .initiator,
        assigneeMode: TaskAssigneeMode = .self,
        status: ItemStatus = .inProgress,
        assignmentState: TaskAssignmentState = .active,
        assignmentNote: String? = nil,
        isPinned: Bool = false,
        isDraft: Bool = false,
        repeatRule: ItemRepeatRule? = nil
    ) {
        self.title = title
        self.notes = notes
        self.listID = listID
        self.projectID = projectID
        self.dueAt = dueAt
        self.hasExplicitTime = hasExplicitTime
        self.remindAt = remindAt
        self.priority = priority
        self.executionRole = executionRole
        self.assigneeMode = assigneeMode
        self.status = status
        self.assignmentState = assignmentState
        self.assignmentNote = assignmentNote
        self.isPinned = isPinned
        self.isDraft = isDraft
        self.repeatRule = repeatRule
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
            priority: item.priority,
            executionRole: item.executionRole,
            assigneeMode: item.assigneeMode,
            status: item.status,
            assignmentState: item.assignmentState,
            assignmentNote: item.assignmentMessages.last?.body,
            isPinned: item.isPinned,
            isDraft: item.isDraft,
            repeatRule: item.repeatRule
        )
    }
}
