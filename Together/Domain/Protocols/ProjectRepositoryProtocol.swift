import Foundation

protocol ProjectRepositoryProtocol: Sendable {
    func fetchProjects(spaceID: UUID?) async throws -> [Project]
    func saveProject(_ project: Project) async throws -> Project
    func archiveProject(projectID: UUID) async throws -> Project
}
