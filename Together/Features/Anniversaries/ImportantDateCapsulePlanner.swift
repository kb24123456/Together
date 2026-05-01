import Foundation

struct ImportantDateCapsuleCandidate: Identifiable, Hashable, Sendable {
    var id: UUID { event.id }
    let event: ImportantDate
    let createdAt: Date
    let daysUntilOrToday: Int
    let isToday: Bool
    let isAnchor: Bool
}

enum ImportantDateCapsulePlanner {
    static let visibilityWindowDays = 7

    static func candidates(
        from records: [ImportantDateStoredRecord],
        referenceDate: Date = .now,
        calendar: Calendar = .current
    ) -> [ImportantDateCapsuleCandidate] {
        let anchor = records
            .filter { isAnchor($0.event) }
            .sorted { lhs, rhs in
                if lhs.createdAt == rhs.createdAt {
                    return lhs.id.uuidString < rhs.id.uuidString
                }
                return lhs.createdAt < rhs.createdAt
            }
            .first

        let nonAnchorCandidates = records
            .filter { !isAnchor($0.event) }
            .compactMap { candidate(from: $0, referenceDate: referenceDate, calendar: calendar) }
            .filter { $0.daysUntilOrToday <= visibilityWindowDays }

        let latest = nonAnchorCandidates
            .max { lhs, rhs in
                if lhs.createdAt == rhs.createdAt {
                    if lhs.event.updatedAt == rhs.event.updatedAt {
                        return lhs.id.uuidString < rhs.id.uuidString
                    }
                    return lhs.event.updatedAt < rhs.event.updatedAt
                }
                return lhs.createdAt < rhs.createdAt
            }

        let remaining = nonAnchorCandidates
            .filter { $0.id != latest?.id }
            .sorted { lhs, rhs in
                if lhs.daysUntilOrToday == rhs.daysUntilOrToday {
                    if lhs.createdAt == rhs.createdAt {
                        if lhs.event.updatedAt == rhs.event.updatedAt {
                            return lhs.id.uuidString < rhs.id.uuidString
                        }
                        return lhs.event.updatedAt > rhs.event.updatedAt
                    }
                    return lhs.createdAt > rhs.createdAt
                }
                return lhs.daysUntilOrToday < rhs.daysUntilOrToday
            }

        var result: [ImportantDateCapsuleCandidate] = []
        if let anchor {
            result.append(anchorCandidate(from: anchor, referenceDate: referenceDate, calendar: calendar))
        }
        if let latest {
            result.append(latest)
        }
        result.append(contentsOf: remaining)
        return result
    }

    static func isAnchor(_ event: ImportantDate) -> Bool {
        if case .anniversary = event.kind { return true }
        return false
    }

    private static func anchorCandidate(
        from record: ImportantDateStoredRecord,
        referenceDate: Date,
        calendar: Calendar
    ) -> ImportantDateCapsuleCandidate {
        let days = daysUntilOrToday(for: record.event, referenceDate: referenceDate, calendar: calendar)
        return ImportantDateCapsuleCandidate(
            event: record.event,
            createdAt: record.createdAt,
            daysUntilOrToday: max(0, days ?? 0),
            isToday: days == 0,
            isAnchor: true
        )
    }

    private static func candidate(
        from record: ImportantDateStoredRecord,
        referenceDate: Date,
        calendar: Calendar
    ) -> ImportantDateCapsuleCandidate? {
        guard let days = daysUntilOrToday(for: record.event, referenceDate: referenceDate, calendar: calendar) else {
            return nil
        }
        return ImportantDateCapsuleCandidate(
            event: record.event,
            createdAt: record.createdAt,
            daysUntilOrToday: days,
            isToday: days == 0,
            isAnchor: false
        )
    }

    private static func daysUntilOrToday(
        for event: ImportantDate,
        referenceDate: Date,
        calendar: Calendar
    ) -> Int? {
        let today = calendar.startOfDay(for: referenceDate)
        let target: Date?

        switch event.recurrence {
        case .none:
            target = calendar.startOfDay(for: event.dateValue)
        case .solarAnnual:
            target = nextSolarAnnualStartOfDay(for: event, referenceDate: today, calendar: calendar)
        case .lunarAnnual:
            target = nextLunarAnnualStartOfDay(for: event, referenceDate: today, calendar: calendar)
        }

        guard let target else { return nil }
        let delta = calendar.dateComponents([.day], from: today, to: target).day ?? 0
        return delta >= 0 ? delta : nil
    }

    private static func nextSolarAnnualStartOfDay(
        for event: ImportantDate,
        referenceDate today: Date,
        calendar: Calendar
    ) -> Date? {
        let month = calendar.component(.month, from: event.dateValue)
        let day = calendar.component(.day, from: event.dateValue)
        var year = calendar.component(.year, from: today)

        for _ in 0..<5 {
            if let candidate = calendar.date(from: DateComponents(year: year, month: month, day: day)),
               calendar.component(.month, from: candidate) == month,
               calendar.component(.day, from: candidate) == day {
                let startOfDay = calendar.startOfDay(for: candidate)
                if startOfDay >= today {
                    return startOfDay
                }
            }

            if month == 2, day == 29,
               let fallback = calendar.date(from: DateComponents(year: year, month: 2, day: 28)) {
                let startOfDay = calendar.startOfDay(for: fallback)
                if startOfDay >= today {
                    return startOfDay
                }
            }

            year += 1
        }

        return nil
    }

    private static func nextLunarAnnualStartOfDay(
        for event: ImportantDate,
        referenceDate today: Date,
        calendar: Calendar
    ) -> Date? {
        var chineseCalendar = Calendar(identifier: .chinese)
        chineseCalendar.timeZone = calendar.timeZone

        let lunarMonth = chineseCalendar.component(.month, from: event.dateValue)
        let lunarDay = chineseCalendar.component(.day, from: event.dateValue)
        var year = chineseCalendar.component(.year, from: today)

        for _ in 0..<5 {
            var components = DateComponents()
            components.calendar = chineseCalendar
            components.timeZone = chineseCalendar.timeZone
            components.year = year
            components.month = lunarMonth
            components.day = lunarDay

            var candidate = chineseCalendar.date(from: components)

            if candidate == nil {
                components.isLeapMonth = false
                candidate = chineseCalendar.date(from: components)
            }

            if let candidate {
                let startOfDay = calendar.startOfDay(for: candidate)
                if startOfDay >= today {
                    return startOfDay
                }
            }

            year += 1
        }

        return nil
    }
}
