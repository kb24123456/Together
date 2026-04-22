import Foundation
import Observation

/// 会员门禁核心。合并 RevenueCat 订阅和 Supabase white-list grants，
/// 暴露可观察的 `PremiumStatus`。
///
/// Task 6 范围：仅实现 `computeStatus` 静态合并函数（源无关 14 天 Grace Period）。
/// 实例生命周期（bootstrap / refresh / logOut / 竞态防护）在 Task 7 添加。
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

    // MARK: - 合并逻辑（纯函数，便于测试）

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
        if !active.isEmpty {
            let best = pickBest(active)
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
                logbookFullUntil: mostRecent.addingTimeInterval(14 * 86400)
            )
        }

        // Step 4: 双查询失败 + 有缓存？
        let rcFailed: Bool
        if case .failure = rcResult { rcFailed = true } else { rcFailed = false }
        let grantsFailed: Bool
        if case .failure = grantsResult { grantsFailed = true } else { grantsFailed = false }
        if rcFailed && grantsFailed, let cached = cachedStatus {
            return cached
        }

        // Step 5: fallback
        return .free
    }

    // MARK: - Private merge helpers

    private nonisolated static func pickBest(_ sources: [MergeSource]) -> MergeSource {
        // 比较规则：
        //   永久（nil）> 有限期（越晚越好）
        //   两个都永久时：.subscription > .grant
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
        }!
    }

    private nonisolated static func collectRecentlyExpired(
        rcResult: Result<RCEntitlementSnapshot, Error>,
        grantsResult: Result<[PremiumGrant], Error>,
        now: Date
    ) -> [Date] {
        var result: [Date] = []
        let fourteenDaysAgo = now.addingTimeInterval(-14 * 86400)

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
