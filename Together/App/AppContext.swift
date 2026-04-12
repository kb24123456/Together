import CloudKit
import Foundation
import Observation
import UIKit
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

    /// Sync health monitor exposed for UI binding (from SyncEngineCoordinator).
    let syncHealthMonitor: SyncHealthMonitor

    private(set) var hasBootstrapped = false
    private var hasCompletedPostLaunchWork = false
    private var hasSyncedReminderNotifications = false
    private var hasRestoredPersistedUserProfile = false

    /// Backup relay polling task — ensures partner relay messages are fetched
    /// even when silent push notifications are delayed or dropped (common in GCBD).
    private var relayPollingTask: Task<Void, Never>?

    init(container: AppContainer, sessionStore: SessionStore, router: AppRouter, appearanceManager: AppearanceManager = AppearanceManager()) {
        self.container = container
        self.sessionStore = sessionStore
        self.router = router
        self.appearanceManager = appearanceManager
        self.syncHealthMonitor = container.syncEngineCoordinator.healthMonitor
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
            periodicTaskApplicationService: container.periodicTaskApplicationService,
            taskTemplateRepository: container.taskTemplateRepository
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

        // Start CKSyncEngine for all active zones
        if sessionStore.authState == .signedIn {
            await startSoloSyncEngineIfNeeded()
            await startPairSyncEngineIfNeeded()
            // One-time migration from public DB to private zone
            await performPublicToPrivateMigrationIfNeeded()
        }

        StartupTrace.mark("AppContext.postLaunch.end")
    }

    // MARK: - CKSyncEngine Setup

    /// Starts the CKSyncEngine-based solo zone sync for single-mode data.
    private func startSoloSyncEngineIfNeeded() async {
        if let soloSpaceID = sessionStore.singleSpace?.id {
            await container.syncEngineCoordinator.configureSoloSpaceID(soloSpaceID)
        }

        await container.syncEngineCoordinator.startSoloSync()

        await container.syncEngineCoordinator.setSoloRemoteChangesCallback { [weak self] count in
            guard let self, count > 0 else { return }
            Task { @MainActor in
                await self.homeViewModel.reload()
                await self.listsViewModel.load()
                await self.projectsViewModel.load()
            }
        }
    }

    /// Starts pair sync for the current pair space if paired.
    func startPairSyncEngineIfNeeded() async {
        guard let summary = sessionStore.pairSpaceSummary,
              let myUserID = sessionStore.currentUser?.id,
              summary.pairSpace.status == .active,
              let memberB = summary.pairSpace.memberB
        else { return }

        let pairSpaceID = summary.pairSpace.id
        let inviterID = summary.pairSpace.memberA.userID
        let responderID = memberB.userID

        let isActive = await container.syncEngineCoordinator.isPairSyncActive(for: pairSpaceID)
        guard !isActive else { return }

        await container.syncEngineCoordinator.startPairSync(
            pairSpaceID: pairSpaceID,
            sharedSpaceID: summary.sharedSpace.id,
            myUserID: myUserID,
            inviterID: inviterID,
            responderID: responderID
        )

        await container.syncEngineCoordinator.setPairRemoteChangesCallback(
            pairSpaceID: pairSpaceID
        ) { [weak self] count in
            guard let self, count > 0 else { return }
            Task { @MainActor in
                await self.reloadAfterSync()
            }
        }
    }

    /// One-time migration of pair space data from public DB to private zone.
    private func performPublicToPrivateMigrationIfNeeded() async {
        guard let summary = sessionStore.pairSpaceSummary,
              summary.pairSpace.status == .active else { return }

        await SyncMigrationService.migrateIfNeeded(
            pairSpaceID: summary.pairSpace.id,
            sharedSpaceID: summary.sharedSpace.id,
            coordinator: container.syncEngineCoordinator,
            ckContainer: container.cloudKitContainer,
            modelContainer: PersistenceController.shared.container
        )
    }

    /// Stops pair sync and cleans up encryption key (for unbind).
    func teardownPairSync(pairSpaceID: UUID) async {
        await container.syncEngineCoordinator.teardownPairSync(pairSpaceID: pairSpaceID)
    }

    /// Posts the current user's profile to the relay so the partner receives avatar/name updates.
    ///
    /// - Parameter includeAvatar: Whether to include the full avatar photo base64 in the payload.
    ///   Pass `true` only when the avatar has actually changed. Omitting the avatar keeps the
    ///   relay payload small (~1KB vs potentially hundreds of KB), significantly improving
    ///   reliability on weak/GCBD networks.
    func syncProfileToPartner(user: User, includeAvatar: Bool = true) async {
        guard let summary = sessionStore.pairSpaceSummary,
              summary.pairSpace.status == .active else { return }

        // nil  = 本次 relay 不涉及头像（metadata-only）→ 接收端保持原样
        // ""   = 发送方显式删除了自定义头像 → 接收端清除
        // 非空 = 新头像 base64 数据 → 接收端保存并更新
        var avatarPhotoBase64: String?
        if includeAvatar {
            if let fileName = user.avatarPhotoFileName {
                let store = LocalUserAvatarMediaStore()
                if var data = try? store.avatarData(named: fileName) {
                    // Cap avatar data at 100KB to keep relay payload reliable on weak networks.
                    #if canImport(UIKit)
                    let maxBytes = 100_000
                    if data.count > maxBytes, let image = UIImage(data: data) {
                        var best = data
                        for quality in stride(from: 0.7, through: 0.3, by: -0.1) {
                            if let compressed = image.jpegData(compressionQuality: quality) {
                                best = compressed
                                if compressed.count <= maxBytes { break }
                            }
                        }
                        data = best
                    }
                    #endif
                    avatarPhotoBase64 = data.base64EncodedString()
                }
            } else {
                // 用户没有自定义头像 → 发空字符串表示"显式无头像"
                avatarPhotoBase64 = ""
            }
        }

        let payload = CloudKitProfileRecordCodec.MemberProfilePayload(
            userID: user.id,
            spaceID: summary.sharedSpace.id,
            displayName: user.displayName,
            avatarSystemName: user.avatarSystemName,
            avatarPhotoBase64: avatarPhotoBase64,
            pairSpaceDisplayName: summary.pairSpace.displayName,
            updatedAt: .now
        )

        await container.syncEngineCoordinator.pushProfileToRelay(payload)
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

    private(set) var pendingInviteCode: String?

    func handleDeepLink(url: URL) {
        guard let code = DeepLinkConfiguration.inviteCode(from: url) else { return }
        pendingInviteCode = code
        router.isProfilePresented = true
    }

    func consumePendingInviteCode() -> String? {
        let code = pendingInviteCode
        pendingInviteCode = nil
        return code
    }

    // MARK: - Sync

    /// Triggers a relay fetch for the pair space if one exists.
    /// Call this on app foreground when in pair mode.
    func syncPairSpaceIfNeeded() async {
        guard let pairSpaceID = sessionStore.pairSpaceSummary?.pairSpace.id else { return }
        await container.syncEngineCoordinator.fetchRelays(for: pairSpaceID)
    }

    /// 任务操作后触发同步
    ///
    /// CKSyncEngine handles push automatically via `onChangeRecorded` forwarding.
    /// For pair zones, the `onLocalChangesPushed` callback posts relay to the partner.
    func syncAfterMutation(spaceID: UUID) {
        // No explicit trigger needed — CKSyncEngine picks up changes automatically.
        // The LocalSyncCoordinator.onChangeRecorded forwarding routes changes
        // to the correct zone via SyncEngineCoordinator.recordChange().
    }

    /// 同步后刷新所有相关 ViewModel 的数据，并检测对方发来的催促提醒
    func reloadAfterSync() async {
        let spaceID = sessionStore.currentSpace?.id
        let previousItems: [Item]
        if let spaceID {
            previousItems = (try? await container.itemRepository.fetchActiveItems(spaceID: spaceID)) ?? []
        } else {
            previousItems = []
        }
        let previousReminders: [UUID: Date] = Dictionary(
            uniqueKeysWithValues: previousItems
                .compactMap { item -> (UUID, Date)? in
                    guard let reminderAt = item.reminderRequestedAt else { return nil }
                    return (item.id, reminderAt)
                }
        )

        // 先刷新 session state（空间名/头像等元数据），再 reload 依赖它的 ViewModel
        if let userID = sessionStore.currentUser?.id {
            let updatedPairingCtx = await container.pairingService.currentPairingContext(for: userID)
            let updatedSpaceCtx = await container.spaceService.currentSpaceContext(for: userID)
            sessionStore.refresh(spaceContext: updatedSpaceCtx, pairingContext: updatedPairingCtx)
        }

        await homeViewModel.reload()

        let currentUserID = sessionStore.currentUser?.id
        let allItems: [Item]
        if let spaceID {
            allItems = (try? await container.itemRepository.fetchActiveItems(spaceID: spaceID)) ?? []
        } else {
            allItems = []
        }
        for item in allItems {
            guard let reminderAt = item.reminderRequestedAt else { continue }
            let previousDate = previousReminders[item.id]
            if previousDate == nil || reminderAt > previousDate! {
                if item.creatorID != currentUserID && item.assigneeMode == .partner {
                    await scheduleReminderNotification(for: item, message: "催你完成任务啦！")
                } else if item.creatorID == currentUserID && item.assigneeMode == .partner {
                    await scheduleReminderNotification(for: item, message: "对方催你确认任务啦！")
                }
            }
        }
    }

    private func scheduleReminderNotification(for item: Item, message: String) async {
        let content = UNMutableNotificationContent()
        content.title = item.title
        content.body = message
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "reminder-\(item.id.uuidString)",
            content: content,
            trigger: nil
        )
        try? await UNUserNotificationCenter.current().add(request)
    }

    /// 推送本地已有数据到 CloudKit（配对成功后调用）
    func pushExistingTasksToCloud(spaceID: UUID) async {
        await startPairSyncEngineIfNeeded()

        let tasks = (try? await container.itemRepository.fetchActiveItems(spaceID: spaceID)) ?? []
        for task in tasks {
            await container.syncCoordinator.recordLocalChange(
                SyncChange(entityKind: .task, operation: .upsert, recordID: task.id, spaceID: spaceID)
            )
        }

        let lists = (try? await container.taskListRepository.fetchTaskLists(spaceID: spaceID)) ?? []
        for list in lists {
            await container.syncCoordinator.recordLocalChange(
                SyncChange(entityKind: .taskList, operation: .upsert, recordID: list.id, spaceID: spaceID)
            )
        }

        let projects = (try? await container.projectRepository.fetchProjects(spaceID: spaceID)) ?? []
        for project in projects {
            await container.syncCoordinator.recordLocalChange(
                SyncChange(entityKind: .project, operation: .upsert, recordID: project.id, spaceID: spaceID)
            )
        }
    }

    // MARK: - Sync Callbacks

    func configureSyncCallbacks() {
        homeViewModel.onTaskMutated = { [weak self] spaceID in
            self?.syncAfterMutation(spaceID: spaceID)
        }
        profileViewModel.onProfileSaved = { [weak self] user, includeAvatar in
            guard let self else { return }
            Task { await self.syncProfileToPartner(user: user, includeAvatar: includeAvatar) }
        }
        configureSyncEngineForwarding()
        configurePairSyncTeardown()
    }

    private func configurePairSyncTeardown() {
        Task {
            if let cloudPairing = container.pairingService as? CloudPairingService {
                await cloudPairing.setOnPairSyncTeardown { [weak self] pairSpaceID in
                    await self?.container.syncEngineCoordinator.teardownPairSync(pairSpaceID: pairSpaceID)
                }
            }
        }
    }

    private func configureSyncEngineForwarding() {
        let coordinator = container.syncEngineCoordinator
        Task {
            if let localCoordinator = container.syncCoordinator as? LocalSyncCoordinator {
                await localCoordinator.setOnChangeRecorded { change in
                    await coordinator.recordChange(change)
                }
            }
        }
    }

    /// 根据当前模式启停 CKSyncEngine pair bridge 及备用 relay 轮询。
    func updateSyncPolling() {
        if sessionStore.activeMode == .pair,
           let pairSpace = sessionStore.currentPairSpace {
            let pairSpaceID = pairSpace.id
            Task {
                await startPairSyncEngineIfNeeded()
                // Fetch any missed relay messages and refresh UI if changes were applied
                let applied = await container.syncEngineCoordinator.fetchRelays(for: pairSpaceID)
                if applied > 0 {
                    await reloadAfterSync()
                }
                // Push own profile metadata so partner gets name/space info after binding.
                // Avatar is omitted to keep payload small; it's only sent when actually changed.
                if let user = sessionStore.currentUser {
                    await syncProfileToPartner(user: user, includeAvatar: false)
                }
            }
            startRelayPollingIfNeeded(pairSpaceID: pairSpaceID)
        } else {
            stopRelayPolling()
        }
    }

    // MARK: - Backup Relay Polling

    /// Starts a background polling loop that fetches relay messages every 30 seconds.
    /// Acts as a safety net when silent push notifications are delayed (common in GCBD).
    private func startRelayPollingIfNeeded(pairSpaceID: UUID) {
        guard relayPollingTask == nil else { return }
        let coordinator = container.syncEngineCoordinator
        relayPollingTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(30))
                guard !Task.isCancelled else { break }
                let applied = await coordinator.fetchRelays(for: pairSpaceID)
                if applied > 0 {
                    await self?.reloadAfterSync()
                }
                // 补发失败的 outbound relay（包括 profile relay）
                await coordinator.retryRelays(for: pairSpaceID)
            }
        }
    }

    private func stopRelayPolling() {
        relayPollingTask?.cancel()
        relayPollingTask = nil
    }

    /// Handle CloudKit push notification.
    /// Routes to relay handler for SyncRelay subscriptions.
    func handleCloudKitNotification(_ userInfo: [AnyHashable: Any]) async {
        // Check if this is a relay subscription notification
        if let notification = CKNotification(fromRemoteNotificationDictionary: userInfo),
           let subscriptionID = notification.subscriptionID {
            let applied = await container.syncEngineCoordinator.handleRelayNotification(
                subscriptionID: subscriptionID
            )
            if applied > 0 {
                await reloadAfterSync()
            }
        }
        // CKSyncEngine handles its own database/zone subscription notifications automatically.
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
