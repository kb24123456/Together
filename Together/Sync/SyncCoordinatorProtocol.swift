import Foundation

enum SyncEntityKind: String, Codable, Hashable, Sendable {
    case task
    case taskList
    case project
    case projectSubtask
    case periodicTask
    case space
    case memberProfile
    case avatarAsset

    /// Maps entity kind to the CKRecord type used by the codec registry.
    var ckRecordType: String {
        switch self {
        case .task: return ItemRecordCodable.ckRecordType
        case .taskList: return TaskListRecordCodable.ckRecordType
        case .project: return ProjectRecordCodable.ckRecordType
        case .projectSubtask: return ProjectSubtaskRecordCodable.ckRecordType
        case .periodicTask: return PeriodicTaskRecordCodable.ckRecordType
        case .space: return SpaceRecordCodable.ckRecordType
        case .memberProfile: return MemberProfileRecordCodable.ckRecordType
        case .avatarAsset: return AvatarAssetRecordCodable.ckRecordType
        }
    }

    init?(ckRecordType: String) {
        switch ckRecordType {
        case ItemRecordCodable.ckRecordType:
            self = .task
        case TaskListRecordCodable.ckRecordType:
            self = .taskList
        case ProjectRecordCodable.ckRecordType:
            self = .project
        case ProjectSubtaskRecordCodable.ckRecordType:
            self = .projectSubtask
        case PeriodicTaskRecordCodable.ckRecordType:
            self = .periodicTask
        case SpaceRecordCodable.ckRecordType:
            self = .space
        case MemberProfileRecordCodable.ckRecordType:
            self = .memberProfile
        case AvatarAssetRecordCodable.ckRecordType:
            self = .avatarAsset
        default:
            return nil
        }
    }
}

enum SyncOperationKind: String, Codable, Hashable, Sendable {
    case upsert
    case complete
    case archive
    case delete
}

struct SyncChange: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    let entityKind: SyncEntityKind
    let operation: SyncOperationKind
    let recordID: UUID
    let spaceID: UUID
    let changedAt: Date

    init(
        id: UUID = UUID(),
        entityKind: SyncEntityKind,
        operation: SyncOperationKind,
        recordID: UUID,
        spaceID: UUID,
        changedAt: Date = .now
    ) {
        self.id = id
        self.entityKind = entityKind
        self.operation = operation
        self.recordID = recordID
        self.spaceID = spaceID
        self.changedAt = changedAt
    }
}

enum SyncMutationLifecycleState: String, Codable, Hashable, Sendable {
    case pending
    case sending
    case confirmed
    case failed
}

struct SyncMutationSnapshot: Hashable, Sendable {
    let change: SyncChange
    let lifecycleState: SyncMutationLifecycleState
    let lastAttemptedAt: Date?
    let confirmedAt: Date?
    let lastError: String?
}

struct SyncCursor: Codable, Hashable, Sendable {
    let token: String
    let updatedAt: Date

    /// Serialized CKServerChangeToken data for incremental zone fetches.
    /// When present, the sync gateway uses this instead of the legacy token string.
    var serverChangeTokenData: Data?

    nonisolated init(token: String, updatedAt: Date, serverChangeTokenData: Data? = nil) {
        self.token = token
        self.updatedAt = updatedAt
        self.serverChangeTokenData = serverChangeTokenData
    }
}

struct SyncPushResult: Codable, Hashable, Sendable {
    let pushedCount: Int
    let cursor: SyncCursor?

    nonisolated init(pushedCount: Int, cursor: SyncCursor?) {
        self.pushedCount = pushedCount
        self.cursor = cursor
    }
}

struct SyncPullResult: Codable, Hashable, Sendable {
    let cursor: SyncCursor?
    let changedRecordIDs: [UUID]
    let payload: RemoteSyncPayload

    nonisolated init(
        cursor: SyncCursor?,
        changedRecordIDs: [UUID],
        payload: RemoteSyncPayload = .empty
    ) {
        self.cursor = cursor
        self.changedRecordIDs = changedRecordIDs
        self.payload = payload
    }
}

protocol SyncCoordinatorProtocol: Sendable {
    func recordLocalChange(_ change: SyncChange) async
    func pendingChanges() async -> [SyncChange]
    func mutationLog(for spaceID: UUID) async -> [SyncMutationSnapshot]
    func clearPendingChanges(recordIDs: [UUID]) async
    func syncState(for spaceID: UUID) async -> SyncState?
    func markPushSuccess(
        for spaceID: UUID,
        cursor: SyncCursor?,
        clearedRecordIDs: [UUID],
        syncedAt: Date
    ) async
    func markSyncFailure(
        for spaceID: UUID,
        errorMessage: String,
        failedAt: Date
    ) async
}
