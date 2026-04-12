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
    ///
    /// Non-primitive types (Date, Data) are wrapped with a `__cktype` marker
    /// so that `deserializeValue` can restore the original type on the receiving end.
    private static func serializeValue(_ value: Any) -> Any {
        switch value {
        case let string as String:
            return string
        case let date as Date:
            // Must check Date before NSNumber — Date is not NSNumber but could
            // be confused if order were reversed in some bridge scenarios.
            return ["__cktype": "date", "__value": date.timeIntervalSince1970] as [String: Any]
        case let number as NSNumber:
            return number
        case let data as Data:
            return ["__cktype": "data", "__value": data.base64EncodedString()] as [String: Any]
        case let list as [Any]:
            return list.map { serializeValue($0) }
        default:
            return "\(value)"
        }
    }

    /// Deserializes a JSON value back to a CKRecordValue-compatible type.
    ///
    /// Recognises the `__cktype` wrapper produced by `serializeValue` and
    /// reconstructs the original Foundation type (Date, Data).
    private static func deserializeValue(_ value: Any) -> Any {
        if let dict = value as? [String: Any], let cktype = dict["__cktype"] as? String {
            switch cktype {
            case "date":
                if let ti = dict["__value"] as? Double {
                    return Date(timeIntervalSince1970: ti)
                }
            case "data":
                if let b64 = dict["__value"] as? String, let data = Data(base64Encoded: b64) {
                    return data
                }
            default:
                break
            }
        }
        if let list = value as? [Any] {
            return list.map { deserializeValue($0) }
        }
        return value
    }
}
