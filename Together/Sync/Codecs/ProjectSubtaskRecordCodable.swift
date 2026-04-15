import CloudKit
import Foundation

/// Bridges `ProjectSubtask` ↔ CKRecord.
struct ProjectSubtaskRecordCodable: RecordCodable {
    static let ckRecordType = "ProjectSubtask"

    let subtask: ProjectSubtask

    func toCKRecord(in zoneID: CKRecordZone.ID) -> CKRecord {
        let recordID = CKRecord.ID(recordName: subtask.id.uuidString, zoneID: zoneID)
        let record = CKRecord(recordType: Self.ckRecordType, recordID: recordID)

        record["projectID"] = subtask.projectID.uuidString as CKRecordValue
        record["creatorID"] = subtask.creatorID.uuidString as CKRecordValue
        record["title"] = subtask.title as CKRecordValue
        record["isCompleted"] = subtask.isCompleted as CKRecordValue
        record["sortOrder"] = subtask.sortOrder as CKRecordValue
        record["updatedAt"] = subtask.updatedAt as CKRecordValue

        return record
    }

    static func from(record: CKRecord) throws -> ProjectSubtaskRecordCodable {
        let id = UUID(uuidString: record.recordID.recordName) ?? UUID()
        guard
            let projectIDRaw = record["projectID"] as? String,
            let projectID = UUID(uuidString: projectIDRaw),
            let title = record["title"] as? String
        else {
            throw RecordCodecError.missingField("required ProjectSubtask field")
        }

        let creatorID: UUID
        if let raw = record["creatorID"] as? String, let parsed = UUID(uuidString: raw) {
            creatorID = parsed
        } else {
            creatorID = UUID()
        }

        let subtask = ProjectSubtask(
            id: id,
            projectID: projectID,
            creatorID: creatorID,
            title: title,
            isCompleted: record["isCompleted"] as? Bool ?? false,
            sortOrder: record["sortOrder"] as? Int ?? 0,
            updatedAt: record["updatedAt"] as? Date ?? .now
        )

        return ProjectSubtaskRecordCodable(subtask: subtask)
    }
}
