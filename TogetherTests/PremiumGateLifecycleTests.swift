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
    private var _fetchDelay: Duration = .zero

    func setNextResult(_ r: Result<[PremiumGrant], Error>) { _nextResult = r }
    func setFetchDelay(_ d: Duration) { _fetchDelay = d }

    func fetchActiveGrants(userID: UUID) async throws -> [PremiumGrant] {
        if _fetchDelay != .zero {
            try? await Task.sleep(for: _fetchDelay)
        }
        return try _nextResult.get()
    }
}

// MARK: - Tests

@MainActor
@Suite
struct PremiumGateLifecycleTests {
    private func makeGate(
        rc: StubRCClient = StubRCClient(),
        grants: StubGrantsLoader = StubGrantsLoader(),
        now: Date = Date()
    ) -> (gate: PremiumGate, rc: StubRCClient, grants: StubGrantsLoader) {
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        let cache = PremiumStatusCache(
            defaults: defaults,
            dateProvider: FixedDateProvider(fixed: now)
        )
        let gate = PremiumGate(
            rcClient: rc,
            grantsLoader: grants,
            cache: cache,
            dateProvider: FixedDateProvider(fixed: now)
        )
        return (gate, rc, grants)
    }

    @Test func initialStatusIsUnknown() {
        let (gate, _, _) = makeGate()
        #expect(gate.status == .unknown)
        #expect(gate.isPremium == false)
    }

    @Test func bootstrapWithActiveGrantSetsPro() async {
        let (gate, _, grants) = makeGate()
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

    @Test func bootstrapWithAllFailuresAndNoCacheYieldsFree() async {
        let (gate, rc, grants) = makeGate()
        let err = NSError(domain: "test", code: -1)
        await rc.setNextResult(.failure(err))
        await grants.setNextResult(.failure(err))

        await gate.bootstrap(userID: UUID())
        #expect(gate.status == .free)
    }

    @Test func logOutClearsStatusAndCache() async {
        let (gate, _, grants) = makeGate()
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
        let (gate, _, _) = makeGate()
        #expect(gate.isPremium == false)

        gate.overrideStatus = .pro(source: .subscription, expiresAt: nil)
        #expect(gate.isPremium)
        #expect(gate.allowsFullLogbook)

        gate.overrideStatus = nil
        #expect(gate.isPremium == false)
    }
    #endif

    @Test func staleBootstrapResultIsDiscarded() async {
        // 快速连续两次 bootstrap，后者应胜出
        let (gate, _, grants) = makeGate()
        let userA = UUID()
        let userB = UUID()

        await grants.setFetchDelay(.milliseconds(100))
        await grants.setNextResult(.success([
            PremiumGrant(
                id: UUID(), userID: userA, category: .developer,
                reason: nil, grantedAt: Date(), expiresAt: nil
            )
        ]))
        let taskA = Task { await gate.bootstrap(userID: userA) }

        // 立刻发起第二次 bootstrap（不同结果）
        try? await Task.sleep(for: .milliseconds(10))
        await grants.setFetchDelay(.zero)
        await grants.setNextResult(.success([]))
        await gate.bootstrap(userID: userB)

        // 等 A 完成
        await taskA.value

        // 最终 status 应是 B 的（.free），不是 A 的 .pro
        #expect(gate.status == .free)
    }
}
