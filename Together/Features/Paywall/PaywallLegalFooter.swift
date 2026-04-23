import SwiftUI

/// Apple 3.1.2(a) 合规占位：自动续费说明 + 隐私 / 使用条款链接。
/// Session B 替换 `privacyURL` / `termsURL` 为公网 URL。
struct PaywallLegalFooter: View {
    let selectedPackage: PaywallPackage?

    private static let privacyURL = URL(string: "https://example.com/placeholder/privacy")!
    private static let termsURL = URL(string: "https://example.com/placeholder/terms")!

    var body: some View {
        VStack(spacing: AppTheme.spacing.xxs) {
            Text(UpsellCopy.legalBodyText(for: selectedPackage))
                .font(AppTheme.typography.sized(11))
                .foregroundStyle(AppTheme.colors.textTertiary)
                .multilineTextAlignment(.center)

            HStack(spacing: AppTheme.spacing.sm) {
                Link("隐私政策", destination: Self.privacyURL)
                Text("·").foregroundStyle(AppTheme.colors.textTertiary.opacity(0.6))
                Link("使用条款", destination: Self.termsURL)
            }
            .font(AppTheme.typography.sized(11, weight: .medium))
            .foregroundStyle(AppTheme.colors.body)
        }
        .padding(.horizontal, AppTheme.spacing.sm)
        .padding(.vertical, AppTheme.spacing.sm)
    }
}

#if DEBUG
#Preview("With package") {
    PaywallLegalFooter(selectedPackage: StubPaywallPurchasing.sampleOffering.packages[1])
        .padding()
}

#Preview("No package") {
    PaywallLegalFooter(selectedPackage: nil)
        .padding()
}
#endif
