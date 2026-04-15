import CloudKit
import Foundation

/// Encodes/decodes `ProjectSubtask` ↔ `CKRecord` for public DB pair sync.
enum PairProjectSubtaskRecordCodec: Sendable {

    nonisolated static let recordType = "PairProjectSubtask"

    nonisolated static func encode(_ subtask: ProjectSubtask, spaceID: UUID, creatorID: UUID) -> CKRecord {
        let recordID = CKRecord.ID(recordName: subtask.id.uuidString)
        let record = CKRecord(recordType: recordType, recordID: recordID)
        record["projectID"] = subtask.projectID.uuidString as CKRecordValue
        record["spaceID"] = spaceID.uuidString as CKRecordValue
        record["creatorID"] = creatorID.uuidString as CKRecordValue
        record["title"] = subtask.title as CKRecordValue
        record["isCompleted"] = subtask.isCompleted as CKRecordValue
        record["sortOrder"] = subtask.sortOrder as CKRecordValue
        record["updatedAt"] = Date.now as CKRecordValue
        record["isDeleted"] = (0 as Int64) as CKRecordValue
        record["deletedAt"] = nil as CKRecordValue?
        return record
    }

    nonisolated static func decode(_ record: CKRecord) throws -> ProjectSubtask {
        let id = UUID(uuidString: record.recordID.recordName) ?? UUID()
        guard
            let projectIDRaw = record["projectID"] as? String,
            let projectID = UUID(uuidString: projectIDRaw),
            let title = record["title"] as? String
        else {
            throw RecordCodecError.missingField("required PairProjectSubtask field")
        }

        return ProjectSubtask(
            id: id,
            projectID: projectID,
            title: title,
            isCompleted: record["isCompleted"] as? Bool ?? false,
            sortOrder: record["sortOrder"] as? Int ?? 0
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
