import Foundation
import Testing
@testable import Together

struct TogetherTests {
    @Test func itemStateMachineMovesPendingToInProgressWhenPartnerAgrees() async throws {
        let next = await ItemStateMachine.nextStatus(
            from: .pendingConfirmation,
            executionRole: .recipient,
            response: .willing
        )

        #expect(next == .inProgress)
    }

    @Test func itemStateMachineMovesInProgressToCompletedWhenMarkedDone() async throws {
        let next = await ItemStateMachine.nextStatus(
            from: .inProgress,
            executionRole: .both,
            isCompletion: true
        )

        #expect(next == .completed)
    }

    @Test func decisionStateMachineRequiresBothParticipants() async throws {
        let votes = [
            DecisionVote(voterID: UUID(), value: .agree, respondedAt: .now)
        ]

        let next = await DecisionStateMachine.nextStatus(from: votes, participantCount: 2)

        #expect(next == .pendingResponse)
    }

    @Test func decisionStateMachineMarksNeutralAsNoConsensus() async throws {
        let votes = [
            DecisionVote(voterID: UUID(), value: .agree, respondedAt: .now),
            DecisionVote(voterID: UUID(), value: .neutral, respondedAt: .now)
        ]

        let next = await DecisionStateMachine.nextStatus(from: votes, participantCount: 2)

        #expect(next == .noConsensusYet)
    }
}
