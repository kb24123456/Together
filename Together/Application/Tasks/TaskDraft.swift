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
    var status: ItemStatus
    var isPinned: Bool
    var isDraft: Bool
    var repeatRule: ItemRepeatRule?

    init(
        title: String,
        notes: String? = nil,
        listID: UUID? = nil,
        projectID: UUID? = nil,
        dueAt: Date? = nil,
        hasExplicitTime: Bool = false,
        remindAt: Date? = nil,
        priority: ItemPriority = .normal,
        executionRole: ItemExecutionRole = .initiator,
        status: ItemStatus = .inProgress,
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
        self.status = status
        self.isPinned = isPinned
        self.isDraft = isDraft
        self.repeatRule = repeatRule
    }
}

extension TaskDraft {
    init(item: Item) {
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
            status: item.status,
            isPinned: item.isPinned,
            isDraft: item.isDraft,
            repeatRule: item.repeatRule
        )
    }
}
