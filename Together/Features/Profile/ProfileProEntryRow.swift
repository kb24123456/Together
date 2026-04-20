import SwiftUI

/// Pro subscription entry. Placed immediately below the identity card and
/// above the collaboration group. Neutral row style — no gradients, no
/// dark chips — per β direction. When subscribed, the row does not
/// disappear; the subtitle transforms (see `ProSubscriptionStatus`).
struct ProfileProEntryRow: View {
    let status: ProSubscriptionStatus

    var body: some View {
        HStack(alignment: .center, spacing: AppTheme.spacing.md) {
            Circle()
                .fill(AppTheme.colors.pairAccent)
                .frame(width: 4, height: 4)

            VStack(alignment: .leading, spacing: AppTheme.spacing.xxs) {
                Text("Together Pro")
                    .font(AppTheme.typography.sized(15, weight: .semibold))
                    .foregroundStyle(AppTheme.colors.title)
                    .lineLimit(1)

                Text(status.subtitleText)
                    .font(AppTheme.typography.sized(12, weight: .regular))
                    .foregroundStyle(AppTheme.colors.textTertiary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
            }

            Spacer(minLength: AppTheme.spacing.md)

            Image(systemName: "chevron.right")
                .font(AppTheme.typography.sized(11, weight: .semibold))
                .foregroundStyle(AppTheme.colors.body.opacity(0.36))
        }
        .padding(.horizontal, AppTheme.spacing.md)
        .padding(.vertical, AppTheme.spacing.sm)
        .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: AppTheme.radius.card, style: .continuous)
                .fill(AppTheme.colors.surfaceElevated)
        )
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Together Pro，\(status.subtitleText)")
        .accessibilityHint(status.accessibilityStateLabel)
    }
}
