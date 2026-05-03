import Testing
import Foundation
@testable import Together

// MARK: - Stub implementations

actor StubRCClient: RCClientProtocol {
    private var _nextResult: Result<RCEntitlementSnapshot, Error> = .success(
        RCEntitlementSnapshot(isProActive: false, proExpirationDate: nil)
    )
    var loggedInID: String?

    nonisolated var isConfigured: Bool { true }
    nonisolated func configure(publicSDKKey: String, appUserID: String) {}

    func setNextResult(_ r: Result<RCEntitlementSnapshot, Error>) { _nextResult = r }

    func fetchCustomerInfo() async throws -> RCEntitlementSnapshot {
        try _nextResult.get()
    }
    func logIn(appUserID: String) async throws { loggedInID = appUserID }
    func logOut() async throws { loggedInID = nil }
}

actor StubGrantsLoader: GrantsLoaderProtocol {
    private var _nextResult: Result<[PremiumGrant], Error> = .success([])
    private(set) var receivedUserIDs: [UUID] = []

    // 显式 hold/release 信号（替代 sleep 时序）
    private var _shouldHoldNext = false
    private var _heldContinuation: CheckedContinuation<Void, Never>?
    private var _didEnterHoldContinuation: CheckedContinuation<Void, Never>?

    func setNextResult(_ r: Result<[PremiumGrant], Error>) { _nextResult = r }

    /// 让下一次 fetch 在真正执行前挂起，直到 `releaseHeld()` 被调用。
    func holdNextFetch() { _shouldHoldNext = true }

    /// 等待 held fetch 真正进入挂起点（用于保证时序而非 sleep）。
    func waitUntilHeld() async {
        if _heldContinuation != nil { return }
        await withCheckedContinuation { c in _didEnterHoldContinuation = c }
    }

    /// 释放 held fetch。
    func releaseHeld() {
        _heldContinuation?.resume()
        _heldContinuation = nil
    }

    func fetchActiveGrants(userID: UUID) async throws -> [PremiumGrant] {
        receivedUserIDs.append(userID)
        if _shouldHoldNext {
            _shouldHoldNext = false
            await withCheckedContinuation { c in
                _heldContinuation = c
                _didEnterHoldContinuation?.resume()
                _didEnterHoldContinuation = nil
            }
        }
        return try _nextResult.get()
    }
}

actor StubEntitlementsLoader: PremiumEntitlementsLoaderProtocol {
    private var _nextResult: Result<[PremiumServerEntitlement], Error> = .success([])

    func setNextResult(_ r: Result<[PremiumServerEntitlement], Error>) { _nextResult = r }

    func fetchActiveEntitlements(userID: UUID) async throws -> [PremiumServerEntitlement] {
        try _nextResult.get()
    }
}

// MARK: - Tests

@MainActor
@Suite
struct PremiumGateLifecycleTests {
    private func makeGate(
        rc: StubRCClient = StubRCClient(),
        grants: StubGrantsLoader = StubGrantsLoader(),
        entitlements: StubEntitlementsLoader = StubEntitlementsLoader(),
        now: Date = Date()
    ) -> (gate: PremiumGate, rc: StubRCClient, grants: StubGrantsLoader, entitlements: StubEntitlementsLoader) {
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        let cache = PremiumStatusCache(
            defaults: defaults,
            dateProvider: FixedDateProvider(fixed: now)
        )
        let gate = PremiumGate(
            rcClient: rc,
            grantsLoader: grants,
            entitlementsLoader: entitlements,
            cache: cache,
            dateProvider: FixedDateProvider(fixed: now)
        )
        return (gate, rc, grants, entitlements)
    }

    @Test func initialStatusIsUnknown() {
        let (gate, _, _, _) = makeGate()
        #expect(gate.status == .unknown)
        #expect(gate.isPremium == false)
    }

    @Test func bootstrapWithActiveGrantSetsPro() async {
        let (gate, _, grants, _) = makeGate()
        let grant = PremiumGrant(
            id: UUID(), userID: UUID(), category: .developer,
            reason: nil, grantedAt: Date(), expiresAt: nil
        )
        await grants.setNextResult(.success([grant]))

        await gate.bootstrap(userID: UUID())
        #expect(gate.isPremium)
        if case let .pro(source, expiresAt) = gate.status {
            #expect(source == .grant)
            #expect(expiresAt == nil)
        } else {
            Issue.record("expected .pro, got \(gate.status)")
        }
    }

    @Test func bootstrapWithActiveServerEntitlementSetsPro() async {
        let now = Date()
        let (gate, rc, _, entitlements) = makeGate(now: now)
        await rc.setNextResult(.success(RCEntitlementSnapshot(isProActive: false, proExpirationDate: nil)))
        let entitlement = PremiumServerEntitlement(
            id: UUID(),
            userID: UUID(),
            entitlementID: RevenueCatConfig.entitlementIdentifier,
            productID: "com.pigdog.together.monthly1m",
            purchasedAt: now,
            expiresAt: now.addingTimeInterval(86400)
        )
        await entitlements.setNextResult(.success([entitlement]))

        await gate.bootstrap(userID: UUID())
        #expect(gate.status == .pro(source: .subscription, expiresAt: entitlement.expiresAt))
    }

    @Test func bootstrapWithAllFailuresAndNoCacheYieldsFree() async {
        let (gate, rc, grants, entitlements) = makeGate()
        let err = NSError(domain: "test", code: -1)
        await rc.setNextResult(.failure(err))
        await grants.setNextResult(.failure(err))
        await entitlements.setNextResult(.failure(err))

        await gate.bootstrap(userID: UUID())
        #expect(gate.status == .free)
    }

    @Test func refreshWithoutBootstrapIsNoOp() async {
        let (gate, _, grants, _) = makeGate()
        // 配置一个会让 status 变 .pro 的结果；如果 refresh 真的跑了，这个会被应用
        await grants.setNextResult(.success([
            PremiumGrant(
                id: UUID(), userID: UUID(), category: .developer,
                reason: nil, grantedAt: Date(), expiresAt: nil
            )
        ]))

        await gate.refresh()

        // 没 bootstrap 过 → currentUserID == nil → refresh 应 no-op
        #expect(gate.status == .unknown)
        let received = await grants.receivedUserIDs
        #expect(received.isEmpty)
    }

    @Test func refreshAfterBootstrapRerunsWithSameUserID() async {
        let (gate, _, grants, _) = makeGate()
        let userID = UUID()

        // 第一次 bootstrap：空 grants → .free
        await gate.bootstrap(userID: userID)
        #expect(gate.status == .free)

        // 变更 grants，refresh 应拉取新的结果并更新 status
        await grants.setNextResult(.success([
            PremiumGrant(
                id: UUID(), userID: userID, category: .developer,
                reason: nil, grantedAt: Date(), expiresAt: nil
            )
        ]))
        await gate.refresh()

        #expect(gate.isPremium)
        let received = await grants.receivedUserIDs
        // refresh 必须用 bootstrap 时捕获的同一 userID，不能掉/换
        #expect(received == [userID, userID])
    }

    @Test func logOutClearsStatusAndCache() async {
        let (gate, _, grants, _) = makeGate()
        let grant = PremiumGrant(
            id: UUID(), userID: UUID(), category: .friend,
            reason: nil, grantedAt: Date(), expiresAt: nil
        )
        await grants.setNextResult(.success([grant]))
        await gate.bootstrap(userID: UUID())
        #expect(gate.isPremium)

        gate.logOut()
        #expect(gate.status == .unknown)
    }

    #if DEBUG
    @Test func debugOverrideTakesPrecedence() {
        let (gate, _, _, _) = makeGate()
        #expect(gate.isPremium == false)

        gate.overrideStatus = .pro(source: .subscription, expiresAt: nil)
        #expect(gate.isPremium)
        #expect(gate.allowsFullLogbook)

        gate.overrideStatus = nil
        #expect(gate.isPremium == false)
    }
    #endif

    @Test func staleBootstrapResultIsDiscarded() async {
        // 两次 bootstrap 交叠：A 的 grants fetch 被 hold 住，B 在中间完成并推进 token；
        // A 释放后结果应被 token 校验丢弃。不依赖 sleep 时序。
        let (gate, _, grants, _) = makeGate()
        let userA = UUID()
        let userB = UUID()

        // A 的结果会让 status 变 .pro——如果 stale 检查失效就会看到
        await grants.holdNextFetch()
        await grants.setNextResult(.success([
            PremiumGrant(
                id: UUID(), userID: userA, category: .developer,
                reason: nil, grantedAt: Date(), expiresAt: nil
            )
        ]))

        let taskA = Task { await gate.bootstrap(userID: userA) }

        // 显式等 A 的 grants fetch 进入挂起点——保证 A 的 token 已写入
        await grants.waitUntilHeld()

        // 换成 B 的结果（空 grants → .free），B 不 hold，直接跑完
        await grants.setNextResult(.success([]))
        await gate.bootstrap(userID: userB)

        // 释放 A；A 恢复后 token 已不匹配，合并结果会被丢弃
        await grants.releaseHeld()
        await taskA.value

        // 最终 status 是 B 的 .free，而不是 A 的 .pro
        #expect(gate.status == .free)
    }
}
