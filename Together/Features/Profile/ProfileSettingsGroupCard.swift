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
            if title.isEmpty == false {
                Text(title)
                    .font(AppTheme.typography.textStyle(.footnote, weight: .semibold))
                    .foregroundStyle(AppTheme.colors.body.opacity(0.52))
                    .tracking(0.4)
                    .padding(.horizontal, AppTheme.spacing.md)
            }

            VStack(spacing: 0) {
                content
            }
            .padding(.horizontal, AppTheme.spacing.md)
        }
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(AppTheme.colors.hairline)
                .frame(height: 1)
                .padding(.horizontal, AppTheme.spacing.md)
        }
    }
}
