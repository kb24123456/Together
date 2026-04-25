import SwiftUI

/// Profile → Together Pro 已激活时的详情区。
/// 设计 DNA（Wave 4）：和 paywall (UpsellContent) 完全一致的 Doit!Pro 风格 — Together 色板。
/// - BrandIcon hero + 大字「Together Pro」 + 状态副标题
/// - 当前套餐卡：**黑底白字 + 顶部 neon 渐变光晕**（标记"激活中"，复用 paywall plan 卡选中态视觉）
/// - 中央 leaf · "你已解锁 N 个 Pro 功能" · leaf 装饰章节
/// - 白色 surface 大卡片包 benefits 列表（icon 黑色 + 右 pairAccent ✓）
/// - Grace 模式：reassurance 列表（橙/红 urgency）+ 黑色 capsule 续订 CTA
/// - 管理：白色 CardSection 包 ManageSubscriptionLink
struct ProfileSubscriptionDetailSection: View {
    let status: PremiumStatus
    let onRequestRenewal: (Int) -> Void

    private var benefits: [UpsellCopy.Benefit] {
        UpsellCopy.benefits(highlightedBy: .generic)
    }

    private var isGraceMode: Bool {
        if case .gracePeriod = status { return true }
        return false
    }

    private var graceDaysRemaining: Int? {
        guard case .gracePeriod = status else { return nil }
        return status.gracePeriodDaysRemaining()
    }

    var body: some View {
        switch status {
        case .pro, .gracePeriod:
            VStack(spacing: AppTheme.spacing.lg) {
                heroSection
                planStatusCard

                if isGraceMode {
                    sectionHeader(title: "续订后立即恢复")
                    graceReassuranceSection
                    renewalCTA
                        .padding(.top, AppTheme.spacing.md)
                } else {
                    sectionHeader(title: "你已解锁 \(benefits.count) 个 Pro 功能")
                    benefitsSection
                }

                manageSection
                    .padding(.top, AppTheme.spacing.sm)
            }
            .padding(.horizontal, AppTheme.spacing.xl)
            .padding(.top, AppTheme.spacing.xl)
            .padding(.bottom, AppTheme.spacing.xxl)
            .frame(maxWidth: .infinity, alignment: .leading)
            .transition(.opacity)
            .animation(AppTheme.motion.micro, value: status)
        case .free, .unknown:
            EmptyView()
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
            Text("Together Pro")
                .font(AppTheme.typography.display)
                .foregroundStyle(AppTheme.colors.title)
            Text(statusSubtitle)
                .font(AppTheme.typography.textStyle(.subheadline))
                .foregroundStyle(statusSubtitleColor)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
    }

    private var statusSubtitle: String {
        switch status {
        case .pro(.subscription, let expiresAt):
            if let expiresAt {
                let formatter = expiresAt.formatted(.dateTime.month().day().locale(Locale(identifier: "zh_Hans")))
                return "订阅活跃 · \(formatter) 续费"
            }
            return "订阅活跃"
        case .pro(.grant, _):
            return "终身有效 · 团队赠送"
        case .gracePeriod:
            let days = graceDaysRemaining ?? 1
            return "订阅已到期 · 还剩 \(days) 天"
        case .free, .unknown:
            return ""
        }
    }

    private var statusSubtitleColor: Color {
        switch status {
        case .gracePeriod:
            let days = graceDaysRemaining ?? 1
            return days <= 1 ? .red : .orange
        default:
            return AppTheme.colors.body
        }
    }

    // MARK: - 当前套餐卡（Doit Pro plan 卡风：黑底白字 + neon strip）

    private var planStatusCard: some View {
        ZStack(alignment: .top) {
            VStack(spacing: AppTheme.spacing.xxs) {
                Spacer(minLength: AppTheme.spacing.sm)
                Text(planLabel)
                    .font(AppTheme.typography.cardLabel)
                    .foregroundStyle(.white.opacity(0.85))
                Text(planTitle)
                    .font(AppTheme.typography.priceXLarge)
                    .foregroundStyle(.white)
                    .minimumScaleFactor(0.7)
                    .lineLimit(1)
                Text(planSubtitle)
                    .font(AppTheme.typography.cardCaption)
                    .foregroundStyle(.white.opacity(0.7))
                    .multilineTextAlignment(.center)
                Spacer(minLength: AppTheme.spacing.sm)
            }
            .frame(maxWidth: .infinity, minHeight: 116)
            .background(
                RoundedRectangle(cornerRadius: AppTheme.radius.card, style: .continuous)
                    .fill(AppTheme.colors.title)
            )

            neonStrip
                .padding(.horizontal, AppTheme.spacing.xs)
                .allowsHitTesting(false)
        }
    }

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

    private var planLabel: String {
        switch status {
        case .pro(.subscription, _): return "当前订阅"
        case .pro(.grant, _): return "永久会员"
        case .gracePeriod: return "订阅已到期"
        case .free, .unknown: return ""
        }
    }

    private var planTitle: String {
        switch status {
        case .pro(.subscription, _): return "Together Pro"
        case .pro(.grant, _): return "Lifetime"
        case .gracePeriod: return "Together Pro"
        case .free, .unknown: return ""
        }
    }

    private var planSubtitle: String {
        switch status {
        case .pro(.subscription, let expiresAt):
            if let expiresAt {
                return "下次续费 \(Self.expirationText(expiresAt))"
            }
            return "订阅有效"
        case .pro(.grant, _):
            return "团队赠送 · 永不过期"
        case .gracePeriod:
            let days = graceDaysRemaining ?? 1
            return "\(days) 天后将自动降级为免费版"
        case .free, .unknown: return ""
        }
    }

    // MARK: - Section header（中央 leaf 装饰）

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

    // MARK: - Benefits (white surface card)

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

    // MARK: - Grace reassurance (white surface card)

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

    // MARK: - 续订 CTA（黑色 capsule，与 paywall 一致）

    @ViewBuilder
    private var renewalCTA: some View {
        if case .gracePeriod = status {
            let days = graceDaysRemaining ?? 1
            Button {
                onRequestRenewal(days)
            } label: {
                Text("立即续订")
                    .font(AppTheme.typography.sized(16, weight: .semibold))
                    .frame(maxWidth: .infinity, minHeight: 54)
                    .background(
                        Capsule().fill(AppTheme.colors.title)
                    )
                    .foregroundStyle(.white)
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Manage CardSection

    private var manageSection: some View {
        VStack(spacing: 0) {
            ManageSubscriptionLink()
                .font(AppTheme.typography.textStyle(.subheadline, weight: .medium))
                .foregroundStyle(AppTheme.colors.title)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, AppTheme.spacing.sm)
        }
        .padding(.horizontal, AppTheme.spacing.md)
        .padding(.vertical, AppTheme.spacing.xs)
        .background(AppTheme.colors.surface, in: RoundedRectangle(cornerRadius: AppTheme.radius.card))
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.radius.card)
                .stroke(AppTheme.colors.outline)
        )
    }

    // MARK: - Static helpers (testable)

    /// `.pro(.subscription)` 时的副标题文案。expiresAt nil 时 fallback "订阅有效"
    /// （spec § 2.1 R26：subscription 来源理论应有 expirationDate；nil 视作异常防御）。
    static func expirationText(_ date: Date?) -> String {
        guard let date else { return "订阅有效" }
        return date.formatted(.dateTime.year().month().day())
    }
}

extension PremiumStatus {
    /// `.gracePeriod` 时返回剩余天数（min 1）；其他态返回 nil。
    /// Calendar / now DI 用于测试稳定（避免 device timezone flake）。
    /// 共享给 GracePeriodBanner（Task 8）复用。
    func gracePeriodDaysRemaining(
        now: Date = .now,
        calendar: Calendar = .current
    ) -> Int? {
        guard case .gracePeriod(_, let until) = self else { return nil }
        return max(1, calendar.dateComponents([.day], from: now, to: until).day ?? 1)
    }
}

#if DEBUG
private let previewSubscription: PremiumStatus = .pro(
    source: .subscription,
    expiresAt: Calendar.current.date(byAdding: .day, value: 30, to: .now)
)
private let previewGrant: PremiumStatus = .pro(source: .grant, expiresAt: nil)
private let previewGrace7: PremiumStatus = .gracePeriod(
    originalExpiry: Calendar.current.date(byAdding: .day, value: -1, to: .now)!,
    logbookFullUntil: Calendar.current.date(byAdding: .day, value: 7, to: .now)!
)
private let previewGrace1: PremiumStatus = .gracePeriod(
    originalExpiry: Calendar.current.date(byAdding: .day, value: -7, to: .now)!,
    logbookFullUntil: Calendar.current.date(byAdding: .day, value: 1, to: .now)!
)

#Preview("订阅 30 天") {
    ZStack {
        GradientGridBackground().ignoresSafeArea()
        ScrollView {
            ProfileSubscriptionDetailSection(status: previewSubscription, onRequestRenewal: { _ in })
        }
    }
}

#Preview("永久白名单") {
    ZStack {
        GradientGridBackground().ignoresSafeArea()
        ScrollView {
            ProfileSubscriptionDetailSection(status: previewGrant, onRequestRenewal: { _ in })
        }
    }
}

#Preview("剩 7 天") {
    ZStack {
        GradientGridBackground().ignoresSafeArea()
        ScrollView {
            ProfileSubscriptionDetailSection(status: previewGrace7, onRequestRenewal: { _ in })
        }
    }
}

#Preview("剩 1 天") {
    ZStack {
        GradientGridBackground().ignoresSafeArea()
        ScrollView {
            ProfileSubscriptionDetailSection(status: previewGrace1, onRequestRenewal: { _ in })
        }
    }
}
#endif
