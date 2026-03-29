import SwiftUI

struct ProfileView: View {
    @Bindable var viewModel: ProfileViewModel
    @State private var topChromeProgress: CGFloat = 0

    var body: some View {
        GeometryReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: AppTheme.spacing.lg) {
                    ProfileScrollOffsetProbe()

                    ProfileUserCard(
                        displayName: viewModel.currentUser?.displayName ?? "未加载用户",
                        spaceName: viewModel.spaceSummary,
                        bindingTitle: viewModel.bindingState.description,
                        avatarSystemName: viewModel.currentUser?.avatarSystemName ?? "person.crop.circle.fill"
                    )

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
            case .completedHistory:
                CompletedHistoryView(viewModel: viewModel.makeCompletedHistoryViewModel())
            case .notificationSettings, .futureCollaboration:
                EmptyView()
            }
        }
        .task {
            await viewModel.load()
        }
        .onPreferenceChange(ProfileScrollOffsetKey.self) { offset in
            let progress = min(max(-offset / 56, 0), 1)
            topChromeProgress = progress
        }
        .animation(.easeOut(duration: 0.18), value: topChromeProgress)
    }

    private var backgroundView: some View {
        LinearGradient(
            colors: [
                AppTheme.colors.homeBackgroundSoft,
                AppTheme.colors.backgroundSoft,
                AppTheme.colors.background
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        .overlay(alignment: .topTrailing) {
            Circle()
                .fill(AppTheme.colors.accentSoft.opacity(0.78))
                .frame(width: 220, height: 220)
                .blur(radius: 24)
                .offset(x: 88, y: -96)
        }
        .overlay(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 56, style: .continuous)
                .fill(AppTheme.colors.secondaryAccent.opacity(0.10))
                .frame(width: 180, height: 180)
                .rotationEffect(.degrees(18))
                .offset(x: -54, y: -70)
                .blur(radius: 8)
        }
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
                value: viewModel.taskUrgencySummary
            ) {
                Picker(
                    "临期窗口",
                    selection: Binding(
                        get: { viewModel.taskUrgencyWindowMinutes },
                        set: { viewModel.updateTaskUrgencyWindow(minutes: $0) }
                    )
                ) {
                    ForEach(viewModel.taskUrgencyOptions, id: \.self) { minutes in
                        Text(viewModel.taskUrgencyLabel(minutes: minutes)).tag(minutes)
                    }
                }
            }

            ProfileSettingsRow(
                title: "默认推迟时间",
                value: viewModel.defaultSnoozeSummary
            ) {
                Picker(
                    "默认推迟时间",
                    selection: Binding(
                        get: { viewModel.defaultSnoozeMinutes },
                        set: { viewModel.updateDefaultSnoozeMinutes($0) }
                    )
                ) {
                    ForEach(viewModel.snoozeMinuteOptions, id: \.self) { option in
                        Text(viewModel.relativeTimeLabel(minutes: option)).tag(option)
                    }
                }
            }

            ProfileSettingsRow(
                title: "已完成自动归档",
                isOn: Binding(
                    get: { viewModel.completedTaskAutoArchiveEnabled },
                    set: { viewModel.updateCompletedTaskAutoArchiveEnabled($0) }
                )
            )

            ProfileSettingsRow(
                title: "归档时间",
                value: viewModel.completedArchiveSummary,
                isEnabled: viewModel.completedTaskAutoArchiveEnabled
            ) {
                Picker(
                    "归档时间",
                    selection: Binding(
                        get: { viewModel.completedTaskAutoArchiveDays },
                        set: { viewModel.updateCompletedTaskAutoArchiveDays($0) }
                    )
                ) {
                    ForEach(viewModel.completedTaskAutoArchiveOptions, id: \.self) { option in
                        Text("\(option)天后").tag(option)
                    }
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
        ProfileView(viewModel: AppContext.bootstrap().profileViewModel)
    }
}
