import Foundation
import Observation

@MainActor
@Observable
final class ProjectsViewModel {
    private let sessionStore: SessionStore
    private let projectRepository: ProjectRepositoryProtocol

    var loadState: LoadableState = .idle
    var projects: [Project] = []

    /// Fired after Repository recordLocalChange. AppContext wires this to
    /// flushRecordedSharedMutation to trigger the Supabase push.
    var onSharedMutationRecorded: ((SyncChange) -> Void)?

    init(sessionStore: SessionStore, projectRepository: ProjectRepositoryProtocol) {
        self.sessionStore = sessionStore
        self.projectRepository = projectRepository
    }

    private func emitMutationRecorded(projectID: UUID, operation: SyncOperationKind) {
        guard let spaceID = sessionStore.currentSpace?.id else { return }
        onSharedMutationRecorded?(
            SyncChange(entityKind: .project, operation: operation, recordID: projectID, spaceID: spaceID)
        )
    }

    var activeProjects: [Project] {
        projects.filter { $0.status == .active || $0.status == .onHold }
    }

    var archivedProjects: [Project] {
        projects.filter { $0.status == .completed || $0.status == .archived }
    }

    func toggleProjectCompletion(projectID: UUID) async {
        guard let project = projects.first(where: { $0.id == projectID }) else { return }
        let actorID = sessionStore.currentUser?.id ?? UUID()

        do {
            let updated = try await projectRepository.setProjectCompleted(
                projectID: projectID,
                isCompleted: project.status != .completed,
                actorID: actorID
            )
            replaceProject(updated)
            emitMutationRecorded(projectID: projectID, operation: updated.status == .completed ? .complete : .upsert)
        } catch {
            loadState = .failed(error.localizedDescription)
        }
    }

    func addSubtask(projectID: UUID, title: String) async {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else { return }
        let creatorID = sessionStore.currentUser?.id ?? UUID()

        do {
            let updated = try await projectRepository.addSubtask(
                projectID: projectID,
                title: trimmed,
                isCompleted: false,
                creatorID: creatorID,
                actorID: creatorID
            )
            replaceProject(updated)
            emitMutationRecorded(projectID: projectID, operation: .upsert)
        } catch {
            loadState = .failed(error.localizedDescription)
        }
    }

    func toggleSubtask(projectID: UUID, subtaskID: UUID) async {
        let actorID = sessionStore.currentUser?.id ?? UUID()
        do {
            let updated = try await projectRepository.toggleSubtask(
                projectID: projectID,
                subtaskID: subtaskID,
                actorID: actorID
            )
            replaceProject(updated)
            emitMutationRecorded(projectID: projectID, operation: .upsert)
        } catch {
            loadState = .failed(error.localizedDescription)
        }
    }

    func updateSubtask(projectID: UUID, subtaskID: UUID, title: String) async {
        let actorID = sessionStore.currentUser?.id ?? UUID()
        do {
            let updated = try await projectRepository.updateSubtask(
                projectID: projectID,
                subtaskID: subtaskID,
                title: title,
                actorID: actorID
            )
            replaceProject(updated)
            emitMutationRecorded(projectID: projectID, operation: .upsert)
        } catch {
            loadState = .failed(error.localizedDescription)
        }
    }

    func deleteSubtask(projectID: UUID, subtaskID: UUID) async {
        let actorID = sessionStore.currentUser?.id ?? UUID()
        do {
            let updated = try await projectRepository.deleteSubtask(
                projectID: projectID,
                subtaskID: subtaskID,
                actorID: actorID
            )
            replaceProject(updated)
            emitMutationRecorded(projectID: projectID, operation: .upsert)
        } catch {
            loadState = .failed(error.localizedDescription)
        }
    }

    func archiveProject(projectID: UUID) async {
        let actorID = sessionStore.currentUser?.id ?? UUID()
        do {
            let archived = try await projectRepository.archiveProject(projectID: projectID, actorID: actorID)
            replaceProject(archived)
            emitMutationRecorded(projectID: projectID, operation: .archive)
        } catch {
            loadState = .failed(error.localizedDescription)
        }
    }

    func canDeleteProject(_ project: Project) -> Bool {
        guard let userID = sessionStore.currentUser?.id else { return true }
        return PairPermissionService.canDeleteProject(project, actorID: userID)
    }

    func canEditProject(_ project: Project) -> Bool {
        guard let userID = sessionStore.currentUser?.id else { return true }
        return PairPermissionService.canEditProject(project, actorID: userID)
    }

    func deleteProject(projectID: UUID) async {
        let actorID = sessionStore.currentUser?.id ?? UUID()
        do {
            try await projectRepository.deleteProject(projectID: projectID, actorID: actorID)
            projects.removeAll { $0.id == projectID }
            emitMutationRecorded(projectID: projectID, operation: .delete)
        } catch {
            loadState = .failed(error.localizedDescription)
        }
    }

    func updateProject(_ project: Project) async {
        let actorID = sessionStore.currentUser?.id ?? UUID()
        do {
            let updated = try await projectRepository.saveProject(project, actorID: actorID)
            replaceProject(updated)
            emitMutationRecorded(projectID: updated.id, operation: .upsert)
        } catch {
            loadState = .failed(error.localizedDescription)
        }
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

    private func replaceProject(_ updated: Project) {
        guard let index = projects.firstIndex(where: { $0.id == updated.id }) else {
            projects.append(updated)
            return
        }

        projects[index] = updated
    }
}
