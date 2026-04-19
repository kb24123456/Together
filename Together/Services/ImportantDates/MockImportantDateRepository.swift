import Foundation

actor MockImportantDateRepository: ImportantDateRepositoryProtocol {
    private var storage: [UUID: ImportantDate] = [:]
    private var tombstones: Set<UUID> = []

    func fetchAll(spaceID: UUID) async throws -> [ImportantDate] {
        storage.values
            .filter { $0.spaceID == spaceID && !tombstones.contains($0.id) }
            .sorted { $0.dateValue < $1.dateValue }
    }

    func fetch(id: UUID) async throws -> ImportantDate? {
        guard !tombstones.contains(id) else { return nil }
        return storage[id]
    }

    func save(_ event: ImportantDate) async throws {
        storage[event.id] = event
        tombstones.remove(event.id)
    }

    func delete(id: UUID) async throws {
        tombstones.insert(id)
    }

    func hardDelete(id: UUID) async throws {
        storage.removeValue(forKey: id)
        tombstones.remove(id)
    }
}
