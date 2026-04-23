import Foundation

/// Pro → Free 运行时翻转的一次性通知载体。由 `AppContext.handlePremiumStatusChange`
/// 在检测到 lapse 时构造，通过 `RootPaywallPresentation.requestLapse` 推到 UI。
///
/// `dedupKey` 持久化在 `LapseAcknowledgedStore` 里（UserDefaults），保证同一次到期不会
/// 在多次冷启动重复弹 sheet。DEBUG 下 `debugSample` 用 UUID 生成独一 key 绕过去重。
struct PremiumLapseNotice: Identifiable, Equatable, Sendable {
    /// 从 `PremiumGate.latestEntitlementExpiration` 读；可能 nil（首次 bootstrap 未获取 RC snapshot）
    let entitlementExpiredAt: Date?
    /// 本地检测到 lapse 的时间（仅用于 fallback dedup key）
    let detectedAt: Date
    let dedupKey: String

    var id: String { dedupKey }
}
