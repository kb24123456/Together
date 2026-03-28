import Foundation

@MainActor
final class MockProjectRepository: ProjectRepositoryProtocol {
    private var projects: [Project] = MockDataFactory.makeProjects()
    private let reminderScheduler: ReminderSchedulerProtocol

    init(reminderScheduler: ReminderSchedulerProtocol) {
        self.reminderScheduler = reminderScheduler
    }

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
        var updatedProject = project
        updatedProject.updatedAt = MockDataFactory.now
        if let index = projects.firstIndex(where: { $0.id == project.id }) {
            projects[index] = updatedProject
        } else {
            projects.append(updatedProject)
        }
        await reminderScheduler.syncProjectReminder(for: updatedProject)
        return updatedProject
    }

    func archiveProject(projectID: UUID) async throws -> Project {
        guard let index = projects.firstIndex(where: { $0.id == projectID }) else {
            throw RepositoryError.notFound
        }

        projects[index].status = .archived
        projects[index].updatedAt = MockDataFactory.now
        await reminderScheduler.removeProjectReminder(for: projectID)
        return projects[index]
    }

    func setProjectCompleted(projectID: UUID, isCompleted: Bool) async throws -> Project {
        guard let index = projects.firstIndex(where: { $0.id == projectID }) else {
            throw RepositoryError.notFound
        }

        projects[index].status = isCompleted ? .completed : .active
        projects[index].completedAt = isCompleted ? MockDataFactory.now : nil
        projects[index].updatedAt = MockDataFactory.now
        return projects[index]
    }

    func addSubtask(projectID: UUID, title: String, isCompleted: Bool) async throws -> Project {
        guard let index = projects.firstIndex(where: { $0.id == projectID }) else {
            throw RepositoryError.notFound
        }

        let subtask = ProjectSubtask(
            projectID: projectID,
            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
            isCompleted: isCompleted,
            sortOrder: projects[index].subtasks.count
        )
        projects[index].subtasks.append(subtask)
        projects[index].taskCount = projects[index].subtasks.count
        projects[index].updatedAt = MockDataFactory.now
        normalizeProjectStatus(at: index)
        return projects[index]
    }

    func toggleSubtask(projectID: UUID, subtaskID: UUID) async throws -> Project {
        guard let projectIndex = projects.firstIndex(where: { $0.id == projectID }) else {
            throw RepositoryError.notFound
        }
        guard let subtaskIndex = projects[projectIndex].subtasks.firstIndex(where: { $0.id == subtaskID }) else {
            throw RepositoryError.notFound
        }

        projects[projectIndex].subtasks[subtaskIndex].isCompleted.toggle()
        projects[projectIndex].updatedAt = MockDataFactory.now
        normalizeProjectStatus(at: projectIndex)
        return projects[projectIndex]
    }

    func updateSubtask(projectID: UUID, subtaskID: UUID, title: String) async throws -> Project {
        guard let projectIndex = projects.firstIndex(where: { $0.id == projectID }) else {
            throw RepositoryError.notFound
        }
        guard let subtaskIndex = projects[projectIndex].subtasks.firstIndex(where: { $0.id == subtaskID }) else {
            throw RepositoryError.notFound
        }

        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else {
            throw RepositoryError.invalidInput("子任务标题不能为空")
        }

        projects[projectIndex].subtasks[subtaskIndex].title = trimmed
        projects[projectIndex].updatedAt = MockDataFactory.now
        return projects[projectIndex]
    }

    func deleteSubtask(projectID: UUID, subtaskID: UUID) async throws -> Project {
        guard let projectIndex = projects.firstIndex(where: { $0.id == projectID }) else {
            throw RepositoryError.notFound
        }

        projects[projectIndex].subtasks.removeAll { $0.id == subtaskID }
        for index in projects[projectIndex].subtasks.indices {
            projects[projectIndex].subtasks[index].sortOrder = index
        }
        projects[projectIndex].taskCount = projects[projectIndex].subtasks.count
        projects[projectIndex].updatedAt = MockDataFactory.now
        normalizeProjectStatus(at: projectIndex)
        return projects[projectIndex]
    }

    private func normalizeProjectStatus(at index: Int) {
        guard projects[index].subtasks.isEmpty == false else { return }

        if projects[index].subtasks.allSatisfy(\.isCompleted) {
            projects[index].status = .completed
            projects[index].completedAt = MockDataFactory.now
        } else if projects[index].status == .completed {
            projects[index].status = .active
            projects[index].completedAt = nil
        }
    }
}
