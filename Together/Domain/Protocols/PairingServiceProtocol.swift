import Foundation

protocol PairingServiceProtocol: Sendable {
    func currentPairingContext(for userID: UUID?) async -> PairingContext
    func createInvite(from inviterID: UUID) async throws -> Invite
    func acceptInvite(inviteID: UUID, responderID: UUID) async throws -> PairingContext
    func declineInvite(inviteID: UUID, responderID: UUID) async throws -> PairingContext
    func cancelInvite(inviteID: UUID, actorID: UUID) async throws -> PairingContext
    func unbind(pairSpaceID: UUID, actorID: UUID) async throws -> PairingContext
}

typealias RelationshipServiceProtocol = PairingServiceProtocol
