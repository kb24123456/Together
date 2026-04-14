import Foundation

struct RemoteSyncPayload: Codable, Hashable, Sendable {
    var tasks: [Item]

    /// Task IDs that were deleted on the remote side (detected via zone change feed).
    var deletedTaskIDs: [UUID]

    nonisolated init(
        tasks: [Item] = [],
        deletedTaskIDs: [UUID] = []
    ) {
        self.tasks = tasks
        self.deletedTaskIDs = deletedTaskIDs
    }

    var totalCount: Int {
        tasks.count + deletedTaskIDs.count
    }

    nonisolated static let empty = RemoteSyncPayload()
}
