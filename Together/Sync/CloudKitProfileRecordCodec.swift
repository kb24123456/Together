import CloudKit
import Foundation

/// 旧公共库成员资料记录编码器。
/// 仅用于读取 legacy public profile 数据并做一次性迁移/缓存修复，
/// 不再参与当前 shared-authority 双人同步主链路。
enum CloudKitProfileRecordCodec {
    nonisolated static let recordType = "MemberProfile"

    /// 可同步的成员 Profile 数据
    struct MemberProfilePayload: Codable, Hashable, Sendable {
        let userID: UUID
        var spaceID: UUID
        var displayName: String
        var avatarSystemName: String?
        var avatarAssetID: String?
        var avatarVersion: Int = 0
        /// Legacy 头像字节，仅允许作为本地缓存修复输入。
        /// 运行时 shared-authority 语义不再依赖该字段。
        var avatarPhotoBase64: String?
        /// Legacy 共享空间名称，仅允许在本地仍是默认/空白时做一次性补齐。
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
        record["avatarAssetID"] = payload.avatarAssetID as CKRecordValue?
        record["avatarVersion"] = payload.avatarVersion as CKRecordValue
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
            avatarAssetID: record["avatarAssetID"] as? String,
            avatarVersion: record["avatarVersion"] as? Int ?? 0,
            avatarPhotoBase64: record["avatarPhotoBase64"] as? String,
            pairSpaceDisplayName: record["pairSpaceDisplayName"] as? String,
            updatedAt: updatedAt
        )
    }
}
