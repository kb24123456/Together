import Foundation
import Testing
@testable import Together

@Suite("ImportantDateCapsulePlanner", .serialized)
struct ImportantDateCapsulePlannerTests {
    private let spaceID = UUID()
    private let creatorID = UUID()

    private func date(_ iso: String) -> Date {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: iso)!
    }

    private func calendar(timeZone: TimeZone = TimeZone(secondsFromGMT: 0)!) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar
    }

    private func record(
        id: UUID = UUID(),
        kind: ImportantDateKind,
        title: String,
        dateValue: Date,
        recurrence: Recurrence = .solarAnnual,
        createdAt: Date,
        showsElapsedDays: Bool = false
    ) -> ImportantDateStoredRecord {
        ImportantDateStoredRecord(
            event: ImportantDate(
                id: id,
                spaceID: spaceID,
                creatorID: creatorID,
                kind: kind,
                title: title,
                dateValue: dateValue,
                recurrence: recurrence,
                notifyDaysBefore: 7,
                notifyOnDay: true,
                icon: nil,
                presetHolidayID: nil,
                showsElapsedDays: showsElapsedDays,
                updatedAt: createdAt
            ),
            createdAt: createdAt
        )
    }

    @Test("anniversary is anchor even when title is not literal 在一起的日子")
    func anniversaryAnchorUsesKindNotTitle() {
        let anniversary = record(
            kind: .anniversary,
            title: "我们的纪念日",
            dateValue: date("2025-05-01T00:00:00Z"),
            createdAt: date("2026-01-01T00:00:00Z"),
            showsElapsedDays: true
        )
        let birthday = record(
            kind: .birthday(memberUserID: UUID()),
            title: "我的生日",
            dateValue: date("1990-05-03T00:00:00Z"),
            createdAt: date("2026-04-30T00:00:00Z")
        )

        let candidates = ImportantDateCapsulePlanner.candidates(
            from: [birthday, anniversary],
            referenceDate: date("2026-05-01T12:00:00Z"),
            calendar: calendar()
        )

        #expect(candidates.map(\.event.id) == [anniversary.event.id, birthday.event.id])
        #expect(candidates.first?.isAnchor == true)
    }

    @Test("dates outside seven days do not enter the pool")
    func sevenDayWindowExcludesFarDates() {
        let anniversary = record(
            kind: .anniversary,
            title: "我们的纪念日",
            dateValue: date("2025-05-01T00:00:00Z"),
            createdAt: date("2026-01-01T00:00:00Z"),
            showsElapsedDays: true
        )
        let farBirthday = record(
            kind: .birthday(memberUserID: UUID()),
            title: "我的生日",
            dateValue: date("1990-05-20T00:00:00Z"),
            createdAt: date("2026-04-30T00:00:00Z")
        )

        let candidates = ImportantDateCapsulePlanner.candidates(
            from: [anniversary, farBirthday],
            referenceDate: date("2026-05-01T12:00:00Z"),
            calendar: calendar()
        )

        #expect(candidates.map(\.event.id) == [anniversary.event.id])
    }

    @Test("latest eligible created date is second after anchor")
    func latestEligibleCreatedDateIsSecond() {
        let anniversary = record(
            kind: .anniversary,
            title: "我们的纪念日",
            dateValue: date("2025-05-01T00:00:00Z"),
            createdAt: date("2026-01-01T00:00:00Z"),
            showsElapsedDays: true
        )
        let soonerOlder = record(
            kind: .custom,
            title: "第一次旅行",
            dateValue: date("2025-05-02T00:00:00Z"),
            createdAt: date("2026-04-01T00:00:00Z")
        )
        let laterNewer = record(
            kind: .birthday(memberUserID: UUID()),
            title: "我的生日",
            dateValue: date("1990-05-06T00:00:00Z"),
            createdAt: date("2026-04-30T00:00:00Z")
        )

        let candidates = ImportantDateCapsulePlanner.candidates(
            from: [soonerOlder, laterNewer, anniversary],
            referenceDate: date("2026-05-01T12:00:00Z"),
            calendar: calendar()
        )

        #expect(candidates.map(\.event.id) == [
            anniversary.event.id,
            laterNewer.event.id,
            soonerOlder.event.id
        ])
    }

    @Test("annual event on current day remains in pool and reports today")
    func annualEventTodayIsIncluded() {
        let anniversary = record(
            kind: .anniversary,
            title: "我们的纪念日",
            dateValue: date("2025-01-01T00:00:00Z"),
            createdAt: date("2026-01-01T00:00:00Z"),
            showsElapsedDays: true
        )
        let birthday = record(
            kind: .birthday(memberUserID: UUID()),
            title: "我的生日",
            dateValue: date("1990-05-01T00:00:00Z"),
            createdAt: date("2026-04-30T00:00:00Z")
        )

        let candidates = ImportantDateCapsulePlanner.candidates(
            from: [anniversary, birthday],
            referenceDate: date("2026-05-01T12:00:00Z"),
            calendar: calendar()
        )

        let birthdayCandidate = candidates.first { $0.event.id == birthday.event.id }
        #expect(birthdayCandidate?.daysUntilOrToday == 0)
        #expect(birthdayCandidate?.isToday == true)
    }

    @Test("solar annual calculation uses injected calendar time zone")
    func solarAnnualUsesInjectedCalendarTimeZone() {
        let originalTimeZone = TimeZone.ReferenceType.default
        TimeZone.ReferenceType.default = TimeZone(secondsFromGMT: -8 * 60 * 60)!
        defer { TimeZone.ReferenceType.default = originalTimeZone }

        let anniversary = record(
            kind: .anniversary,
            title: "我们的纪念日",
            dateValue: date("2025-01-01T12:00:00Z"),
            createdAt: date("2026-01-01T00:00:00Z"),
            showsElapsedDays: true
        )
        let birthday = record(
            kind: .birthday(memberUserID: UUID()),
            title: "跨时区生日",
            dateValue: date("1990-05-01T00:30:00Z"),
            createdAt: date("2026-04-30T00:00:00Z")
        )

        let candidates = ImportantDateCapsulePlanner.candidates(
            from: [anniversary, birthday],
            referenceDate: date("2026-05-01T12:00:00Z"),
            calendar: calendar()
        )

        let birthdayCandidate = candidates.first { $0.event.id == birthday.event.id }
        #expect(birthdayCandidate?.daysUntilOrToday == 0)
        #expect(birthdayCandidate?.isToday == true)
    }

    @Test("invalid anchor stays in pool but is not reported as today")
    func invalidAnchorIsNotReportedAsToday() {
        let anniversary = record(
            kind: .anniversary,
            title: "旧纪念日",
            dateValue: date("2020-01-01T00:00:00Z"),
            recurrence: .none,
            createdAt: date("2026-01-01T00:00:00Z"),
            showsElapsedDays: true
        )

        let candidates = ImportantDateCapsulePlanner.candidates(
            from: [anniversary],
            referenceDate: date("2026-05-01T12:00:00Z"),
            calendar: calendar()
        )

        #expect(candidates.map(\.event.id) == [anniversary.event.id])
        #expect(candidates.first?.daysUntilOrToday == 0)
        #expect(candidates.first?.isToday == false)
    }

    @Test("non-recurring today enters pool and reports today")
    func nonRecurringTodayEntersPool() {
        let anniversary = record(
            kind: .anniversary,
            title: "我们的纪念日",
            dateValue: date("2025-01-01T00:00:00Z"),
            createdAt: date("2026-01-01T00:00:00Z"),
            showsElapsedDays: true
        )
        let oneOff = record(
            kind: .custom,
            title: "今天的一次性事件",
            dateValue: date("2026-05-01T00:00:00Z"),
            recurrence: .none,
            createdAt: date("2026-04-30T00:00:00Z")
        )

        let candidates = ImportantDateCapsulePlanner.candidates(
            from: [anniversary, oneOff],
            referenceDate: date("2026-05-01T12:00:00Z"),
            calendar: calendar()
        )

        let oneOffCandidate = candidates.first { $0.event.id == oneOff.event.id }
        #expect(oneOffCandidate?.daysUntilOrToday == 0)
        #expect(oneOffCandidate?.isToday == true)
    }

    @Test("non-recurring future date within seven days enters pool")
    func nonRecurringFutureWithinWindowEntersPool() {
        let anniversary = record(
            kind: .anniversary,
            title: "我们的纪念日",
            dateValue: date("2025-01-01T00:00:00Z"),
            createdAt: date("2026-01-01T00:00:00Z"),
            showsElapsedDays: true
        )
        let oneOff = record(
            kind: .custom,
            title: "即将发生的一次性事件",
            dateValue: date("2026-05-08T00:00:00Z"),
            recurrence: .none,
            createdAt: date("2026-04-30T00:00:00Z")
        )

        let candidates = ImportantDateCapsulePlanner.candidates(
            from: [anniversary, oneOff],
            referenceDate: date("2026-05-01T12:00:00Z"),
            calendar: calendar()
        )

        let oneOffCandidate = candidates.first { $0.event.id == oneOff.event.id }
        #expect(oneOffCandidate?.daysUntilOrToday == 7)
        #expect(oneOffCandidate?.isToday == false)
    }

    @Test("non-recurring past date is excluded from pool")
    func nonRecurringPastDateIsExcluded() {
        let anniversary = record(
            kind: .anniversary,
            title: "我们的纪念日",
            dateValue: date("2025-01-01T00:00:00Z"),
            createdAt: date("2026-01-01T00:00:00Z"),
            showsElapsedDays: true
        )
        let oneOff = record(
            kind: .custom,
            title: "已过去的一次性事件",
            dateValue: date("2026-04-30T00:00:00Z"),
            recurrence: .none,
            createdAt: date("2026-04-30T00:00:00Z")
        )

        let candidates = ImportantDateCapsulePlanner.candidates(
            from: [anniversary, oneOff],
            referenceDate: date("2026-05-01T12:00:00Z"),
            calendar: calendar()
        )

        #expect(candidates.map(\.event.id) == [anniversary.event.id])
    }
}
