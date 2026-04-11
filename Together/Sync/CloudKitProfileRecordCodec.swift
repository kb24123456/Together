import CloudKit
import Foundation

/// 同步成员 profile 信息到 CloudKit 公共库。
/// 记录以 `{spaceID}-{userID}` 为唯一键，确保每个空间中每个用户只有一条 profile 记录。
enum CloudKitProfileRecordCodec {
    nonisolated static let recordType = "MemberProfile"

    /// 可同步的成员 Profile 数据
    struct MemberProfilePayload: Codable, Hashable, Sendable {
        let userID: UUID
        var spaceID: UUID
        var displayName: String
        var avatarSystemName: String?
        /// Base64 编码的头像照片数据（压缩后的 JPEG）
        var avatarPhotoBase64: String?
        /// PairSpace 的显示名称（任何一方都可以修改）
        var pairSpaceDisplayName: String?
        var updatedAt: Date
    }

    nonisolated static func makeRecord(from payload: MemberProfilePayload) -> CKRecord {
        let recordName = "\(payload.spaceID.uuidString)-\(payload.userID.uuidString)"
        let recordID = CKRecord.ID(recordName: recordName)
        let record = CKRecord(recordType: recordType, recordID: recordID)
        record["userID"] = payload.userID.uuidString as CKRecordValue
        record["spaceID"] = payload.spaceID.uuidString as CKRecordValue
        record["displayName"] = payload.displayName as CKRecordValue
        record["avatarSystemName"] = payload.avatarSystemName as CKRecordValue?
        record["avatarPhotoBase64"] = payload.avatarPhotoBase64 as CKRecordValue?
        record["pairSpaceDisplayName"] = payload.pairSpaceDisplayName as CKRecordValue?
        record["updatedAt"] = payload.updatedAt as CKRecordValue
        return record
    }

    nonisolated static func decode(record: CKRecord) -> MemberProfilePayload? {
        guard
            let userIDStr = record["userID"] as? String,
            let userID = UUID(uuidString: userIDStr),
            let spaceIDStr = record["spaceID"] as? String,
            let spaceID = UUID(uuidString: spaceIDStr),
            let displayName = record["displayName"] as? String,
            let updatedAt = record["updatedAt"] as? Date
        else { return nil }

        return MemberProfilePayload(
            userID: userID,
            spaceID: spaceID,
            displayName: displayName,
            avatarSystemName: record["avatarSystemName"] as? String,
            avatarPhotoBase64: record["avatarPhotoBase64"] as? String,
            pairSpaceDisplayName: record["pairSpaceDisplayName"] as? String,
            updatedAt: updatedAt
        )
    }
}
