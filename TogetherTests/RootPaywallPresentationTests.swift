import Testing
import Foundation
@testable import Together

private func makeLapse(_ key: String) -> PremiumLapseNotice {
    PremiumLapseNotice(
        entitlementExpiredAt: Date(timeIntervalSince1970: 1_000_000),
        detectedAt: Date(timeIntervalSince1970: 1_100_000),
        dedupKey: key
    )
}

@MainActor
@Suite
struct RootPaywallPresentationBasicTests {
    @Test func emptyRequestTriggerPresentsImmediately() {
        let p = RootPaywallPresentation()
        p.requestTrigger(.projectQuota)
        #expect(p.presenting == .quota(.projectQuota))
        #expect(p.queue.isEmpty)
    }

    @Test func emptyRequestLapsePresentsImmediately() {
        let p = RootPaywallPresentation()
        let n = makeLapse("k1")
        p.requestLapse(n)
        #expect(p.presenting == .lapse(n))
        #expect(p.queue.isEmpty)
    }

    @Test func dismissCurrentOnLastClearsPresenting() {
        let p = RootPaywallPresentation()
        p.requestTrigger(.projectQuota)
        p.dismissCurrent()
        #expect(p.presenting == nil)
    }

    @Test func dismissWithEmptyStateIsNoOp() {
        let p = RootPaywallPresentation()
        p.dismissCurrent()
        #expect(p.presenting == nil)
        #expect(p.queue.isEmpty)
    }
}

@MainActor
@Suite
struct RootPaywallPresentationQueueOrderTests {
    @Test func secondTriggerGoesToQueue() {
        let p = RootPaywallPresentation()
        p.requestTrigger(.projectQuota)
        p.requestTrigger(.anniversaryQuota)
        #expect(p.presenting == .quota(.projectQuota))
        #expect(p.queue == [.quota(.anniversaryQuota)])
    }

    @Test func lapseInsertsAtQueueHeadWithoutPreempting() {
        let p = RootPaywallPresentation()
        p.requestTrigger(.projectQuota)
        p.requestTrigger(.anniversaryQuota)
        let n = makeLapse("k1")
        p.requestLapse(n)

        #expect(p.presenting == .quota(.projectQuota))
        #expect(p.queue == [.lapse(n), .quota(.anniversaryQuota)])
    }

    @Test func dismissPopsQueueHead() {
        let p = RootPaywallPresentation()
        p.requestTrigger(.projectQuota)
        p.requestTrigger(.anniversaryQuota)
        p.dismissCurrent()
        #expect(p.presenting == .quota(.anniversaryQuota))
        #expect(p.queue.isEmpty)
    }

    @Test func lapseWinsOverQueuedTriggerAfterDismiss() {
        let p = RootPaywallPresentation()
        p.requestTrigger(.projectQuota)
        p.requestTrigger(.anniversaryQuota)   // queue: [anniversary]
        let n = makeLapse("k1")
        p.requestLapse(n)                      // queue: [lapse, anniversary]

        p.dismissCurrent()                     // projectQuota 关 → lapse 登场
        #expect(p.presenting == .lapse(n))
        #expect(p.queue == [.quota(.anniversaryQuota)])

        p.dismissCurrent()
        #expect(p.presenting == .quota(.anniversaryQuota))
    }
}

@MainActor
@Suite
struct RootPaywallPresentationDedupTests {
    @Test func duplicateTriggerInQueueIsDropped() {
        let p = RootPaywallPresentation()
        p.requestTrigger(.projectQuota)
        p.requestTrigger(.anniversaryQuota)
        p.requestTrigger(.anniversaryQuota)
        #expect(p.queue == [.quota(.anniversaryQuota)])
    }

    @Test func triggerSameAsPresentingIsDropped() {
        let p = RootPaywallPresentation()
        p.requestTrigger(.projectQuota)
        p.requestTrigger(.projectQuota)
        #expect(p.presenting == .quota(.projectQuota))
        #expect(p.queue.isEmpty)
    }

    @Test func duplicateLapseIsDroppedByDedupKey() {
        let p = RootPaywallPresentation()
        let n = makeLapse("k1")
        p.requestLapse(n)
        p.requestLapse(n)
        p.requestLapse(makeLapse("k1"))   // 相同 dedupKey → 同 Kind
        #expect(p.presenting == .lapse(n))
        #expect(p.queue.isEmpty)
    }

    @Test func differentLapseDedupKeysCoexist() {
        let p = RootPaywallPresentation()
        let n1 = makeLapse("k1")
        let n2 = makeLapse("k2")
        p.requestTrigger(.projectQuota)
        p.requestLapse(n1)
        p.requestLapse(n2)
        // 两个 lapse 都插队头，后来者更靠前
        #expect(p.queue == [.lapse(n2), .lapse(n1)])
    }

    @Test func graceExpiringSkipsDedupSameValue() {
        // Session B Task 12: grace 主动续订点击不应被合并器吃掉
        let p = RootPaywallPresentation()
        p.requestTrigger(.anniversaryQuota)
        p.requestTrigger(.graceExpiring(daysRemaining: 7))
        p.requestTrigger(.graceExpiring(daysRemaining: 7))   // 第二次相同 N
        #expect(p.queue == [
            .quota(.graceExpiring(daysRemaining: 7)),
            .quota(.graceExpiring(daysRemaining: 7))
        ])
    }

    @Test func graceExpiringDifferentValuesAlsoCoexist() {
        let p = RootPaywallPresentation()
        p.requestTrigger(.projectQuota)
        p.requestTrigger(.graceExpiring(daysRemaining: 7))
        p.requestTrigger(.graceExpiring(daysRemaining: 5))
        #expect(p.queue == [
            .quota(.graceExpiring(daysRemaining: 7)),
            .quota(.graceExpiring(daysRemaining: 5))
        ])
    }

    @Test func nonGraceQuotaStillDeduped() {
        // 守卫：dedup skip 仅作用于 graceExpiring；其他 quota case 仍 dedup
        let p = RootPaywallPresentation()
        p.requestTrigger(.projectQuota)
        p.requestTrigger(.anniversaryQuota)
        p.requestTrigger(.anniversaryQuota)   // 应被 dedup
        #expect(p.queue == [.quota(.anniversaryQuota)])
    }
}

@MainActor
@Suite
struct RootPaywallPresentationKindMappingTests {
    @Test func quotaMapsToTrigger() {
        let k = RootPaywallPresentation.Kind.quota(.projectQuota)
        #expect(k.toDisplayKind() == .trigger(.projectQuota))
    }

    @Test func lapseMapsToLapseDisplayKind() {
        let n = makeLapse("k1")
        let k = RootPaywallPresentation.Kind.lapse(n)
        #expect(k.toDisplayKind() == .lapse(n))
    }

    @Test func idCombinesPrefixWithIdentifier() {
        let k1 = RootPaywallPresentation.Kind.quota(.anniversaryQuota)
        #expect(k1.id == "quota:anniversary_quota")
        let k2 = RootPaywallPresentation.Kind.lapse(makeLapse("abc"))
        #expect(k2.id == "lapse:abc")
    }
}
