import Foundation

enum DecisionStateMachine {
    static func nextStatus(from votes: [DecisionVote], participantCount: Int) -> DecisionStatus {
        guard votes.count >= participantCount else {
            return .pendingResponse
        }

        if votes.allSatisfy({ $0.value == .agree }) {
            return .consensusReached
        }

        return .noConsensusYet
    }
}
