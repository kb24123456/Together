import Foundation
import Observation

@MainActor
@Observable
final class ProfileViewModel {
    private let sessionStore: SessionStore
    private let authService: AuthServiceProtocol
    private let relationshipService: RelationshipServiceProtocol
    private let notificationService: NotificationServiceProtocol
    private let itemRepository: ItemRepositoryProtocol
    private let taskApplicationService: TaskApplicationServiceProtocol
    private let taskListRepository: TaskListRepositoryProtocol
    private let projectRepository: ProjectRepositoryProtocol
    private let reminderScheduler: ReminderSchedulerProtocol

    var loadState: LoadableState = .idle
    var notificationAuthorization: NotificationAuthorizationStatus = .notDetermined

    init(
        sessionStore: SessionStore,
        authService: AuthServiceProtocol,
        relationshipService: RelationshipServiceProtocol,
        notificationService: NotificationServiceProtocol,
        itemRepository: ItemRepositoryProtocol,
        taskApplicationService: TaskApplicationServiceProtocol,
        taskListRepository: TaskListRepositoryProtocol,
        projectRepository: ProjectRepositoryProtocol,
        reminderScheduler: ReminderSchedulerProtocol
    ) {
        self.sessionStore = sessionStore
        self.authService = authService
        self.relationshipService = relationshipService
        self.notificationService = notificationService
        self.itemRepository = itemRepository
        self.taskApplicationService = taskApplicationService
        self.taskListRepository = taskListRepository
        self.projectRepository = projectRepository
        self.reminderScheduler = reminderScheduler
    }

    var currentUser: User? { sessionStore.currentUser }
    var currentSpace: Space? { sessionStore.currentSpace }
    var bindingState: BindingState { sessionStore.bindingState }
    var pairSpace: PairSpace? { sessionStore.currentPairSpace }
    var activeInvite: Invite? { sessionStore.activeInvite }

    var notificationSummary: String {
        switch notificationAuthorization {
        case .authorized:
            return "提醒已开启"
        case .denied:
            return "提醒未开启"
        case .notDetermined:
            return "尚未请求提醒权限"
        }
    }

    var taskUrgencySummary: String {
        taskUrgencyLabel(minutes: taskUrgencyWindowMinutes)
    }

    var defaultSnoozeSummary: String {
        relativeTimeLabel(minutes: defaultSnoozeMinutes)
    }

    var completedArchiveSummary: String {
        "\(completedTaskAutoArchiveDays)天后"
    }

    var spaceSummary: String {
        currentSpace?.displayName ?? "我的任务空间"
    }

    var collaborationSummary: String {
        bindingState.supportsSharedCollaboration ? bindingState.description : "后续开放"
    }

    var taskUrgencyWindowMinutes: Int {
        sessionStore.currentUser?.preferences.taskUrgencyWindowMinutes ?? 30
    }

    let taskUrgencyOptions: [Int] = [10, 30, 60, 120]
    let snoozeMinuteOptions: [Int] = Array(stride(from: 5, through: 180, by: 5))
    let completedTaskAutoArchiveOptions: [Int] = NotificationSettings.completedTaskAutoArchiveDayOptions

    var defaultSnoozeMinutes: Int {
        NotificationSettings.normalizedSnoozeMinutes(
            sessionStore.currentUser?.preferences.defaultSnoozeMinutes ?? NotificationSettings.defaultSnoozeMinutes
        )
    }

    var completedTaskAutoArchiveEnabled: Bool {
        sessionStore.currentUser?.preferences.completedTaskAutoArchiveEnabled ?? true
    }

    var completedTaskAutoArchiveDays: Int {
        NotificationSettings.normalizedCompletedTaskAutoArchiveDays(
            sessionStore.currentUser?.preferences.completedTaskAutoArchiveDays
            ?? NotificationSettings.defaultCompletedTaskAutoArchiveDays
        )
    }

    func load() async {
        loadState = .loading
        notificationAuthorization = await notificationService.authorizationStatus()
        loadState = .loaded
    }

    func requestNotifications() async {
        notificationAuthorization = (try? await notificationService.requestAuthorization()) ?? .denied
        guard notificationAuthorization == .authorized else { return }
        let spaceID = sessionStore.currentSpace?.id
        let tasks = (try? await itemRepository.fetchActiveItems(spaceID: spaceID)) ?? []
        let projects = (try? await projectRepository.fetchProjects(spaceID: spaceID)) ?? []
        await reminderScheduler.resync(tasks: tasks, projects: projects)
    }

    func createInvite() async {
        guard let inviterID = currentUser?.id else { return }
        _ = try? await relationshipService.createInvite(from: inviterID)
    }

    func updateTaskUrgencyWindow(minutes: Int) {
        guard var user = sessionStore.currentUser else { return }
        user.preferences.taskUrgencyWindowMinutes = minutes
        user.updatedAt = .now
        sessionStore.currentUser = user
    }

    func updateDefaultSnoozeMinutes(_ minutes: Int) {
        guard var user = sessionStore.currentUser else { return }
        user.preferences.defaultSnoozeMinutes = NotificationSettings.normalizedSnoozeMinutes(minutes)
        user.updatedAt = .now
        sessionStore.currentUser = user
    }

    func updateCompletedTaskAutoArchiveEnabled(_ isEnabled: Bool) {
        guard var user = sessionStore.currentUser else { return }
        user.preferences.completedTaskAutoArchiveEnabled = isEnabled
        user.updatedAt = .now
        sessionStore.currentUser = user
    }

    func updateCompletedTaskAutoArchiveDays(_ days: Int) {
        guard var user = sessionStore.currentUser else { return }
        user.preferences.completedTaskAutoArchiveDays = NotificationSettings.normalizedCompletedTaskAutoArchiveDays(days)
        user.updatedAt = .now
        sessionStore.currentUser = user
    }

    func makeCompletedHistoryViewModel() -> CompletedHistoryViewModel {
        CompletedHistoryViewModel(
            sessionStore: sessionStore,
            itemRepository: itemRepository,
            taskApplicationService: taskApplicationService,
            taskListRepository: taskListRepository,
            projectRepository: projectRepository
        )
    }

    func signOut() async {
        await authService.signOut()
        sessionStore.authState = .signedOut
        sessionStore.bindingState = .singleTrial
        sessionStore.currentUser = nil
        sessionStore.currentSpace = nil
        sessionStore.availableSpaces = []
        sessionStore.currentPairSpace = nil
    }

    func taskUrgencyLabel(minutes: Int) -> String {
        if minutes >= 60, minutes.isMultiple(of: 60) {
            return "\(minutes / 60)小时"
        }
        return "\(minutes)分钟"
    }

    func relativeTimeLabel(minutes: Int) -> String {
        if minutes >= 60, minutes.isMultiple(of: 60) {
            return "\(minutes / 60)小时后"
        }
        return "\(minutes)分钟后"
    }
}
