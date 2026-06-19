import Foundation

struct TaskSubtask: Identifiable, Hashable, Sendable, Codable {
    let id: UUID
    let itemID: UUID
    var creatorID: UUID
    var title: String
    var isCompleted: Bool
    var sortOrder: Int
    var updatedAt: Date
    var sourceTaskID: UUID?
    var sourceNotes: String?
    var sourceDueAt: Date?
    var sourceHasExplicitTime: Bool
    var sourceRemindAt: Date?
    var sourceCreatedAt: Date?
    var sourceCompletedAt: Date?

    nonisolated init(
        id: UUID = UUID(),
        itemID: UUID,
        creatorID: UUID,
        title: String,
        isCompleted: Bool = false,
        sortOrder: Int,
        updatedAt: Date = .now,
        sourceTaskID: UUID? = nil,
        sourceNotes: String? = nil,
        sourceDueAt: Date? = nil,
        sourceHasExplicitTime: Bool = false,
        sourceRemindAt: Date? = nil,
        sourceCreatedAt: Date? = nil,
        sourceCompletedAt: Date? = nil
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
    }

    nonisolated static func == (lhs: TaskSubtask, rhs: TaskSubtask) -> Bool {
        lhs.id == rhs.id
            && lhs.itemID == rhs.itemID
            && lhs.creatorID == rhs.creatorID
            && lhs.title == rhs.title
            && lhs.isCompleted == rhs.isCompleted
            && lhs.sortOrder == rhs.sortOrder
            && lhs.updatedAt == rhs.updatedAt
            && lhs.sourceTaskID == rhs.sourceTaskID
            && lhs.sourceNotes == rhs.sourceNotes
            && lhs.sourceDueAt == rhs.sourceDueAt
            && lhs.sourceHasExplicitTime == rhs.sourceHasExplicitTime
            && lhs.sourceRemindAt == rhs.sourceRemindAt
            && lhs.sourceCreatedAt == rhs.sourceCreatedAt
            && lhs.sourceCompletedAt == rhs.sourceCompletedAt
    }

    nonisolated func hash(into hasher: inout Hasher) {
        hasher.combine(id)
        hasher.combine(itemID)
        hasher.combine(creatorID)
        hasher.combine(title)
        hasher.combine(isCompleted)
        hasher.combine(sortOrder)
        hasher.combine(updatedAt)
        hasher.combine(sourceTaskID)
        hasher.combine(sourceNotes)
        hasher.combine(sourceDueAt)
        hasher.combine(sourceHasExplicitTime)
        hasher.combine(sourceRemindAt)
        hasher.combine(sourceCreatedAt)
        hasher.combine(sourceCompletedAt)
    }
}

struct TaskSubtaskDraft: Identifiable, Hashable, Sendable, Codable {
    let id: UUID
    var title: String
    var isCompleted: Bool
    var sortOrder: Int
    var sourceTaskID: UUID?
    var sourceNotes: String?
    var sourceDueAt: Date?
    var sourceHasExplicitTime: Bool
    var sourceRemindAt: Date?
    var sourceCreatedAt: Date?
    var sourceCompletedAt: Date?

    nonisolated init(
        id: UUID = UUID(),
        title: String,
        isCompleted: Bool = false,
        sortOrder: Int = 0,
        sourceTaskID: UUID? = nil,
        sourceNotes: String? = nil,
        sourceDueAt: Date? = nil,
        sourceHasExplicitTime: Bool = false,
        sourceRemindAt: Date? = nil,
        sourceCreatedAt: Date? = nil,
        sourceCompletedAt: Date? = nil
    ) {
        self.id = id
        self.title = title
        self.isCompleted = isCompleted
        self.sortOrder = sortOrder
        self.sourceTaskID = sourceTaskID
        self.sourceNotes = sourceNotes
        self.sourceDueAt = sourceDueAt
        self.sourceHasExplicitTime = sourceHasExplicitTime
        self.sourceRemindAt = sourceRemindAt
        self.sourceCreatedAt = sourceCreatedAt
        self.sourceCompletedAt = sourceCompletedAt
    }

    nonisolated static func == (lhs: TaskSubtaskDraft, rhs: TaskSubtaskDraft) -> Bool {
        lhs.id == rhs.id
            && lhs.title == rhs.title
            && lhs.isCompleted == rhs.isCompleted
            && lhs.sortOrder == rhs.sortOrder
            && lhs.sourceTaskID == rhs.sourceTaskID
            && lhs.sourceNotes == rhs.sourceNotes
            && lhs.sourceDueAt == rhs.sourceDueAt
            && lhs.sourceHasExplicitTime == rhs.sourceHasExplicitTime
            && lhs.sourceRemindAt == rhs.sourceRemindAt
            && lhs.sourceCreatedAt == rhs.sourceCreatedAt
            && lhs.sourceCompletedAt == rhs.sourceCompletedAt
    }

    nonisolated func hash(into hasher: inout Hasher) {
        hasher.combine(id)
        hasher.combine(title)
        hasher.combine(isCompleted)
        hasher.combine(sortOrder)
        hasher.combine(sourceTaskID)
        hasher.combine(sourceNotes)
        hasher.combine(sourceDueAt)
        hasher.combine(sourceHasExplicitTime)
        hasher.combine(sourceRemindAt)
        hasher.combine(sourceCreatedAt)
        hasher.combine(sourceCompletedAt)
    }
}
