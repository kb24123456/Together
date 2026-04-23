import Foundation

/// RevenueCat 相关常量。所有引用集中到此，避免魔法字符串。
enum RevenueCatConfig {
    /// Public SDK key。Public key 设计上可安全硬编码（类似 Supabase anon key），
    /// 不是机密 — 真正的服务端凭证（P8）在 RC Dashboard 侧配置。
    ///
    /// 当前值是 RC Project `9691e26b` 的 iOS sandbox key。正式提交 App Store 前
    /// 需要切换为 production key（RC 区分 sandbox / production）。
    static let publicSDKKey: String = "test_vSgWSmgUqnLiCKZvjDshWoFySiT"

    /// Entitlement 标识符，必须和 RC Dashboard 中创建的 entitlement ID 完全一致。
    static let entitlementIdentifier: String = "pro"
}
