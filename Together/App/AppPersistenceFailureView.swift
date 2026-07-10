import SwiftUI

struct AppPersistenceFailureView: View {
    let failure: PersistenceStartupFailure
    let onRetry: () -> Void

    var body: some View {
        ZStack {
            GradientGridBackground()
                .ignoresSafeArea()

            VStack(spacing: AppTheme.spacing.xl) {
                Image(systemName: "externaldrive.badge.exclamationmark")
                    .font(AppTheme.typography.sized(44, weight: .semibold))
                    .foregroundStyle(AppTheme.colors.warning)
                    .accessibilityHidden(true)

                VStack(spacing: AppTheme.spacing.sm) {
                    Text("无法打开本地数据")
                        .font(AppTheme.typography.sized(20, weight: .bold))
                        .foregroundStyle(AppTheme.colors.title)

                    Text("Together 已保留原有数据库，没有执行重置或删除。请重试；如果问题持续存在，请保留当前安装并联系支持。")
                        .font(AppTheme.typography.sized(15, weight: .medium))
                        .foregroundStyle(AppTheme.colors.body.opacity(0.72))
                        .multilineTextAlignment(.center)
                        .lineSpacing(4)
                }

                Button("重试", action: onRetry)
                    .font(AppTheme.typography.sized(16, weight: .semibold))
                    .buttonStyle(.borderedProminent)
                    .buttonBorderShape(.capsule)
                    .accessibilityHint("重新尝试打开现有本地数据库")

                #if DEBUG
                Text(failure.summary)
                    .font(.caption.monospaced())
                    .foregroundStyle(AppTheme.colors.textTertiary)
                    .textSelection(.enabled)
                #endif
            }
            .padding(.horizontal, AppTheme.spacing.xxl)
            .frame(maxWidth: 520)
        }
    }
}

#if DEBUG
#Preview {
    AppPersistenceFailureView(
        failure: PersistenceStartupFailure(summary: "Preview failure"),
        onRetry: {}
    )
}
#endif
