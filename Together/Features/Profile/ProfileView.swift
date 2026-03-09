import SwiftUI

struct ProfileView: View {
    @Bindable var viewModel: ProfileViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppTheme.spacing.lg) {
                accountSection
                bindingSection
                reminderSection
                privacySection
                signOutSection
            }
            .padding(.horizontal, AppTheme.spacing.md)
            .padding(.top, AppTheme.spacing.md)
            .padding(.bottom, AppTheme.spacing.xl)
        }
        .background(AppTheme.colors.background.ignoresSafeArea())
        .navigationTitle("我")
        .task {
            await viewModel.load()
        }
    }

    private var accountSection: some View {
        CardSection(title: "账号信息") {
            if let user = viewModel.currentUser {
                HStack(spacing: AppTheme.spacing.md) {
                    Image(systemName: user.avatarSystemName ?? "person.crop.circle")
                        .font(.system(size: 36))
                        .foregroundStyle(AppTheme.colors.accent)

                    VStack(alignment: .leading, spacing: AppTheme.spacing.xs) {
                        Text(user.displayName)
                            .font(.headline)
                        Text("Sign in with Apple 已接入到 AuthService 协议层")
                            .font(.subheadline)
                            .foregroundStyle(AppTheme.colors.body)
                    }
                }
            } else {
                EmptyStateCard(title: "未登录", message: "当前为占位状态，后续接入真实 Apple 登录。")
            }
        }
    }

    private var bindingSection: some View {
        CardSection(title: "绑定状态") {
            VStack(alignment: .leading, spacing: AppTheme.spacing.sm) {
                StatusBadge(title: viewModel.bindingState.description, tint: AppTheme.colors.accent)
                if let pairSpace = viewModel.pairSpace, let partner = pairSpace.memberB {
                    Text("当前与 \(partner.nickname) 处于同一个双人空间")
                        .font(.subheadline)
                        .foregroundStyle(AppTheme.colors.body)
                } else {
                    Text("未绑定时只能体验示例、创建草稿，不能形成真实双人闭环。")
                        .font(.subheadline)
                        .foregroundStyle(AppTheme.colors.body)
                }

                Button("邀请另一半加入") {
                    Task {
                        await viewModel.createInvite()
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(AppTheme.colors.accent)
            }
        }
    }

    private var reminderSection: some View {
        CardSection(title: "提醒设置") {
            VStack(alignment: .leading, spacing: AppTheme.spacing.sm) {
                reminderRow(title: "新事项提醒", enabled: viewModel.currentUser?.preferences.newItemEnabled ?? false)
                reminderRow(title: "决策提醒", enabled: viewModel.currentUser?.preferences.decisionEnabled ?? false)
                reminderRow(title: "纪念日提醒", enabled: viewModel.currentUser?.preferences.anniversaryEnabled ?? false)
                reminderRow(title: "截止时间提醒", enabled: viewModel.currentUser?.preferences.deadlineEnabled ?? false)

                Text("系统授权：\(viewModel.notificationAuthorization.rawValue)")
                    .font(.caption)
                    .foregroundStyle(AppTheme.colors.body)

                Button("请求通知权限") {
                    Task {
                        await viewModel.requestNotifications()
                    }
                }
                .buttonStyle(.bordered)
            }
        }
    }

    private var privacySection: some View {
        CardSection(title: "数据与隐私") {
            Text("解绑后，原双人数据不可迁移给新的第三人；重新绑定必须从零开始。")
                .font(.subheadline)
                .foregroundStyle(AppTheme.colors.body)
        }
    }

    private var signOutSection: some View {
        Button("退出登录") {
            Task {
                await viewModel.signOut()
            }
        }
        .buttonStyle(.bordered)
        .tint(AppTheme.colors.danger)
    }

    private func reminderRow(title: String, enabled: Bool) -> some View {
        HStack {
            Text(title)
                .foregroundStyle(AppTheme.colors.title)
            Spacer()
            Image(systemName: enabled ? "checkmark.circle.fill" : "xmark.circle")
                .foregroundStyle(enabled ? AppTheme.colors.success : AppTheme.colors.body)
        }
    }
}
