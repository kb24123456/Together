import Foundation

enum HomeTaskDateLabel {
    static func text(for item: Item, calendar: Calendar = .current) -> String {
        if let dueAt = item.dueAt {
            guard item.hasExplicitTime else {
                return monthDayText(for: dueAt, calendar: calendar)
            }
            return hourMinuteText(for: dueAt, calendar: calendar)
        }

        return monthDayText(for: item.createdAt, calendar: calendar)
    }

    private static func monthDayText(for date: Date, calendar: Calendar) -> String {
        let components = calendar.dateComponents([.month, .day], from: date)
        let month = components.month ?? 1
        let day = components.day ?? 1
        return "\(month)月\(day)日"
    }

    private static func hourMinuteText(for date: Date, calendar: Calendar) -> String {
        let components = calendar.dateComponents([.hour, .minute], from: date)
        let hour = components.hour ?? 0
        let minute = components.minute ?? 0
        return String(format: "%02d:%02d", hour, minute)
    }
}

enum CompletedTaskRange: Hashable, Sendable {
    case today
    case workweekExcludingToday
    case workweek
    case month
    case all

    func bounds(for date: Date, calendar: Calendar = .current) -> CompletedTaskRangeBounds {
        switch self {
        case .today:
            let start = calendar.startOfDay(for: date)
            let end = calendar.date(byAdding: .day, value: 1, to: start) ?? start
            return CompletedTaskRangeBounds(lowerBound: start, upperBound: end)
        case .workweekExcludingToday:
            let workweek = Self.workweekBounds(for: date, calendar: calendar)
            let todayStart = calendar.startOfDay(for: date)
            let upperBound = min(todayStart, workweek.upperBound ?? todayStart)
            return CompletedTaskRangeBounds(lowerBound: workweek.lowerBound, upperBound: upperBound)
        case .workweek:
            return Self.workweekBounds(for: date, calendar: calendar)
        case .month:
            let interval = calendar.dateInterval(of: .month, for: date)
                ?? DateInterval(start: calendar.startOfDay(for: date), duration: 86_400)
            return CompletedTaskRangeBounds(lowerBound: interval.start, upperBound: interval.end)
        case .all:
            return CompletedTaskRangeBounds(lowerBound: nil, upperBound: nil)
        }
    }

    private static func workweekBounds(for date: Date, calendar: Calendar) -> CompletedTaskRangeBounds {
        let dayStart = calendar.startOfDay(for: date)
        let weekday = calendar.component(.weekday, from: dayStart)
        let daysSinceMonday = (weekday + 5) % 7
        let monday = calendar.date(byAdding: .day, value: -daysSinceMonday, to: dayStart) ?? dayStart
        let saturday = calendar.date(byAdding: .day, value: 5, to: monday) ?? monday
        return CompletedTaskRangeBounds(lowerBound: monday, upperBound: saturday)
    }
}

struct CompletedTaskRangeBounds: Equatable, Sendable {
    let lowerBound: Date?
    let upperBound: Date?

    var requiredRange: Range<Date> {
        (lowerBound ?? .distantPast)..<(upperBound ?? .distantFuture)
    }
}
