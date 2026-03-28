import Foundation

enum ItemStateMachine {
    nonisolated static func nextStatus(
        from currentStatus: ItemStatus,
        executionRole: ItemExecutionRole,
        response: ItemResponseKind? = nil,
        isCompletion: Bool = false
    ) -> ItemStatus {
        if isCompletion, currentStatus == .inProgress {
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
