import SwiftUI

/// 单个 package 卡片。选中态 `pairAccent` 边框，试用徽章右上。
struct PaywallPackageCard: View {
    let package: PaywallPackage
    let isSelected: Bool
    let onSelect: () -> Void

    private var trialText: String? { UpsellCopy.formatTrial(package.introductoryOffer) }

    var body: some View {
        Button(action: onSelect) {
            HStack(alignment: .center, spacing: AppTheme.spacing.md) {
                selectionIndicator
                VStack(alignment: .leading, spacing: AppTheme.spacing.xxs) {
                    Text(package.localizedTitle)
                        .font(AppTheme.typography.sized(16, weight: .semibold))
                        .foregroundStyle(AppTheme.colors.title)
                    Text(UpsellCopy.formatPriceLine(package))
                        .font(AppTheme.typography.sized(14, weight: .medium))
                        .foregroundStyle(AppTheme.colors.body)
                }
                Spacer()
                if let trialText {
                    Text(trialText)
                        .font(AppTheme.typography.sized(11, weight: .semibold))
                        .foregroundStyle(AppTheme.colors.pairAccent)
                        .padding(.horizontal, AppTheme.spacing.sm)
                        .padding(.vertical, AppTheme.spacing.xxs)
                        .background(
                            Capsule().fill(AppTheme.colors.pairAccent.opacity(0.12))
                        )
                }
            }
            .padding(AppTheme.spacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: AppTheme.radius.card, style: .continuous)
                    .fill(AppTheme.colors.surfaceElevated)
            )
            .overlay(
                RoundedRectangle(cornerRadius: AppTheme.radius.card, style: .continuous)
                    .stroke(
                        isSelected ? AppTheme.colors.pairAccent : Color.clear,
                        lineWidth: 2
                    )
            )
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityAddTraits(.isButton)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var selectionIndicator: some View {
        ZStack {
            Circle()
                .stroke(
                    isSelected ? AppTheme.colors.pairAccent : AppTheme.colors.textTertiary.opacity(0.5),
                    lineWidth: 1.5
                )
                .frame(width: 20, height: 20)
            if isSelected {
                Circle()
                    .fill(AppTheme.colors.pairAccent)
                    .frame(width: 10, height: 10)
            }
        }
    }

    private var accessibilityLabel: String {
        let price = UpsellCopy.formatPriceLine(package)
        if let trial = trialText {
            return "\(package.localizedTitle)，\(price)，\(trial)"
        }
        return "\(package.localizedTitle)，\(price)"
    }
}

#if DEBUG
#Preview("Unselected") {
    PaywallPackageCard(
        package: StubPaywallPurchasing.sampleOffering.packages[0],
        isSelected: false,
        onSelect: {}
    )
    .padding()
}

#Preview("Selected annual with trial") {
    PaywallPackageCard(
        package: StubPaywallPurchasing.sampleOffering.packages[1],
        isSelected: true,
        onSelect: {}
    )
    .padding()
}

#Preview("Lifetime") {
    PaywallPackageCard(
        package: StubPaywallPurchasing.sampleOffering.packages[2],
        isSelected: false,
        onSelect: {}
    )
    .padding()
}
#endif
