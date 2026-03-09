import Foundation

struct MockRelationshipService: RelationshipServiceProtocol {
    func currentBindingContext(for userID: UUID?) async -> BindingContext {
        BindingContext(
            state: .paired,
            pairSpace: MockDataFactory.makePairSpace(),
            activeInvite: nil
        )
    }

    func createInvite(from inviterID: UUID) async throws -> Invite {
        MockDataFactory.makeInvite()
    }

    func unbind(pairSpaceID: UUID) async throws {}
}
