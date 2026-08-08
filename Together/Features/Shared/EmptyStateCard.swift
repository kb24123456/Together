import SwiftUI

/// 通用空状态卡片。
/// 视觉优先级：illustration > systemImage > 无图标。
/// illustration 用于 v3 baseline 风格的 transparent PNG 插画（如 EmptyList / EmptyCalendar 等）。
struct EmptyStateCard: View {
    let title: String
    let message: String
    var illustration: String? = nil
    var systemImage: String? = nil
    var usesNeutralBackground = false

    var body: some View {
        VStack(alignment: .center, spacing: AppTheme.spacing.sm) {
            if let illustration {
                Image(illustration)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 110, height: 110)
                    .accessibilityHidden(true)
            } else if let systemImage {
                Image(systemName: systemImage)
                    .font(AppTheme.typography.sized(36, weight: .light))
                    .foregroundStyle(AppTheme.colors.body.opacity(0.72))
                    .padding(.bottom, AppTheme.spacing.xs)
                    .accessibilityHidden(true)
            }
            Text(title)
                .font(AppTheme.typography.textStyle(.headline, weight: .semibold))
                .foregroundStyle(AppTheme.colors.title)
                .multilineTextAlignment(.center)
            Text(message)
                .font(AppTheme.typography.textStyle(.subheadline))
                .foregroundStyle(AppTheme.colors.body)
                .multilineTextAlignment(.center)
        }
        .padding(AppTheme.spacing.lg)
        .frame(maxWidth: .infinity)
        .background(
            (usesNeutralBackground ? Color.clear : AppTheme.colors.surfaceElevated),
            in: RoundedRectangle(cornerRadius: AppTheme.radius.card)
        )
    }
}
