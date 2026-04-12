import Foundation

/// A single change entry within a SyncRelay payload.
///
/// Represents one record mutation (upsert or delete) that needs
/// to be transmitted to the partner via the public DB relay.
struct ChangeEntry: Codable, Sendable {
    /// CKRecord type name (e.g. "Task", "TaskList", "Project").
    let recordType: String

    /// The UUID of the record being changed.
    let recordID: String

    /// The operation: "upsert" or "delete".
    let operation: String

    /// JSON-encoded record fields (nil for delete operations).
    let fieldsJSON: String?

    enum Operation: String, Codable, Sendable {
        case upsert
        case delete
    }
}

/// Metadata for a received relay message after decryption.
struct RelayMessage: Sendable {
    let senderUserID: UUID
    let pairSpaceID: UUID
    let sequenceNumber: Int64
    let changes: [ChangeEntry]
    let timestamp: Date
}
