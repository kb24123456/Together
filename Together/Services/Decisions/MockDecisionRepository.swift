import Foundation

@MainActor
final class MockDecisionRepository: DecisionRepositoryProtocol {
    private var decisions: [Decision] = MockDataFactory.makeDecisions()

    func fetchDecisions(spaceID: UUID?) async throws -> [Decision] {
        decisions
            .filter { $0.spaceID == spaceID }
            .sorted { $0.updatedAt > $1.updatedAt }
    }

    func submitVote(decisionID: UUID, voterID: UUID, value: DecisionVoteValue) async throws -> Decision {
        guard let index = decisions.firstIndex(where: { $0.id == decisionID }) else {
            throw RepositoryError.notFound
        }

        var decision = decisions[index]
        if let voteIndex = decision.votes.firstIndex(where: { $0.voterID == voterID }) {
            decision.votes[voteIndex].value = value
            decision.votes[voteIndex].respondedAt = MockDataFactory.now
        } else {
            decision.votes.append(DecisionVote(voterID: voterID, value: value, respondedAt: MockDataFactory.now))
        }

        decision.status = DecisionStateMachine.nextStatus(from: decision.votes, participantCount: 2)
        decision.updatedAt = MockDataFactory.now
        decisions[index] = decision
        return decision
    }

    func archive(decisionID: UUID) async throws -> Decision {
        guard let index = decisions.firstIndex(where: { $0.id == decisionID }) else {
            throw RepositoryError.notFound
        }

        var decision = decisions[index]
        decision.status = .archived
        decision.archivedAt = MockDataFactory.now
        decision.updatedAt = MockDataFactory.now
        decisions[index] = decision
        return decision
    }

    func convertToItem(decisionID: UUID, actorID: UUID) async throws -> Decision {
        guard let index = decisions.firstIndex(where: { $0.id == decisionID }) else {
            throw RepositoryError.notFound
        }

        var decision = decisions[index]
        decision.convertedItemID = UUID()
        decision.updatedAt = MockDataFactory.now
        decisions[index] = decision
        return decision
    }
}
