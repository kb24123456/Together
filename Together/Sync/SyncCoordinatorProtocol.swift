import Foundation

enum SyncEntityKind: String, Codable, Hashable, Sendable {
    case task
    case taskList
    case project
    case space
}

enum SyncOperationKind: String, Codable, Hashable, Sendable {
    case upsert
    case complete
    case archive
    case delete
}

struct SyncChange: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    let entityKind: SyncEntityKind
    let operation: SyncOperationKind
    let recordID: UUID
    let spaceID: UUID
    let changedAt: Date

    init(
        id: UUID = UUID(),
        entityKind: SyncEntityKind,
        operation: SyncOperationKind,
        recordID: UUID,
        spaceID: UUID,
        changedAt: Date = .now
    ) {
        self.id = id
        self.entityKind = entityKind
        self.operation = operation
        self.recordID = recordID
        self.spaceID = spaceID
        self.changedAt = changedAt
    }
}

struct SyncCursor: Codable, Hashable, Sendable {
    let token: String
    let updatedAt: Date
}

struct SyncPushResult: Codable, Hashable, Sendable {
    let pushedCount: Int
    let cursor: SyncCursor?
}

struct SyncPullResult: Codable, Hashable, Sendable {
    let cursor: SyncCursor?
    let changedRecordIDs: [UUID]
    let payload: RemoteSyncPayload

    init(
        cursor: SyncCursor?,
        changedRecordIDs: [UUID],
        payload: RemoteSyncPayload = .empty
    ) {
        self.cursor = cursor
        self.changedRecordIDs = changedRecordIDs
        self.payload = payload
    }
}

protocol SyncCoordinatorProtocol: Sendable {
    func recordLocalChange(_ change: SyncChange) async
    func pendingChanges() async -> [SyncChange]
    func clearPendingChanges(recordIDs: [UUID]) async
    func syncState(for spaceID: UUID) async -> SyncState?
    func markPushSuccess(
        for spaceID: UUID,
        cursor: SyncCursor?,
        clearedRecordIDs: [UUID],
        syncedAt: Date
    ) async
    func markSyncFailure(
        for spaceID: UUID,
        errorMessage: String,
        failedAt: Date
    ) async
}
