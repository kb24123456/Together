import CloudKit
import Foundation

/// Manages CKQuerySubscription for real-time push notifications on the public database.
///
/// Creates one subscription per Pair* record type per space, so CloudKit sends
/// a silent push when any pair data changes. The push triggers
/// `PairSyncPoller.nudge()` for immediate sync.
actor CloudKitSubscriptionManager {
    private let container: CKContainer

    /// Subscription IDs stored per space for cleanup.
    private var activeSubscriptionIDs: [UUID: [String]] = [:]

    /// Record types to subscribe to — matches PairSyncCodecRegistry.supportedRecordTypes
    /// but only the highest-change-frequency types to avoid subscription quota pressure.
    private static let subscribedRecordTypes = [
        PairTaskRecordCodec.recordType,         // PairTask — most frequent
        PairTaskListRecordCodec.recordType,      // PairTaskList
        PairProjectRecordCodec.recordType,       // PairProject
        PairPeriodicTaskRecordCodec.recordType,  // PairPeriodicTask
        PairSpaceRecordCodec.recordType,         // PairSpace — rename
        PairMemberProfileRecordCodec.recordType, // PairMemberProfile — nickname/avatar
    ]

    init(container: CKContainer) {
        self.container = container
    }

    // MARK: - Subscribe

    /// Creates query subscriptions on the public database for all Pair* record types
    /// matching the given space (via spaceID filter).
    func subscribe(for spaceID: UUID) async throws {
        let db = container.publicCloudDatabase
        var savedIDs: [String] = []

        for recordType in Self.subscribedRecordTypes {
            let subscriptionID = "pair-\(recordType)-\(spaceID.uuidString)"

            // Check if already subscribed
            if let existing = try? await db.subscription(for: subscriptionID) {
                #if DEBUG
                print("[SubscriptionManager] Already subscribed: \(existing.subscriptionID)")
                #endif
                savedIDs.append(subscriptionID)
                continue
            }

            let predicate = NSPredicate(
                format: "spaceID == %@",
                spaceID.uuidString as NSString
            )
            let subscription = CKQuerySubscription(
                recordType: recordType,
                predicate: predicate,
                subscriptionID: subscriptionID,
                options: [.firesOnRecordCreation, .firesOnRecordUpdate]
            )

            let notificationInfo = CKSubscription.NotificationInfo()
            notificationInfo.shouldSendContentAvailable = true // Silent push
            subscription.notificationInfo = notificationInfo

            do {
                let saved = try await db.save(subscription)
                savedIDs.append(saved.subscriptionID)
                #if DEBUG
                print("[SubscriptionManager] Subscribed: \(saved.subscriptionID)")
                #endif
            } catch {
                #if DEBUG
                print("[SubscriptionManager] Subscribe failed for \(recordType): \(error)")
                #endif
                // Continue with other types — partial subscription is better than none
            }
        }

        activeSubscriptionIDs[spaceID] = savedIDs
    }

    // MARK: - Unsubscribe

    /// Removes all subscriptions for a pair space.
    func unsubscribe(for spaceID: UUID) async {
        let db = container.publicCloudDatabase
        let ids = activeSubscriptionIDs[spaceID] ?? Self.subscribedRecordTypes.map {
            "pair-\($0)-\(spaceID.uuidString)"
        }

        for subscriptionID in ids {
            do {
                try await db.deleteSubscription(withID: subscriptionID)
                #if DEBUG
                print("[SubscriptionManager] Unsubscribed: \(subscriptionID)")
                #endif
            } catch {
                #if DEBUG
                print("[SubscriptionManager] Unsubscribe error (may already be removed): \(error)")
                #endif
            }
        }
        activeSubscriptionIDs.removeValue(forKey: spaceID)
    }

    // MARK: - Notification Handling

    /// Determines if a remote notification is a CloudKit subscription notification.
    nonisolated static func isCloudKitNotification(_ userInfo: [AnyHashable: Any]) -> Bool {
        CKNotification(fromRemoteNotificationDictionary: userInfo) != nil
    }
}
