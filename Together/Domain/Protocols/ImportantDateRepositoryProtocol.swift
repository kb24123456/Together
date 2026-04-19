import Foundation

protocol ImportantDateRepositoryProtocol: Sendable {
    func fetchAll(spaceID: UUID) async throws -> [ImportantDate]
    func fetch(id: UUID) async throws -> ImportantDate?
    func save(_ event: ImportantDate) async throws
    func delete(id: UUID) async throws
    func hardDelete(id: UUID) async throws
}
