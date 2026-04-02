import Foundation

struct MockSpaceService: SpaceServiceProtocol {
    func currentSpaceContext(for userID: UUID?) async -> SpaceContext {
        let currentSpace = MockDataFactory.makeSingleSpace()
        let pairSpaceSummary = MockDataFactory.makePairSpaceSummary()
        return SpaceContext(
            singleSpace: currentSpace,
            pairSpaceSummary: pairSpaceSummary,
            activeMode: .single,
            availableModes: [.single, .pair]
        )
    }
}
