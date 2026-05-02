import Foundation

/// 会员状态。由 `PremiumGate` 合并 RC 订阅与 Supabase white-list grants 得出。
///
/// - `.unknown` 尚未 bootstrap（启动中）
/// - `.free` 无任何会员权益
/// - `.pro(source:, expiresAt:)` 活跃会员；`expiresAt == nil` 即永久
/// - `.gracePeriod(...)` 订阅或 grant 最近 14 天内过期；Logbook 仍展示全历史
enum PremiumStatus: Equatable, Codable, Sendable {
    case unknown
    case free
    case pro(source: PremiumSource, expiresAt: Date?)
    case gracePeriod(originalExpiry: Date, logbookFullUntil: Date)

    enum PremiumSource: String, Codable, Sendable {
        case subscription
        case grant
    }

    /// 是否拥有当前有效的 Pro 权益。
    ///
    /// Grace 期不再被视为完整 Pro：它只保留 Logbook 全历史访问，
    /// 不应继续放行跨设备同步、项目/纪念日超额创建等 Pro 功能。
    var isPremium: Bool {
        switch self {
        case .pro: return true
        case .unknown, .free, .gracePeriod: return false
        }
    }

    var isProOrGracePeriod: Bool {
        switch self {
        case .pro, .gracePeriod: return true
        case .unknown, .free: return false
        }
    }

    /// Logbook 是否允许展示全历史。Pro 和 gracePeriod 均允许。
    var allowsFullLogbook: Bool {
        switch self {
        case .pro, .gracePeriod: return true
        case .unknown, .free: return false
        }
    }
}
