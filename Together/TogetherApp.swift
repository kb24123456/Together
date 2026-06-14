import SwiftUI
import UserNotifications

@main
struct TogetherApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var notificationDelegate = AppNotificationDelegate()
    @State private var appBootstrapper = AppBootstrapper()
    @Environment(\.scenePhase) private var scenePhase

    init() {
        #if DEBUG
        DebugResetCoordinator.applyPendingNukeIfNeeded()
        #endif
        StartupTrace.mark("TogetherApp.init")
    }

    var body: some Scene {
        WindowGroup {
            Group {
                switch appBootstrapper.phase {
                case .ready:
                    if let appContext = appBootstrapper.appContext {
                        AppRootView()
                            .environment(appContext)
                            .overlay {
                                if appContext.sessionStore.isAppLocked {
                                    AppLockOverlay(
                                        biometricService: appContext.container.biometricAuthService,
                                        onUnlocked: {
                                            appContext.sessionStore.isAppLocked = false
                                        }
                                    )
                                    .transition(.opacity)
                                }
                            }
                            .animation(.easeInOut(duration: 0.3), value: appContext.sessionStore.isAppLocked)
                    }
                case .needsAuth:
                    if let appContext = appBootstrapper.appContext {
                        SignInView(
                            authService: appContext.container.authService,
                            onSignedIn: { session in
                                Task {
                                    await appBootstrapper.handleSignIn(session: session)
                                }
                            }
                        )
                    }
                case .idle, .bootstrapping:
                    AppLaunchView()
                }
            }
            .animation(.easeInOut(duration: 0.30), value: appBootstrapper.phase)
                .task {
                    StartupTrace.mark("TogetherApp.root.task.start")
                    UNUserNotificationCenter.current().delegate = notificationDelegate
                    UNUserNotificationCenter.current().setNotificationCategories(
                        NotificationActionCatalog.categories
                    )
                    appDelegate.bootstrapper = appBootstrapper
                    await appBootstrapper.bootstrapIfNeeded()
                    // Cold-launch deep-link: transfer any APNs task_id captured before bootstrap.
                    if let appContext = appBootstrapper.appContext,
                       let taskID = appDelegate.consumePendingTaskIDFromNotification() {
                        appContext.rememberDeepLinkTaskID(taskID)
                        await appContext.consumeDeepLinkTaskIDIfAny()
                    }
                    StartupTrace.mark("TogetherApp.root.task.end")
                }
                .task(id: appBootstrapper.isReady) {
                    guard let appContext = appBootstrapper.appContext else { return }
                    StartupTrace.mark("TogetherApp.ready.task.start")
                    notificationDelegate.configure(appContext: appContext)
                    await appContext.performPostLaunchWorkIfNeeded()
                    StartupTrace.mark("TogetherApp.ready.task.end")
                }
                .onChange(of: appBootstrapper.appContext?.sessionStore.authState) { _, newValue in
                    if newValue == .signedOut, appBootstrapper.phase == .ready {
                        appBootstrapper.handleSignOut()
                    }
                }
                .onOpenURL { url in
                    if let appContext = appBootstrapper.appContext {
                        appContext.handleDeepLink(url: url)
                    }
                }
                .onChange(of: scenePhase) { _, newPhase in
                    guard let appContext = appBootstrapper.appContext,
                          appBootstrapper.phase == .ready
                    else { return }

                    switch newPhase {
                    case .background:
                        let lockEnabled = appContext.sessionStore.currentUser?.preferences.appLockEnabled == true
                        if lockEnabled {
                            appContext.sessionStore.isAppLocked = true
                        }
                        // SwiftData handles CloudKit scheduling for the private database.
                    case .active:
                        appContext.updateSyncPolling()
                        Task { await appContext.handleAppBecameActive() }
                    default:
                        break
                    }
                }
        }
    }
}
