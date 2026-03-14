import Foundation

struct SyncState: Codable, Hashable, Sendable {
    let spaceID: UUID
    var cursor: SyncCursor?
    var lastSyncedAt: Date?
    var lastError: String?
    var retryCount: Int
    var updatedAt: Date

    nonisolated init(
        spaceID: UUID,
        cursor: SyncCursor? = nil,
        lastSyncedAt: Date? = nil,
        lastError: String? = nil,
        retryCount: Int = 0,
        updatedAt: Date = .now
    ) {
        self.spaceID = spaceID
        self.cursor = cursor
        self.lastSyncedAt = lastSyncedAt
        self.lastError = lastError
        self.retryCount = retryCount
        self.updatedAt = updatedAt
    }
}
