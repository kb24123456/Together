import CloudKit
import Foundation

enum CloudKitTaskRecordCodecError: Error {
    case missingField(String)
    case invalidField(String)
}

enum CloudKitTaskRecordCodec {
    nonisolated static let recordType = "Task"

    nonisolated static func makeRecord(from item: Item) throws -> CKRecord {
        let record = CKRecord(recordType: recordType, recordID: CKRecord.ID(recordName: item.id.uuidString))
        record["spaceID"] = item.spaceID?.uuidString as CKRecordValue?
        record["listID"] = item.listID?.uuidString as CKRecordValue?
        record["projectID"] = item.projectID?.uuidString as CKRecordValue?
        record["creatorID"] = item.creatorID.uuidString as CKRecordValue
        record["title"] = item.title as CKRecordValue
        record["notes"] = item.notes as CKRecordValue?
        record["locationText"] = item.locationText as CKRecordValue?
        record["executionRole"] = item.executionRole.rawValue as CKRecordValue
        record["assigneeMode"] = item.assigneeMode.rawValue as CKRecordValue
        record["priority"] = item.priority.rawValue as CKRecordValue
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
        record["repeatRuleJSON"] = try encode(item.repeatRule) as CKRecordValue?
        record["latestResponseJSON"] = try encode(item.latestResponse) as CKRecordValue?
        record["responseHistoryJSON"] = try encode(item.responseHistory) as CKRecordValue
        record["assignmentMessagesJSON"] = try encode(item.assignmentMessages) as CKRecordValue
        record["lastActionByUserID"] = item.lastActionByUserID?.uuidString as CKRecordValue?
        record["lastActionAt"] = item.lastActionAt as CKRecordValue?
        return record
    }

    nonisolated static func decode(record: CKRecord) throws -> Item {
        let id = UUID(uuidString: record.recordID.recordName) ?? UUID()
        guard
            let creatorIDRaw = record["creatorID"] as? String,
            let creatorID = UUID(uuidString: creatorIDRaw),
            let title = record["title"] as? String,
            let executionRoleRaw = record["executionRole"] as? String,
            let assigneeModeRaw = (record["assigneeMode"] as? String) ?? ItemExecutionRole(rawValue: executionRoleRaw)?.assigneeMode.rawValue,
            let priorityRaw = record["priority"] as? String,
            let statusRaw = record["status"] as? String,
            let assignmentStateRaw = (record["assignmentState"] as? String) ?? ItemStatus(rawValue: statusRaw)?.assignmentState.rawValue,
            let createdAt = record["createdAt"] as? Date,
            let updatedAt = record["updatedAt"] as? Date
        else {
            throw CloudKitTaskRecordCodecError.missingField("required task field")
        }

        let responseHistoryJSON = (record["responseHistoryJSON"] as? String) ?? "[]"
        let assignmentMessagesJSON = (record["assignmentMessagesJSON"] as? String) ?? "[]"

        return Item(
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
            priority: ItemPriority(rawValue: priorityRaw) ?? .normal,
            dueAt: record["dueAt"] as? Date,
            hasExplicitTime: record["hasExplicitTime"] as? Bool ?? false,
            remindAt: record["remindAt"] as? Date,
            status: ItemStatus(rawValue: statusRaw) ?? .pendingConfirmation,
            assignmentState: TaskAssignmentState(rawValue: assignmentStateRaw) ?? .active,
            latestResponse: try decodeOptional((record["latestResponseJSON"] as? String), as: ItemResponse.self),
            responseHistory: try decode(responseHistoryJSON, as: [ItemResponse].self),
            assignmentMessages: try decode(assignmentMessagesJSON, as: [TaskAssignmentMessage].self),
            lastActionByUserID: UUID(uuidString: (record["lastActionByUserID"] as? String) ?? ""),
            lastActionAt: record["lastActionAt"] as? Date,
            createdAt: createdAt,
            updatedAt: updatedAt,
            completedAt: record["completedAt"] as? Date,
            isPinned: record["isPinned"] as? Bool ?? false,
            isDraft: record["isDraft"] as? Bool ?? false,
            isArchived: record["isArchived"] as? Bool ?? false,
            archivedAt: record["archivedAt"] as? Date,
            repeatRule: try decodeOptional((record["repeatRuleJSON"] as? String), as: ItemRepeatRule.self)
        )
    }

    private nonisolated static func encode<T: Encodable>(_ value: T?) throws -> String? {
        guard let value else { return nil }
        let data = try JSONEncoder().encode(value)
        return String(data: data, encoding: .utf8)
    }

    private nonisolated static func encode<T: Encodable>(_ value: T) throws -> String {
        let data = try JSONEncoder().encode(value)
        guard let string = String(data: data, encoding: .utf8) else {
            throw CloudKitTaskRecordCodecError.invalidField("json encoding")
        }
        return string
    }

    private nonisolated static func decode<T: Decodable>(_ json: String, as type: T.Type) throws -> T {
        guard let data = json.data(using: .utf8) else {
            throw CloudKitTaskRecordCodecError.invalidField("json data")
        }
        return try JSONDecoder().decode(T.self, from: data)
    }

    private nonisolated static func decodeOptional<T: Decodable>(_ json: String?, as type: T.Type) throws -> T? {
        guard let json else { return nil }
        return try decode(json, as: type)
    }
}
