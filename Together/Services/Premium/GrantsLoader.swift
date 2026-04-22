import Foundation

/// `PremiumGate` 对 Supabase `premium_grants` 表的访问抽象。
protocol GrantsLoaderProtocol: Sendable {
    /// 查询某个用户当前所有未撤销、未过期的 grants。
    /// Loader 层负责过滤 `revoked_at IS NULL` 和 `expires_at` 有效性，
    /// PremiumGate 拿到的结果可直接信任为"当前可用"。
    func fetchActiveGrants(userID: UUID) async throws -> [PremiumGrant]
}

/// 与数据库 premium_grants 行对应的领域模型。
/// 对应 spec §3 的表结构（投射关心的字段到 Swift 层）。
struct PremiumGrant: Equatable, Sendable, Identifiable {
    let id: UUID
    let userID: UUID
    let category: Category
    let reason: String?
    let grantedAt: Date
    let expiresAt: Date?  // nil = 永久

    enum Category: String, Sendable, Equatable {
        case developer
        case friend
        case grandfather
        case testflight
    }
}
