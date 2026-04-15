import Foundation

protocol ProjectRepositoryProtocol: Sendable {
    func fetchProjects(spaceID: UUID?) async throws -> [Project]
    func saveProject(_ project: Project, actorID: UUID) async throws -> Project
    func archiveProject(projectID: UUID, actorID: UUID) async throws -> Project
    func deleteProject(projectID: UUID, actorID: UUID) async throws
    func setProjectCompleted(projectID: UUID, isCompleted: Bool, actorID: UUID) async throws -> Project
    func addSubtask(projectID: UUID, title: String, isCompleted: Bool, creatorID: UUID, actorID: UUID) async throws -> Project
    func toggleSubtask(projectID: UUID, subtaskID: UUID, actorID: UUID) async throws -> Project
    func updateSubtask(projectID: UUID, subtaskID: UUID, title: String, actorID: UUID) async throws -> Project
    func deleteSubtask(projectID: UUID, subtaskID: UUID, actorID: UUID) async throws -> Project
}
