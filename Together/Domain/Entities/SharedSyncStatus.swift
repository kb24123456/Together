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
    var lastError: String?

    static let idle = SharedSyncStatus(
        level: .idle,
        lastSuccessfulSync: nil,
        pendingMutationCount: 0,
        lastError: nil
    )
}
