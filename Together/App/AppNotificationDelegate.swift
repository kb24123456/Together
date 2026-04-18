import Foundation
import os
import UserNotifications

private let notificationDelegateLogger = Logger(subsystem: "com.pigdog.Together", category: "AppNotificationDelegate")

@MainActor
final class AppNotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    private weak var appContext: AppContext?
    private var pendingResponses: [UNNotificationResponse] = []

    func configure(appContext: AppContext) {
        self.appContext = appContext
        UNUserNotificationCenter.current().setNotificationCategories(NotificationActionCatalog.categories)
        let drained = pendingResponses
        pendingResponses.removeAll()
        Task { @MainActor in
            for response in drained {
                notificationDelegateLogger.info("[Nudge] draining queued response actionIdentifier=\(response.actionIdentifier, privacy: .public)")
                await appContext.handleNotificationResponse(response)
            }
        }
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        // Drop self-notifications: if the push was sent by the current user, suppress the banner.
        if let senderIDString = notification.request.content.userInfo["sender_id"] as? String {
            let currentUserID = appContext?.sessionStore.currentUser?.id.uuidString
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
        if let appContext {
            await appContext.handleNotificationResponse(response)
        } else {
            notificationDelegateLogger.info("[Nudge] appContext not yet configured, queuing response actionIdentifier=\(response.actionIdentifier, privacy: .public)")
            pendingResponses.append(response)
        }
    }
}
