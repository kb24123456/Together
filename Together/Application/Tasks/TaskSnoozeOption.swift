import Foundation

nonisolated enum TaskSnoozeOption: Sendable, Hashable {
    case tomorrow
    case nextMonday
    case minutes(Int)
    case custom(date: Date, hasExplicitTime: Bool)
}

nonisolated enum TaskSnoozeDateCalculator {
    static func dueDate(
        currentDueAt: Date?,
        hasExplicitTime: Bool,
        option: TaskSnoozeOption,
        now: Date,
        calendar: Calendar
    ) -> Date {
        switch option {
        case .tomorrow:
            let tomorrow = calendar.date(byAdding: .day, value: 1, to: now) ?? now
            return datePreservingTime(
                currentDueAt: currentDueAt,
                hasExplicitTime: hasExplicitTime,
                targetDay: tomorrow,
                calendar: calendar
            )
        case .nextMonday:
            let weekday = calendar.component(.weekday, from: now)
            let daysUntilMonday = (9 - weekday) % 7
            let positiveDaysUntilMonday = daysUntilMonday == 0 ? 7 : daysUntilMonday
            let monday = calendar.date(byAdding: .day, value: positiveDaysUntilMonday, to: now) ?? now
            return datePreservingTime(
                currentDueAt: currentDueAt,
                hasExplicitTime: hasExplicitTime,
                targetDay: monday,
                calendar: calendar
            )
        case let .minutes(minutes):
            let baseDate = currentDueAt.map { max($0, now) } ?? now
            let future = baseDate.addingTimeInterval(TimeInterval(minutes * 60))
            let roundedMinute = Int((Double(calendar.component(.minute, from: future)) / 5.0).rounded()) * 5
            let minuteOverflow = roundedMinute / 60
            let normalizedMinute = roundedMinute % 60
            let normalizedHour = (calendar.component(.hour, from: future) + minuteOverflow) % 24
            return calendar.date(
                bySettingHour: normalizedHour,
                minute: normalizedMinute,
                second: 0,
                of: future
            ) ?? future
        case let .custom(date, _):
            return date
        }
    }

    private static func datePreservingTime(
        currentDueAt: Date?,
        hasExplicitTime: Bool,
        targetDay: Date,
        calendar: Calendar
    ) -> Date {
        let dayStart = calendar.startOfDay(for: targetDay)
        guard hasExplicitTime, let currentDueAt else { return dayStart }
        let time = calendar.dateComponents([.hour, .minute], from: currentDueAt)
        return calendar.date(
            bySettingHour: time.hour ?? 0,
            minute: time.minute ?? 0,
            second: 0,
            of: dayStart
        ) ?? dayStart
    }
}
