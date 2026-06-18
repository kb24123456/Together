import Foundation

struct TaskSubtask: Identifiable, Hashable, Sendable, Codable {
    let id: UUID
    let itemID: UUID
    var creatorID: UUID
    var title: String
    var isCompleted: Bool
    var sortOrder: Int
    var updatedAt: Date

    nonisolated init(
        id: UUID = UUID(),
        itemID: UUID,
        creatorID: UUID,
        title: String,
        isCompleted: Bool = false,
        sortOrder: Int,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.itemID = itemID
        self.creatorID = creatorID
        self.title = title
        self.isCompleted = isCompleted
        self.sortOrder = sortOrder
        self.updatedAt = updatedAt
    }

    nonisolated static func == (lhs: TaskSubtask, rhs: TaskSubtask) -> Bool {
        lhs.id == rhs.id
            && lhs.itemID == rhs.itemID
            && lhs.creatorID == rhs.creatorID
            && lhs.title == rhs.title
            && lhs.isCompleted == rhs.isCompleted
            && lhs.sortOrder == rhs.sortOrder
            && lhs.updatedAt == rhs.updatedAt
    }

    nonisolated func hash(into hasher: inout Hasher) {
        hasher.combine(id)
        hasher.combine(itemID)
        hasher.combine(creatorID)
        hasher.combine(title)
        hasher.combine(isCompleted)
        hasher.combine(sortOrder)
        hasher.combine(updatedAt)
    }
}

struct TaskSubtaskDraft: Identifiable, Hashable, Sendable, Codable {
    let id: UUID
    var title: String
    var isCompleted: Bool
    var sortOrder: Int

    nonisolated init(
        id: UUID = UUID(),
        title: String,
        isCompleted: Bool = false,
        sortOrder: Int = 0
    ) {
        self.id = id
        self.title = title
        self.isCompleted = isCompleted
        self.sortOrder = sortOrder
    }

    nonisolated static func == (lhs: TaskSubtaskDraft, rhs: TaskSubtaskDraft) -> Bool {
        lhs.id == rhs.id
            && lhs.title == rhs.title
            && lhs.isCompleted == rhs.isCompleted
            && lhs.sortOrder == rhs.sortOrder
    }

    nonisolated func hash(into hasher: inout Hasher) {
        hasher.combine(id)
        hasher.combine(title)
        hasher.combine(isCompleted)
        hasher.combine(sortOrder)
    }
}
