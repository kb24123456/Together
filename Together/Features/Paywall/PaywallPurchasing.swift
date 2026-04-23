import Foundation

/// Session A 付费墙 ViewModel 对 RevenueCat 的访问抽象。
///
/// 与 Phase 2 `RCClientProtocol` 刻意分离：后者只负责 PremiumGate 拉 entitlement 快照，
/// 本协议负责 offerings 展示 + 购买 + 恢复——生命周期和调用方不同。
///
/// 生产实现：`RevenueCatPaywallPurchasing`（Task 2）；测试 stub：`actor StubPaywallPurchasing`。
protocol PaywallPurchasingProtocol: Sendable {
    /// 读 `Purchases.shared.offerings().current`。为 nil 时抛 `PaywallError.noOfferings`。
    func loadOfferings() async throws -> PaywallOffering

    /// 购买指定 package。`packageID` 必须来自最近一次 `loadOfferings` 返回的 `PaywallPackage.id`；
    /// 实现不保证跨 `loadOfferings` 调用的 packageID 仍然有效。
    func purchase(packageID: String) async throws -> PaywallPurchaseOutcome

    /// 调用 `Purchases.shared.restorePurchases()`；检查 entitlement `isActive` 判定结果。
    func restorePurchases() async throws -> PaywallPurchaseOutcome
}

// MARK: - 数据模型（全部 Sendable / Equatable，方便 UI 测试断言）

struct PaywallOffering: Sendable, Equatable {
    let offeringID: String
    let packages: [PaywallPackage]

    func package(id: String) -> PaywallPackage? {
        packages.first { $0.id == id }
    }
}

struct PaywallPackage: Identifiable, Sendable, Equatable {
    /// RevenueCat package identifier（如 `"$rc_monthly"` / `"$rc_annual"`）。
    let id: String
    /// App Store Connect Product ID。
    let productID: String
    /// `StoreProduct.localizedTitle`。
    let localizedTitle: String
    /// `StoreProduct.localizedPriceString`，不含周期后缀（周期后缀由 `UpsellCopy.formatPriceLine` 拼）。
    let localizedPriceString: String
    let price: Decimal
    let currencyCode: String
    /// 订阅周期；非订阅（一次性购买 / 终身）为 nil。
    let subscriptionPeriod: PaywallPeriod?
    /// 介绍期 offer；`isFreeTrial == true` 为免费试用。
    let introductoryOffer: PaywallIntroOffer?
}

enum PaywallPeriod: Sendable, Equatable {
    case day(Int)
    case week(Int)
    case month(Int)
    case year(Int)
}

struct PaywallIntroOffer: Sendable, Equatable {
    let period: PaywallPeriod
    /// `0` 代表免费试用。
    let price: Decimal

    var isFreeTrial: Bool { price == 0 }
}

/// 购买 / 恢复的结果。错误通过 `throws PaywallError` 传递，本 enum 仅涵盖非错误路径。
enum PaywallPurchaseOutcome: Sendable, Equatable {
    /// 购买成功 / entitlement 已激活。
    case success
    /// 用户在系统弹窗点"取消"。
    case cancelled
    /// Ask to Buy / SCA 等异步批准，RC SDK 会在批准后通过 `updatedCustomerInfo` 回调。
    case pending
    /// 仅 `restorePurchases` 返回：RC 成功调用但 entitlement 未激活。
    case nothingToRestore
}
