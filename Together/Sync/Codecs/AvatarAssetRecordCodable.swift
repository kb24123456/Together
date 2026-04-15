import CloudKit
import Foundation

struct AvatarAssetRecordCodable: RecordCodable {
    static let ckRecordType = "AvatarAsset"

    struct Asset: Hashable, Sendable {
        let assetID: UUID
        let version: Int
        let updatedAt: Date
        let fileName: String?
        let data: Data?
    }

    let asset: Asset

    func toCKRecord(in zoneID: CKRecordZone.ID) -> CKRecord {
        let recordID = CKRecord.ID(recordName: asset.assetID.uuidString.lowercased(), zoneID: zoneID)
        let record = CKRecord(recordType: Self.ckRecordType, recordID: recordID)
        record["assetID"] = asset.assetID.uuidString.lowercased() as CKRecordValue
        record["version"] = asset.version as CKRecordValue
        record["updatedAt"] = asset.updatedAt as CKRecordValue
        if let fileName = asset.fileName {
            let fileURL = UserAvatarStorage.fileURL(fileName: fileName)
            if FileManager.default.fileExists(atPath: fileURL.path(percentEncoded: false)) {
                record["avatarAsset"] = CKAsset(fileURL: fileURL)
            }
        }
        return record
    }

    static func from(record: CKRecord) throws -> AvatarAssetRecordCodable {
        guard
            let assetIDRaw = record["assetID"] as? String,
            let assetID = UUID(uuidString: assetIDRaw),
            let updatedAt = record["updatedAt"] as? Date
        else {
            throw RecordCodecError.missingField("required AvatarAsset field")
        }

        let version = record["version"] as? Int ?? 0
        let assetData: Data?
        if let ckAsset = record["avatarAsset"] as? CKAsset,
           let fileURL = ckAsset.fileURL {
            assetData = try? Data(contentsOf: fileURL)
        } else {
            assetData = nil
        }

        return AvatarAssetRecordCodable(
            asset: Asset(
                assetID: assetID,
                version: version,
                updatedAt: updatedAt,
                fileName: nil,
                data: assetData
            )
        )
    }
}
