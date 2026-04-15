import CloudKit
import Foundation

/// Encodes/decodes `Item` ↔ `CKRecord` for the **public** database pair sync.
///
/// Record type `"PairTask"` lives in the public DB default zone.
/// Adds `isDeleted`/`deletedAt` soft-delete fields and `occurrenceCompletionsJSON`.
enum PairTaskRecordCodec: Sendable {

    static let recordType = "PairTask"

    // MARK: - Encode

    static func encode(_ item: Item) -> CKRecord {
        let recordID = CKRecord.ID(recordName: item.id.uuidString)
        let record = CKRecord(recordType: recordType, recordID: recordID)
        populate(record, from: item)
        // Live record
        record["isDeleted"] = (0 as Int64) as CKRecordValue
        record["deletedAt"] = nil as CKRecordValue?
        return record
    }

    /// Creates a soft-delete tombstone record.
    /// Public DB cannot truly delete records created by another user,
    /// so we mark `isDeleted = 1` instead.
    static func encodeSoftDelete(recordID: UUID, spaceID: UUID, deletedAt: Date) -> CKRecord {
        let ckRecordID = CKRecord.ID(recordName: recordID.uuidString)
        let record = CKRecord(recordType: recordType, recordID: ckRecordID)
        record["spaceID"] = spaceID.uuidString as CKRecordValue
        record["isDeleted"] = (1 as Int64) as CKRecordValue
        record["deletedAt"] = deletedAt as CKRecordValue
        record["updatedAt"] = deletedAt as CKRecordValue
        return record
    }

    // MARK: - Decode

    static func decode(_ record: CKRecord) throws -> Item {
        let id = UUID(uuidString: record.recordID.recordName) ?? UUID()

        guard
            let creatorIDRaw = record["creatorID"] as? String,
            let creatorID = UUID(uuidString: creatorIDRaw),
            let title = record["title"] as? String,
            let executionRoleRaw = record["executionRole"] as? String,
            let statusRaw = record["status"] as? String,
            let createdAt = record["createdAt"] as? Date,
            let updatedAt = record["updatedAt"] as? Date
        else {
            throw RecordCodecError.missingField("required PairTask field")
        }

        let assigneeModeRaw = (record["assigneeMode"] as? String)
            ?? ItemExecutionRole(rawValue: executionRoleRaw)?.assigneeMode.rawValue
            ?? TaskAssigneeMode.`self`.rawValue

        let assignmentStateRaw = (record["assignmentState"] as? String)
            ?? ItemStatus(rawValue: statusRaw)?.assignmentState.rawValue
            ?? TaskAssignmentState.active.rawValue

        let responseHistoryJSON = (record["responseHistoryJSON"] as? String) ?? "[]"
        let assignmentMessagesJSON = (record["assignmentMessagesJSON"] as? String) ?? "[]"

        // Soft-delete flag
        let isDeleted = (record["isDeleted"] as? Int64 ?? 0) == 1
        let deletedAt = record["deletedAt"] as? Date

        let item = Item(
            id: id,
            spaceID: UUID(uuidString: (record["spaceID"] as? String) ?? ""),
            listID: UUID(uuidString: (record["listID"] as? String) ?? ""),
            projectID: UUID(uuidString: (record["projectID"] as? String) ?? ""),
            creatorID: creatorID,
            title: title,
            notes: record["notes"] as? String,
            locationText: record["locationText"] as? String,
            executionRole: ItemExecutionRole(rawValue: executionRoleRaw) ?? .initiator,
            assigneeMode: TaskAssigneeMode(rawValue: assigneeModeRaw) ?? .self,
            dueAt: record["dueAt"] as? Date,
            hasExplicitTime: record["hasExplicitTime"] as? Bool ?? false,
            remindAt: record["remindAt"] as? Date,
            status: ItemStatus(rawValue: statusRaw) ?? .pendingConfirmation,
            assignmentState: TaskAssignmentState(rawValue: assignmentStateRaw) ?? .active,
            latestResponse: try RecordJSON.decodeOptional(record["latestResponseJSON"] as? String, as: ItemResponse.self),
            responseHistory: try RecordJSON.decode(responseHistoryJSON, as: [ItemResponse].self),
            assignmentMessages: try RecordJSON.decode(assignmentMessagesJSON, as: [TaskAssignmentMessage].self),
            lastActionByUserID: UUID(uuidString: (record["lastActionByUserID"] as? String) ?? ""),
            lastActionAt: record["lastActionAt"] as? Date,
            createdAt: createdAt,
            updatedAt: updatedAt,
            completedAt: record["completedAt"] as? Date,
            occurrenceCompletions: (try? RecordJSON.decode(
                (record["occurrenceCompletionsJSON"] as? String) ?? "[]",
                as: [ItemOccurrenceCompletion].self
            )) ?? [],
            isPinned: record["isPinned"] as? Bool ?? false,
            isDraft: record["isDraft"] as? Bool ?? false,
            isArchived: isDeleted || (record["isArchived"] as? Bool ?? false),
            archivedAt: isDeleted ? deletedAt : (record["archivedAt"] as? Date),
            repeatRule: try RecordJSON.decodeOptional(record["repeatRuleJSON"] as? String, as: ItemRepeatRule.self),
            reminderRequestedAt: record["reminderRequestedAt"] as? Date
        )

        return item
    }

    // MARK: - Helpers

    /// Whether the decoded record represents a soft-deleted item.
    static func isSoftDeleted(_ record: CKRecord) -> Bool {
        (record["isDeleted"] as? Int64 ?? 0) == 1
    }

    // MARK: - Private

    private static func populate(_ record: CKRecord, from item: Item) {
        record["spaceID"] = item.spaceID?.uuidString as CKRecordValue?
        record["listID"] = item.listID?.uuidString as CKRecordValue?
        record["projectID"] = item.projectID?.uuidString as CKRecordValue?
        record["creatorID"] = item.creatorID.uuidString as CKRecordValue
        record["title"] = item.title as CKRecordValue
        record["notes"] = item.notes as CKRecordValue?
        record["locationText"] = item.locationText as CKRecordValue?
        record["executionRole"] = item.executionRole.rawValue as CKRecordValue
        record["assigneeMode"] = item.assigneeMode.rawValue as CKRecordValue
        record["status"] = item.status.rawValue as CKRecordValue
        record["assignmentState"] = item.assignmentState.rawValue as CKRecordValue
        record["dueAt"] = item.dueAt as CKRecordValue?
        record["hasExplicitTime"] = item.hasExplicitTime as CKRecordValue
        record["remindAt"] = item.remindAt as CKRecordValue?
        record["createdAt"] = item.createdAt as CKRecordValue
        record["updatedAt"] = item.updatedAt as CKRecordValue
        record["completedAt"] = item.completedAt as CKRecordValue?
        record["isPinned"] = item.isPinned as CKRecordValue
        record["isDraft"] = item.isDraft as CKRecordValue
        record["isArchived"] = item.isArchived as CKRecordValue
        record["archivedAt"] = item.archivedAt as CKRecordValue?
        record["lastActionByUserID"] = item.lastActionByUserID?.uuidString as CKRecordValue?
        record["lastActionAt"] = item.lastActionAt as CKRecordValue?
        record["reminderRequestedAt"] = item.reminderRequestedAt as CKRecordValue?

        // JSON-encoded complex fields
        record["repeatRuleJSON"] = (try? RecordJSON.encodeOptional(item.repeatRule)) as CKRecordValue?
        record["latestResponseJSON"] = (try? RecordJSON.encodeOptional(item.latestResponse)) as CKRecordValue?
        record["responseHistoryJSON"] = (try? RecordJSON.encode(item.responseHistory)) as CKRecordValue?
        record["assignmentMessagesJSON"] = (try? RecordJSON.encode(item.assignmentMessages)) as CKRecordValue?
        record["occurrenceCompletionsJSON"] = (try? RecordJSON.encode(item.occurrenceCompletions)) as CKRecordValue?
    }
}
