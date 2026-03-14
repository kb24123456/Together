import Foundation

protocol AnniversaryRepositoryProtocol: Sendable {
    func fetchAnniversaries(spaceID: UUID?) async throws -> [Anniversary]
}
