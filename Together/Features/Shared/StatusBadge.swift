import SwiftUI

struct StatusBadge: View {
    let title: String
    let tint: Color

    var body: some View {
        Text(title)
            .font(AppTheme.typography.textStyle(.caption1, weight: .semibold))
            .foregroundStyle(tint)
            .padding(.horizontal, AppTheme.spacing.sm)
            .padding(.vertical, AppTheme.spacing.xs)
            .background(tint.opacity(0.12), in: Capsule())
    }
}
