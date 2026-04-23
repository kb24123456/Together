import Foundation
import RevenueCat

/// `RCClientProtocol` 的生产实现，封装 `Purchases` 单例。
///
/// 这是一层薄 pass-through：所有状态都住在 RC SDK 内部，本类无存储属性。
/// 真正的合并 / 缓存 / 竞态防护由 `PremiumGate` 负责；这里只做 RC → 项目类型的翻译。
final class RevenueCatClient: RCClientProtocol {
    nonisolated var isConfigured: Bool { Purchases.isConfigured }

    nonisolated func configure(publicSDKKey: String, appUserID: String) {
        Purchases.configure(withAPIKey: publicSDKKey, appUserID: appUserID)
    }

    func fetchCustomerInfo() async throws -> RCEntitlementSnapshot {
        let info = try await Purchases.shared.customerInfo()
        let entitlement = info.entitlements[RevenueCatConfig.entitlementIdentifier]
        return RCEntitlementSnapshot(
            isProActive: entitlement?.isActive ?? false,
            proExpirationDate: entitlement?.expirationDate
        )
    }

    func logIn(appUserID: String) async throws {
        _ = try await Purchases.shared.logIn(appUserID)
    }

    func logOut() async throws {
        _ = try await Purchases.shared.logOut()
    }
}
