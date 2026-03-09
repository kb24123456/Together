import Foundation

struct MockAnniversaryRepository: AnniversaryRepositoryProtocol {
    func fetchAnniversaries(relationshipID: UUID?) async throws -> [Anniversary] {
        MockDataFactory.makeAnniversaries()
            .filter { $0.relationshipID == relationshipID }
            .sorted { $0.eventDate < $1.eventDate }
    }
}
