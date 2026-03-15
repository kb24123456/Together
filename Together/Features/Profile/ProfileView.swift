import SwiftUI

struct ProfileView: View {
    @Bindable var viewModel: ProfileViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppTheme.spacing.lg) {
                if let currentUser = viewModel.currentUser {
                    CardSection(title: currentUser.displayName, subtitle: "当前以单人 Todo 模式运行") {
                        VStack(alignment: .leading, spacing: AppTheme.spacing.sm) {
                            Text(viewModel.currentSpace?.displayName ?? "未加载工作空间")
                                .font(AppTheme.typography.textStyle(.headline, weight: .semibold))
                                .foregroundStyle(AppTheme.colors.title)
                            StatusBadge(title: viewModel.bindingState.description, tint: AppTheme.colors.accent)
                        }
                    }
                }

                CardSection(title: "提醒与偏好", subtitle: "通知、默认视图和动效偏好将在这里统一管理") {
                    VStack(alignment: .leading, spacing: AppTheme.spacing.sm) {
                        Text(viewModel.notificationSummary)
                            .foregroundStyle(AppTheme.colors.body)

                        if viewModel.notificationAuthorization != .authorized {
                            Button("开启提醒") {
                                Task {
                                    await viewModel.requestNotifications()
                                }
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(AppTheme.colors.accent)
                        }

                        Divider()
                            .padding(.vertical, 4)

                        VStack(alignment: .leading, spacing: 10) {
                            Text("临期任务提醒规则")
                                .font(AppTheme.typography.textStyle(.headline, weight: .semibold))
                                .foregroundStyle(AppTheme.colors.title)

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

                            Text("在距离截止前这段时间内，Today 列表会把任务时间标红，并启用呼吸跳动效果。")
                                .font(AppTheme.typography.textStyle(.caption1))
                                .foregroundStyle(AppTheme.colors.body.opacity(0.7))
                        }

                        Divider()
                            .padding(.vertical, 4)

                        VStack(alignment: .leading, spacing: 10) {
                            Text("时间快捷预设")
                                .font(AppTheme.typography.textStyle(.headline, weight: .semibold))
                                .foregroundStyle(AppTheme.colors.title)

                            ForEach(Array(viewModel.quickTimePresetMinutes.enumerated()), id: \.offset) { index, minutes in
                                HStack(spacing: 12) {
                                    Text("预设\(index + 1)")
                                        .foregroundStyle(AppTheme.colors.body)

                                    Spacer(minLength: 0)

                                    Picker(
                                        "预设\(index + 1)",
                                        selection: Binding(
                                            get: { viewModel.quickTimePresetMinutes[index] },
                                            set: { viewModel.updateQuickTimePreset(minutes: $0, at: index) }
                                        )
                                    ) {
                                        ForEach(viewModel.quickTimePresetOptions, id: \.self) { option in
                                            Text(relativeTimeLabel(minutes: option)).tag(option)
                                        }
                                    }
                                    .pickerStyle(.menu)
                                }
                            }

                            Text("添加页时间二级菜单会优先显示这 3 个快捷时间，分钟粒度固定为 5 分钟。")
                                .font(AppTheme.typography.textStyle(.caption1))
                                .foregroundStyle(AppTheme.colors.body.opacity(0.7))
                        }
                    }
                }

                EmptyStateCard(
                    title: "未来双人模式",
                    message: "当前先把单人 Todo 主链路做顺。双人协作入口会保留在这里，不再反向主导首版结构。"
                )
            }
            .padding(AppTheme.spacing.xl)
        }
        .background(AppTheme.colors.background.ignoresSafeArea())
        .navigationTitle("我")
        .toolbar(.visible, for: .navigationBar)
        .font(AppTheme.typography.body)
        .task {
            await viewModel.load()
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
