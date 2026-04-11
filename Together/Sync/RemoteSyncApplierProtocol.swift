import Foundation

protocol RemoteSyncApplierProtocol: Sendable {
    func apply(_ payload: RemoteSyncPayload, in spaceID: UUID, localPendingRecordIDs: Set<UUID>) async throws -> Int
}
