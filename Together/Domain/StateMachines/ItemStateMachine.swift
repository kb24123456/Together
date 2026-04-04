import Foundation

enum ItemStateMachine {
    nonisolated static func initialAssignmentState(for assigneeMode: TaskAssigneeMode) -> TaskAssignmentState {
        switch assigneeMode {
        case .self, .both:
            return .active
        case .partner:
            return .pendingResponse
        }
    }

    nonisolated static func nextAssignmentState(
        from currentState: TaskAssignmentState,
        response: ItemResponseKind? = nil,
        isCompletion: Bool = false
    ) -> TaskAssignmentState {
        if isCompletion {
            return .completed
        }

        guard let response else { return currentState }

        switch response {
        case .willing, .acknowledged:
            return .accepted
        case .notAvailableNow:
            return .snoozed
        case .notSuitable:
            return .declined
        }
    }

    nonisolated static func nextStatus(
        from currentStatus: ItemStatus,
        executionRole: ItemExecutionRole,
        response: ItemResponseKind? = nil,
        isCompletion: Bool = false
    ) -> ItemStatus {
        if isCompletion {
            return .completed
        }

        guard currentStatus == .pendingConfirmation, let response else {
            return currentStatus
        }

        switch response {
        case .willing, .acknowledged:
            return .inProgress
        case .notAvailableNow, .notSuitable:
            return .declinedOrBlocked
        }
    }
}
