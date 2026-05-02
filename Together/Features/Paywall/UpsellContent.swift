import SwiftUI

/// 付费墙主体视图，无 sheet 装饰。`UpsellSheet` 包 close + success overlay；
/// Profile 的 `ProfileSubscriptionView` Free 态直接嵌入本视图。
///
/// 设计 DNA（Doit!Pro 风 × Together 色板）：
/// - 浅米色 GradientGrid 背景
/// - Hero: BrandIcon 居中 + 大字粗体品牌名
/// - Plan: 横排 3 卡，选中态黑底白字 + 顶部 neon 光晕
/// - 中央章节 header + 麦穗装饰
/// - Benefits: CardSection 包，每行 icon + title + sub + 右 ✓
/// - 底部 sticky 黑色 CTA + 灰色 restore + 合规 footer
struct UpsellContent: View {
    let displayKind: UpsellDisplayKind
    @Bindable var viewModel: PaywallViewModel

    private var hero: UpsellCopy.Hero { UpsellCopy.hero(for: displayKind) }
    private var benefits: [UpsellCopy.Benefit] { UpsellCopy.benefits(highlightedBy: displayKind) }

    private var isGraceMode: Bool {
        if case .trigger(.graceExpiring) = displayKind { return true }
        return false
    }

    private var graceDaysRemaining: Int? {
        if case .trigger(.graceExpiring(let days)) = displayKind { return days }
        return nil
    }

    var body: some View {
        ZStack {
            GradientGridBackground()
                .ignoresSafeArea()

            ScrollView {
                VStack(spacing: AppTheme.spacing.lg) {
                    if let banner = hero.lapseBanner {
                        lapseBanner(banner)
                    }

                    heroSection
                    packagesSection

                    if isGraceMode {
                        sectionHeader(title: graceSectionHeaderTitle)
                        graceReassuranceSection
                    } else {
                        sectionHeader(title: benefitsSectionHeaderTitle)
                        benefitsSection
                    }

                    if case .failed(let err) = viewModel.state {
                        errorInline(err)
                    }

                    PaywallLegalFooter(selectedPackage: viewModel.selectedPackage)
                        .padding(.top, AppTheme.spacing.md)
                    primaryCTA
                    restoreButton
                }
                .padding(.horizontal, AppTheme.spacing.xl)
                .padding(.top, AppTheme.spacing.xl)
                .padding(.bottom, AppTheme.spacing.xxl)
            }
        }
    }

    // MARK: - Hero

    private var heroSection: some View {
        VStack(spacing: AppTheme.spacing.sm) {
            Image("BrandIcon")
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
                .frame(width: 96, height: 96)
                .accessibilityHidden(true)
            Text(hero.title)
                .font(AppTheme.typography.display)
                .foregroundStyle(AppTheme.colors.title)
                .multilineTextAlignment(.center)
            Text(hero.subtitle)
                .font(AppTheme.typography.textStyle(.subheadline))
                .foregroundStyle(AppTheme.colors.bodySecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Lapse banner

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

    // MARK: - Packages (3 横排)

    @ViewBuilder
    private var packagesSection: some View {
        if case .failed(.noOfferings) = viewModel.state {
            noOfferingsEmptyState
        } else if let offering = viewModel.cachedOffering {
            VStack(spacing: AppTheme.spacing.sm) {
                HStack(alignment: .top, spacing: AppTheme.spacing.sm) {
                    ForEach(offering.packages) { pkg in
                        PaywallPackageCard(
                            package: pkg,
                            isSelected: pkg.id == viewModel.selectedPackageID,
                            topBadge: topBadge(for: pkg, in: offering),
                            onSelect: { viewModel.selectPackage(pkg.id) }
                        )
                    }
                }
                if let daily = dailyCostLabel {
                    Text(daily)
                        .font(AppTheme.typography.sized(12, weight: .regular))
                        .foregroundStyle(AppTheme.colors.textTertiary)
                        .frame(maxWidth: .infinity)
                        .padding(.top, AppTheme.spacing.xs)
                }
            }
        } else if case .loadingOfferings = viewModel.state {
            ProgressView()
                .frame(maxWidth: .infinity, minHeight: 120)
        }
    }

    private func topBadge(for pkg: PaywallPackage, in offering: PaywallOffering) -> String? {
        if let period = pkg.subscriptionPeriod, case .year(1) = period,
           let monthly = offering.packages.first(where: {
               if let p = $0.subscriptionPeriod, case .month(1) = p { return true }
               return false
           }),
           let percent = UpsellCopy.annualizedSavingsPercent(monthly: monthly, yearly: pkg) {
            return "省 \(percent)%"
        }
        return UpsellCopy.formatTrial(pkg.introductoryOffer)
    }

    private var dailyCostLabel: String? {
        guard let pkg = viewModel.selectedPackage else { return nil }
        return UpsellCopy.formatDailyCost(pkg)
    }

    // MARK: - Section header (中央 + 麦穗装饰)

    private var benefitsSectionHeaderTitle: String {
        "解锁超过 \(benefits.count) 个 Pro 功能"
    }

    private var graceSectionHeaderTitle: String {
        "续订后立即恢复"
    }

    private func sectionHeader(title: String) -> some View {
        HStack(spacing: AppTheme.spacing.sm) {
            Image(systemName: "leaf.fill")
                .rotationEffect(.degrees(-25))
                .foregroundStyle(AppTheme.colors.textTertiary.opacity(0.55))
                .font(.system(size: 13))
            Text(title)
                .font(AppTheme.typography.sectionHeader)
                .foregroundStyle(AppTheme.colors.title)
            Image(systemName: "leaf.fill")
                .scaleEffect(x: -1, y: 1)
                .rotationEffect(.degrees(25))
                .foregroundStyle(AppTheme.colors.textTertiary.opacity(0.55))
                .font(.system(size: 13))
        }
        .frame(maxWidth: .infinity)
        .padding(.top, AppTheme.spacing.lg)
    }

    // MARK: - Benefits (CardSection 包)

    private var benefitsSection: some View {
        VStack(spacing: 0) {
            ForEach(Array(benefits.enumerated()), id: \.element.id) { index, benefit in
                if index > 0 {
                    Divider()
                        .background(AppTheme.colors.hairline)
                        .padding(.leading, 56)
                }
                benefitRow(benefit)
            }
        }
        .padding(AppTheme.spacing.md)
        .background(AppTheme.colors.surface, in: RoundedRectangle(cornerRadius: AppTheme.radius.card))
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.radius.card)
                .stroke(AppTheme.colors.outline)
        )
    }

    private func benefitRow(_ benefit: UpsellCopy.Benefit) -> some View {
        HStack(alignment: .center, spacing: AppTheme.spacing.md) {
            Image(systemName: benefit.iconName)
                .font(.system(size: 17, weight: .regular))
                .foregroundStyle(AppTheme.colors.title)
                .frame(width: 28, height: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(benefit.displayText)
                    .font(AppTheme.typography.textStyle(.subheadline, weight: .semibold))
                    .foregroundStyle(AppTheme.colors.title)
                Text(benefit.subtitleText)
                    .font(AppTheme.typography.textStyle(.caption1))
                    .foregroundStyle(AppTheme.colors.body)
            }
            Spacer(minLength: 0)
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 18))
                .foregroundStyle(AppTheme.colors.pairAccent)
        }
        .padding(.vertical, AppTheme.spacing.sm)
    }

    // MARK: - Grace reassurance

    private var graceReassuranceSection: some View {
        VStack(spacing: 0) {
            graceRow(icon: "lock.shield.fill", title: "数据完整保留",
                     subtitle: "任务、纪念日、配对历史都安全",
                     isUrgent: false, isCritical: false)
            Divider().background(AppTheme.colors.hairline).padding(.leading, 56)
            graceRow(icon: "bolt.fill", title: "续订后立即恢复",
                     subtitle: "跨设备同步、全量历史立即可用",
                     isUrgent: false, isCritical: false)
            if let days = graceDaysRemaining {
                Divider().background(AppTheme.colors.hairline).padding(.leading, 56)
                graceRow(icon: "clock.badge.exclamationmark.fill",
                         title: days <= 1 ? "时间紧迫" : "请尽快续订",
                         subtitle: "\(days) 天后将自动降级为免费版",
                         isUrgent: true, isCritical: days <= 1)
            }
        }
        .padding(AppTheme.spacing.md)
        .background(AppTheme.colors.surface, in: RoundedRectangle(cornerRadius: AppTheme.radius.card))
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.radius.card)
                .stroke(AppTheme.colors.outline)
        )
    }

    private func graceRow(icon: String, title: String, subtitle: String,
                          isUrgent: Bool, isCritical: Bool) -> some View {
        let tint: Color = isCritical ? .red : (isUrgent ? .orange : AppTheme.colors.title)
        return HStack(alignment: .center, spacing: AppTheme.spacing.md) {
            Image(systemName: icon)
                .font(.system(size: 17, weight: .regular))
                .foregroundStyle(tint)
                .frame(width: 28, height: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(AppTheme.typography.textStyle(.subheadline, weight: .semibold))
                    .foregroundStyle(AppTheme.colors.title)
                Text(subtitle)
                    .font(AppTheme.typography.textStyle(.caption1))
                    .foregroundStyle(isUrgent ? tint.opacity(0.85) : AppTheme.colors.body)
            }
            Spacer(minLength: 0)
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 18))
                .foregroundStyle(isUrgent ? tint : AppTheme.colors.pairAccent)
        }
        .padding(.vertical, AppTheme.spacing.sm)
    }

    // MARK: - CTA + restore (内联在 ScrollView 末尾)

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
            .frame(maxWidth: .infinity, minHeight: 54)
            .background(
                Capsule()
                    .fill(ctaEnabled ? AppTheme.colors.title : AppTheme.colors.title.opacity(0.4))
            )
            .foregroundStyle(.white)
        }
        .buttonStyle(.plain)
        .disabled(!ctaEnabled)
        .accessibilityHint("订阅 Together Pro")
    }

    private var ctaLabel: String {
        if isGraceMode, viewModel.selectedPackage != nil {
            return "立即续订"
        }
        if viewModel.selectedPackage != nil {
            return "立即解锁"
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
        case .purchaseCancelled: "购买已取消"
        case .paymentPending: "等待批准"
        case .unknown: "出错了"
        case .entitlementNotReady: "购买已提交"
        case .nothingToRestore: "未检测到可恢复的购买记录"
        #if DEBUG
        case .debugOverrideMasksPro: "DEBUG: override 拦住购买结果"
        #endif
        }
    }

    private func errorBody(_ e: PaywallError) -> String {
        switch e {
        case .noOfferings: "请稍后再试"
        case .network: "请检查网络后重试"
        case .purchaseCancelled: "你可以随时重新选择套餐"
        case .paymentPending: "购买正在等待 Apple ID 批准"
        case .unknown: "请稍后重试；多次失败请联系我们"
        case .entitlementNotReady: "正在同步，请稍后回 Profile 确认"
        case .nothingToRestore: "请确认登录的 Apple ID 是否曾购买过 Together Pro"
        #if DEBUG
        case .debugOverrideMasksPro: "切到无 override 状态可验证真实解锁"
        #endif
        }
    }

    private func canRetry(_ e: PaywallError) -> Bool {
        switch e {
        case .noOfferings, .network, .unknown: true
        case .purchaseCancelled, .paymentPending, .entitlementNotReady, .nothingToRestore: false
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
        }
        .buttonStyle(.plain)
        .disabled(viewModel.isInFlight)
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
                    .background(Capsule().fill(AppTheme.colors.pairAccent.opacity(0.12)))
                    .foregroundStyle(AppTheme.colors.pairAccent)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, AppTheme.spacing.xl)
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

#Preview("Grace 7 天") {
    UpsellContent(
        displayKind: .trigger(.graceExpiring(daysRemaining: 7)),
        viewModel: makePreviewVM(loaded: true)
    )
}

#Preview("Grace 1 天") {
    UpsellContent(
        displayKind: .trigger(.graceExpiring(daysRemaining: 1)),
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
