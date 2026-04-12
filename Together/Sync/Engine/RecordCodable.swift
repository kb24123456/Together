import CloudKit
import Foundation

// MARK: - Protocol

/// Defines bidirectional mapping between a domain entity and a CKRecord.
///
/// Each syncable entity type conforms to this protocol so that
/// `RecordCodecRegistry` can encode/decode any record generically.
protocol RecordCodable: Sendable {
    /// The CKRecord type name used in CloudKit (e.g. "Task", "TaskList").
    static var ckRecordType: String { get }

    /// Encodes the entity into a CKRecord within the given zone.
    func toCKRecord(in zoneID: CKRecordZone.ID) -> CKRecord

    /// Decodes a CKRecord back into the domain entity.
    static func from(record: CKRecord) throws -> Self
}

// MARK: - Errors

enum RecordCodecError: Error, LocalizedError {
    case missingField(String)
    case invalidField(String)
    case unknownRecordType(String)
    case jsonEncodingFailed
    case jsonDecodingFailed(String)

    var errorDescription: String? {
        switch self {
        case .missingField(let f): "Missing required field: \(f)"
        case .invalidField(let f): "Invalid field value: \(f)"
        case .unknownRecordType(let t): "Unknown record type: \(t)"
        case .jsonEncodingFailed: "JSON encoding failed"
        case .jsonDecodingFailed(let d): "JSON decoding failed: \(d)"
        }
    }
}

// MARK: - JSON Helpers

/// Shared JSON encoding/decoding helpers for record codecs.
enum RecordJSON {
    private static let encoder = JSONEncoder()
    private static let decoder = JSONDecoder()

    static func encode<T: Encodable>(_ value: T) throws -> String {
        let data = try encoder.encode(value)
        guard let string = String(data: data, encoding: .utf8) else {
            throw RecordCodecError.jsonEncodingFailed
        }
        return string
    }

    static func encodeOptional<T: Encodable>(_ value: T?) throws -> String? {
        guard let value else { return nil }
        return try encode(value)
    }

    static func decode<T: Decodable>(_ json: String, as type: T.Type) throws -> T {
        guard let data = json.data(using: .utf8) else {
            throw RecordCodecError.jsonDecodingFailed("invalid UTF-8")
        }
        return try decoder.decode(T.self, from: data)
    }

    static func decodeOptional<T: Decodable>(_ json: String?, as type: T.Type) throws -> T? {
        guard let json else { return nil }
        return try decode(json, as: type)
    }
}
