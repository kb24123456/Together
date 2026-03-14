import Foundation

struct MockSpaceService: SpaceServiceProtocol {
    func currentSpaceContext(for userID: UUID?) async -> SpaceContext {
        let currentSpace = MockDataFactory.makeSingleSpace()
        return SpaceContext(
            currentSpace: currentSpace,
            availableSpaces: [currentSpace]
        )
    }
}
