import Foundation

struct MockSpaceService: SpaceServiceProtocol {
    func currentSpaceContext(for userID: UUID?) async -> SpaceContext {
        let currentSpace = MockDataFactory.makeSingleSpace()
        return SpaceContext(
            singleSpace: currentSpace,
            activeMode: .single,
            availableModes: [.single]
        )
    }

    func createSingleSpace(for userID: UUID) async throws -> Space {
        MockDataFactory.makeSingleSpace()
    }
}
