import Foundation
import os
import UserNotifications

private let notificationDelegateLogger = Logger(subsystem: "com.pigdog.Together", category: "AppNotificationDelegate")

final class AppNotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    private weak var appContext: AppContext?

    func configure(appContext: AppContext) {
        self.appContext = appContext
        UNUserNotificationCenter.current().setNotificationCategories(NotificationActionCatalog.categories)
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        // Drop self-notifications: if the push was sent by the current user, suppress the banner.
        if let senderIDString = notification.request.content.userInfo["sender_id"] as? String {
            let currentUserID = await MainActor.run { appContext?.sessionStore.currentUser?.id.uuidString }
            if let currentUserID, senderIDString.lowercased() == currentUserID.lowercased() {
                notificationDelegateLogger.info("[Nudge] willPresent suppressed self-notification senderID=\(senderIDString, privacy: .private)")
                return []
            }
        }
        return [.banner, .sound, .list]
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        guard let appContext else { return }
        await appContext.handleNotificationResponse(response)
    }
}
