import CloudKit
import Foundation

/// Manages CKQuerySubscription for real-time push notifications on the public database.
///
/// When a Task record matching the pair space is created or updated,
/// CloudKit sends a silent push notification to trigger incremental sync.
actor CloudKitSubscriptionManager {
    private let container: CKContainer

    /// Subscription IDs stored per space for cleanup.
    private var activeSubscriptionIDs: [UUID: String] = [:]

    init(container: CKContainer) {
        self.container = container
    }

    // MARK: - Subscribe

    /// Creates a query subscription on the public database for Task records
    /// matching the given pair space (via spaceID filter).
    func subscribe(for pairSpaceID: UUID) async throws {
        let db = container.publicCloudDatabase
        let subscriptionID = "pair-sync-\(pairSpaceID.uuidString)"

        // Check if already subscribed
        if let existing = try? await db.subscription(for: subscriptionID) {
            #if DEBUG
            print("[SubscriptionManager] Already subscribed: \(existing.subscriptionID)")
            #endif
            activeSubscriptionIDs[pairSpaceID] = subscriptionID
            return
        }

        // Query subscription: notify when Task records for this spaceID change
        let predicate = NSPredicate(
            format: "spaceID == %@",
            pairSpaceID.uuidString as NSString
        )
        let subscription = CKQuerySubscription(
            recordType: CloudKitTaskRecordCodec.recordType,
            predicate: predicate,
            subscriptionID: subscriptionID,
            options: [.firesOnRecordCreation, .firesOnRecordUpdate, .firesOnRecordDeletion]
        )

        let notificationInfo = CKSubscription.NotificationInfo()
        notificationInfo.shouldSendContentAvailable = true // Silent push
        subscription.notificationInfo = notificationInfo

        let saved = try await db.save(subscription)
        activeSubscriptionIDs[pairSpaceID] = saved.subscriptionID
        #if DEBUG
        print("[SubscriptionManager] ✅ Subscribed: \(saved.subscriptionID)")
        #endif
    }

    // MARK: - Unsubscribe

    /// Removes the subscription for a pair space.
    func unsubscribe(for pairSpaceID: UUID) async {
        let db = container.publicCloudDatabase
        let subscriptionID = activeSubscriptionIDs[pairSpaceID]
            ?? "pair-sync-\(pairSpaceID.uuidString)"

        do {
            try await db.deleteSubscription(withID: subscriptionID)
            activeSubscriptionIDs.removeValue(forKey: pairSpaceID)
            #if DEBUG
            print("[SubscriptionManager] ⏹️ Unsubscribed: \(subscriptionID)")
            #endif
        } catch {
            #if DEBUG
            print("[SubscriptionManager] Unsubscribe error (may already be removed): \(error)")
            #endif
        }
    }

    // MARK: - Notification Handling

    /// Determines if a remote notification is a CloudKit subscription notification.
    nonisolated static func isCloudKitNotification(_ userInfo: [AnyHashable: Any]) -> Bool {
        CKNotification(fromRemoteNotificationDictionary: userInfo) != nil
    }
}
