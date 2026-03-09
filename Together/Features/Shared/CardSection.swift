import SwiftUI

struct CardSection<Content: View>: View {
    let title: String
    let subtitle: String?
    @ViewBuilder var content: Content

    init(title: String, subtitle: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.subtitle = subtitle
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.spacing.md) {
            VStack(alignment: .leading, spacing: AppTheme.spacing.xs) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(AppTheme.colors.title)

                if let subtitle {
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(AppTheme.colors.body)
                }
            }

            content
        }
        .padding(AppTheme.spacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppTheme.colors.surface, in: RoundedRectangle(cornerRadius: AppTheme.radius.card))
        .overlay {
            RoundedRectangle(cornerRadius: AppTheme.radius.card)
                .stroke(AppTheme.colors.outline)
        }
    }
}
