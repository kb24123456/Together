import CloudKit
import Foundation

struct MemberProfileRecordCodable: RecordCodable {
    static let ckRecordType = "MemberProfile"

    struct Profile: Hashable, Sendable {
        let userID: UUID
        let spaceID: UUID
        var displayName: String
        var avatarSystemName: String?
        var avatarAssetID: String?
        var avatarVersion: Int
        var avatarDeleted: Bool
        var updatedAt: Date
    }

    let profile: Profile

    func toCKRecord(in zoneID: CKRecordZone.ID) -> CKRecord {
        let recordID = CKRecord.ID(recordName: profile.userID.uuidString, zoneID: zoneID)
        let record = CKRecord(recordType: Self.ckRecordType, recordID: recordID)
        record["userID"] = profile.userID.uuidString as CKRecordValue
        record["spaceID"] = profile.spaceID.uuidString as CKRecordValue
        record["displayName"] = profile.displayName as CKRecordValue
        record["avatarSystemName"] = profile.avatarSystemName as CKRecordValue?
        record["avatarAssetID"] = profile.avatarAssetID as CKRecordValue?
        record["avatarVersion"] = profile.avatarVersion as CKRecordValue
        record["avatarDeleted"] = profile.avatarDeleted as CKRecordValue
        record["updatedAt"] = profile.updatedAt as CKRecordValue
        return record
    }

    static func from(record: CKRecord) throws -> MemberProfileRecordCodable {
        guard
            let userIDRaw = record["userID"] as? String,
            let userID = UUID(uuidString: userIDRaw),
            let spaceIDRaw = record["spaceID"] as? String,
            let spaceID = UUID(uuidString: spaceIDRaw),
            let displayName = record["displayName"] as? String,
            let updatedAt = record["updatedAt"] as? Date
        else {
            throw RecordCodecError.missingField("required MemberProfile field")
        }

        let avatarDeleted = record["avatarDeleted"] as? Bool ?? false
        let avatarAssetID = record["avatarAssetID"] as? String
        let avatarVersion = record["avatarVersion"] as? Int ?? 0

        return MemberProfileRecordCodable(
            profile: Profile(
                userID: userID,
                spaceID: spaceID,
                displayName: displayName,
                avatarSystemName: record["avatarSystemName"] as? String,
                avatarAssetID: avatarAssetID,
                avatarVersion: avatarVersion,
                avatarDeleted: avatarDeleted,
                updatedAt: updatedAt
            )
        )
    }
}
