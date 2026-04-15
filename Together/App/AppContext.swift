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
    private var seededPairMetadataSpaceIDs: Set<UUID> = []
    private var pairSyncService: PairSyncService?
    private var pairSyncPoller: PairSyncPoller?
    private var pairSubscriptionManager: CloudKitSubscriptionManager?

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

        var spaceContext = await container.spaceService.currentSpaceContext(for: userID)
        let pairingContext = await container.pairingService.currentPairingContext(for: userID)

        if spaceContext.singleSpace == nil {
            if let newSpace = try? await container.spaceService.createSingleSpace(for: userID) {
                spaceContext.singleSpace = newSpace
            }
        }

        sessionStore.applySpaceAndPairing(spaceContext: spaceContext, pairingContext: pairingContext)
        sessionStore.activeMode = .single
    }

    func performPostLaunchWorkIfNeeded() async {
        guard hasCompletedPostLaunchWork == false else { return }
        hasCompletedPostLaunchWork = true
        StartupTrace.mark("AppContext.postLaunch.begin")
        await restorePersistedUserProfileIfNeeded()
        await routinesViewModel.load()
        await syncReminderNotificationsIfNeeded()

        // Start sync engines
        if sessionStore.authState == .signedIn {
            // One-time schema seeder for CloudKit Development environment
            #if DEBUG
            await PairSchemaSeeder.seedIfNeeded(container: container.cloudKitContainer)
            #endif

            await startSoloSyncEngineIfNeeded()
            await startPairSyncEngineIfNeeded()
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
    ///
    /// Uses `PairSyncService` (public DB CKQuery) instead of CKSyncEngine pair bridges.
    func startPairSyncEngineIfNeeded() async {
        guard let summary = sessionStore.pairSpaceSummary,
              let myUserID = sessionStore.currentUser?.id,
              summary.pairSpace.status == .active
        else { return }

        // Don't re-create if already active for this space
        if pairSyncPoller?.isActive == true { return }

        let sharedSpaceID = summary.sharedSpace.id

        // Create and configure PairSyncService
        let service = PairSyncService(
            ckContainer: container.cloudKitContainer,
            modelContainer: PersistenceController.shared.container
        )
        await service.configure(spaceID: sharedSpaceID, myUserID: myUserID)
        self.pairSyncService = service

        // Create and start PairSyncPoller with adaptive polling
        let poller = PairSyncPoller()
        poller.start { [weak self, weak service] in
            guard let service else { return .noChange }
            let result = await service.syncOnce()
            // Refresh UI after sync with changes
            if case .changes = result {
                Task { @MainActor [weak self] in
                    self?.refreshSharedSyncStatus()
                    await self?.reloadAfterSync()
                }
            }
            return result
        }
        self.pairSyncPoller = poller

        // Set up push subscriptions on the public DB for this space
        let subManager = CloudKitSubscriptionManager(container: container.cloudKitContainer)
        self.pairSubscriptionManager = subManager
        Task {
            try? await subManager.subscribe(for: sharedSpaceID)
        }

        refreshSharedSyncStatus()
    }

    /// One-time migration of pair space data from public DB to private zone.
    /// Disabled: pair sync now uses public DB directly (Path A).
    private func performPublicToPrivateMigrationIfNeeded() async {
        // No-op: CKSyncEngine private zone migration is no longer needed.
    }

    /// Stops pair sync and cleans up (for unbind).
    func teardownPairSync(pairSpaceID: UUID) async {
        pairSyncPoller?.stop()
        pairSyncPoller = nil
        await pairSyncService?.teardown()
        pairSyncService = nil
        // Unsubscribe push notifications for the shared space
        if let sharedSpaceID = sessionStore.pairSpaceSummary?.sharedSpace.id {
            await pairSubscriptionManager?.unsubscribe(for: sharedSpaceID)
        }
        pairSubscriptionManager = nil
        seededPairMetadataSpaceIDs.remove(pairSpaceID)
        sessionStore.updateSharedSyncStatus(.idle)
    }

    /// Queues the current user's shared member profile into the shared authority sync path.
    func syncProfileToPartner(user: User) async {
        guard let summary = sessionStore.pairSpaceSummary,
              summary.pairSpace.status == .active else { return }
        let avatarStore = LocalUserAvatarMediaStore()
        if let avatarAssetID = user.avatarAssetID,
           let assetUUID = UUID(uuidString: avatarAssetID) {
            let cacheFileName = user.avatarCacheFileName ?? avatarStore.cacheFileName(for: avatarAssetID)
            if avatarStore.fileExists(named: cacheFileName) {
            await submitSharedMutation(
                SyncChange(
                    entityKind: .avatarAsset,
                    operation: .upsert,
                    recordID: assetUUID,
                    spaceID: summary.sharedSpace.id
                )
            )
            }
        }
        await submitSharedMutation(
            SyncChange(
                entityKind: .memberProfile,
                operation: .upsert,
                recordID: user.id,
                spaceID: summary.sharedSpace.id
            )
        )
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

    /// Ensures pair sync is running whenever an active pair relationship exists.
    func syncPairSpaceIfNeeded() async {
        guard sessionStore.hasActivePairSpace else { return }
        await startPairSyncEngineIfNeeded()
    }

    /// 本地数据变更后触发同步。
    /// Solo 变更走 CKSyncEngine；pair 变更走 PairSyncPoller nudge。
    func syncAfterMutation(spaceID: UUID) {
        // Solo sync path (CKSyncEngine)
        Task { [weak self] in
            await self?.container.syncEngineCoordinator.sendChanges(for: spaceID)
        }
        // Pair sync path: nudge poller for immediate push+pull
        if let sharedSpaceID = sessionStore.pairSpaceSummary?.sharedSpace.id,
           spaceID == sharedSpaceID {
            pairSyncPoller?.nudge()
        }
        Task { [weak self] in
            await self?.refreshSharedSyncStatusAsync()
        }
    }

    func flushRecordedSharedMutation(_ change: SyncChange) async {
        // Nudge pair poller to push the recorded mutation immediately
        pairSyncPoller?.nudge()
        await refreshSharedSyncStatusAsync()
    }

    private func submitSharedMutation(_ change: SyncChange) async {
        await container.syncCoordinator.recordLocalChange(change)
        pairSyncPoller?.nudge()
        await refreshSharedSyncStatusAsync()
    }

    /// 同步后刷新所有相关 ViewModel 的数据，并检测对方发来的催促提醒
    func reloadAfterSync() async {
        await restorePersistedUserProfileIfNeeded(force: true)
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
        await listsViewModel.load()
        await projectsViewModel.load()
        await calendarViewModel.load()

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

        // Nudge pair poller to push all recorded changes immediately
        pairSyncPoller?.nudge()
    }

    // MARK: - Sync Callbacks

    func configureSyncCallbacks() {
        homeViewModel.onTaskMutated = { [weak self] spaceID in
            self?.syncAfterMutation(spaceID: spaceID)
        }
        homeViewModel.onSharedMutationRecorded = { [weak self] change in
            guard let self else { return }
            Task {
                await self.flushRecordedSharedMutation(change)
            }
        }
        homeViewModel.onConvertToPeriodicTask = { [weak self] title in
            guard let self else { return }
            router.pendingComposerTitle = title
            router.activeComposer = .newPeriodicTask
        }
        homeViewModel.onConvertToProject = { [weak self] title in
            guard let self else { return }
            router.pendingComposerTitle = title
            router.activeComposer = .newProject
        }
        profileViewModel.onProfileSaved = { [weak self] user in
            guard let self else { return }
            Task { await self.syncProfileToPartner(user: user) }
        }
        profileViewModel.onTaskMutated = { [weak self] spaceID in
            self?.syncAfterMutation(spaceID: spaceID)
        }
        profileViewModel.onSharedMutationRecorded = { [weak self] change in
            guard let self else { return }
            Task {
                await self.submitSharedMutation(change)
            }
        }
        configureSyncEngineForwarding()
        configurePairSyncTeardown()
    }

    private func configurePairSyncTeardown() {
        Task {
            if let cloudPairing = container.pairingService as? CloudPairingService {
                await cloudPairing.setOnPairSyncTeardown { [weak self] pairSpaceID in
                    await self?.teardownPairSync(pairSpaceID: pairSpaceID)
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

    /// 根据当前绑定状态启停双人共享同步。
    func updateSyncPolling() {
        if let pairSpace = sessionStore.currentPairSpace,
           pairSpace.status == .active {
            let pairSpaceID = pairSpace.id
            // Nudge existing poller on foreground recovery / mode switch
            pairSyncPoller?.nudge()
            Task {
                await startPairSyncEngineIfNeeded()
                if seededPairMetadataSpaceIDs.contains(pairSpaceID) == false,
                   let user = sessionStore.currentUser {
                    await syncProfileToPartner(user: user)
                    seededPairMetadataSpaceIDs.insert(pairSpaceID)
                }
                await MainActor.run {
                    self.refreshSharedSyncStatus()
                }
            }
        } else {
            // CRITICAL: Only tear down if poller is actually active.
            // Prevents self-destructing on transient nil pairSpaceSummary during refresh.
            if pairSyncPoller?.isActive == true {
                pairSyncPoller?.stop()
                pairSyncPoller = nil
                Task { [weak self] in await self?.pairSyncService?.teardown() }
                pairSyncService = nil
                pairSubscriptionManager = nil
            }
            seededPairMetadataSpaceIDs.removeAll()
            refreshSharedSyncStatus()
        }
    }

    private func refreshSharedSyncStatus() {
        Task { [weak self] in
            await self?.refreshSharedSyncStatusAsync()
        }
    }

    private func refreshSharedSyncStatusAsync() async {
        guard let pairSummary = sessionStore.pairSpaceSummary else {
            sessionStore.updateSharedMutationSnapshots([:])
            sessionStore.updateSharedSyncStatus(.idle)
            return
        }

        var status = syncHealthMonitor.sharedStatus(for: pairSummary.pairSpace.id)
        let snapshots = await container.syncCoordinator.mutationLog(for: pairSummary.sharedSpace.id)
        let latestSnapshots = snapshots.reduce(into: [SharedMutationRecordKey: SyncMutationSnapshot]()) { result, snapshot in
            result[
                SharedMutationRecordKey(
                    entityKind: snapshot.change.entityKind,
                    recordID: snapshot.change.recordID
                )
            ] = snapshot
        }
        let pendingMutationCount = snapshots.reduce(into: 0) { result, snapshot in
            switch snapshot.lifecycleState {
            case .pending, .sending:
                result += 1
            case .confirmed, .failed:
                break
            }
        }
        let failedMutationCount = snapshots.reduce(into: 0) { result, snapshot in
            if snapshot.lifecycleState == .failed {
                result += 1
            }
        }
        let lastMutationError = snapshots
            .last(where: { $0.lifecycleState == .failed && ($0.lastError?.isEmpty == false) })?
            .lastError

        status.pendingMutationCount = pendingMutationCount
        status.failedMutationCount = failedMutationCount
        if let lastMutationError {
            status.lastError = lastMutationError
            if status.level != .syncing {
                status.level = .degraded
            }
        } else if failedMutationCount > 0 {
            status.level = .degraded
        } else if pendingMutationCount > 0 {
            status.level = .syncing
        }

        sessionStore.updateSharedMutationSnapshots(latestSnapshots)
        sessionStore.updateSharedSyncStatus(status)
    }

    /// Handle CloudKit push notification.
    /// Pair sync subscriptions (CKQuerySubscription on public DB) trigger immediate
    /// sync via PairSyncPoller.nudge().
    func handleCloudKitNotification(_ userInfo: [AnyHashable: Any]) async {
        guard let notification = CKNotification(fromRemoteNotificationDictionary: userInfo) else {
            return
        }

        // Check if this is a pair sync subscription notification
        if let queryNotification = notification as? CKQueryNotification,
           let subscriptionID = queryNotification.subscriptionID,
           subscriptionID.hasPrefix("pair-") {
            pairSyncPoller?.nudge()
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
            await flushRecordedSharedMutation(
                SyncChange(
                    entityKind: .task,
                    operation: .complete,
                    recordID: parsed.targetID,
                    spaceID: spaceID
                )
            )
            await homeViewModel.reload()
        } catch {
            return
        }
    }

    private func seedMockSession() {
        sessionStore.seedMock(
            currentUser: MockDataFactory.makeCurrentUser(),
            singleSpace: MockDataFactory.makeSingleSpace(),
            pairSummary: MockDataFactory.makePairSpaceSummary()
        )
    }
}
