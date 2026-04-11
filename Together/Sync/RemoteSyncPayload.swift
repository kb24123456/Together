import Foundation

struct RemoteSyncPayload: Codable, Hashable, Sendable {
    var tasks: [Item]

    /// Task IDs that were deleted on the remote side (detected via zone change feed).
    var deletedTaskIDs: [UUID]

    /// Member profile updates from the remote side.
    var memberProfiles: [CloudKitProfileRecordCodec.MemberProfilePayload]

    nonisolated init(
        tasks: [Item] = [],
        deletedTaskIDs: [UUID] = [],
        memberProfiles: [CloudKitProfileRecordCodec.MemberProfilePayload] = []
    ) {
        self.tasks = tasks
        self.deletedTaskIDs = deletedTaskIDs
        self.memberProfiles = memberProfiles
    }

    var totalCount: Int {
        tasks.count + deletedTaskIDs.count + memberProfiles.count
    }

    nonisolated static let empty = RemoteSyncPayload()
}
