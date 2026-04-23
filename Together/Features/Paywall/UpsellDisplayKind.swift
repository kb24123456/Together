import Foundation

/// Paywall UI 显示层的统一契约。`RootPaywallPresentation.Kind`（quota / lapse）和 Profile
/// 主动入口（无 trigger）都映射到本 enum；`UpsellContent` 只依赖此类型，不耦合合并器。
enum UpsellDisplayKind: Equatable, Sendable {
    /// 配额拦截 → 按 `UpsellTrigger` 差异化 hero 文案
    case trigger(UpsellTrigger)
    /// Pro → Free 到期 → 复用 `.crossDeviceSync` hero + 顶部 "订阅已到期" banner
    case lapse(PremiumLapseNotice)
    /// Profile 主动升级 → fallback hero（"升级 Together Pro · 解锁全部 Pro 功能"）
    case generic
}
