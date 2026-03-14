import Foundation

struct SyncRunResult: Hashable, Sendable {
    let spaceID: UUID
    let pendingCountBeforeSync: Int
    let pushedCount: Int
    let pulledCount: Int
    let cursor: SyncCursor?
}

protocol SyncOrchestratorProtocol: Sendable {
    func sync(spaceID: UUID) async throws -> SyncRunResult
}
