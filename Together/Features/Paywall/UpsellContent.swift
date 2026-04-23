import SwiftUI

/// 付费墙主体视图，无 sheet 装饰。`UpsellSheet` 包 close + success overlay；
/// Profile 的 `ProfileSubscriptionView` Free 态直接嵌入本视图。
struct UpsellContent: View {
    let displayKind: UpsellDisplayKind
    @Bindable var viewModel: PaywallViewModel

    private var hero: UpsellCopy.Hero { UpsellCopy.hero(for: displayKind) }
    private var benefits: [UpsellCopy.Benefit] { UpsellCopy.benefits(highlightedBy: displayKind) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppTheme.spacing.xl) {
                if let banner = hero.lapseBanner {
                    lapseBanner(banner)
                }

                heroSection
                benefitsSection
                packagesSection
                primaryCTA

                if case .failed(let err) = viewModel.state {
                    errorInline(err)
                }

                restoreButton

                PaywallLegalFooter(selectedPackage: viewModel.selectedPackage)
            }
            .padding(.horizontal, AppTheme.spacing.lg)
            .padding(.vertical, AppTheme.spacing.xl)
        }
        .background(AppTheme.colors.background.ignoresSafeArea())
    }

    // MARK: - Sections

    private func lapseBanner(_ text: String) -> some View {
        Text(text)
            .font(AppTheme.typography.sized(13, weight: .semibold))
            .foregroundStyle(AppTheme.colors.pairAccent)
            .frame(maxWidth: .infinity)
            .padding(.vertical, AppTheme.spacing.sm)
            .padding(.horizontal, AppTheme.spacing.md)
            .background(
                RoundedRectangle(cornerRadius: AppTheme.radius.md, style: .continuous)
                    .fill(AppTheme.colors.pairAccent.opacity(0.12))
            )
    }

    private var heroSection: some View {
        VStack(alignment: .leading, spacing: AppTheme.spacing.xs) {
            Image(systemName: "crown.fill")
                .font(AppTheme.typography.sized(36, weight: .medium))
                .foregroundStyle(AppTheme.colors.pairAccent)
                .padding(.bottom, AppTheme.spacing.xs)
            Text(hero.title)
                .font(AppTheme.typography.sized(26, weight: .bold))
                .foregroundStyle(AppTheme.colors.title)
            Text(hero.subtitle)
                .font(AppTheme.typography.sized(14, weight: .regular))
                .foregroundStyle(AppTheme.colors.textTertiary)
        }
    }

    private var benefitsSection: some View {
        VStack(alignment: .leading, spacing: AppTheme.spacing.sm) {
            ForEach(benefits) { benefit in
                HStack(alignment: .center, spacing: AppTheme.spacing.sm) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(AppTheme.typography.sized(16, weight: .semibold))
                        .foregroundStyle(AppTheme.colors.pairAccent)
                    Text(benefit.displayText)
                        .font(AppTheme.typography.sized(14, weight: .medium))
                        .foregroundStyle(AppTheme.colors.body)
                    Spacer()
                }
            }
        }
    }

    @ViewBuilder
    private var packagesSection: some View {
        if case .failed(.noOfferings) = viewModel.state {
            noOfferingsEmptyState
        } else if let offering = viewModel.cachedOffering {
            VStack(spacing: AppTheme.spacing.sm) {
                ForEach(offering.packages) { pkg in
                    PaywallPackageCard(
                        package: pkg,
                        isSelected: pkg.id == viewModel.selectedPackageID,
                        onSelect: { viewModel.selectPackage(pkg.id) }
                    )
                }
            }
        } else if case .loadingOfferings = viewModel.state {
            ProgressView()
                .frame(maxWidth: .infinity, minHeight: 120)
        }
    }

    private var noOfferingsEmptyState: some View {
        VStack(spacing: AppTheme.spacing.md) {
            Image(systemName: "exclamationmark.triangle")
                .font(AppTheme.typography.sized(28, weight: .regular))
                .foregroundStyle(AppTheme.colors.textTertiary)
            Text("付费墙暂时不可用")
                .font(AppTheme.typography.sized(15, weight: .semibold))
                .foregroundStyle(AppTheme.colors.title)
            Text("请稍后再试")
                .font(AppTheme.typography.sized(13))
                .foregroundStyle(AppTheme.colors.textTertiary)
            Button {
                Task { await viewModel.load() }
            } label: {
                Text("重试")
                    .font(AppTheme.typography.sized(14, weight: .semibold))
                    .padding(.horizontal, AppTheme.spacing.lg)
                    .padding(.vertical, AppTheme.spacing.sm)
                    .background(
                        Capsule().fill(AppTheme.colors.pairAccent.opacity(0.12))
                    )
                    .foregroundStyle(AppTheme.colors.pairAccent)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, AppTheme.spacing.xl)
    }

    private var primaryCTA: some View {
        Button {
            Task { await viewModel.purchaseSelected() }
        } label: {
            ZStack {
                if case .purchasing = viewModel.state {
                    ProgressView().tint(.white)
                } else {
                    Text(ctaLabel)
                        .font(AppTheme.typography.sized(16, weight: .semibold))
                }
            }
            .frame(maxWidth: .infinity, minHeight: 52)
            .background(
                RoundedRectangle(cornerRadius: AppTheme.radius.card, style: .continuous)
                    .fill(ctaEnabled ? AppTheme.colors.pairAccent : AppTheme.colors.pairAccent.opacity(0.4))
            )
            .foregroundStyle(.white)
        }
        .buttonStyle(.plain)
        .disabled(!ctaEnabled)
        .accessibilityHint("订阅 Together Pro")
    }

    private var ctaLabel: String {
        if let pkg = viewModel.selectedPackage,
           let trial = UpsellCopy.formatTrial(pkg.introductoryOffer) {
            return "开始\(trial) · \(UpsellCopy.formatPriceLine(pkg))"
        } else if let pkg = viewModel.selectedPackage {
            return "订阅 \(UpsellCopy.formatPriceLine(pkg))"
        }
        return "升级 Together Pro"
    }

    private var ctaEnabled: Bool {
        if viewModel.selectedPackageID == nil { return false }
        if viewModel.isInFlight { return false }
        if case .failed = viewModel.state { return false }
        return true
    }

    private func errorInline(_ error: PaywallError) -> some View {
        VStack(alignment: .leading, spacing: AppTheme.spacing.xs) {
            Text(errorTitle(error))
                .font(AppTheme.typography.sized(13, weight: .semibold))
                .foregroundStyle(AppTheme.colors.pairAccent)
            Text(errorBody(error))
                .font(AppTheme.typography.sized(12))
                .foregroundStyle(AppTheme.colors.body)
            HStack(spacing: AppTheme.spacing.sm) {
                Button("关闭") { viewModel.dismissError() }
                    .font(AppTheme.typography.sized(12, weight: .semibold))
                    .foregroundStyle(AppTheme.colors.pairAccent)
                if canRetry(error) {
                    Button("重试") { Task { await viewModel.load() } }
                        .font(AppTheme.typography.sized(12, weight: .semibold))
                        .foregroundStyle(AppTheme.colors.pairAccent)
                }
            }
            .padding(.top, AppTheme.spacing.xxs)
        }
        .padding(AppTheme.spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: AppTheme.radius.md, style: .continuous)
                .fill(AppTheme.colors.pairAccent.opacity(0.08))
        )
    }

    private func errorTitle(_ e: PaywallError) -> String {
        switch e {
        case .noOfferings: "付费墙暂时不可用"
        case .network: "网络连接异常"
        case .unknown: "出错了"
        case .entitlementNotReady: "购买已提交"
        case .nothingToRestore: "未找到已购买订阅"
        #if DEBUG
        case .debugOverrideMasksPro: "DEBUG: override 拦住购买结果"
        #endif
        }
    }

    private func errorBody(_ e: PaywallError) -> String {
        switch e {
        case .noOfferings: "请稍后再试"
        case .network: "请检查网络后重试"
        case .unknown: "请稍后重试；多次失败请联系我们"
        case .entitlementNotReady: "正在同步，请稍后回 Profile 确认"
        case .nothingToRestore: "请确认使用购买时的 Apple ID"
        #if DEBUG
        case .debugOverrideMasksPro: "切到无 override 状态可验证真实解锁"
        #endif
        }
    }

    private func canRetry(_ e: PaywallError) -> Bool {
        switch e {
        case .noOfferings, .network, .unknown: true
        case .entitlementNotReady, .nothingToRestore: false
        #if DEBUG
        case .debugOverrideMasksPro: false
        #endif
        }
    }

    private var restoreButton: some View {
        Button {
            Task { await viewModel.restore() }
        } label: {
            Text("恢复购买")
                .font(AppTheme.typography.sized(13, weight: .medium))
                .foregroundStyle(AppTheme.colors.body)
                .underline()
        }
        .buttonStyle(.plain)
        .disabled(viewModel.isInFlight)
        .frame(maxWidth: .infinity)
    }
}

#if DEBUG
#Preview("Anniversary quota") {
    UpsellContent(
        displayKind: .trigger(.anniversaryQuota),
        viewModel: makePreviewVM(loaded: true)
    )
}

#Preview("Lapse") {
    let notice = PremiumLapseNotice(
        entitlementExpiredAt: Date(timeIntervalSinceNow: -86400),
        detectedAt: Date(),
        dedupKey: "preview-lapse"
    )
    return UpsellContent(
        displayKind: .lapse(notice),
        viewModel: makePreviewVM(loaded: true)
    )
}

#Preview("Generic (Profile entry)") {
    UpsellContent(
        displayKind: .generic,
        viewModel: makePreviewVM(loaded: true)
    )
}

#Preview("Loading") {
    UpsellContent(displayKind: .generic, viewModel: makePreviewVM(loaded: false))
}

#Preview("No offerings") {
    UpsellContent(
        displayKind: .generic,
        viewModel: makePreviewVM(loaded: false, failure: .noOfferings)
    )
}

@MainActor
private func makePreviewVM(
    loaded: Bool,
    failure: PaywallError? = nil
) -> PaywallViewModel {
    let stub = StubPaywallPurchasing()
    let gate = PremiumGate.preview()
    let vm = PaywallViewModel(
        purchasing: stub,
        premiumGate: gate,
        onFinished: { _ in }
    )
    if loaded {
        Task { @MainActor in await vm.load() }
    } else if let failure {
        Task {
            await stub.setLoadOfferingsError(failure)
            await vm.load()
        }
    }
    return vm
}
#endif
