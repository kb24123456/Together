import CloudKit
import Foundation

/// Unified decode result for any pair-sync entity from the public DB.
enum PairSyncDecodedEntity: Sendable {
    case task(Item)
    case taskList(TaskList)
    case project(Project)
    case projectSubtask(ProjectSubtask)
    case periodicTask(PeriodicTask)
    case space(Space)
    case memberProfile(MemberProfileRecordCodable.Profile)
    case avatarAsset(AvatarAssetRecordCodable.Asset)

    var entityKind: SyncEntityKind {
        switch self {
        case .task: .task
        case .taskList: .taskList
        case .project: .project
        case .projectSubtask: .projectSubtask
        case .periodicTask: .periodicTask
        case .space: .space
        case .memberProfile: .memberProfile
        case .avatarAsset: .avatarAsset
        }
    }
}

/// Maps `SyncEntityKind` to public-DB pair sync codecs.
/// All methods are nonisolated static to avoid actor isolation conflicts.
enum PairSyncCodecRegistry: Sendable {

    // MARK: - Soft-Delete

    nonisolated static func encodeSoftDelete(
        entityKind: SyncEntityKind,
        recordID: UUID,
        spaceID: UUID,
        at deletedAt: Date
    ) -> CKRecord? {
        switch entityKind {
        case .task:
            PairTaskRecordCodec.encodeSoftDelete(recordID: recordID, spaceID: spaceID, deletedAt: deletedAt)
        case .taskList:
            PairTaskListRecordCodec.encodeSoftDelete(recordID: recordID, spaceID: spaceID, deletedAt: deletedAt)
        case .project:
            PairProjectRecordCodec.encodeSoftDelete(recordID: recordID, spaceID: spaceID, deletedAt: deletedAt)
        case .projectSubtask:
            PairProjectSubtaskRecordCodec.encodeSoftDelete(recordID: recordID, spaceID: spaceID, deletedAt: deletedAt)
        case .periodicTask:
            PairPeriodicTaskRecordCodec.encodeSoftDelete(recordID: recordID, spaceID: spaceID, deletedAt: deletedAt)
        case .space, .memberProfile, .avatarAsset:
            nil  // These entity types are not soft-deleted
        }
    }

    // MARK: - Decode

    nonisolated static func decode(_ record: CKRecord) -> PairSyncDecodedEntity? {
        switch record.recordType {
        case PairTaskRecordCodec.recordType:
            guard let item = try? PairTaskRecordCodec.decode(record) else { return nil }
            return .task(item)
        case PairTaskListRecordCodec.recordType:
            guard let list = try? PairTaskListRecordCodec.decode(record) else { return nil }
            return .taskList(list)
        case PairProjectRecordCodec.recordType:
            guard let project = try? PairProjectRecordCodec.decode(record) else { return nil }
            return .project(project)
        case PairProjectSubtaskRecordCodec.recordType:
            guard let subtask = try? PairProjectSubtaskRecordCodec.decode(record) else { return nil }
            return .projectSubtask(subtask)
        case PairPeriodicTaskRecordCodec.recordType:
            guard let task = try? PairPeriodicTaskRecordCodec.decode(record) else { return nil }
            return .periodicTask(task)
        case PairSpaceRecordCodec.recordType:
            guard let space = try? PairSpaceRecordCodec.decode(record) else { return nil }
            return .space(space)
        case PairMemberProfileRecordCodec.recordType:
            guard let profile = try? PairMemberProfileRecordCodec.decode(record) else { return nil }
            return .memberProfile(profile)
        case PairAvatarAssetRecordCodec.recordType:
            guard let asset = try? PairAvatarAssetRecordCodec.decode(record) else { return nil }
            return .avatarAsset(asset)
        default:
            return nil
        }
    }

    /// Whether the given record represents a soft-deleted entity.
    nonisolated static func isSoftDeleted(_ record: CKRecord) -> Bool {
        (record["isDeleted"] as? Int64 ?? 0) == 1
    }

    /// CKRecord type names this registry can handle — used to build pull queries.
    nonisolated static var supportedRecordTypes: [String] {
        [
            PairTaskRecordCodec.recordType,
            PairTaskListRecordCodec.recordType,
            PairProjectRecordCodec.recordType,
            PairProjectSubtaskRecordCodec.recordType,
            PairPeriodicTaskRecordCodec.recordType,
            PairSpaceRecordCodec.recordType,
            PairMemberProfileRecordCodec.recordType,
            PairAvatarAssetRecordCodec.recordType,
        ]
    }

    /// Entity kinds this registry supports — used to filter PersistentSyncChange rows.
    nonisolated static var supportedEntityKinds: Set<SyncEntityKind> {
        [.task, .taskList, .project, .projectSubtask, .periodicTask, .space, .memberProfile, .avatarAsset]
    }
}
