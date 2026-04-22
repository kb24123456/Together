import Foundation

/// `PremiumGate` 对 RevenueCat 的访问抽象。生产实现由 `RevenueCatClient` 提供，
/// 测试实现由 stub 提供。
///
/// 抽象的目的：PremiumGate 的合并算法可以在不加载真实 RC SDK 的情况下被单元测试。
protocol RCClientProtocol: Sendable {
    /// 是否已完成 configure。
    var isConfigured: Bool { get }

    /// 首次 configure（仅应在未 configured 时调用）。
    func configure(publicSDKKey: String, appUserID: String)

    /// 查询当前 appUserID 的 entitlement 状态。
    /// 失败时抛错（网络问题、未 configure 等）。
    func fetchCustomerInfo() async throws -> RCEntitlementSnapshot

    /// 切换到新的 appUserID（登录新账号）。
    func logIn(appUserID: String) async throws

    /// 清除当前用户关联（登出）。
    func logOut() async throws
}

/// 从 RevenueCat `CustomerInfo` 提炼出的 PremiumGate 关心的最小信息。
/// 避免让 PremiumGate 直接依赖 RevenueCat SDK 的类型。
struct RCEntitlementSnapshot: Equatable, Sendable {
    /// entitlement["pro"].isActive
    let isProActive: Bool
    /// entitlement["pro"].expirationDate（永久订阅为 nil）
    let proExpirationDate: Date?
}
