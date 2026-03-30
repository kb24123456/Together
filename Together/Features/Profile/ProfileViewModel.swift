import Foundation
import Observation

enum ProfileExpandedSetting: Hashable {
    case taskUrgency
    case defaultSnooze
    case completedArchive
}

enum ProfileCustomDurationKind: Hashable, Identifiable {
    case taskUrgency
    case defaultSnooze

    var id: Self { self }

    var title: String {
        switch self {
        case .taskUrgency:
            return "自定义临期提醒"
        case .defaultSnooze:
            return "自定义默认推迟时间"
        }
    }

    var initialMinutes: Int {
        switch self {
        case .taskUrgency:
            return 30
        case .defaultSnooze:
            return NotificationSettings.defaultSnoozeMinutes
        }
    }
}

@MainActor
@Observable
final class ProfileViewModel {
    private let sessionStore: SessionStore
    private let authService: AuthServiceProtocol
    private let relationshipService: RelationshipServiceProtocol
    private let userProfileRepository: UserProfileRepositoryProtocol
    private let notificationService: NotificationServiceProtocol
    private let itemRepository: ItemRepositoryProtocol
    private let taskApplicationService: TaskApplicationServiceProtocol
    private let taskListRepository: TaskListRepositoryProtocol
    private let projectRepository: ProjectRepositoryProtocol
    private let reminderScheduler: ReminderSchedulerProtocol

    var loadState: LoadableState = .idle
    var notificationAuthorization: NotificationAuthorizationStatus = .notDetermined
    var expandedSetting: ProfileExpandedSetting?
    var customDurationSheet: ProfileCustomDurationKind?

    init(
        sessionStore: SessionStore,
        authService: AuthServiceProtocol,
        relationshipService: RelationshipServiceProtocol,
        userProfileRepository: UserProfileRepositoryProtocol,
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
        self.userProfileRepository = userProfileRepository
        self.notificationService = notificationService
        self.itemRepository = itemRepository
        self.taskApplicationService = taskApplicationService
        self.taskListRepository = taskListRepository
        self.projectRepository = projectRepository
        self.reminderScheduler = reminderScheduler
    }

    var currentUser: User? { sessionStore.currentUser }
    var currentUserRevision: UUID { sessionStore.userProfileRevision }
    var currentSpace: Space? { sessionStore.currentSpace }
    var bindingState: BindingState { sessionStore.bindingState }
    var pairSpace: PairSpace? { sessionStore.currentPairSpace }
    var activeInvite: Invite? { sessionStore.activeInvite }

    var profileCardPrimaryName: String { currentUserDisplayName }
    var profileCardSecondaryName: String? { linkedPartnerDisplayName }

    var profileCardPrimaryAvatar: ProfileCardAvatar {
        ProfileCardAvatar(
            displayName: currentUserDisplayName,
            avatarAsset: currentUser?.avatarAsset ?? .system("person.crop.circle.fill"),
            overrideImage: nil
        )
    }

    var profileCardSecondaryAvatarState: ProfileCardSecondaryAvatarState {
        guard let partnerName = linkedPartnerDisplayName else {
            return .placeholder
        }

        return .user(
            ProfileCardAvatar(
                displayName: partnerName,
                avatarAsset: .system("person.crop.circle.fill"),
                overrideImage: nil
            )
        )
    }

    func makeEditProfileViewModel() -> EditProfileViewModel {
        EditProfileViewModel(
            sessionStore: sessionStore,
            userProfileRepository: userProfileRepository
        )
    }

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
        guard taskReminderEnabled else { return "已关闭" }
        return taskUrgencyLabel(minutes: taskUrgencyWindowMinutes)
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
        NotificationSettings.normalizedSnoozeMinutes(
            sessionStore.currentUser?.preferences.taskUrgencyWindowMinutes ?? 30
        )
    }

    var taskReminderEnabled: Bool {
        sessionStore.currentUser?.preferences.taskReminderEnabled ?? true
    }

    let taskUrgencyOptions: [Int] = [5, 10, 30, 60]
    let snoozeMinuteOptions: [Int] = [5, 10, 30, 60]
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

    var customDurationInitialMinutes: Int {
        switch customDurationSheet {
        case .taskUrgency:
            return taskUrgencyWindowMinutes
        case .defaultSnooze:
            return defaultSnoozeMinutes
        case nil:
            return ProfileCustomDurationKind.defaultSnooze.initialMinutes
        }
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
        user.preferences.taskUrgencyWindowMinutes = NotificationSettings.normalizedSnoozeMinutes(minutes)
        applyUpdatedPreferences(user.preferences, to: user)
    }

    func updateDefaultSnoozeMinutes(_ minutes: Int) {
        guard var user = sessionStore.currentUser else { return }
        user.preferences.defaultSnoozeMinutes = NotificationSettings.normalizedSnoozeMinutes(minutes)
        applyUpdatedPreferences(user.preferences, to: user)
    }

    func updateCompletedTaskAutoArchiveEnabled(_ isEnabled: Bool) {
        guard var user = sessionStore.currentUser else { return }
        user.preferences.completedTaskAutoArchiveEnabled = isEnabled
        applyUpdatedPreferences(user.preferences, to: user)
    }

    func updateCompletedTaskAutoArchiveDays(_ days: Int) {
        guard var user = sessionStore.currentUser else { return }
        user.preferences.completedTaskAutoArchiveDays = NotificationSettings.normalizedCompletedTaskAutoArchiveDays(days)
        applyUpdatedPreferences(user.preferences, to: user)
    }

    func updateTaskReminderEnabled(_ isEnabled: Bool) {
        guard var user = sessionStore.currentUser else { return }
        user.preferences.taskReminderEnabled = isEnabled
        applyUpdatedPreferences(user.preferences, to: user)
        if isEnabled == false, expandedSetting == .taskUrgency {
            expandedSetting = nil
        }
    }

    func toggleExpandedSetting(_ setting: ProfileExpandedSetting) {
        if expandedSetting == setting {
            expandedSetting = nil
        } else {
            expandedSetting = setting
        }
    }

    func presentCustomDurationSheet(_ kind: ProfileCustomDurationKind) {
        customDurationSheet = kind
    }

    func dismissCustomDurationSheet() {
        customDurationSheet = nil
    }

    func applyCustomDuration(_ minutes: Int) {
        guard let customDurationSheet else { return }
        switch customDurationSheet {
        case .taskUrgency:
            updateTaskUrgencyWindow(minutes: minutes)
        case .defaultSnooze:
            updateDefaultSnoozeMinutes(minutes)
        }
        self.customDurationSheet = nil
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

    private func applyUpdatedPreferences(_ preferences: NotificationSettings, to user: User) {
        var updatedUser = user
        updatedUser.preferences = preferences
        updatedUser.updatedAt = .now
        sessionStore.currentUser = updatedUser

        Task {
            _ = try? await userProfileRepository.savePreferences(
                for: updatedUser,
                preferences: preferences
            )
        }
    }

    private var currentUserDisplayName: String {
        currentUser?.displayName ?? "未加载用户"
    }

    private var linkedPartnerDisplayName: String? {
        guard bindingState.supportsSharedCollaboration else { return nil }
        guard let nickname = pairSpace?.memberB?.nickname.trimmingCharacters(in: .whitespacesAndNewlines) else {
            return nil
        }
        return nickname.isEmpty ? nil : nickname
    }
}
