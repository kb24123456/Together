import Testing
import Foundation
@testable import Together

@Suite
struct GracePeriodBannerDaysRemainingTests {
    private static let utc: Calendar = {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        return cal
    }()

    private static let day: TimeInterval = 86_400

    private func date(_ iso: String) -> Date {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f.date(from: iso)!
    }

    @Test func sevenDaysAhead() {
        let now = date("2026-01-01T00:00:00.000Z")
        let until = now.addingTimeInterval(7 * Self.day)
        #expect(GracePeriodBanner.daysRemaining(now: now, until: until, calendar: Self.utc) == 7)
    }

    @Test func oneDayAhead() {
        let now = date("2026-01-01T00:00:00.000Z")
        let until = now.addingTimeInterval(Self.day)
        #expect(GracePeriodBanner.daysRemaining(now: now, until: until, calendar: Self.utc) == 1)
    }

    @Test func sameInstantUsesMin1Floor() {
        let now = date("2026-01-01T00:00:00.000Z")
        #expect(GracePeriodBanner.daysRemaining(now: now, until: now, calendar: Self.utc) == 1)
    }

    @Test func pastBoundaryUsesMin1Floor() {
        let now = date("2026-01-09T00:00:00.000Z")
        let until = date("2026-01-08T00:00:00.000Z")
        #expect(GracePeriodBanner.daysRemaining(now: now, until: until, calendar: Self.utc) == 1)
    }

    @Test func thirteenDaysAhead() {
        // 14 天宽限期内典型中段
        let now = date("2026-01-01T00:00:00.000Z")
        let until = now.addingTimeInterval(13 * Self.day)
        #expect(GracePeriodBanner.daysRemaining(now: now, until: until, calendar: Self.utc) == 13)
    }
}
