import CloudKit
import Foundation
import os.log

private let logger = Logger(subsystem: "com.pigdog.Together", category: "RelaySubscription")

/// Manages CKQuerySubscription instances for SyncRelay records in the public DB.
///
/// Each active pair space gets its own subscription, filtered by pairSpaceID
/// and excluding the current user's own relay records.
actor SyncRelaySubscriptionManager {
    private let container: CKContainer
    private let myUserID: UUID
    private var activeSubscriptions: Set<String> = []

    init(container: CKContainer, myUserID: UUID) {
        self.container = container
        self.myUserID = myUserID
    }

    // MARK: - Subscribe

    /// Creates a CKQuerySubscription for relay records in a specific pair space.
    func subscribe(pairSpaceID: UUID) async throws {
        let subscriptionID = subscriptionID(for: pairSpaceID)

        guard !activeSubscriptions.contains(subscriptionID) else {
            logger.info("[RelaySubscription] Already subscribed for space \(pairSpaceID.uuidString.prefix(8))")
            return
        }

        let predicate = NSPredicate(
            format: "pairSpaceID == %@ AND senderUserID != %@",
            pairSpaceID.uuidString as NSString,
            myUserID.uuidString as NSString
        )

        let subscription = CKQuerySubscription(
            recordType: SyncRelayGateway.recordType,
            predicate: predicate,
            subscriptionID: subscriptionID,
            options: [.firesOnRecordCreation]
        )

        let info = CKSubscription.NotificationInfo()
        info.shouldSendContentAvailable = true // Silent push
        subscription.notificationInfo = info

        try await container.publicCloudDatabase.save(subscription)

        activeSubscriptions.insert(subscriptionID)
        logger.info("[RelaySubscription] ✅ Subscribed for space \(pairSpaceID.uuidString.prefix(8))")
    }

    // MARK: - Unsubscribe

    /// Removes the CKQuerySubscription for a pair space.
    func unsubscribe(pairSpaceID: UUID) async throws {
        let subscriptionID = subscriptionID(for: pairSpaceID)

        guard activeSubscriptions.contains(subscriptionID) else { return }

        try await container.publicCloudDatabase.deleteSubscription(withID: subscriptionID)

        activeSubscriptions.remove(subscriptionID)
        logger.info("[RelaySubscription] ⏹️ Unsubscribed for space \(pairSpaceID.uuidString.prefix(8))")
    }

    // MARK: - Helpers

    /// Deterministic subscription ID per pair space.
    func subscriptionID(for pairSpaceID: UUID) -> String {
        "relay-\(pairSpaceID.uuidString)"
    }

    /// Checks if a notification's subscription ID corresponds to a relay subscription.
    func pairSpaceID(for subscriptionID: String) -> UUID? {
        let prefix = "relay-"
        guard subscriptionID.hasPrefix(prefix) else { return nil }
        return UUID(uuidString: String(subscriptionID.dropFirst(prefix.count)))
    }
}
