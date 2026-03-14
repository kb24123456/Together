import Foundation

enum SyncOrchestratorError: Error, Equatable {
    case remoteChangesNotSupported(Int)
}

actor DefaultSyncOrchestrator: SyncOrchestratorProtocol {
    private let syncCoordinator: SyncCoordinatorProtocol
    private let cloudGateway: CloudSyncGatewayProtocol
    private let remoteSyncApplier: RemoteSyncApplierProtocol

    init(
        syncCoordinator: SyncCoordinatorProtocol,
        cloudGateway: CloudSyncGatewayProtocol,
        remoteSyncApplier: RemoteSyncApplierProtocol
    ) {
        self.syncCoordinator = syncCoordinator
        self.cloudGateway = cloudGateway
        self.remoteSyncApplier = remoteSyncApplier
    }

    func sync(spaceID: UUID) async throws -> SyncRunResult {
        let pendingChanges = await syncCoordinator.pendingChanges()
            .filter { $0.spaceID == spaceID }
            .sorted { $0.changedAt < $1.changedAt }
        let currentState = await syncCoordinator.syncState(for: spaceID)
        let syncedAt = Date.now

        do {
            let pushResult: SyncPushResult
            if pendingChanges.isEmpty {
                pushResult = SyncPushResult(pushedCount: 0, cursor: currentState?.cursor)
            } else {
                pushResult = try await cloudGateway.push(changes: pendingChanges, for: spaceID)
            }

            let latestCursor = pushResult.cursor ?? currentState?.cursor
            let pullResult = try await cloudGateway.pull(spaceID: spaceID, since: latestCursor)
            let appliedRemoteChanges = try await remoteSyncApplier.apply(pullResult.payload, in: spaceID)

            guard pullResult.changedRecordIDs.isEmpty || appliedRemoteChanges == pullResult.changedRecordIDs.count else {
                throw SyncOrchestratorError.remoteChangesNotSupported(pullResult.changedRecordIDs.count)
            }

            let finalCursor = pullResult.cursor ?? latestCursor
            await syncCoordinator.markPushSuccess(
                for: spaceID,
                cursor: finalCursor,
                clearedRecordIDs: pendingChanges.map(\.recordID),
                syncedAt: syncedAt
            )

            return SyncRunResult(
                spaceID: spaceID,
                pendingCountBeforeSync: pendingChanges.count,
                pushedCount: pushResult.pushedCount,
                pulledCount: appliedRemoteChanges,
                cursor: finalCursor
            )
        } catch {
            await syncCoordinator.markSyncFailure(
                for: spaceID,
                errorMessage: syncFailureMessage(for: error),
                failedAt: syncedAt
            )
            throw error
        }
    }

    private func syncFailureMessage(for error: Error) -> String {
        switch error {
        case SyncOrchestratorError.remoteChangesNotSupported:
            return "Remote apply pipeline not implemented"
        default:
            return String(describing: error)
        }
    }
}
