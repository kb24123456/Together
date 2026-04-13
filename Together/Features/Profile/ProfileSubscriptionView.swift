import SwiftUI

/// 会员页面 — 当前为功能预览，StoreKit 2 接入后替换
struct ProfileSubscriptionView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                // MARK: - 皇冠品牌区
                VStack(spacing: 8) {
                    Image(systemName: "crown.fill")
                        .font(.system(size: 52))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [Color(white: 0.55), Color(white: 0.75)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .shadow(color: .black.opacity(0.1), radius: 6, y: 4)
                        .padding(.top, 32)

                    Text("Together Pro")
                        .font(AppTheme.typography.sized(28, weight: .bold))
                        .foregroundStyle(AppTheme.colors.title)

                    Text("即将推出")
                        .font(AppTheme.typography.sized(15, weight: .medium))
                        .foregroundStyle(AppTheme.colors.textTertiary)
                }
                .padding(.bottom, 28)

                // MARK: - 当前状态
                HStack(spacing: 8) {
                    Image(systemName: "gift.fill")
                        .font(AppTheme.typography.sized(15, weight: .medium))
                        .foregroundStyle(AppTheme.colors.sky)
                    Text("当前为免费版，所有功能均可使用")
                        .font(AppTheme.typography.sized(14, weight: .medium))
                        .foregroundStyle(AppTheme.colors.body)
                }
                .padding(.vertical, 12)
                .padding(.horizontal, 16)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(AppTheme.colors.sky.opacity(0.08))
                )
                .padding(.horizontal, AppTheme.spacing.lg)
                .padding(.bottom, 28)

                // MARK: - 功能列表
                VStack(spacing: 0) {
                    HStack {
                        Text("Pro 功能")
                            .font(AppTheme.typography.textStyle(.headline, weight: .semibold))
                            .foregroundStyle(AppTheme.colors.title)
                        Spacer()
                    }
                    .padding(.horizontal, AppTheme.spacing.lg)
                    .padding(.bottom, 14)

                    VStack(spacing: 0) {
                        ProFeatureRow(icon: "infinity", title: "无限任务", subtitle: "不限数量添加你的任务")
                        ProFeatureRow(icon: "person.2.fill", title: "双人协作", subtitle: "共享任务空间，实时同步")
                        ProFeatureRow(icon: "square.stack", title: "例行事务", subtitle: "周期任务自动生成与追踪")
                        ProFeatureRow(icon: "icloud.fill", title: "iCloud 同步", subtitle: "多设备同步你的任务")
                        ProFeatureRow(icon: "bell.badge.fill", title: "智能提醒", subtitle: "临期提醒与自定义通知")
                        ProFeatureRow(icon: "folder.fill", title: "项目管理", subtitle: "项目分组与子任务拆解")
                        ProFeatureRow(icon: "calendar", title: "日历视图", subtitle: "按日期查看和管理任务")
                        ProFeatureRow(icon: "lock.shield.fill", title: "隐私保护", subtitle: "Face ID / 密码锁定应用")
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .fill(AppTheme.colors.surfaceElevated)
                    )
                    .shadow(color: AppTheme.colors.shadow.opacity(0.2), radius: 10, y: 4)
                    .padding(.horizontal, AppTheme.spacing.lg)
                }
            }
            .padding(.bottom, AppTheme.spacing.xxl)
        }
        .background(AppTheme.colors.background.ignoresSafeArea())
        .navigationTitle("会员")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - 功能行

private struct ProFeatureRow: View {
    let icon: String
    let title: String
    let subtitle: String

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(AppTheme.typography.sized(18, weight: .medium))
                .foregroundStyle(AppTheme.colors.sky)
                .frame(width: 32, alignment: .center)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(AppTheme.typography.textStyle(.subheadline, weight: .semibold))
                    .foregroundStyle(AppTheme.colors.title)

                Text(subtitle)
                    .font(AppTheme.typography.sized(12, weight: .regular))
                    .foregroundStyle(AppTheme.colors.textTertiary)
            }

            Spacer()

            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 20))
                .foregroundStyle(AppTheme.colors.sky.opacity(0.7))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 13)
    }
}
