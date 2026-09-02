import Foundation
import Observation

@MainActor
@Observable
final class ProfileViewModel {
    private let sessionStore: SessionStore
    private let userProfileRepository: UserProfileRepositoryProtocol
    private let notificationService: NotificationServiceProtocol
    private let itemRepository: ItemRepositoryProtocol
    private let taskApplicationService: TaskApplicationServiceProtocol
    private let taskListRepository: TaskListRepositoryProtocol
    private let projectRepository: ProjectRepositoryProtocol
    private let periodicTaskRepository: PeriodicTaskRepositoryProtocol
    private let reminderScheduler: ReminderSchedulerProtocol
    private let personalDataDeletionService: PersonalDataDeletionService
    private let biometricAuthService: BiometricAuthServiceProtocol

    var onTaskMutated: ((_ spaceID: UUID) -> Void)?
    var loadState: LoadableState = .idle
    var notificationAuthorization: NotificationAuthorizationStatus = .notDetermined
    var alarmAuthorization: RoutineAlarmAuthorizationStatus = .notDetermined
    var reminderDelivery: PeriodicReminderDelivery = .alarm
    var iCloudStatus: ICloudStatus = .couldNotDetermine
    var isCheckingICloudStatus = false
    var isAccountDeletionInProgress: Bool = false
    var deletionErrorMessage: String?
    var weeklyPlanningReviewCompletionCount = 0
    var onProfileSaved: ((_ user: User) -> Void)?
    var onPersonalDataDeleted: ((_ user: User, _ space: Space) -> Void)?
    private var reminderDeliveryUpdateRevision = 0

    init(
        sessionStore: SessionStore,
        userProfileRepository: UserProfileRepositoryProtocol,
        notificationService: NotificationServiceProtocol,
        itemRepository: ItemRepositoryProtocol,
        taskApplicationService: TaskApplicationServiceProtocol,
        taskListRepository: TaskListRepositoryProtocol,
        projectRepository: ProjectRepositoryProtocol,
        periodicTaskRepository: PeriodicTaskRepositoryProtocol,
        reminderScheduler: ReminderSchedulerProtocol,
        personalDataDeletionService: PersonalDataDeletionService,
        biometricAuthService: BiometricAuthServiceProtocol = BiometricAuthService()
    ) {
        self.sessionStore = sessionStore
        self.userProfileRepository = userProfileRepository
        self.notificationService = notificationService
        self.itemRepository = itemRepository
        self.taskApplicationService = taskApplicationService
        self.taskListRepository = taskListRepository
        self.projectRepository = projectRepository
        self.periodicTaskRepository = periodicTaskRepository
        self.reminderScheduler = reminderScheduler
        self.personalDataDeletionService = personalDataDeletionService
        self.biometricAuthService = biometricAuthService
    }

    var currentUser: User? { sessionStore.currentUser }
    var currentUserRevision: UUID { sessionStore.userProfileRevision }
    var currentSpace: Space? { sessionStore.currentSpace }

    var profileCardPrimaryName: String { currentUserDisplayName }
    func makeEditProfileViewModel(user: User?) -> EditProfileViewModel {
        let vm = EditProfileViewModel(
            sessionStore: sessionStore,
            userProfileRepository: userProfileRepository,
            user: user
        )
        vm.onProfileSaved = onProfileSaved
        return vm
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

    var taskUrgencyPickerOptions: [Int] {
        Array(Set(taskUrgencyOptions + [taskUrgencyWindowMinutes])).sorted()
    }

    var dailySummaryEnabled: Bool {
        sessionStore.currentUser?.preferences.dailySummaryEnabled ?? false
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

    var appLockEnabled: Bool {
        sessionStore.currentUser?.preferences.appLockEnabled ?? false
    }

    var biometricTypeName: String {
        biometricAuthService.biometricTypeName()
    }

    var iCloudStatusSummary: String {
        if isCheckingICloudStatus { return "检查中…" }

        switch iCloudStatus {
        case .available: return "iCloud 已登录"
        case .noAccount: return "未登录 iCloud"
        case .restricted: return "受限"
        case .couldNotDetermine: return "无法确认"
        case .temporarilyUnavailable: return "暂时不可用"
        }
    }

    var appVersionString: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(version) (\(build))"
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

    func load() async {
        loadState = .loading
        isCheckingICloudStatus = true
        async let notifStatus = notificationService.authorizationStatus()
        async let alarmStatus = reminderScheduler.alarmAuthorizationStatus()
        async let deliveryPreference = reminderScheduler.reminderDeliveryPreference()
        async let cloudStatus = ICloudStatusService.checkStatus()
        notificationAuthorization = await notifStatus
        alarmAuthorization = await alarmStatus
        reminderDelivery = await deliveryPreference
        iCloudStatus = await cloudStatus
        isCheckingICloudStatus = false
        if let spaceID = sessionStore.currentSpace?.id,
           let review = try? await itemRepository.fetchPlanningReview(
               spaceID: spaceID,
               range: .week,
               referenceDate: .now
           ) {
            weeklyPlanningReviewCompletionCount = review.completionCount
        }
        loadState = .loaded
    }

    func planningReview(
        range: PlanningReviewRange,
        referenceDate: Date = .now
    ) async throws -> PlanningReviewSnapshot {
        try await itemRepository.fetchPlanningReview(
            spaceID: sessionStore.currentSpace?.id,
            range: range,
            referenceDate: referenceDate
        )
    }

    func taskLifecycleReview(itemID: UUID) async throws -> TaskLifecycleReview {
        try await itemRepository.fetchTaskLifecycleReview(itemID: itemID)
    }

    func checkICloudStatus() async {
        guard isCheckingICloudStatus == false else { return }
        isCheckingICloudStatus = true
        defer { isCheckingICloudStatus = false }
        iCloudStatus = await ICloudStatusService.checkStatus()
    }

    func refreshNotificationAuthorization() async {
        notificationAuthorization = await notificationService.authorizationStatus()
    }

    @discardableResult
    func requestAccountDeletion() async -> Bool {
        isAccountDeletionInProgress = true
        deletionErrorMessage = nil
        defer { isAccountDeletionInProgress = false }

        switch await personalDataDeletionService.deleteAllData() {
        case let .completed(newUser, newSpace):
            sessionStore.applyPersonalIdentity(user: newUser, space: newSpace)
            onPersonalDataDeleted?(newUser, newSpace)
            return true
        case let .failed(message):
            deletionErrorMessage = message
            return false
        }
    }

    func requestNotifications() async {
        notificationAuthorization = (try? await notificationService.requestAuthorization()) ?? .denied
        await resyncReminderNotifications()
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

    func updateDailySummaryEnabled(_ isEnabled: Bool) {
        guard var user = sessionStore.currentUser else { return }
        user.preferences.dailySummaryEnabled = isEnabled && user.preferences.taskReminderEnabled
        applyUpdatedPreferences(user.preferences, to: user)
        Task {
            if isEnabled, notificationAuthorization != .authorized {
                await requestNotifications()
            } else {
                await resyncReminderNotifications()
            }
        }
    }

    func updateTaskReminderEnabled(_ isEnabled: Bool) {
        guard var user = sessionStore.currentUser else { return }
        user.preferences.taskReminderEnabled = isEnabled
        if isEnabled == false {
            user.preferences.dailySummaryEnabled = false
        }
        applyUpdatedPreferences(user.preferences, to: user)

        Task {
            if isEnabled, notificationAuthorization != .authorized {
                await requestNotifications()
            } else {
                await resyncReminderNotifications()
            }
        }
    }

    func updateReminderDelivery(_ delivery: PeriodicReminderDelivery) {
        reminderDeliveryUpdateRevision &+= 1
        let revision = reminderDeliveryUpdateRevision
        if delivery == .notification {
            reminderDelivery = .notification
        }
        Task {
            if delivery == .alarm {
                guard await authorizeAppleAlarmIfNeeded() else { return }
            }
            guard revision == reminderDeliveryUpdateRevision else { return }
            reminderDelivery = delivery
            await reminderScheduler.updateReminderDeliveryPreference(delivery)
            await resyncReminderNotifications()
        }
    }

    func requestAppleAlarmAuthorization() {
        reminderDeliveryUpdateRevision &+= 1
        let revision = reminderDeliveryUpdateRevision
        Task {
            guard await authorizeAppleAlarmIfNeeded() else { return }
            guard revision == reminderDeliveryUpdateRevision else { return }
            reminderDelivery = .alarm
            await reminderScheduler.updateReminderDeliveryPreference(.alarm)
            await resyncReminderNotifications()
        }
    }

    func makeCompletedHistoryViewModel(
        initialFilter: CompletedHistoryFilter = .week
    ) -> CompletedHistoryViewModel {
        let viewModel = CompletedHistoryViewModel(
            sessionStore: sessionStore,
            itemRepository: itemRepository,
            taskApplicationService: taskApplicationService,
            taskListRepository: taskListRepository,
            projectRepository: projectRepository,
            initialFilter: initialFilter
        )
        viewModel.onTaskMutated = onTaskMutated
        return viewModel
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

    func iCloudStatusDescription(for status: ICloudStatus) -> String {
        switch status {
        case .available:
            return "iCloud 已登录，Together 会使用你的私人 iCloud 数据库进行同步与恢复。"
        case .noAccount:
            return "当前设备未登录 iCloud。登录 iCloud 后可在 Apple 设备间恢复任务数据。"
        case .restricted:
            return "当前 iCloud 访问受限，请检查系统设置或屏幕使用时间限制。"
        case .couldNotDetermine:
            return "暂时无法确认 iCloud 状态，可以稍后重新检查。"
        case .temporarilyUnavailable:
            return "iCloud 暂时不可用，系统恢复后会继续同步。"
        }
    }

    private func resyncReminderNotifications() async {
        let spaceID = sessionStore.currentSpace?.id
        let tasks = (try? await itemRepository.fetchActiveItems(spaceID: spaceID)) ?? []
        let projects = (try? await projectRepository.fetchProjects(spaceID: spaceID)) ?? []
        let periodicTasks = (try? await periodicTaskRepository.fetchActiveTasks(spaceID: spaceID)) ?? []
        await reminderScheduler.resync(
            spaceID: spaceID,
            tasks: tasks,
            projects: projects,
            includeTaskReminders: taskReminderEnabled,
            includeDailySummary: taskReminderEnabled && dailySummaryEnabled
        )
        for task in periodicTasks {
            await reminderScheduler.syncPeriodicTaskReminder(for: task, referenceDate: .now)
        }
    }

    private func authorizeAppleAlarmIfNeeded() async -> Bool {
        let currentStatus = await reminderScheduler.alarmAuthorizationStatus()
        let resolvedStatus: RoutineAlarmAuthorizationStatus
        if currentStatus == .notDetermined {
            resolvedStatus = (try? await reminderScheduler.requestAlarmAuthorization()) ?? .denied
        } else {
            resolvedStatus = currentStatus
        }
        alarmAuthorization = resolvedStatus
        return resolvedStatus == .authorized
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
