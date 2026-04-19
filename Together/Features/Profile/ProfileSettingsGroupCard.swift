import SwiftUI

struct ProfileSettingsGroupCard<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    init(title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.spacing.sm) {
            Text(title)
                .font(AppTheme.typography.textStyle(.headline, weight: .semibold))
                .foregroundStyle(AppTheme.colors.body.opacity(0.62))

            VStack(spacing: AppTheme.spacing.md) {
                content
            }
            .padding(.horizontal, AppTheme.spacing.md)
            .padding(.vertical, AppTheme.spacing.md)
            .background(
                RoundedRectangle(cornerRadius: AppTheme.radius.xl, style: .continuous)
                    .fill(AppTheme.colors.surfaceElevated)
            )
            .shadow(color: AppTheme.colors.shadow.opacity(0.34), radius: 14, y: 6)
        }
    }
}
