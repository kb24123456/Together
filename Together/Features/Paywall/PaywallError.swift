import Foundation
import RevenueCat

/// 付费墙 UI 层错误。生产错误（RC SDK / 网络）通过 `init(from:)` 翻译；内部 state 错误由 VM 显式构造。
///
/// Spec § 3.3 定义了每个 case 的 inline UI 表现（不走 alert，除 `.pendingApproval` 走关 sheet）。
enum PaywallError: Error, Equatable, Sendable {
    /// `offerings.current == nil`——RC Dashboard 未 mark current。
    case noOfferings
    /// 网络 / 离线。
    case network
    /// SDK 边缘路径抛出了用户取消购买。正常路径应返回 `.cancelled` outcome。
    case purchaseCancelled
    /// SDK 边缘路径抛出了等待批准。正常路径应返回 `.pending` outcome。
    case paymentPending
    /// 未归类的 RC / SDK 错误。
    case unknown
    /// 购买真成功但 `PremiumGate.refresh()` 后 `isPremium` 仍 false（RC 最终一致延迟）。
    case entitlementNotReady
    /// 仅 restore 路径：无可恢复的订阅。
    case nothingToRestore
    #if DEBUG
    /// DEBUG override 强制 Free，购买真成功但 override 拦着 `isPremium`——开发调试提示。
    case debugOverrideMasksPro
    #endif

    /// 从 `Purchases.shared.purchase(package:)` / `restorePurchases()` 抛出的 Error 翻译为 UI case。
    /// 未分类错误归 `.unknown`。
    ///
    /// 正常路径下，cancel / Ask-to-Buy 通过 `PaywallPurchaseOutcome.cancelled` / `.pending` 返回
    /// 而不是抛错；但 RC SDK 某些旧桥接路径仍可能抛 `.purchaseCancelledError` /
    /// `.paymentPendingError`，本 init 仍显式区分，交由 VM 映射回非错误状态。
    init(from error: Error) {
        let nsError = error as NSError
        if let code = ErrorCode(rawValue: nsError.code) {
            switch code {
            case .networkError, .offlineConnectionError:
                self = .network
            case .purchaseCancelledError:
                self = .purchaseCancelled
            case .paymentPendingError:
                self = .paymentPending
            default:
                self = .unknown
            }
        } else if nsError.domain == NSURLErrorDomain {
            self = .network
        } else {
            self = .unknown
        }
    }
}
