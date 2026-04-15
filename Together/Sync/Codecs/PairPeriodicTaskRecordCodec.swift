import CloudKit
import Foundation

/// Encodes/decodes `PeriodicTask` ↔ `CKRecord` for public DB pair sync.
enum PairPeriodicTaskRecordCodec: Sendable {

    nonisolated static let recordType = "PairPeriodicTask"

    nonisolated static func encode(_ task: PeriodicTask) -> CKRecord {
        let recordID = CKRecord.ID(recordName: task.id.uuidString)
        let record = CKRecord(recordType: recordType, recordID: recordID)
        record["spaceID"] = task.spaceID?.uuidString as CKRecordValue?
        record["creatorID"] = task.creatorID.uuidString as CKRecordValue
        record["title"] = task.title as CKRecordValue
        record["notes"] = task.notes as CKRecordValue?
        record["cycle"] = task.cycle.rawValue as CKRecordValue
        record["sortOrder"] = task.sortOrder as CKRecordValue
        record["isActive"] = task.isActive as CKRecordValue
        record["createdAt"] = task.createdAt as CKRecordValue
        record["updatedAt"] = task.updatedAt as CKRecordValue
        record["reminderRulesJSON"] = (try? RecordJSON.encode(task.reminderRules)) as CKRecordValue?
        record["completionsJSON"] = (try? RecordJSON.encode(task.completions)) as CKRecordValue?
        record["isDeleted"] = (0 as Int64) as CKRecordValue
        record["deletedAt"] = nil as CKRecordValue?
        return record
    }

    nonisolated static func decode(_ record: CKRecord) throws -> PeriodicTask {
        let id = UUID(uuidString: record.recordID.recordName) ?? UUID()
        guard
            let creatorIDRaw = record["creatorID"] as? String,
            let creatorID = UUID(uuidString: creatorIDRaw),
            let title = record["title"] as? String,
            let cycleRaw = record["cycle"] as? String,
            let createdAt = record["createdAt"] as? Date,
            let updatedAt = record["updatedAt"] as? Date
        else {
            throw RecordCodecError.missingField("required PairPeriodicTask field")
        }

        let reminderRulesJSON = (record["reminderRulesJSON"] as? String) ?? "[]"
        let completionsJSON = (record["completionsJSON"] as? String) ?? "[]"

        return PeriodicTask(
            id: id,
            spaceID: UUID(uuidString: (record["spaceID"] as? String) ?? ""),
            creatorID: creatorID,
            title: title,
            notes: record["notes"] as? String,
            cycle: PeriodicCycle(rawValue: cycleRaw) ?? .weekly,
            reminderRules: (try? RecordJSON.decode(reminderRulesJSON, as: [PeriodicReminderRule].self)) ?? [],
            completions: (try? RecordJSON.decode(completionsJSON, as: [PeriodicCompletion].self)) ?? [],
            sortOrder: record["sortOrder"] as? Double ?? 0,
            isActive: record["isActive"] as? Bool ?? true,
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
