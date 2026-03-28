import Foundation

enum TaskListKind: String, CaseIterable, Hashable, Sendable, Codable {
    case systemInbox
    case systemToday
    case systemUpcoming
    case custom
}

struct TaskList: Identifiable, Hashable, Sendable {
    let id: UUID
    var spaceID: UUID
    var name: String
    var kind: TaskListKind
    var colorToken: String?
    var sortOrder: Double
    var isArchived: Bool
    var taskCount: Int
    let createdAt: Date
    var updatedAt: Date

    nonisolated init(
        id: UUID,
        spaceID: UUID,
        name: String,
        kind: TaskListKind,
        colorToken: String?,
        sortOrder: Double,
        isArchived: Bool,
        taskCount: Int,
        createdAt: Date,
        updatedAt: Date
    ) {
        self.id = id
        self.spaceID = spaceID
        self.name = name
        self.kind = kind
        self.colorToken = colorToken
        self.sortOrder = sortOrder
        self.isArchived = isArchived
        self.taskCount = taskCount
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
