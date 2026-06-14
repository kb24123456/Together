import UIKit

/// Handles UIApplicationDelegate callbacks that are not available in the SwiftUI lifecycle.
///
/// Responsibilities:
/// - Register for remote notifications used by local notification deep links.
/// - Forward silent pushes to AppContext when the app is alive.
/// - Capture cold-launch task_id from APNs userInfo for deep-link routing.
@MainActor
final class AppDelegate: NSObject, UIApplicationDelegate {

    weak var bootstrapper: AppBootstrapper?

    /// Captured from launchOptions[.remoteNotification] on cold launch.
    /// Consumed once by `consumePendingTaskIDFromNotification()` after bootstrap.
    private(set) var pendingTaskIDFromNotification: UUID?

    // MARK: - Launch

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
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
            await appContext.handleRemoteNotification(userInfo)
            completionHandler(.newData)
        }
    }

    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        // 保留 APNs token 入口，当前版本不上传到第三方后端。
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
}
