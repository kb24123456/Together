import CloudKit
import Foundation

/// Encodes/decodes avatar binary assets ↔ `CKRecord` for public DB pair sync.
/// Uses `CKAsset` for the avatar file and the same `AvatarAssetRecordCodable.Asset`
/// structure for consistency.
enum PairAvatarAssetRecordCodec: Sendable {

    nonisolated static let recordType = "PairAvatarAsset"

    nonisolated static func encode(_ asset: AvatarAssetRecordCodable.Asset, spaceID: UUID) -> CKRecord {
        let recordID = CKRecord.ID(recordName: asset.assetID.uuidString.lowercased())
        let record = CKRecord(recordType: recordType, recordID: recordID)
        record["assetID"] = asset.assetID.uuidString.lowercased() as CKRecordValue
        record["spaceID"] = spaceID.uuidString as CKRecordValue
        record["version"] = asset.version as CKRecordValue
        record["updatedAt"] = asset.updatedAt as CKRecordValue
        if let fileName = asset.fileName {
            let fileURL = UserAvatarStorage.fileURL(fileName: fileName)
            if FileManager.default.fileExists(atPath: fileURL.path(percentEncoded: false)) {
                record["avatarData"] = CKAsset(fileURL: fileURL)
            }
        }
        return record
    }

    nonisolated static func decode(_ record: CKRecord) throws -> AvatarAssetRecordCodable.Asset {
        guard
            let assetIDRaw = record["assetID"] as? String,
            let assetID = UUID(uuidString: assetIDRaw),
            let updatedAt = record["updatedAt"] as? Date
        else {
            throw RecordCodecError.missingField("required PairAvatarAsset field")
        }

        let version = record["version"] as? Int ?? 0
        let assetData: Data?
        if let ckAsset = record["avatarData"] as? CKAsset,
           let fileURL = ckAsset.fileURL {
            assetData = try? Data(contentsOf: fileURL)
        } else {
            assetData = nil
        }

        return AvatarAssetRecordCodable.Asset(
            assetID: assetID,
            version: version,
            updatedAt: updatedAt,
            fileName: nil,
            data: assetData
        )
    }
}
