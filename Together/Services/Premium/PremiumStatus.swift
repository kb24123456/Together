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

    var isPremium: Bool {
        switch self {
        case .pro, .gracePeriod: return true
        case .unknown, .free: return false
        }
    }

    /// Logbook 是否允许展示全历史。Pro 和 gracePeriod 均允许。
    var allowsFullLogbook: Bool { isPremium }
}
