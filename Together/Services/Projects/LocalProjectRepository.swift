import Foundation
import SwiftData

actor LocalProjectRepository: ProjectRepositoryProtocol {
    private let container: ModelContainer
    private let reminderScheduler: ReminderSchedulerProtocol

    init(container: ModelContainer, reminderScheduler: ReminderSchedulerProtocol) {
        self.container = container
        self.reminderScheduler = reminderScheduler
    }

    func fetchProjects(spaceID: UUID?) async throws -> [Project] {
        let context = ModelContext(container)
        let descriptor: FetchDescriptor<PersistentProject>

        if let spaceID {
            descriptor = FetchDescriptor(
                predicate: #Predicate<PersistentProject> { $0.spaceID == spaceID },
                sortBy: [SortDescriptor(\PersistentProject.updatedAt, order: .reverse)]
            )
        } else {
            descriptor = FetchDescriptor(
                sortBy: [SortDescriptor(\PersistentProject.updatedAt, order: .reverse)]
            )
        }

        let projects = try context.fetch(descriptor)
        let subtasksByProject = try subtasksByProject(in: context, projectIDs: projects.map(\.id))

        return projects.map { project in
            let subtasks = subtasksByProject[project.id, default: []]
            return project.domainModel(taskCount: subtasks.count).withSubtasks(subtasks)
        }
    }

    func saveProject(_ project: Project) async throws -> Project {
        let context = ModelContext(container)
        var savedProject = project
        savedProject.updatedAt = .now

        if let record = try fetchRecord(projectID: project.id, context: context) {
            record.update(from: savedProject)
        } else {
            context.insert(PersistentProject(project: savedProject))
        }

        try context.save()
        let subtasks = try self.subtasks(for: savedProject.id, in: context)
        let projectWithCount = savedProject.withSubtasks(subtasks)
        await reminderScheduler.syncProjectReminder(for: projectWithCount)
        return projectWithCount
    }

    func archiveProject(projectID: UUID) async throws -> Project {
        let context = ModelContext(container)
        guard let record = try fetchRecord(projectID: projectID, context: context) else {
            throw RepositoryError.notFound
        }

        record.statusRawValue = ProjectStatus.archived.rawValue
        record.updatedAt = .now
        try context.save()

        let subtasks = try subtasks(for: record.id, in: context)
        let archivedProject = record.domainModel(taskCount: subtasks.count).withSubtasks(subtasks)
        await reminderScheduler.removeProjectReminder(for: archivedProject.id)
        return archivedProject
    }

    func deleteProject(projectID: UUID) async throws {
        let context = ModelContext(container)
        guard let record = try fetchRecord(projectID: projectID, context: context) else {
            throw RepositoryError.notFound
        }

        let subtaskDescriptor = FetchDescriptor<PersistentProjectSubtask>(
            predicate: #Predicate<PersistentProjectSubtask> { $0.projectID == projectID }
        )
        let subtaskRecords = try context.fetch(subtaskDescriptor)
        for subtaskRecord in subtaskRecords {
            context.delete(subtaskRecord)
        }
        context.delete(record)
        try context.save()

        await reminderScheduler.removeProjectReminder(for: projectID)
    }

    func setProjectCompleted(projectID: UUID, isCompleted: Bool) async throws -> Project {
        let context = ModelContext(container)
        guard let record = try fetchRecord(projectID: projectID, context: context) else {
            throw RepositoryError.notFound
        }

        record.statusRawValue = isCompleted ? ProjectStatus.completed.rawValue : ProjectStatus.active.rawValue
        record.completedAt = isCompleted ? .now : nil
        record.updatedAt = .now
        try context.save()

        let subtasks = try subtasks(for: projectID, in: context)
        let project = record.domainModel(taskCount: subtasks.count).withSubtasks(subtasks)
        await syncReminder(for: project)
        return project
    }

    func addSubtask(projectID: UUID, title: String, isCompleted: Bool) async throws -> Project {
        let context = ModelContext(container)
        guard let record = try fetchRecord(projectID: projectID, context: context) else {
            throw RepositoryError.notFound
        }

        let existingSubtasks = try subtasks(for: projectID, in: context)
        let subtask = ProjectSubtask(
            projectID: projectID,
            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
            isCompleted: isCompleted,
            sortOrder: existingSubtasks.count
        )
        context.insert(PersistentProjectSubtask(subtask: subtask))

        if isCompleted == false, record.statusRawValue == ProjectStatus.completed.rawValue {
            record.statusRawValue = ProjectStatus.active.rawValue
            record.completedAt = nil
        }
        record.updatedAt = .now

        try context.save()
        return try await finalizedProject(projectID: projectID, context: context)
    }

    func toggleSubtask(projectID: UUID, subtaskID: UUID) async throws -> Project {
        let context = ModelContext(container)
        guard let record = try fetchRecord(projectID: projectID, context: context) else {
            throw RepositoryError.notFound
        }
        guard let subtaskRecord = try fetchSubtaskRecord(subtaskID: subtaskID, context: context) else {
            throw RepositoryError.notFound
        }

        subtaskRecord.isCompleted.toggle()
        record.updatedAt = .now
        try normalizeProjectStatus(record: record, context: context)
        try context.save()

        return try await finalizedProject(projectID: projectID, context: context)
    }

    func updateSubtask(projectID: UUID, subtaskID: UUID, title: String) async throws -> Project {
        let context = ModelContext(container)
        guard let record = try fetchRecord(projectID: projectID, context: context) else {
            throw RepositoryError.notFound
        }
        guard let subtaskRecord = try fetchSubtaskRecord(subtaskID: subtaskID, context: context) else {
            throw RepositoryError.notFound
        }

        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else {
            throw RepositoryError.invalidInput("子任务标题不能为空")
        }

        subtaskRecord.title = trimmed
        record.updatedAt = .now
        try context.save()

        return try await finalizedProject(projectID: projectID, context: context)
    }

    func deleteSubtask(projectID: UUID, subtaskID: UUID) async throws -> Project {
        let context = ModelContext(container)
        guard let record = try fetchRecord(projectID: projectID, context: context) else {
            throw RepositoryError.notFound
        }
        guard let subtaskRecord = try fetchSubtaskRecord(subtaskID: subtaskID, context: context) else {
            throw RepositoryError.notFound
        }

        context.delete(subtaskRecord)
        record.updatedAt = .now
        try context.save()

        try resequenceSubtasks(projectID: projectID, context: context)
        try normalizeProjectStatus(record: record, context: context)
        try context.save()

        return try await finalizedProject(projectID: projectID, context: context)
    }

    private func fetchRecord(projectID: UUID, context: ModelContext) throws -> PersistentProject? {
        let descriptor = FetchDescriptor<PersistentProject>(
            predicate: #Predicate<PersistentProject> { $0.id == projectID }
        )
        return try context.fetch(descriptor).first
    }

    private func fetchSubtaskRecord(subtaskID: UUID, context: ModelContext) throws -> PersistentProjectSubtask? {
        let descriptor = FetchDescriptor<PersistentProjectSubtask>(
            predicate: #Predicate<PersistentProjectSubtask> { $0.id == subtaskID }
        )
        return try context.fetch(descriptor).first
    }

    private func subtasksByProject(
        in context: ModelContext,
        projectIDs: [UUID]
    ) throws -> [UUID: [ProjectSubtask]] {
        let allSubtasks = try context.fetch(
            FetchDescriptor<PersistentProjectSubtask>(
                sortBy: [SortDescriptor(\PersistentProjectSubtask.sortOrder, order: .forward)]
            )
        )

        let projectIDSet = Set(projectIDs)
        return allSubtasks.reduce(into: [:]) { result, subtask in
            guard projectIDSet.contains(subtask.projectID) else { return }
            result[subtask.projectID, default: []].append(subtask.domainModel())
        }
    }

    private func subtasks(for projectID: UUID, in context: ModelContext) throws -> [ProjectSubtask] {
        let descriptor = FetchDescriptor<PersistentProjectSubtask>(
            predicate: #Predicate<PersistentProjectSubtask> { $0.projectID == projectID },
            sortBy: [SortDescriptor(\PersistentProjectSubtask.sortOrder, order: .forward)]
        )
        return try context.fetch(descriptor).map { $0.domainModel() }
    }

    private func resequenceSubtasks(projectID: UUID, context: ModelContext) throws {
        let descriptor = FetchDescriptor<PersistentProjectSubtask>(
            predicate: #Predicate<PersistentProjectSubtask> { $0.projectID == projectID },
            sortBy: [SortDescriptor(\PersistentProjectSubtask.sortOrder, order: .forward)]
        )
        let records = try context.fetch(descriptor)
        for (index, record) in records.enumerated() {
            record.sortOrder = index
        }
    }

    private func normalizeProjectStatus(record: PersistentProject, context: ModelContext) throws {
        let subtasks = try subtasks(for: record.id, in: context)
        guard subtasks.isEmpty == false else { return }

        if subtasks.allSatisfy(\.isCompleted) {
            record.statusRawValue = ProjectStatus.completed.rawValue
            record.completedAt = .now
        } else if record.statusRawValue == ProjectStatus.completed.rawValue {
            record.statusRawValue = ProjectStatus.active.rawValue
            record.completedAt = nil
        }
    }

    private func finalizedProject(projectID: UUID, context: ModelContext) async throws -> Project {
        guard let record = try fetchRecord(projectID: projectID, context: context) else {
            throw RepositoryError.notFound
        }

        let subtasks = try subtasks(for: projectID, in: context)
        let project = record.domainModel(taskCount: subtasks.count).withSubtasks(subtasks)
        await syncReminder(for: project)
        return project
    }

    private func syncReminder(for project: Project) async {
        if project.status == .completed || project.status == .archived {
            await reminderScheduler.removeProjectReminder(for: project.id)
        } else {
            await reminderScheduler.syncProjectReminder(for: project)
        }
    }
}

private extension Project {
    nonisolated func withSubtasks(_ subtasks: [ProjectSubtask]) -> Project {
        Project(
            id: id,
            spaceID: spaceID,
            name: name,
            notes: notes,
            colorToken: colorToken,
            status: status,
            targetDate: targetDate,
            remindAt: remindAt,
            taskCount: subtasks.count,
            subtasks: subtasks,
            createdAt: createdAt,
            updatedAt: updatedAt,
            completedAt: completedAt
        )
    }
}
