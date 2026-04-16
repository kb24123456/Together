import Foundation

struct ProjectSubtask: Identifiable, Hashable, Sendable, Codable {
    let id: UUID
    let projectID: UUID
    var creatorID: UUID
    var title: String
    var isCompleted: Bool
    var sortOrder: Int
    var updatedAt: Date

    nonisolated init(
        id: UUID = UUID(),
        projectID: UUID,
        creatorID: UUID,
        title: String,
        isCompleted: Bool = false,
        sortOrder: Int,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.projectID = projectID
        self.creatorID = creatorID
        self.title = title
        self.isCompleted = isCompleted
        self.sortOrder = sortOrder
        self.updatedAt = updatedAt
    }
}
