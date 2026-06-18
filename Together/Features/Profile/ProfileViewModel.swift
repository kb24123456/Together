import Foundation
import Observation

enum ProfileExpandedSetting: Hashable {
    case taskUrgency
    case completedArchive
    case appearance
}

enum ProfileCustomDurationKind: Hashable, Identifiable {
    case taskUrgency

    var id: Self { self }

    var title: String {
        "自定义临期提醒"
    }

    var initialMinutes: Int {
        30
    }
}

@MainActor
@Observable
final class ProfileViewModel {
    private let sessionStore: SessionStore
    private let authService: AuthServiceProtocol
    private let userProfileRepository: UserProfileRepositoryProtocol
    private let notificationService: NotificationServiceProtocol
    private let itemRepository: ItemRepositoryProtocol
    private let taskApplicationService: TaskApplicationServiceProtocol
    private let taskListRepository: TaskListRepositoryProtocol
    private let projectRepository: ProjectRepositoryProtocol
    private let reminderScheduler: ReminderSchedulerProtocol
    private let biometricAuthService: BiometricAuthServiceProtocol

    var onTaskMutated: ((_ spaceID: UUID) -> Void)?
    var loadState: LoadableState = .idle
    var notificationAuthorization: NotificationAuthorizationStatus = .notDetermined
    var expandedSetting: ProfileExpandedSetting?
    var customDurationSheet: ProfileCustomDurationKind?
    var iCloudStatus: ICloudStatus = .couldNotDetermine
    var isAccountDeletionInProgress: Bool = false
    var onProfileSaved: ((_ user: User) -> Void)?

    init(
        sessionStore: SessionStore,
        authService: AuthServiceProtocol,
        userProfileRepository: UserProfileRepositoryProtocol,
        notificationService: NotificationServiceProtocol,
        itemRepository: ItemRepositoryProtocol,
        taskApplicationService: TaskApplicationServiceProtocol,
        taskListRepository: TaskListRepositoryProtocol,
        projectRepository: ProjectRepositoryProtocol,
        reminderScheduler: ReminderSchedulerProtocol,
        biometricAuthService: BiometricAuthServiceProtocol = BiometricAuthService()
    ) {
        self.sessionStore = sessionStore
        self.authService = authService
        self.userProfileRepository = userProfileRepository
        self.notificationService = notificationService
        self.itemRepository = itemRepository
        self.taskApplicationService = taskApplicationService
        self.taskListRepository = taskListRepository
        self.projectRepository = projectRepository
        self.reminderScheduler = reminderScheduler
        self.biometricAuthService = biometricAuthService
    }

    var currentUser: User? { sessionStore.currentUser }
    var currentUserRevision: UUID { sessionStore.userProfileRevision }
    var currentSpace: Space? { sessionStore.currentSpace }

    var profileCardPrimaryName: String { currentUserDisplayName }
    var profileCardSecondaryName: String? { nil }

    var profileCardPrimaryAvatar: ProfileCardAvatar {
        ProfileCardAvatar(
            displayName: currentUserDisplayName,
            avatarAsset: currentUser?.avatarAsset ?? .system("person.crop.circle.fill"),
            overrideImage: nil
        )
    }

    func makeEditProfileViewModel(user: User?) -> EditProfileViewModel {
        let vm = EditProfileViewModel(
            sessionStore: sessionStore,
            userProfileRepository: userProfileRepository,
            user: user
        )
        vm.onProfileSaved = onProfileSaved
        return vm
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

    var completedArchiveSummary: String {
        "\(completedTaskAutoArchiveDays)天后"
    }

    var spaceSummary: String {
        currentSpace?.displayName ?? "我的任务空间"
    }

    var identityCardSubtitle: String {
        "独立工作空间"
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
    let completedTaskAutoArchiveOptions: [Int] = NotificationSettings.completedTaskAutoArchiveDayOptions

    var completedTaskAutoArchiveEnabled: Bool {
        sessionStore.currentUser?.preferences.completedTaskAutoArchiveEnabled ?? true
    }

    var completedTaskAutoArchiveDays: Int {
        NotificationSettings.normalizedCompletedTaskAutoArchiveDays(
            sessionStore.currentUser?.preferences.completedTaskAutoArchiveDays
            ?? NotificationSettings.defaultCompletedTaskAutoArchiveDays
        )
    }

    var appLockEnabled: Bool {
        sessionStore.currentUser?.preferences.appLockEnabled ?? false
    }

    var biometricTypeName: String {
        biometricAuthService.biometricTypeName()
    }

    var iCloudStatusSummary: String {
        switch iCloudStatus {
        case .available: return "已连接"
        case .noAccount: return "未登录 iCloud"
        case .restricted: return "受限"
        case .couldNotDetermine: return "检查中…"
        case .temporarilyUnavailable: return "暂时不可用"
        }
    }

    var appVersionString: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(version) (\(build))"
    }

    var cacheSizeString: String {
        let cacheSize = URLCache.shared.currentDiskUsage
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useMB, .useKB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(cacheSize))
    }

    func updateAppLockEnabled(_ isEnabled: Bool) {
        if isEnabled {
            // 开启前先验证生物识别身份
            Task {
                let success = (try? await biometricAuthService.authenticate(
                    reason: "验证身份以启用应用锁定"
                )) ?? false
                guard success, var user = sessionStore.currentUser else { return }
                user.preferences.appLockEnabled = true
                applyUpdatedPreferences(user.preferences, to: user)
            }
        } else {
            guard var user = sessionStore.currentUser else { return }
            user.preferences.appLockEnabled = false
            applyUpdatedPreferences(user.preferences, to: user)
        }
    }

    var customDurationInitialMinutes: Int {
        switch customDurationSheet {
        case .taskUrgency:
            return taskUrgencyWindowMinutes
        case nil:
            return ProfileCustomDurationKind.taskUrgency.initialMinutes
        }
    }

    func load() async {
        loadState = .loading
        async let notifStatus = notificationService.authorizationStatus()
        async let cloudStatus = ICloudStatusService.checkStatus()
        notificationAuthorization = await notifStatus
        iCloudStatus = await cloudStatus
        loadState = .loaded
    }

    func checkICloudStatus() async {
        iCloudStatus = await ICloudStatusService.checkStatus()
    }

    func clearCache() {
        URLCache.shared.removeAllCachedResponses()
    }

    func requestAccountDeletion() async {
        isAccountDeletionInProgress = true
        let spaceID = currentSpace?.id

        // 1. 删除所有任务数据
        if let spaceID {
            let allItems = (try? await itemRepository.fetchActiveItems(spaceID: spaceID)) ?? []
            let archivedItems = (try? await itemRepository.fetchCompletedItems(
                spaceID: spaceID, searchText: nil, before: nil, limit: 10000
            )) ?? []
            for item in allItems + archivedItems {
                try? await itemRepository.deleteItem(itemID: item.id)
            }
        }

        // 2. 删除所有项目
        if let spaceID {
            let projects = (try? await projectRepository.fetchProjects(spaceID: spaceID)) ?? []
            for project in projects {
                try? await projectRepository.deleteProject(projectID: project.id, actorID: project.creatorID)
            }
        }

        // 3. 取消所有本地通知
        await reminderScheduler.resync(tasks: [], projects: [])

        // 4. 签出（清除 Keychain + Session）
        await signOut()
        isAccountDeletionInProgress = false
    }

    func requestNotifications() async {
        notificationAuthorization = (try? await notificationService.requestAuthorization()) ?? .denied
        guard notificationAuthorization == .authorized else { return }
        let spaceID = sessionStore.currentSpace?.id
        let tasks = (try? await itemRepository.fetchActiveItems(spaceID: spaceID)) ?? []
        let projects = (try? await projectRepository.fetchProjects(spaceID: spaceID)) ?? []
        await reminderScheduler.resync(tasks: tasks, projects: projects)
    }

    func updateTaskUrgencyWindow(minutes: Int) {
        guard var user = sessionStore.currentUser else { return }
        user.preferences.taskUrgencyWindowMinutes = NotificationSettings.normalizedSnoozeMinutes(minutes)
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
        }
        self.customDurationSheet = nil
    }

    func makeCompletedHistoryViewModel() -> CompletedHistoryViewModel {
        let viewModel = CompletedHistoryViewModel(
            sessionStore: sessionStore,
            itemRepository: itemRepository,
            taskApplicationService: taskApplicationService,
            taskListRepository: taskListRepository,
            projectRepository: projectRepository
        )
        viewModel.onTaskMutated = onTaskMutated
        return viewModel
    }

    func signOut() async {
        await authService.signOut()
        sessionStore.clearForSignOut()
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

}
