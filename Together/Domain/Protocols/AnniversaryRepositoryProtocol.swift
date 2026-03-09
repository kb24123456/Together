import Foundation

protocol AnniversaryRepositoryProtocol: Sendable {
    func fetchAnniversaries(relationshipID: UUID?) async throws -> [Anniversary]
}
