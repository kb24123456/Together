import Foundation

protocol DecisionRepositoryProtocol: Sendable {
    func fetchDecisions(relationshipID: UUID?) async throws -> [Decision]
    func submitVote(decisionID: UUID, voterID: UUID, value: DecisionVoteValue) async throws -> Decision
    func archive(decisionID: UUID) async throws -> Decision
    func convertToItem(decisionID: UUID, actorID: UUID) async throws -> Decision
}
