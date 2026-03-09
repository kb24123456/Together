import Foundation

protocol RelationshipServiceProtocol: Sendable {
    func currentBindingContext(for userID: UUID?) async -> BindingContext
    func createInvite(from inviterID: UUID) async throws -> Invite
    func unbind(pairSpaceID: UUID) async throws
}
