import CloudKit
import Foundation
import Observation
import os
import RevenueCat
import Supabase
import SwiftData
import UIKit
import UserNotifications

private let appContextLogger = Logger(subsystem: "com.pigdog.Together", category: "AppContext")
// premiumLogger 定义在 Together/Services/Premium/PremiumLogger.swift 作为 module-internal

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
    let importantDatesViewModel: ImportantDatesViewModel

    /// Sync health monitor exposed for UI binding (from SyncEngineCoordinator).
    let syncHealthMonitor: SyncHealthMonitor

    // MARK: - Paywall (Session A Task 9a)

    /// 付费墙 sheet 合并器——AppRootView 挂唯一的 `.sheet(item:)` 观察本属性。
    let rootPaywallPresentation = RootPaywallPresentation()

    /// lapse 通知去重（UserDefaults 持久化）。
    let lapseAcknowledgedStore = LapseAcknowledgedStore()

    /// 生产购买抽象。复用同一实例跨所有 UpsellSheet / UpsellContent（packageCache 一致）。
    /// DEBUG 用 Stub（中文 + ¥ 样本数据）方便 UI 验收，不打 Apple Sandbox / RC TestStore；
    /// Release / TestFlight 用真 RC。
    #if DEBUG
    let paywallPurchasing: PaywallPurchasingProtocol = StubPaywallPurchasing()
    #else
    let paywallPurchasing: PaywallPurchasingProtocol = RevenueCatPaywallPurchasing()
    #endif

    /// 监听 PremiumGate.status 转活边沿（non-pro→pro），记 OSLog 让 Session C 评估升级。
    /// 进程级生命周期（spec § 2.6）；init 末尾 start，无 stop。
    let pendingApprovalObserver: PendingApprovalObserver

    private(set) var hasBootstrapped = false
    private var hasCompletedPostLaunchWork = false
    private var hasSyncedReminderNotifications = false
    private var hasRestoredPersistedUserProfile = false
    private var seededPairMetadataSpaceIDs: Set<UUID> = []
    private var supabaseSyncService: SupabaseSyncService?
    private var isStartingSupabaseSync = false  // 防止 startSupabaseSyncIfNeeded 多 Task 并发穿 guard
    private nonisolated(unsafe) let supabaseAuth = SupabaseAuthService()
    private var activeSharedSpaceID: UUID?

    // Premium 生命周期：configure/teardown/refresh 通过任务链串行化，
    // 避免快速登入-登出-再登入导致的 RC configure vs logIn 竞争。
    private var premiumGateTask: Task<Void, Never>?
    private var lastPremiumRefreshAt: Date?

    init(container: AppContainer, sessionStore: SessionStore, router: AppRouter, appearanceManager: AppearanceManager = AppearanceManager()) {
        self.container = container
        self.sessionStore = sessionStore
        self.router = router
        self.appearanceManager = appearanceManager
        self.syncHealthMonitor = container.syncEngineCoordinator.healthMonitor
        self.pendingApprovalObserver = PendingApprovalObserver(premiumGate: container.premiumGate)
        self.homeViewModel = HomeViewModel(
            sessionStore: sessionStore,
            taskApplicationService: container.taskApplicationService,
            itemRepository: container.itemRepository,
            taskTemplateRepository: container.taskTemplateRepository
        )
        self.listsViewModel = ListsViewModel(
            sessionStore: sessionStore,
            taskListRepository: container.taskListRepository
        )
        self.projectsViewModel = ProjectsViewModel(
            sessionStore: sessionStore,
            projectRepository: container.projectRepository,
            premiumGate: container.premiumGate
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
            biometricAuthService: container.biometricAuthService,
            premiumGate: container.premiumGate
        )
        self.importantDatesViewModel = ImportantDatesViewModel(
            sessionStore: sessionStore,
            premiumGate: container.premiumGate,
            repository: container.importantDateRepository
        )
        self.importantDatesViewModel.onChange = { [weak self] in
            guard let self else { return }
            // LocalImportantDateRepository.save/delete already recorded the change
            // into PersistentSyncChange via syncCoordinator; we still need to kick
            // SupabaseSyncService.push() so the row actually leaves the device.
            await self.supabaseSyncService?.push()
            await self.refreshSharedSyncStatusAsync()
            guard let pairSpaceID = self.sessionStore.pairSpaceSummary?.sharedSpace.id else { return }
            await self.container.anniversaryScheduler.refresh(
                spaceID: pairSpaceID,
                partnerName: self.sessionStore.pairSpaceSummary?.partner?.displayName,
                myName: self.sessionStore.currentUser?.displayName,
                myUserID: self.sessionStore.currentUser?.id
            )
        }
        // Session B Task 11: 启动 status 转活监听（OSLog only）
        self.pendingApprovalObserver.start()
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
            if sessionStore.singleSpace == nil {
                await setupSpacesForCurrentUserIfNeeded()
            }
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
        let purgeContext = ModelContext(PersistenceController.shared.container)
        PairPeriodicPurgeMigration.runIfNeeded(context: purgeContext)
        PairSpaceOrphanPurgeMigration.runIfNeeded(context: purgeContext)
        if let pairSpaceID = sessionStore.pairSpaceSummary?.sharedSpace.id {
            importantDatesViewModel.configure(spaceID: pairSpaceID)
            Task { [importantDatesViewModel] in
                await importantDatesViewModel.load()
            }
            let partnerName = sessionStore.pairSpaceSummary?.partner?.displayName
            let myName = sessionStore.currentUser?.displayName
            let myUserID = sessionStore.currentUser?.id
            Task { [container] in
                await container.anniversaryScheduler.refresh(
                    spaceID: pairSpaceID,
                    partnerName: partnerName,
                    myName: myName,
                    myUserID: myUserID
                )
            }
        }
        await restorePersistedUserProfileIfNeeded()
        await routinesViewModel.load()
        await syncReminderNotificationsIfNeeded()

        // 启动顺序对外部读者说明：
        //   1. 先恢复 Supabase session —— configurePremiumGate 需要 auth.uid() 来查
        //      premium_grants（RLS policy `auth.uid() = user_id`）。
        //   2. 激活 Premium 门禁 —— startSoloSyncEngineIfNeeded 和若干业务 gate
        //      会读 premiumGate.isPremium，必须在它们之前 bootstrap 完成。
        //   3. 启动 CKSyncEngine solo（Pro-only）。
        //   4. 启动 Supabase 双人同步。
        if sessionStore.authState == .signedIn {
            _ = await supabaseAuth.restoreSession()
            await configurePremiumGate()
            await startSoloSyncEngineIfNeeded()
            await startSupabaseSyncIfNeeded()
            // 自动检查是否有待接受的邀请已被对端接受
            await autoCheckInviteAcceptedIfPending()
        }

        StartupTrace.mark("AppContext.postLaunch.end")
    }

    // MARK: - CKSyncEngine Setup

    /// Starts the CKSyncEngine-based solo zone sync for single-mode data.
    private func startSoloSyncEngineIfNeeded() async {
        if let soloSpaceID = sessionStore.singleSpace?.id {
            await container.syncEngineCoordinator.configureSoloSpaceID(soloSpaceID)
        }

        // Pro-only：跨设备同步是 Together Pro 功能，非 Pro 用户仅本地 + iCloud 账号锁定。
        // `isPremium` 在调用时点取快照；运行时转为 Free 的收尾由 stopSyncIfLostPremium 处理。
        await container.syncEngineCoordinator.startSoloSync(
            isPremium: container.premiumGate.isPremium
        )

        await container.syncEngineCoordinator.setSoloRemoteChangesCallback { [weak self] count in
            guard let self, count > 0 else { return }
            Task { @MainActor in
                await self.homeViewModel.reload()
                await self.listsViewModel.load()
                await self.projectsViewModel.load()
            }
        }
    }

    /// 启动 Supabase 双人同步（替代旧的 PairSyncService）
    func startSupabaseSyncIfNeeded() async {
        guard let summary = sessionStore.pairSpaceSummary,
              summary.pairSpace.status == .active
        else { return }

        // 并发守卫：已经在同步或正在启动都直接返回。
        // 重点：isStartingSupabaseSync 在遇到首个 await 前同步设置，
        // 这样在 `await supabaseAuth.currentUserID` 挂起期间其他 Task 也会被挡住，
        // 避免创建多个 SupabaseSyncService 重复订阅同一 Realtime channel。
        if supabaseSyncService != nil || isStartingSupabaseSync { return }
        isStartingSupabaseSync = true

        // 所有 return / throw 路径都要清锁；Swift 的 defer 在 MainActor 异步函数里工作正常
        defer { isStartingSupabaseSync = false }

        guard let myUserID = await supabaseAuth.currentUserID else {
            return
        }

        // 使用 Supabase space UUID 作为同步目标
        // 兜底：如果本地 sharedSpace.id 与 cloudKitZoneName 存储的 Supabase UUID 不一致，
        // 优先使用 Supabase 的（处理旧版配对数据）
        var sharedSpaceID = summary.sharedSpace.id
        if let zoneName = summary.pairSpace.cloudKitZoneName,
           let supabaseUUID = UUID(uuidString: zoneName),
           supabaseUUID != sharedSpaceID {
            sharedSpaceID = supabaseUUID
        }

        let service = SupabaseSyncService(
            modelContainer: PersistenceController.shared.container,
            avatarUploader: container.avatarUploader
        )
        let localUserID = sessionStore.currentUser?.id
        await service.configure(spaceID: sharedSpaceID, myUserID: myUserID, myLocalUserID: localUserID)

        // 先把 service 记录到 AppContext，再 startListening。
        // 这样即便 startListening 内部 await 很久，其他 Task 的 `supabaseSyncService != nil` 也会挡住。
        self.supabaseSyncService = service
        self.activeSharedSpaceID = sharedSpaceID
        sessionStore.updateSharedSyncStatus(SharedSyncStatus(level: .syncing, pendingMutationCount: 0, failedMutationCount: 0))

        // Pair is now active and we know the sharedSpaceID. postLaunch may have
        // fired earlier before the pair was ready, leaving importantDatesViewModel
        // unconfigured. Configure + load now so UI queries return rows.
        importantDatesViewModel.configure(spaceID: sharedSpaceID)
        Task { [importantDatesViewModel] in
            await importantDatesViewModel.load()
        }

        await service.startListening()
    }

    /// 停止 Supabase 双人同步（解绑时调用）
    func teardownSupabaseSync(pairSpaceID: UUID) async {
        await supabaseSyncService?.teardown()
        supabaseSyncService = nil
        activeSharedSpaceID = nil
        isStartingSupabaseSync = false
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
        await startSupabaseSyncIfNeeded()
    }

    /// 本地数据变更后触发同步。
    /// Solo 变更走 CKSyncEngine；pair 变更走 Supabase push。
    func syncAfterMutation(spaceID: UUID) {
        // Solo sync path (CKSyncEngine)
        Task { [weak self] in
            await self?.container.syncEngineCoordinator.sendChanges(for: spaceID)
        }
        // Pair sync path: Supabase push
        // 同时匹配 sharedSpace.id 和 activeSharedSpaceID，兼容旧数据 UUID 不一致的情况
        let pairSharedSpaceID = sessionStore.pairSpaceSummary?.sharedSpace.id
        if spaceID == pairSharedSpaceID || spaceID == activeSharedSpaceID {
            Task { [weak self] in
                await self?.supabaseSyncService?.push()
            }
        }
        Task { [weak self] in
            await self?.refreshSharedSyncStatusAsync()
        }
    }

    func flushRecordedSharedMutation(_ change: SyncChange) async {
        // Repository 已经 recordLocalChange，这里只需触发 push。
        // 若再 record 一次会出现重复条目，空耗带宽。
        await supabaseSyncService?.push()
        await refreshSharedSyncStatusAsync()
    }

    private func submitSharedMutation(_ change: SyncChange) async {
        let serviceDescription = supabaseSyncService == nil ? "nil" : "active"
        appContextLogger.info("[SharedMutation] submit kind=\(change.entityKind.rawValue, privacy: .public) op=\(change.operation.rawValue, privacy: .public) recordID=\(change.recordID.uuidString, privacy: .public) spaceID=\(change.spaceID.uuidString, privacy: .public) supabaseService=\(serviceDescription, privacy: .public)")
        await container.syncCoordinator.recordLocalChange(change)
        await supabaseSyncService?.push()
        await refreshSharedSyncStatusAsync()
    }

    /// 同步后刷新所有相关 ViewModel 的数据。
    func reloadAfterSync() async {
        await restorePersistedUserProfileIfNeeded(force: true)

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
        await routinesViewModel.load()
    }

    /// 推送本地已有数据到 Supabase（配对成功后调用）
    func pushExistingTasksToCloud(spaceID: UUID) async {
        await startSupabaseSyncIfNeeded()

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
            for subtask in project.subtasks {
                await container.syncCoordinator.recordLocalChange(
                    SyncChange(entityKind: .projectSubtask, operation: .upsert, recordID: subtask.id, spaceID: spaceID)
                )
            }
        }

        let periodicTasks = (try? await container.periodicTaskRepository.fetchActiveTasks(spaceID: spaceID)) ?? []
        for periodicTask in periodicTasks {
            await container.syncCoordinator.recordLocalChange(
                SyncChange(entityKind: .periodicTask, operation: .upsert, recordID: periodicTask.id, spaceID: spaceID)
            )
        }

        // 立即推送到 Supabase
        await supabaseSyncService?.push()
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
            // 入口预检：超额直接弹 paywall，不弹 Composer
            if !self.projectsViewModel.canCreateAnotherForCurrentUser() {
                self.projectsViewModel.requestQuotaUpsell()
                return
            }
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
        // RoutinesViewModel: Repository + ApplicationService both recordLocalChange,
        // so we only need to trigger the push (same pattern as HomeViewModel).
        routinesViewModel.onSharedMutationRecorded = { [weak self] change in
            guard let self else { return }
            Task {
                await self.flushRecordedSharedMutation(change)
            }
        }
        // ProjectsViewModel: Repository records save/delete/subtask mutations.
        // ViewModel only needs to trigger the push.
        projectsViewModel.onSharedMutationRecorded = { [weak self] change in
            guard let self else { return }
            Task {
                await self.flushRecordedSharedMutation(change)
            }
        }
        configureSyncEngineForwarding()
        configurePairSyncTeardown()
        configureSupabaseRealtimeObservers()
    }

    /// 监听 Supabase Realtime / catchUp 发出的通知，刷新 UI
    private func configureSupabaseRealtimeObservers() {
        NotificationCenter.default.addObserver(
            forName: .supabaseRealtimeChanged,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                await self.reloadAfterSync()
            }
        }
        NotificationCenter.default.addObserver(
            forName: .pairMemberJoined,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                await self.reloadAfterSync()
            }
        }
        NotificationCenter.default.addObserver(
            forName: .pairMemberRemoved,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                await self.handlePartnerLeftPairSpace()
            }
        }
        NotificationCenter.default.addObserver(
            forName: .partnerAvatarDownloaded,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                await self.reloadAfterSync()
            }
        }
        NotificationCenter.default.addObserver(
            forName: .importantDatesChanged,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                guard let pairSpaceID = self.sessionStore.pairSpaceSummary?.sharedSpace.id else { return }
                await self.container.anniversaryScheduler.refresh(
                    spaceID: pairSpaceID,
                    partnerName: self.sessionStore.pairSpaceSummary?.partner?.displayName,
                    myName: self.sessionStore.currentUser?.displayName,
                    myUserID: self.sessionStore.currentUser?.id
                )
                await self.reloadAfterSync()
            }
        }
    }

    private func configurePairSyncTeardown() {
        Task {
            if let cloudPairing = container.pairingService as? CloudPairingService {
                await cloudPairing.setOnPairSyncTeardown { [weak self] pairSpaceID in
                    await self?.teardownSupabaseSync(pairSpaceID: pairSpaceID)
                }
                await cloudPairing.setPairJoinObserver(self)
            }
        }
    }

    private func configureSyncEngineForwarding() {
        let coordinator = container.syncEngineCoordinator
        Task { [weak self] in
            guard let self else { return }
            if let localCoordinator = container.syncCoordinator as? LocalSyncCoordinator {
                await localCoordinator.setOnChangeRecorded { [weak self] change in
                    // 只有 solo 变更才转发给 CKSyncEngine；pair 变更只走 Supabase
                    let activeShared: UUID? = await MainActor.run { [weak self] in
                        self?.activeSharedSpaceID
                    }
                    if let activeShared, change.spaceID == activeShared {
                        // pair 共享空间的变更，跳过 CKSync
                        return
                    }
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
            Task {
                await startSupabaseSyncIfNeeded()
                if seededPairMetadataSpaceIDs.contains(pairSpaceID) == false {
                    // 首次激活：推送本地已有数据到 Supabase
                    if let sharedSpaceID = activeSharedSpaceID {
                        await pushExistingTasksToCloud(spaceID: sharedSpaceID)
                    }
                    if let user = sessionStore.currentUser {
                        await syncProfileToPartner(user: user)
                    }
                    seededPairMetadataSpaceIDs.insert(pairSpaceID)
                }
                await MainActor.run {
                    self.refreshSharedSyncStatus()
                }
            }
        } else {
            // 停止 Supabase 同步
            if supabaseSyncService != nil {
                Task { [weak self] in await self?.supabaseSyncService?.teardown() }
                supabaseSyncService = nil
            }
            isStartingSupabaseSync = false
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

    /// Handle CloudKit push notification (solo sync only).
    /// Pair sync now uses Supabase Realtime + APNs, not CloudKit subscriptions.
    func handleCloudKitNotification(_ userInfo: [AnyHashable: Any]) async {
        // CloudKit 通知现在只用于 Solo CKSyncEngine
        // Pair 同步通过 Supabase Realtime WebSocket 处理
    }

    func handleNotificationResponse(_ response: UNNotificationResponse) async {
        // APNs-originated TASK_NUDGE: userInfo carries task_id directly;
        // identifier is server-generated and does not follow AppNotification format.
        if let taskIDString = response.notification.request.content.userInfo["task_id"] as? String,
           let taskID = UUID(uuidString: taskIDString),
           response.notification.request.content.categoryIdentifier == NotificationActionCatalog.taskNudgeCategoryIdentifier {
            // Drop self-notifications: the Edge Function fans out to every device in the space,
            // including the sender's own device. Ignore the push if sender_id matches current user.
            if let senderIDString = response.notification.request.content.userInfo["sender_id"] as? String,
               let currentUserID = sessionStore.currentUser?.id.uuidString,
               senderIDString.lowercased() == currentUserID.lowercased() {
                appContextLogger.info("[Nudge] handleNotificationResponse dropped self-notification senderID=\(senderIDString, privacy: .private)")
                return
            }
            await bootstrapIfNeeded()
            switch response.actionIdentifier {
            case NotificationActionCatalog.completeNudgeActionIdentifier:
                await completeTaskFromNotification(taskID: taskID)
            case UNNotificationDefaultActionIdentifier:
                await openTaskFromNotification(taskID: taskID)
            default:
                break
            }
            return
        }

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

    // MARK: - Deep-link Task Navigation

    private var pendingDeepLinkTaskID: UUID?

    /// Stored when openTaskFromNotification fires before HomeView.onReceive is alive (cold launch).
    /// HomeView.onAppear drains this via consumePendingHighlightTaskID() to apply scroll+highlight.
    private(set) var pendingHighlightTaskID: UUID?

    func rememberDeepLinkTaskID(_ id: UUID) {
        pendingDeepLinkTaskID = id
    }

    func consumeDeepLinkTaskIDIfAny() async {
        guard let id = pendingDeepLinkTaskID else { return }
        pendingDeepLinkTaskID = nil
        await openTaskFromNotification(taskID: id)
    }

    func consumePendingHighlightTaskID() -> UUID? {
        let id = pendingHighlightTaskID
        pendingHighlightTaskID = nil
        return id
    }

    func openTaskFromNotification(taskID: UUID) async {
        await bootstrapIfNeeded()
        router.currentSurface = .today
        // Store the id so HomeView.onAppear can drain it on cold launch, when onReceive hasn't
        // subscribed yet and the post below would fire into the void.
        pendingHighlightTaskID = taskID
        NotificationCenter.default.post(
            name: .openTaskFromNudge,
            object: nil,
            userInfo: ["task_id": taskID]
        )
    }

    func completeTaskFromNotification(taskID: UUID) async {
        await bootstrapIfNeeded()

        guard
            let spaceID = sessionStore.currentSpace?.id,
            let actorID = sessionStore.currentUser?.id
        else { return }

        do {
            _ = try await container.taskApplicationService.completeTask(
                in: spaceID, taskID: taskID, actorID: actorID
            )
            await flushRecordedSharedMutation(
                SyncChange(entityKind: .task, operation: .complete, recordID: taskID, spaceID: spaceID)
            )
            await homeViewModel.reload()
        } catch {
            appContextLogger.error("[Nudge] complete failed: \(error.localizedDescription)")
        }
    }
}

extension Notification.Name {
    static let openTaskFromNudge = Notification.Name("openTaskFromNudge")
}

extension AppContext {
    /// Handles the Realtime "partner deleted their space_members row" event.
    /// Triggered by SupabaseSyncService.handleMemberChange(.delete) → .pairMemberRemoved.
    /// Without this handler the device whose partner left would stay stuck displaying
    /// "已配对" forever (the bug reported during paired testing where 357 unpairs but
    /// 786 keeps showing paired state).
    @MainActor
    func handlePartnerLeftPairSpace() async {
        guard let pairSpace = sessionStore.currentPairSpace,
              pairSpace.status == .active,
              let userID = sessionStore.currentUser?.id else {
            return
        }
        let pairSpaceID = pairSpace.id
        do {
            _ = try await container.pairingService.unbind(pairSpaceID: pairSpaceID, actorID: userID)
            appContextLogger.info("[PairLeave] local unbind completed after partner left")
        } catch {
            appContextLogger.error("[PairLeave] local unbind failed: \(error.localizedDescription, privacy: .public)")
        }
        let updatedPairingCtx = await container.pairingService.currentPairingContext(for: userID)
        let updatedSpaceCtx = await container.spaceService.currentSpaceContext(for: userID)
        sessionStore.refresh(spaceContext: updatedSpaceCtx, pairingContext: updatedPairingCtx)
        await reloadAfterSync()
    }
}

extension AppContext: PairJoinObserver {
    func onSuccessfulPairJoin() async {
        // 1) Prompt for notification permission once (added by partner-nudge feature)
        let status = await container.notificationService.authorizationStatus()
        if status == .notDetermined {
            _ = try? await container.notificationService.requestAuthorization()
        }

        // 2) Refresh sessionStore so pairSpaceSummary reflects the new active state.
        //    Why: this observer is invoked BEFORE the calling ViewModel runs
        //    `apply(pairingContext:)` (CloudPairingService.checkAndFinalizeIfAccepted →
        //    pairJoinObserver?.onSuccessfulPairJoin → return → ProfileViewModel.apply).
        //    Without an explicit refresh here the host side would see a stale
        //    pairSpaceSummary, the `status == .active` guard in startSupabaseSyncIfNeeded
        //    would fail, and pair sync would never start until the user toggled
        //    scenePhase. That race is exactly the "host sees nothing from partner"
        //    failure mode reported during paired testing.
        if let userID = sessionStore.currentUser?.id {
            let updatedPairingCtx = await container.pairingService.currentPairingContext(for: userID)
            let updatedSpaceCtx = await container.spaceService.currentSpaceContext(for: userID)
            sessionStore.refresh(spaceContext: updatedSpaceCtx, pairingContext: updatedPairingCtx)
        }

        // 3) Start pair sync (idempotent). startListening internally runs catchUp,
        //    so the partner's avatar / nickname / existing tasks land in local DB
        //    before the user hits Home.
        await startSupabaseSyncIfNeeded()

        // 4) Eagerly push own profile (display name + avatar) so the partner sees
        //    correct nickname/avatar within seconds instead of waiting for the
        //    next profile-edit save. updateSyncPolling's seedPairMetadata path
        //    also covers this, but only fires when the SwiftUI onChange picks up
        //    pairSpaceSummary — that observer can be late on the host side.
        //    syncProfileToPartner is a no-op when there's no shared mutation
        //    queued, and dedupes server-side by upsert, so calling it twice is
        //    safe.
        if let user = sessionStore.currentUser {
            await syncProfileToPartner(user: user)
        }
        appContextLogger.info("[PairJoin] sync started + initial catchUp + profile push completed")
    }
}

// MARK: - Premium lifecycle

extension AppContext {
    /// 登入成功或冷启动已登入时调用。
    /// 串行：若有前一个 premium task（configure/teardown/refresh）仍在跑，先等它完成。
    func configurePremiumGate() async {
        let previous = premiumGateTask
        let task = Task { @MainActor in
            if let previous { await previous.value }
            await self.runConfigurePremiumGate()
        }
        premiumGateTask = task
        await task.value
    }

    /// 登出时调用。
    func teardownPremiumGate() async {
        let previous = premiumGateTask
        let task = Task { @MainActor in
            if let previous { await previous.value }
            await self.runTeardownPremiumGate()
        }
        premiumGateTask = task
        await task.value
    }

    /// 前台激活时的条件刷新。1 小时内已刷过就 no-op。
    func refreshPremiumGateIfStale() async {
        if let last = lastPremiumRefreshAt,
           Date().timeIntervalSince(last) < Self.premiumRefreshInterval {
            return
        }
        let previous = premiumGateTask
        let task = Task { @MainActor in
            if let previous { await previous.value }
            await self.container.premiumGate.refresh()
            self.lastPremiumRefreshAt = Date()
            premiumLogger.info("PremiumGate refreshed → \(String(describing: self.container.premiumGate.status), privacy: .public)")
        }
        premiumGateTask = task
        await task.value
    }

    private static let premiumRefreshInterval: TimeInterval = 3600

    private func runConfigurePremiumGate() async {
        // 关键：用 **Supabase** auth.uid 作为身份锚点，而不是本地 `User.id`。
        // - `premium_grants` 的 RLS 按 `auth.uid() = user_id` 过滤，查询时依赖 session。
        // - RC `appUserID` 必须和 Supabase auth 对齐（spec § 1），否则订阅状态在设备间不连续。
        // 本地 `sessionStore.currentUser.id` 是 Apple Sign-In 生成的独立 UUID，和
        // Supabase `auth.users.id` 是两套（详见历史身份不对齐笔记），**不能**通用。
        //
        // RC 启动顺序（防 paywall fatal）：先 anonymous configure（无 appUserID），
        // 这样未登录用户进 paywall 也能拉 offerings；登录后用 `logIn` 把 anonymous
        // 购买 alias 到真 Supabase user（RC 自动 merge）。
        if !Purchases.isConfigured {
            RevenueCatConfig.assertProductionKeyConfigured()
            Purchases.configure(withAPIKey: RevenueCatConfig.publicSDKKey)
            premiumLogger.info("RC anonymous configure")
        }

        guard let supabaseUserID = await supabaseAuth.currentUserID else {
            premiumLogger.debug("configurePremiumGate skipped: no active Supabase session (RC stays anonymous)")
            return
        }
        let appUserID = supabaseUserID.uuidString

        do {
            _ = try await Purchases.shared.logIn(appUserID)
            premiumLogger.info("RC logIn ok for user \(appUserID, privacy: .private(mask: .hash))")
        } catch {
            premiumLogger.error("RC logIn failed: \(error.localizedDescription, privacy: .public)")
        }

        await container.premiumGate.bootstrap(userID: supabaseUserID)
        lastPremiumRefreshAt = Date()
        premiumLogger.info("PremiumGate bootstrapped → \(String(describing: self.container.premiumGate.status), privacy: .public)")
    }

    private func runTeardownPremiumGate() async {
        do {
            _ = try await Purchases.shared.logOut()
        } catch {
            // Purchases.logOut 在"已是匿名"时会抛错——无害，调低为 debug
            premiumLogger.debug("RC logOut noop/failed: \(error.localizedDescription, privacy: .public)")
        }
        container.premiumGate.logOut()
        lastPremiumRefreshAt = nil
        premiumLogger.info("PremiumGate torn down")
    }

    /// Pro → Free 运行时转变处理（P2.1）。由 TogetherApp 的 `.onChange(of: premiumGate.isPremium)`
    /// 触发。只有 true → false 的翻转才需要干预：关掉当前跑着的 CKSyncEngine，
    /// 避免非 Pro 用户继续享受跨设备同步到下次冷启动才停。
    ///
    /// Pro→Free 运行时：数据面停同步 + UI 面通过 rootPaywallPresentation 弹 lapse sheet。
    /// spec § 2.5。
    func handlePremiumStatusChange(wasPremium: Bool, isPremium: Bool) async {
        guard wasPremium, !isPremium else { return }
        premiumLogger.info("Premium lapsed at runtime — stopping solo sync")
        await container.syncEngineCoordinator.stopSoloSync()
        // 清 debounce 时间戳：下次前台再回时立即 refresh 拿最新状态（可能是网络恢复导致的误判）
        lastPremiumRefreshAt = nil

        #if DEBUG
        // DEBUG override picker 切 Pro→Free 会反复触发；不自动推 UI 避免骚扰。
        // 开发者测 lapse UI 走 ProfileDebugSection 的手动按钮。
        if container.premiumGate.overrideStatus != nil {
            premiumLogger.info("paywall.lapse.skippedForOverride")
            return
        }
        #endif

        let now = Date()
        let expiredAt = container.premiumGate.latestEntitlementExpiration
        let dedupKey = PremiumLapseNotice.dedupKey(expiredAt: expiredAt, detectedAt: now)

        guard !lapseAcknowledgedStore.contains(dedupKey) else {
            premiumLogger.info("paywall.lapse.deduped dedupKey=\(dedupKey, privacy: .public)")
            return
        }

        let notice = PremiumLapseNotice(
            entitlementExpiredAt: expiredAt,
            detectedAt: now,
            dedupKey: dedupKey
        )
        premiumLogger.info("paywall.lapse.requested dedupKey=\(dedupKey, privacy: .public)")
        rootPaywallPresentation.requestLapse(notice)
    }

    /// 付费墙 sheet 关闭后的统一清理入口。由 AppRootView 观察 `rootPaywallPresentation.presenting`
    /// 从非 nil 变 nil 时调用。Session A § 5.2。
    func paywallDidDismiss(kind: RootPaywallPresentation.Kind) {
        switch kind {
        case .quota(.projectQuota):
            projectsViewModel.dismissUpsell()
        case .quota(.anniversaryQuota):
            importantDatesViewModel.dismissUpsell()
        case .lapse(let notice):
            lapseAcknowledgedStore.insert(notice.dedupKey)
            premiumLogger.info("paywall.lapse.acknowledged dedupKey=\(notice.dedupKey, privacy: .public)")
        case .quota(.logbookHistory), .quota(.crossDeviceSync):
            // Session B/C 接入 VM 源后补
            break
        case .quota(.graceExpiring):
            // Banner 触发，无 VM dismiss 回调；用户主动 retry / 忽略均无副作用
            break
        }
    }

    /// 自动检查 invite 是否已被接受——冷启动 + scene 激活时触发。
    /// 没有这个自动化，发出邀请后要用户主动点"检查是否已接受"按钮才能 sync 本地状态，
    /// 稍一遗忘 iPhone 就会一直停在 `invitePending`，即使对端 iPad 早已接受。
    func autoCheckInviteAcceptedIfPending() async {
        guard sessionStore.bindingState == .invitePending else { return }
        await profileViewModel.checkInviteAccepted()
    }
}
