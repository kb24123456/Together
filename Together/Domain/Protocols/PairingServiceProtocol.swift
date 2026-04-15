import Foundation

protocol PairingServiceProtocol: Sendable {
    func currentPairingContext(for userID: UUID?) async -> PairingContext
    func createInvite(from inviterID: UUID, displayName: String) async throws -> Invite
    func acceptInvite(inviteID: UUID, responderID: UUID) async throws -> PairingContext
    func acceptInviteByCode(_ code: String, responderID: UUID, responderDisplayName: String) async throws -> PairingContext
    func declineInvite(inviteID: UUID, responderID: UUID) async throws -> PairingContext
    func cancelInvite(inviteID: UUID, actorID: UUID) async throws -> PairingContext
    /// Cancel ALL pending invites for a user and reset to singleTrial.
    func cancelAllPendingInvites(for userID: UUID) async throws -> PairingContext
    func updatePairSpaceDisplayName(pairSpaceID: UUID, displayName: String?, actorID: UUID) async
    func unbind(pairSpaceID: UUID, actorID: UUID) async throws -> PairingContext
    /// Device A: check if pending invite was accepted on Device B and finalize local state.
    func checkAndFinalizeIfAccepted(pairSpaceID: UUID, inviterID: UUID) async throws -> PairingContext?
}

typealias RelationshipServiceProtocol = PairingServiceProtocol
