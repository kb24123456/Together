import Foundation

actor NoOpSyncCoordinator: SyncCoordinatorProtocol {
    func recordLocalChange(_ change: SyncChange) async {}

    func pendingChanges() async -> [SyncChange] {
        []
    }

    func mutationLog(for spaceID: UUID) async -> [SyncMutationSnapshot] {
        _ = spaceID
        return []
    }

    func clearPendingChanges(recordIDs: [UUID]) async {}

    func syncState(for spaceID: UUID) async -> SyncState? {
        nil
    }

    func markPushSuccess(
        for spaceID: UUID,
        cursor: SyncCursor?,
        clearedRecordIDs: [UUID],
        syncedAt: Date
    ) async {}

    func markSyncFailure(
        for spaceID: UUID,
        errorMessage: String,
        failedAt: Date
    ) async {}
}
