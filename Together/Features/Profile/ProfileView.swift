import SwiftUI
import UIKit

struct ProfileView: View {
    @Environment(AppContext.self) private var appContext
    @Bindable var viewModel: ProfileViewModel
    @State private var topChromeProgress: CGFloat = 0
    @Namespace private var profileTransition

    var body: some View {
        let currentUser = appContext.sessionStore.currentUser

        GeometryReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: AppTheme.spacing.lg) {
                    ProfileScrollOffsetProbe()

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

                    appearanceSection
                    executionPreferencesSection
                    historyAndReminderSection
                    securitySection
                    systemAndCollaborationSection
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
            // 只在可以接受邀请的状态下自动处理
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
                // 配对成功反馈
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
    }

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

    private var appearanceSection: some View {
        ProfileSettingsGroupCard(title: "外观") {
            HStack(spacing: 0) {
                ForEach(AppearanceMode.allCases, id: \.self) { mode in
                    let isSelected = appContext.appearanceManager.mode == mode

                    Button {
                        HomeInteractionFeedback.selection()
                        withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) {
                            appContext.appearanceManager.mode = mode
                        }
                    } label: {
                        VStack(spacing: 8) {
                            Image(systemName: mode.icon)
                                .font(AppTheme.typography.sized(18, weight: .semibold))
                                .foregroundStyle(isSelected ? AppTheme.colors.title : AppTheme.colors.textTertiary)

                            Text(mode.title)
                                .font(AppTheme.typography.sized(13, weight: .semibold))
                                .foregroundStyle(isSelected ? AppTheme.colors.title : AppTheme.colors.body)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(isSelected ? AppTheme.colors.background : .clear)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .stroke(isSelected ? AppTheme.colors.outline : .clear, lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 4)
        }
    }

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

    private var profileListAnimation: Animation {
        .spring(response: 0.34, dampingFraction: 0.86)
    }

    private var profileListRowTransition: AnyTransition {
        .asymmetric(
            insertion: .move(edge: .top).combined(with: .opacity).combined(with: .scale(scale: 0.985, anchor: .top)),
            removal: .move(edge: .top).combined(with: .opacity)
        )
    }

    private var historyAndReminderSection: some View {
        ProfileSettingsGroupCard(title: "历史与提醒") {
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

            if viewModel.notificationAuthorization == .authorized {
                ProfileSettingsRow(
                    title: "提醒权限",
                    value: viewModel.notificationSummary
                )
            } else {
                Button {
                    HomeInteractionFeedback.selection()
                    Task {
                        await viewModel.requestNotifications()
                    }
                } label: {
                    ProfileSettingsRow(
                        title: "提醒权限",
                        value: "未开启",
                        showsChevron: true
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var securitySection: some View {
        ProfileSettingsGroupCard(title: "安全") {
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

    private var systemAndCollaborationSection: some View {
        ProfileSettingsGroupCard(title: "系统与协作") {
            ProfileSettingsRow(
                title: "当前工作空间",
                value: viewModel.spaceSummary
            )

            ProfileSettingsRow(
                title: "双人模式",
                value: viewModel.collaborationSummary
            )

            Text(viewModel.collaborationDetailText)
                .font(AppTheme.typography.sized(14, weight: .medium))
                .foregroundStyle(AppTheme.colors.body.opacity(0.72))
                .padding(.horizontal, 4)
                .padding(.top, 2)

            Text(viewModel.activeModeSummary)
                .font(AppTheme.typography.sized(13, weight: .semibold))
                .foregroundStyle(AppTheme.colors.textTertiary)
                .padding(.horizontal, 4)

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
                    .foregroundStyle(AppTheme.colors.title)

                Spacer()

                if isSelected {
                    Image(systemName: "checkmark")
                        .font(AppTheme.typography.sized(13, weight: .bold))
                        .foregroundStyle(AppTheme.colors.profileAccent)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(
                        isSelected
                        ? AppTheme.colors.profileAccentSoft
                        : AppTheme.colors.backgroundSoft.opacity(0.92)
                    )
            )
        }
        .buttonStyle(.plain)
    }
}
