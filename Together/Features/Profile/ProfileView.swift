import SwiftUI

struct ProfileView: View {
    @Bindable var viewModel: ProfileViewModel
    @State private var topChromeProgress: CGFloat = 0

    var body: some View {
        GeometryReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: AppTheme.spacing.lg) {
                    ProfileScrollOffsetProbe()

                    heroSection
                    historySection
                    preferencesSection
                    systemSection
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
                .fill(AppTheme.colors.accentSoft.opacity(0.85))
                .frame(width: 220, height: 220)
                .blur(radius: 24)
                .offset(x: 88, y: -96)
        }
        .overlay(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 56, style: .continuous)
                .fill(AppTheme.colors.secondaryAccent.opacity(0.12))
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

    private var heroSection: some View {
        VStack(alignment: .leading, spacing: AppTheme.spacing.lg) {
            HStack(alignment: .top, spacing: AppTheme.spacing.md) {
                avatarSettingCard

                VStack(alignment: .leading, spacing: 12) {
                    Text(viewModel.currentUser?.displayName ?? "未加载用户")
                        .font(AppTheme.typography.sized(30, weight: .bold))
                        .foregroundStyle(AppTheme.colors.title)

                    Text(viewModel.currentSpace?.displayName ?? "未加载工作空间")
                        .font(AppTheme.typography.textStyle(.headline, weight: .semibold))
                        .foregroundStyle(AppTheme.colors.body.opacity(0.86))

                    StatusBadge(title: viewModel.bindingState.description, tint: AppTheme.colors.accent)

                    Text("把资料、提醒偏好与历史沉淀收在一个更安静的空间里，不打断 Today 的执行节奏。")
                        .font(AppTheme.typography.textStyle(.subheadline))
                        .foregroundStyle(AppTheme.colors.body.opacity(0.76))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            HStack(spacing: 12) {
                profileMetric(
                    title: "提醒状态",
                    value: viewModel.notificationSummary,
                    tint: notificationTint
                )
                profileMetric(
                    title: "历史任务",
                    value: viewModel.completedTaskAutoArchiveEnabled ? "\(viewModel.completedTaskAutoArchiveDays) 天归档" : "手动管理",
                    tint: AppTheme.colors.accent
                )
            }
        }
        .padding(AppTheme.spacing.xl)
        .background(
            RoundedRectangle(cornerRadius: 34, style: .continuous)
                .fill(AppTheme.colors.surface.opacity(0.96))
        )
        .overlay {
            RoundedRectangle(cornerRadius: 34, style: .continuous)
                .stroke(AppTheme.colors.outline.opacity(0.7))
        }
        .shadow(color: AppTheme.colors.shadow.opacity(1.2), radius: 24, y: 14)
    }

    private var avatarSettingCard: some View {
        VStack(alignment: .center, spacing: 12) {
            Circle()
                .fill(
                    LinearGradient(
                        colors: [
                            AppTheme.colors.avatarWarm,
                            AppTheme.colors.surface
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay {
                    Image(systemName: viewModel.currentUser?.avatarSystemName ?? "person.crop.circle.fill")
                        .font(AppTheme.typography.sized(44, weight: .semibold))
                        .foregroundStyle(AppTheme.colors.title.opacity(0.86))
                }
                .frame(width: 112, height: 112)

            VStack(spacing: 4) {
                Text("头像设置区")
                    .font(AppTheme.typography.textStyle(.headline, weight: .semibold))
                    .foregroundStyle(AppTheme.colors.title)
                Text("预留更换头像与资料编辑入口")
                    .font(AppTheme.typography.textStyle(.caption1))
                    .foregroundStyle(AppTheme.colors.body.opacity(0.66))
                    .multilineTextAlignment(.center)
            }

            Button("即将支持", systemImage: "camera.circle") {}
                .buttonStyle(.bordered)
                .tint(AppTheme.colors.accent)
                .disabled(true)
        }
        .frame(maxWidth: 160)
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(AppTheme.colors.surfaceElevated)
        )
    }

    private func profileMetric(title: String, value: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(AppTheme.typography.textStyle(.caption1, weight: .semibold))
                .foregroundStyle(AppTheme.colors.body.opacity(0.62))
            Text(value)
                .font(AppTheme.typography.textStyle(.headline, weight: .semibold))
                .foregroundStyle(AppTheme.colors.title)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(tint.opacity(0.10))
        )
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(tint.opacity(0.18))
        }
    }

    private var historySection: some View {
        VStack(alignment: .leading, spacing: AppTheme.spacing.md) {
            Text("历史沉淀")
                .font(AppTheme.typography.textStyle(.headline, weight: .semibold))
                .foregroundStyle(AppTheme.colors.title)

            NavigationLink(value: ProfileRoute.completedHistory) {
                HStack(alignment: .center, spacing: AppTheme.spacing.md) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("查看历史任务")
                            .font(AppTheme.typography.sized(22, weight: .bold))
                            .foregroundStyle(AppTheme.colors.title)

                        Text("已完成任务会在这里持续沉淀，Today 只保留当前仍需处理的任务。")
                            .font(AppTheme.typography.textStyle(.subheadline))
                            .foregroundStyle(AppTheme.colors.body.opacity(0.74))
                            .fixedSize(horizontal: false, vertical: true)

                        HStack(spacing: 8) {
                            historyChip("仅收纳已完成", tint: AppTheme.colors.accent)
                            historyChip(
                                viewModel.completedTaskAutoArchiveEnabled
                                ? "\(viewModel.completedTaskAutoArchiveDays) 天自动归档"
                                : "手动归档",
                                tint: AppTheme.colors.coral
                            )
                        }
                    }

                    Spacer(minLength: 0)

                    ZStack {
                        RoundedRectangle(cornerRadius: 24, style: .continuous)
                            .fill(AppTheme.colors.surface.opacity(0.85))
                            .frame(width: 88, height: 120)

                        VStack(spacing: 10) {
                            Image(systemName: "tray.full")
                                .font(AppTheme.typography.sized(28, weight: .semibold))
                            Image(systemName: "arrow.right")
                                .font(AppTheme.typography.sized(14, weight: .bold))
                        }
                        .foregroundStyle(AppTheme.colors.title.opacity(0.76))
                    }
                }
                .padding(AppTheme.spacing.xl)
                .background(
                    LinearGradient(
                        colors: [
                            AppTheme.colors.accentSoft,
                            AppTheme.colors.surface
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .clipShape(.rect(cornerRadius: 30))
                .overlay {
                    RoundedRectangle(cornerRadius: 30, style: .continuous)
                        .stroke(AppTheme.colors.outline.opacity(0.65))
                }
            }
            .buttonStyle(.plain)
        }
    }

    private func historyChip(_ title: String, tint: Color) -> some View {
        Text(title)
            .font(AppTheme.typography.sized(12, weight: .semibold))
            .foregroundStyle(tint)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(
                Capsule(style: .continuous)
                    .fill(tint.opacity(0.10))
            )
    }

    private var preferencesSection: some View {
        VStack(alignment: .leading, spacing: AppTheme.spacing.md) {
            Text("执行偏好")
                .font(AppTheme.typography.textStyle(.headline, weight: .semibold))
                .foregroundStyle(AppTheme.colors.title)

            VStack(alignment: .leading, spacing: AppTheme.spacing.md) {
                preferencePanel(
                    title: "临期任务提醒",
                    subtitle: "Today 会在距离截止前这段时间内，把任务时间标红并启用呼吸跳动效果。"
                ) {
                    Picker(
                        "临期窗口",
                        selection: Binding(
                            get: { viewModel.taskUrgencyWindowMinutes },
                            set: { viewModel.updateTaskUrgencyWindow(minutes: $0) }
                        )
                    ) {
                        ForEach(viewModel.taskUrgencyOptions, id: \.self) { minutes in
                            Text(minutesLabel(minutes)).tag(minutes)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                preferencePanel(
                    title: "默认推迟时间",
                    subtitle: "首页任务左滑点按推迟图标后，会直接按这个时间执行。"
                ) {
                    HStack(spacing: 12) {
                        Text("默认值")
                            .foregroundStyle(AppTheme.colors.body)

                        Spacer(minLength: 0)

                        Picker(
                            "默认推迟时间",
                            selection: Binding(
                                get: { viewModel.defaultSnoozeMinutes },
                                set: { viewModel.updateDefaultSnoozeMinutes($0) }
                            )
                        ) {
                            ForEach(viewModel.snoozeMinuteOptions, id: \.self) { option in
                                Text(relativeTimeLabel(minutes: option)).tag(option)
                            }
                        }
                        .pickerStyle(.menu)
                    }

                    Text("分钟粒度固定为 5 分钟。")
                        .font(AppTheme.typography.textStyle(.caption1))
                        .foregroundStyle(AppTheme.colors.body.opacity(0.62))
                }

                preferencePanel(
                    title: "已完成自动归档",
                    subtitle: "关闭后，历史完成任务会持续保留在活跃数据中，可能降低列表清晰度、搜索准确性与长期性能。"
                ) {
                    Toggle(
                        "自动归档已完成任务",
                        isOn: Binding(
                            get: { viewModel.completedTaskAutoArchiveEnabled },
                            set: { viewModel.updateCompletedTaskAutoArchiveEnabled($0) }
                        )
                    )
                    .tint(AppTheme.colors.accent)

                    HStack(spacing: 12) {
                        Text("归档时间")
                            .foregroundStyle(AppTheme.colors.body)

                        Spacer(minLength: 0)

                        Picker(
                            "归档时间",
                            selection: Binding(
                                get: { viewModel.completedTaskAutoArchiveDays },
                                set: { viewModel.updateCompletedTaskAutoArchiveDays($0) }
                            )
                        ) {
                            ForEach(viewModel.completedTaskAutoArchiveOptions, id: \.self) { option in
                                Text("\(option)天").tag(option)
                            }
                        }
                        .pickerStyle(.menu)
                        .disabled(viewModel.completedTaskAutoArchiveEnabled == false)
                        .opacity(viewModel.completedTaskAutoArchiveEnabled ? 1 : 0.46)
                    }
                }
            }
        }
    }

    private func preferencePanel<Content: View>(
        title: String,
        subtitle: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title)
                .font(AppTheme.typography.textStyle(.headline, weight: .semibold))
                .foregroundStyle(AppTheme.colors.title)

            Text(subtitle)
                .font(AppTheme.typography.textStyle(.caption1))
                .foregroundStyle(AppTheme.colors.body.opacity(0.68))
                .fixedSize(horizontal: false, vertical: true)

            content()
        }
        .padding(AppTheme.spacing.lg)
        .background(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(AppTheme.colors.surface)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .stroke(AppTheme.colors.outline)
        }
    }

    private var systemSection: some View {
        VStack(alignment: .leading, spacing: AppTheme.spacing.md) {
            Text("系统状态")
                .font(AppTheme.typography.textStyle(.headline, weight: .semibold))
                .foregroundStyle(AppTheme.colors.title)

            VStack(alignment: .leading, spacing: AppTheme.spacing.md) {
                if viewModel.notificationAuthorization != .authorized {
                    Button("开启提醒", systemImage: "bell.badge") {
                        Task {
                            await viewModel.requestNotifications()
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(AppTheme.colors.accent)
                }

                HStack(spacing: 14) {
                    systemRow(
                        title: "提醒权限",
                        value: viewModel.notificationSummary,
                        systemImage: "bell.fill",
                        tint: notificationTint
                    )
                    systemRow(
                        title: "未来双人模式",
                        value: "入口保留在这里",
                        systemImage: "person.2.fill",
                        tint: AppTheme.colors.secondaryAccent
                    )
                }
            }
        }
    }

    private func systemRow(title: String, value: String, systemImage: String, tint: Color) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: systemImage)
                .font(AppTheme.typography.sized(16, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 34, height: 34)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(tint.opacity(0.12))
                )

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(AppTheme.typography.textStyle(.caption1, weight: .semibold))
                    .foregroundStyle(AppTheme.colors.body.opacity(0.68))
                Text(value)
                    .font(AppTheme.typography.textStyle(.subheadline, weight: .semibold))
                    .foregroundStyle(AppTheme.colors.title)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(AppTheme.spacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(AppTheme.colors.surface)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(AppTheme.colors.outline)
        }
    }

    private var notificationTint: Color {
        switch viewModel.notificationAuthorization {
        case .authorized:
            return AppTheme.colors.accent
        case .denied:
            return AppTheme.colors.coral
        case .notDetermined:
            return AppTheme.colors.sun
        }
    }

    private func minutesLabel(_ minutes: Int) -> String {
        if minutes >= 60 {
            return "\(minutes / 60)小时"
        }
        return "\(minutes)分钟"
    }

    private func relativeTimeLabel(minutes: Int) -> String {
        if minutes >= 60, minutes.isMultiple(of: 60) {
            return "\(minutes / 60)小时后"
        }
        return "\(minutes)分钟后"
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
