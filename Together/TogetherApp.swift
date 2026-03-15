import SwiftUI
import UserNotifications

@main
struct TogetherApp: App {
    @State private var notificationDelegate = AppNotificationDelegate()
    @State private var appContext = AppContext.bootstrap()

    var body: some Scene {
        WindowGroup {
            AppRootView()
                .environment(appContext)
                .task {
                    UNUserNotificationCenter.current().delegate = notificationDelegate
                    notificationDelegate.configure(appContext: appContext)
                }
        }
    }
}
