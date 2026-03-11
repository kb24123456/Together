import SwiftUI

struct EmptyStateCard: View {
    let title: String
    let message: String

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.spacing.sm) {
            Text(title)
                .font(AppTheme.typography.textStyle(.headline, weight: .semibold))
                .foregroundStyle(AppTheme.colors.title)
            Text(message)
                .font(AppTheme.typography.textStyle(.subheadline))
                .foregroundStyle(AppTheme.colors.body)
        }
        .padding(AppTheme.spacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppTheme.colors.accentSoft, in: RoundedRectangle(cornerRadius: AppTheme.radius.card))
    }
}
