import Foundation

struct ProjectSubtask: Identifiable, Hashable, Sendable {
    let id: UUID
    let projectID: UUID
    var title: String
    var isCompleted: Bool
    var sortOrder: Int

    nonisolated init(
        id: UUID = UUID(),
        projectID: UUID,
        title: String,
        isCompleted: Bool = false,
        sortOrder: Int
    ) {
        self.id = id
        self.projectID = projectID
        self.title = title
        self.isCompleted = isCompleted
        self.sortOrder = sortOrder
    }
}
