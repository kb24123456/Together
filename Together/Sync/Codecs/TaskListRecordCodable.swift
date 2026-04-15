import CloudKit
import Foundation

/// Bridges `TaskList` ↔ CKRecord.
struct TaskListRecordCodable: RecordCodable {
    static let ckRecordType = "TaskList"

    let taskList: TaskList

    func toCKRecord(in zoneID: CKRecordZone.ID) -> CKRecord {
        let recordID = CKRecord.ID(recordName: taskList.id.uuidString, zoneID: zoneID)
        let record = CKRecord(recordType: Self.ckRecordType, recordID: recordID)

        record["spaceID"] = taskList.spaceID.uuidString as CKRecordValue
        record["name"] = taskList.name as CKRecordValue
        record["kind"] = taskList.kind.rawValue as CKRecordValue
        record["colorToken"] = taskList.colorToken as CKRecordValue?
        record["sortOrder"] = taskList.sortOrder as CKRecordValue
        record["isArchived"] = taskList.isArchived as CKRecordValue
        record["createdAt"] = taskList.createdAt as CKRecordValue
        record["updatedAt"] = taskList.updatedAt as CKRecordValue

        return record
    }

    static func from(record: CKRecord) throws -> TaskListRecordCodable {
        let id = UUID(uuidString: record.recordID.recordName) ?? UUID()
        guard
            let spaceIDRaw = record["spaceID"] as? String,
            let spaceID = UUID(uuidString: spaceIDRaw),
            let name = record["name"] as? String,
            let kindRaw = record["kind"] as? String,
            let createdAt = record["createdAt"] as? Date,
            let updatedAt = record["updatedAt"] as? Date
        else {
            throw RecordCodecError.missingField("required TaskList field")
        }

        let taskList = TaskList(
            id: id,
            spaceID: spaceID,
            creatorID: UUID(),
            name: name,
            kind: TaskListKind(rawValue: kindRaw) ?? .custom,
            colorToken: record["colorToken"] as? String,
            sortOrder: record["sortOrder"] as? Double ?? 0,
            isArchived: record["isArchived"] as? Bool ?? false,
            taskCount: 0, // Computed locally, not synced
            createdAt: createdAt,
            updatedAt: updatedAt
        )

        return TaskListRecordCodable(taskList: taskList)
    }
}
