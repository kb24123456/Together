import SwiftUI

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

                    NavigationLink(value: ProfileRoute.editProfile) {
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

                    executionPreferencesSection
                    historyAndReminderSection
                    systemAndCollaborationSection
                }
                .padding(.horizontal, AppTheme.spacing.xl)
                .padding(.top, AppTheme.spacing.md)
                .padding(.bottom, AppTheme.spacing.xxl)
            }
            .coordinateSpace(name: ProfileScrollOffsetKey.coordinateSpaceName)
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
            case .completedHistory:
                CompletedHistoryView(viewModel: viewModel.makeCompletedHistoryViewModel())
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
                        onCustom: { viewModel.presentCustomDurationSheet(.taskUrgency) }
                    )
                }
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
                    onCustom: { viewModel.presentCustomDurationSheet(.defaultSnooze) }
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
            }
        }
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

            if viewModel.notificationAuthorization == .authorized {
                ProfileSettingsRow(
                    title: "提醒权限",
                    value: viewModel.notificationSummary
                )
            } else {
                Button {
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
        }
    }

    private func expandableSelectionRow<Content: View>(
        title: String,
        value: String,
        setting: ProfileExpandedSetting,
        @ViewBuilder content: () -> Content
    ) -> some View {
        ProfileExpandableSettingRow(
            title: title,
            value: value,
            isExpanded: viewModel.expandedSetting == setting,
            onToggle: { viewModel.toggleExpandedSetting(setting) },
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

private struct ProfileExpandableSettingRow<Content: View>: View {
    let title: String
    let value: String
    let isExpanded: Bool
    let onToggle: () -> Void
    @ViewBuilder let content: Content

    init(
        title: String,
        value: String,
        isExpanded: Bool,
        onToggle: @escaping () -> Void,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.value = value
        self.isExpanded = isExpanded
        self.onToggle = onToggle
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button(action: onToggle) {
                ProfileSettingsRow(
                    title: title,
                    value: value,
                    showsChevron: true,
                    chevronSystemName: isExpanded ? "chevron.up" : "chevron.down"
                )
            }
            .buttonStyle(.plain)

            if isExpanded {
                VStack(spacing: 8) {
                    Divider()
                        .overlay(AppTheme.colors.outline.opacity(0.45))
                        .padding(.bottom, 2)

                    content
                }
                .transition(
                    .asymmetric(
                        insertion: .move(edge: .top).combined(with: .opacity),
                        removal: .opacity
                    )
                )
            }
        }
        .animation(.easeOut(duration: 0.18), value: isExpanded)
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
                        .foregroundStyle(AppTheme.colors.accent)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(
                        isSelected
                        ? AppTheme.colors.accent.opacity(0.12)
                        : AppTheme.colors.backgroundSoft.opacity(0.92)
                    )
            )
        }
        .buttonStyle(.plain)
    }
}
