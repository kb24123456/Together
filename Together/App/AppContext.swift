import CloudKit
import Foundation
import Observation
import UserNotifications

@MainActor
@Observable
final class AppContext {
    let container: AppContainer
    let sessionStore: SessionStore
    let router: AppRouter
    let appearanceManager: AppearanceManager
    let homeViewModel: HomeViewModel
    let listsViewModel: ListsViewModel
    let projectsViewModel: ProjectsViewModel
    let calendarViewModel: CalendarViewModel
    let profileViewModel: ProfileViewModel
    let routinesViewModel: RoutinesViewModel

    var syncScheduler: SyncScheduler { container.syncScheduler }

    private(set) var hasBootstrapped = false
    private var hasCompletedPostLaunchWork = false
    private var hasSyncedReminderNotifications = false
    private var hasRestoredPersistedUserProfile = false

    init(container: AppContainer, sessionStore: SessionStore, router: AppRouter, appearanceManager: AppearanceManager = AppearanceManager()) {
        self.container = container
        self.sessionStore = sessionStore
        self.router = router
        self.appearanceManager = appearanceManager
        self.homeViewModel = HomeViewModel(
            sessionStore: sessionStore,
            taskApplicationService: container.taskApplicationService,
            itemRepository: container.itemRepository,
            quickCaptureParser: container.quickCaptureParser,
            taskTemplateRepository: container.taskTemplateRepository
        )
        self.listsViewModel = ListsViewModel(
            sessionStore: sessionStore,
            taskListRepository: container.taskListRepository
        )
        self.projectsViewModel = ProjectsViewModel(
            sessionStore: sessionStore,
            projectRepository: container.projectRepository
        )
        self.calendarViewModel = CalendarViewModel(
            sessionStore: sessionStore,
            itemRepository: container.itemRepository
        )
        self.routinesViewModel = RoutinesViewModel(
            sessionStore: sessionStore,
            periodicTaskApplicationService: container.periodicTaskApplicationService
        )
        self.profileViewModel = ProfileViewModel(
            sessionStore: sessionStore,
            authService: container.authService,
            pairingService: container.pairingService,
            userProfileRepository: container.userProfileRepository,
            notificationService: container.notificationService,
            itemRepository: container.itemRepository,
            taskApplicationService: container.taskApplicationService,
            taskListRepository: container.taskListRepository,
            projectRepository: container.projectRepository,
            reminderScheduler: container.reminderScheduler,
            syncOrchestrator: container.syncOrchestrator,
            biometricAuthService: container.biometricAuthService
        )
    }

    static func makeContext() -> AppContext {
        StartupTrace.mark("AppContext.make.begin")
        let container = LocalServiceFactory.makeContainer()
        StartupTrace.mark("AppContext.make.containerReady")
        let sessionStore = SessionStore()
        let router = AppRouter()
        let context = AppContext(container: container, sessionStore: sessionStore, router: router)
        context.configureSyncCallbacks()
        StartupTrace.mark("AppContext.make.end")
        return context
    }

    #if DEBUG
    static func makeBootstrappedContext() -> AppContext {
        let container = LocalServiceFactory.makeContainer()
        let sessionStore = SessionStore()
        let router = AppRouter()
        let context = AppContext(container: container, sessionStore: sessionStore, router: router)
        context.seedMockSession()
        context.hasBootstrapped = true
        return context
    }
    #endif

    func bootstrapIfNeeded() async {
        guard hasBootstrapped == false else { return }

        await sessionStore.bootstrap(
            authService: container.authService,
            spaceService: container.spaceService,
            pairingService: container.pairingService
        )
        if sessionStore.authState == .signedIn {
            await restorePersistedUserProfileIfNeeded()
        }
        hasBootstrapped = true
    }

    func setupSpacesForCurrentUserIfNeeded() async {
        guard let userID = sessionStore.currentUser?.id else { return }

        let spaceContext = await container.spaceService.currentSpaceContext(for: userID)
        let pairingContext = await container.pairingService.currentPairingContext(for: userID)

        if spaceContext.singleSpace == nil {
            // First-time user — create a single space
            if let newSpace = try? await container.spaceService.createSingleSpace(for: userID) {
                sessionStore.singleSpace = newSpace
            }
        } else {
            sessionStore.singleSpace = spaceContext.singleSpace
        }

        sessionStore.pairSpaceSummary = spaceContext.pairSpaceSummary ?? pairingContext.pairSpaceSummary
        sessionStore.availableModeStates = spaceContext.availableModes
        sessionStore.pairingContext = pairingContext
        sessionStore.activeMode = .single
    }

    func performPostLaunchWorkIfNeeded() async {
        guard hasCompletedPostLaunchWork == false else { return }
        hasCompletedPostLaunchWork = true
        StartupTrace.mark("AppContext.postLaunch.begin")
        await restorePersistedUserProfileIfNeeded()
        await routinesViewModel.load()
        await syncReminderNotificationsIfNeeded()
        StartupTrace.mark("AppContext.postLaunch.end")
    }

    func restorePersistedUserProfileIfNeeded(force: Bool = false) async {
        guard force || hasRestoredPersistedUserProfile == false else { return }
        #if DEBUG
        let currentUserDescription = sessionStore.currentUser.map {
            "id=\($0.id.uuidString.lowercased()) avatarFile=\($0.avatarPhotoFileName ?? "nil")"
        } ?? "nil"
        StartupTrace.mark("AppContext.restoreUser.begin currentUser=\(currentUserDescription)")
        #endif
        let mergedUser = await container.userProfileRepository.mergedUser(sessionStore.currentUser)
        guard let mergedUser else {
            #if DEBUG
            StartupTrace.mark("AppContext.restoreUser.end mergedUser=nil")
            #endif
            return
        }
        hasRestoredPersistedUserProfile = true
        sessionStore.currentUser = mergedUser
        #if DEBUG
        StartupTrace.mark(
            "AppContext.restoreUser.end mergedAvatarFile=\(mergedUser.avatarPhotoFileName ?? "nil")"
        )
        #endif
    }

    func syncReminderNotificationsIfNeeded(force: Bool = false) async {
        guard force || hasSyncedReminderNotifications == false else { return }
        let spaceID = sessionStore.currentSpace?.id

        let tasks = (try? await container.itemRepository.fetchActiveItems(spaceID: spaceID)) ?? []
        let projects = (try? await container.projectRepository.fetchProjects(spaceID: spaceID)) ?? []

        await container.reminderScheduler.resync(tasks: tasks, projects: projects)

        let periodicTasks = (try? await container.periodicTaskRepository.fetchActiveTasks(spaceID: spaceID)) ?? []
        for periodicTask in periodicTasks {
            await container.reminderScheduler.syncPeriodicTaskReminder(for: periodicTask, referenceDate: .now)
        }

        hasSyncedReminderNotifications = true
    }

    // MARK: - Deep Link

    /// 待处理的邀请码（由 Universal Link 传入，ProfileView 消费后置 nil）
    private(set) var pendingInviteCode: String?

    /// 解析 Universal Link，提取邀请码并导航到 Profile 处理。
    func handleDeepLink(url: URL) {
        guard let code = DeepLinkConfiguration.inviteCode(from: url) else { return }
        pendingInviteCode = code
        // 导航到 Profile 页面，ProfileView 会自动消费邀请码
        router.isProfilePresented = true
    }

    /// ProfileView 取走邀请码后调用，防止重复处理。
    func consumePendingInviteCode() -> String? {
        let code = pendingInviteCode
        pendingInviteCode = nil
        return code
    }

    // MARK: - Sync

    /// Triggers a full sync cycle for the pair space if one exists.
    /// Call this after task mutations that should propagate to the partner,
    /// and on app foreground when in pair mode.
    func syncPairSpaceIfNeeded() async {
        guard let pairSharedSpaceID = sessionStore.pairSpaceSummary?.sharedSpace.id else { return }
        _ = try? await container.syncOrchestrator.sync(spaceID: pairSharedSpaceID)
    }

    /// 任务操作后触发同步（仅在双人模式下且操作的是共享空间）
    func syncAfterMutation(spaceID: UUID) {
        guard sessionStore.activeMode == .pair,
              spaceID == sessionStore.pairSpaceSummary?.sharedSpace.id else { return }
        Task {
            do {
                let result = try await container.syncOrchestrator.sync(spaceID: spaceID)
                #if DEBUG
                print("[Sync] mutation push: pushed=\(result.pushedCount) pulled=\(result.pulledCount)")
                #endif
                if result.pulledCount > 0 {
                    await reloadAfterSync()
                }
            } catch {
                #if DEBUG
                print("[Sync] mutation push failed: \(error)")
                #endif
            }
        }
    }

    /// 同步后刷新所有相关 ViewModel 的数据，并检测对方发来的催促提醒
    func reloadAfterSync() async {
        // 记录刷新前的催促时间戳，用于检测新催促
        let previousReminders: [UUID: Date] = Dictionary(
            uniqueKeysWithValues: homeViewModel.items
                .compactMap { item -> (UUID, Date)? in
                    guard let reminderAt = item.reminderRequestedAt else { return nil }
                    return (item.id, reminderAt)
                }
        )

        await homeViewModel.reload()

        // 检测新到达的催促提醒（对方发来的）
        let currentUserID = sessionStore.currentUser?.id
        for item in homeViewModel.items {
            guard let reminderAt = item.reminderRequestedAt else { continue }
            let previousDate = previousReminders[item.id]
            // 催促时间是新的（之前没有或更新了），且不是自己发的
            if previousDate == nil || reminderAt > previousDate! {
                if item.creatorID != currentUserID && item.assigneeMode == .partner {
                    // 对方催促我：我是被指派者
                    await scheduleReminderNotification(for: item, message: "催你完成任务啦！")
                } else if item.creatorID == currentUserID && item.assigneeMode == .partner {
                    // 对方催促：我是创建者，对方是执行者
                    await scheduleReminderNotification(for: item, message: "对方催你确认任务啦！")
                }
            }
        }
    }

    /// 为催促提醒触发本地通知
    private func scheduleReminderNotification(for item: Item, message: String) async {
        let content = UNMutableNotificationContent()
        content.title = item.title
        content.body = message
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "reminder-\(item.id.uuidString)",
            content: content,
            trigger: nil // 立即触发
        )
        try? await UNUserNotificationCenter.current().add(request)
    }

    /// 推送本地已有任务到 CloudKit（配对成功后调用）
    func pushExistingTasksToCloud(spaceID: UUID) async {
        let tasks = (try? await container.itemRepository.fetchActiveItems(spaceID: spaceID)) ?? []
        for task in tasks {
            await container.syncCoordinator.recordLocalChange(
                SyncChange(
                    entityKind: .task,
                    operation: .upsert,
                    recordID: task.id,
                    spaceID: spaceID
                )
            )
        }
        _ = try? await container.syncOrchestrator.sync(spaceID: spaceID)
    }

    /// 配置所有同步相关回调
    func configureSyncCallbacks() {
        // HomeViewModel 任务操作后触发同步
        homeViewModel.onTaskMutated = { [weak self] spaceID in
            self?.syncAfterMutation(spaceID: spaceID)
        }
        configureSyncScheduler()
    }

    /// 配置 SyncScheduler 回调，使同步完成后自动刷新 UI
    private func configureSyncScheduler() {
        syncScheduler.onSyncCompleted = { [weak self] result in
            guard let self, result.pulledCount > 0 else { return }
            Task { @MainActor in
                await self.reloadAfterSync()
            }
        }
    }

    /// 根据当前模式启停同步轮询，并配置同步网关
    func updateSyncPolling() {
        if sessionStore.activeMode == .pair,
           let pairSpace = sessionStore.currentPairSpace,
           let spaceID = sessionStore.pairSpaceSummary?.sharedSpace.id {

            let pairSpaceID = pairSpace.id
            Task {
                // Configure gateway with spaceID (public DB, no custom zone needed)
                await container.cloudGateway.configure(spaceID: spaceID)
                try? await container.subscriptionManager.subscribe(for: pairSpaceID)
                syncScheduler.startPolling(spaceID: spaceID)
            }
        } else {
            syncScheduler.stopPolling()
        }
    }

    /// Handle CloudKit subscription push notification
    func handleCloudKitNotification(_ userInfo: [AnyHashable: Any]) async {
        guard CloudKitSubscriptionManager.isCloudKitNotification(userInfo) else { return }
        await syncScheduler.handleSubscriptionNotification()
    }

    /// Called when the participant accepts a CKShare (e.g. via tapping a shared link).
    ///
    /// This completes the CloudKit-side share acceptance and triggers an initial sync
    /// to pull the shared zone records into the local database.
    func handleAcceptedCloudKitShare(metadata: CKShare.Metadata) async {
        do {
            try await container.shareManager.acceptShare(metadata: metadata)
            #if DEBUG
            let zoneName = metadata.share.recordID.zoneID.zoneName
            print("[ShareAccept] ✅ Accepted share for zone: \(zoneName)")
            #endif
            await syncPairSpaceIfNeeded()
        } catch {
            #if DEBUG
            print("[ShareAccept] ❌ \(error)")
            #endif
        }
    }

    func handleNotificationResponse(_ response: UNNotificationResponse) async {
        await bootstrapIfNeeded()

        guard let parsed = AppNotification.parseIdentifier(response.notification.request.identifier) else {
            return
        }

        if let snoozeDelay = NotificationActionCatalog.snoozeInterval(for: response.actionIdentifier) {
            guard parsed.targetType == .item else { return }
            await container.reminderScheduler.snoozeTaskReminder(
                itemID: parsed.targetID,
                title: response.notification.request.content.title,
                body: response.notification.request.content.body,
                delay: snoozeDelay
            )
            return
        }

        guard response.actionIdentifier == NotificationActionCatalog.completeActionIdentifier else {
            return
        }

        guard
            parsed.targetType == .item,
            let spaceID = sessionStore.currentSpace?.id,
            let actorID = sessionStore.currentUser?.id
        else {
            return
        }

        do {
            _ = try await container.taskApplicationService.completeTask(
                in: spaceID,
                taskID: parsed.targetID,
                actorID: actorID
            )
            await homeViewModel.reload()
        } catch {
            return
        }
    }

    private func seedMockSession() {
        sessionStore.authState = .signedIn
        sessionStore.currentUser = MockDataFactory.makeCurrentUser()
        sessionStore.singleSpace = MockDataFactory.makeSingleSpace()
        sessionStore.pairSpaceSummary = MockDataFactory.makePairSpaceSummary()
        sessionStore.availableModeStates = [.single, .pair]
        sessionStore.pairingContext = PairingContext(
            state: .paired,
            pairSpaceSummary: MockDataFactory.makePairSpaceSummary(),
            activeInvite: nil
        )
        sessionStore.activeMode = .single
    }
}
