import Foundation

enum ImportantDateKind: Hashable, Sendable {
    case birthday(memberUserID: UUID)
    case anniversary
    case holiday
    case custom

    var rawValue: String {
        switch self {
        case .birthday: return "birthday"
        case .anniversary: return "anniversary"
        case .holiday: return "holiday"
        case .custom: return "custom"
        }
    }
}

enum Recurrence: String, Hashable, Sendable, Codable {
    case none
    case solarAnnual
    case lunarAnnual

    var supabaseValue: String? {
        switch self {
        case .none: return nil
        case .solarAnnual: return "solar_annual"
        case .lunarAnnual: return "lunar_annual"
        }
    }

    init(supabaseValue: String?) {
        switch supabaseValue {
        case "solar_annual": self = .solarAnnual
        case "lunar_annual": self = .lunarAnnual
        default: self = .none
        }
    }
}

enum PresetHolidayID: String, CaseIterable, Sendable, Codable {
    case valentines
    case qixi
    case springFestival

    var defaultTitle: String {
        switch self {
        case .valentines: return "情人节"
        case .qixi: return "七夕"
        case .springFestival: return "春节"
        }
    }

    var defaultIcon: String {
        switch self {
        case .valentines: return "heart.fill"
        case .qixi: return "sparkles"
        case .springFestival: return "party.popper.fill"
        }
    }

    var recurrence: Recurrence {
        switch self {
        case .valentines: return .solarAnnual
        case .qixi, .springFestival: return .lunarAnnual
        }
    }

    /// Month/day in the relevant calendar (solar for valentines, lunar for qixi/spring).
    var monthDay: (month: Int, day: Int) {
        switch self {
        case .valentines: return (2, 14)       // solar
        case .qixi: return (7, 7)              // lunar
        case .springFestival: return (1, 1)    // lunar
        }
    }
}

struct ImportantDate: Identifiable, Hashable, Sendable {
    let id: UUID
    let spaceID: UUID
    let creatorID: UUID
    var kind: ImportantDateKind
    var title: String
    var dateValue: Date
    var recurrence: Recurrence
    var notifyDaysBefore: Int
    var notifyOnDay: Bool
    var icon: String?
    var presetHolidayID: PresetHolidayID?
    var updatedAt: Date

    static let validNotifyDaysBefore: [Int] = [1, 3, 7, 15, 30]
}

extension ImportantDate {
    /// Returns the next occurrence strictly after `reference`, or nil if this is
    /// a non-recurring event that has already passed.
    func nextOccurrence(after reference: Date, calendar: Calendar = .current) -> Date? {
        switch recurrence {
        case .none:
            return dateValue > reference ? dateValue : nil
        case .solarAnnual:
            return nextSolarOccurrence(after: reference, calendar: calendar)
        case .lunarAnnual:
            return nextLunarOccurrence(after: reference)
        }
    }

    private func nextSolarOccurrence(after reference: Date, calendar: Calendar) -> Date? {
        var gregorian = calendar
        gregorian.timeZone = .current
        let month = gregorian.component(.month, from: dateValue)
        let day = gregorian.component(.day, from: dateValue)
        var year = gregorian.component(.year, from: reference)

        // Loop 5 iterations to always find the next leap-year Feb 29 if that's
        // the source date. For non-Feb-29 birthdays, 2 iterations would suffice;
        // 5 just gives headroom.
        for _ in 0..<5 {
            // Calendar.date(from:) silently wraps invalid components (Feb 29
            // in a non-leap year → Mar 1), so we must validate that the returned
            // date actually has the month/day we asked for.
            if let candidate = gregorian.date(from: DateComponents(year: year, month: month, day: day)),
               gregorian.component(.month, from: candidate) == month,
               gregorian.component(.day, from: candidate) == day,
               candidate > reference {
                return candidate
            }
            // Feb 29 fallback: in a non-leap year, celebrate on Feb 28.
            // Matches iOS Calendar / Reminders convention.
            if month == 2, day == 29,
               let fallback = gregorian.date(from: DateComponents(year: year, month: 2, day: 28)),
               fallback > reference {
                return fallback
            }
            year += 1
        }
        return nil
    }

    private func nextLunarOccurrence(after reference: Date) -> Date? {
        var chineseCal = Calendar(identifier: .chinese)
        chineseCal.timeZone = .current
        let lunarMonth = chineseCal.component(.month, from: dateValue)
        let lunarDay = chineseCal.component(.day, from: dateValue)
        var year = chineseCal.component(.year, from: reference)

        // Loop 5 iterations so leap-month sources still find the next valid
        // lunar year within a reasonable window.
        for _ in 0..<5 {
            var comps = DateComponents()
            comps.year = year
            comps.month = lunarMonth
            comps.day = lunarDay
            var candidate = chineseCal.date(from: comps)

            // Leap-month fallback: if this year lacks the leap month, drop the flag.
            if candidate == nil {
                comps.isLeapMonth = false
                candidate = chineseCal.date(from: comps)
            }

            if let candidate, candidate > reference {
                return candidate
            }
            year += 1
        }
        return nil
    }

    func daysUntilNext(from reference: Date = .now, calendar: Calendar = .current) -> Int? {
        guard let next = nextOccurrence(after: reference, calendar: calendar) else { return nil }
        let start = calendar.startOfDay(for: reference)
        let end = calendar.startOfDay(for: next)
        return calendar.dateComponents([.day], from: start, to: end).day
    }

    var daysSinceStart: Int {
        let cal = Calendar.current
        let start = cal.startOfDay(for: dateValue)
        let now = cal.startOfDay(for: .now)
        return cal.dateComponents([.day], from: start, to: now).day ?? 0
    }
}
