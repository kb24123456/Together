import Foundation

struct MockRelationshipService: RelationshipServiceProtocol {
    func currentPairingContext(for userID: UUID?) async -> PairingContext {
        PairingContext(
            state: .paired,
            pairSpaceSummary: MockDataFactory.makePairSpaceSummary(),
            activeInvite: nil
        )
    }

    func createInvite(from inviterID: UUID, displayName: String) async throws -> Invite {
        MockDataFactory.makeInvite()
    }

    func acceptInviteByCode(_ code: String, responderID: UUID, responderDisplayName: String) async throws -> PairingContext {
        PairingContext(
            state: .paired,
            pairSpaceSummary: MockDataFactory.makePairSpaceSummary(),
            activeInvite: nil
        )
    }

    func checkAndFinalizeIfAccepted(pairSpaceID: UUID, inviterID: UUID) async throws -> PairingContext? {
        nil
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

    func cancelAllPendingInvites(for userID: UUID) async throws -> PairingContext {
        PairingContext(state: .singleTrial, pairSpaceSummary: nil, activeInvite: nil)
    }

    func updatePairSpaceDisplayName(pairSpaceID: UUID, displayName: String?, actorID: UUID) async {}

    func unbind(pairSpaceID: UUID, actorID: UUID) async throws -> PairingContext {
        PairingContext(state: .unbound, pairSpaceSummary: nil, activeInvite: nil)
    }
}
