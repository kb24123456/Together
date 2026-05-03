import Foundation

/// Subscription status for the Pro entry row in Profile.
///
/// Rendered by `ProfileProEntryRow`. When the user subscribes, the row persists
/// and its subtitle transforms — it does NOT disappear. This avoids the
/// industry-reported "ghost upgrade CTA after paying" anti-pattern.
enum ProSubscriptionStatus: Equatable {
    case free
    case trial(daysLeft: Int, renewalDate: Date)
    case active(renewalDate: Date)
    /// Ask to Buy / SCA 家长审批中。spec § 2.10 / § 10 ③ 决策：立即关 sheet 后 Profile
    /// 子标题提示"等待家长审批"，避免用户以为付款失败。
    case pendingApproval

    /// Short, single-line subtitle copy for the Pro entry row.
    /// Kept under 40 Chinese chars to avoid wrapping on narrow devices.
    var subtitleText: String {
        switch self {
        case .free:
            return "跨设备同步、更多项目、全量历史"
        case let .trial(daysLeft, renewalDate):
            return "试用剩余 \(daysLeft) 天 · \(Self.shortDateFormatter.string(from: renewalDate)) 续费"
        case let .active(renewalDate):
            return "订阅中 · 下次续费 \(Self.shortDateFormatter.string(from: renewalDate))"
        case .pendingApproval:
            return "等待家长审批 · 批准后自动生效"
        }
    }

    /// VoiceOver suffix for the Pro row. Describes the subscription state explicitly.
    var accessibilityStateLabel: String {
        switch self {
        case .free:
            return "升级订阅"
        case let .trial(daysLeft, _):
            return "试用中，剩余 \(daysLeft) 天"
        case let .active(renewalDate):
            return "订阅中，下次续费 \(Self.shortDateFormatter.string(from: renewalDate))"
        case .pendingApproval:
            return "购买提交中，等待家长审批"
        }
    }

    private static let shortDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "yyyy 年 M 月 d 日"
        return f
    }()
}
