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
