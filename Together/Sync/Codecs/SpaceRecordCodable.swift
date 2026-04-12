import CloudKit
import Foundation

struct SpaceRecordCodable: RecordCodable {
    static let ckRecordType = "SharedSpace"

    let space: Space

    func toCKRecord(in zoneID: CKRecordZone.ID) -> CKRecord {
        let recordID = CKRecord.ID(recordName: space.id.uuidString, zoneID: zoneID)
        let record = CKRecord(recordType: Self.ckRecordType, recordID: recordID)
        record["type"] = space.type.rawValue as CKRecordValue
        record["displayName"] = space.displayName as CKRecordValue
        record["ownerUserID"] = space.ownerUserID.uuidString as CKRecordValue
        record["status"] = space.status.rawValue as CKRecordValue
        record["createdAt"] = space.createdAt as CKRecordValue
        record["updatedAt"] = space.updatedAt as CKRecordValue
        record["archivedAt"] = space.archivedAt as CKRecordValue?
        return record
    }

    static func from(record: CKRecord) throws -> SpaceRecordCodable {
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
            throw RecordCodecError.missingField("required SharedSpace field")
        }

        return SpaceRecordCodable(
            space: Space(
                id: id,
                type: SpaceType(rawValue: typeRaw) ?? .pair,
                displayName: displayName,
                ownerUserID: ownerUserID,
                status: SpaceStatus(rawValue: statusRaw) ?? .active,
                createdAt: createdAt,
                updatedAt: updatedAt,
                archivedAt: record["archivedAt"] as? Date
            )
        )
    }
}
