import SwiftUI

struct ProfileSyncRecoveryView: View {
    @Bindable var viewModel: ProfileViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppTheme.spacing.xxl) {
                ProfileFlatSection(title: "iCloud") {
                    ProfileFlatValueRow(
                        title: "状态",
                        value: viewModel.iCloudStatusSummary,
                        systemImage: "icloud",
                        trailingSymbol: ""
                    )

                    Button {
                        HomeInteractionFeedback.selection()
                        Task { await viewModel.checkICloudStatus() }
                    } label: {
                        ProfileFlatValueRow(
                            title: "检查 iCloud 状态",
                            value: "",
                            systemImage: "arrow.clockwise",
                            trailingSymbol: ""
                        )
                    }
                    .buttonStyle(.plain)
                }

                Text(viewModel.iCloudStatusDescription(for: viewModel.iCloudStatus))
                    .font(AppTheme.typography.sized(14, weight: .medium))
                    .foregroundStyle(AppTheme.colors.textTertiary)
                    .lineSpacing(4)
                    .padding(.top, -AppTheme.spacing.lg)
            }
            .padding(.horizontal, AppTheme.spacing.md)
            .padding(.top, AppTheme.spacing.lg)
            .padding(.bottom, AppTheme.spacing.xxl)
        }
        .applySoftScrollEdgeTransition()
        .background(AppTheme.colors.background.ignoresSafeArea())
        .navigationTitle("iCloud 同步")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await viewModel.checkICloudStatus()
        }
    }
}
