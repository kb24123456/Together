import Foundation
import Observation

enum ProfileExpandedSetting: Hashable {
    case taskUrgency
    case defaultSnooze
    case completedArchive
    case pairQuickReplies
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
    private let pairingService: PairingServiceProtocol
    private let userProfileRepository: UserProfileRepositoryProtocol
    private let notificationService: NotificationServiceProtocol
    private let itemRepository: ItemRepositoryProtocol
    private let taskApplicationService: TaskApplicationServiceProtocol
    private let taskListRepository: TaskListRepositoryProtocol
    private let projectRepository: ProjectRepositoryProtocol
    private let reminderScheduler: ReminderSchedulerProtocol
    private let biometricAuthService: BiometricAuthServiceProtocol

    var loadState: LoadableState = .idle
    var notificationAuthorization: NotificationAuthorizationStatus = .notDetermined
    var expandedSetting: ProfileExpandedSetting?
    var customDurationSheet: ProfileCustomDurationKind?
    var inviteCodeEntryPresented: Bool = false
    var isCheckingInvite: Bool = false
    var acceptInviteError: String?
    var createInviteError: String?
    var iCloudStatus: ICloudStatus = .couldNotDetermine
    var isAccountDeletionInProgress: Bool = false

    init(
        sessionStore: SessionStore,
        authService: AuthServiceProtocol,
        pairingService: PairingServiceProtocol,
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
        self.pairingService = pairingService
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
    var bindingState: BindingState { sessionStore.bindingState }
    var isPairMode: Bool { sessionStore.activeMode == .pair }
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

    func makeEditProfileViewModel(user: User?) -> EditProfileViewModel {
        EditProfileViewModel(
            sessionStore: sessionStore,
            userProfileRepository: userProfileRepository,
            user: user
        )
    }

    /// 对方的头像信息（用于双人编辑界面）
    var pairPartnerAvatar: ProfileCardAvatar {
        let partner = pairPartner
        return ProfileCardAvatar(
            displayName: partner?.nickname ?? "对方",
            avatarAsset: .system("person.crop.circle.fill"), // 对方头像暂用默认
            overrideImage: nil
        )
    }

    /// 共享空间的自定义名称
    var pairSpaceDisplayName: String {
        pairSpace?.displayName ?? ""
    }

    /// 更新共享空间的显示名称
    func updatePairSpaceDisplayName(_ newName: String) {
        guard var space = sessionStore.currentPairSpace else { return }
        space.displayName = newName.isEmpty ? nil : newName
        sessionStore.pairSpaceSummary?.pairSpace = space
        Task {
            await pairingService.updatePairSpaceDisplayName(pairSpaceID: space.id, displayName: newName.isEmpty ? nil : newName)
        }
        // 触发 profile sync 将新空间名同步到伙伴
        sessionStore.userProfileRevision = UUID()
    }

    /// 获取配对的对方成员
    private var pairPartner: PairMember? {
        guard let pairSpace else { return nil }
        if pairSpace.memberA.userID == currentUser?.id {
            return pairSpace.memberB
        } else {
            return pairSpace.memberA
        }
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
        if isPairMode, let pairName = pairSpace?.displayName, !pairName.isEmpty {
            return pairName
        }
        return currentSpace?.displayName ?? "我的任务空间"
    }

    var collaborationSummary: String {
        bindingState.description
    }

    var collaborationDetailText: String {
        switch bindingState {
        case .paired:
            return pairSpaceSummaryText
        case .invitePending:
            return "等待对方接受邀请"
        case .inviteReceived:
            return "收到邀请，等待你的处理"
        case .singleTrial, .unbound:
            return "创建共享任务空间后，你们会看到同一套双人任务数据"
        }
    }

    var activeModeSummary: String {
        sessionStore.activeMode == .pair ? "当前在双人模式" : "当前在单人模式"
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

    var pairQuickReplyMessages: [String] {
        NotificationSettings.normalizedPairQuickReplyMessages(
            sessionStore.currentUser?.preferences.pairQuickReplyMessages
            ?? NotificationSettings.defaultPairQuickReplyMessages
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
        let userID = currentUser?.id
        let spaceID = currentSpace?.id

        // 1. 如果配对状态，先解绑
        if let pairSpaceID = pairSpace?.id, let userID {
            _ = try? await pairingService.unbind(pairSpaceID: pairSpaceID, actorID: userID)
        }

        // 2. 删除所有任务数据
        if let spaceID {
            let allItems = (try? await itemRepository.fetchActiveItems(spaceID: spaceID)) ?? []
            let archivedItems = (try? await itemRepository.fetchCompletedItems(
                spaceID: spaceID, searchText: nil, before: nil, limit: 10000
            )) ?? []
            for item in allItems + archivedItems {
                try? await itemRepository.deleteItem(itemID: item.id)
            }
        }

        // 3. 删除所有项目
        if let spaceID {
            let projects = (try? await projectRepository.fetchProjects(spaceID: spaceID)) ?? []
            for project in projects {
                try? await projectRepository.deleteProject(projectID: project.id)
            }
        }

        // 4. 取消所有本地通知
        await reminderScheduler.resync(tasks: [], projects: [])

        // 5. 签出（清除 Keychain + Session）
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

    func createInvite() async {
        guard let inviterID = currentUser?.id else { return }
        let displayName = currentUser?.displayName ?? ""
        createInviteError = nil
        do {
            let invite = try await pairingService.createInvite(from: inviterID, displayName: displayName)
            sessionStore.pairingContext.activeInvite = invite
            sessionStore.pairingContext.state = .invitePending
        } catch {
            let message: String
            if let pairingError = error as? PairingError {
                message = pairingError.errorDescription ?? error.localizedDescription
            } else {
                message = "发布邀请失败：\(error.localizedDescription)"
            }
            createInviteError = message
        }
    }

    /// Device B: accept a cross-device invite by entering the invite code.
    /// Returns an error message string if failed, or nil on success.
    @discardableResult
    func acceptInviteByCode(_ code: String) async -> String? {
        guard let responderID = currentUser?.id else { return "用户未登录" }
        let responderName = currentUser?.displayName ?? ""
        acceptInviteError = nil
        do {
            let context = try await pairingService.acceptInviteByCode(
                code,
                responderID: responderID,
                responderDisplayName: responderName
            )
            apply(pairingContext: context)
            inviteCodeEntryPresented = false
            // CKSyncEngine handles initial sync automatically via PairSyncBridge
            return nil
        } catch let error as PairingError {
            let msg = error.errorDescription ?? "配对失败"
            acceptInviteError = msg
            return msg
        } catch {
            let msg = "连接失败：\(error.localizedDescription)"
            acceptInviteError = msg
            return msg
        }
    }

    /// Device A: cancel all pending invites and reset to singleTrial.
    func cancelCurrentInvite() async {
        // 1. 立即重置 UI（不等任何异步操作）
        let resetContext = PairingContext(
            state: .singleTrial,
            pairSpaceSummary: nil,
            activeInvite: nil
        )
        apply(pairingContext: resetContext)

        // 2. 异步清理 SwiftData 中残留的 pending 邀请
        guard let userID = currentUser?.id else { return }
        if let freshContext = try? await pairingService.cancelAllPendingInvites(for: userID) {
            apply(pairingContext: freshContext)
        }
    }

    /// Device A: poll CloudKit to see if the partner has accepted the invite.
    func checkInviteAccepted() async {
        guard let inviterID = currentUser?.id else { return }

        // 优先从 activeInvite 获取 pairSpaceID，没有则从已有 pairSpace 获取
        let pairSpaceID: UUID? = activeInvite?.pairSpaceID ?? pairSpace?.id

        guard let pairSpaceID else {
            // 如果连 pairSpaceID 都获取不到，重新加载 context 看看
            let freshContext = await pairingService.currentPairingContext(for: inviterID)
            if freshContext.state != .invitePending {
                // 状态已经不是 invitePending，直接同步
                apply(pairingContext: freshContext)
            }
            return
        }

        isCheckingInvite = true
        if let context = try? await pairingService.checkAndFinalizeIfAccepted(
            pairSpaceID: pairSpaceID,
            inviterID: inviterID
        ) {
            apply(pairingContext: context)
            // 1.8: 检测到对方接受后，推送本地任务到 CloudKit
            // CKSyncEngine handles sync automatically via PairSyncBridge
        }
        isCheckingInvite = false
    }

    func acceptInvite() async {
        guard let inviteID = activeInvite?.id, let userID = currentUser?.id else { return }
        guard let pairingContext = try? await pairingService.acceptInvite(inviteID: inviteID, responderID: userID) else { return }
        apply(pairingContext: pairingContext)
    }

    func declineInvite() async {
        guard let inviteID = activeInvite?.id, let userID = currentUser?.id else { return }
        guard let pairingContext = try? await pairingService.declineInvite(inviteID: inviteID, responderID: userID) else { return }
        apply(pairingContext: pairingContext)
    }

    func unbindPairSpace() async {
        guard let pairSpaceID = pairSpace?.id, let userID = currentUser?.id else { return }
        guard let pairingContext = try? await pairingService.unbind(pairSpaceID: pairSpaceID, actorID: userID) else { return }
        apply(pairingContext: pairingContext)
        sessionStore.activeMode = .single
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

    func updatePairQuickReplyMessages(_ messages: [String]) {
        guard var user = sessionStore.currentUser else { return }
        user.preferences.pairQuickReplyMessages = NotificationSettings.normalizedPairQuickReplyMessages(messages)
        applyUpdatedPreferences(user.preferences, to: user)
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
        sessionStore.currentUser = nil
        sessionStore.singleSpace = nil
        sessionStore.pairSpaceSummary = nil
        sessionStore.availableModeStates = [.single]
        sessionStore.pairingContext = PairingContext(state: .singleTrial, pairSpaceSummary: nil, activeInvite: nil)
        sessionStore.activeMode = .single
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
        // 动态找到"不是自己"的那个成员，而不是硬编码 memberB
        let partner: PairMember?
        if pairSpace?.memberA.userID == currentUser?.id {
            partner = pairSpace?.memberB
        } else {
            partner = pairSpace?.memberA
        }
        guard let nickname = partner?.nickname.trimmingCharacters(in: .whitespacesAndNewlines) else {
            return nil
        }
        return nickname.isEmpty ? nil : nickname
    }

    private var pairSpaceSummaryText: String {
        if let linkedPartnerDisplayName {
            return "已与 \(linkedPartnerDisplayName) 共享"
        }
        return "双人空间已开启"
    }

    private func apply(pairingContext: PairingContext) {
        sessionStore.pairingContext = pairingContext
        sessionStore.pairSpaceSummary = pairingContext.pairSpaceSummary
        // 1.4: 正确设置 availableModeStates
        sessionStore.availableModeStates = pairingContext.pairSpaceSummary != nil
            ? [.single, .pair] : [.single]
        // 1.5: 绑定成功后自动切换到双人模式
        if pairingContext.state == .paired, pairingContext.pairSpaceSummary != nil {
            sessionStore.activeMode = .pair
        }
        // 解绑或丢失配对后回退到单人模式
        if pairingContext.pairSpaceSummary == nil, sessionStore.activeMode == .pair {
            sessionStore.activeMode = .single
        }
    }
}
