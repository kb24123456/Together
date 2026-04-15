import CloudKit
import Foundation

/// Encodes/decodes `TaskList` ↔ `CKRecord` for public DB pair sync.
enum PairTaskListRecordCodec: Sendable {

    nonisolated static let recordType = "PairTaskList"

    nonisolated static func encode(_ taskList: TaskList, creatorID: UUID) -> CKRecord {
        let recordID = CKRecord.ID(recordName: taskList.id.uuidString)
        let record = CKRecord(recordType: recordType, recordID: recordID)
        record["spaceID"] = taskList.spaceID.uuidString as CKRecordValue
        record["creatorID"] = creatorID.uuidString as CKRecordValue
        record["name"] = taskList.name as CKRecordValue
        record["kind"] = taskList.kind.rawValue as CKRecordValue
        record["colorToken"] = taskList.colorToken as CKRecordValue?
        record["sortOrder"] = taskList.sortOrder as CKRecordValue
        record["isArchived"] = taskList.isArchived as CKRecordValue
        record["createdAt"] = taskList.createdAt as CKRecordValue
        record["updatedAt"] = taskList.updatedAt as CKRecordValue
        record["isDeleted"] = (0 as Int64) as CKRecordValue
        record["deletedAt"] = nil as CKRecordValue?
        return record
    }

    nonisolated static func decode(_ record: CKRecord) throws -> TaskList {
        let id = UUID(uuidString: record.recordID.recordName) ?? UUID()
        guard
            let spaceIDRaw = record["spaceID"] as? String,
            let spaceID = UUID(uuidString: spaceIDRaw),
            let name = record["name"] as? String,
            let kindRaw = record["kind"] as? String,
            let createdAt = record["createdAt"] as? Date,
            let updatedAt = record["updatedAt"] as? Date
        else {
            throw RecordCodecError.missingField("required PairTaskList field")
        }

        let creatorID = UUID(uuidString: (record["creatorID"] as? String) ?? "") ?? UUID()
        return TaskList(
            id: id,
            spaceID: spaceID,
            creatorID: creatorID,
            name: name,
            kind: TaskListKind(rawValue: kindRaw) ?? .custom,
            colorToken: record["colorToken"] as? String,
            sortOrder: record["sortOrder"] as? Double ?? 0,
            isArchived: record["isArchived"] as? Bool ?? false,
            taskCount: 0,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }

    nonisolated static func encodeSoftDelete(recordID: UUID, spaceID: UUID, deletedAt: Date) -> CKRecord {
        let ckRecordID = CKRecord.ID(recordName: recordID.uuidString)
        let record = CKRecord(recordType: recordType, recordID: ckRecordID)
        record["spaceID"] = spaceID.uuidString as CKRecordValue
        record["isDeleted"] = (1 as Int64) as CKRecordValue
        record["deletedAt"] = deletedAt as CKRecordValue
        record["updatedAt"] = deletedAt as CKRecordValue
        return record
    }

    nonisolated static func isSoftDeleted(_ record: CKRecord) -> Bool {
        (record["isDeleted"] as? Int64 ?? 0) == 1
    }
}
