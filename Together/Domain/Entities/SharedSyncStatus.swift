import Foundation

enum SyncHealthLevel: String, Hashable, Sendable {
    case idle
    case syncing
    case healthy
    case degraded
}

struct SharedSyncStatus: Hashable, Sendable {
    var level: SyncHealthLevel
    var lastSuccessfulSync: Date?
    var pendingMutationCount: Int
    var failedMutationCount: Int
    var lastError: String?
    var lastSendError: String?
    var lastFetchError: String?

    static let idle = SharedSyncStatus(
        level: .idle,
        lastSuccessfulSync: nil,
        pendingMutationCount: 0,
        failedMutationCount: 0,
        lastError: nil,
        lastSendError: nil,
        lastFetchError: nil
    )
}

struct SharedMutationRecordKey: Hashable, Sendable {
    let entityKind: SyncEntityKind
    let recordID: UUID
}

enum SharedMutationDisplayState: Hashable, Sendable {
    case syncing
    case confirmed
    case failed

    static let confirmationVisibilityWindow: TimeInterval = 6

    var text: String {
        switch self {
        case .syncing:
            return "同步中"
        case .confirmed:
            return "已同步"
        case .failed:
            return "同步失败"
        }
    }

    static func resolve(
        from snapshot: SyncMutationSnapshot,
        now: Date = .now
    ) -> SharedMutationDisplayState? {
        switch snapshot.lifecycleState {
        case .pending, .sending:
            return .syncing
        case .failed:
            return .failed
        case .confirmed:
            guard let confirmedAt = snapshot.confirmedAt else { return nil }
            return now.timeIntervalSince(confirmedAt) <= confirmationVisibilityWindow ? .confirmed : nil
        }
    }
}
