import Foundation

enum ProjectStatus: String, CaseIterable, Hashable, Sendable, Codable {
    case active
    case onHold
    case completed
    case archived
}

struct Project: Identifiable, Hashable, Sendable {
    let id: UUID
    var spaceID: UUID
    var name: String
    var notes: String?
    var colorToken: String?
    var status: ProjectStatus
    var targetDate: Date?
    var remindAt: Date?
    var priority: ItemPriority
    var taskCount: Int
    let createdAt: Date
    var updatedAt: Date
    var completedAt: Date?

    nonisolated init(
        id: UUID,
        spaceID: UUID,
        name: String,
        notes: String?,
        colorToken: String?,
        status: ProjectStatus,
        targetDate: Date?,
        remindAt: Date?,
        priority: ItemPriority,
        taskCount: Int,
        createdAt: Date,
        updatedAt: Date,
        completedAt: Date?
    ) {
        self.id = id
        self.spaceID = spaceID
        self.name = name
        self.notes = notes
        self.colorToken = colorToken
        self.status = status
        self.targetDate = targetDate
        self.remindAt = remindAt
        self.priority = priority
        self.taskCount = taskCount
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.completedAt = completedAt
    }
}
