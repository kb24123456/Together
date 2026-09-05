import SwiftUI

struct ProfileDataManagementView: View {
    @Bindable var viewModel: ProfileViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppTheme.hierarchy.spacing.section) {
                ProfileFlatSection(title: "危险操作") {
                    NavigationLink(value: ProfileRoute.accountDeletion) {
                        ProfileFlatDestinationRow(
                            title: "删除所有数据",
                            subtitle: "永久删除本机与 iCloud 中的数据",
                            systemImage: "trash",
                            titleColor: AppTheme.colors.danger
                        )
                    }
                    .buttonStyle(.plain)
                }

                Text("删除前需要输入昵称并再次确认，此操作不可撤销。")
                    .font(AppTheme.typography.hierarchy(.supporting, weight: .medium))
                    .foregroundStyle(AppTheme.colors.profileAccent)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, AppTheme.spacing.xl)
            .padding(.top, AppTheme.hierarchy.spacing.component)
            .padding(.bottom, AppTheme.hierarchy.spacing.page * 2)
        }
        .applySoftScrollEdgeTransition()
        .background(AppTheme.colors.profileBackground.ignoresSafeArea())
        .navigationTitle("数据管理")
        .navigationBarTitleDisplayMode(.inline)
    }
}

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

                if let errorMessage = viewModel.deletionErrorMessage {
                    deletionFailureSection(message: errorMessage)
                }

                // 注销按钮
                deleteButton
            }
            .padding(.horizontal, AppTheme.spacing.xl)
            .padding(.top, AppTheme.spacing.lg)
            .padding(.bottom, AppTheme.spacing.xxl)
        }
        .applySoftScrollEdgeTransition()
        .background(AppTheme.colors.background.ignoresSafeArea())
        .navigationTitle("删除数据")
        .navigationBarTitleDisplayMode(.inline)
        .alert("确认删除所有数据", isPresented: $showsFinalConfirmation) {
            Button("取消", role: .cancel) {}
            Button("确认删除", role: .destructive) {
                HomeInteractionFeedback.delete()
                Task {
                    if await viewModel.requestAccountDeletion() {
                        dismiss()
                    }
                }
            }
        } message: {
            Text("此操作不可撤销，将删除 Together 中的个人任务数据。")
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

            Text("本机删除完成后，iCloud 会继续同步删除。同步完成时间取决于系统和网络状态。")
                .font(AppTheme.typography.textStyle(.subheadline, weight: .regular))
                .foregroundStyle(AppTheme.colors.body)
                .lineSpacing(4)
        }
    }

    private var dataListSection: some View {
        ProfileSettingsGroupCard(title: "将被删除的数据") {
            deletionItem(icon: "person.crop.circle", text: "个人资料（昵称、头像）")
            deletionItem(icon: "checkmark.circle", text: "所有任务数据（待办、已完成、已归档）")
            deletionItem(icon: "square.stack", text: "定期任务")
            deletionItem(icon: "folder", text: "项目和清单")
            deletionItem(icon: "icloud", text: "对应的 iCloud 私有同步记录")
        }
    }

    private func deletionFailureSection(message: String) -> some View {
        VStack(alignment: .leading, spacing: AppTheme.spacing.sm) {
            Label("删除未完成", systemImage: "exclamationmark.circle.fill")
                .font(AppTheme.typography.sized(15, weight: .semibold))
                .foregroundStyle(AppTheme.colors.danger)
            Text(message)
                .font(AppTheme.typography.sized(14, weight: .medium))
                .foregroundStyle(AppTheme.colors.body)
            Button("重试") {
                Task {
                    if await viewModel.requestAccountDeletion() {
                        dismiss()
                    }
                }
            }
            .font(AppTheme.typography.sized(15, weight: .semibold))
            .disabled(viewModel.isAccountDeletionInProgress)
        }
        .padding(AppTheme.spacing.md)
        .background(
            RoundedRectangle(cornerRadius: AppTheme.radius.md, style: .continuous)
                .fill(AppTheme.colors.surfaceElevated)
        )
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
            Text("请输入你的昵称「\(expectedName)」以确认删除")
                .font(AppTheme.typography.textStyle(.subheadline, weight: .medium))
                .foregroundStyle(AppTheme.colors.body)

            TextField("输入昵称", text: $confirmationText)
                .font(AppTheme.typography.sized(17, weight: .medium))
                .foregroundStyle(AppTheme.colors.title)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.done)
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
                Text("删除数据")
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
