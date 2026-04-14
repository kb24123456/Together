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
