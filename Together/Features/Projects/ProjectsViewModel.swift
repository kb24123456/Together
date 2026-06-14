import Foundation
import Observation
import SwiftUI

@MainActor
@Observable
final class ProjectsViewModel {
    private let sessionStore: SessionStore
    private let projectRepository: ProjectRepositoryProtocol

    var loadState: LoadableState = .idle
    var projects: [Project] = []

    init(
        sessionStore: SessionStore,
        projectRepository: ProjectRepositoryProtocol
    ) {
        self.sessionStore = sessionStore
        self.projectRepository = projectRepository
    }

    var activeProjects: [Project] {
        projects
            .filter { $0.status == .active || $0.status == .onHold }
            .sorted(by: projectSort)
    }

    var archivedProjects: [Project] {
        projects
            .filter { $0.status == .completed || $0.status == .archived }
            .sorted(by: projectSort)
    }

    private func projectSort(lhs: Project, rhs: Project) -> Bool {
        if lhs.sortOrder != rhs.sortOrder { return lhs.sortOrder < rhs.sortOrder }
        if lhs.updatedAt != rhs.updatedAt { return lhs.updatedAt > rhs.updatedAt }
        return lhs.id.uuidString < rhs.id.uuidString
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
        } catch {
            loadState = .failed(error.localizedDescription)
        }
    }

    func reorderProjects(_ orderedProjects: [Project], fromOffsets: IndexSet, toOffset: Int) async {
        let actorID = sessionStore.currentUser?.id ?? UUID()
        var reorderedIDs = orderedProjects.map(\.id)
        reorderedIDs.move(fromOffsets: fromOffsets, toOffset: toOffset)

        do {
            let updatedProjects = try await projectRepository.reorderProjects(
                projectIDs: reorderedIDs,
                actorID: actorID
            )
            for updated in updatedProjects {
                replaceProject(updated)
            }
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
        } catch {
            loadState = .failed(error.localizedDescription)
        }
    }

    func archiveProject(projectID: UUID) async {
        let actorID = sessionStore.currentUser?.id ?? UUID()
        do {
            let archived = try await projectRepository.archiveProject(projectID: projectID, actorID: actorID)
            replaceProject(archived)
        } catch {
            loadState = .failed(error.localizedDescription)
        }
    }

    func canDeleteProject(_ project: Project) -> Bool {
        guard let userID = sessionStore.currentUser?.id else { return true }
        return SoloPermissionService.canDeleteProject(project, actorID: userID)
            || canManageProjectAsCurrentSingleSpaceOwner(project, actorID: userID)
    }

    func canEditProject(_ project: Project) -> Bool {
        guard let userID = sessionStore.currentUser?.id else { return true }
        return SoloPermissionService.canEditProject(project, actorID: userID)
    }

    func deleteProject(projectID: UUID) async {
        let actorID = sessionStore.currentUser?.id ?? UUID()
        do {
            try await projectRepository.deleteProject(projectID: projectID, actorID: actorID)
            projects.removeAll { $0.id == projectID }
        } catch {
            loadState = .failed(error.localizedDescription)
        }
    }

    func updateProject(_ project: Project) async {
        let actorID = sessionStore.currentUser?.id ?? UUID()
        do {
            let updated = try await projectRepository.saveProject(project, actorID: actorID)
            replaceProject(updated)
        } catch {
            loadState = .failed(error.localizedDescription)
        }
    }

    /// 新建项目。
    /// 子任务由主叫方传入，成功创建后按顺序写入仓库。
    @discardableResult
    func createNew(
        _ project: Project,
        subtasks: [(title: String, isCompleted: Bool)] = []
    ) async -> Project? {
        let actorID = sessionStore.currentUser?.id ?? UUID()

        do {
            let created = try await projectRepository.saveProject(project, actorID: actorID)
            for subtask in subtasks {
                _ = try await projectRepository.addSubtask(
                    projectID: created.id,
                    title: subtask.title,
                    isCompleted: subtask.isCompleted,
                    creatorID: actorID,
                    actorID: actorID
                )
            }
            await load()
            return created
        } catch {
            loadState = .failed(error.localizedDescription)
            return nil
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

    private func canManageProjectAsCurrentSingleSpaceOwner(_ project: Project, actorID: UUID) -> Bool {
        guard let space = sessionStore.currentSpace else { return false }
        return space.id == project.spaceID
            && space.type == .single
            && space.ownerUserID == actorID
            && space.status == .active
    }
}
