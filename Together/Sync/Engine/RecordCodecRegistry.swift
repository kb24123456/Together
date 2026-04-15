import CloudKit
import Foundation

/// Central registry that maps CKRecord types to their codec implementations.
///
/// Used by `SyncEngineDelegate` to encode domain entities → CKRecord (push)
/// and decode CKRecord → domain entities (pull).
struct RecordCodecRegistry: Sendable {

    // MARK: - Codec Table

    /// Maps CKRecord type name → decoding closure.
    private let decoders: [String: @Sendable (CKRecord) throws -> any RecordCodable]

    /// All registered CKRecord type names.
    var registeredTypes: [String] { Array(decoders.keys) }

    init() {
        var table: [String: @Sendable (CKRecord) throws -> any RecordCodable] = [:]

        // Task (Item)
        table[ItemRecordCodable.ckRecordType] = { record in
            try ItemRecordCodable.from(record: record)
        }

        // TaskList
        table[TaskListRecordCodable.ckRecordType] = { record in
            try TaskListRecordCodable.from(record: record)
        }

        // Project
        table[ProjectRecordCodable.ckRecordType] = { record in
            try ProjectRecordCodable.from(record: record)
        }

        // ProjectSubtask
        table[ProjectSubtaskRecordCodable.ckRecordType] = { record in
            try ProjectSubtaskRecordCodable.from(record: record)
        }

        // PeriodicTask
        table[PeriodicTaskRecordCodable.ckRecordType] = { record in
            try PeriodicTaskRecordCodable.from(record: record)
        }

        // SharedSpace metadata
        table[SpaceRecordCodable.ckRecordType] = { record in
            try SpaceRecordCodable.from(record: record)
        }

        // MemberProfile metadata
        table[MemberProfileRecordCodable.ckRecordType] = { record in
            try MemberProfileRecordCodable.from(record: record)
        }

        // Avatar asset payload
        table[AvatarAssetRecordCodable.ckRecordType] = { record in
            try AvatarAssetRecordCodable.from(record: record)
        }

        self.decoders = table
    }

    // MARK: - Encode

    /// Encodes any `RecordCodable` entity into a CKRecord within the specified zone.
    func encode(_ entity: any RecordCodable, in zoneID: CKRecordZone.ID) -> CKRecord {
        entity.toCKRecord(in: zoneID)
    }

    // MARK: - Decode

    /// Decodes a CKRecord into its corresponding domain entity.
    /// Throws `RecordCodecError.unknownRecordType` if no codec is registered.
    func decode(_ record: CKRecord) throws -> any RecordCodable {
        guard let decoder = decoders[record.recordType] else {
            throw RecordCodecError.unknownRecordType(record.recordType)
        }
        return try decoder(record)
    }

    /// Returns true if the registry has a codec for the given record type.
    func canDecode(_ recordType: String) -> Bool {
        decoders[recordType] != nil
    }
}
