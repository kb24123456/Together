import CloudKit
import Foundation

/// Encodes/decodes `Space` ↔ `CKRecord` for public DB pair sync.
enum PairSpaceRecordCodec: Sendable {

    nonisolated static let recordType = "PairSpace"

    nonisolated static func encode(_ space: Space) -> CKRecord {
        let recordID = CKRecord.ID(recordName: space.id.uuidString)
        let record = CKRecord(recordType: recordType, recordID: recordID)
        record["spaceID"] = space.id.uuidString as CKRecordValue
        record["type"] = space.type.rawValue as CKRecordValue
        record["displayName"] = space.displayName as CKRecordValue
        record["ownerUserID"] = space.ownerUserID.uuidString as CKRecordValue
        record["status"] = space.status.rawValue as CKRecordValue
        record["createdAt"] = space.createdAt as CKRecordValue
        record["updatedAt"] = space.updatedAt as CKRecordValue
        record["archivedAt"] = space.archivedAt as CKRecordValue?
        return record
    }

    nonisolated static func decode(_ record: CKRecord) throws -> Space {
        let id = UUID(uuidString: record.recordID.recordName) ?? UUID()
        guard
            let typeRaw = record["type"] as? String,
            let displayName = record["displayName"] as? String,
            let ownerUserIDRaw = record["ownerUserID"] as? String,
            let ownerUserID = UUID(uuidString: ownerUserIDRaw),
            let statusRaw = record["status"] as? String,
            let createdAt = record["createdAt"] as? Date,
            let updatedAt = record["updatedAt"] as? Date
        else {
            throw RecordCodecError.missingField("required PairSpace field")
        }

        return Space(
            id: id,
            type: SpaceType(rawValue: typeRaw) ?? .pair,
            displayName: displayName,
            ownerUserID: ownerUserID,
            status: SpaceStatus(rawValue: statusRaw) ?? .active,
            createdAt: createdAt,
            updatedAt: updatedAt,
            archivedAt: record["archivedAt"] as? Date
        )
    }
}
