import Foundation

struct RemoteSyncPayload: Codable, Hashable, Sendable {
    var tasks: [Item]

    init(tasks: [Item] = []) {
        self.tasks = tasks
    }

    var totalCount: Int {
        tasks.count
    }

    static let empty = RemoteSyncPayload()
}
