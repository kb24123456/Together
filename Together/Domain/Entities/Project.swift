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
    let creatorID: UUID
    var name: String
    var notes: String?
    var colorToken: String?
    var status: ProjectStatus
    var targetDate: Date?
    var remindAt: Date?
    var taskCount: Int
    var subtasks: [ProjectSubtask]
    let createdAt: Date
    var updatedAt: Date
    var completedAt: Date?

    nonisolated init(
        id: UUID,
        spaceID: UUID,
        creatorID: UUID,
        name: String,
        notes: String?,
        colorToken: String?,
        status: ProjectStatus,
        targetDate: Date?,
        remindAt: Date?,
        taskCount: Int,
        subtasks: [ProjectSubtask] = [],
        createdAt: Date,
        updatedAt: Date,
        completedAt: Date?
    ) {
        self.id = id
        self.spaceID = spaceID
        self.creatorID = creatorID
        self.name = name
        self.notes = notes
        self.colorToken = colorToken
        self.status = status
        self.targetDate = targetDate
        self.remindAt = remindAt
        self.taskCount = taskCount
        self.subtasks = subtasks
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.completedAt = completedAt
    }
}

extension Project {
    var completedSubtaskCount: Int {
        subtasks.filter(\.isCompleted).count
    }

    var subtaskProgress: Double {
        guard subtasks.isEmpty == false else { return 0 }
        return Double(completedSubtaskCount) / Double(subtasks.count)
    }
}
