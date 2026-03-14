import Foundation

protocol RemoteSyncApplierProtocol: Sendable {
    func apply(_ payload: RemoteSyncPayload, in spaceID: UUID) async throws -> Int
}
