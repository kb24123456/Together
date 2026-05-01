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
            .sorted { $0.createdAt < $1.createdAt }
            .first

        let nonAnchorCandidates = records
            .filter { !isAnchor($0.event) }
            .compactMap { candidate(from: $0, referenceDate: referenceDate, calendar: calendar) }
            .filter { $0.daysUntilOrToday <= visibilityWindowDays }

        let latestEligibleID = nonAnchorCandidates
            .max { lhs, rhs in
                if lhs.createdAt == rhs.createdAt {
                    return lhs.event.updatedAt < rhs.event.updatedAt
                }
                return lhs.createdAt < rhs.createdAt
            }?
            .id

        let latest = nonAnchorCandidates.filter { $0.id == latestEligibleID }
        let remaining = nonAnchorCandidates
            .filter { $0.id != latestEligibleID }
            .sorted { lhs, rhs in
                if lhs.daysUntilOrToday == rhs.daysUntilOrToday {
                    if lhs.createdAt == rhs.createdAt {
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
        result.append(contentsOf: latest)
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
        let days = daysUntilOrToday(for: record.event, referenceDate: referenceDate, calendar: calendar) ?? 0
        return ImportantDateCapsuleCandidate(
            event: record.event,
            createdAt: record.createdAt,
            daysUntilOrToday: max(0, days),
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
        case .solarAnnual, .lunarAnnual:
            let previousDay = calendar.date(byAdding: .day, value: -1, to: today) ?? today
            target = event.nextOccurrence(after: previousDay, calendar: calendar).map {
                calendar.startOfDay(for: $0)
            }
        }

        guard let target else { return nil }
        let delta = calendar.dateComponents([.day], from: today, to: target).day ?? 0
        return delta >= 0 ? delta : nil
    }
}
