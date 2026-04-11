import SwiftUI
import UserNotifications

@main
struct TogetherApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var notificationDelegate = AppNotificationDelegate()
    @State private var appBootstrapper = AppBootstrapper()
    @Environment(\.scenePhase) private var scenePhase

    init() {
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
                .task {
                    StartupTrace.mark("TogetherApp.root.task.start")
                    UNUserNotificationCenter.current().delegate = notificationDelegate
                    UNUserNotificationCenter.current().setNotificationCategories(
                        NotificationActionCatalog.categories
                    )
                    appDelegate.bootstrapper = appBootstrapper
                    await appBootstrapper.bootstrapIfNeeded()
                    StartupTrace.mark("TogetherApp.root.task.end")
                }
                .task(id: appBootstrapper.isReady) {
                    guard let appContext = appBootstrapper.appContext else { return }
                    StartupTrace.mark("TogetherApp.ready.task.start")
                    notificationDelegate.configure(appContext: appContext)
                    await appContext.performPostLaunchWorkIfNeeded()
                    // Handle any CKShare acceptance that arrived before bootstrap
                    if let metadata = appDelegate.consumePendingShareMetadata() {
                        await appContext.handleAcceptedCloudKitShare(metadata: metadata)
                    }
                    StartupTrace.mark("TogetherApp.ready.task.end")
                }
                .onChange(of: appBootstrapper.appContext?.sessionStore.authState) { _, newValue in
                    if newValue == .signedOut, appBootstrapper.phase == .ready {
                        appBootstrapper.handleSignOut()
                    }
                }
                .onOpenURL { url in
                    // Universal Link 邀请跳转
                    if let appContext = appBootstrapper.appContext {
                        appContext.handleDeepLink(url: url)
                    }
                }
                .onChange(of: appBootstrapper.appContext?.sessionStore.activeMode) { _, newMode in
                    guard let appContext = appBootstrapper.appContext,
                          appBootstrapper.phase == .ready
                    else { return }
                    // 配对成功或解绑后，立即启停同步轮询
                    appContext.updateSyncPolling()
                    if newMode == .pair {
                        Task { await appContext.syncPairSpaceIfNeeded() }
                    }
                }
                .onChange(of: appBootstrapper.appContext?.sessionStore.userProfileRevision) { _, _ in
                    // 用户 profile 变更后，同步到 CloudKit
                    appBootstrapper.appContext?.syncProfileToCloud()
                }
                .onChange(of: appBootstrapper.appContext?.sessionStore.pairSpaceSummary) { _, _ in
                    // pairSpaceSummary 到位后（可能晚于 activeMode 变化），重新评估轮询状态
                    guard let appContext = appBootstrapper.appContext,
                          appBootstrapper.phase == .ready,
                          appContext.sessionStore.activeMode == .pair
                    else { return }
                    appContext.updateSyncPolling()
                }
                .onChange(of: scenePhase) { _, newPhase in
                    guard let appContext = appBootstrapper.appContext,
                          appBootstrapper.phase == .ready
                    else { return }

                    if newPhase == .background,
                       appContext.sessionStore.currentUser?.preferences.appLockEnabled == true {
                        appContext.sessionStore.isAppLocked = true
                    }

                    if newPhase == .background {
                        appContext.syncScheduler.stopPolling()
                    }

                    if newPhase == .active {
                        // 启动/恢复同步轮询（仅在 pair 模式下）
                        appContext.updateSyncPolling()
                        // 立即触发一次同步
                        if appContext.sessionStore.activeMode == .pair {
                            Task { await appContext.syncPairSpaceIfNeeded() }
                        }
                    }
                }
        }
    }
}
