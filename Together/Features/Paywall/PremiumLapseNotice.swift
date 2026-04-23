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

// MARK: - DedupKey helper

extension PremiumLapseNotice {
    /// 计算 dedupKey。有真实 `expiredAt` 时按秒精确；没有时按天 fallback（避免同日反复弹）。
    /// spec § 2.5。
    static func dedupKey(expiredAt: Date?, detectedAt: Date) -> String {
        if let d = expiredAt {
            return "lapse:\(Int(d.timeIntervalSince1970))"
        }
        let day = Int(detectedAt.timeIntervalSince1970 / 86_400)
        return "lapse:fallback:\(day)"
    }
}

#if DEBUG
extension PremiumLapseNotice {
    /// DEBUG 手动触发 lapse sheet 专用。dedupKey 用 UUID 保证 `LapseAcknowledgedStore.contains`
    /// 永不命中，可反复点按钮测 UI。
    static func debugSample(now: Date) -> PremiumLapseNotice {
        PremiumLapseNotice(
            entitlementExpiredAt: now.addingTimeInterval(-86_400),
            detectedAt: now,
            dedupKey: "lapse:debug:\(UUID().uuidString)"
        )
    }
}
#endif
