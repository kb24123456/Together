import Foundation

struct TodayWidgetSnapshotBuilder: Sendable {
    private let calendar: Calendar

    nonisolated init(calendar: Calendar = .current) {
        self.calendar = calendar
    }

    nonisolated func build(
        items: [Item],
        referenceDate: Date,
        limit: Int = 3
    ) -> TodayWidgetSnapshot {
        let dayStart = calendar.startOfDay(for: referenceDate)
        let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) ?? referenceDate
        let incompleteToday = items.filter {
            isIncomplete($0, on: referenceDate)
                && belongsToToday($0, referenceDate: referenceDate, dayEnd: dayEnd)
        }
        let sorted = incompleteToday.sorted {
            isHigherPriority($0, than: $1, referenceDate: referenceDate)
        }
        let completedTodayCount = items.filter {
            belongsToToday($0, referenceDate: referenceDate, dayEnd: dayEnd)
                && $0.completionDate(on: referenceDate, calendar: calendar) != nil
        }.count
        let overdueCount = incompleteToday.filter {
            $0.isOverdue(on: referenceDate, calendar: calendar)
        }.count

        return TodayWidgetSnapshot(
            generatedAt: .now,
            referenceDate: referenceDate,
            remainingCount: sorted.count,
            completedTodayCount: completedTodayCount,
            overdueCount: overdueCount,
            tasks: Array(sorted.prefix(max(limit, 1))).enumerated().map { index, item in
                taskSnapshot(for: item, referenceDate: referenceDate, sortIndex: index)
            },
            nextUpcomingTask: nextUpcomingTask(
                from: items,
                referenceDate: referenceDate,
                dayEnd: dayEnd
            )
        )
    }

    private nonisolated func isIncomplete(_ item: Item, on referenceDate: Date) -> Bool {
        item.isCompleted(on: referenceDate, calendar: calendar) == false && item.status != .completed
    }

    private nonisolated func belongsToToday(
        _ item: Item,
        referenceDate: Date,
        dayEnd: Date
    ) -> Bool {
        guard let dueDate = timelineSortDate(for: item, referenceDate: referenceDate) else {
            return false
        }
        return dueDate < dayEnd
    }

    private nonisolated func timelineSortDate(for item: Item, referenceDate: Date) -> Date? {
        if item.repeatRule != nil {
            return item.occurrenceDueDate(on: referenceDate, calendar: calendar)
        }
        return item.dueAt
    }

    private nonisolated func isHigherPriority(
        _ lhs: Item,
        than rhs: Item,
        referenceDate: Date
    ) -> Bool {
        let lhsOverdue = lhs.isOverdue(on: referenceDate, calendar: calendar)
        let rhsOverdue = rhs.isOverdue(on: referenceDate, calendar: calendar)
        if lhsOverdue != rhsOverdue { return lhsOverdue }
        if lhs.isUrgent != rhs.isUrgent { return lhs.isUrgent }

        let lhsDueAt = timelineSortDate(for: lhs, referenceDate: referenceDate) ?? .distantFuture
        let rhsDueAt = timelineSortDate(for: rhs, referenceDate: referenceDate) ?? .distantFuture
        if lhsDueAt != rhsDueAt { return lhsDueAt < rhsDueAt }
        if lhs.sortOrder != rhs.sortOrder { return lhs.sortOrder < rhs.sortOrder }
        if lhs.createdAt != rhs.createdAt { return lhs.createdAt < rhs.createdAt }
        return lhs.id.uuidString < rhs.id.uuidString
    }

    private nonisolated func taskSnapshot(
        for item: Item,
        referenceDate: Date,
        sortIndex: Int
    ) -> TodayWidgetTaskSnapshot {
        let isOverdue = item.isOverdue(on: referenceDate, calendar: calendar)
        return TodayWidgetTaskSnapshot(
            id: item.id,
            title: item.title,
            dueTimeText: todayScheduleText(
                for: item,
                referenceDate: referenceDate,
                isOverdue: isOverdue
            ),
            sortIndex: sortIndex,
            isOverdue: isOverdue
        )
    }

    private nonisolated func todayScheduleText(
        for item: Item,
        referenceDate: Date,
        isOverdue: Bool
    ) -> String? {
        let dueAt = item.occurrenceDueDate(on: referenceDate, calendar: calendar) ?? item.dueAt
        let timeText = dueAt.flatMap { date in
            item.hasExplicitTime
                ? date.formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits))
                : nil
        }
        guard isOverdue else { return timeText }
        return ["逾期", timeText].compactMap { $0 }.joined(separator: " ")
    }

    private nonisolated func nextUpcomingTask(
        from items: [Item],
        referenceDate: Date,
        dayEnd: Date
    ) -> TodayWidgetTaskSnapshot? {
        let candidates = items.compactMap { item -> (Item, Date)? in
            guard isIncomplete(item, on: referenceDate) else { return nil }
            guard let nextDate = nextScheduledDate(for: item, from: dayEnd) else { return nil }
            return (item, nextDate)
        }.sorted { lhs, rhs in
            if lhs.1 != rhs.1 { return lhs.1 < rhs.1 }
            if lhs.0.isUrgent != rhs.0.isUrgent { return lhs.0.isUrgent }
            return lhs.0.createdAt < rhs.0.createdAt
        }

        guard let (item, dueDate) = candidates.first else { return nil }
        return TodayWidgetTaskSnapshot(
            id: item.id,
            title: item.title,
            dueTimeText: upcomingScheduleText(
                for: dueDate,
                referenceDate: referenceDate,
                hasExplicitTime: item.hasExplicitTime
            ),
            sortIndex: 0
        )
    }

    private nonisolated func nextScheduledDate(for item: Item, from dayEnd: Date) -> Date? {
        guard let repeatRule = item.repeatRule else {
            guard let dueAt = item.dueAt, dueAt >= dayEnd else { return nil }
            return dueAt
        }

        for offset in 0..<366 {
            guard let candidate = calendar.date(byAdding: .day, value: offset, to: dayEnd) else {
                continue
            }
            if repeatRule.matches(
                referenceDate: candidate,
                anchorDate: item.anchorDateForRepeatRule,
                calendar: calendar
            ) {
                let dayComponents = calendar.dateComponents([.year, .month, .day], from: candidate)
                let timeComponents = calendar.dateComponents([.hour, .minute, .second], from: item.dueAt ?? candidate)
                return calendar.date(from: DateComponents(
                    year: dayComponents.year,
                    month: dayComponents.month,
                    day: dayComponents.day,
                    hour: timeComponents.hour,
                    minute: timeComponents.minute,
                    second: timeComponents.second
                ))
            }
        }
        return nil
    }

    private nonisolated func upcomingScheduleText(
        for date: Date,
        referenceDate: Date,
        hasExplicitTime: Bool
    ) -> String {
        let tomorrow = calendar.date(
            byAdding: .day,
            value: 1,
            to: calendar.startOfDay(for: referenceDate)
        )
        let dateText = tomorrow.map { calendar.isDate(date, inSameDayAs: $0) } == true
            ? "明天"
            : date.formatted(.dateTime.month().day())
        guard hasExplicitTime else { return dateText }
        let timeText = date.formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits))
        return "\(dateText) \(timeText)"
    }
}
