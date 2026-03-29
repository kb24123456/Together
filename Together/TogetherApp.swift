import SwiftUI
import UserNotifications

@main
struct TogetherApp: App {
    @State private var notificationDelegate = AppNotificationDelegate()
    @State private var appBootstrapper = AppBootstrapper()

    init() {
        StartupTrace.mark("TogetherApp.init")
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if let appContext = appBootstrapper.appContext {
                    AppRootView()
                        .environment(appContext)
                } else {
                    AppLaunchView()
                }
            }
                .task {
                    StartupTrace.mark("TogetherApp.root.task.start")
                    UNUserNotificationCenter.current().delegate = notificationDelegate
                    UNUserNotificationCenter.current().setNotificationCategories(
                        NotificationActionCatalog.categories
                    )
                    await appBootstrapper.bootstrapIfNeeded()
                    StartupTrace.mark("TogetherApp.root.task.end")
                }
                .task(id: appBootstrapper.isReady) {
                    guard let appContext = appBootstrapper.appContext else { return }
                    StartupTrace.mark("TogetherApp.ready.task.start")
                    notificationDelegate.configure(appContext: appContext)
                    await appContext.performPostLaunchWorkIfNeeded()
                    StartupTrace.mark("TogetherApp.ready.task.end")
                }
        }
    }
}
