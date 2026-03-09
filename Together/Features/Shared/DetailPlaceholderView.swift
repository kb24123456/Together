import SwiftUI

struct DetailPlaceholderView: View {
    let title: String
    let message: String

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.spacing.md) {
            Text(title)
                .font(.title3.bold())
            Text(message)
                .foregroundStyle(AppTheme.colors.body)
            Spacer()
        }
        .padding(AppTheme.spacing.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(AppTheme.colors.background.ignoresSafeArea())
    }
}
