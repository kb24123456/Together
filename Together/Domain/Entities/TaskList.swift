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
}
