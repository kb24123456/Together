import Testing
import Foundation
@testable import Together

@Suite
struct PremiumStatusTests {
    @Test func freeIsNotPremium() {
        #expect(PremiumStatus.free.isPremium == false)
        #expect(PremiumStatus.free.allowsFullLogbook == false)
    }

    @Test func unknownIsNotPremium() {
        #expect(PremiumStatus.unknown.isPremium == false)
        #expect(PremiumStatus.unknown.allowsFullLogbook == false)
    }

    @Test func proIsPremium() {
        let status = PremiumStatus.pro(source: .subscription, expiresAt: nil)
        #expect(status.isPremium)
        #expect(status.allowsFullLogbook)
    }

    @Test func gracePeriodAllowsFullLogbook() {
        let status = PremiumStatus.gracePeriod(
            originalExpiry: Date(timeIntervalSince1970: 1000),
            logbookFullUntil: Date(timeIntervalSince1970: 1000 + 14 * 86400)
        )
        #expect(status.isPremium)
        #expect(status.allowsFullLogbook)
    }

    @Test func codableRoundtripForFree() throws {
        let original = PremiumStatus.free
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(PremiumStatus.self, from: data)
        #expect(decoded == original)
    }

    @Test func codableRoundtripForProWithExpiry() throws {
        let expiry = Date(timeIntervalSince1970: 2000)
        let original = PremiumStatus.pro(source: .grant, expiresAt: expiry)
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(PremiumStatus.self, from: data)
        #expect(decoded == original)
    }

    @Test func codableRoundtripForGrace() throws {
        let original = PremiumStatus.gracePeriod(
            originalExpiry: Date(timeIntervalSince1970: 1000),
            logbookFullUntil: Date(timeIntervalSince1970: 1000 + 14 * 86400)
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(PremiumStatus.self, from: data)
        #expect(decoded == original)
    }
}

@Suite
struct UpsellTriggerTests {
    @Test func allCasesHaveUniqueIDs() {
        let ids: Set<String> = [
            UpsellTrigger.anniversaryQuota.id,
            UpsellTrigger.projectQuota.id,
            UpsellTrigger.logbookHistory.id,
            UpsellTrigger.crossDeviceSync.id
        ]
        #expect(ids.count == 4)
    }

    @Test func identifiableIsStable() {
        // Same case should produce same id twice
        #expect(UpsellTrigger.anniversaryQuota.id == UpsellTrigger.anniversaryQuota.id)
    }
}

@Suite
struct PremiumGateErrorTests {
    @Test func quotaExceededIsEquatable() {
        let a = PremiumGateError.quotaExceeded(limit: 5, feature: .anniversary)
        let b = PremiumGateError.quotaExceeded(limit: 5, feature: .anniversary)
        let c = PremiumGateError.quotaExceeded(limit: 3, feature: .project)
        #expect(a == b)
        #expect(a != c)
    }
}

@Suite
struct DateProviderTests {
    @Test func systemProviderReturnsCurrentTime() {
        let provider = SystemDateProvider()
        let before = Date()
        let mid = provider.now()
        let after = Date()
        #expect(mid >= before && mid <= after)
    }

    @Test func fixedProviderReturnsFixedTime() {
        let fixed = Date(timeIntervalSince1970: 1000)
        let provider = FixedDateProvider(fixed: fixed)
        #expect(provider.now() == fixed)
        #expect(provider.now() == fixed)  // 多次调用仍相同
    }
}
