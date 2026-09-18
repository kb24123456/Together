import Foundation

/// Presentation values only; recurrence evaluation remains in the existing calculator.
struct PeriodicDayPickerOption: Identifiable, Equatable {
    let timing: PeriodicReminderRule.Timing
    let label: String
    let title: String
    var id: PeriodicReminderRule.Timing { timing }
}

enum PeriodicSchedulePickerValues {
    static func displayedTiming(
        _ timing: PeriodicReminderRule.Timing?, cycle: PeriodicCycle
    ) -> PeriodicReminderRule.Timing? {
        // Match the existing editor's interpretation without rewriting stored rules.
        if cycle == .monthly, case .dayOfPeriod(let day) = timing, day >= 31 {
            return .daysBeforeEnd(1)
        }
        return timing
    }

    static func days(
        cycle: PeriodicCycle,
        selected: PeriodicReminderRule.Timing?,
        calendar: Calendar = .current
    ) -> [PeriodicDayPickerOption] {
        let count: Int
        switch cycle {
        case .daily: return []
        case .weekly: count = 7
        case .monthly: count = 30
        case .quarterly: count = 90
        case .yearly: count = 0
        }
        var options = (0..<count).map { index -> PeriodicDayPickerOption in
            let day = index + 1
            let title: String
            switch cycle {
            case .weekly:
                let names = ["周日", "周一", "周二", "周三", "周四", "周五", "周六"]
                title = names[(calendar.firstWeekday + day - 2) % 7]
            case .monthly: title = "\(day)号"
            default: title = "第\(day)天"
            }
            return PeriodicDayPickerOption(
                timing: .dayOfPeriod(day),
                label: cycle == .weekly ? title : "\(day)",
                title: title
            )
        }
        if cycle == .yearly {
            options = [
                .init(timing: .dayOfPeriod(1), label: "年初", title: "年初"),
                .init(timing: .daysBeforeEnd(1), label: "年末", title: "年末"),
                .init(timing: .businessDayOfPeriod(1), label: "首个工作日", title: "首个工作日"),
                .init(timing: .lastBusinessDay, label: "最后工作日", title: "最后工作日"),
                .init(timing: .daysBeforeEnd(30), label: "年末前30天", title: "年末前30天")
            ]
        } else if cycle != .weekly {
            options.append(.init(
                timing: .daysBeforeEnd(1),
                label: cycle == .monthly ? "月末" : "末日",
                title: "最后一天"
            ))
        }
        if let selected = displayedTiming(selected, cycle: cycle),
           !options.contains(where: { $0.timing == selected }) {
            let title = specialTitle(selected)
            options.append(.init(timing: selected, label: cycle == .yearly ? "已有日期" : title, title: title))
        }
        return options
    }

    static func specialTitle(_ timing: PeriodicReminderRule.Timing) -> String {
        switch timing {
        case .dayOfPeriod(let day): return "第\(day)天"
        case .businessDayOfPeriod(1): return "首个工作日"
        case .businessDayOfPeriod(let day): return "第\(day)工作日"
        case .daysBeforeEnd(1): return "最后一天"
        case .daysBeforeEnd(let days): return "结束前\(days)天"
        case .lastBusinessDay: return "最后工作日"
        case .weekdayOfMonth(let ordinal, let weekday):
            let names = ["周日", "周一", "周二", "周三", "周四", "周五", "周六"]
            return ordinal.title + names[max(1, min(7, weekday)) - 1]
        }
    }
}

/// A recurring hour/minute is a wall-clock value, not a date or a UTC instant.
/// This neutral day exposes all 288 choices even on today's DST transition.
/// Only hour/minute leave this adapter; the recurrence scheduler still uses local time.
enum PeriodicTimePickerValue {
    static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .gmt
        return calendar
    }

    static var referenceDay: Date {
        Date(timeIntervalSinceReferenceDate: 14 * 86_400)
    }

    static func date(hour: Int, minute: Int) -> Date {
        calendar.date(
            bySettingHour: max(0, min(23, hour)),
            minute: max(0, min(59, minute)), second: 0, of: referenceDay
        ) ?? referenceDay
    }

    static func draft(rule: PeriodicReminderRule?) -> ExistingTaskScheduleDraft {
        let time: Date?
        if let hour = rule?.hour, let minute = rule?.minute {
            time = date(hour: hour, minute: minute)
        } else {
            time = nil
        }
        return ExistingTaskScheduleDraft(
            dueAt: time,
            hasExplicitTime: time != nil,
            fallbackDate: referenceDay,
            calendar: calendar
        )
    }

    static func seed(now: Date = .now, localCalendar: Calendar = .current) -> Date {
        date(hour: localCalendar.component(.hour, from: now), minute: localCalendar.component(.minute, from: now))
    }
}
