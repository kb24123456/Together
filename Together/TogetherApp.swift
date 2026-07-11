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
                case .restoringIdentity(let isSlow):
                    PersonalIdentityBootstrapView(
                        title: isSlow ? "数据恢复时间较长" : "正在恢复你的数据",
                        message: isSlow
                            ? "请保持网络连接；Together 不会在恢复完成前创建第二个空间。"
                            : "正在从你的私人 iCloud 数据库恢复。",
                        primaryButtonTitle: nil,
                        onPrimaryAction: nil,
                        onUseLocally: {
                            Task { await appBootstrapper.startLocally() }
                        }
                    )
                case .requiresLocalStart:
                    PersonalIdentityBootstrapView(
                        title: "开始使用 Together",
                        message: "iCloud 中没有发现已有数据。确认后将创建你的个人空间。",
                        primaryButtonTitle: "开始使用",
                        onPrimaryAction: {
                            Task { await appBootstrapper.startLocally() }
                        },
                        onUseLocally: nil
                    )
                case .identityFailed(let message):
                    PersonalIdentityBootstrapView(
                        title: "个人空间暂时不可用",
                        message: message,
                        primaryButtonTitle: "重试",
                        onPrimaryAction: {
                            Task { await appBootstrapper.retryIdentityResolution() }
                        },
                        onUseLocally: nil
                    )
                case .idle, .bootstrapping:
                    AppLaunchView()
                case .persistenceFailed(let failure):
                    AppPersistenceFailureView(
                        failure: failure,
                        onRetry: {
                            Task {
                                await appBootstrapper.retryPersistenceBootstrap()
                            }
                        }
                    )
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
