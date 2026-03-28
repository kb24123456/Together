import Foundation

struct RemoteSyncPayload: Codable, Hashable, Sendable {
    var tasks: [Item]

    nonisolated init(tasks: [Item] = []) {
        self.tasks = tasks
    }

    var totalCount: Int {
        tasks.count
    }

    nonisolated static let empty = RemoteSyncPayload()
}
