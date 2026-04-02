import Foundation

struct MockRelationshipService: RelationshipServiceProtocol {
    func currentPairingContext(for userID: UUID?) async -> PairingContext {
        PairingContext(
            state: .paired,
            pairSpaceSummary: MockDataFactory.makePairSpaceSummary(),
            activeInvite: nil
        )
    }

    func createInvite(from inviterID: UUID) async throws -> Invite {
        MockDataFactory.makeInvite()
    }

    func acceptInvite(inviteID: UUID, responderID: UUID) async throws -> PairingContext {
        PairingContext(
            state: .paired,
            pairSpaceSummary: MockDataFactory.makePairSpaceSummary(),
            activeInvite: nil
        )
    }

    func declineInvite(inviteID: UUID, responderID: UUID) async throws -> PairingContext {
        PairingContext(state: .singleTrial, pairSpaceSummary: nil, activeInvite: nil)
    }

    func cancelInvite(inviteID: UUID, actorID: UUID) async throws -> PairingContext {
        PairingContext(state: .singleTrial, pairSpaceSummary: nil, activeInvite: nil)
    }

    func unbind(pairSpaceID: UUID, actorID: UUID) async throws -> PairingContext {
        PairingContext(state: .unbound, pairSpaceSummary: nil, activeInvite: nil)
    }
}
