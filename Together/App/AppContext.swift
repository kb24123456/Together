import Foundation
import Observation
import os
import SwiftData
import UIKit
import UserNotifications
import WidgetKit

private let appContextLogger = Logger(subsystem: "com.pigdog.Together", category: "AppContext")

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
    let ambientBackgroundSettings: AmbientBackgroundSettings
    let homeViewModel: HomeViewModel
    let profileViewModel: ProfileViewModel
    let routinesViewModel: RoutinesViewModel

    private(set) var hasBootstrapped = false
    private(set) var startupRestorePresentationState: StartupRestorePresentationState = .idle
    private var hasCompletedPostLaunchWork = false
    private var isPerformingPostLaunchWork = false
    private var hasEnteredBackgroundSinceLaunch = false
    private var hasSyncedReminderNotifications = false
    private var hasRestoredPersistedUserProfile = false
    private var startupRestoreSlowTask: Task<Void, Never>?
    private var reloadAfterSyncTask: Task<Void, Never>?
    private var reloadAfterSyncRevision = 0
    private var cloudImportConvergenceTask: Task<Void, Never>?
    private var postLaunchMaintenanceTask: Task<Void, Never>?
    private var pendingDeepLinkTaskID: UUID?
    private var pendingHighlightTaskID: UUID?

    private let todayWidgetContextStore: TodayWidgetSharedContextStore
    private let todayWidgetSnapshotWriter: TodayWidgetSnapshotWriter
    private let taskFollowActivityCoordinator: TaskFollowActivityCoordinator
    private let cloudImportConvergenceDelays: [Duration]
    private let cloudKitDiagnosticsEnabled = ProcessInfo.processInfo.arguments.contains(
        "-TogetherCloudKitDiagnostics"
    )

    private static let reloadAfterSyncCoalescingDelay: Duration = .milliseconds(180)

    init(
        container: AppContainer,
        sessionStore: SessionStore,
        router: AppRouter,
        appearanceManager: AppearanceManager? = nil,
        cloudImportConvergenceDelays: [Duration] = [.milliseconds(800), .seconds(4)]
    ) {
        self.container = container
        self.sessionStore = sessionStore
        self.router = router
        self.appearanceManager = appearanceManager ?? AppearanceManager()
        self.ambientBackgroundSettings = AmbientBackgroundSettings()
        self.cloudImportConvergenceDelays = cloudImportConvergenceDelays

        let todayWidgetContextStore = TodayWidgetSharedContextStore()
        self.todayWidgetContextStore = todayWidgetContextStore
        self.todayWidgetSnapshotWriter = TodayWidgetSnapshotWriter(
            itemRepository: container.itemRepository,
            contextStore: todayWidgetContextStore
        )
        self.taskFollowActivityCoordinator = TaskFollowActivityCoordinator(
            itemRepository: container.itemRepository
        )

        self.homeViewModel = HomeViewModel(
            sessionStore: sessionStore,
            taskApplicationService: container.taskApplicationService,
            itemRepository: container.itemRepository
        )
        self.routinesViewModel = RoutinesViewModel(
            sessionStore: sessionStore,
            periodicTaskApplicationService: container.periodicTaskApplicationService
        )
        self.profileViewModel = ProfileViewModel(
            sessionStore: sessionStore,
            userProfileRepository: container.userProfileRepository,
            notificationService: container.notificationService,
            itemRepository: container.itemRepository,
            taskApplicationService: container.taskApplicationService,
            taskListRepository: container.taskListRepository,
            projectRepository: container.projectRepository,
            periodicTaskRepository: container.periodicTaskRepository,
            reminderScheduler: container.reminderScheduler,
            personalDataDeletionService: container.personalDataDeletionService,
            biometricAuthService: container.biometricAuthService
        )
        configureCallbacks()
    }

    static func makeContext() throws -> AppContext {
        StartupTrace.mark("AppContext.make.begin")
        let container = try LocalServiceFactory.makeContainer()
        StartupTrace.mark("AppContext.make.containerReady")
        let context = AppContext(
            container: container,
            sessionStore: SessionStore(),
            router: AppRouter()
        )
        StartupTrace.mark("AppContext.make.end")
        return context
    }

    #if DEBUG
    static func makeBootstrappedContext() -> AppContext {
        let context: AppContext
        do {
            context = try AppContext.makeContext()
        } catch {
            preconditionFailure("[AppContext] Preview bootstrap failed: \(error)")
        }
        context.seedMockSession()
        context.hasBootstrapped = true
        return context
    }
    #endif

    func bootstrapIfNeeded(afterInitialCloudImport: Bool = false) async -> PersonalIdentityResolution {
        if hasBootstrapped,
           afterInitialCloudImport == false,
           let user = sessionStore.currentUser,
           let space = sessionStore.currentSpace {
            return .ready(user: user, space: space)
        }

        let resolution = container.personalIdentityService.resolve(
            afterInitialCloudImport: afterInitialCloudImport
        )
        if case let .ready(user, space) = resolution {
            await finishIdentityBootstrap(user: user, space: space)
        }
        return resolution
    }

    func startLocally() async throws -> PersonalIdentityResolution {
        let resolution = try container.personalIdentityService.startLocally()
        if case let .ready(user, space) = resolution {
            await finishIdentityBootstrap(user: user, space: space)
        }
        return resolution
    }

    private func finishIdentityBootstrap(user: User, space: Space) async {
        sessionStore.applyPersonalIdentity(user: user, space: space)
        await migrateLegacyProjectsIfNeeded()
        await normalizeMissingTaskDatesIfNeeded(referenceDate: .now)
        await restorePersistedUserProfileIfNeeded()
        hasBootstrapped = true
    }

    private func normalizeMissingTaskDatesIfNeeded(referenceDate: Date) async {
        guard let spaceID = sessionStore.currentSpace?.id else { return }
        do {
            _ = try await container.itemRepository.normalizeMissingTaskDates(
                spaceID: spaceID,
                referenceDate: referenceDate
            )
        } catch {
            appContextLogger.error(
                "[TaskDateNormalization] failed: \(error.localizedDescription, privacy: .public)"
            )
        }
    }

    func migrateLegacyProjectsIfNeeded() async {
        do {
            _ = try container.projectToTaskMigrationService.migrateLegacyProjectsToTasks(
                spaceID: sessionStore.currentSpace?.id
            )
        } catch {
            appContextLogger.error("[ProjectMigration] failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    func restorePersistedUserProfileIfNeeded(force: Bool = false) async {
        if force {
            hasRestoredPersistedUserProfile = false
        }
        guard hasRestoredPersistedUserProfile == false else { return }
        guard let user = sessionStore.currentUser else { return }
        hasRestoredPersistedUserProfile = true
        sessionStore.currentUser = await container.userProfileRepository.mergedUser(user) ?? user
    }

    func performPostLaunchWorkIfNeeded() async {
        guard hasCompletedPostLaunchWork == false, isPerformingPostLaunchWork == false else { return }
        isPerformingPostLaunchWork = true
        defer { isPerformingPostLaunchWork = false }
        StartupTrace.mark("AppContext.postLaunch.begin")
        await restorePersistedUserProfileIfNeeded()
        StartupTrace.mark("AppContext.postLaunch.profileRestored")
        await routinesViewModel.loadIfNeeded()
        StartupTrace.mark("AppContext.postLaunch.routinesLoaded")
        hasCompletedPostLaunchWork = true
        StartupTrace.mark("AppContext.postLaunch.end")

        postLaunchMaintenanceTask = Task { @MainActor [weak self] in
            guard let self else { return }
            await self.syncReminderNotificationsIfNeeded()
            StartupTrace.mark("AppContext.postLaunch.remindersSynced")
            await self.refreshTodayWidgetSnapshot()
            StartupTrace.mark("AppContext.postLaunch.widgetRefreshed")
            await self.reconcileFollowActivity(reason: .appActive)
        }
    }

    func handleAppBecameActive() async {
        guard hasCompletedPostLaunchWork, hasEnteredBackgroundSinceLaunch else { return }
        hasEnteredBackgroundSinceLaunch = false
        await homeViewModel.reload(reason: .sync)
        await profileViewModel.refreshNotificationAuthorization()
        await syncReminderNotifications()
        await refreshTodayWidgetSnapshot()
        if let spaceID = sessionStore.currentSpace?.id {
            _ = await taskFollowActivityCoordinator.reconcileAfterAppBecameActive(spaceID: spaceID)
        }
    }

    func handleAppEnteredBackground() {
        hasEnteredBackgroundSinceLaunch = true
    }

    func refreshTodayWidgetSnapshot() async {
        guard
            let spaceID = sessionStore.currentSpace?.id,
            let actorID = sessionStore.currentUser?.id
        else {
            todayWidgetContextStore.clear()
            do {
                try TodayWidgetSnapshotStore().write(.empty)
            } catch {
                appContextLogger.error("[WidgetSnapshot] clear failed: \(error.localizedDescription, privacy: .public)")
            }
            WidgetCenter.shared.reloadTimelines(ofKind: TodayWidgetConstants.listWidgetKind)
            return
        }

        todayWidgetContextStore.write(TodayWidgetSharedContext(spaceID: spaceID, actorID: actorID))
        do {
            try await todayWidgetSnapshotWriter.refreshTodayWidgetSnapshot()
        } catch {
            appContextLogger.error("[WidgetSnapshot] today write failed: \(error.localizedDescription, privacy: .public)")
        }
        WidgetCenter.shared.reloadTimelines(ofKind: TodayWidgetConstants.listWidgetKind)
    }

    func updateSyncPolling() {}

    func handleRemoteNotification(_ userInfo: [AnyHashable: Any]) async {
        _ = userInfo
        await reloadAfterSync()
    }

    @discardableResult
    func handleSuccessfulCloudImport() async -> Task<Void, Never> {
        cloudImportConvergenceTask?.cancel()
        await restorePersistedUserProfileIfNeeded(force: true)
        await reloadAfterSync()
        logCloudImportReload(stage: "immediate")

        let delays = cloudImportConvergenceDelays
        let task = Task { @MainActor [weak self] in
            for (index, delay) in delays.enumerated() {
                do {
                    try await Task.sleep(for: delay)
                } catch {
                    return
                }
                guard let self, Task.isCancelled == false else { return }
                await self.restorePersistedUserProfileIfNeeded(force: true)
                await self.reloadAfterSync()
                self.logCloudImportReload(stage: "retry-\(index + 1)")
            }
        }
        cloudImportConvergenceTask = task
        return task
    }

    func handleNotificationResponse(_ response: UNNotificationResponse) async {
        if let target = AppNotification.parseIdentifier(response.notification.request.identifier),
           target.targetType.isDailySummary {
            await handleDeepLink(.today)
            return
        }

        guard let taskID = taskID(from: response.notification.request.content.userInfo) else { return }

        switch response.actionIdentifier {
        case NotificationActionCatalog.completeActionIdentifier,
             NotificationActionCatalog.completeNudgeActionIdentifier:
            await completeTaskFromNotification(taskID)
        default:
            if let delay = NotificationActionCatalog.snoozeInterval(for: response.actionIdentifier) {
                await snoozeTaskFromNotification(taskID, delay: delay)
            } else {
                await handleDeepLink(.task(taskID))
            }
        }
    }

    func handleDeepLink(url: URL) {
        guard let deepLink = AppDeepLink(url: url) else {
            homeViewModel.externalRouteErrorMessage = "无法打开这个 Together 链接。"
            return
        }
        Task { await handleDeepLink(deepLink) }
    }

    func handleDeepLink(_ deepLink: AppDeepLink) async {
        switch deepLink {
        case .today:
            pendingDeepLinkTaskID = nil
            pendingHighlightTaskID = nil
            homeViewModel.clearExternalRouteFailure()
            router.resetToToday()
        case .newTask:
            requestTaskCreation()
        case .task(let taskID):
            router.resetToToday()
            await homeViewModel.reload(reason: .sync)

            guard homeViewModel.item(for: taskID) != nil else {
                pendingHighlightTaskID = nil
                homeViewModel.presentExternalRouteFailure(taskID: taskID)
                return
            }

            homeViewModel.clearExternalRouteFailure()
            pendingHighlightTaskID = taskID
            NotificationCenter.default.post(
                name: .openTaskFromNudge,
                object: nil,
                userInfo: ["task_id": taskID]
            )
        }
    }

    func rememberDeepLinkTaskID(_ id: UUID) {
        pendingDeepLinkTaskID = id
    }

    func consumeDeepLinkTaskIDIfAny() async {
        guard let taskID = pendingDeepLinkTaskID else { return }
        pendingDeepLinkTaskID = nil
        await handleDeepLink(.task(taskID))
    }

    func consumePendingHighlightTaskID() -> UUID? {
        let id = pendingHighlightTaskID
        pendingHighlightTaskID = nil
        return id
    }

    func requestTaskCreation(title: String? = nil) {
        pendingDeepLinkTaskID = nil
        pendingHighlightTaskID = nil
        homeViewModel.clearExternalRouteFailure()
        router.resetToToday()
        router.requestComposer(.newTask, title: title)
    }

    private func configureCallbacks() {
        homeViewModel.onTaskMutated = { [weak self] spaceID in
            self?.syncAfterMutation(spaceID: spaceID)
            Task { await self?.refreshTodayWidgetSnapshot() }
        }
        homeViewModel.onTaskFollowChanged = { [weak self] spaceID in
            Task { @MainActor in
                guard let self else { return }
                let result = await self.taskFollowActivityCoordinator.reconcile(
                    spaceID: spaceID,
                    reason: .userMutation
                )
                if result == .activitiesDisabled {
                    self.homeViewModel.presentOperationStatus("已关注，但实时活动未开启")
                }
            }
        }
        homeViewModel.onTodayDataChanged = { [weak self] in
            Task { await self?.refreshTodayWidgetSnapshot() }
        }
        homeViewModel.onConvertToPeriodicTask = { [weak self] title in
            guard let self else { return }
            router.pendingPeriodicCycle = nil
            router.requestComposer(.newPeriodicTask, title: title)
        }
        profileViewModel.onTaskMutated = { [weak self] spaceID in
            self?.syncAfterMutation(spaceID: spaceID)
        }
        profileViewModel.onProfileSaved = { [weak self] user in
            self?.sessionStore.currentUser = user
            Task { await self?.refreshTodayWidgetSnapshot() }
        }
        profileViewModel.onPersonalDataDeleted = { [weak self] _, _ in
            guard let self else { return }
            router.currentSurface = .today
            routinesViewModel.restoreCachedTasksForCurrentSpace()
            Task {
                await self.homeViewModel.reload(reason: .sync)
                await self.routinesViewModel.reload()
            }
        }
        homeViewModel.onRetryExternalTaskRoute = { [weak self] taskID in
            Task { await self?.handleDeepLink(.task(taskID)) }
        }
    }

    private func syncReminderNotificationsIfNeeded() async {
        guard hasSyncedReminderNotifications == false else { return }
        hasSyncedReminderNotifications = true
        await syncReminderNotifications()
    }

    private func syncReminderNotifications() async {
        guard let spaceID = sessionStore.currentSpace?.id else { return }
        StartupTrace.mark("AppContext.reminderSync.fetch.begin")
        let tasks = (try? await container.itemRepository.fetchActiveItems(spaceID: spaceID)) ?? []
        StartupTrace.mark("AppContext.reminderSync.tasksFetched count=\(tasks.count)")
        let projects = (try? await container.projectRepository.fetchProjects(spaceID: spaceID)) ?? []
        let periodicTasks = (try? await container.periodicTaskRepository.fetchActiveTasks(spaceID: spaceID)) ?? []
        StartupTrace.mark("AppContext.reminderSync.projectsFetched count=\(projects.count)")
        await container.reminderScheduler.resync(
            spaceID: spaceID,
            tasks: tasks,
            projects: projects,
            includeTaskReminders: sessionStore.currentUser?.preferences.taskReminderEnabled ?? true,
            includeDailySummary: (
                sessionStore.currentUser?.preferences.taskReminderEnabled ?? true
            ) && (
                sessionStore.currentUser?.preferences.dailySummaryEnabled ?? false
            )
        )
        for task in periodicTasks {
            await container.reminderScheduler.syncPeriodicTaskReminder(for: task, referenceDate: .now)
        }
        StartupTrace.mark("AppContext.reminderSync.resync.end")
    }

    private func syncAfterMutation(spaceID: UUID) {
        Task {
            await refreshTodayWidgetSnapshot()
            _ = await taskFollowActivityCoordinator.reconcile(
                spaceID: spaceID,
                reason: .dataChanged
            )
        }
    }

    private func reconcileFollowActivity(reason: TaskFollowReconcileReason) async {
        guard let spaceID = sessionStore.currentSpace?.id else { return }
        _ = await taskFollowActivityCoordinator.reconcile(spaceID: spaceID, reason: reason)
    }

    private func reloadAfterSync() async {
        reloadAfterSyncRevision &+= 1
        if reloadAfterSyncTask == nil {
            reloadAfterSyncTask = Task { @MainActor [weak self] in
                await self?.performCoalescedReloadAfterSync()
            }
        }
        await reloadAfterSyncTask?.value
    }

    private func performCoalescedReloadAfterSync() async {
        while true {
            try? await Task.sleep(for: Self.reloadAfterSyncCoalescingDelay)
            let appliedRevision = reloadAfterSyncRevision
            await normalizeMissingTaskDatesIfNeeded(referenceDate: .now)
            await homeViewModel.reload(reason: .sync)
            await routinesViewModel.reload()
            await refreshTodayWidgetSnapshot()
            await reconcileFollowActivity(reason: .dataChanged)
            guard appliedRevision == reloadAfterSyncRevision else { continue }
            break
        }
        await syncReminderNotifications()
        reloadAfterSyncTask = nil
        finishStartupRestorePresentation()
    }

    private func logCloudImportReload(stage: String) {
        guard cloudKitDiagnosticsEnabled else { return }
        print(
            "[CloudImportReload] stage=\(stage)"
                + " homeCount=\(homeViewModel.items.count)"
                + " revision=\(homeViewModel.reloadRevision)"
        )
    }

    private func beginStartupRestorePresentation() {
        startupRestoreSlowTask?.cancel()
        startupRestorePresentationState = .restoring(isSlow: false)
        startupRestoreSlowTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(3))
            guard let self, case .restoring = self.startupRestorePresentationState else { return }
            self.startupRestorePresentationState = .restoring(isSlow: true)
        }
    }

    private func finishStartupRestorePresentation() {
        startupRestoreSlowTask?.cancel()
        startupRestoreSlowTask = nil
        startupRestorePresentationState = .idle
    }

    private func taskID(from userInfo: [AnyHashable: Any]) -> UUID? {
        if let taskID = userInfo["task_id"] as? UUID {
            return taskID
        }
        if let taskIDString = userInfo["task_id"] as? String {
            return UUID(uuidString: taskIDString)
        }
        return nil
    }

    private func completeTaskFromNotification(_ taskID: UUID) async {
        guard
            let spaceID = sessionStore.currentSpace?.id,
            let actorID = sessionStore.currentUser?.id
        else { return }
        _ = try? await container.taskApplicationService.completeTask(
            in: spaceID,
            taskID: taskID,
            actorID: actorID,
            referenceDate: .now
        )
        syncAfterMutation(spaceID: spaceID)
    }

    private func snoozeTaskFromNotification(_ taskID: UUID, delay: TimeInterval) async {
        guard
            let spaceID = sessionStore.currentSpace?.id,
            let actorID = sessionStore.currentUser?.id
        else { return }
        _ = try? await container.taskApplicationService.snoozeTask(
            in: spaceID,
            taskID: taskID,
            actorID: actorID,
            option: .custom(date: Date.now.addingTimeInterval(delay), hasExplicitTime: true)
        )
        syncAfterMutation(spaceID: spaceID)
    }

    #if DEBUG
    private func seedMockSession() {
        let currentUser = MockDataFactory.makeCurrentUser()
        let singleSpace = MockDataFactory.makeSingleSpace()
        sessionStore.seedMock(
            currentUser: currentUser,
            singleSpace: singleSpace
        )
    }
    #endif
}
