import CloudKit
import UIKit

/// Handles UIApplicationDelegate callbacks that are not available in the SwiftUI lifecycle.
///
/// Responsibilities:
/// - Register for remote notifications used by CloudKit sync.
/// - Forward silent pushes to AppContext when the app is alive.
/// - Capture cold-launch task_id from APNs userInfo for deep-link routing.
@MainActor
final class AppDelegate: NSObject, UIApplicationDelegate {

    weak var bootstrapper: AppBootstrapper?

    /// Stored when share acceptance arrives before the app is fully bootstrapped.
    /// AppContext consumes this via `consumePendingShareMetadata()` once ready.
    private(set) var pendingShareMetadata: CKShare.Metadata?

    /// Captured from launchOptions[.remoteNotification] on cold launch.
    /// Consumed once by `consumePendingTaskIDFromNotification()` after bootstrap.
    private(set) var pendingTaskIDFromNotification: UUID?

    // MARK: - Launch

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        // CloudKit shared/private database subscriptions may still wake the app in background.
        application.registerForRemoteNotifications()

        if let remote = launchOptions?[.remoteNotification] as? [AnyHashable: Any],
           let taskIDString = remote["task_id"] as? String,
           let taskID = UUID(uuidString: taskIDString) {
            pendingTaskIDFromNotification = taskID
        }

        return true
    }

    func consumePendingTaskIDFromNotification() -> UUID? {
        let id = pendingTaskIDFromNotification
        pendingTaskIDFromNotification = nil
        return id
    }

    // MARK: - Remote Notifications

    func application(
        _ application: UIApplication,
        didReceiveRemoteNotification userInfo: [AnyHashable: Any],
        fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void
    ) {
        guard let appContext = bootstrapper?.appContext else {
            completionHandler(.noData)
            return
        }
        Task {
            await appContext.handleCloudKitNotification(userInfo)
            completionHandler(.newData)
        }
    }

    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        // 注册 device token 到 Supabase（用于双人同步 APNs 推送）
        Task {
            await DeviceTokenService().registerToken(deviceToken)
        }
    }

    func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        #if DEBUG
        print("[AppDelegate] Failed to register for remote notifications: \(error)")
        #endif
    }

    // MARK: - CKShare (legacy, disabled)
    // Direct share-link acceptance is not yet the primary invite path. The current
    // production flow accepts shares from the invite code lookup result.

    func application(
        _ application: UIApplication,
        userDidAcceptCloudKitShareWith cloudKitShareMetadata: CKShare.Metadata
    ) {
        pendingShareMetadata = cloudKitShareMetadata
    }

    func consumePendingShareMetadata() -> CKShare.Metadata? {
        let m = pendingShareMetadata
        pendingShareMetadata = nil
        return m
    }
}
