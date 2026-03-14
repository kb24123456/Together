import Foundation
import Observation

@MainActor
@Observable
final class ProjectsViewModel {
    private let sessionStore: SessionStore
    private let projectRepository: ProjectRepositoryProtocol

    var loadState: LoadableState = .idle
    var projects: [Project] = []

    init(sessionStore: SessionStore, projectRepository: ProjectRepositoryProtocol) {
        self.sessionStore = sessionStore
        self.projectRepository = projectRepository
    }

    var activeProjects: [Project] {
        projects.filter { $0.status == .active || $0.status == .onHold }
    }

    var archivedProjects: [Project] {
        projects.filter { $0.status == .completed || $0.status == .archived }
    }

    func load() async {
        loadState = .loading

        do {
            projects = try await projectRepository.fetchProjects(spaceID: sessionStore.currentSpace?.id)
            loadState = .loaded
        } catch {
            loadState = .failed(error.localizedDescription)
        }
    }
}
