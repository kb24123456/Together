import Foundation
import SwiftData

actor LocalImportantDateRepository: ImportantDateRepositoryProtocol {
    private let modelContainer: ModelContainer
    private let syncCoordinator: SyncCoordinatorProtocol?

    init(modelContainer: ModelContainer, syncCoordinator: SyncCoordinatorProtocol? = nil) {
        self.modelContainer = modelContainer
        self.syncCoordinator = syncCoordinator
    }

    func fetchAll(spaceID: UUID) async throws -> [ImportantDate] {
        let context = ModelContext(modelContainer)
        let descriptor = FetchDescriptor<PersistentImportantDate>(
            predicate: #Predicate {
                $0.spaceID == spaceID && $0.isLocallyDeleted == false
            },
            sortBy: [SortDescriptor(\.dateValue)]
        )
        let rows = try context.fetch(descriptor)
        return rows.map { $0.domainModel() }
    }

    func fetch(id: UUID) async throws -> ImportantDate? {
        let context = ModelContext(modelContainer)
        let descriptor = FetchDescriptor<PersistentImportantDate>(
            predicate: #Predicate { $0.id == id && $0.isLocallyDeleted == false }
        )
        return try context.fetch(descriptor).first?.domainModel()
    }

    func save(_ event: ImportantDate) async throws {
        let context = ModelContext(modelContainer)
        let eventID = event.id
        let descriptor = FetchDescriptor<PersistentImportantDate>(
            predicate: #Predicate { $0.id == eventID }
        )
        if let existing = try context.fetch(descriptor).first {
            existing.apply(from: event)
        } else {
            context.insert(PersistentImportantDate.make(from: event))
        }
        try context.save()
        await syncCoordinator?.recordLocalChange(
            SyncChange(entityKind: .importantDate, operation: .upsert,
                       recordID: event.id, spaceID: event.spaceID)
        )
    }

    func delete(id: UUID) async throws {
        let context = ModelContext(modelContainer)
        let descriptor = FetchDescriptor<PersistentImportantDate>(
            predicate: #Predicate { $0.id == id }
        )
        guard let existing = try context.fetch(descriptor).first else { return }
        existing.isLocallyDeleted = true
        existing.deletedAt = .now
        existing.updatedAt = .now
        let spaceID = existing.spaceID
        try context.save()
        await syncCoordinator?.recordLocalChange(
            SyncChange(entityKind: .importantDate, operation: .delete,
                       recordID: id, spaceID: spaceID)
        )
    }

    func hardDelete(id: UUID) async throws {
        let context = ModelContext(modelContainer)
        let descriptor = FetchDescriptor<PersistentImportantDate>(
            predicate: #Predicate { $0.id == id }
        )
        if let existing = try context.fetch(descriptor).first {
            context.delete(existing)
            try context.save()
        }
    }
}
