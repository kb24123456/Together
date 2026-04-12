import Foundation
import SwiftData

/// Persists relay messages that failed to send, for retry on network recovery.
///
/// Also tracks the last received relay sequence number per pair space,
/// so the gateway knows where to resume fetching from.
@Model
final class PersistentSyncRelayQueue {
    var id: UUID
    var pairSpaceID: UUID

    /// The JSON-encoded [ChangeEntry] payload (pre-encryption).
    var payloadJSON: String

    /// Number of send attempts so far.
    var attemptCount: Int

    /// When this relay was first queued.
    var createdAt: Date

    /// When the last send attempt occurred.
    var lastAttemptAt: Date?

    /// Last error message from a failed send attempt.
    var lastError: String?

    init(
        id: UUID = UUID(),
        pairSpaceID: UUID,
        payloadJSON: String,
        attemptCount: Int = 0,
        createdAt: Date = .now,
        lastAttemptAt: Date? = nil,
        lastError: String? = nil
    ) {
        self.id = id
        self.pairSpaceID = pairSpaceID
        self.payloadJSON = payloadJSON
        self.attemptCount = attemptCount
        self.createdAt = createdAt
        self.lastAttemptAt = lastAttemptAt
        self.lastError = lastError
    }
}

/// Tracks the last received relay sequence number per pair space.
/// Separate from PersistentSyncState to avoid coupling CKSyncEngine state
/// with relay state.
@Model
final class PersistentRelaySequence {
    var pairSpaceID: UUID
    var lastReceivedSequence: Int64
    var lastSentSequence: Int64
    var updatedAt: Date

    init(pairSpaceID: UUID, lastReceivedSequence: Int64 = 0, lastSentSequence: Int64 = 0, updatedAt: Date = .now) {
        self.pairSpaceID = pairSpaceID
        self.lastReceivedSequence = lastReceivedSequence
        self.lastSentSequence = lastSentSequence
        self.updatedAt = updatedAt
    }
}
