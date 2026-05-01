import Foundation
import Testing
@testable import Together

@Suite("ImportantDateCapsulePlanner")
struct ImportantDateCapsulePlannerTests {
    private let spaceID = UUID()
    private let creatorID = UUID()

    private func date(_ iso: String) -> Date {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: iso)!
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
            calendar: Calendar(identifier: .gregorian)
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
            calendar: Calendar(identifier: .gregorian)
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
            calendar: Calendar(identifier: .gregorian)
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
            calendar: Calendar(identifier: .gregorian)
        )

        let birthdayCandidate = candidates.first { $0.event.id == birthday.event.id }
        #expect(birthdayCandidate?.daysUntilOrToday == 0)
        #expect(birthdayCandidate?.isToday == true)
    }
}
