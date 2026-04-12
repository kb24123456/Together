import Foundation
import SwiftData

/// Compatibility-only legacy models kept so pre-rebuild stores can be opened
/// and migrated forward without deleting user data.
///
/// These entities are no longer part of the active Together runtime schema.
@Model
final class PersistentSyncRelayQueue {
    var id: UUID
    var pairSpaceID: UUID
    var payloadJSON: String
    var attemptCount: Int
    var createdAt: Date
    var lastAttemptAt: Date?
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

/// Compatibility-only legacy relay sequence state.
@Model
final class PersistentRelaySequence {
    var pairSpaceID: UUID
    var lastReceivedSequence: Int64
    var lastSentSequence: Int64
    var updatedAt: Date

    init(
        pairSpaceID: UUID,
        lastReceivedSequence: Int64 = 0,
        lastSentSequence: Int64 = 0,
        updatedAt: Date = .now
    ) {
        self.pairSpaceID = pairSpaceID
        self.lastReceivedSequence = lastReceivedSequence
        self.lastSentSequence = lastSentSequence
        self.updatedAt = updatedAt
    }
}
