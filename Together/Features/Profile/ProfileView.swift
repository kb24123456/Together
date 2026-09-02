import SwiftUI
import UIKit

struct ProfileView: View {
    @Environment(AppContext.self) private var appContext
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.openURL) private var openURL
    @Bindable var viewModel: ProfileViewModel
    @State private var isSyncSheetPresented = false
    @Namespace private var profileTransition

    var body: some View {
        @Bindable var appearanceManager = appContext.appearanceManager
        @Bindable var ambientBackgroundSettings = appContext.ambientBackgroundSettings

        ScrollView {
            VStack(alignment: .leading, spacing: AppTheme.hierarchy.spacing.section) {
                NavigationLink(value: ProfileRoute.editProfile) {
                    ProfileCompactIdentityRow(
                        name: appContext.sessionStore.currentUser?.displayName ?? viewModel.profileCardPrimaryName,
                        avatar: ProfileCardAvatar(
                            displayName: appContext.sessionStore.currentUser?.displayName ?? viewModel.profileCardPrimaryName,
                            avatarAsset: appContext.sessionStore.currentUser?.avatarAsset ?? .system("person.crop.circle.fill"),
                            overrideImage: nil
                        )
                    )
                    .id(appContext.sessionStore.userProfileRevision)
                    .matchedTransitionSource(id: ProfileTransitionSource.profileCard, in: profileTransition)
                }
                .buttonStyle(.plain)
                .padding(.bottom, AppTheme.hierarchy.spacing.component)

                ProfileFlatSection(title: "显示") {
                    ProfileFlatOptionRow(
                        title: "外观",
                        value: appearanceManager.mode.title,
                        systemImage: "circle.lefthalf.filled"
                    ) {
                        Picker("外观", selection: $appearanceManager.mode) {
                            ForEach(AppearanceMode.allCases, id: \.self) { mode in
                                Text(mode.title)
                                    .tag(mode)
                            }
                        }
                    }

                    ProfileFlatToggleRow(
                        title: "动态背景",
                        systemImage: "sparkles"
                    ) {
                        Toggle("动态背景", isOn: $ambientBackgroundSettings.isEnabled)
                            .labelsHidden()
                    }
                }

                ProfileFlatSection(title: "提醒") {
                    ProfileFlatToggleRow(
                        title: "任务提醒",
                        systemImage: "bell"
                    ) {
                        Toggle("任务提醒", isOn: Binding(
                            get: { viewModel.taskReminderEnabled },
                            set: { viewModel.updateTaskReminderEnabled($0) }
                        ))
                        .labelsHidden()
                    }

                    if viewModel.taskReminderEnabled {
                        VStack(spacing: 0) {
                            ProfileFlatOptionRow(
                                title: "提醒方式",
                                value: viewModel.reminderDelivery == .alarm ? "Apple 闹钟" : "普通通知",
                                systemImage: viewModel.reminderDelivery == .alarm ? "alarm" : "bell"
                            ) {
                                Picker(
                                    "提醒方式",
                                    selection: Binding(
                                        get: { viewModel.reminderDelivery },
                                        set: { viewModel.updateReminderDelivery($0) }
                                    )
                                ) {
                                    Text("Apple 闹钟").tag(PeriodicReminderDelivery.alarm)
                                    Text("普通通知").tag(PeriodicReminderDelivery.notification)
                                }
                            }

                            if viewModel.reminderDelivery == .alarm,
                               viewModel.alarmAuthorization == .notDetermined {
                                ProfileInlineNotice(
                                    message: "允许 Apple 闹钟后，定时提醒可在静音或专注模式下响铃。",
                                    actionTitle: "允许",
                                    action: viewModel.requestAppleAlarmAuthorization
                                )
                            } else if viewModel.reminderDelivery == .alarm,
                                      viewModel.alarmAuthorization == .denied {
                                ProfileInlineNotice(
                                    message: "Apple 闹钟权限已关闭，将自动改用普通通知。",
                                    actionTitle: "前往设置",
                                    action: openAlarmSettings
                                )
                            }

                            ProfileFlatOptionRow(
                                title: "临近窗口",
                                value: viewModel.taskUrgencyLabel(minutes: viewModel.taskUrgencyWindowMinutes),
                                systemImage: "timer"
                            ) {
                                ForEach(viewModel.taskUrgencyPickerOptions, id: \.self) { minutes in
                                    Button {
                                        HomeInteractionFeedback.selection()
                                        viewModel.updateTaskUrgencyWindow(minutes: minutes)
                                    } label: {
                                        if viewModel.taskUrgencyWindowMinutes == minutes {
                                            Label(viewModel.taskUrgencyLabel(minutes: minutes), systemImage: "checkmark")
                                        } else {
                                            Text(viewModel.taskUrgencyLabel(minutes: minutes))
                                        }
                                    }
                                }
                            }

                            ProfileFlatToggleRow(
                                title: "每日摘要",
                                systemImage: "clock"
                            ) {
                                HStack(spacing: AppTheme.hierarchy.spacing.related) {
                                    Text("09:00 · 18:00")
                                        .font(AppTheme.typography.hierarchy(.supporting, weight: .medium))
                                        .foregroundStyle(AppTheme.colors.body.opacity(0.58))

                                    Toggle("每日摘要", isOn: Binding(
                                        get: { viewModel.dailySummaryEnabled },
                                        set: { viewModel.updateDailySummaryEnabled($0) }
                                    ))
                                    .labelsHidden()
                                    .accessibilityHint("每天早上九点发送今日待完成数量，晚上六点发送剩余未完成数量")
                                }
                            }

                            if viewModel.notificationAuthorization == .denied {
                                ProfileInlineNotice(
                                    message: "系统通知已关闭，部分任务提醒可能无法送达。",
                                    actionTitle: "前往设置",
                                    action: openAppSettings
                                )
                            }
                        }
                        .transition(conditionalSettingsTransition)
                    }
                }

                ProfileFlatSection(title: "整理") {

                    NavigationLink(value: ProfileRoute.planningReview) {
                        ProfileFlatValueRow(
                            title: "计划复盘",
                            value: planningReviewSubtitle,
                            systemImage: "chart.bar.doc.horizontal"
                        )
                    }
                    .buttonStyle(.plain)

                    ProfileFlatToggleRow(
                        title: "已完成自动归档",
                        systemImage: "archivebox"
                    ) {
                        Toggle("已完成自动归档", isOn: Binding(
                            get: { viewModel.completedTaskAutoArchiveEnabled },
                            set: { viewModel.updateCompletedTaskAutoArchiveEnabled($0) }
                        ))
                        .labelsHidden()
                    }

                    if viewModel.completedTaskAutoArchiveEnabled {
                        ProfileFlatOptionRow(
                            title: "归档时间",
                            value: "\(viewModel.completedTaskAutoArchiveDays) 天后",
                            systemImage: "clock.arrow.circlepath"
                        ) {
                            ForEach(viewModel.completedTaskAutoArchiveOptions, id: \.self) { days in
                                Button {
                                    HomeInteractionFeedback.selection()
                                    viewModel.updateCompletedTaskAutoArchiveDays(days)
                                } label: {
                                    if viewModel.completedTaskAutoArchiveDays == days {
                                        Label("\(days) 天后", systemImage: "checkmark")
                                    } else {
                                        Text("\(days) 天后")
                                    }
                                }
                            }
                        }
                        .transition(conditionalSettingsTransition)
                    }
                }

                ProfileFlatSection(title: "隐私与数据") {
                    ProfileFlatToggleRow(
                        title: "应用锁定（\(viewModel.biometricTypeName)）",
                        systemImage: "lock"
                    ) {
                        Toggle("应用锁定", isOn: Binding(
                            get: { viewModel.appLockEnabled },
                            set: { viewModel.updateAppLockEnabled($0) }
                        ))
                        .labelsHidden()
                    }

                    Button {
                        HomeInteractionFeedback.selection()
                        isSyncSheetPresented = true
                    } label: {
                        ProfileFlatValueRow(
                            title: "iCloud 同步",
                            value: viewModel.iCloudStatusSummary,
                            systemImage: "icloud"
                        )
                    }
                    .buttonStyle(.plain)

                    NavigationLink(value: ProfileRoute.accountDeletion) {
                        ProfileFlatValueRow(
                            title: "删除所有数据",
                            value: "",
                            systemImage: "trash",
                            titleColor: AppTheme.colors.danger
                        )
                    }
                    .buttonStyle(.plain)
                }

                ProfileFlatSection(title: "关于") {
                    NavigationLink(value: ProfileRoute.about) {
                        ProfileFlatValueRow(
                            title: "Together",
                            value: "版本 \(viewModel.appVersionString)",
                            systemImage: "info.circle"
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, AppTheme.spacing.md)
            .padding(.top, AppTheme.spacing.md)
            .padding(.bottom, AppTheme.spacing.xxl * 2)
        }
        .applySoftScrollEdgeTransition()
        .background(AppTheme.colors.background.ignoresSafeArea())
        .navigationTitle("我")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink(value: ProfileRoute.completedHistory) {
                    ToolbarTextActionLabel(title: "已完成")
                }
                .accessibilityHint("查看已完成任务")
            }
        }
        .navigationDestination(for: ProfileRoute.self) { route in
            switch route {
            case .editProfile:
                EditProfileView(
                    viewModel: viewModel.makeEditProfileViewModel(user: appContext.sessionStore.currentUser)
                )
                .navigationTransition(.zoom(sourceID: ProfileTransitionSource.profileCard, in: profileTransition))
            case .completedHistory:
                CompletedHistoryView(viewModel: viewModel.makeCompletedHistoryViewModel(initialFilter: .all))
            case .planningReview:
                PlanningReviewView(
                    loadReview: viewModel.planningReview,
                    loadTaskReview: viewModel.taskLifecycleReview
                )
            case .accountDeletion:
                ProfileAccountDeletionView(viewModel: viewModel)
            case .about:
                ProfileAboutView(appVersion: viewModel.appVersionString)
            }
        }
        .task {
            await viewModel.load()
        }
        .sheet(isPresented: $isSyncSheetPresented) {
            NavigationStack {
                ProfileSyncRecoveryView(viewModel: viewModel)
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button("完成") {
                                HomeInteractionFeedback.selection()
                                isSyncSheetPresented = false
                            }
                        }
                    }
            }
            .presentationSizing(.fitted)
        }
        .animation(
            reduceMotion ? .easeOut(duration: 0.16) : .smooth(duration: 0.28),
            value: viewModel.taskReminderEnabled
        )
        .animation(
            reduceMotion ? .easeOut(duration: 0.16) : .smooth(duration: 0.28),
            value: viewModel.completedTaskAutoArchiveEnabled
        )
    }

    private var conditionalSettingsTransition: AnyTransition {
        reduceMotion
            ? .opacity
            : .opacity.combined(with: .move(edge: .top))
    }

    private func openAppSettings() {
        guard let url = URL(string: UIApplication.openNotificationSettingsURLString) else { return }
        openURL(url)
    }

    private func openAlarmSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        openURL(url)
    }

    private var planningReviewSubtitle: String {
        if Calendar.current.component(.weekday, from: .now) == 6 {
            return "本周可回顾"
        }
        return "本周 \(viewModel.weeklyPlanningReviewCompletionCount) 项"
    }
}

private enum ProfileTransitionSource {
    static let profileCard = "profile-card"
}

private struct ProfileCompactIdentityRow: View {
    let name: String
    let avatar: ProfileCardAvatar

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        HStack(spacing: AppTheme.hierarchy.spacing.component) {
            UserAvatarView(
                avatarAsset: avatar.avatarAsset,
                displayName: avatar.displayName,
                size: 76,
                fillColor: AppTheme.colors.avatarWarm,
                symbolColor: AppTheme.colors.title.opacity(0.82),
                symbolFont: AppTheme.typography.sized(28, weight: .semibold),
                overrideImage: avatar.overrideImage
            )

            Text(name)
                .font(AppTheme.typography.hierarchy(.title, weight: .medium))
                .foregroundStyle(AppTheme.colors.title)
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 1)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: AppTheme.hierarchy.spacing.component)

            Image(systemName: "chevron.right")
                .font(AppTheme.typography.sized(13, weight: .bold))
                .foregroundStyle(AppTheme.colors.body.opacity(0.36))
        }
        .padding(.vertical, AppTheme.hierarchy.spacing.component)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(name)
        .accessibilityHint("编辑个人资料")
    }
}

#if DEBUG
#Preview("Profile") {
    NavigationStack {
        ProfileView(viewModel: AppContext.makeBootstrappedContext().profileViewModel)
    }
}
#endif
