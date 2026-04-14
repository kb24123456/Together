import CloudKit
import Foundation

/// Bridges `PeriodicTask` ↔ CKRecord.
///
/// Complex nested types (reminderRules, completions)
/// are stored as JSON strings in the CKRecord.
struct PeriodicTaskRecordCodable: RecordCodable {
    static let ckRecordType = "PeriodicTask"

    let periodicTask: PeriodicTask

    func toCKRecord(in zoneID: CKRecordZone.ID) -> CKRecord {
        let recordID = CKRecord.ID(recordName: periodicTask.id.uuidString, zoneID: zoneID)
        let record = CKRecord(recordType: Self.ckRecordType, recordID: recordID)

        record["spaceID"] = periodicTask.spaceID?.uuidString as CKRecordValue?
        record["creatorID"] = periodicTask.creatorID.uuidString as CKRecordValue
        record["title"] = periodicTask.title as CKRecordValue
        record["notes"] = periodicTask.notes as CKRecordValue?
        record["cycle"] = periodicTask.cycle.rawValue as CKRecordValue
        record["sortOrder"] = periodicTask.sortOrder as CKRecordValue
        record["isActive"] = periodicTask.isActive as CKRecordValue
        record["createdAt"] = periodicTask.createdAt as CKRecordValue
        record["updatedAt"] = periodicTask.updatedAt as CKRecordValue

        // JSON-encoded arrays
        record["reminderRulesJSON"] = (try? RecordJSON.encode(periodicTask.reminderRules)) as CKRecordValue?
        record["completionsJSON"] = (try? RecordJSON.encode(periodicTask.completions)) as CKRecordValue?

        return record
    }

    static func from(record: CKRecord) throws -> PeriodicTaskRecordCodable {
        let id = UUID(uuidString: record.recordID.recordName) ?? UUID()
        guard
            let creatorIDRaw = record["creatorID"] as? String,
            let creatorID = UUID(uuidString: creatorIDRaw),
            let title = record["title"] as? String,
            let cycleRaw = record["cycle"] as? String,
            let createdAt = record["createdAt"] as? Date,
            let updatedAt = record["updatedAt"] as? Date
        else {
            throw RecordCodecError.missingField("required PeriodicTask field")
        }

        let reminderRulesJSON = (record["reminderRulesJSON"] as? String) ?? "[]"
        let completionsJSON = (record["completionsJSON"] as? String) ?? "[]"

        let periodicTask = PeriodicTask(
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

        return PeriodicTaskRecordCodable(periodicTask: periodicTask)
    }
}
