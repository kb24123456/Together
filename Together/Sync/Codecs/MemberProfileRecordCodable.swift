import CloudKit
import Foundation

struct MemberProfileRecordCodable: RecordCodable {
    static let ckRecordType = CloudKitProfileRecordCodec.recordType

    struct Profile: Hashable, Sendable {
        let userID: UUID
        let spaceID: UUID
        var displayName: String
        var avatarSystemName: String?
        var avatarPhotoData: Data?
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
        record["avatarDeleted"] = profile.avatarDeleted as CKRecordValue
        record["updatedAt"] = profile.updatedAt as CKRecordValue

        if let avatarPhotoData = profile.avatarPhotoData {
            let store = LocalUserAvatarMediaStore()
            let fileName = store.canonicalFileName(for: profile.userID)
            try? store.persistAvatarData(avatarPhotoData, fileName: fileName)
            record["avatarAsset"] = CKAsset(fileURL: UserAvatarStorage.fileURL(fileName: fileName))
        }

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
        let avatarPhotoData: Data?
        if let asset = record["avatarAsset"] as? CKAsset,
           let fileURL = asset.fileURL {
            avatarPhotoData = try? Data(contentsOf: fileURL)
        } else {
            avatarPhotoData = nil
        }

        return MemberProfileRecordCodable(
            profile: Profile(
                userID: userID,
                spaceID: spaceID,
                displayName: displayName,
                avatarSystemName: record["avatarSystemName"] as? String,
                avatarPhotoData: avatarPhotoData,
                avatarDeleted: avatarDeleted,
                updatedAt: updatedAt
            )
        )
    }
}
