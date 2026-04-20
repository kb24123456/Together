import Foundation
import Testing
@testable import Together

@Suite
struct ProSubscriptionStatusTests {

    @Test func freeStatusSubtitleIsStatic() {
        let status = ProSubscriptionStatus.free
        #expect(status.subtitleText == "共享仪式、更长历史、自定义主题")
    }

    @Test func trialStatusSubtitleIncludesDaysAndDate() {
        let renewal = date(2026, 5, 25)
        let status = ProSubscriptionStatus.trial(daysLeft: 5, renewalDate: renewal)
        let subtitle = status.subtitleText
        #expect(subtitle.contains("试用剩余 5 天"))
        #expect(subtitle.contains("2026"))
        #expect(subtitle.contains("5"))
    }

    @Test func activeStatusSubtitleIncludesRenewalDate() {
        let renewal = date(2026, 5, 20)
        let status = ProSubscriptionStatus.active(renewalDate: renewal)
        let subtitle = status.subtitleText
        #expect(subtitle.contains("订阅中"))
        #expect(subtitle.contains("2026"))
    }

    @Test func accessibilityStateLabel() {
        #expect(ProSubscriptionStatus.free.accessibilityStateLabel == "升级订阅")
        let active = ProSubscriptionStatus.active(renewalDate: date(2026, 5, 20))
        #expect(active.accessibilityStateLabel.contains("订阅中"))
    }

    // MARK: - Helpers

    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        return Calendar(identifier: .gregorian).date(from: components) ?? .now
    }
}
