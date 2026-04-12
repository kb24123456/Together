import CloudKit
import Foundation
import os.log

private let logger = Logger(subsystem: "com.pigdog.Together", category: "RelayChangeConverter")

/// Converts between CKRecord and ChangeEntry for relay transmission.
///
/// When local changes are pushed to the private zone, the successfully saved CKRecords
/// are converted to ChangeEntry payloads for relay posting to the partner.
/// When relay messages are received from the partner, ChangeEntries are converted
/// back to domain entities and applied to local SwiftData.
enum RelayChangeConverter {

    // MARK: - CKRecord → ChangeEntry (for posting relay)

    /// Converts a successfully pushed CKRecord to a ChangeEntry for relay.
    static func toChangeEntry(from record: CKRecord) -> ChangeEntry? {
        let recordType = record.recordType
        let recordID = record.recordID.recordName

        // Serialize all fields to a JSON dictionary
        var fields: [String: Any] = [:]
        for key in record.allKeys() {
            if let value = record[key] {
                fields[key] = serializeValue(value)
            }
        }

        guard let fieldsData = try? JSONSerialization.data(withJSONObject: fields),
              let fieldsJSON = String(data: fieldsData, encoding: .utf8) else {
            logger.warning("[RelayConverter] Failed to serialize fields for \(recordType)/\(recordID.prefix(8))")
            return nil
        }

        return ChangeEntry(
            recordType: recordType,
            recordID: recordID,
            operation: "upsert",
            fieldsJSON: fieldsJSON
        )
    }

    /// Converts a deletion to a ChangeEntry for relay.
    static func toDeletionEntry(recordID: CKRecord.ID, recordType: String) -> ChangeEntry {
        ChangeEntry(
            recordType: recordType,
            recordID: recordID.recordName,
            operation: "delete",
            fieldsJSON: nil
        )
    }

    // MARK: - ChangeEntry → CKRecord (for applying relay)

    /// Reconstructs a CKRecord from a ChangeEntry received via relay.
    /// The record is placed in the specified zone for local private DB storage.
    static func toCKRecord(from entry: ChangeEntry, in zoneID: CKRecordZone.ID) -> CKRecord? {
        guard entry.operation == "upsert",
              let fieldsJSON = entry.fieldsJSON,
              let fieldsData = fieldsJSON.data(using: .utf8),
              let fields = try? JSONSerialization.jsonObject(with: fieldsData) as? [String: Any]
        else {
            return nil
        }

        let recordID = CKRecord.ID(recordName: entry.recordID, zoneID: zoneID)
        let record = CKRecord(recordType: entry.recordType, recordID: recordID)

        for (key, value) in fields {
            record[key] = deserializeValue(value) as? CKRecordValue
        }

        return record
    }

    // MARK: - Value Serialization

    /// Serializes a CKRecordValue to a JSON-compatible type.
    private static func serializeValue(_ value: Any) -> Any {
        switch value {
        case let string as String:
            return string
        case let number as NSNumber:
            return number
        case let date as Date:
            return date.timeIntervalSince1970
        case let data as Data:
            return data.base64EncodedString()
        case let list as [Any]:
            return list.map { serializeValue($0) }
        default:
            return "\(value)"
        }
    }

    /// Deserializes a JSON value back to a CKRecordValue-compatible type.
    /// Note: Date fields are stored as TimeInterval and need type-aware reconstruction.
    /// The codec layer handles this via its own from(record:) logic.
    private static func deserializeValue(_ value: Any) -> Any {
        // JSON values come back as String, NSNumber, Array, or Dictionary
        // We pass them through as-is; the codec's from(record:) handles type conversion.
        return value
    }
}
