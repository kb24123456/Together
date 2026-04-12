import CloudKit
import UIKit

/// Handles UIApplicationDelegate callbacks that are not available in the SwiftUI lifecycle.
///
/// Responsibilities:
/// - Register for remote notifications so CKQuerySubscription pushes are delivered.
/// - Forward silent push notifications to AppContext for relay fetching.
@MainActor
final class AppDelegate: NSObject, UIApplicationDelegate {

    weak var bootstrapper: AppBootstrapper?

    /// Stored when share acceptance arrives before the app is fully bootstrapped.
    /// AppContext consumes this via `consumePendingShareMetadata()` once ready.
    private(set) var pendingShareMetadata: CKShare.Metadata?

    // MARK: - Launch

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        // Register for remote (silent) push notifications.
        // Required so that CKQuerySubscription for SyncRelay can trigger relay fetches.
        application.registerForRemoteNotifications()
        return true
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
        // Token managed by CloudKit framework; no manual handling needed.
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

    func application(
        _ application: UIApplication,
        userDidAcceptCloudKitShareWith cloudKitShareMetadata: CKShare.Metadata
    ) {
        // CKShare is no longer used for pairing (replaced by SyncRelay architecture).
    }

    func consumePendingShareMetadata() -> CKShare.Metadata? {
        let m = pendingShareMetadata
        pendingShareMetadata = nil
        return m
    }
}
