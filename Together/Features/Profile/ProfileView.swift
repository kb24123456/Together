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
}
