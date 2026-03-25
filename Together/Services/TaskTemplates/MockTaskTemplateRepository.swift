import Foundation

actor MockTaskTemplateRepository: TaskTemplateRepositoryProtocol {
    private var templates: [TaskTemplate]

    init(templates: [TaskTemplate] = []) {
        self.templates = templates
    }

    func fetchTaskTemplates(spaceID: UUID?) async throws -> [TaskTemplate] {
        let filtered = templates.filter { template in
            guard let spaceID else { return true }
            return template.spaceID == spaceID
        }
        return filtered.sorted { $0.updatedAt > $1.updatedAt }
    }

    func saveTaskTemplate(_ template: TaskTemplate) async throws -> TaskTemplate {
        var saved = template
        saved.updatedAt = .now

        if let index = templates.firstIndex(where: { $0.id == template.id }) {
            templates[index] = saved
        } else {
            templates.append(saved)
        }

        return saved
    }

    func deleteTaskTemplate(templateID: UUID) async throws {
        templates.removeAll { $0.id == templateID }
    }
}
