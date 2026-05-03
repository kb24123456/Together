import Testing
import Foundation
@testable import Together

@Suite
struct PremiumGateMergeTests {
    private let now = Date(timeIntervalSince1970: 10_000_000)

    private func dateOffset(_ days: Double) -> Date {
        now.addingTimeInterval(days * 86400)
    }

    // MARK: - Step 2: 活跃来源

    @Test func activeRCSubscriptionMakesPro() {
        let status = PremiumGate.computeStatus(
            rcResult: .success(RCEntitlementSnapshot(
                isProActive: true,
                proExpirationDate: dateOffset(30)
            )),
            grantsResult: .success([]),
            cachedStatus: nil,
            now: now
        )
        #expect(status == .pro(source: .subscription, expiresAt: dateOffset(30)))
    }

    @Test func activeGrantMakesPro() {
        let grant = PremiumGrant(
            id: UUID(), userID: UUID(), category: .friend,
            reason: nil, grantedAt: dateOffset(-5), expiresAt: nil
        )
        let status = PremiumGate.computeStatus(
            rcResult: .success(RCEntitlementSnapshot(isProActive: false, proExpirationDate: nil)),
            grantsResult: .success([grant]),
            cachedStatus: nil,
            now: now
        )
        #expect(status == .pro(source: .grant, expiresAt: nil))
    }

    @Test func activeServerEntitlementMakesProWhenRCIsEmpty() {
        let entitlement = PremiumServerEntitlement(
            id: UUID(),
            userID: UUID(),
            entitlementID: RevenueCatConfig.entitlementIdentifier,
            productID: "com.pigdog.together.monthly1m",
            purchasedAt: dateOffset(-1),
            expiresAt: dateOffset(1)
        )
        let status = PremiumGate.computeStatus(
            rcResult: .success(RCEntitlementSnapshot(isProActive: false, proExpirationDate: nil)),
            grantsResult: .success([]),
            entitlementsResult: .success([entitlement]),
            cachedStatus: nil,
            now: now
        )
        #expect(status == .pro(source: .subscription, expiresAt: dateOffset(1)))
    }

    @Test func bothActivePrefersLaterExpiry() {
        let lateGrant = PremiumGrant(
            id: UUID(), userID: UUID(), category: .grandfather,
            reason: nil, grantedAt: dateOffset(-100), expiresAt: nil
        )
        let rc = RCEntitlementSnapshot(isProActive: true, proExpirationDate: dateOffset(30))
        let status = PremiumGate.computeStatus(
            rcResult: .success(rc),
            grantsResult: .success([lateGrant]),
            cachedStatus: nil,
            now: now
        )
        // 永久（nil）胜过有限期
        switch status {
        case let .pro(_, expiresAt):
            #expect(expiresAt == nil)
        default:
            Issue.record("expected .pro status, got \(status)")
        }
    }

    // MARK: - Step 3: Grace Period

    @Test func rcExpiredWithin14DaysYieldsGracePeriod() {
        let expired5DaysAgo = dateOffset(-5)
        let rc = RCEntitlementSnapshot(isProActive: false, proExpirationDate: expired5DaysAgo)
        let status = PremiumGate.computeStatus(
            rcResult: .success(rc),
            grantsResult: .success([]),
            cachedStatus: nil,
            now: now
        )
        let expectedLogbookUntil = expired5DaysAgo.addingTimeInterval(14 * 86400)
        #expect(status == .gracePeriod(
            originalExpiry: expired5DaysAgo,
            logbookFullUntil: expectedLogbookUntil
        ))
    }

    @Test func grantExpiredWithin14DaysYieldsGracePeriod() {
        let expired3DaysAgo = dateOffset(-3)
        let grant = PremiumGrant(
            id: UUID(), userID: UUID(), category: .testflight,
            reason: nil, grantedAt: dateOffset(-95), expiresAt: expired3DaysAgo
        )
        let status = PremiumGate.computeStatus(
            rcResult: .success(RCEntitlementSnapshot(isProActive: false, proExpirationDate: nil)),
            grantsResult: .success([grant]),
            cachedStatus: nil,
            now: now
        )
        let expectedLogbookUntil = expired3DaysAgo.addingTimeInterval(14 * 86400)
        #expect(status == .gracePeriod(
            originalExpiry: expired3DaysAgo,
            logbookFullUntil: expectedLogbookUntil
        ))
    }

    @Test func expiredOver14DaysYieldsFree() {
        let rc = RCEntitlementSnapshot(isProActive: false, proExpirationDate: dateOffset(-20))
        let status = PremiumGate.computeStatus(
            rcResult: .success(rc),
            grantsResult: .success([]),
            cachedStatus: nil,
            now: now
        )
        #expect(status == .free)
    }

    @Test func multipleExpiredPicksMostRecent() {
        let olderExpired = dateOffset(-12)
        let recentExpired = dateOffset(-3)
        let olderGrant = PremiumGrant(
            id: UUID(), userID: UUID(), category: .testflight,
            reason: nil, grantedAt: dateOffset(-100), expiresAt: olderExpired
        )
        let rc = RCEntitlementSnapshot(isProActive: false, proExpirationDate: recentExpired)
        let status = PremiumGate.computeStatus(
            rcResult: .success(rc),
            grantsResult: .success([olderGrant]),
            cachedStatus: nil,
            now: now
        )
        // originalExpiry 应是"最晚过期"的那个
        switch status {
        case let .gracePeriod(originalExpiry, _):
            #expect(originalExpiry == recentExpired)
        default:
            Issue.record("expected gracePeriod, got \(status)")
        }
    }

    // MARK: - Step 4: 查询失败 + 缓存

    @Test func bothFailuresUseCache() {
        let cached = PremiumStatus.pro(source: .subscription, expiresAt: dateOffset(5))
        let status = PremiumGate.computeStatus(
            rcResult: .failure(NSError(domain: "test", code: -1)),
            grantsResult: .failure(NSError(domain: "test", code: -1)),
            cachedStatus: cached,
            now: now
        )
        #expect(status == cached)
    }

    @Test func bothFailuresNoCacheReturnsFree() {
        let status = PremiumGate.computeStatus(
            rcResult: .failure(NSError(domain: "test", code: -1)),
            grantsResult: .failure(NSError(domain: "test", code: -1)),
            cachedStatus: nil,
            now: now
        )
        #expect(status == .free)
    }

    /// 真实离线场景：任一权威来源失败时，不能用另一边的空结果直接降级。
    /// 缓存有 TTL，短期保守保留上次状态，避免 RC 或 Supabase 瞬时异常关闭付费权益。
    @Test func grantsFailureAloneUsesCacheEvenWhenRCStaleInactive() {
        let cached = PremiumStatus.pro(source: .grant, expiresAt: nil)
        let status = PremiumGate.computeStatus(
            rcResult: .success(RCEntitlementSnapshot(isProActive: false, proExpirationDate: nil)),
            grantsResult: .failure(NSError(domain: "network", code: -1009)),
            cachedStatus: cached,
            now: now
        )
        #expect(status == cached)
    }

    @Test func grantsFailureWithRCInactiveNoCacheReturnsFree() {
        let status = PremiumGate.computeStatus(
            rcResult: .success(RCEntitlementSnapshot(isProActive: false, proExpirationDate: nil)),
            grantsResult: .failure(NSError(domain: "network", code: -1009)),
            cachedStatus: nil,
            now: now
        )
        #expect(status == .free)
    }

    @Test func rcFailureWithActiveGrantUsesActiveGrant() {
        let cached = PremiumStatus.pro(source: .grant, expiresAt: nil)
        let grant = PremiumGrant(
            id: UUID(), userID: UUID(), category: .friend,
            reason: nil, grantedAt: dateOffset(-1), expiresAt: nil
        )
        let status = PremiumGate.computeStatus(
            rcResult: .failure(NSError(domain: "test", code: -1)),
            grantsResult: .success([grant]),
            cachedStatus: cached,
            now: now
        )
        #expect(status == .pro(source: .grant, expiresAt: nil))
    }

    @Test func rcFailureWithEmptyGrantsUsesCache() {
        let cached = PremiumStatus.pro(source: .subscription, expiresAt: dateOffset(10))
        let status = PremiumGate.computeStatus(
            rcResult: .failure(NSError(domain: "rc", code: -1)),
            grantsResult: .success([]),
            cachedStatus: cached,
            now: now
        )
        #expect(status == cached)
    }

    @Test func knownRecentExpiryBeatsCacheEvenWhenOtherSourceFails() {
        let expired3DaysAgo = dateOffset(-3)
        let cached = PremiumStatus.pro(source: .subscription, expiresAt: dateOffset(10))
        let status = PremiumGate.computeStatus(
            rcResult: .success(RCEntitlementSnapshot(isProActive: false, proExpirationDate: expired3DaysAgo)),
            grantsResult: .failure(NSError(domain: "network", code: -1009)),
            cachedStatus: cached,
            now: now
        )

        #expect(status == .gracePeriod(
            originalExpiry: expired3DaysAgo,
            logbookFullUntil: expired3DaysAgo.addingTimeInterval(14 * 86400)
        ))
    }

    // MARK: - Step 5: 双源无效 + 非 Grace

    @Test func noSourcesReturnsFree() {
        let status = PremiumGate.computeStatus(
            rcResult: .success(RCEntitlementSnapshot(isProActive: false, proExpirationDate: nil)),
            grantsResult: .success([]),
            cachedStatus: nil,
            now: now
        )
        #expect(status == .free)
    }
}
