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
}
