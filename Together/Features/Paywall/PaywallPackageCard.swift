import SwiftUI

/// 单个 package 卡片（Doit!Pro 风格）。
/// 选中态：**黑底白字 + 顶部 neon 渐变光晕**（最大视觉锚点）
/// 未选态：白底黑字 + 浅 outline
/// 卡片纵向布局：plan 名（小）→ 价格（大粗）→ 副标题（小）
struct PaywallPackageCard: View {
    let package: PaywallPackage
    let isSelected: Bool
    /// 顶部小徽章文案（年付 "省 41%"），nil 不显示。selected 时也会显示。
    var topBadge: String? = nil
    let onSelect: () -> Void

    private var foreground: Color {
        isSelected ? .white : AppTheme.colors.title
    }
    private var subtitleColor: Color {
        isSelected ? .white.opacity(0.7) : AppTheme.colors.body.opacity(0.85)
    }
    private var planNameColor: Color {
        isSelected ? .white.opacity(0.85) : AppTheme.colors.body
    }

    var body: some View {
        Button(action: onSelect) {
            ZStack(alignment: .top) {
                // 卡片主体
                VStack(spacing: AppTheme.spacing.xxs) {
                    Spacer(minLength: AppTheme.spacing.sm)
                    Text(UpsellCopy.packageDisplayName(package))
                        .font(AppTheme.typography.cardLabel)
                        .foregroundStyle(planNameColor)
                    Text(package.localizedPriceString)
                        .font(AppTheme.typography.priceLarge)
                        .foregroundStyle(foreground)
                        .minimumScaleFactor(0.7)
                        .lineLimit(1)
                    Text(UpsellCopy.packageSubtitle(package))
                        .font(AppTheme.typography.cardCaption)
                        .foregroundStyle(subtitleColor)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .padding(.horizontal, AppTheme.spacing.xxs)
                    Spacer(minLength: AppTheme.spacing.sm)
                }
                .frame(maxWidth: .infinity, minHeight: 116)
                .background(
                    RoundedRectangle(cornerRadius: AppTheme.radius.card, style: .continuous)
                        .fill(isSelected ? AppTheme.colors.title : AppTheme.colors.surface)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: AppTheme.radius.card, style: .continuous)
                        .stroke(isSelected ? Color.clear : AppTheme.colors.outline, lineWidth: 1)
                )

                // 顶部 neon 光晕 — 仅选中态
                if isSelected {
                    neonStrip
                        .padding(.horizontal, AppTheme.spacing.xs)
                        .padding(.top, 0)
                        .allowsHitTesting(false)
                }

                // 顶部 badge — capsule，跨在卡片顶部边缘
                if let topBadge {
                    Text(topBadge)
                        .font(AppTheme.typography.sized(10, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, AppTheme.spacing.sm)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(AppTheme.colors.pairAccent))
                        .offset(y: -10)
                        .accessibilityHidden(true)
                }
            }
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityAddTraits(.isButton)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    /// neon 光晕：4 色横向渐变 + 微 blur，营造科技/奢华感。
    private var neonStrip: some View {
        LinearGradient(
            colors: [
                AppTheme.colors.violet.opacity(0.95),
                AppTheme.colors.sky,
                AppTheme.colors.pairAccent,
                AppTheme.colors.sun
            ],
            startPoint: .leading,
            endPoint: .trailing
        )
        .frame(height: 4)
        .clipShape(Capsule())
        .blur(radius: 1.5)
        .padding(.top, 6)
    }

    private var accessibilityLabel: String {
        let price = UpsellCopy.formatPriceLine(package)
        let badge = topBadge ?? UpsellCopy.formatTrial(package.introductoryOffer) ?? ""
        let parts = [UpsellCopy.packageDisplayName(package), price, badge].filter { !$0.isEmpty }
        return parts.joined(separator: "，")
    }
}

#if DEBUG
#Preview("Three plans row") {
    HStack(spacing: AppTheme.spacing.sm) {
        PaywallPackageCard(
            package: StubPaywallPurchasing.sampleOffering.packages[2],
            isSelected: true,
            topBadge: nil,
            onSelect: {}
        )
        PaywallPackageCard(
            package: StubPaywallPurchasing.sampleOffering.packages[1],
            isSelected: false,
            topBadge: "省 41%",
            onSelect: {}
        )
        PaywallPackageCard(
            package: StubPaywallPurchasing.sampleOffering.packages[0],
            isSelected: false,
            topBadge: nil,
            onSelect: {}
        )
    }
    .padding()
}
#endif
