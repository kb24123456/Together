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
        let taskCounts = try taskCountsByProject(in: context, spaceID: spaceID)

        return projects.map { $0.domainModel(taskCount: taskCounts[$0.id, default: 0]) }
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
        let count = try taskCountsByProject(in: context, spaceID: savedProject.spaceID)[savedProject.id, default: 0]
        let projectWithCount = savedProject.withTaskCount(count)
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

        let count = try taskCountsByProject(in: context, spaceID: record.spaceID)[record.id, default: 0]
        let archivedProject = record.domainModel(taskCount: count)
        await reminderScheduler.removeProjectReminder(for: archivedProject.id)
        return archivedProject
    }

    private func fetchRecord(projectID: UUID, context: ModelContext) throws -> PersistentProject? {
        let descriptor = FetchDescriptor<PersistentProject>(
            predicate: #Predicate<PersistentProject> { $0.id == projectID }
        )
        return try context.fetch(descriptor).first
    }

    private func taskCountsByProject(in context: ModelContext, spaceID: UUID?) throws -> [UUID: Int] {
        let descriptor: FetchDescriptor<PersistentItem>

        if let spaceID {
            descriptor = FetchDescriptor(
                predicate: #Predicate<PersistentItem> { $0.spaceID == spaceID && $0.isArchived == false }
            )
        } else {
            descriptor = FetchDescriptor(
                predicate: #Predicate<PersistentItem> { $0.isArchived == false }
            )
        }

        return try context.fetch(descriptor).reduce(into: [:]) { result, item in
            guard let projectID = item.projectID else { return }
            result[projectID, default: 0] += 1
        }
    }
}

private extension Project {
    nonisolated func withTaskCount(_ count: Int) -> Project {
        Project(
            id: id,
            spaceID: spaceID,
            name: name,
            notes: notes,
            colorToken: colorToken,
            status: status,
            targetDate: targetDate,
            remindAt: remindAt,
            priority: priority,
            taskCount: count,
            createdAt: createdAt,
            updatedAt: updatedAt,
            completedAt: completedAt
        )
    }
}
