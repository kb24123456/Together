import Foundation

actor MockImportantDateRepository: ImportantDateRepositoryProtocol {
    private var storage: [UUID: ImportantDateStoredRecord] = [:]
    private var tombstones: Set<UUID> = []

    func fetchAll(spaceID: UUID) async throws -> [ImportantDate] {
        let records = try await fetchAllStoredRecords(spaceID: spaceID)
        return records.map(\.event)
    }

    func fetchAllStoredRecords(spaceID: UUID) async throws -> [ImportantDateStoredRecord] {
        storage.values
            .filter { $0.event.spaceID == spaceID && !tombstones.contains($0.id) }
            .sorted {
                if $0.event.dateValue == $1.event.dateValue {
                    return $0.createdAt > $1.createdAt
                }
                return $0.event.dateValue < $1.event.dateValue
            }
    }

    func fetch(id: UUID) async throws -> ImportantDate? {
        guard !tombstones.contains(id) else { return nil }
        return storage[id]?.event
    }

    func save(_ event: ImportantDate) async throws {
        let createdAt = storage[event.id]?.createdAt ?? Date()
        storage[event.id] = ImportantDateStoredRecord(event: event, createdAt: createdAt)
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
