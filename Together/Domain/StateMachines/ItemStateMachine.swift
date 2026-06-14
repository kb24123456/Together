import Foundation

enum ItemStateMachine {
    nonisolated static func nextStatus(
        from currentStatus: ItemStatus,
        isCompletion: Bool = false
    ) -> ItemStatus {
        if isCompletion {
            return .completed
        }
        return currentStatus
    }
}
