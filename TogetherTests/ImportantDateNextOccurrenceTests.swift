import Testing
import Foundation
@testable import Together

@Suite("ImportantDate.nextOccurrence")
struct ImportantDateNextOccurrenceTests {

    private func makeEvent(
        dateValue: Date,
        recurrence: Recurrence,
        kind: ImportantDateKind = .custom
    ) -> ImportantDate {
        ImportantDate(
            id: UUID(),
            spaceID: UUID(),
            creatorID: UUID(),
            kind: kind,
            title: "Test",
            dateValue: dateValue,
            recurrence: recurrence,
            notifyDaysBefore: 7,
            notifyOnDay: true,
            icon: nil,
            presetHolidayID: nil,
            updatedAt: .now
        )
    }

    private func date(_ isoString: String) -> Date {
        let fmt = ISO8601DateFormatter()
        fmt.formatOptions = [.withInternetDateTime]
        return fmt.date(from: isoString)!
    }

    @Test("solarAnnual: date is later this year — returns this year's date")
    func solarThisYearUpcoming() {
        let event = makeEvent(
            dateValue: date("2020-05-20T00:00:00Z"),
            recurrence: .solarAnnual
        )
        let reference = date("2026-01-15T00:00:00Z")
        let next = event.nextOccurrence(after: reference)
        let cal = Calendar(identifier: .gregorian)
        #expect(cal.component(.year, from: next!) == 2026)
        #expect(cal.component(.month, from: next!) == 5)
        #expect(cal.component(.day, from: next!) == 20)
    }

    @Test("solarAnnual: date already passed this year — rolls to next year")
    func solarThisYearPassed() {
        let event = makeEvent(
            dateValue: date("2020-02-14T00:00:00Z"),
            recurrence: .solarAnnual
        )
        let reference = date("2026-06-01T00:00:00Z")
        let next = event.nextOccurrence(after: reference)
        let cal = Calendar(identifier: .gregorian)
        #expect(cal.component(.year, from: next!) == 2027)
        #expect(cal.component(.month, from: next!) == 2)
        #expect(cal.component(.day, from: next!) == 14)
    }

    @Test("lunarAnnual: qixi 2026 — 农历 7/7 对应公历 2026/8/19")
    func lunarQixi2026() {
        // 2020-08-25 is 农历 2020/7/7 (qixi)
        let event = makeEvent(
            dateValue: date("2020-08-25T00:00:00Z"),
            recurrence: .lunarAnnual,
            kind: .holiday
        )
        let reference = date("2026-01-01T00:00:00Z")
        let next = event.nextOccurrence(after: reference)
        #expect(next != nil)
        let cal = Calendar(identifier: .gregorian)
        // 2026 qixi is August 19
        #expect(cal.component(.year, from: next!) == 2026)
        #expect(cal.component(.month, from: next!) == 8)
        #expect(cal.component(.day, from: next!) == 19)
    }

    @Test("lunarAnnual: current year already passed — rolls to next")
    func lunarAfterEvent() {
        // 农历 1/1 (春节) — 2026 春节 2/17
        let event = makeEvent(
            dateValue: date("2020-01-25T00:00:00Z"),  // 2020 春节公历日期
            recurrence: .lunarAnnual
        )
        let reference = date("2026-03-01T00:00:00Z")  // 已过 2026 春节
        let next = event.nextOccurrence(after: reference)
        #expect(next != nil)
        let cal = Calendar(identifier: .gregorian)
        // 2027 春节公历 2/6
        #expect(cal.component(.year, from: next!) == 2027)
    }

    @Test("none recurrence: past event returns nil")
    func nonRecurringPast() {
        let event = makeEvent(
            dateValue: date("2020-01-01T00:00:00Z"),
            recurrence: .none
        )
        let next = event.nextOccurrence(after: .now)
        #expect(next == nil)
    }

    @Test("none recurrence: future event returns that date")
    func nonRecurringFuture() {
        let future = Date.now.addingTimeInterval(60 * 60 * 24 * 30)  // +30 days
        let event = makeEvent(dateValue: future, recurrence: .none)
        let next = event.nextOccurrence(after: .now)
        #expect(next == future)
    }

    @Test("solarAnnual: Feb 29 birthday in non-leap year falls back to Feb 28")
    func solarFeb29InNonLeapYear() {
        // 2000 was a leap year, so Feb 29 is a valid source date.
        let event = makeEvent(
            dateValue: date("2000-02-29T00:00:00Z"),
            recurrence: .solarAnnual
        )
        // 2025 is non-leap (100-rule: divisible by 4 but 2100 is not; 2025 isn't
        // divisible by 4 at all). Reference Jan 1 2025 → expect Feb 28 2025.
        let reference = date("2025-01-01T00:00:00Z")
        let next = event.nextOccurrence(after: reference)
        #expect(next != nil)
        let cal = Calendar(identifier: .gregorian)
        #expect(cal.component(.year, from: next!) == 2025)
        #expect(cal.component(.month, from: next!) == 2)
        #expect(cal.component(.day, from: next!) == 28)
    }

    @Test("solarAnnual: Feb 29 birthday in leap year returns real Feb 29")
    func solarFeb29InLeapYear() {
        let event = makeEvent(
            dateValue: date("2000-02-29T00:00:00Z"),
            recurrence: .solarAnnual
        )
        // 2028 is a leap year. Reference Jan 1 2028 → expect Feb 29 2028.
        let reference = date("2028-01-01T00:00:00Z")
        let next = event.nextOccurrence(after: reference)
        #expect(next != nil)
        let cal = Calendar(identifier: .gregorian)
        #expect(cal.component(.year, from: next!) == 2028)
        #expect(cal.component(.month, from: next!) == 2)
        #expect(cal.component(.day, from: next!) == 29)
    }

    @Test("solarAnnual: reference several non-leap years before next leap year resolves")
    func solarFeb29LongGap() {
        // Reference 2025-03-01 (past Feb 28 of a non-leap year, so can't fall
        // back to 2025-02-28). Next occurrence should be 2026-02-28 (the
        // year-1 fallback) since 2026 is still non-leap.
        let event = makeEvent(
            dateValue: date("2000-02-29T00:00:00Z"),
            recurrence: .solarAnnual
        )
        let reference = date("2025-03-01T00:00:00Z")
        let next = event.nextOccurrence(after: reference)
        #expect(next != nil)
        let cal = Calendar(identifier: .gregorian)
        #expect(cal.component(.year, from: next!) == 2026)
        #expect(cal.component(.month, from: next!) == 2)
        #expect(cal.component(.day, from: next!) == 28)
    }
}
