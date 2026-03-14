import Foundation

struct MockAnniversaryRepository: AnniversaryRepositoryProtocol {
    func fetchAnniversaries(spaceID: UUID?) async throws -> [Anniversary] {
        MockDataFactory.makeAnniversaries()
            .filter { $0.spaceID == spaceID }
            .sorted { $0.eventDate < $1.eventDate }
    }
}
