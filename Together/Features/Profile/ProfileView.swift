import SwiftUI
import UIKit

struct ProfileView: View {
    @Environment(AppContext.self) private var appContext
    @Environment(\.openURL) private var openURL
    @Bindable var viewModel: ProfileViewModel
    @State private var topChromeProgress: CGFloat = 0
    @State private var showsSignOutAlert: Bool = false
    @State private var showsClearCacheAlert: Bool = false
    @State private var showsResetMigrationAlert: Bool = false
    @Namespace private var profileTransition

    var body: some View {
        let currentUser = appContext.sessionStore.currentUser

        GeometryReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: AppTheme.spacing.lg) {
                    ProfileScrollOffsetProbe()

                    // MARK: - 名片区
                    NavigationLink(value: viewModel.isPairMode ? ProfileRoute.editPairProfile : ProfileRoute.editProfile) {
                        ProfileUserCard(
                            primaryName: currentUser?.displayName ?? viewModel.profileCardPrimaryName,
                            secondaryName: viewModel.profileCardSecondaryName,
                            primaryAvatar: ProfileCardAvatar(
                                displayName: currentUser?.displayName ?? viewModel.profileCardPrimaryName,
                                avatarAsset: currentUser?.avatarAsset ?? .system("person.crop.circle.fill"),
                                overrideImage: nil
                            ),
                            secondaryAvatarState: viewModel.profileCardSecondaryAvatarState
                        )
                        .id(appContext.sessionStore.userProfileRevision)
                        .matchedTransitionSource(id: ProfileTransitionSource.profileCard, in: profileTransition)
                    }
                    .buttonStyle(.plain)
                    .simultaneousGesture(
                        TapGesture().onEnded {
                            HomeInteractionFeedback.selection()
                        }
                    )

                    // MARK: - 分组设置
                    collaborationSection
                    executionPreferencesSection
                    notificationsAndHistorySection
                    securitySection
                    dataAndAccountSection
                    aboutRow
                    appearanceSection

                    // MARK: - 退出登录
                    signOutFooter
                }
                .padding(.horizontal, AppTheme.spacing.md)
                .padding(.top, AppTheme.spacing.md)
                .padding(.bottom, AppTheme.spacing.xxl)
            }
            .coordinateSpace(name: ProfileScrollOffsetKey.coordinateSpaceName)
            .applyScrollEdgeProtection()
            .background(backgroundView.ignoresSafeArea())
            .overlay(alignment: .top) {
                topChromeGradientMask(safeAreaTop: proxy.safeAreaInsets.top)
            }
        }
        .navigationTitle("我")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .toolbarBackground(.regularMaterial, for: .navigationBar)
        .toolbarBackground(topChromeProgress > 0.02 ? .visible : .hidden, for: .navigationBar)
        .font(AppTheme.typography.body)
        .navigationDestination(for: ProfileRoute.self) { route in
            switch route {
            case .editProfile:
                EditProfileView(
                    viewModel: viewModel.makeEditProfileViewModel(user: appContext.sessionStore.currentUser)
                )
                    .id(appContext.sessionStore.userProfileRevision)
                    .navigationTransition(.zoom(sourceID: ProfileTransitionSource.profileCard, in: profileTransition))
            case .editPairProfile:
                EditPairProfileView(
                    viewModel: viewModel.makeEditProfileViewModel(user: appContext.sessionStore.currentUser),
                    partnerAvatar: viewModel.pairPartnerAvatar,
                    partnerName: viewModel.profileCardSecondaryName ?? "对方",
                    spaceName: viewModel.pairSpaceDisplayName,
                    onSpaceNameChanged: { newName in
                        viewModel.updatePairSpaceDisplayName(newName)
                    }
                )
                    .id(appContext.sessionStore.userProfileRevision)
                    .navigationTransition(.zoom(sourceID: ProfileTransitionSource.profileCard, in: profileTransition))
            case .completedHistory:
                CompletedHistoryView(viewModel: viewModel.makeCompletedHistoryViewModel())
            case .privacyPolicy:
                ProfilePrivacyPolicyView()
            case .termsOfService:
                ProfileTermsOfServiceView()
            case .accountDeletion:
                ProfileAccountDeletionView(viewModel: viewModel)
            case .subscription:
                ProfileSubscriptionView()
            case .feedback:
                ProfileFeedbackView()
            case .about:
                ProfileAboutView(appVersion: viewModel.appVersionString)
            case .notificationSettings, .futureCollaboration:
                EmptyView()
            }
        }
        .task {
            await viewModel.load()
        }
        // Universal Link 到达后自动处理邀请码
        .task(id: appContext.pendingInviteCode) {
            guard let code = appContext.consumePendingInviteCode() else { return }
            let state = appContext.sessionStore.bindingState
            guard state == .singleTrial || state == .unbound else { return }
            await viewModel.acceptInviteByCode(code)
        }
        .sheet(item: $viewModel.customDurationSheet) { kind in
            ProfileDurationPickerSheet(
                title: kind.title,
                initialMinutes: viewModel.customDurationInitialMinutes,
                onSave: { viewModel.applyCustomDuration($0) },
                onDismiss: { viewModel.dismissCustomDurationSheet() }
            )
        }
        .onChange(of: viewModel.bindingState) { oldState, newState in
            if oldState != .paired, newState == .paired {
                let generator = UINotificationFeedbackGenerator()
                generator.notificationOccurred(.success)
            }
        }
        .sheet(isPresented: $viewModel.inviteCodeEntryPresented) {
            InviteCodeEntryView(isPresented: $viewModel.inviteCodeEntryPresented) { code in
                await viewModel.acceptInviteByCode(code)
            }
            .presentationDetents([.medium])
        }
        .onPreferenceChange(ProfileScrollOffsetKey.self) { offset in
            let progress = min(max(-offset / 56, 0), 1)
            topChromeProgress = progress
        }
        .animation(.easeOut(duration: 0.18), value: topChromeProgress)
        .alert("确认退出", isPresented: $showsSignOutAlert) {
            Button("取消", role: .cancel) {}
            Button("退出登录", role: .destructive) {
                Task { await viewModel.signOut() }
            }
        } message: {
            Text("退出后需要重新登录才能使用。")
        }
        .alert("清除缓存", isPresented: $showsClearCacheAlert) {
            Button("取消", role: .cancel) {}
            Button("清除", role: .destructive) {
                viewModel.clearCache()
            }
        } message: {
            Text("将清除应用的缓存数据（\(viewModel.cacheSizeString)），不会影响你的任务数据。")
        }
        .alert("重置同步迁移", isPresented: $showsResetMigrationAlert) {
            Button("取消", role: .cancel) {}
            Button("重置", role: .destructive) {
                SyncMigrationService.resetMigration()
            }
        } message: {
            Text("将重置公有库到私有库的数据迁移状态，下次启动时会重新执行迁移。仅在同步异常时使用。")
        }
    }

    // MARK: - Background & Chrome

    private var backgroundView: some View {
        AppTheme.colors.background
    }

    private func topChromeGradientMask(safeAreaTop: CGFloat) -> some View {
        Rectangle()
            .fill(
                LinearGradient(
                    colors: [
                        AppTheme.colors.background.opacity(0.16 * topChromeProgress),
                        .clear
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .frame(height: safeAreaTop + 44)
            .allowsHitTesting(false)
    }

    // MARK: - 双人协作

    private var collaborationSection: some View {
        ProfileSettingsGroupCard(title: "双人协作") {
            ProfileSettingsRow(
                title: "当前工作空间",
                value: viewModel.spaceSummary
            )

            ProfileSettingsRow(
                title: "双人模式",
                value: viewModel.collaborationSummary
            )

            collaborationActionRow
        }
    }

    @ViewBuilder
    private var collaborationActionRow: some View {
        switch viewModel.bindingState {
        case .singleTrial, .unbound:
            VStack(spacing: 10) {
                Button {
                    HomeInteractionFeedback.selection()
                    Task { await viewModel.createInvite() }
                } label: {
                    collaborationButtonLabel(title: "发起双人邀请", tint: AppTheme.colors.title)
                }
                .buttonStyle(.plain)

                if let err = viewModel.createInviteError {
                    Text(err)
                        .font(AppTheme.typography.sized(12, weight: .medium))
                        .foregroundStyle(AppTheme.colors.danger)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 8)
                }

                Button {
                    HomeInteractionFeedback.selection()
                    viewModel.inviteCodeEntryPresented = true
                } label: {
                    collaborationButtonLabel(title: "输入邀请码", tint: AppTheme.colors.profileAccent)
                }
                .buttonStyle(.plain)
            }

        case .invitePending:
            InvitePendingSection(
                invite: viewModel.activeInvite,
                onCopy: { code in
                    UIPasteboard.general.string = code
                    HomeInteractionFeedback.selection()
                },
                onCheckAccepted: {
                    await viewModel.checkInviteAccepted()
                },
                onCancel: {
                    await viewModel.cancelCurrentInvite()
                },
                onRegenerate: {
                    await viewModel.cancelCurrentInvite()
                    await viewModel.createInvite()
                }
            )

        case .inviteReceived:
            HStack(spacing: 10) {
                Button {
                    HomeInteractionFeedback.selection()
                    Task { await viewModel.acceptInvite() }
                } label: {
                    collaborationButtonLabel(title: "接受邀请", tint: AppTheme.colors.title)
                }
                .buttonStyle(.plain)

                Button {
                    HomeInteractionFeedback.selection()
                    Task { await viewModel.declineInvite() }
                } label: {
                    collaborationButtonLabel(title: "拒绝", tint: AppTheme.colors.coral)
                }
                .buttonStyle(.plain)
            }

        case .paired:
            Button {
                HomeInteractionFeedback.selection()
                Task { await viewModel.unbindPairSpace() }
            } label: {
                collaborationButtonLabel(title: "解绑双人空间", tint: AppTheme.colors.coral)
            }
            .buttonStyle(.plain)
        }
    }

    private func collaborationButtonLabel(title: String, tint: Color) -> some View {
        Text(title)
            .font(AppTheme.typography.sized(14, weight: .bold))
            .foregroundStyle(tint)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(AppTheme.colors.surfaceElevated)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(AppTheme.colors.outline.opacity(0.14), lineWidth: 1)
            }
    }

    // MARK: - 执行偏好

    private var executionPreferencesSection: some View {
        ProfileSettingsGroupCard(title: "执行偏好") {
            ProfileSettingsRow(
                title: "临期任务提醒",
                isOn: Binding(
                    get: { viewModel.taskReminderEnabled },
                    set: { viewModel.updateTaskReminderEnabled($0) }
                )
            )

            if viewModel.taskReminderEnabled {
                expandableSelectionRow(
                    title: "提醒时间",
                    value: viewModel.taskUrgencySummary,
                    setting: .taskUrgency
                ) {
                    selectionContent(
                        options: viewModel.taskUrgencyOptions,
                        selectedValue: viewModel.taskUrgencyWindowMinutes,
                        label: { viewModel.taskUrgencyLabel(minutes: $0) },
                        onSelect: { viewModel.updateTaskUrgencyWindow(minutes: $0) },
                        onCustom: {
                            HomeInteractionFeedback.selection()
                            viewModel.presentCustomDurationSheet(.taskUrgency)
                        }
                    )
                }
                .transition(profileListRowTransition)
            }

            expandableSelectionRow(
                title: "默认推迟时间",
                value: viewModel.defaultSnoozeSummary,
                setting: .defaultSnooze
            ) {
                selectionContent(
                    options: viewModel.snoozeMinuteOptions,
                    selectedValue: viewModel.defaultSnoozeMinutes,
                    label: { viewModel.relativeTimeLabel(minutes: $0) },
                    onSelect: { viewModel.updateDefaultSnoozeMinutes($0) },
                    onCustom: {
                        HomeInteractionFeedback.selection()
                        viewModel.presentCustomDurationSheet(.defaultSnooze)
                    }
                )
            }

            expandableSelectionRow(
                title: "双人预设留言",
                value: viewModel.pairQuickReplyMessages.joined(separator: " / "),
                setting: .pairQuickReplies
            ) {
                ProfileQuickReplyEditor(
                    initialMessages: viewModel.pairQuickReplyMessages,
                    onSave: { messages in
                        HomeInteractionFeedback.selection()
                        viewModel.updatePairQuickReplyMessages(messages)
                    }
                )
            }

            ProfileSettingsRow(
                title: "已完成自动归档",
                isOn: Binding(
                    get: { viewModel.completedTaskAutoArchiveEnabled },
                    set: { viewModel.updateCompletedTaskAutoArchiveEnabled($0) }
                )
            )

            if viewModel.completedTaskAutoArchiveEnabled {
                expandableSelectionRow(
                    title: "归档时间",
                    value: viewModel.completedArchiveSummary,
                    setting: .completedArchive
                ) {
                    selectionContent(
                        options: viewModel.completedTaskAutoArchiveOptions,
                        selectedValue: viewModel.completedTaskAutoArchiveDays,
                        label: { "\($0)天后" },
                        onSelect: { viewModel.updateCompletedTaskAutoArchiveDays($0) }
                    )
                }
                .transition(profileListRowTransition)
            }
        }
        .animation(profileListAnimation, value: viewModel.taskReminderEnabled)
        .animation(profileListAnimation, value: viewModel.completedTaskAutoArchiveEnabled)
    }

    // MARK: - 通知与权限

    private var notificationsAndHistorySection: some View {
        ProfileSettingsGroupCard(title: "通知与权限") {
            if viewModel.notificationAuthorization == .authorized {
                ProfileSettingsRow(
                    title: "提醒权限",
                    value: "已开启"
                )
            } else {
                Button {
                    HomeInteractionFeedback.selection()
                    if viewModel.notificationAuthorization == .denied {
                        if let url = URL(string: UIApplication.openNotificationSettingsURLString) {
                            openURL(url)
                        }
                    } else {
                        Task { await viewModel.requestNotifications() }
                    }
                } label: {
                    ProfileSettingsRow(
                        title: "提醒权限",
                        value: viewModel.notificationAuthorization == .denied ? "去开启" : "未开启",
                        showsChevron: true
                    )
                }
                .buttonStyle(.plain)
            }

            // 统一权限管理入口 → 跳转系统设置
            Button {
                HomeInteractionFeedback.selection()
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    openURL(url)
                }
            } label: {
                ProfileSettingsRow(
                    title: "权限管理",
                    value: "系统设置",
                    showsChevron: true
                )
            }
            .buttonStyle(.plain)

            NavigationLink(value: ProfileRoute.completedHistory) {
                ProfileSettingsRow(
                    title: "历史任务",
                    value: "查看",
                    showsChevron: true
                )
            }
            .buttonStyle(.plain)
            .simultaneousGesture(
                TapGesture().onEnded {
                    HomeInteractionFeedback.selection()
                }
            )
        }
    }

    // MARK: - 安全与隐私

    private var securitySection: some View {
        ProfileSettingsGroupCard(title: "安全与隐私") {
            ProfileSettingsRow(
                title: "应用锁定（\(viewModel.biometricTypeName)）",
                isOn: Binding(
                    get: { viewModel.appLockEnabled },
                    set: { viewModel.updateAppLockEnabled($0) }
                )
            )

            if viewModel.appLockEnabled {
                Text("切到后台时自动锁定，需要\(viewModel.biometricTypeName)或密码解锁")
                    .font(AppTheme.typography.sized(13, weight: .medium))
                    .foregroundStyle(AppTheme.colors.textTertiary)
                    .padding(.horizontal, 4)
            }
        }
    }

    // MARK: - 数据与账号

    private var dataAndAccountSection: some View {
        ProfileSettingsGroupCard(title: "数据与账号") {
            // iCloud 同步状态
            ProfileSettingsRow(
                title: "iCloud 同步",
                value: viewModel.iCloudStatusSummary
            )

            // 会员入口横幅
            NavigationLink(value: ProfileRoute.subscription) {
                ProBannerRow()
            }
            .buttonStyle(.plain)
            .simultaneousGesture(
                TapGesture().onEnded { HomeInteractionFeedback.selection() }
            )

            // 清除缓存
            Button {
                HomeInteractionFeedback.selection()
                showsClearCacheAlert = true
            } label: {
                ProfileSettingsRow(
                    title: "清除缓存",
                    value: viewModel.cacheSizeString
                )
            }
            .buttonStyle(.plain)

            // 重置同步迁移（手动兜底：公有库→私有库迁移异常时使用）
            Button {
                HomeInteractionFeedback.selection()
                showsResetMigrationAlert = true
            } label: {
                ProfileSettingsRow(
                    title: "重置同步迁移",
                    value: SyncMigrationService.isMigrationCompleted ? "已完成" : "进行中"
                )
            }
            .buttonStyle(.plain)

            // 账号注销（合规必备：Apple 5.1.1(v) + 个保法 Art. 47）
            NavigationLink(value: ProfileRoute.accountDeletion) {
                ProfileSettingsRow(
                    title: "账号注销",
                    value: "",
                    showsChevron: true
                )
            }
            .buttonStyle(.plain)
            .simultaneousGesture(
                TapGesture().onEnded { HomeInteractionFeedback.selection() }
            )
        }
    }

    // MARK: - 关于 Together（跳转子页面）

    private var aboutRow: some View {
        ProfileSettingsGroupCard(title: "") {
            NavigationLink(value: ProfileRoute.about) {
                ProfileSettingsRow(
                    title: "关于 Together",
                    value: "v\(viewModel.appVersionString)",
                    showsChevron: true
                )
            }
            .buttonStyle(.plain)
            .simultaneousGesture(
                TapGesture().onEnded { HomeInteractionFeedback.selection() }
            )
        }
    }

    // MARK: - 外观（紧凑样式）

    private var appearanceSection: some View {
        ProfileSettingsGroupCard(title: "外观") {
            HStack(spacing: 4) {
                ForEach(AppearanceMode.allCases, id: \.self) { mode in
                    let isSelected = appContext.appearanceManager.mode == mode

                    Button {
                        HomeInteractionFeedback.selection()
                        withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
                            appContext.appearanceManager.mode = mode
                        }
                    } label: {
                        Text(mode.title)
                            .font(AppTheme.typography.sized(13, weight: .semibold))
                            .foregroundStyle(isSelected ? .white : AppTheme.colors.body)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 9)
                            .background(
                                Capsule(style: .continuous)
                                    .fill(isSelected ? AppTheme.colors.sky : .clear)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: - 退出登录

    private var signOutFooter: some View {
        Button {
            HomeInteractionFeedback.selection()
            showsSignOutAlert = true
        } label: {
            Text("退出登录")
                .font(AppTheme.typography.sized(15, weight: .semibold))
                .foregroundStyle(AppTheme.colors.danger)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(AppTheme.colors.surfaceElevated)
                )
                .shadow(color: AppTheme.colors.shadow.opacity(0.14), radius: 8, y: 4)
        }
        .buttonStyle(.plain)
        .padding(.top, AppTheme.spacing.sm)
    }

    // MARK: - Helpers

    private var profileListAnimation: Animation {
        .spring(response: 0.34, dampingFraction: 0.86)
    }

    private var profileListRowTransition: AnyTransition {
        .asymmetric(
            insertion: .move(edge: .top).combined(with: .opacity).combined(with: .scale(scale: 0.985, anchor: .top)),
            removal: .move(edge: .top).combined(with: .opacity)
        )
    }

    private func expandableSelectionRow<Content: View>(
        title: String,
        value: String,
        setting: ProfileExpandedSetting,
        @ViewBuilder content: () -> Content
    ) -> some View {
        ProfileExpandableDisclosureRow(
            title: title,
            value: value,
            isExpanded: Binding(
                get: { viewModel.expandedSetting == setting },
                set: { isExpanded in
                    if isExpanded {
                        viewModel.expandedSetting = setting
                    } else if viewModel.expandedSetting == setting {
                        viewModel.expandedSetting = nil
                    }
                }
            ),
            content: content
        )
    }

    private func selectionContent(
        options: [Int],
        selectedValue: Int,
        label: @escaping (Int) -> String,
        onSelect: @escaping (Int) -> Void,
        onCustom: (() -> Void)? = nil
    ) -> some View {
        VStack(spacing: 8) {
            ForEach(options, id: \.self) { option in
                ProfileInlineOptionButton(
                    title: label(option),
                    isSelected: selectedValue == option
                ) {
                    HomeInteractionFeedback.selection()
                    onSelect(option)
                }
            }

            if let onCustom {
                ProfileInlineOptionButton(
                    title: "自定义",
                    isSelected: options.contains(selectedValue) == false,
                    action: onCustom
                )
            }
        }
    }
}

// MARK: - Pro Banner

private struct ProBannerRow: View {
    var body: some View {
        HStack(spacing: 14) {
            // 皇冠图标
            ZStack {
                Circle()
                    .fill(.white)
                    .frame(width: 40, height: 40)

                Image(systemName: "crown.fill")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(.black)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text("Together Pro")
                    .font(AppTheme.typography.sized(17, weight: .bold))
                    .foregroundStyle(.white)

                Text("升级解锁全部功能")
                    .font(AppTheme.typography.sized(13, weight: .medium))
                    .foregroundStyle(.white.opacity(0.6))
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(AppTheme.typography.sized(14, weight: .semibold))
                .foregroundStyle(.white.opacity(0.5))
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Color(white: 0.18), Color(white: 0.08)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(
                    AngularGradient(
                        colors: [
                            .purple.opacity(0.5), .blue.opacity(0.4),
                            .green.opacity(0.3), .yellow.opacity(0.3),
                            .orange.opacity(0.3), .pink.opacity(0.4),
                            .purple.opacity(0.5)
                        ],
                        center: .center
                    ),
                    lineWidth: 1.5
                )
        )
    }
}

// MARK: - Private Components

private struct ProfileQuickReplyEditor: View {
    let initialMessages: [String]
    let onSave: ([String]) -> Void

    @State private var messages: [String]

    init(initialMessages: [String], onSave: @escaping ([String]) -> Void) {
        self.initialMessages = NotificationSettings.normalizedPairQuickReplyMessages(initialMessages)
        self.onSave = onSave
        _messages = State(initialValue: NotificationSettings.normalizedPairQuickReplyMessages(initialMessages))
    }

    var body: some View {
        VStack(spacing: 8) {
            ForEach(messages.indices, id: \.self) { index in
                TextField("预设留言", text: Binding(
                    get: { messages[index] },
                    set: { messages[index] = $0 }
                ))
                .font(AppTheme.typography.textStyle(.subheadline, weight: .medium))
                .foregroundStyle(AppTheme.colors.title)
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(AppTheme.colors.backgroundSoft.opacity(0.92))
                )
            }

            Button("保存预设") {
                onSave(messages)
                messages = NotificationSettings.normalizedPairQuickReplyMessages(messages)
            }
            .font(AppTheme.typography.sized(14, weight: .bold))
            .foregroundStyle(AppTheme.colors.title)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(AppTheme.colors.surfaceElevated)
            )
        }
    }
}

private enum ProfileTransitionSource {
    static let profileCard = "profile-card"
}

private struct ProfileScrollOffsetProbe: View {
    var body: some View {
        GeometryReader { proxy in
            Color.clear
                .preference(
                    key: ProfileScrollOffsetKey.self,
                    value: proxy.frame(in: .named(ProfileScrollOffsetKey.coordinateSpaceName)).minY
                )
        }
        .frame(height: 0)
    }
}

private struct ProfileScrollOffsetKey: PreferenceKey {
    static let coordinateSpaceName = "profile-scroll"
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

#Preview("Profile") {
    NavigationStack {
        ProfileView(viewModel: AppContext.makeBootstrappedContext().profileViewModel)
    }
}

private struct ProfileExpandableDisclosureRow<Content: View>: View {
    let title: String
    let value: String
    @Binding var isExpanded: Bool
    @ViewBuilder let content: Content

    init(
        title: String,
        value: String,
        isExpanded: Binding<Bool>,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.value = value
        self._isExpanded = isExpanded
        self.content = content()
    }

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            VStack(spacing: 8) {
                Divider()
                    .overlay(AppTheme.colors.outline.opacity(0.45))
                    .padding(.bottom, 2)

                content
            }
            .padding(.top, 10)
        } label: {
            HStack(alignment: .center, spacing: 12) {
                ProfileSettingsRow(
                    title: title,
                    value: value
                )

                Spacer(minLength: 0)
            }
        }
        .disclosureGroupStyle(ProfilePlainDisclosureGroupStyle())
        .tint(AppTheme.colors.body.opacity(0.48))
        .contentShape(Rectangle())
    }
}

private struct ProfilePlainDisclosureGroupStyle: DisclosureGroupStyle {
    func makeBody(configuration: Configuration) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                HomeInteractionFeedback.selection()
                withAnimation(.easeOut(duration: 0.2)) {
                    configuration.isExpanded.toggle()
                }
            } label: {
                HStack(alignment: .center, spacing: 12) {
                    configuration.label

                    Image(systemName: "chevron.down")
                        .font(AppTheme.typography.sized(12, weight: .bold))
                        .foregroundStyle(AppTheme.colors.body.opacity(0.36))
                        .rotationEffect(.degrees(configuration.isExpanded ? 180 : 0))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if configuration.isExpanded {
                configuration.content
            }
        }
    }
}

private struct ProfileInlineOptionButton: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Text(title)
                    .font(AppTheme.typography.textStyle(.subheadline, weight: .medium))
                    .foregroundStyle(isSelected ? AppTheme.colors.sky : AppTheme.colors.title)

                Spacer()

                if isSelected {
                    Image(systemName: "checkmark")
                        .font(AppTheme.typography.sized(13, weight: .bold))
                        .foregroundStyle(AppTheme.colors.sky)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(isSelected ? AppTheme.colors.sky.opacity(0.1) : .clear)
            )
        }
        .buttonStyle(.plain)
    }
}
