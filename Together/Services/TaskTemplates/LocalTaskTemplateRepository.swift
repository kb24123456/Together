import Foundation
import SwiftData

actor LocalTaskTemplateRepository: TaskTemplateRepositoryProtocol {
    private let container: ModelContainer

    init(container: ModelContainer) {
        self.container = container
    }

    func fetchTaskTemplates(spaceID: UUID?) async throws -> [TaskTemplate] {
        let context = ModelContext(container)
        let descriptor: FetchDescriptor<PersistentTaskTemplate>

        if let spaceID {
            descriptor = FetchDescriptor(
                predicate: #Predicate<PersistentTaskTemplate> { $0.spaceID == spaceID },
                sortBy: [SortDescriptor(\PersistentTaskTemplate.updatedAt, order: .reverse)]
            )
        } else {
            descriptor = FetchDescriptor(
                sortBy: [SortDescriptor(\PersistentTaskTemplate.updatedAt, order: .reverse)]
            )
        }

        return try context.fetch(descriptor).map(\.domainModel)
    }

    func saveTaskTemplate(_ template: TaskTemplate) async throws -> TaskTemplate {
        let context = ModelContext(container)
        let savedTemplate = TaskTemplate(
            id: template.id,
            spaceID: template.spaceID,
            title: template.title,
            notes: template.notes,
            listID: template.listID,
            projectID: template.projectID,
            priority: template.priority,
            isPinned: template.isPinned,
            hasExplicitTime: template.hasExplicitTime,
            time: template.time,
            reminderOffset: template.reminderOffset,
            repeatRule: template.repeatRule,
            createdAt: template.createdAt,
            updatedAt: .now
        )

        if let record = try fetchRecord(templateID: template.id, context: context) {
            record.update(from: savedTemplate)
        } else {
            context.insert(PersistentTaskTemplate(template: savedTemplate))
        }

        try context.save()
        return savedTemplate
    }

    func deleteTaskTemplate(templateID: UUID) async throws {
        let context = ModelContext(container)
        guard let record = try fetchRecord(templateID: templateID, context: context) else {
            throw RepositoryError.notFound
        }

        context.delete(record)
        try context.save()
    }

    private func fetchRecord(templateID: UUID, context: ModelContext) throws -> PersistentTaskTemplate? {
        let descriptor = FetchDescriptor<PersistentTaskTemplate>(
            predicate: #Predicate<PersistentTaskTemplate> { $0.id == templateID }
        )
        return try context.fetch(descriptor).first
    }
}
