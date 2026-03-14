import Foundation

actor PlaceholderCloudSyncGateway: CloudSyncGatewayProtocol {
    func push(changes: [SyncChange], for spaceID: UUID) async throws -> SyncPushResult {
        let latestChangeDate = changes.map(\.changedAt).max() ?? .now
        let cursor = changes.isEmpty
            ? nil
            : SyncCursor(
                token: "local-\(spaceID.uuidString)-\(Int(latestChangeDate.timeIntervalSince1970))",
                updatedAt: latestChangeDate
            )

        return SyncPushResult(
            pushedCount: changes.count,
            cursor: cursor
        )
    }

    func pull(spaceID: UUID, since cursor: SyncCursor?) async throws -> SyncPullResult {
        SyncPullResult(
            cursor: cursor,
            changedRecordIDs: [],
            payload: .empty
        )
    }
}
