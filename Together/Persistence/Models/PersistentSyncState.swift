import Foundation
import SwiftData

@Model
final class PersistentSyncState {
    var spaceID: UUID
    var cursorToken: String?
    var cursorUpdatedAt: Date?
    var lastSyncedAt: Date?
    var lastError: String?
    var retryCount: Int
    var updatedAt: Date

    /// Serialized CKServerChangeToken for incremental zone fetches.
    @Attribute(.externalStorage)
    var serverChangeTokenData: Data?

    init(state: SyncState) {
        self.spaceID = state.spaceID
        self.cursorToken = state.cursor?.token
        self.cursorUpdatedAt = state.cursor?.updatedAt
        self.lastSyncedAt = state.lastSyncedAt
        self.lastError = state.lastError
        self.retryCount = state.retryCount
        self.updatedAt = state.updatedAt
        self.serverChangeTokenData = state.cursor?.serverChangeTokenData
    }

    var domainModel: SyncState {
        let cursor: SyncCursor? = cursorToken.map {
            SyncCursor(
                token: $0,
                updatedAt: cursorUpdatedAt ?? updatedAt,
                serverChangeTokenData: serverChangeTokenData
            )
        }
        return SyncState(
            spaceID: spaceID,
            cursor: cursor,
            lastSyncedAt: lastSyncedAt,
            lastError: lastError,
            retryCount: retryCount,
            updatedAt: updatedAt
        )
    }

    func update(from state: SyncState) {
        cursorToken = state.cursor?.token
        cursorUpdatedAt = state.cursor?.updatedAt
        lastSyncedAt = state.lastSyncedAt
        lastError = state.lastError
        retryCount = state.retryCount
        updatedAt = state.updatedAt
        serverChangeTokenData = state.cursor?.serverChangeTokenData
    }
}
