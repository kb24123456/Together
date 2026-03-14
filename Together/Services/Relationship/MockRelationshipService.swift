import Foundation

struct MockRelationshipService: RelationshipServiceProtocol {
    func currentBindingContext(for userID: UUID?) async -> BindingContext {
        BindingContext(
            state: .singleTrial,
            pairSpace: nil,
            activeInvite: nil
        )
    }

    func createInvite(from inviterID: UUID) async throws -> Invite {
        MockDataFactory.makeInvite()
    }

    func unbind(pairSpaceID: UUID) async throws {}
}
