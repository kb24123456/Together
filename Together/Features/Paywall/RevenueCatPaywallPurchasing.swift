import Foundation
import RevenueCat

/// `PaywallPurchasingProtocol` 的生产实现，包一层 `Purchases.shared`。
///
/// 选 actor 的原因：`packageCache` 是可变状态，`loadOfferings` 并发调用要线程安全；
/// 所有对外方法天然 `async`，actor 隔离零成本。
///
/// Phase 2 `RevenueCatClient` 是 `final class` + 无状态薄 pass-through；本 class 有状态，
/// 不对齐成 `final class`，以免引入 `@unchecked Sendable` 的危险。
actor RevenueCatPaywallPurchasing: PaywallPurchasingProtocol {

    private var packageCache: [String: Package] = [:]

    init() {}

    func loadOfferings() async throws -> PaywallOffering {
        // RC SDK fatal error guard: 未登录 / Supabase session 未建立时 Purchases 还没
        // configure，调 .shared 会 SDK 内部 fatal。提前 throw `.noOfferings`，paywall
        // UI 走"加载失败"路径，用户不会闪退。
        guard Purchases.isConfigured else { throw PaywallError.noOfferings }
        let offerings = try await Purchases.shared.offerings()
        guard let current = offerings.current else {
            throw PaywallError.noOfferings
        }
        packageCache.removeAll()
        let mapped: [PaywallPackage] = current.availablePackages.map { pkg in
            packageCache[pkg.identifier] = pkg
            return Self.translate(package: pkg)
        }
        return PaywallOffering(offeringID: current.identifier, packages: mapped)
    }

    func purchase(packageID: String) async throws -> PaywallPurchaseOutcome {
        guard Purchases.isConfigured else { throw PaywallError.unknown }
        guard let pkg = packageCache[packageID] else {
            // packageID 过期（未调 loadOfferings 就 purchase，或 offering 已被替换）——
            // 不应发生于正常 VM 流程；fallback 为 unknown 错误，OSLog 定位
            throw PaywallError.unknown
        }
        let result = try await Purchases.shared.purchase(package: pkg)
        if result.userCancelled { return .cancelled }
        let ent = result.customerInfo.entitlements[RevenueCatConfig.entitlementIdentifier]
        if ent?.isActive == true { return .success }
        // transaction 落地但 entitlement 未激活：典型 Ask to Buy / SCA pending 路径
        return .pending
    }

    func restorePurchases() async throws -> PaywallPurchaseOutcome {
        guard Purchases.isConfigured else { throw PaywallError.unknown }
        let info = try await Purchases.shared.restorePurchases()
        let ent = info.entitlements[RevenueCatConfig.entitlementIdentifier]
        return ent?.isActive == true ? .success : .nothingToRestore
    }

    // MARK: - RC → 本地类型 Translation

    private static func translate(package: Package) -> PaywallPackage {
        let product = package.storeProduct
        return PaywallPackage(
            id: package.identifier,
            productID: product.productIdentifier,
            localizedTitle: product.localizedTitle,
            localizedPriceString: product.localizedPriceString,
            price: product.price,
            currencyCode: product.currencyCode ?? "",
            subscriptionPeriod: product.subscriptionPeriod.map(translate(period:)),
            introductoryOffer: product.introductoryDiscount.map(translate(discount:))
        )
    }

    private static func translate(period: SubscriptionPeriod) -> PaywallPeriod {
        switch period.unit {
        case .day: .day(period.value)
        case .week: .week(period.value)
        case .month: .month(period.value)
        case .year: .year(period.value)
        @unknown default: .day(period.value)
        }
    }

    private static func translate(discount: StoreProductDiscount) -> PaywallIntroOffer {
        let period = translate(period: discount.subscriptionPeriod)
        let price: Decimal = discount.paymentMode == .freeTrial ? .zero : discount.price
        return PaywallIntroOffer(period: period, price: price)
    }
}
