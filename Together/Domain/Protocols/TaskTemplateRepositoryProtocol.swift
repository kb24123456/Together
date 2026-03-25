import Foundation

protocol TaskTemplateRepositoryProtocol: Sendable {
    func fetchTaskTemplates(spaceID: UUID?) async throws -> [TaskTemplate]
    func saveTaskTemplate(_ template: TaskTemplate) async throws -> TaskTemplate
    func deleteTaskTemplate(templateID: UUID) async throws
}
