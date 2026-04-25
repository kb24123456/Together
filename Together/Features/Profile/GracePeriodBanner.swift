import SwiftUI

/// Logbook 顶部 grace period 横幅。整行 Button，VoiceOver combine。
/// 不可关闭——宽限期 14 天的硬时间窗，dismiss 会让用户错过续订挽回路径。
///
/// `now` / `calendar` DI 用于测试稳定（避免 device timezone flake）。
struct GracePeriodBanner: View {
    let logbookFullUntil: Date
    var now: Date = .now
    var calendar: Calendar = .current
    let onTap: (Int) -> Void

    /// 剩余天数算法。提为 static 便于单测；与 `PremiumStatus.gracePeriodDaysRemaining` 等价。
    static func daysRemaining(now: Date, until: Date, calendar: Calendar = .current) -> Int {
        max(1, calendar.dateComponents([.day], from: now, to: until).day ?? 1)
    }

    private var daysRemaining: Int {
        Self.daysRemaining(now: now, until: logbookFullUntil, calendar: calendar)
    }

    var body: some View {
        Button {
            onTap(daysRemaining)
        } label: {
            HStack(spacing: AppTheme.spacing.sm) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                Text("订阅已到期 · 剩 \(daysRemaining) 天可看全历史")
                    .font(AppTheme.typography.sized(13, weight: .medium))
                    .foregroundStyle(AppTheme.colors.title)
                    .multilineTextAlignment(.leading)
                Spacer(minLength: AppTheme.spacing.xs)
                Image(systemName: "chevron.right")
                    .font(AppTheme.typography.sized(12, weight: .semibold))
                    .foregroundStyle(AppTheme.colors.textTertiary)
            }
            .padding(.horizontal, AppTheme.spacing.md)
            .padding(.vertical, AppTheme.spacing.sm)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.orange.opacity(0.15))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("订阅已到期，剩 \(daysRemaining) 天可看全历史")
        .accessibilityHint("双击立即续订")
        .accessibilityAddTraits(.isButton)
    }
}

#if DEBUG
#Preview("7 days remaining") {
    GracePeriodBanner(
        logbookFullUntil: Calendar.current.date(byAdding: .day, value: 7, to: .now)!,
        onTap: { _ in }
    )
    .padding()
}

#Preview("1 day remaining") {
    GracePeriodBanner(
        logbookFullUntil: Calendar.current.date(byAdding: .day, value: 1, to: .now)!,
        onTap: { _ in }
    )
    .padding()
}
#endif
