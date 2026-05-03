import Foundation
import Supabase

/// `PremiumGate` 对 Supabase `premium_grants` 表的访问抽象。
protocol GrantsLoaderProtocol: Sendable {
    /// 查询某个用户所有 `revoked_at IS NULL` 的 grants（包括近期过期的）。
    ///
    /// 不在这一层按 `expires_at` 过滤：spec §2.3 step 3 的 Grace Period
    /// 判定依赖过去 14 天内过期的 grant，所以过期检查必须留在
    /// `PremiumGate.computeStatus` 做。Loader 只负责剔除 revoked。
    func fetchActiveGrants(userID: UUID) async throws -> [PremiumGrant]
}

/// `premium_entitlements` 是 RevenueCat webhook 写入的服务端订阅事实。
/// 客户端不能只依赖 RevenueCat SDK 的本机缓存，否则退出重登、SDK cache 或
/// Customer merge 延迟都可能让已付费用户短暂变 Free。
protocol PremiumEntitlementsLoaderProtocol: Sendable {
    func fetchActiveEntitlements(userID: UUID) async throws -> [PremiumServerEntitlement]
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

struct PremiumServerEntitlement: Equatable, Sendable, Identifiable {
    let id: UUID
    let userID: UUID
    let entitlementID: String
    let productID: String?
    let purchasedAt: Date?
    let expiresAt: Date?
}

// MARK: - Production implementation

/// `GrantsLoaderProtocol` 的生产实现，基于 supabase-swift SDK。
///
/// SELECT 语义：同一 user_id 的所有 `revoked_at IS NULL` 行，过期与否都拉回来。
/// 过期判定、Grace Period 判定由 `PremiumGate.computeStatus` 在客户端做。
final class SupabaseGrantsLoader: GrantsLoaderProtocol {
    private let client: SupabaseClient

    init(client: SupabaseClient) {
        self.client = client
    }

    func fetchActiveGrants(userID: UUID) async throws -> [PremiumGrant] {
        let rows: [GrantRow] = try await client
            .from("premium_grants")
            .select()
            .eq("user_id", value: userID.uuidString)
            .is("revoked_at", value: nil)
            .execute()
            .value

        return try rows.map { try $0.toDomain() }
    }
}

final class SupabasePremiumEntitlementsLoader: PremiumEntitlementsLoaderProtocol {
    private let client: SupabaseClient

    init(client: SupabaseClient) {
        self.client = client
    }

    func fetchActiveEntitlements(userID: UUID) async throws -> [PremiumServerEntitlement] {
        let rows: [EntitlementRow] = try await client
            .from("premium_entitlements")
            .select()
            .eq("user_id", value: userID.uuidString.lowercased())
            .eq("entitlement_id", value: RevenueCatConfig.entitlementIdentifier)
            .is("revoked_at", value: nil)
            .execute()
            .value

        return rows.map { $0.toDomain() }
    }
}

final class EmptyPremiumEntitlementsLoader: PremiumEntitlementsLoaderProtocol, @unchecked Sendable {
    nonisolated init() {}

    func fetchActiveEntitlements(userID: UUID) async throws -> [PremiumServerEntitlement] { [] }
}

// MARK: - DB row DTO

private struct GrantRow: Decodable {
    let id: UUID
    let userID: UUID
    let category: String
    let reason: String?
    let grantedAt: Date
    let expiresAt: Date?

    enum CodingKeys: String, CodingKey {
        case id, category, reason
        case userID = "user_id"
        case grantedAt = "granted_at"
        case expiresAt = "expires_at"
    }

    func toDomain() throws -> PremiumGrant {
        guard let cat = PremiumGrant.Category(rawValue: category) else {
            throw GrantDecodeError.unknownCategory(category)
        }
        return PremiumGrant(
            id: id, userID: userID, category: cat, reason: reason,
            grantedAt: grantedAt, expiresAt: expiresAt
        )
    }
}

enum GrantDecodeError: Error, Equatable {
    /// DB 的 category 文本超出 `PremiumGrant.Category` 的 rawValue 集合——
    /// 通常意味着表 CHECK 约束和 Swift enum 脱节，应当 surface 而不是静默吞。
    case unknownCategory(String)
}

private struct EntitlementRow: Decodable {
    let id: UUID
    let userID: UUID
    let entitlementID: String
    let productID: String?
    let purchasedAt: Date?
    let expiresAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case userID = "user_id"
        case entitlementID = "entitlement_id"
        case productID = "product_id"
        case purchasedAt = "purchased_at"
        case expiresAt = "expires_at"
    }

    func toDomain() -> PremiumServerEntitlement {
        PremiumServerEntitlement(
            id: id,
            userID: userID,
            entitlementID: entitlementID,
            productID: productID,
            purchasedAt: purchasedAt,
            expiresAt: expiresAt
        )
    }
}
