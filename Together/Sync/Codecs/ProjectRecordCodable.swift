import CloudKit
import Foundation

/// Bridges `Project` ↔ CKRecord.
struct ProjectRecordCodable: RecordCodable {
    static let ckRecordType = "Project"

    let project: Project

    func toCKRecord(in zoneID: CKRecordZone.ID) -> CKRecord {
        let recordID = CKRecord.ID(recordName: project.id.uuidString, zoneID: zoneID)
        let record = CKRecord(recordType: Self.ckRecordType, recordID: recordID)

        record["spaceID"] = project.spaceID.uuidString as CKRecordValue
        record["name"] = project.name as CKRecordValue
        record["notes"] = project.notes as CKRecordValue?
        record["colorToken"] = project.colorToken as CKRecordValue?
        record["status"] = project.status.rawValue as CKRecordValue
        record["targetDate"] = project.targetDate as CKRecordValue?
        record["remindAt"] = project.remindAt as CKRecordValue?
        record["createdAt"] = project.createdAt as CKRecordValue
        record["updatedAt"] = project.updatedAt as CKRecordValue
        record["completedAt"] = project.completedAt as CKRecordValue?

        return record
    }

    static func from(record: CKRecord) throws -> ProjectRecordCodable {
        let id = UUID(uuidString: record.recordID.recordName) ?? UUID()
        guard
            let spaceIDRaw = record["spaceID"] as? String,
            let spaceID = UUID(uuidString: spaceIDRaw),
            let name = record["name"] as? String,
            let statusRaw = record["status"] as? String,
            let createdAt = record["createdAt"] as? Date,
            let updatedAt = record["updatedAt"] as? Date
        else {
            throw RecordCodecError.missingField("required Project field")
        }

        let project = Project(
            id: id,
            spaceID: spaceID,
            name: name,
            notes: record["notes"] as? String,
            colorToken: record["colorToken"] as? String,
            status: ProjectStatus(rawValue: statusRaw) ?? .active,
            targetDate: record["targetDate"] as? Date,
            remindAt: record["remindAt"] as? Date,
            taskCount: 0, // Computed locally
            subtasks: [], // Synced as separate ProjectSubtask records
            createdAt: createdAt,
            updatedAt: updatedAt,
            completedAt: record["completedAt"] as? Date
        )

        return ProjectRecordCodable(project: project)
    }
}
