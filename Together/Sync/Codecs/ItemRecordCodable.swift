import CloudKit
import Foundation

/// Bridges `Item` (Task) ↔ CKRecord.
///
/// Reuses field mapping from the existing `CloudKitTaskRecordCodec`,
/// now conforming to the `RecordCodable` protocol for use with CKSyncEngine.
struct ItemRecordCodable: RecordCodable {
    static let ckRecordType = "Task"

    let item: Item

    func toCKRecord(in zoneID: CKRecordZone.ID) -> CKRecord {
        let recordID = CKRecord.ID(recordName: item.id.uuidString, zoneID: zoneID)
        let record = CKRecord(recordType: Self.ckRecordType, recordID: recordID)

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

        return record
    }

    static func from(record: CKRecord) throws -> ItemRecordCodable {
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
            throw RecordCodecError.missingField("required Task field")
        }

        let assigneeModeRaw = (record["assigneeMode"] as? String)
            ?? ItemExecutionRole(rawValue: executionRoleRaw)?.assigneeMode.rawValue
            ?? TaskAssigneeMode.`self`.rawValue

        let assignmentStateRaw = (record["assignmentState"] as? String)
            ?? ItemStatus(rawValue: statusRaw)?.assignmentState.rawValue
            ?? TaskAssignmentState.active.rawValue

        let responseHistoryJSON = (record["responseHistoryJSON"] as? String) ?? "[]"
        let assignmentMessagesJSON = (record["assignmentMessagesJSON"] as? String) ?? "[]"

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
            isPinned: record["isPinned"] as? Bool ?? false,
            isDraft: record["isDraft"] as? Bool ?? false,
            isArchived: record["isArchived"] as? Bool ?? false,
            archivedAt: record["archivedAt"] as? Date,
            repeatRule: try RecordJSON.decodeOptional(record["repeatRuleJSON"] as? String, as: ItemRepeatRule.self),
            reminderRequestedAt: record["reminderRequestedAt"] as? Date
        )

        return ItemRecordCodable(item: item)
    }
}
