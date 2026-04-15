import CloudKit
import Foundation

/// Encodes/decodes `Project` ↔ `CKRecord` for public DB pair sync.
enum PairProjectRecordCodec: Sendable {

    nonisolated static let recordType = "PairProject"

    nonisolated static func encode(_ project: Project, creatorID: UUID) -> CKRecord {
        let recordID = CKRecord.ID(recordName: project.id.uuidString)
        let record = CKRecord(recordType: recordType, recordID: recordID)
        record["spaceID"] = project.spaceID.uuidString as CKRecordValue
        record["creatorID"] = creatorID.uuidString as CKRecordValue
        record["name"] = project.name as CKRecordValue
        record["notes"] = project.notes as CKRecordValue?
        record["colorToken"] = project.colorToken as CKRecordValue?
        record["status"] = project.status.rawValue as CKRecordValue
        record["targetDate"] = project.targetDate as CKRecordValue?
        record["remindAt"] = project.remindAt as CKRecordValue?
        record["createdAt"] = project.createdAt as CKRecordValue
        record["updatedAt"] = project.updatedAt as CKRecordValue
        record["completedAt"] = project.completedAt as CKRecordValue?
        record["isDeleted"] = (0 as Int64) as CKRecordValue
        record["deletedAt"] = nil as CKRecordValue?
        return record
    }

    nonisolated static func decode(_ record: CKRecord) throws -> Project {
        let id = UUID(uuidString: record.recordID.recordName) ?? UUID()
        guard
            let spaceIDRaw = record["spaceID"] as? String,
            let spaceID = UUID(uuidString: spaceIDRaw),
            let name = record["name"] as? String,
            let statusRaw = record["status"] as? String,
            let createdAt = record["createdAt"] as? Date,
            let updatedAt = record["updatedAt"] as? Date
        else {
            throw RecordCodecError.missingField("required PairProject field")
        }

        let creatorID = UUID(uuidString: (record["creatorID"] as? String) ?? "") ?? UUID()
        return Project(
            id: id,
            spaceID: spaceID,
            creatorID: creatorID,
            name: name,
            notes: record["notes"] as? String,
            colorToken: record["colorToken"] as? String,
            status: ProjectStatus(rawValue: statusRaw) ?? .active,
            targetDate: record["targetDate"] as? Date,
            remindAt: record["remindAt"] as? Date,
            taskCount: 0,
            subtasks: [],
            createdAt: createdAt,
            updatedAt: updatedAt,
            completedAt: record["completedAt"] as? Date
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
