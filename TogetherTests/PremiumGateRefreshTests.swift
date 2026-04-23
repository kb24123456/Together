import Testing
import Foundation
@testable import Together

/// 补齐 Phase 2 遗留的 refresh 边界覆盖（Session A Task 8 还债）。
///
/// Phase 2 `PremiumGateLifecycleTests` 已覆盖：
/// - refresh 未 bootstrap 时 no-op
/// - refresh 复用 bootstrap 的 userID
/// - staleBootstrapResult 交叠 token 防护
/// 本 suite 补：连续 refresh race / logOut 中途作废 / refresh 失败保留状态 /
///             `latestEntitlementExpiration` 不被失败 overwrite。
@MainActor
@Suite
struct PremiumGateRefreshTests {

    private func makeGate(
        rc: StubRCClient = StubRCClient(),
        grants: StubGrantsLoader = StubGrantsLoader(),
        now: Date = Date()
    ) -> (gate: PremiumGate, rc: StubRCClient, grants: StubGrantsLoader) {
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        let cache = PremiumStatusCache(defaults: defaults, dateProvider: FixedDateProvider(fixed: now))
        let gate = PremiumGate(
            rcClient: rc,
            grantsLoader: grants,
            cache: cache,
            dateProvider: FixedDateProvider(fixed: now)
        )
        return (gate, rc, grants)
    }

    @Test func concurrentRefreshKeepsOnlyLastResult() async {
        let (gate, _, grants) = makeGate()
        let userID = UUID()

        // bootstrap → .free
        await grants.setNextResult(.success([]))
        await gate.bootstrap(userID: userID)
        #expect(gate.status == .free)

        // refresh A: held 住；会返回 pro 结果（若被应用）
        let proGrant = PremiumGrant(
            id: UUID(), userID: userID, category: .developer,
            reason: nil, grantedAt: Date(), expiresAt: nil
        )
        await grants.setNextResult(.success([proGrant]))
        await grants.holdNextFetch()
        async let refreshA: Void = gate.refresh()
        await grants.waitUntilHeld()

        // refresh B: 不 hold，直接 .free，token 变新
        await grants.setNextResult(.success([]))
        await gate.refresh()
        #expect(gate.status == .free)

        // 释放 A：A 的结果由于 token 不匹配被丢弃
        await grants.releaseHeld()
        _ = await refreshA
        #expect(gate.status == .free, "A 的 pro 结果必须被 token 校验丢弃")
    }

    @Test func logOutDuringRefreshDiscardsResult() async {
        let (gate, _, grants) = makeGate()
        let userID = UUID()

        await grants.setNextResult(.success([]))
        await gate.bootstrap(userID: userID)

        // refresh hold 住
        let proGrant = PremiumGrant(
            id: UUID(), userID: userID, category: .developer,
            reason: nil, grantedAt: Date(), expiresAt: nil
        )
        await grants.setNextResult(.success([proGrant]))
        await grants.holdNextFetch()
        async let refreshT: Void = gate.refresh()
        await grants.waitUntilHeld()

        // 中途 logOut → token 刷新
        gate.logOut()
        #expect(gate.status == .unknown)

        // 释放 held fetch：应被丢弃
        await grants.releaseHeld()
        _ = await refreshT
        #expect(gate.status == .unknown, "logOut 必须作废 in-flight refresh 结果")
    }

    @Test func refreshFailurePreservesBootstrappedStatus() async {
        let (gate, rc, grants) = makeGate()
        let userID = UUID()

        // bootstrap：RC 返回 active，status = .pro
        await rc.setNextResult(.success(
            RCEntitlementSnapshot(isProActive: true, proExpirationDate: Date.distantFuture)
        ))
        await grants.setNextResult(.success([]))
        await gate.bootstrap(userID: userID)
        #expect(gate.isPremium)

        // refresh 两路都失败；cache 仍是 pro，computeStatus 落回 cache
        let err = NSError(domain: "test", code: -1)
        await rc.setNextResult(.failure(err))
        await grants.setNextResult(.failure(err))

        await gate.refresh()
        #expect(gate.isPremium, "refresh 两路失败但缓存有效时应保留 bootstrap 状态")
    }

    @Test func latestEntitlementExpirationNotOverwrittenOnRefreshFailure() async {
        let (gate, rc, grants) = makeGate()
        let expiry = Date(timeIntervalSince1970: 100_000)

        await rc.setNextResult(.success(
            RCEntitlementSnapshot(isProActive: true, proExpirationDate: expiry)
        ))
        await grants.setNextResult(.success([]))
        await gate.bootstrap(userID: UUID())
        #expect(gate.latestEntitlementExpiration == expiry)

        // RC 失败 → cachedProExpirationDate 不应被覆盖
        await rc.setNextResult(.failure(NSError(domain: "test", code: -1)))
        await gate.refresh()

        #expect(
            gate.latestEntitlementExpiration == expiry,
            "cachedProExpirationDate 在 RC failure 分支不应 overwrite 上次成功值"
        )
    }

    @Test func latestEntitlementExpirationReflectsLatestSuccessfulFetch() async {
        let (gate, rc, grants) = makeGate()
        let firstExpiry = Date(timeIntervalSince1970: 100_000)
        let secondExpiry = Date(timeIntervalSince1970: 200_000)

        await rc.setNextResult(.success(
            RCEntitlementSnapshot(isProActive: true, proExpirationDate: firstExpiry)
        ))
        await grants.setNextResult(.success([]))
        await gate.bootstrap(userID: UUID())
        #expect(gate.latestEntitlementExpiration == firstExpiry)

        // RC 新的 expiration → cached 应更新
        await rc.setNextResult(.success(
            RCEntitlementSnapshot(isProActive: true, proExpirationDate: secondExpiry)
        ))
        await gate.refresh()
        #expect(gate.latestEntitlementExpiration == secondExpiry)
    }

    @Test func latestEntitlementExpirationUpdatesEvenWhenEntitlementBecomesInactive() async {
        // RC 失效时仍可返回 expirationDate（它刚失效）；lapse UI 需要这个值
        let (gate, rc, grants) = makeGate()
        let expiry = Date(timeIntervalSince1970: 100_000)
        await rc.setNextResult(.success(
            RCEntitlementSnapshot(isProActive: false, proExpirationDate: expiry)
        ))
        await grants.setNextResult(.success([]))
        await gate.bootstrap(userID: UUID())

        #expect(gate.latestEntitlementExpiration == expiry,
                "isProActive=false 时 expirationDate 也要缓存（lapse UI 依赖）")
    }
}
