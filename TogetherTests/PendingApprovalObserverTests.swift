import Testing
import Foundation
import OSLog
@testable import Together

@MainActor
@Suite
struct PendingApprovalObserverTests {

    // MARK: - Helpers

    private func makeObserver() -> PendingApprovalObserver {
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        let date = FixedDateProvider(fixed: Date())
        let cache = PremiumStatusCache(defaults: defaults, dateProvider: date)
        let gate = PremiumGate(
            rcClient: StubRCClient(),
            grantsLoader: StubGrantsLoader(),
            cache: cache,
            dateProvider: date
        )
        return PendingApprovalObserver(
            premiumGate: gate,
            logger: Logger(subsystem: "test", category: "pending_approval")
        )
    }

    private static let proSubscription: PremiumStatus = .pro(source: .subscription, expiresAt: Date(timeIntervalSinceNow: 3600))
    private static let proGrant: PremiumStatus = .pro(source: .grant, expiresAt: nil)
    private static let grace: PremiumStatus = .gracePeriod(
        originalExpiry: Date(timeIntervalSinceNow: -3600),
        logbookFullUntil: Date(timeIntervalSinceNow: 7 * 86400)
    )

    // MARK: - Edge cases

    @Test func unknownToProTriggersActivation() {
        let observer = makeObserver()
        var captured: (PremiumStatus, PremiumStatus)?
        observer.onActivation = { from, to in captured = (from, to) }

        observer.recordStatus(.unknown)
        observer.recordStatus(Self.proSubscription)

        #expect(captured != nil)
        #expect(captured?.0 == .unknown)
        #expect(captured?.1 == Self.proSubscription)
    }

    @Test func freeToProTriggersActivation() {
        let observer = makeObserver()
        var count = 0
        observer.onActivation = { _, _ in count += 1 }

        observer.recordStatus(.free)
        observer.recordStatus(Self.proSubscription)

        #expect(count == 1)
    }

    @Test func gracePeriodToProTriggersActivation() {
        // grace 只保留 Logbook，不再等同完整 Pro；续订回 Pro 应触发激活边沿。
        let observer = makeObserver()
        var count = 0
        observer.onActivation = { _, _ in count += 1 }

        observer.recordStatus(Self.grace)
        observer.recordStatus(Self.proSubscription)

        #expect(count == 1)
    }

    @Test func proToFreeDoesNotTrigger() {
        let observer = makeObserver()
        var count = 0
        observer.onActivation = { _, _ in count += 1 }

        observer.recordStatus(Self.proSubscription)
        observer.recordStatus(.free)

        #expect(count == 0)
    }

    @Test func freeToFreeDoesNotTrigger() {
        let observer = makeObserver()
        var count = 0
        observer.onActivation = { _, _ in count += 1 }

        observer.recordStatus(.free)
        observer.recordStatus(.free)

        #expect(count == 0)
    }

    @Test func freeToGraceDoesNotTrigger() {
        // grace 不是 .pro case → 不算激活
        let observer = makeObserver()
        var count = 0
        observer.onActivation = { _, _ in count += 1 }

        observer.recordStatus(.free)
        observer.recordStatus(Self.grace)

        #expect(count == 0)
    }

    @Test func multipleCyclesEachTrigger() {
        // free → pro → free → pro → free → pro 触发 3 次
        let observer = makeObserver()
        var count = 0
        observer.onActivation = { _, _ in count += 1 }

        observer.recordStatus(.free)
        observer.recordStatus(Self.proSubscription)
        observer.recordStatus(.free)
        observer.recordStatus(Self.proSubscription)
        observer.recordStatus(.free)
        observer.recordStatus(Self.proSubscription)

        #expect(count == 3)
    }

    @Test func firstStatusDoesNotTrigger() {
        // 首次 record 时 lastSeenStatus 为 nil，不触发
        let observer = makeObserver()
        var count = 0
        observer.onActivation = { _, _ in count += 1 }

        observer.recordStatus(Self.proSubscription)

        #expect(count == 0)
    }

    @Test func grantSourceAlsoTriggers() {
        // .pro(.grant) 也算 .pro case
        let observer = makeObserver()
        var count = 0
        observer.onActivation = { _, _ in count += 1 }

        observer.recordStatus(.free)
        observer.recordStatus(Self.proGrant)

        #expect(count == 1)
    }
}
