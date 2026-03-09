import SwiftUI

struct EmptyStateCard: View {
    let title: String
    let message: String

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.spacing.sm) {
            Text(title)
                .font(.headline)
                .foregroundStyle(AppTheme.colors.title)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(AppTheme.colors.body)
        }
        .padding(AppTheme.spacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppTheme.colors.accentSoft, in: RoundedRectangle(cornerRadius: AppTheme.radius.card))
    }
}
