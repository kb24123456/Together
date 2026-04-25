import SwiftUI

/// Apple 3.1.2(a) 合规：自动续费说明 + 隐私 / 使用条款链接。
/// URL 走 `LegalURLs` 集中常量，由运营在 pre-TestFlight 单独 PR 替换为终值。
struct PaywallLegalFooter: View {
    let selectedPackage: PaywallPackage?

    var body: some View {
        VStack(spacing: AppTheme.spacing.xxs) {
            Text(UpsellCopy.legalBodyText(for: selectedPackage))
                .font(AppTheme.typography.sized(11))
                .foregroundStyle(AppTheme.colors.textTertiary)
                .multilineTextAlignment(.center)

            HStack(spacing: AppTheme.spacing.sm) {
                Link("隐私政策", destination: LegalURLs.privacy)
                Text("·").foregroundStyle(AppTheme.colors.textTertiary.opacity(0.6))
                Link("使用条款", destination: LegalURLs.terms)
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
