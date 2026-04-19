import SwiftUI

/// 「关于 Together」子页面：隐私政��、用户协议、意见反馈、版本号
struct ProfileAboutView: View {
    let appVersion: String

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppTheme.spacing.lg) {
                // App 标识
                VStack(spacing: AppTheme.spacing.sm) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(AppTheme.typography.sized(52))
                        .foregroundStyle(AppTheme.colors.sky)

                    Text("Together")
                        .font(AppTheme.typography.sized(20, weight: .bold))
                        .foregroundStyle(AppTheme.colors.title)

                    Text("版本 \(appVersion)")
                        .font(AppTheme.typography.sized(13, weight: .medium))
                        .foregroundStyle(AppTheme.colors.textTertiary)
                }
                .frame(maxWidth: .infinity)
                .padding(.top, AppTheme.spacing.xl)
                .padding(.bottom, AppTheme.spacing.sm)

                // 链接列表
                ProfileSettingsGroupCard(title: "") {
                    NavigationLink(destination: ProfileFeedbackView()) {
                        ProfileSettingsRow(
                            title: "意见反馈",
                            value: "",
                            showsChevron: true
                        )
                    }
                    .buttonStyle(.plain)
                    .simultaneousGesture(
                        TapGesture().onEnded { HomeInteractionFeedback.selection() }
                    )

                    NavigationLink(destination: ProfilePrivacyPolicyView()) {
                        ProfileSettingsRow(
                            title: "隐私政策",
                            value: "",
                            showsChevron: true
                        )
                    }
                    .buttonStyle(.plain)
                    .simultaneousGesture(
                        TapGesture().onEnded { HomeInteractionFeedback.selection() }
                    )

                    NavigationLink(destination: ProfileTermsOfServiceView()) {
                        ProfileSettingsRow(
                            title: "用户协议",
                            value: "",
                            showsChevron: true
                        )
                    }
                    .buttonStyle(.plain)
                    .simultaneousGesture(
                        TapGesture().onEnded { HomeInteractionFeedback.selection() }
                    )
                }
            }
            .padding(.horizontal, AppTheme.spacing.md)
            .padding(.bottom, AppTheme.spacing.xxl)
        }
        .background(AppTheme.colors.background.ignoresSafeArea())
        .navigationTitle("关于 Together")
        .navigationBarTitleDisplayMode(.inline)
    }
}
