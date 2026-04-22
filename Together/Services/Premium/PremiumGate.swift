import Foundation
import Observation

/// 会员门禁核心。合并 RevenueCat 订阅和 Supabase white-list grants，
/// 暴露可观察的 `PremiumStatus`。
///
/// Task 6 范围：仅实现 `computeStatus` 静态合并函数（源无关 14 天 Grace Period）。
/// Task 7 范围：实例生命周期（bootstrap / refresh / logOut / 竞态防护）。
@MainActor
@Observable
final class PremiumGate {
    private(set) var status: PremiumStatus = .unknown

    var isPremium: Bool { (overrideStatus ?? status).isPremium }
    var allowsFullLogbook: Bool { (overrideStatus ?? status).allowsFullLogbook }

    #if DEBUG
    var overrideStatus: PremiumStatus?
    #else
    private var overrideStatus: PremiumStatus? { nil }
    #endif

    // MARK: - 依赖

    private let rcClient: RCClientProtocol
    private let grantsLoader: GrantsLoaderProtocol
    private let cache: PremiumStatusCache
    private let dateProvider: DateProvider

    // 竞态防护：每次 bootstrap 生成新 token，只有 token 匹配时才写入结果
    private var bootstrapToken = UUID()
    private var currentUserID: UUID?

    init(
        rcClient: RCClientProtocol,
        grantsLoader: GrantsLoaderProtocol,
        cache: PremiumStatusCache,
        dateProvider: DateProvider
    ) {
        self.rcClient = rcClient
        self.grantsLoader = grantsLoader
        self.cache = cache
        self.dateProvider = dateProvider
    }

    // MARK: - Lifecycle

    func bootstrap(userID: UUID) async {
        currentUserID = userID
        let token = UUID()
        bootstrapToken = token

        async let rcResult = safeFetchRC()
        async let grantsResult = safeFetchGrants(userID: userID)
        let (rc, grants) = await (rcResult, grantsResult)

        // 竞态防护：只有 token 仍是最新的才应用结果
        guard bootstrapToken == token else { return }

        let cached = cache.load()
        let newStatus = Self.computeStatus(
            rcResult: rc, grantsResult: grants,
            cachedStatus: cached,
            now: dateProvider.now()
        )
        status = newStatus
        cache.save(newStatus)
    }

    func refresh() async {
        guard let userID = currentUserID else { return }
        await bootstrap(userID: userID)
    }

    func logOut() {
        bootstrapToken = UUID()  // 使任何 in-flight bootstrap 作废
        currentUserID = nil
        status = .unknown
        cache.clear()
    }

    // MARK: - Private safe wrappers

    private func safeFetchRC() async -> Result<RCEntitlementSnapshot, Error> {
        do {
            let info = try await rcClient.fetchCustomerInfo()
            return .success(info)
        } catch {
            return .failure(error)
        }
    }

    private func safeFetchGrants(userID: UUID) async -> Result<[PremiumGrant], Error> {
        do {
            let grants = try await grantsLoader.fetchActiveGrants(userID: userID)
            return .success(grants)
        } catch {
            return .failure(error)
        }
    }

    // MARK: - 合并逻辑（纯函数，便于测试）

    /// Grace Period 时长：14 天（秒）。
    private static let gracePeriodInterval: TimeInterval = 14 * 86400

    /// 源无关的 14 天 Grace Period 合并算法（spec § 2.3）。
    /// RC 订阅和白名单 grant 任一来源近期过期都进入 Grace Period。
    nonisolated static func computeStatus(
        rcResult: Result<RCEntitlementSnapshot, Error>,
        grantsResult: Result<[PremiumGrant], Error>,
        cachedStatus: PremiumStatus?,
        now: Date
    ) -> PremiumStatus {
        // Step 1: 收集所有来源
        var sources: [MergeSource] = []

        if case let .success(rc) = rcResult, rc.isProActive {
            sources.append(MergeSource(kind: .subscription, expiresAt: rc.proExpirationDate))
        }

        if case let .success(grants) = grantsResult {
            for g in grants {
                sources.append(MergeSource(kind: .grant, expiresAt: g.expiresAt))
            }
        }

        // Step 2: 任一有效？（expiresAt == nil 或 > now）
        let active = sources.filter { s in
            guard let expiry = s.expiresAt else { return true }  // nil = 永久
            return expiry > now
        }
        if let best = pickBest(active) {
            return .pro(source: best.kind, expiresAt: best.expiresAt)
        }

        // Step 3: 任一在过去 14 天内过期？
        let graceCandidates = collectRecentlyExpired(
            rcResult: rcResult,
            grantsResult: grantsResult,
            now: now
        )
        if let mostRecent = graceCandidates.max() {
            return .gracePeriod(
                originalExpiry: mostRecent,
                logbookFullUntil: mostRecent.addingTimeInterval(gracePeriodInterval)
            )
        }

        // Step 4: 双查询失败 + 有缓存？
        if case .failure = rcResult, case .failure = grantsResult, let cached = cachedStatus {
            return cached
        }

        // Step 5: fallback
        return .free
    }

    // MARK: - Private merge helpers

    /// 从活跃 sources 中选出最优一条。sources 为空时返回 nil。
    ///
    /// 比较规则：
    ///   永久（nil）> 有限期（越晚越好）
    ///   两个都永久时：.subscription > .grant
    private nonisolated static func pickBest(_ sources: [MergeSource]) -> MergeSource? {
        sources.max { lhs, rhs in
            // 返回 true 表示 lhs < rhs（即 rhs 更优）
            switch (lhs.expiresAt, rhs.expiresAt) {
            case (nil, nil):
                // 都是永久：.subscription 胜，所以如果 lhs 是 grant 且 rhs 是 subscription，lhs < rhs
                return lhs.kind == .grant && rhs.kind == .subscription
            case (nil, _):
                // lhs 永久，rhs 有限期：lhs 更优，所以 lhs > rhs
                return false
            case (_, nil):
                // rhs 永久：rhs 更优，所以 lhs < rhs
                return true
            case let (l?, r?):
                return l < r
            }
        }
    }

    private nonisolated static func collectRecentlyExpired(
        rcResult: Result<RCEntitlementSnapshot, Error>,
        grantsResult: Result<[PremiumGrant], Error>,
        now: Date
    ) -> [Date] {
        var result: [Date] = []
        let fourteenDaysAgo = now.addingTimeInterval(-gracePeriodInterval)

        // RC：未激活但有过期日期，且在 (now-14d, now] 窗口内
        if case let .success(rc) = rcResult,
           !rc.isProActive,
           let expiry = rc.proExpirationDate,
           expiry > fourteenDaysAgo, expiry <= now {
            result.append(expiry)
        }

        // Grants：有过期日期，且在窗口内
        if case let .success(grants) = grantsResult {
            for g in grants {
                if let expiry = g.expiresAt,
                   expiry > fourteenDaysAgo, expiry <= now {
                    result.append(expiry)
                }
            }
        }
        return result
    }
}

// MARK: - Internal merge type

private struct MergeSource {
    let kind: PremiumStatus.PremiumSource
    let expiresAt: Date?
}
