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
    let homeViewModel: HomeViewModel
    let listsViewModel: ListsViewModel
    let projectsViewModel: ProjectsViewModel
    let profileViewModel: ProfileViewModel
    let routinesViewModel: RoutinesViewModel

    private(set) var hasBootstrapped = false
    private(set) var startupRestorePresentationState: StartupRestorePresentationState = .idle
    private var hasCompletedPostLaunchWork = false
    private var hasSyncedReminderNotifications = false
    private var hasRestoredPersistedUserProfile = false
    private var startupRestoreSlowTask: Task<Void, Never>?
    private var reloadAfterSyncTask: Task<Void, Never>?
    private var pendingDeepLinkTaskID: UUID?
    private var pendingHighlightTaskID: UUID?

    private let todayWidgetContextStore: TodayWidgetSharedContextStore
    private let todayWidgetSnapshotWriter: TodayWidgetSnapshotWriter

    private static let reloadAfterSyncCoalescingDelay: Duration = .milliseconds(180)

    init(
        container: AppContainer,
        sessionStore: SessionStore,
        router: AppRouter,
        appearanceManager: AppearanceManager = AppearanceManager()
    ) {
        self.container = container
        self.sessionStore = sessionStore
        self.router = router
        self.appearanceManager = appearanceManager

        let todayWidgetContextStore = TodayWidgetSharedContextStore()
        self.todayWidgetContextStore = todayWidgetContextStore
        self.todayWidgetSnapshotWriter = TodayWidgetSnapshotWriter(
            itemRepository: container.itemRepository,
            contextStore: todayWidgetContextStore
        )

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
            projectRepository: container.projectRepository
        )
        self.routinesViewModel = RoutinesViewModel(
            sessionStore: sessionStore,
            periodicTaskApplicationService: container.periodicTaskApplicationService,
            taskTemplateRepository: container.taskTemplateRepository
        )
        self.profileViewModel = ProfileViewModel(
            sessionStore: sessionStore,
            authService: container.authService,
            userProfileRepository: container.userProfileRepository,
            notificationService: container.notificationService,
            itemRepository: container.itemRepository,
            taskApplicationService: container.taskApplicationService,
            taskListRepository: container.taskListRepository,
            projectRepository: container.projectRepository,
            reminderScheduler: container.reminderScheduler,
            biometricAuthService: container.biometricAuthService
        )
        configureCallbacks()
    }

    static func makeContext() -> AppContext {
        StartupTrace.mark("AppContext.make.begin")
        let container = LocalServiceFactory.makeContainer()
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
        let context = AppContext.makeContext()
        context.seedMockSession()
        context.hasBootstrapped = true
        return context
    }
    #endif

    func bootstrapIfNeeded() async {
        guard hasBootstrapped == false else { return }
        await sessionStore.bootstrap(
            authService: container.authService,
            spaceService: container.spaceService
        )
        if sessionStore.authState == .signedIn {
            if sessionStore.singleSpace == nil {
                await setupSpacesForCurrentUserIfNeeded()
            }
            await migrateLegacyProjectsIfNeeded()
            await restorePersistedUserProfileIfNeeded()
        }
        hasBootstrapped = true
    }

    func setupSpacesForCurrentUserIfNeeded() async {
        guard let userID = sessionStore.currentUser?.id else { return }

        var spaceContext = await container.spaceService.currentSpaceContext(for: userID)
        if spaceContext.singleSpace == nil {
            if let newSpace = try? await container.spaceService.createSingleSpace(for: userID) {
                spaceContext.singleSpace = newSpace
            }
        }
        sessionStore.applySpaceContext(spaceContext)
        sessionStore.activeMode = .single
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

    func restorePersistedUserProfileIfNeeded(force _: Bool = false) async {
        guard hasRestoredPersistedUserProfile == false else { return }
        hasRestoredPersistedUserProfile = true
        guard let user = sessionStore.currentUser else { return }
        sessionStore.currentUser = user
    }

    func performPostLaunchWorkIfNeeded() async {
        guard hasCompletedPostLaunchWork == false else { return }
        hasCompletedPostLaunchWork = true
        StartupTrace.mark("AppContext.postLaunch.begin")
        await restorePersistedUserProfileIfNeeded()
        await routinesViewModel.loadIfNeeded()
        await syncReminderNotificationsIfNeeded()
        await refreshTodayWidgetSnapshot()
        StartupTrace.mark("AppContext.postLaunch.end")
    }

    func handleAppBecameActive() async {
        await homeViewModel.reload(reason: .sync)
        await refreshTodayWidgetSnapshot()
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
            WidgetCenter.shared.reloadTimelines(ofKind: TodayWidgetConstants.focusWidgetKind)
            WidgetCenter.shared.reloadTimelines(ofKind: TodayWidgetConstants.listWidgetKind)
            return
        }

        todayWidgetContextStore.write(TodayWidgetSharedContext(spaceID: spaceID, actorID: actorID))
        do {
            try await todayWidgetSnapshotWriter.refreshTodayWidgetSnapshot()
        } catch {
            appContextLogger.error("[WidgetSnapshot] today write failed: \(error.localizedDescription, privacy: .public)")
        }
        WidgetCenter.shared.reloadTimelines(ofKind: TodayWidgetConstants.focusWidgetKind)
        WidgetCenter.shared.reloadTimelines(ofKind: TodayWidgetConstants.listWidgetKind)
    }

    func updateSyncPolling() {}

    func handleRemoteNotification(_ userInfo: [AnyHashable: Any]) async {
        if let taskIDString = userInfo["task_id"] as? String,
           let taskID = UUID(uuidString: taskIDString) {
            rememberDeepLinkTaskID(taskID)
        }
        await reloadAfterSync()
    }

    func handleNotificationResponse(_ response: UNNotificationResponse) async {
        guard let taskID = taskID(from: response.notification.request.content.userInfo) else { return }

        switch response.actionIdentifier {
        case NotificationActionCatalog.completeActionIdentifier,
             NotificationActionCatalog.completeNudgeActionIdentifier:
            await completeTaskFromNotification(taskID)
        default:
            if let delay = NotificationActionCatalog.snoozeInterval(for: response.actionIdentifier) {
                await snoozeTaskFromNotification(taskID, delay: delay)
            } else {
                rememberDeepLinkTaskID(taskID)
                await consumeDeepLinkTaskIDIfAny()
            }
        }
    }

    func handleDeepLink(url: URL) {
        guard let taskID = UUID(uuidString: url.lastPathComponent) else { return }
        rememberDeepLinkTaskID(taskID)
        Task { await consumeDeepLinkTaskIDIfAny() }
    }

    func rememberDeepLinkTaskID(_ id: UUID) {
        pendingDeepLinkTaskID = id
        pendingHighlightTaskID = id
    }

    func consumeDeepLinkTaskIDIfAny() async {
        guard let taskID = pendingDeepLinkTaskID else { return }
        pendingDeepLinkTaskID = nil
        pendingHighlightTaskID = taskID
        router.currentSurface = .today
    }

    func consumePendingHighlightTaskID() -> UUID? {
        let id = pendingHighlightTaskID
        pendingHighlightTaskID = nil
        return id
    }

    private func configureCallbacks() {
        homeViewModel.onTaskMutated = { [weak self] spaceID in
            self?.syncAfterMutation(spaceID: spaceID)
            Task { await self?.refreshTodayWidgetSnapshot() }
        }
        homeViewModel.onTodayDataChanged = { [weak self] in
            Task { await self?.refreshTodayWidgetSnapshot() }
        }
        homeViewModel.onConvertToPeriodicTask = { [weak self] title in
            guard let self else { return }
            router.pendingComposerTitle = title
            router.pendingPeriodicCycle = nil
            router.activeComposer = .newPeriodicTask
        }
        profileViewModel.onTaskMutated = { [weak self] spaceID in
            self?.syncAfterMutation(spaceID: spaceID)
        }
        profileViewModel.onProfileSaved = { [weak self] user in
            self?.sessionStore.currentUser = user
            Task { await self?.refreshTodayWidgetSnapshot() }
        }
    }

    private func syncReminderNotificationsIfNeeded() async {
        guard hasSyncedReminderNotifications == false else { return }
        hasSyncedReminderNotifications = true
        await homeViewModel.reload(reason: .sync)
        guard let spaceID = sessionStore.currentSpace?.id else { return }
        let tasks = (try? await container.itemRepository.fetchActiveItems(spaceID: spaceID)) ?? []
        let projects = (try? await container.projectRepository.fetchProjects(spaceID: spaceID)) ?? []
        await container.reminderScheduler.resync(tasks: tasks, projects: projects)
    }

    private func syncAfterMutation(spaceID: UUID) {
        _ = spaceID
        Task {
            await refreshTodayWidgetSnapshot()
        }
    }

    private func reloadAfterSync() async {
        if reloadAfterSyncTask == nil {
            reloadAfterSyncTask = Task { @MainActor [weak self] in
                await self?.performCoalescedReloadAfterSync()
            }
        }
        await reloadAfterSyncTask?.value
    }

    private func performCoalescedReloadAfterSync() async {
        try? await Task.sleep(for: Self.reloadAfterSyncCoalescingDelay)
        await homeViewModel.reload(reason: .sync)
        await listsViewModel.load()
        await projectsViewModel.load()
        await routinesViewModel.loadIfNeeded()
        await refreshTodayWidgetSnapshot()
        reloadAfterSyncTask = nil
        finishStartupRestorePresentation()
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
