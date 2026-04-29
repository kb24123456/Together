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

enum StartupRestorePresentationState: Equatable {
    case idle
    case restoring(isSlow: Bool)
    case failed

    var isVisible: Bool {
        self != .idle
    }
}

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
    private(set) var startupRestorePresentationState: StartupRestorePresentationState = .idle
    private var hasCompletedPostLaunchWork = false
    private var hasSyncedReminderNotifications = false
    private var hasRestoredPersistedUserProfile = false
    private var hasHydratedOwnProfile = false
    private var seededPairMetadataSpaceIDs: Set<UUID> = []
    private var supabaseSyncService: SupabaseSyncService?
    private var isStartingSupabaseSync = false  // 防止 startSupabaseSyncIfNeeded 多 Task 并发穿 guard
    private let supabaseAuth: SupabaseAuthService
    private var activeSharedSpaceID: UUID?

    /// Supabase auth.uid of the current device's signed-in user. Cached on
    /// pair-sync startup; nil before sign-in or while sync is being torn down.
    /// Stable across UI refreshes and survives Sign-in-with-Apple sessions on
    /// the same Apple ID, so it's the right key for cross-device-unique
    /// identity (e.g. ImportantDateKind.birthday(memberUserID:) in 1.0.1+
    /// uses this rather than the local-only User.id which differs per device).
    private(set) var currentSupabaseUserID: UUID?

    /// Supabase auth.uid of the paired partner. Resolved by reading
    /// space_members and excluding `currentSupabaseUserID`. Set when a pair
    /// sync starts; cleared on teardown.
    private(set) var partnerSupabaseUserID: UUID?

    // Premium 生命周期：configure/teardown/refresh 通过任务链串行化，
    // 避免快速登入-登出-再登入导致的 RC configure vs logIn 竞争。
    private var premiumGateTask: Task<Void, Never>?
    private var lastPremiumRefreshAt: Date?
    private var startupRestoreSlowTask: Task<Void, Never>?
    private var startupRestoreRetryTask: Task<Void, Never>?

    init(container: AppContainer, sessionStore: SessionStore, router: AppRouter, appearanceManager: AppearanceManager = AppearanceManager()) {
        self.container = container
        self.supabaseAuth = container.supabaseAuthService
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
            if await shouldPresentStartupRestoreUI(requiresPremium: false) {
                beginStartupRestorePresentation()
            }
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
        //   3. 启动 Supabase solo recovery（Pro-only）。
        //   4. 暂时保留 CKSyncEngine solo（Pro-only）。
        //   5. 启动 Supabase 双人同步。
        if sessionStore.authState == .signedIn {
            _ = await supabaseAuth.restoreSession()
            await configurePremiumGate()
            let presentsStartupRestore = await shouldPresentStartupRestoreUI()
            if presentsStartupRestore {
                if startupRestorePresentationState.isVisible == false {
                    beginStartupRestorePresentation()
                }
            } else if startupRestorePresentationState.isVisible {
                finishStartupRestorePresentation()
            }
            let didCompleteSoloRecovery = await startSupabaseSoloSyncRecoveryIfNeeded()
            if presentsStartupRestore, didCompleteSoloRecovery {
                await reloadAfterSync()
                finishStartupRestorePresentation()
            }
            await startSoloSyncEngineIfNeeded()
            // user_profiles hydrate 必须在 startSupabaseSyncIfNeeded 之前 await 完成，
            // 否则 pair sync 启动后 push 路径可能用旧的 local 覆盖云端最新值。
            await hydrateOwnProfileFromCloudIfNeeded()
            await hydratePairSpaceFromCloudIfNeeded()
            await startSupabaseSyncIfNeeded()
            // 自动检查是否有待接受的邀请已被对端接受
            await autoCheckInviteAcceptedIfPending()
        }

        StartupTrace.mark("AppContext.postLaunch.end")
    }

    private func startSupabaseSoloSyncRecoveryIfNeeded() async -> Bool {
        guard let supabaseUserID = await supabaseAuth.currentUserID else {
            appContextLogger.debug("[SupabaseSolo] recovery skipped: no active Supabase session")
            if startupRestorePresentationState.isVisible {
                failStartupRestorePresentation()
            }
            return false
        }

        let displayName = sessionStore.currentUser?.displayName ?? "我"
        guard let localUserID = sessionStore.currentUser?.id else {
            appContextLogger.debug("[SupabaseSolo] recovery skipped: no local user")
            if startupRestorePresentationState.isVisible {
                failStartupRestorePresentation()
            }
            return false
        }

        do {
            try await container.supabaseSoloSyncService.start(
                userID: supabaseUserID,
                localUserID: localUserID,
                displayName: displayName,
                platform: .current,
                isPro: container.premiumGate.isPremium
            )
            appContextLogger.info("[SupabaseSolo] recovery completed")
        } catch SoloSyncServiceError.requiresPro {
            appContextLogger.info("[SupabaseSolo] recovery skipped: requires Pro")
            finishStartupRestorePresentation()
            return false
        } catch {
            appContextLogger.error("[SupabaseSolo] recovery failed: \(error.localizedDescription, privacy: .public)")
            failStartupRestorePresentation()
            return false
        }

        await refreshSessionSpaceContext(for: localUserID)
        return true
    }

    private func refreshSessionSpaceContext(for userID: UUID) async {
        let updatedSpaceContext = await container.spaceService.currentSpaceContext(for: userID)
        sessionStore.refresh(spaceContext: updatedSpaceContext, pairingContext: sessionStore.pairingContext)
    }

    private func shouldPresentStartupRestoreUI(requiresPremium: Bool = true) async -> Bool {
        guard sessionStore.authState == .signedIn else { return false }
        guard sessionStore.selectedWorkspace == .single else { return false }
        guard requiresPremium == false || container.premiumGate.isPremium else { return false }
        guard let spaceID = sessionStore.singleSpace?.id else { return false }

        do {
            let localItems = try await container.itemRepository.fetchActiveItems(spaceID: spaceID)
            return localItems.isEmpty
        } catch {
            appContextLogger.error("[StartupRestoreUI] local preflight failed: \(error.localizedDescription, privacy: .public)")
            return true
        }
    }

    private func beginStartupRestorePresentation(cancelsRetry: Bool = true) {
        startupRestoreSlowTask?.cancel()
        if cancelsRetry {
            startupRestoreRetryTask?.cancel()
        }
        startupRestorePresentationState = .restoring(isSlow: false)
        startupRestoreSlowTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(3))
            guard let self, Task.isCancelled == false else { return }
            if case .restoring = self.startupRestorePresentationState {
                self.startupRestorePresentationState = .restoring(isSlow: true)
            }
        }
    }

    private func finishStartupRestorePresentation() {
        startupRestoreSlowTask?.cancel()
        startupRestoreRetryTask?.cancel()
        startupRestoreSlowTask = nil
        startupRestoreRetryTask = nil
        startupRestorePresentationState = .idle
    }

    private func failStartupRestorePresentation() {
        startupRestoreSlowTask?.cancel()
        startupRestoreSlowTask = nil
        startupRestorePresentationState = .failed
        scheduleStartupRestoreRetry()
    }

    private func scheduleStartupRestoreRetry() {
        startupRestoreRetryTask?.cancel()
        startupRestoreRetryTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(15))
            guard let self, Task.isCancelled == false else { return }
            guard self.startupRestorePresentationState == .failed else { return }
            guard self.sessionStore.authState == .signedIn, self.container.premiumGate.isPremium else {
                self.finishStartupRestorePresentation()
                return
            }

            self.beginStartupRestorePresentation(cancelsRetry: false)
            let didCompleteSoloRecovery = await self.startSupabaseSoloSyncRecoveryIfNeeded()
            if didCompleteSoloRecovery {
                await self.reloadAfterSync()
                self.finishStartupRestorePresentation()
            }
        }
    }

    // MARK: - CKSyncEngine Setup

    /// Starts the CKSyncEngine-based solo zone sync for single-mode data.
    private func startSoloSyncEngineIfNeeded() async {
        let soloSpaceID = sessionStore.singleSpace?.id
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
                await self.reloadAfterSync()
            }
        }
        await container.syncEngineCoordinator.performStartupSync()

        if let soloSpaceID {
            await enqueueExistingSoloDataForCloudBackup(spaceID: soloSpaceID)
        }
    }

    private func enqueueExistingSoloDataForCloudBackup(spaceID: UUID) async {
        guard await container.syncEngineCoordinator.isRunningSolo else { return }

        let context = ModelContext(PersistenceController.shared.container)
        let archivedSpaceStatus = SpaceStatus.archived.rawValue
        if let space = try? context.fetch(
            FetchDescriptor<PersistentSpace>(
                predicate: #Predicate<PersistentSpace> { $0.id == spaceID && $0.statusRawValue != archivedSpaceStatus }
            )
        ).first {
            await container.syncCoordinator.recordLocalChange(
                SyncChange(entityKind: .space, operation: .upsert, recordID: space.id, spaceID: spaceID)
            )
        }

        let optionalSpaceID: UUID? = spaceID
        let items = (try? context.fetch(
            FetchDescriptor<PersistentItem>(
                predicate: #Predicate<PersistentItem> {
                    $0.spaceID == optionalSpaceID && $0.isLocallyDeleted == false
                }
            )
        )) ?? []
        for item in items {
            await container.syncCoordinator.recordLocalChange(
                SyncChange(
                    entityKind: .task,
                    operation: item.isArchived ? .archive : .upsert,
                    recordID: item.id,
                    spaceID: spaceID
                )
            )
        }

        let lists = (try? await container.taskListRepository.fetchTaskLists(spaceID: spaceID)) ?? []
        for list in lists {
            await container.syncCoordinator.recordLocalChange(
                SyncChange(entityKind: .taskList, operation: list.isArchived ? .archive : .upsert, recordID: list.id, spaceID: spaceID)
            )
        }

        let projects = (try? await container.projectRepository.fetchProjects(spaceID: spaceID)) ?? []
        for project in projects {
            await container.syncCoordinator.recordLocalChange(
                SyncChange(
                    entityKind: .project,
                    operation: project.status == .archived ? .archive : .upsert,
                    recordID: project.id,
                    spaceID: spaceID
                )
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

        await container.syncEngineCoordinator.sendChanges(for: spaceID)
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
            avatarUploader: container.avatarUploader,
            userProfileRemote: container.userProfileRemote
        )
        let localUserID = sessionStore.currentUser?.id
        await service.configure(spaceID: sharedSpaceID, myUserID: myUserID, myLocalUserID: localUserID)

        // 先把 service 记录到 AppContext，再 startListening。
        // 这样即便 startListening 内部 await 很久，其他 Task 的 `supabaseSyncService != nil` 也会挡住。
        self.supabaseSyncService = service
        self.activeSharedSpaceID = sharedSpaceID
        self.currentSupabaseUserID = myUserID
        sessionStore.updateSharedSyncStatus(SharedSyncStatus(level: .syncing, pendingMutationCount: 0, failedMutationCount: 0))

        // Resolve partner's supabase user_id from space_members.
        // Detached so we don't block the main sync startup.
        Task { [weak self] in
            guard let self else { return }
            let partnerID = await Self.resolvePartnerSupabaseUserID(
                spaceID: sharedSpaceID,
                excluding: myUserID
            )
            await MainActor.run {
                self.partnerSupabaseUserID = partnerID
            }
        }

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
        currentSupabaseUserID = nil
        partnerSupabaseUserID = nil
        isStartingSupabaseSync = false
        seededPairMetadataSpaceIDs.remove(pairSpaceID)
        sessionStore.updateSharedSyncStatus(.idle)
    }

    /// Reads the partner's Supabase auth.uid by querying space_members and
    /// excluding the current user's own row. Returns nil if the row hasn't
    /// landed yet (Realtime ordering can place this call before the partner's
    /// INSERT replicates) — caller should be prepared for a transient nil.
    nonisolated private static func resolvePartnerSupabaseUserID(
        spaceID: UUID,
        excluding selfID: UUID
    ) async -> UUID? {
        struct Row: Decodable { let userId: UUID; enum CodingKeys: String, CodingKey { case userId = "user_id" } }
        let rows: [Row]? = try? await SupabaseClientProvider.shared.from("space_members")
            .select("user_id")
            .eq("space_id", value: spaceID.uuidString)
            .neq("user_id", value: selfID.uuidString)
            .execute()
            .value
        return rows?.first?.userId
    }

    /// Pushes the user's profile to the user-scoped `user_profiles` table.
    ///
    /// Independent of pair status — runs in single mode too, so that reinstall
    /// + SIWA can later hydrate displayName/avatar back from the cloud.
    /// Avatar bytes are uploaded at `users/{userID}/{version}.jpg` (see
    /// AvatarStorageUploader.uploadAvatarUserScoped). Best-effort: any error
    /// is logged but not surfaced — local save has already succeeded.
    ///
    /// `force=true` re-uploads bytes even if avatarVersion hasn't bumped.
    /// Default skips redundant byte uploads via UserDefaults watermark
    /// `together.userProfile.lastSyncedAvatarVersion.{userID}`.
    func syncOwnProfileToCloud(user: User, force: Bool = false) async {
        guard let supabaseUserID = await supabaseAuth.currentUserID else {
            appContextLogger.debug("[OwnProfile] sync skipped: no active Supabase session")
            return
        }

        let watermarkKey = Self.userProfileCloudWatermarkKey(supabaseUserID: supabaseUserID)
        let lastSyncedVersion = UserDefaults.standard.integer(forKey: watermarkKey)
        var avatarURLString: String?

        // Avatar bytes upload — only if we actually have a photo on disk and
        // version has bumped (or caller forces).
        if user.avatarAssetID != nil,
           let fileName = user.avatarCacheFileName {
            let avatarStore = LocalUserAvatarMediaStore()
            let shouldUpload = (force || user.avatarVersion > lastSyncedVersion) && avatarStore.fileExists(named: fileName)
            if shouldUpload {
                do {
                    let bytes = try avatarStore.avatarData(named: fileName)
                    let signed = try await container.avatarUploader.uploadAvatarUserScoped(
                        bytes: bytes,
                        userID: supabaseUserID,
                        version: user.avatarVersion
                    )
                    avatarURLString = signed.absoluteString
                    UserDefaults.standard.set(user.avatarVersion, forKey: watermarkKey)
                    appContextLogger.info("[OwnProfile] avatar uploaded version=\(user.avatarVersion) bytes=\(bytes.count)")
                } catch {
                    appContextLogger.error("[OwnProfile] avatar upload failed: \(error.localizedDescription, privacy: .public)")
                    // Fall through with avatarURLString=nil; row upsert still
                    // proceeds so displayName / metadata at least propagate.
                }
            }
        }

        var existingAvatarURLString: String?
        if avatarURLString == nil, user.avatarAssetID != nil {
            do {
                existingAvatarURLString = try await container.userProfileRemote.fetchOwn()?.avatarURL
            } catch {
                appContextLogger.error("[OwnProfile] existing avatar URL fetch failed: \(error.localizedDescription, privacy: .public)")
            }
        }

        let dto = Self.makeCloudUserProfileDTO(
            from: user,
            supabaseUserID: supabaseUserID,
            avatarURLString: Self.resolvedCloudAvatarURLString(
                for: user,
                uploadedAvatarURLString: avatarURLString,
                existingAvatarURLString: existingAvatarURLString
            )
        )
        do {
            try await container.userProfileRemote.upsertOwn(dto)
            appContextLogger.info("[OwnProfile] upserted user_profiles version=\(user.avatarVersion)")
        } catch {
            appContextLogger.error("[OwnProfile] upsertOwn failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    nonisolated static func userProfileCloudWatermarkKey(supabaseUserID: UUID) -> String {
        "together.userProfile.lastSyncedAvatarVersion.\(supabaseUserID.uuidString.lowercased())"
    }

    nonisolated static func resolvedCloudAvatarURLString(
        for user: User,
        uploadedAvatarURLString: String?,
        existingAvatarURLString: String?
    ) -> String? {
        if let uploadedAvatarURLString {
            return uploadedAvatarURLString
        }
        if user.avatarAssetID != nil {
            return existingAvatarURLString
        }
        return nil
    }

    nonisolated static func makeCloudUserProfileDTO(
        from user: User,
        supabaseUserID: UUID,
        avatarURLString: String?
    ) -> UserProfileDTO {
        UserProfileDTO(
            userID: supabaseUserID,
            displayName: user.displayName,
            avatarURL: avatarURLString,
            avatarAssetID: user.avatarAssetID,
            avatarSystemName: user.avatarSystemName,
            avatarVersion: user.avatarVersion,
            updatedAt: nil
        )
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

    /// Pulls the user's profile from `user_profiles` if cloud is fresher than
    /// local. Runs once per cold start, before pair sync starts so partner
    /// pushes don't race against our hydrate.
    ///
    /// Triggers hydrate when:
    ///   - local.displayName 为空 且 dto.displayName 非空（重装+SIWA 后 SwiftData 空）
    ///   - dto.avatarVersion > local.avatarVersion（多端编辑追赶）
    ///
    /// Best-effort: any failure (no session / network / nil row) is logged
    /// and the function returns silently. Does NOT mutate local state when
    /// remote is stale or equal; that's syncOwnProfileToCloud's job at next
    /// onProfileSaved.
    func hydrateOwnProfileFromCloudIfNeeded() async {
        guard hasHydratedOwnProfile == false else { return }
        guard sessionStore.authState == .signedIn,
              let localUser = sessionStore.currentUser else { return }

        let dto: UserProfileDTO?
        do {
            dto = try await container.userProfileRemote.fetchOwn()
        } catch {
            appContextLogger.error("[OwnProfile] hydrate fetchOwn failed: \(error.localizedDescription, privacy: .public)")
            return
        }

        guard let dto else {
            // 云端没有 row — 026 backfill 兜底应该让现有用户都有；新用户走 onProfileSaved
            // 触发首次 upsert。这里 nothing to do。
            hasHydratedOwnProfile = true
            return
        }

        let localEmpty = localUser.displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let cloudHasName = dto.displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
        let cloudVersionNewer = dto.avatarVersion > localUser.avatarVersion
        let shouldHydrate = (localEmpty && cloudHasName) || cloudVersionNewer

        guard shouldHydrate else {
            hasHydratedOwnProfile = true
            appContextLogger.info("[OwnProfile] hydrate skip — local up-to-date (localVer=\(localUser.avatarVersion) cloudVer=\(dto.avatarVersion))")
            return
        }

        // 下载头像 bytes（如果云端有 url 且 assetID）
        var avatarBytes: Data?
        if let urlString = dto.avatarURL,
           let url = URL(string: urlString),
           dto.avatarAssetID != nil {
            do {
                avatarBytes = try await container.avatarUploader.downloadAvatar(from: url)
            } catch {
                appContextLogger.error("[OwnProfile] hydrate avatar download failed: \(error.localizedDescription, privacy: .public)")
                // 继续 hydrate displayName / metadata,头像下次启动再补
            }
        }

        do {
            let hydrated = try await container.userProfileRepository.hydrateFromRemote(
                for: localUser,
                displayName: dto.displayName,
                avatarBytes: avatarBytes,
                avatarAssetID: dto.avatarAssetID,
                avatarSystemName: dto.avatarSystemName,
                avatarVersion: dto.avatarVersion
            )
            sessionStore.currentUser = hydrated
            hasHydratedOwnProfile = true
            // 同步成功后,把 watermark 也更新,避免下次 syncOwnProfileToCloud 误判要重传 bytes
            let watermarkKey = Self.userProfileCloudWatermarkKey(supabaseUserID: dto.userID)
            UserDefaults.standard.set(dto.avatarVersion, forKey: watermarkKey)
            appContextLogger.info("[OwnProfile] hydrated displayName=\(hydrated.displayName, privacy: .private) version=\(dto.avatarVersion)")
        } catch {
            appContextLogger.error("[OwnProfile] hydrate persist failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Reinstall recovery (1.0.1 §10): when local SwiftData is empty after a
    /// fresh install but Supabase has an active pair space the user belongs to,
    /// rebuild the local PersistentPairSpace + both PersistentPairMembership
    /// rows from cloud data so the UI returns to its paired state without
    /// requiring the user to re-pair manually.
    ///
    /// Triggered after `hydrateOwnProfileFromCloudIfNeeded()` in the
    /// post-launch sequence; idempotent — bails out when local PairSpace is
    /// already active.
    func hydratePairSpaceFromCloudIfNeeded() async {
        guard let myAuthUID = await supabaseAuth.currentUserID else { return }
        guard let localUser = sessionStore.currentUser else { return }

        let modelContainer = PersistenceController.shared.container
        let context = ModelContext(modelContainer)

        // Bail if local already has an active pair space — no recovery needed.
        let existingSpaces = (try? context.fetch(FetchDescriptor<PersistentPairSpace>())) ?? []
        if existingSpaces.contains(where: { $0.statusRawValue == "active" }) {
            appContextLogger.info("[PairRestore] skip — local pair space already active")
            return
        }

        // Find an active space I belong to via PostgREST inner join.
        struct SpaceRow: Decodable {
            let id: UUID
            let displayName: String
            let createdAt: Date
            let ownerUserId: UUID
            enum CodingKeys: String, CodingKey {
                case id
                case displayName = "display_name"
                case createdAt = "created_at"
                case ownerUserId = "owner_user_id"
            }
        }

        let spaceRows: [SpaceRow]
        do {
            spaceRows = try await SupabaseClientProvider.shared
                .from("spaces")
                .select("id, display_name, created_at, owner_user_id, space_members!inner(user_id)")
                .eq("status", value: "active")
                .eq("space_members.user_id", value: myAuthUID.uuidString)
                .order("created_at", ascending: false)
                .limit(1)
                .execute()
                .value
        } catch {
            appContextLogger.error("[PairRestore] spaces query failed: \(error.localizedDescription, privacy: .public)")
            return
        }
        guard let space = spaceRows.first else {
            appContextLogger.info("[PairRestore] no active pair space found in cloud for current user")
            return
        }

        // Pull both members of that space.
        struct MemberRow: Decodable {
            let userId: UUID
            let displayName: String
            let avatarUrl: String?
            let avatarAssetId: String?
            let avatarSystemName: String?
            let avatarVersion: Int?
            let joinedAt: Date
            enum CodingKeys: String, CodingKey {
                case userId = "user_id"
                case displayName = "display_name"
                case avatarUrl = "avatar_url"
                case avatarAssetId = "avatar_asset_id"
                case avatarSystemName = "avatar_system_name"
                case avatarVersion = "avatar_version"
                case joinedAt = "joined_at"
            }
        }
        let members: [MemberRow]
        do {
            members = try await SupabaseClientProvider.shared
                .from("space_members")
                .select("user_id, display_name, avatar_url, avatar_asset_id, avatar_system_name, avatar_version, joined_at")
                .eq("space_id", value: space.id.uuidString)
                .execute()
                .value
        } catch {
            appContextLogger.error("[PairRestore] members query failed: \(error.localizedDescription, privacy: .public)")
            return
        }
        guard members.count == 2,
              let mine = members.first(where: { $0.userId == myAuthUID }),
              let partner = members.first(where: { $0.userId != myAuthUID }) else {
            appContextLogger.info("[PairRestore] expected 2 members, got \(members.count) — skipping rebuild")
            return
        }

        // Build local SwiftData rows using exact PersistentPairSpace.init signature.
        // activatedAt: an "active" space was definitely activated — use createdAt as
        // a safe floor value since the cloud spaces table doesn't expose activated_at.
        let pairSpace = PersistentPairSpace(
            id: space.id,
            sharedSpaceID: space.id,
            statusRawValue: "active",
            displayName: nil,
            createdAt: space.createdAt,
            activatedAt: space.createdAt,
            endedAt: nil,
            cloudKitZoneName: space.id.uuidString,
            ownerRecordID: space.ownerUserId.uuidString,
            isZoneOwner: space.ownerUserId == myAuthUID
        )
        context.insert(pairSpace)

        let selfMembership = PersistentPairMembership(
            id: UUID(),
            pairSpaceID: pairSpace.id,
            userID: localUser.id,
            nickname: mine.displayName,
            joinedAt: mine.joinedAt,
            avatarSystemName: mine.avatarSystemName,
            avatarPhotoFileName: nil,
            avatarAssetID: mine.avatarAssetId,
            avatarVersion: mine.avatarVersion ?? 0
        )
        context.insert(selfMembership)

        // Partner gets a fresh local UUID — we don't have their device-local id
        // and never will (it's device-private). Existing partner-side code on
        // this device only knows them by this UUID anyway.
        let partnerMembership = PersistentPairMembership(
            id: UUID(),
            pairSpaceID: pairSpace.id,
            userID: UUID(),
            nickname: partner.displayName,
            joinedAt: partner.joinedAt,
            avatarSystemName: partner.avatarSystemName,
            avatarPhotoFileName: nil,
            avatarAssetID: partner.avatarAssetId,
            avatarVersion: partner.avatarVersion ?? 0
        )
        context.insert(partnerMembership)

        do {
            try context.save()
            appContextLogger.info("[PairRestore] rebuilt PairSpace \(space.id, privacy: .public)")
        } catch {
            appContextLogger.error("[PairRestore] save failed: \(error.localizedDescription, privacy: .public)")
            return
        }

        // Refresh sessionStore so UI picks up new pair state immediately.
        let updatedPairingCtx = await container.pairingService.currentPairingContext(for: localUser.id)
        let updatedSpaceCtx = await container.spaceService.currentSpaceContext(for: localUser.id)
        sessionStore.refresh(spaceContext: updatedSpaceCtx, pairingContext: updatedPairingCtx)
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
        if let supabaseSyncService {
            await supabaseSyncService.catchUp()
            let stillPaired = await validateRemotePairMembershipStillActive()
            if stillPaired {
                await reloadAfterSync()
            }
        } else {
            await startSupabaseSyncIfNeeded()
        }
    }

    /// Handles remote notifications routed through UIApplicationDelegate.
    /// CloudKit still owns solo restoration; pair APNs is an explicit trigger
    /// to catch up Supabase state because Realtime delivery can be missed while
    /// the app is foregrounded, suspended, or reconnecting.
    func handleRemoteNotification(_ userInfo: [AnyHashable: Any]) async {
        if Self.isPairRemoteNotification(userInfo) {
            await handlePairRemoteNotification(userInfo)
        } else {
            await handleCloudKitNotification(userInfo)
        }
    }

    func handlePairRemoteNotification(_ userInfo: [AnyHashable: Any]) async {
        await bootstrapIfNeeded()

        if Self.remoteNotificationEventType(userInfo) == "pair_unbound" {
            await handlePartnerLeftPairSpace()
            return
        }

        await syncPairSpaceIfNeeded()
    }

    private static func isPairRemoteNotification(_ userInfo: [AnyHashable: Any]) -> Bool {
        if remoteNotificationEventType(userInfo) != nil { return true }
        if userInfo["task_id"] != nil { return true }
        return false
    }

    private static func remoteNotificationEventType(_ userInfo: [AnyHashable: Any]) -> String? {
        userInfo["event_type"] as? String
    }

    private func validateRemotePairMembershipStillActive() async -> Bool {
        guard
            sessionStore.hasActivePairSpace,
            let sharedSpaceID = activeSharedSpaceID,
            let mySupabaseUserID = currentSupabaseUserID
        else {
            return true
        }

        struct Row: Decodable {
            let userId: UUID
            enum CodingKeys: String, CodingKey { case userId = "user_id" }
        }

        do {
            let rows: [Row] = try await SupabaseClientProvider.shared
                .from("space_members")
                .select("user_id")
                .eq("space_id", value: sharedSpaceID.uuidString)
                .neq("user_id", value: mySupabaseUserID.uuidString)
                .execute()
                .value

            if rows.isEmpty {
                await handlePartnerLeftPairSpace()
                return false
            }
        } catch {
            appContextLogger.error("[PairMembership] remote validation failed: \(error.localizedDescription, privacy: .public)")
        }

        return true
    }

    /// 本地数据变更后触发同步。
    /// Solo 变更走 Supabase recovery outbox + CKSyncEngine；pair 变更走 Supabase push。
    func syncAfterMutation(spaceID: UUID) {
        Task { [weak self] in
            guard let self else { return }
            let supabaseUserID = await self.supabaseAuth.currentUserID
            await self.pushSoloSupabaseMutationIfEligible(
                spaceID: spaceID,
                supabaseUserID: supabaseUserID
            )
        }

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

    func pushSoloSupabaseMutationIfEligible(
        spaceID: UUID,
        supabaseUserID: UUID?,
        platform: SoloDevicePlatform = .current
    ) async {
        guard let supabaseUserID else { return }
        guard sessionStore.singleSpace?.id == spaceID else { return }
        guard SoloSyncGate.decision(platform: platform, isPro: container.premiumGate.isPremium) == .allowed else {
            return
        }

        do {
            try await container.supabaseSoloSyncService.pushPending(
                spaceID: spaceID,
                userID: supabaseUserID
            )
        } catch {
            appContextLogger.error("[SupabaseSolo] mutation push failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    func flushRecordedSharedMutation(_ change: SyncChange) async {
        let supabaseUserID = await supabaseAuth.currentUserID
        await flushRecordedMutation(change, supabaseUserID: supabaseUserID)
    }

    func flushRecordedMutation(
        _ change: SyncChange,
        supabaseUserID: UUID?,
        platform: SoloDevicePlatform = .current
    ) async {
        if sessionStore.singleSpace?.id == change.spaceID {
            await pushSoloSupabaseMutationIfEligible(
                spaceID: change.spaceID,
                supabaseUserID: supabaseUserID,
                platform: platform
            )
            return
        }

        await supabaseSyncService?.push()
        await refreshSharedSyncStatusAsync()
    }

    private func submitSharedMutation(_ change: SyncChange) async {
        let serviceDescription = supabaseSyncService == nil ? "nil" : "active"
        appContextLogger.info("[SharedMutation] submit kind=\(change.entityKind.rawValue, privacy: .public) op=\(change.operation.rawValue, privacy: .public) recordID=\(change.recordID.uuidString, privacy: .public) spaceID=\(change.spaceID.uuidString, privacy: .public) supabaseService=\(serviceDescription, privacy: .public)")
        await container.syncCoordinator.recordLocalChange(change)
        await flushRecordedSharedMutation(change)
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
            Task {
                // user_profiles 是 user-scoped,无论是否配对都推
                await self.syncOwnProfileToCloud(user: user)
                // space_members 仍然 dual-write,1.0 老对端兼容
                await self.syncProfileToPartner(user: user)
            }
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
                    let pairSpaceIDs: Set<UUID> = await MainActor.run { [weak self] in
                        var ids = Set<UUID>()
                        if let activeSharedSpaceID = self?.activeSharedSpaceID {
                            ids.insert(activeSharedSpaceID)
                        }
                        if let summarySharedSpaceID = self?.sessionStore.pairSpaceSummary?.sharedSpace.id {
                            ids.insert(summarySharedSpaceID)
                        }
                        return ids
                    }
                    if pairSpaceIDs.contains(change.spaceID) {
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
        await container.syncEngineCoordinator.fetchChangesForSolo()
    }

    func handleNotificationResponse(_ response: UNNotificationResponse) async {
        if response.notification.request.content.userInfo["event_type"] as? String == "pair_unbound" {
            await bootstrapIfNeeded()
            await handlePartnerLeftPairSpace()
            return
        }

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

        // 3) Force teardown + full restart of pair sync. Why this is mandatory
        //    rather than just startSupabaseSyncIfNeeded:
        //    - Unbind → re-pair within one session leaves a stale
        //      supabaseSyncService bound to the old space's Realtime channel
        //      and lastSyncedAt watermark. The `service != nil` guard inside
        //      startSupabaseSyncIfNeeded would short-circuit, so the host
        //      keeps listening on the wrong channel and never receives the
        //      partner's task INSERT/UPDATE events (build-4 testing showed
        //      357 push-OK but receive-blank for 786's tasks).
        //    - Resetting lastSyncedAt forces a full distantPast catchUp on
        //      the new space, so first-frame state (existing rows + partner
        //      profile) is pulled atomically rather than depending on later
        //      Realtime deltas.
        if let staleSpaceID = sessionStore.currentPairSpace?.id {
            await teardownSupabaseSync(pairSpaceID: staleSpaceID)
        }
        if let newSharedSpaceID = sessionStore.pairSpaceSummary?.sharedSpace.id {
            UserDefaults.standard.removeObject(
                forKey: "together.supabase.lastSyncedAt.\(newSharedSpaceID.uuidString)"
            )
        }
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
        if !wasPremium, isPremium {
            premiumLogger.info("Premium activated at runtime — starting solo sync")
            await startSoloSyncEngineIfNeeded()
            return
        }

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
