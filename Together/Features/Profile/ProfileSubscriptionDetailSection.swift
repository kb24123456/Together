import SwiftUI

/// Profile → Together Pro 已激活时的详情区。处理 3 种 PremiumStatus 渲染：
/// - `.pro(.subscription)` → 标题 + "有效期至 ..." + ManageSubscriptionLink
/// - `.pro(.grant)` → 标题 + "由 Together 团队赠送 · 终身有效"
/// - `.gracePeriod` → 警告区 + "剩 N 天" + 续订按钮 + ManageSubscriptionLink
///
/// pendingApproval 由调用方（ProfileSubscriptionView）外层处理，不在本 view 内。
struct ProfileSubscriptionDetailSection: View {
    let status: PremiumStatus
    let onRequestRenewal: (Int) -> Void

    var body: some View {
        Group {
            switch status {
            case .pro(.subscription, let expiresAt):
                proSubscriptionView(expiration: expiresAt)
            case .pro(.grant, _):
                proGrantView
            case .gracePeriod:
                graceView
            case .free, .unknown:
                EmptyView()
            }
        }
        .transition(.opacity.combined(with: .scale(scale: 0.95)))
        .animation(.easeInOut(duration: 0.3), value: status)
    }

    // MARK: - Sub-views

    private func proSubscriptionView(expiration: Date?) -> some View {
        VStack(spacing: AppTheme.spacing.md) {
            crownHeader
            Text(Self.expirationText(expiration))
                .font(AppTheme.typography.sized(13))
                .foregroundStyle(AppTheme.colors.textTertiary)
                .multilineTextAlignment(.center)
            ManageSubscriptionLink()
                .padding(.top, AppTheme.spacing.sm)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, AppTheme.spacing.xl)
    }

    private var proGrantView: some View {
        VStack(spacing: AppTheme.spacing.md) {
            crownHeader
            Text("由 Together 团队赠送 · 终身有效")
                .font(AppTheme.typography.sized(13))
                .foregroundStyle(AppTheme.colors.textTertiary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, AppTheme.spacing.xl)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, AppTheme.spacing.xl)
    }

    private var graceView: some View {
        let daysRemaining = status.gracePeriodDaysRemaining() ?? 1
        return VStack(alignment: .leading, spacing: AppTheme.spacing.sm) {
            HStack(spacing: AppTheme.spacing.xs) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                Text("订阅已到期")
                    .font(AppTheme.typography.sized(15, weight: .semibold))
                    .foregroundStyle(AppTheme.colors.title)
            }
            Text("剩 \(daysRemaining) 天可看全历史，期满后将自动降级为 Free")
                .font(AppTheme.typography.sized(13))
                .foregroundStyle(AppTheme.colors.textTertiary)
            Button("立即续订") {
                onRequestRenewal(daysRemaining)
            }
            .buttonStyle(.borderedProminent)
            .tint(AppTheme.colors.pairAccent)
            .padding(.top, AppTheme.spacing.xs)
            ManageSubscriptionLink()
                .padding(.top, AppTheme.spacing.xs)
        }
        .padding(AppTheme.spacing.md)
        .background(
            RoundedRectangle(cornerRadius: AppTheme.radius.md, style: .continuous)
                .fill(.orange.opacity(0.1))
        )
        .padding(.horizontal, AppTheme.spacing.md)
        .padding(.vertical, AppTheme.spacing.lg)
    }

    private var crownHeader: some View {
        VStack(spacing: AppTheme.spacing.sm) {
            Image(systemName: "crown.fill")
                .font(AppTheme.typography.sized(36, weight: .semibold))
                .foregroundStyle(AppTheme.colors.pairAccent)
            Text("Together Pro · 已激活")
                .font(AppTheme.typography.sized(20, weight: .bold))
                .foregroundStyle(AppTheme.colors.title)
        }
    }

    // MARK: - Static helpers (testable)

    /// `.pro(.subscription)` 时的副标题文案。expiresAt nil 时 fallback "订阅有效"
    /// （spec § 2.1 R26：subscription 来源理论应有 expirationDate；nil 视作异常防御）。
    static func expirationText(_ date: Date?) -> String {
        guard let date else { return "订阅有效" }
        return "有效期至 \(date.formatted(.dateTime.year().month().day()))"
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
    expiresAt: Calendar.current.date(byAdding: .month, value: 11, to: .now)
)
private let previewGrant: PremiumStatus = .pro(source: .grant, expiresAt: nil)
private let previewGrace: PremiumStatus = .gracePeriod(
    originalExpiry: Calendar.current.date(byAdding: .day, value: -1, to: .now)!,
    logbookFullUntil: Calendar.current.date(byAdding: .day, value: 7, to: .now)!
)

#Preview("Pro · subscription") {
    ProfileSubscriptionDetailSection(status: previewSubscription, onRequestRenewal: { _ in })
}

#Preview("Pro · grant") {
    ProfileSubscriptionDetailSection(status: previewGrant, onRequestRenewal: { _ in })
}

#Preview("Grace period · 7 days") {
    ProfileSubscriptionDetailSection(status: previewGrace, onRequestRenewal: { _ in })
}
#endif
