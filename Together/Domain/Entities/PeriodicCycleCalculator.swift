import Foundation

enum PeriodicCycleCalculator {

    // MARK: - Period Key

    nonisolated static func periodKey(
        for cycle: PeriodicCycle,
        date: Date,
        calendar: Calendar = .current
    ) -> String {
        switch cycle {
        case .weekly:
            let week = calendar.component(.weekOfYear, from: date)
            let year = calendar.component(.yearForWeekOfYear, from: date)
            return String(format: "%04d-W%02d", year, week)

        case .monthly:
            let year = calendar.component(.year, from: date)
            let month = calendar.component(.month, from: date)
            return String(format: "%04d-%02d", year, month)

        case .quarterly:
            let year = calendar.component(.year, from: date)
            let month = calendar.component(.month, from: date)
            let quarter = (month - 1) / 3 + 1
            return String(format: "%04d-Q%d", year, quarter)

        case .yearly:
            let year = calendar.component(.year, from: date)
            return String(format: "%04d", year)
        }
    }

    // MARK: - Period Date Range

    nonisolated static func periodDateRange(
        for cycle: PeriodicCycle,
        date: Date,
        calendar: Calendar = .current
    ) -> (start: Date, end: Date) {
        switch cycle {
        case .weekly:
            let startOfWeek = calendar.dateInterval(of: .weekOfYear, for: date)!.start
            let endOfWeek = calendar.date(byAdding: .day, value: 7, to: startOfWeek)!
            return (startOfWeek, endOfWeek)

        case .monthly:
            let components = calendar.dateComponents([.year, .month], from: date)
            let startOfMonth = calendar.date(from: components)!
            let endOfMonth = calendar.date(byAdding: .month, value: 1, to: startOfMonth)!
            return (startOfMonth, endOfMonth)

        case .quarterly:
            let year = calendar.component(.year, from: date)
            let month = calendar.component(.month, from: date)
            let quarterStartMonth = ((month - 1) / 3) * 3 + 1
            let startOfQuarter = calendar.date(from: DateComponents(year: year, month: quarterStartMonth, day: 1))!
            let endOfQuarter = calendar.date(byAdding: .month, value: 3, to: startOfQuarter)!
            return (startOfQuarter, endOfQuarter)

        case .yearly:
            let year = calendar.component(.year, from: date)
            let startOfYear = calendar.date(from: DateComponents(year: year, month: 1, day: 1))!
            let endOfYear = calendar.date(from: DateComponents(year: year + 1, month: 1, day: 1))!
            return (startOfYear, endOfYear)
        }
    }

    // MARK: - Days Remaining

    nonisolated static func daysRemainingInPeriod(
        for cycle: PeriodicCycle,
        date: Date,
        calendar: Calendar = .current
    ) -> Int {
        let range = periodDateRange(for: cycle, date: date, calendar: calendar)
        let today = calendar.startOfDay(for: date)
        return max(0, calendar.dateComponents([.day], from: today, to: range.end).day ?? 0)
    }

    // MARK: - Total Days in Period

    nonisolated static func totalDaysInPeriod(
        for cycle: PeriodicCycle,
        date: Date,
        calendar: Calendar = .current
    ) -> Int {
        let range = periodDateRange(for: cycle, date: date, calendar: calendar)
        return calendar.dateComponents([.day], from: range.start, to: range.end).day ?? 1
    }

    // MARK: - Period Progress (0.0 to 1.0)

    nonisolated static func periodProgress(
        for cycle: PeriodicCycle,
        date: Date,
        calendar: Calendar = .current
    ) -> Double {
        let total = totalDaysInPeriod(for: cycle, date: date, calendar: calendar)
        let remaining = daysRemainingInPeriod(for: cycle, date: date, calendar: calendar)
        guard total > 0 else { return 1.0 }
        return Double(total - remaining) / Double(total)
    }

    // MARK: - Reminder Trigger Date

    nonisolated static func reminderTriggerDate(
        rule: PeriodicReminderRule,
        cycle: PeriodicCycle,
        date: Date,
        calendar: Calendar = .current
    ) -> Date? {
        let range = periodDateRange(for: cycle, date: date, calendar: calendar)
        return reminderTriggerDate(
            rule: rule,
            periodStart: range.start,
            periodEnd: range.end,
            calendar: calendar
        )
    }

    nonisolated static func reminderTriggerDate(
        rule: PeriodicReminderRule,
        periodStart: Date,
        periodEnd: Date,
        calendar: Calendar = .current
    ) -> Date? {
        var baseDate: Date?

        switch rule.timing {
        case .dayOfPeriod(let day):
            baseDate = calendar.date(byAdding: .day, value: day - 1, to: periodStart)

        case .businessDayOfPeriod(let n):
            baseDate = nthBusinessDay(n, from: periodStart, calendar: calendar)

        case .daysBeforeEnd(let days):
            baseDate = calendar.date(byAdding: .day, value: -days, to: periodEnd)
        }

        guard let base = baseDate else { return nil }

        return calendar.date(bySettingHour: rule.hour, minute: rule.minute, second: 0, of: base)
    }

    // MARK: - Business Day Calculation

    nonisolated static func nthBusinessDay(
        _ n: Int,
        from startDate: Date,
        calendar: Calendar = .current
    ) -> Date? {
        guard n > 0 else { return nil }

        var businessDayCount = 0
        var currentDate = startDate

        while businessDayCount < n {
            let weekday = calendar.component(.weekday, from: currentDate)
            let isWeekend = weekday == 1 || weekday == 7
            if !isWeekend {
                businessDayCount += 1
                if businessDayCount == n {
                    return currentDate
                }
            }
            guard let next = calendar.date(byAdding: .day, value: 1, to: currentDate) else {
                return nil
            }
            currentDate = next
        }

        return nil
    }
}
