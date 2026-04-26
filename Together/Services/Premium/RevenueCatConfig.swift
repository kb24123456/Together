import Foundation

/// RevenueCat 相关常量。所有引用集中到此，避免魔法字符串。
///
/// DEBUG build 用 RC Project sandbox key（可搭配 Sandbox Apple ID 走假订阅流程）；
/// Release build 用 App-specific production key（从 RC Dashboard →
/// Apps → iOS App → API Keys 复制）。Public key 设计上可安全硬编码（类似 Supabase
/// anon key），不是机密，真正的服务端凭证（P8）在 RC Dashboard 侧配置。
enum RevenueCatConfig {
    /// 发布前必须被替换掉的占位值；release build 启动时会 precondition 失败阻断发布。
    private static let productionKeyPlaceholder = "appl_PLACEHOLDER_PRODUCTION_KEY"

    static let publicSDKKey: String = {
        #if DEBUG
        return "test_vSgWSmgUqnLiCKZvjDshWoFySiT"
        #else
        return "appl_koHbDHsCMItIBGguDIqkaaBtZTw"
        #endif
    }()

    /// Release build 里占位 key 未替换 = 立即失败，避免把废 build 推上 TestFlight。
    /// 调用方：`RevenueCatConfig.assertProductionKeyConfigured()`，在 AppDelegate
    /// 或 `configurePremiumGate` 里 eagerly 触发一次即可。
    static func assertProductionKeyConfigured() {
        #if !DEBUG
        precondition(
            publicSDKKey != productionKeyPlaceholder,
            "RevenueCatConfig.publicSDKKey still holds the production placeholder — "
            + "set the real appl_ key from RC Dashboard before cutting a release build."
        )
        #endif
    }

    /// Entitlement 标识符，必须和 RC Dashboard 中创建的 entitlement ID 完全一致。
    static let entitlementIdentifier: String = "pro"
}
