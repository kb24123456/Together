import Foundation

enum ItemRepeatFrequency: String, CaseIterable, Hashable, Sendable, Codable {
    case daily
    case weekly
    case monthly

    var title: String {
        switch self {
        case .daily:
            return "每天"
        case .weekly:
            return "每周"
        case .monthly:
            return "每月"
        }
    }
}

struct ItemRepeatRule: Hashable, Sendable, Codable {
    private enum CodingKeys: String, CodingKey {
        case frequency
        case interval
        case weekday
        case weekdays
        case dayOfMonth
    }

    var frequency: ItemRepeatFrequency
    var interval: Int
    var weekday: Int?
    var weekdays: [Int]?
    var dayOfMonth: Int?

    nonisolated init(
        frequency: ItemRepeatFrequency,
        interval: Int = 1,
        weekday: Int? = nil,
        weekdays: [Int]? = nil,
        dayOfMonth: Int? = nil
    ) {
        self.frequency = frequency
        self.interval = max(1, interval)
        self.weekday = weekday
        self.weekdays = weekdays?.sorted()
        self.dayOfMonth = dayOfMonth
    }

    nonisolated static func == (lhs: ItemRepeatRule, rhs: ItemRepeatRule) -> Bool {
        lhs.frequency == rhs.frequency
            && lhs.interval == rhs.interval
            && lhs.weekday == rhs.weekday
            && lhs.weekdays == rhs.weekdays
            && lhs.dayOfMonth == rhs.dayOfMonth
    }

    nonisolated init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        frequency = try container.decode(ItemRepeatFrequency.self, forKey: .frequency)
        interval = try container.decode(Int.self, forKey: .interval)
        weekday = try container.decodeIfPresent(Int.self, forKey: .weekday)
        weekdays = try container.decodeIfPresent([Int].self, forKey: .weekdays)
        dayOfMonth = try container.decodeIfPresent(Int.self, forKey: .dayOfMonth)
    }

    nonisolated func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(frequency, forKey: .frequency)
        try container.encode(interval, forKey: .interval)
        try container.encodeIfPresent(weekday, forKey: .weekday)
        try container.encodeIfPresent(weekdays, forKey: .weekdays)
        try container.encodeIfPresent(dayOfMonth, forKey: .dayOfMonth)
    }

    nonisolated func title(anchorDate: Date, calendar: Calendar = .current) -> String {
        switch frequency {
        case .daily:
            return "每天"
        case .weekly:
            let configuredWeekdays = resolvedWeekdays(anchorDate: anchorDate, calendar: calendar)
            if configuredWeekdays == [2, 3, 4, 5, 6] {
                return "工作日"
            }
            let title = configuredWeekdays.map(weekdayTitle(for:)).joined(separator: "、")
            if interval == 2 {
                return "每两周\(title)"
            }
            return "每周\(title)"
        case .monthly:
            let targetDay = dayOfMonth ?? calendar.component(.day, from: anchorDate)
            switch interval {
            case 3:
                return "每季度\(targetDay)日"
            case 6:
                return "每半年\(targetDay)日"
            default:
                return "每月\(targetDay)日"
            }
        }
    }

    nonisolated func matches(referenceDate: Date, anchorDate: Date, calendar: Calendar = .current) -> Bool {
        let normalizedReference = calendar.startOfDay(for: referenceDate)
        let normalizedAnchor = calendar.startOfDay(for: anchorDate)

        guard normalizedReference >= normalizedAnchor else {
            return false
        }

        switch frequency {
        case .daily:
            let dayDistance = calendar.dateComponents([.day], from: normalizedAnchor, to: normalizedReference).day ?? 0
            return dayDistance.isMultiple(of: interval)
        case .weekly:
            let configuredWeekdays = resolvedWeekdays(anchorDate: normalizedAnchor, calendar: calendar)
            guard configuredWeekdays.contains(calendar.component(.weekday, from: normalizedReference)) else {
                return false
            }
            let weekDistance = calendar.dateComponents([.weekOfYear], from: normalizedAnchor, to: normalizedReference).weekOfYear ?? 0
            return weekDistance.isMultiple(of: interval)
        case .monthly:
            let targetDay = dayOfMonth ?? calendar.component(.day, from: normalizedAnchor)
            guard calendar.component(.day, from: normalizedReference) == targetDay else {
                return false
            }
            let monthDistance = calendar.dateComponents([.month], from: normalizedAnchor, to: normalizedReference).month ?? 0
            return monthDistance.isMultiple(of: interval)
        }
    }

    private nonisolated func resolvedWeekdays(anchorDate: Date, calendar: Calendar) -> [Int] {
        if let weekdays, weekdays.isEmpty == false {
            return weekdays
        }

        return [weekday ?? calendar.component(.weekday, from: anchorDate)]
    }

    private nonisolated func weekdayTitle(for weekday: Int) -> String {
        switch weekday {
        case 1: return "日"
        case 2: return "一"
        case 3: return "二"
        case 4: return "三"
        case 5: return "四"
        case 6: return "五"
        case 7: return "六"
        default: return "?"
        }
    }
}

extension Item {
    nonisolated var anchorDateForRepeatRule: Date {
        dueAt ?? createdAt
    }

    nonisolated func occurrenceDueDate(on referenceDate: Date, calendar: Calendar = .current) -> Date? {
        guard let dueAt else { return nil }
        guard let repeatRule else { return dueAt }
        guard repeatRule.matches(referenceDate: referenceDate, anchorDate: anchorDateForRepeatRule, calendar: calendar) else {
            return nil
        }

        let dayComponents = calendar.dateComponents([.year, .month, .day], from: referenceDate)
        let timeComponents = calendar.dateComponents([.hour, .minute, .second], from: dueAt)
        return calendar.date(from: DateComponents(
            year: dayComponents.year,
            month: dayComponents.month,
            day: dayComponents.day,
            hour: timeComponents.hour,
            minute: timeComponents.minute,
            second: timeComponents.second
        ))
    }

    nonisolated func occurs(on referenceDate: Date, calendar: Calendar = .current) -> Bool {
        if let repeatRule {
            return repeatRule.matches(referenceDate: referenceDate, anchorDate: anchorDateForRepeatRule, calendar: calendar)
        }

        guard let dueAt else { return false }
        return calendar.isDate(dueAt, inSameDayAs: referenceDate)
    }

    nonisolated func isCompleted(on referenceDate: Date, calendar: Calendar = .current) -> Bool {
        if repeatRule != nil {
            if occurrenceCompletions.contains(where: { calendar.isDate($0.occurrenceDate, inSameDayAs: referenceDate) }) {
                return true
            }

            guard let completedAt else { return false }
            return calendar.isDate(completedAt, inSameDayAs: referenceDate)
        }

        guard completedAt != nil || status == .completed else { return false }

        if let dueAt {
            return calendar.isDate(dueAt, inSameDayAs: referenceDate)
        }

        guard let completedAt else { return false }
        return calendar.isDate(completedAt, inSameDayAs: referenceDate)
    }

    nonisolated func completionDate(on referenceDate: Date, calendar: Calendar = .current) -> Date? {
        if repeatRule != nil {
            if let occurrenceCompletion = occurrenceCompletions.first(where: {
                calendar.isDate($0.occurrenceDate, inSameDayAs: referenceDate)
            }) {
                return occurrenceCompletion.completedAt
            }

            guard let completedAt, calendar.isDate(completedAt, inSameDayAs: referenceDate) else {
                return nil
            }
            return completedAt
        }

        guard let completedAt else { return nil }

        if let dueAt, calendar.isDate(dueAt, inSameDayAs: referenceDate) {
            return completedAt
        }

        guard calendar.isDate(completedAt, inSameDayAs: referenceDate) else { return nil }
        return completedAt
    }

    nonisolated func appearsOnHome(for referenceDate: Date, includeOverdue: Bool, calendar: Calendar = .current) -> Bool {
        if occurs(on: referenceDate, calendar: calendar) {
            return true
        }

        if includeOverdue,
           repeatRule == nil,
           let dueAt,
           dueAt < calendar.startOfDay(for: referenceDate),
           status != .completed
        {
            return true
        }

        return isCompleted(on: referenceDate, calendar: calendar)
    }

    nonisolated func isOverdue(on referenceDate: Date, calendar: Calendar = .current) -> Bool {
        guard isCompleted(on: referenceDate, calendar: calendar) == false else { return false }
        guard status != .completed else { return false }

        if repeatRule != nil {
            guard let dueAt = occurrenceDueDate(on: referenceDate, calendar: calendar) else { return false }
            return dueAt < overdueBoundary(on: referenceDate, calendar: calendar)
        }

        guard let dueAt else { return false }
        return dueAt < overdueBoundary(on: referenceDate, calendar: calendar)
    }

    private nonisolated func overdueBoundary(on referenceDate: Date, calendar: Calendar) -> Date {
        let todayStart = calendar.startOfDay(for: .now)
        let referenceStart = calendar.startOfDay(for: referenceDate)

        if referenceStart < todayStart {
            if hasExplicitTime {
                return calendar.date(byAdding: .day, value: 1, to: referenceStart) ?? referenceDate
            }
            return calendar.date(byAdding: .day, value: 1, to: referenceStart) ?? referenceDate
        }

        if calendar.isDate(referenceDate, inSameDayAs: .now), hasExplicitTime {
            return .now
        }

        return referenceStart
    }
}
