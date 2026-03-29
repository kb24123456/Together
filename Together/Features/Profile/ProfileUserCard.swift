import SwiftUI

struct ProfileUserCard: View {
    let displayName: String
    let spaceName: String
    let bindingTitle: String
    let avatarSystemName: String

    var body: some View {
        HStack(alignment: .center, spacing: AppTheme.spacing.md) {
            Circle()
                .fill(
                    LinearGradient(
                        colors: [
                            AppTheme.colors.avatarWarm,
                            AppTheme.colors.surface
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay {
                    Image(systemName: avatarSystemName)
                        .font(AppTheme.typography.sized(36, weight: .semibold))
                        .foregroundStyle(AppTheme.colors.title.opacity(0.84))
                }
                .frame(width: 86, height: 86)

            VStack(alignment: .leading, spacing: 8) {
                Text(displayName)
                    .font(AppTheme.typography.sized(28, weight: .bold))
                    .foregroundStyle(AppTheme.colors.title)
                    .lineLimit(1)

                Text(spaceName)
                    .font(AppTheme.typography.textStyle(.headline, weight: .medium))
                    .foregroundStyle(AppTheme.colors.body.opacity(0.74))
                    .lineLimit(1)

                StatusBadge(title: bindingTitle, tint: AppTheme.colors.accent)
            }

            Spacer(minLength: 0)
        }
        .padding(22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .fill(Color.white.opacity(0.96))
        )
        .shadow(color: AppTheme.colors.shadow.opacity(0.34), radius: 16, y: 7)
        .accessibilityElement(children: .combine)
    }
}
