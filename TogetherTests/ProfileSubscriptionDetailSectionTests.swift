import Testing
import Foundation
@testable import Together

// MARK: - PremiumStatus.gracePeriodDaysRemaining

@Suite
struct PremiumStatusGraceDaysRemainingTests {
    private static let utc = Calendar(identifier: .gregorian).withTimeZone("UTC")
    private static let day = TimeInterval(86_400)

    private func date(_ iso: String) -> Date {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f.date(from: iso) ?? Date(timeIntervalSince1970: 0)
    }

    @Test func proSubscriptionReturnsNil() {
        let status: PremiumStatus = .pro(source: .subscription, expiresAt: Date())
        #expect(status.gracePeriodDaysRemaining() == nil)
    }

    @Test func proGrantReturnsNil() {
        let status: PremiumStatus = .pro(source: .grant, expiresAt: nil)
        #expect(status.gracePeriodDaysRemaining() == nil)
    }

    @Test func freeReturnsNil() {
        #expect(PremiumStatus.free.gracePeriodDaysRemaining() == nil)
    }

    @Test func unknownReturnsNil() {
        #expect(PremiumStatus.unknown.gracePeriodDaysRemaining() == nil)
    }

    @Test func sevenDaysAhead() {
        let now = date("2026-01-01T00:00:00.000Z")
        let until = now.addingTimeInterval(7 * Self.day)
        let status: PremiumStatus = .gracePeriod(originalExpiry: now, logbookFullUntil: until)
        #expect(status.gracePeriodDaysRemaining(now: now, calendar: Self.utc) == 7)
    }

    @Test func oneDayAhead() {
        let now = date("2026-01-01T00:00:00.000Z")
        let until = now.addingTimeInterval(Self.day)
        let status: PremiumStatus = .gracePeriod(originalExpiry: now, logbookFullUntil: until)
        #expect(status.gracePeriodDaysRemaining(now: now, calendar: Self.utc) == 1)
    }

    @Test func sameInstantUsesMin1Floor() {
        // until == now → diff 0 day，min 1 守卫保证显示 "剩 1 天"
        let now = date("2026-01-01T00:00:00.000Z")
        let status: PremiumStatus = .gracePeriod(originalExpiry: now, logbookFullUntil: now)
        #expect(status.gracePeriodDaysRemaining(now: now, calendar: Self.utc) == 1)
    }

    @Test func pastBoundaryUsesMin1Floor() {
        // until < now（边界过期）→ diff 负，min 1 守卫
        let now = date("2026-01-09T00:00:00.000Z")
        let until = date("2026-01-08T00:00:00.000Z")
        let status: PremiumStatus = .gracePeriod(originalExpiry: until, logbookFullUntil: until)
        #expect(status.gracePeriodDaysRemaining(now: now, calendar: Self.utc) == 1)
    }
}

// MARK: - ProfileSubscriptionDetailSection.expirationText

@Suite
struct ProfileSubscriptionDetailSectionExpirationTextTests {
    @Test func nilReturnsFallback() {
        #expect(ProfileSubscriptionDetailSection.expirationText(nil) == "订阅有效")
    }

    @Test func validDateReturnsFormatted() {
        let date = Date(timeIntervalSince1970: 1_800_000_000)  // 2027-01-15
        let text = ProfileSubscriptionDetailSection.expirationText(date)
        // 重构后 label "有效期" 由 infoRow 提供，本函数只返回日期串。
        #expect(text.contains("2027"))
        #expect(text.hasPrefix("有效期至 ") == false)
    }
}

// MARK: - Helpers

private extension Calendar {
    func withTimeZone(_ identifier: String) -> Calendar {
        var cal = self
        if let tz = TimeZone(identifier: identifier) {
            cal.timeZone = tz
        }
        return cal
    }
}
