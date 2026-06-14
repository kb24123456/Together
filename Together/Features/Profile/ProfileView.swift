import SwiftUI
import UIKit

struct ProfileView: View {
    @Environment(AppContext.self) private var appContext
    @Environment(\.openURL) private var openURL
    @Bindable var viewModel: ProfileViewModel
    @State private var topChromeProgress: CGFloat = 0
    @State private var showsSignOutAlert: Bool = false
    @State private var showsClearCacheAlert: Bool = false
    @Namespace private var profileTransition

    var body: some View {
        let currentUser = appContext.sessionStore.currentUser

        GeometryReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: AppTheme.spacing.lg) {
                    ProfileScrollOffsetProbe()

                    // MARK: - 名片区
                    NavigationLink(value: ProfileRoute.editProfile) {
                        ProfileUserCard(
                            primaryName: currentUser?.displayName ?? viewModel.profileCardPrimaryName,
                            primaryAvatar: ProfileCardAvatar(
                                displayName: currentUser?.displayName ?? viewModel.profileCardPrimaryName,
                                avatarAsset: currentUser?.avatarAsset ?? .system("person.crop.circle.fill"),
                                overrideImage: nil
                            ),
                            subtitle: viewModel.identityCardSubtitle
                        )
                        .id(appContext.sessionStore.userProfileRevision)
                        .transition(.opacity.combined(with: .move(edge: .trailing)))
                        .matchedTransitionSource(id: ProfileTransitionSource.profileCard, in: profileTransition)
                    }
                    .buttonStyle(.plain)
                    .simultaneousGesture(
                        TapGesture().onEnded {
                            HomeInteractionFeedback.selection()
                        }
                    )

                    // MARK: - 分组设置
                    executionPreferencesSection
                    systemSettingsSection
                    aboutRow

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
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink(value: ProfileRoute.completedHistory) {
                    Text("日志")
                        .font(AppTheme.typography.body)
                        .fontWeight(.medium)
                }
                .accessibilityHint("查看已完成任务")
            }
        }
        .toolbarBackground(.regularMaterial, for: .navigationBar)
        .toolbarBackground(topChromeProgress > 0.02 ? .visible : .hidden, for: .navigationBar)
        .font(AppTheme.typography.body)
        .navigationDestination(for: ProfileRoute.self) { route in
            switch route {
            case .editProfile:
                EditProfileView(
                    viewModel: viewModel.makeEditProfileViewModel(user: appContext.sessionStore.currentUser)
                )
                    .navigationTransition(.zoom(sourceID: ProfileTransitionSource.profileCard, in: profileTransition))
            case .completedHistory:
                CompletedHistoryView(viewModel: viewModel.makeCompletedHistoryViewModel())
            case .privacyPolicy:
                ProfilePrivacyPolicyView()
            case .termsOfService:
                ProfileTermsOfServiceView()
            case .accountDeletion:
                ProfileAccountDeletionView(viewModel: viewModel)
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
        .sheet(item: $viewModel.customDurationSheet) { kind in
            ProfileDurationPickerSheet(
                title: kind.title,
                initialMinutes: viewModel.customDurationInitialMinutes,
                onSave: { viewModel.applyCustomDuration($0) },
                onDismiss: { viewModel.dismissCustomDurationSheet() }
            )
        }
        .onPreferenceChange(ProfileScrollOffsetKey.self) { offset in
            let progress = min(max(-offset / 56, 0), 1)
            topChromeProgress = progress
        }
        .animation(.easeOut(duration: 0.18), value: topChromeProgress)
        .alert("确认退出", isPresented: $showsSignOutAlert) {
            Button("取消", role: .cancel) {}
            Button("退出登录", role: .destructive) {
                HomeInteractionFeedback.warning()
                Task { await viewModel.signOut() }
            }
        } message: {
            Text("退出后需要重新登录才能使用。")
        }
        .alert("清除缓存", isPresented: $showsClearCacheAlert) {
            Button("取消", role: .cancel) {}
            Button("清除", role: .destructive) {
                HomeInteractionFeedback.delete()
                viewModel.clearCache()
            }
        } message: {
            Text("将清除应用的缓存数据（\(viewModel.cacheSizeString)），不会影响你的任务数据。")
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

    // MARK: - 系统设置（合并通知与外观 / 安全与隐私 / 数据与账号）

    private var systemSettingsSection: some View {
        ProfileSettingsGroupCard(title: "系统设置") {
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

            expandableSelectionRow(
                title: "外观",
                value: appearanceValueLabel,
                setting: .appearance
            ) {
                appearanceOptionsContent
            }

            ProfileSettingsRow(
                title: "应用锁定（\(viewModel.biometricTypeName)）",
                isOn: Binding(
                    get: { viewModel.appLockEnabled },
                    set: { viewModel.updateAppLockEnabled($0) }
                )
            )

            ProfileSettingsRow(
                title: "iCloud 同步",
                value: viewModel.iCloudStatusSummary
            )

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
        .animation(profileListAnimation, value: appContext.appearanceManager.mode)
    }

    private var appearanceValueLabel: String {
        appContext.appearanceManager.mode.title
    }

    // MARK: - 关于 Together（跳转子页面）

    private var aboutRow: some View {
        ProfileSettingsGroupCard(title: "") {
            NavigationLink(value: ProfileRoute.about) {
                ProfileSettingsRow(
                    title: "关于",
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

    // MARK: - 退出登录

    private var signOutFooter: some View {
        Button {
            HomeInteractionFeedback.selection()
            showsSignOutAlert = true
        } label: {
            Text("退出登录")
                .font(AppTheme.typography.sized(15, weight: .semibold))
                .foregroundStyle(AppTheme.colors.danger)
                .frame(maxWidth: .infinity, minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.top, AppTheme.spacing.lg)
        .accessibilityHint("退出后需要重新登录")
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

    private var appearanceOptionsContent: some View {
        VStack(spacing: AppTheme.spacing.xs) {
            ForEach(AppearanceMode.allCases, id: \.self) { mode in
                ProfileInlineOptionButton(
                    title: mode.title,
                    isSelected: appContext.appearanceManager.mode == mode
                ) {
                    HomeInteractionFeedback.selection()
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
                        appContext.appearanceManager.mode = mode
                    }
                }
            }
        }
    }

    private func selectionContent(
        options: [Int],
        selectedValue: Int,
        label: @escaping (Int) -> String,
        onSelect: @escaping (Int) -> Void,
        onCustom: (() -> Void)? = nil
    ) -> some View {
        VStack(spacing: AppTheme.spacing.xs) {
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

// MARK: - Private Components

private struct ProfileQuickReplyEditor: View {
    let initialMessages: [String]
    let onSave: ([String]) -> Void

    @State private var messages: [String]

    init(initialMessages: [String], onSave: @escaping ([String]) -> Void) {
        self.initialMessages = NotificationSettings.normalizedQuickReplyMessages(initialMessages)
        self.onSave = onSave
        _messages = State(initialValue: NotificationSettings.normalizedQuickReplyMessages(initialMessages))
    }

    var body: some View {
        VStack(spacing: AppTheme.spacing.xs) {
            ForEach(messages.indices, id: \.self) { index in
                TextField("预设留言", text: Binding(
                    get: { messages[index] },
                    set: { messages[index] = $0 }
                ))
                .font(AppTheme.typography.textStyle(.subheadline, weight: .medium))
                .foregroundStyle(AppTheme.colors.title)
                .padding(.horizontal, AppTheme.spacing.md)
                .padding(.vertical, AppTheme.spacing.md)
                .background(
                    RoundedRectangle(cornerRadius: AppTheme.radius.lg, style: .continuous)
                        .fill(AppTheme.colors.backgroundSoft.opacity(0.92))
                )
            }

            HStack {
                Spacer()
                Button("保存") {
                    HomeInteractionFeedback.selection()
                    onSave(messages)
                    messages = NotificationSettings.normalizedQuickReplyMessages(messages)
                }
                .font(AppTheme.typography.sized(14, weight: .semibold))
                .foregroundStyle(AppTheme.colors.selectionTint)
            }
            .padding(.top, AppTheme.spacing.xs)
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

#if DEBUG
#Preview("Profile") {
    NavigationStack {
        ProfileView(viewModel: AppContext.makeBootstrappedContext().profileViewModel)
    }
}
#endif

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
            VStack(spacing: AppTheme.spacing.xs) {
                Divider()
                    .overlay(AppTheme.colors.hairline)
                    .padding(.bottom, AppTheme.spacing.xxs)

                content
            }
            .padding(.top, AppTheme.spacing.sm)
        } label: {
            HStack(alignment: .center, spacing: AppTheme.spacing.md) {
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
                withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) {
                    configuration.isExpanded.toggle()
                }
            } label: {
                HStack(alignment: .center, spacing: AppTheme.spacing.md) {
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
            HStack(spacing: AppTheme.spacing.md) {
                Text(title)
                    .font(AppTheme.typography.textStyle(.subheadline, weight: .medium))
                    .foregroundStyle(isSelected ? AppTheme.colors.selectionTint : AppTheme.colors.title)

                Spacer()

                if isSelected {
                    Image(systemName: "checkmark")
                        .font(AppTheme.typography.sized(13, weight: .bold))
                        .foregroundStyle(AppTheme.colors.selectionTint)
                }
            }
            .padding(.horizontal, AppTheme.spacing.md)
            .padding(.vertical, AppTheme.spacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: AppTheme.radius.lg, style: .continuous)
                    .fill(isSelected ? AppTheme.colors.selectionTint.opacity(0.08) : .clear)
            )
        }
        .buttonStyle(.plain)
    }
}
