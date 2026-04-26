import XCTest
@testable import Together

final class ImportantDateDisplayModeTests: XCTestCase {

    private func makeEvent(
        kind: ImportantDateKind,
        anchor: Date,
        recurrence: Recurrence
    ) -> ImportantDate {
        ImportantDate(
            id: UUID(),
            spaceID: UUID(),
            creatorID: UUID(),
            kind: kind,
            title: "test",
            dateValue: anchor,
            recurrence: recurrence,
            notifyDaysBefore: 7,
            notifyOnDay: true,
            icon: nil,
            presetHolidayID: nil,
            updatedAt: .now
        )
    }

    private var now: Date { Calendar.current.startOfDay(for: .now) }
    private var futureAnchor: Date { Calendar.current.date(byAdding: .day, value: 60, to: now)! }
    private var pastAnchor: Date { Calendar.current.date(byAdding: .year, value: -2, to: now)! }

    func test_anchorInFuture_alwaysCountdown() {
        for kind in [ImportantDateKind.anniversary, .holiday, .custom, .birthday(memberUserID: UUID())] {
            let e = makeEvent(kind: kind, anchor: futureAnchor, recurrence: .none)
            XCTAssertEqual(e.selectMode(now: now), .countdown, "kind=\(kind) anchor in future should be countdown")
        }
    }

    func test_birthday_pastAnchor_recurring_isCountdown() {
        let e = makeEvent(kind: .birthday(memberUserID: UUID()), anchor: pastAnchor, recurrence: .solarAnnual)
        XCTAssertEqual(e.selectMode(now: now), .countdown)
    }

    func test_holiday_pastAnchor_recurring_isCountdown() {
        let e = makeEvent(kind: .holiday, anchor: pastAnchor, recurrence: .solarAnnual)
        XCTAssertEqual(e.selectMode(now: now), .countdown)
    }

    func test_anniversary_pastAnchor_recurring_farFromNext_isForwardCount() {
        // anchor 2 years ago today, solarAnnual → next occurrence is ~365 days away → forwardCount.
        let twoYearsAgoToday = Calendar.current.date(byAdding: .year, value: -2, to: now)!
        let e = makeEvent(kind: .anniversary, anchor: twoYearsAgoToday, recurrence: .solarAnnual)
        XCTAssertEqual(e.selectMode(now: now), .forwardCount)
    }

    func test_anniversary_pastAnchor_recurring_within30Days_flipsCountdown() {
        // anchor 2 years ago + 20 days → next occurrence ~20 days away (< 30) → countdown.
        let recentAnniversaryDay = Calendar.current.date(byAdding: .day, value: 20, to: now)!
        let twoYearsBack = Calendar.current.date(byAdding: .year, value: -2, to: recentAnniversaryDay)!
        let e = makeEvent(kind: .anniversary, anchor: twoYearsBack, recurrence: .solarAnnual)
        XCTAssertEqual(e.selectMode(now: now), .countdown)
    }

    func test_custom_pastAnchor_noneRecurrence_isForwardCount() {
        let e = makeEvent(kind: .custom, anchor: pastAnchor, recurrence: .none)
        XCTAssertEqual(e.selectMode(now: now), .forwardCount)
    }

    func test_custom_pastAnchor_recurring_sameRuleAsAnniversary() {
        let twoYearsAgoToday = Calendar.current.date(byAdding: .year, value: -2, to: now)!
        let e = makeEvent(kind: .custom, anchor: twoYearsAgoToday, recurrence: .solarAnnual)
        XCTAssertEqual(e.selectMode(now: now), .forwardCount)
    }
}
