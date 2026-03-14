import Foundation

@MainActor
final class MockProjectRepository: ProjectRepositoryProtocol {
    private var projects: [Project] = MockDataFactory.makeProjects()

    func fetchProjects(spaceID: UUID?) async throws -> [Project] {
        projects
            .filter { $0.spaceID == spaceID }
            .sorted { lhs, rhs in
                if lhs.status == rhs.status {
                    return lhs.updatedAt > rhs.updatedAt
                }
                return lhs.createdAt < rhs.createdAt
            }
    }

    func saveProject(_ project: Project) async throws -> Project {
        if let index = projects.firstIndex(where: { $0.id == project.id }) {
            projects[index] = project
        } else {
            projects.append(project)
        }
        return project
    }

    func archiveProject(projectID: UUID) async throws -> Project {
        guard let index = projects.firstIndex(where: { $0.id == projectID }) else {
            throw RepositoryError.notFound
        }

        projects[index].status = .archived
        projects[index].updatedAt = MockDataFactory.now
        return projects[index]
    }
}
