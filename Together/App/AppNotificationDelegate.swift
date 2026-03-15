import Foundation
import UserNotifications

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
        [.banner, .sound, .list]
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        guard let appContext else { return }
        await appContext.handleNotificationResponse(response)
    }
}
