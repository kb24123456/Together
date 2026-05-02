import Testing
import Foundation
@testable import Together

/// `PremiumGate.effectiveStatus` 行为契约测试。
///
/// `effectiveStatus = overrideStatus ?? status`，是 view 层应该读的值（同 isPremium /
/// allowsFullLogbook 同源）。Session B smoke 撞过 raw status 不含 override 导致
/// detail section 空白的 bug（见 commit c550dd9 / fix: expose effectiveStatus）；
/// 本套测试是该 bug 的回归守卫，并显式 documentation：
/// - View 层应用 effectiveStatus（DEBUG override 切换可见）
/// - Service 层（lapse 检测、log）可继续用 raw status（关心真实 RC 状态）
@MainActor
@Suite
struct PremiumGateEffectiveStatusTests {

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

    private func bootstrapActivePro(gate: PremiumGate, rc: StubRCClient) async {
        await rc.setNextResult(.success(RCEntitlementSnapshot(isProActive: true, proExpirationDate: nil)))
        await gate.bootstrap(userID: UUID())
    }

    // MARK: - 无 override（release 默认行为）

    @Test func effectiveStatusEqualsRawStatusWhenNoOverride() {
        let (gate, _, _) = makeGate()
        // 初始 status == .unknown，effective 跟随
        #expect(gate.effectiveStatus == gate.status)
        #expect(gate.effectiveStatus == .unknown)
    }

    @Test func effectiveStatusReflectsBootstrappedStatus() async {
        let (gate, rc, _) = makeGate()
        await bootstrapActivePro(gate: gate, rc: rc)
        // 无 override，effective 跟随真实合并状态
        #expect(gate.effectiveStatus == gate.status)
        if case .pro = gate.effectiveStatus {} else {
            Issue.record("expected .pro, got \(gate.effectiveStatus)")
        }
    }

    // MARK: - DEBUG override 行为

    #if DEBUG
    @Test func overrideShadowsRawStatusWhenSet() {
        let (gate, _, _) = makeGate()
        // 真实 status .unknown
        #expect(gate.status == .unknown)
        // 设 override 为 Pro
        let overrideValue: PremiumStatus = .pro(source: .subscription, expiresAt: Date(timeIntervalSinceNow: 30 * 86400))
        gate.overrideStatus = overrideValue
        // effective 反映 override，raw 不受影响
        #expect(gate.effectiveStatus == overrideValue)
        #expect(gate.status == .unknown)  // raw 守卫
    }

    @Test func overrideToGracePeriodIsObservable() {
        let (gate, _, _) = makeGate()
        let until = Date(timeIntervalSinceNow: 7 * 86400)
        let overrideValue: PremiumStatus = .gracePeriod(
            originalExpiry: Date(timeIntervalSinceNow: -1 * 86400),
            logbookFullUntil: until
        )
        gate.overrideStatus = overrideValue
        #expect(gate.effectiveStatus == overrideValue)
        // gracePeriod 关联值可被 view 解构（CompletedHistoryView 用法）
        if case .gracePeriod(_, let logbookFullUntil) = gate.effectiveStatus {
            #expect(logbookFullUntil == until)
        } else {
            Issue.record("expected .gracePeriod, got \(gate.effectiveStatus)")
        }
    }

    @Test func clearingOverrideReturnsToRawStatus() async {
        let (gate, rc, _) = makeGate()
        await bootstrapActivePro(gate: gate, rc: rc)  // raw .pro
        gate.overrideStatus = .free                  // override .free
        #expect(gate.effectiveStatus == .free)
        gate.overrideStatus = nil                    // clear
        // 回到 raw .pro
        if case .pro = gate.effectiveStatus {} else {
            Issue.record("expected .pro after clear, got \(gate.effectiveStatus)")
        }
    }

    @Test func multipleOverrideSwitchesAreReflected() {
        let (gate, _, _) = makeGate()
        gate.overrideStatus = .free
        #expect(gate.effectiveStatus == .free)

        gate.overrideStatus = .pro(source: .grant, expiresAt: nil)
        if case .pro(.grant, _) = gate.effectiveStatus {} else {
            Issue.record("expected .pro(.grant), got \(gate.effectiveStatus)")
        }

        gate.overrideStatus = .pro(source: .subscription, expiresAt: nil)
        if case .pro(.subscription, _) = gate.effectiveStatus {} else {
            Issue.record("expected .pro(.subscription), got \(gate.effectiveStatus)")
        }
    }

    @Test func proAndLogbookCapabilitiesFollowEffectiveStatusSeparately() {
        let (gate, _, _) = makeGate()
        // raw .unknown → 默认 not premium
        #expect(gate.isPremium == false)
        #expect(gate.allowsFullLogbook == false)

        // override → grace 只保留 Logbook 全历史，不视为完整 Pro
        gate.overrideStatus = .gracePeriod(
            originalExpiry: Date(timeIntervalSinceNow: -1 * 86400),
            logbookFullUntil: Date(timeIntervalSinceNow: 7 * 86400)
        )
        #expect(gate.isPremium == false)
        #expect(gate.allowsFullLogbook == true)

        // override → free 关掉
        gate.overrideStatus = .free
        #expect(gate.isPremium == false)
        #expect(gate.allowsFullLogbook == false)
    }
    #endif
}
