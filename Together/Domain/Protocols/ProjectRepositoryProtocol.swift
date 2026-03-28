import Foundation

protocol ProjectRepositoryProtocol: Sendable {
    func fetchProjects(spaceID: UUID?) async throws -> [Project]
    func saveProject(_ project: Project) async throws -> Project
    func archiveProject(projectID: UUID) async throws -> Project
    func setProjectCompleted(projectID: UUID, isCompleted: Bool) async throws -> Project
    func addSubtask(projectID: UUID, title: String, isCompleted: Bool) async throws -> Project
    func toggleSubtask(projectID: UUID, subtaskID: UUID) async throws -> Project
    func updateSubtask(projectID: UUID, subtaskID: UUID, title: String) async throws -> Project
    func deleteSubtask(projectID: UUID, subtaskID: UUID) async throws -> Project
}
