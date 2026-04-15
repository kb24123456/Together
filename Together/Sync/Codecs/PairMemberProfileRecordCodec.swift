import CloudKit
import Foundation

/// Encodes/decodes member profile metadata ↔ `CKRecord` for public DB pair sync.
/// Uses the same `MemberProfileRecordCodable.Profile` structure for consistency.
enum PairMemberProfileRecordCodec: Sendable {

    nonisolated static let recordType = "PairMemberProfile"

    nonisolated static func encode(_ profile: MemberProfileRecordCodable.Profile) -> CKRecord {
        let recordID = CKRecord.ID(recordName: profile.userID.uuidString)
        let record = CKRecord(recordType: recordType, recordID: recordID)
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

    nonisolated static func decode(_ record: CKRecord) throws -> MemberProfileRecordCodable.Profile {
        guard
            let userIDRaw = record["userID"] as? String,
            let userID = UUID(uuidString: userIDRaw),
            let spaceIDRaw = record["spaceID"] as? String,
            let spaceID = UUID(uuidString: spaceIDRaw),
            let displayName = record["displayName"] as? String,
            let updatedAt = record["updatedAt"] as? Date
        else {
            throw RecordCodecError.missingField("required PairMemberProfile field")
        }

        return MemberProfileRecordCodable.Profile(
            userID: userID,
            spaceID: spaceID,
            displayName: displayName,
            avatarSystemName: record["avatarSystemName"] as? String,
            avatarAssetID: record["avatarAssetID"] as? String,
            avatarVersion: record["avatarVersion"] as? Int ?? 0,
            avatarDeleted: record["avatarDeleted"] as? Bool ?? false,
            updatedAt: updatedAt
        )
    }
}
