import Foundation

protocol CloudSyncGatewayProtocol: Sendable {
    func push(changes: [SyncChange], for spaceID: UUID) async throws -> SyncPushResult
    func pull(spaceID: UUID, since cursor: SyncCursor?) async throws -> SyncPullResult
}
