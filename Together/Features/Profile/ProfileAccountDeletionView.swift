import SwiftUI

struct ProfileAccountDeletionView: View {
    @Bindable var viewModel: ProfileViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var confirmationText: String = ""
    @State private var showsFinalConfirmation: Bool = false

    private var expectedName: String {
        viewModel.currentUser?.displayName ?? ""
    }

    private var isConfirmationValid: Bool {
        confirmationText.trimmingCharacters(in: .whitespacesAndNewlines) == expectedName
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppTheme.spacing.xl) {
                // 警告说明
                warningSection

                // 数据清单
                dataListSection

                // 输入确认
                confirmationInputSection

                // 注销按钮
                deleteButton
            }
            .padding(.horizontal, AppTheme.spacing.xl)
            .padding(.top, AppTheme.spacing.lg)
            .padding(.bottom, AppTheme.spacing.xxl)
        }
        .background(AppTheme.colors.background.ignoresSafeArea())
        .navigationTitle("账号注销")
        .navigationBarTitleDisplayMode(.inline)
        .alert("确认注销账号", isPresented: $showsFinalConfirmation) {
            Button("取消", role: .cancel) {}
            Button("确认注销", role: .destructive) {
                HomeInteractionFeedback.delete()
                Task {
                    await viewModel.requestAccountDeletion()
                }
            }
        } message: {
            Text("此操作不可撤销，您的所有数据将被永久删除。")
        }
    }

    private var warningSection: some View {
        VStack(alignment: .leading, spacing: AppTheme.spacing.md) {
            HStack(spacing: AppTheme.spacing.sm) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(AppTheme.typography.sized(20, weight: .semibold))
                    .foregroundStyle(AppTheme.colors.warning)

                Text("请仔细阅读以下内容")
                    .font(AppTheme.typography.textStyle(.headline, weight: .semibold))
                    .foregroundStyle(AppTheme.colors.title)
            }

            Text("注销账号后，以下数据将被永久删除且无法恢复。云端数据将在 14 天内完全清除。")
                .font(AppTheme.typography.textStyle(.subheadline, weight: .regular))
                .foregroundStyle(AppTheme.colors.body)
                .lineSpacing(4)
        }
    }

    private var dataListSection: some View {
        ProfileSettingsGroupCard(title: "将被删除的数据") {
            deletionItem(icon: "person.crop.circle", text: "个人资料（昵称、头像）")
            deletionItem(icon: "checkmark.circle", text: "所有任务数据（待办、已完成、已归档）")
            deletionItem(icon: "square.stack", text: "例行事务和模板")
            deletionItem(icon: "folder", text: "项目和清单")
            if viewModel.isPairMode {
                deletionItem(icon: "person.2", text: "双人协作空间（将自动解绑）")
            }
            deletionItem(icon: "icloud", text: "iCloud 云端同步数据")
        }
    }

    private func deletionItem(icon: String, text: String) -> some View {
        HStack(spacing: AppTheme.spacing.md) {
            Image(systemName: icon)
                .font(AppTheme.typography.sized(15, weight: .medium))
                .foregroundStyle(AppTheme.colors.danger)
                .frame(width: 24, alignment: .center)

            Text(text)
                .font(AppTheme.typography.textStyle(.subheadline, weight: .medium))
                .foregroundStyle(AppTheme.colors.title)
        }
        .padding(.vertical, AppTheme.spacing.xxs)
    }

    private var confirmationInputSection: some View {
        VStack(alignment: .leading, spacing: AppTheme.spacing.sm) {
            Text("请输入你的昵称「\(expectedName)」以确认注销")
                .font(AppTheme.typography.textStyle(.subheadline, weight: .medium))
                .foregroundStyle(AppTheme.colors.body)

            TextField("输入昵称", text: $confirmationText)
                .font(AppTheme.typography.textStyle(.body, weight: .medium))
                .foregroundStyle(AppTheme.colors.title)
                .padding(.horizontal, AppTheme.spacing.md)
                .padding(.vertical, AppTheme.spacing.md)
                .background(
                    RoundedRectangle(cornerRadius: AppTheme.radius.md, style: .continuous)
                        .fill(AppTheme.colors.surfaceElevated)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: AppTheme.radius.md, style: .continuous)
                        .stroke(AppTheme.colors.outline, lineWidth: 1)
                )
        }
    }

    private var deleteButton: some View {
        Button {
            HomeInteractionFeedback.selection()
            showsFinalConfirmation = true
        } label: {
            HStack(spacing: AppTheme.spacing.xs) {
                if viewModel.isAccountDeletionInProgress {
                    ProgressView()
                        .tint(.white)
                }
                Text("注销账号")
                    .font(AppTheme.typography.sized(16, weight: .bold))
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, AppTheme.spacing.md)
            .background(
                RoundedRectangle(cornerRadius: AppTheme.radius.lg, style: .continuous)
                    .fill(isConfirmationValid ? AppTheme.colors.danger : AppTheme.colors.danger.opacity(0.4))
            )
        }
        .buttonStyle(.plain)
        .disabled(!isConfirmationValid || viewModel.isAccountDeletionInProgress)
        .padding(.top, AppTheme.spacing.sm)
    }
}
