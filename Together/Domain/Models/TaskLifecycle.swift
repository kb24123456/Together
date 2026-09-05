import Foundation

nonisolated enum TaskLifecycleEventKind: String, CaseIterable, Sendable, Codable {
    case created
    case firstScheduled
    case postponed
    case movedEarlier
    case scheduleCleared
    case rescheduled
    case completed
    case reopened

    var title: String {
        switch self {
        case .created: "创建任务"
        case .firstScheduled: "首次排期"
        case .postponed: "推迟计划"
        case .movedEarlier: "提前计划"
        case .scheduleCleared: "取消排期"
        case .rescheduled: "重新排期"
        case .completed: "完成任务"
        case .reopened: "恢复为待办"
        }
    }
}

nonisolated struct TaskScheduleSnapshot: Equatable, Sendable {
    let dueAt: Date?
    let hasExplicitTime: Bool
}

nonisolated enum TaskLifecycleEventClassifier {
    static func classifyScheduleChange(
        from old: TaskScheduleSnapshot,
        to new: TaskScheduleSnapshot,
        hasRecordedSchedule: Bool
    ) -> TaskLifecycleEventKind? {
        guard old != new else { return nil }

        switch (old.dueAt, new.dueAt) {
        case (nil, nil):
            return nil
        case (nil, .some):
            return hasRecordedSchedule ? .rescheduled : .firstScheduled
        case (.some, nil):
            return .scheduleCleared
        case let (.some(oldDate), .some(newDate)):
            if newDate > oldDate { return .postponed }
            if newDate < oldDate { return .movedEarlier }
            return old.hasExplicitTime == new.hasExplicitTime ? nil : .rescheduled
        }
    }
}

nonisolated struct TaskLifecycleEvent: Identifiable, Equatable, Sendable {
    let id: UUID
    let taskID: UUID
    let kind: TaskLifecycleEventKind
    let occurredAt: Date
    let oldDueAt: Date?
    let newDueAt: Date?
    let oldHasExplicitTime: Bool?
    let newHasExplicitTime: Bool?
    let incompleteSubtaskCount: Int?
}

nonisolated enum TaskLifecycleHistoryCoverage: Equatable, Sendable {
    case complete
    case sinceFeatureUpdate

    var label: String? {
        switch self {
        case .complete: nil
        case .sinceFeatureUpdate: "更新前未记录"
        }
    }
}

nonisolated struct TaskLifecycleReview: Equatable, Sendable {
    let taskID: UUID
    let title: String
    let createdAt: Date
    let completedAt: Date?
    let currentDueAt: Date?
    let currentHasExplicitTime: Bool
    let historyCoverage: TaskLifecycleHistoryCoverage
    let events: [TaskLifecycleEvent]

    var completionDuration: TimeInterval? {
        guard let completedAt else { return nil }
        return max(0, completedAt.timeIntervalSince(createdAt))
    }

    var firstCompletedAt: Date? {
        events.first(where: { $0.kind == .completed })?.occurredAt ?? completedAt
    }

    var postponeCount: Int {
        events.count(where: { $0.kind == .postponed })
    }

    var cumulativePostponement: TimeInterval {
        events.reduce(0) { result, event in
            guard event.kind == .postponed,
                  let oldDueAt = event.oldDueAt,
                  let newDueAt = event.newDueAt
            else { return result }
            return result + max(0, newDueAt.timeIntervalSince(oldDueAt))
        }
    }

    var reopenCount: Int {
        events.count(where: { $0.kind == .reopened })
    }

    var firstSchedule: TaskScheduleSnapshot? {
        guard let event = events.first(where: { $0.kind == .firstScheduled }),
              let dueAt = event.newDueAt
        else { return nil }
        return TaskScheduleSnapshot(
            dueAt: dueAt,
            hasExplicitTime: event.newHasExplicitTime ?? false
        )
    }

    var finalSchedule: TaskScheduleSnapshot? {
        if let completionEvent = events.last(where: { $0.kind == .completed }),
           let dueAt = completionEvent.newDueAt {
            return TaskScheduleSnapshot(
                dueAt: dueAt,
                hasExplicitTime: completionEvent.newHasExplicitTime ?? false
            )
        }
        guard let currentDueAt else { return nil }
        return TaskScheduleSnapshot(dueAt: currentDueAt, hasExplicitTime: currentHasExplicitTime)
    }

    var finalPlanDrift: TimeInterval? {
        guard let first = firstSchedule?.dueAt, let final = finalSchedule?.dueAt else { return nil }
        return final.timeIntervalSince(first)
    }
}

nonisolated enum ExecutionReviewRange: String, CaseIterable, Sendable {
    case week
    case month

    var title: String { self == .week ? "本周" : "本月" }

    func includesCompletion(_ date: Date, in interval: DateInterval, calendar: Calendar) -> Bool {
        guard date >= interval.start, date <= interval.end else { return false }
        // A reference-time cutoff is inclusive; a natural-period end belongs
        // to the next period, even when the shorter previous month is clamped.
        return date < fullInterval(containing: interval.start, calendar: calendar).end
    }

    func interval(through referenceDate: Date, calendar: Calendar) -> DateInterval {
        let fullInterval = fullInterval(containing: referenceDate, calendar: calendar)
        return DateInterval(
            start: fullInterval.start,
            end: min(max(referenceDate, fullInterval.start), fullInterval.end)
        )
    }

    func previousComparableInterval(through referenceDate: Date, calendar: Calendar) -> DateInterval {
        let current = fullInterval(containing: referenceDate, calendar: calendar)
        guard let previousStart = calendar.date(
            byAdding: self == .week ? .weekOfYear : .month,
            value: -1,
            to: current.start
        ) else {
            return DateInterval(start: current.start, end: current.start)
        }

        let previousFull = fullInterval(containing: previousStart, calendar: calendar)
        let currentDay = calendar.startOfDay(for: referenceDate)
        let dayOffset = max(
            0,
            calendar.dateComponents([.day], from: current.start, to: currentDay).day ?? 0
        )
        guard let previousMatchedDay = calendar.date(
            byAdding: .day,
            value: dayOffset,
            to: previousFull.start
        ) else {
            return previousFull
        }

        let timeComponents = calendar.dateComponents(
            [.hour, .minute, .second, .nanosecond],
            from: referenceDate
        )
        let matchedEnd = calendar.date(byAdding: timeComponents, to: previousMatchedDay)
            ?? previousMatchedDay

        return DateInterval(
            start: previousFull.start,
            end: min(max(matchedEnd, previousFull.start), previousFull.end)
        )
    }

    private func fullInterval(containing date: Date, calendar: Calendar) -> DateInterval {
        calendar.dateInterval(of: self == .week ? .weekOfYear : .month, for: date)
            ?? DateInterval(
                start: calendar.startOfDay(for: date),
                end: calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: date))
                    ?? date
            )
    }
}

nonisolated enum ExecutionReviewNoteworthyReason: Equatable, Sendable {
    case postponed(count: Int, cumulativeDuration: TimeInterval, coverage: TaskLifecycleHistoryCoverage)
    case reopened(count: Int, coverage: TaskLifecycleHistoryCoverage)
    case missedFirstPlan(completedAt: Date, schedule: TaskScheduleSnapshot)
}

nonisolated struct ExecutionReviewNoteworthyItem: Identifiable, Equatable, Sendable {
    let id: UUID
    let title: String
    let reason: ExecutionReviewNoteworthyReason
}

nonisolated enum ExecutionReviewTrendMetric: Equatable, Sendable {
    case firstPlanOnTimeRate
    case postponedProportion
}

nonisolated struct ExecutionReviewTrend: Identifiable, Equatable, Sendable {
    let metric: ExecutionReviewTrendMetric
    let currentCount: Int
    let currentSampleCount: Int
    let previousCount: Int
    let previousSampleCount: Int
    var id: String { String(describing: metric) }
}

nonisolated struct ExecutionReviewCompletedItem: Identifiable, Equatable, Sendable {
    let id: UUID
    let title: String
    let completedAt: Date
}

nonisolated struct ExecutionReviewSnapshot: Equatable, Sendable {
    let range: ExecutionReviewRange
    let interval: DateInterval
    let completedItems: [ExecutionReviewCompletedItem]
    let firstPlanSampleCount: Int
    let firstPlanOnTimeCount: Int
    let postponementSampleCount: Int
    let postponedCompletionCount: Int
    let noteworthyItems: [ExecutionReviewNoteworthyItem]
    let trends: [ExecutionReviewTrend]

    var completionCount: Int { completedItems.count }

    var firstPlanOnTimeRate: Double? {
        Self.rate(matchingCount: firstPlanOnTimeCount, sampleCount: firstPlanSampleCount)
    }

    var postponedProportion: Double? {
        Self.rate(matchingCount: postponedCompletionCount, sampleCount: postponementSampleCount)
    }

    static func empty(
        range: ExecutionReviewRange,
        referenceDate: Date,
        calendar: Calendar = .current
    ) -> Self {
        Self(
            range: range,
            interval: range.interval(through: referenceDate, calendar: calendar),
            completedItems: [],
            firstPlanSampleCount: 0,
            firstPlanOnTimeCount: 0,
            postponementSampleCount: 0,
            postponedCompletionCount: 0,
            noteworthyItems: [],
            trends: []
        )
    }

    private static func rate(matchingCount: Int, sampleCount: Int) -> Double? {
        guard sampleCount > 0 else { return nil }
        return Double(matchingCount) / Double(sampleCount)
    }
}

nonisolated enum TaskLifecycleMetrics {
    static func isOnTime(
        completedAt: Date,
        schedule: TaskScheduleSnapshot,
        calendar: Calendar
    ) -> Bool {
        guard let dueAt = schedule.dueAt else { return false }
        if schedule.hasExplicitTime {
            return completedAt <= dueAt
        }
        let endOfDueDay = calendar.date(
            byAdding: .day,
            value: 1,
            to: calendar.startOfDay(for: dueAt)
        ) ?? dueAt
        return completedAt < endOfDueDay
    }

    static func missedPlanMagnitude(
        completedAt: Date,
        schedule: TaskScheduleSnapshot,
        calendar: Calendar
    ) -> TimeInterval? {
        guard let dueAt = schedule.dueAt,
              isOnTime(completedAt: completedAt, schedule: schedule, calendar: calendar) == false
        else { return nil }

        if schedule.hasExplicitTime {
            return max(0, completedAt.timeIntervalSince(dueAt))
        }

        let dueDay = calendar.startOfDay(for: dueAt)
        let completionDay = calendar.startOfDay(for: completedAt)
        let calendarDays = max(
            1,
            calendar.dateComponents([.day], from: dueDay, to: completionDay).day ?? 1
        )
        return Double(calendarDays) * 86_400
    }
}

nonisolated enum ExecutionReviewMetrics {
    static let minimumTrendSampleCount = 5

    static func snapshot(
        range: ExecutionReviewRange,
        interval: DateInterval,
        currentReviews: [TaskLifecycleReview],
        previousReviews: [TaskLifecycleReview],
        calendar: Calendar
    ) -> ExecutionReviewSnapshot {
        let current = periodMetrics(for: currentReviews, calendar: calendar)
        let previous = periodMetrics(for: previousReviews, calendar: calendar)
        var trends: [ExecutionReviewTrend] = []

        if current.firstPlanSampleCount >= minimumTrendSampleCount,
           previous.firstPlanSampleCount >= minimumTrendSampleCount {
            trends.append(ExecutionReviewTrend(
                metric: .firstPlanOnTimeRate,
                currentCount: current.firstPlanOnTimeCount,
                currentSampleCount: current.firstPlanSampleCount,
                previousCount: previous.firstPlanOnTimeCount,
                previousSampleCount: previous.firstPlanSampleCount
            ))
        }

        if current.postponementSampleCount >= minimumTrendSampleCount,
           previous.postponementSampleCount >= minimumTrendSampleCount {
            trends.append(ExecutionReviewTrend(
                metric: .postponedProportion,
                currentCount: current.postponedCompletionCount,
                currentSampleCount: current.postponementSampleCount,
                previousCount: previous.postponedCompletionCount,
                previousSampleCount: previous.postponementSampleCount
            ))
        }

        return ExecutionReviewSnapshot(
            range: range,
            interval: interval,
            completedItems: currentReviews.compactMap { review in
                guard let completedAt = review.completedAt else { return nil }
                return ExecutionReviewCompletedItem(
                    id: review.taskID,
                    title: review.title,
                    completedAt: completedAt
                )
            }.sorted { lhs, rhs in
                if lhs.completedAt != rhs.completedAt { return lhs.completedAt > rhs.completedAt }
                return lhs.id.uuidString < rhs.id.uuidString
            },
            firstPlanSampleCount: current.firstPlanSampleCount,
            firstPlanOnTimeCount: current.firstPlanOnTimeCount,
            postponementSampleCount: current.postponementSampleCount,
            postponedCompletionCount: current.postponedCompletionCount,
            noteworthyItems: noteworthyItems(from: currentReviews, calendar: calendar),
            trends: trends
        )
    }

    private struct PeriodMetrics {
        let firstPlanSampleCount: Int
        let firstPlanOnTimeCount: Int
        let postponementSampleCount: Int
        let postponedCompletionCount: Int
    }

    private static func periodMetrics(
        for reviews: [TaskLifecycleReview],
        calendar: Calendar
    ) -> PeriodMetrics {
        let completeHistory = reviews.filter { $0.historyCoverage == .complete }
        let firstPlanResults = completeHistory.compactMap { review -> Bool? in
            guard let completedAt = review.completedAt,
                  let schedule = review.firstSchedule
            else { return nil }
            return TaskLifecycleMetrics.isOnTime(
                completedAt: completedAt,
                schedule: schedule,
                calendar: calendar
            )
        }

        return PeriodMetrics(
            firstPlanSampleCount: firstPlanResults.count,
            firstPlanOnTimeCount: firstPlanResults.count(where: { $0 }),
            postponementSampleCount: completeHistory.count,
            postponedCompletionCount: completeHistory.count(where: { $0.postponeCount > 0 })
        )
    }

    private static func noteworthyItems(
        from reviews: [TaskLifecycleReview],
        calendar: Calendar
    ) -> [ExecutionReviewNoteworthyItem] {
        let candidates = reviews.compactMap { review -> ExecutionReviewNoteworthyItem? in
            if review.reopenCount > 0 {
                return ExecutionReviewNoteworthyItem(
                    id: review.taskID,
                    title: review.title,
                    reason: .reopened(
                        count: review.reopenCount,
                        coverage: review.historyCoverage
                    )
                )
            }

            if review.postponeCount >= 2 {
                return ExecutionReviewNoteworthyItem(
                    id: review.taskID,
                    title: review.title,
                    reason: .postponed(
                        count: review.postponeCount,
                        cumulativeDuration: review.cumulativePostponement,
                        coverage: review.historyCoverage
                    )
                )
            }

            guard review.historyCoverage == .complete,
                  let completedAt = review.completedAt,
                  let schedule = review.firstSchedule,
                  TaskLifecycleMetrics.missedPlanMagnitude(
                      completedAt: completedAt,
                      schedule: schedule,
                      calendar: calendar
                  ) != nil
            else { return nil }

            return ExecutionReviewNoteworthyItem(
                id: review.taskID,
                title: review.title,
                reason: .missedFirstPlan(completedAt: completedAt, schedule: schedule)
            )
        }
        .sorted { lhs, rhs in
            isHigherPriority(lhs, than: rhs, calendar: calendar)
        }
        // Represent each observed kind of change before filling spare slots.
        // A task still has exactly one reason, so it cannot appear twice.
        var representedPriorities: Set<Int> = []
        var selected = candidates.filter {
            representedPriorities.insert(priority(of: $0.reason)).inserted
        }
        let selectedIDs = Set(selected.map(\.id))
        selected.append(contentsOf: candidates.filter { selectedIDs.contains($0.id) == false }
            .prefix(max(0, 3 - selected.count)))
        return selected
    }

    private static func isHigherPriority(
        _ lhs: ExecutionReviewNoteworthyItem,
        than rhs: ExecutionReviewNoteworthyItem,
        calendar: Calendar
    ) -> Bool {
        let lhsPriority = priority(of: lhs.reason)
        let rhsPriority = priority(of: rhs.reason)
        if lhsPriority != rhsPriority { return lhsPriority > rhsPriority }

        switch (lhs.reason, rhs.reason) {
        case let (.reopened(lhsCount, _), .reopened(rhsCount, _)):
            if lhsCount != rhsCount { return lhsCount > rhsCount }
        case let (
            .postponed(lhsCount, lhsDuration, _),
            .postponed(rhsCount, rhsDuration, _)
        ):
            if lhsCount != rhsCount { return lhsCount > rhsCount }
            if lhsDuration != rhsDuration { return lhsDuration > rhsDuration }
        case let (
            .missedFirstPlan(lhsCompletedAt, lhsSchedule),
            .missedFirstPlan(rhsCompletedAt, rhsSchedule)
        ):
            let lhsMagnitude = TaskLifecycleMetrics.missedPlanMagnitude(
                completedAt: lhsCompletedAt,
                schedule: lhsSchedule,
                calendar: calendar
            ) ?? 0
            let rhsMagnitude = TaskLifecycleMetrics.missedPlanMagnitude(
                completedAt: rhsCompletedAt,
                schedule: rhsSchedule,
                calendar: calendar
            ) ?? 0
            if lhsMagnitude != rhsMagnitude { return lhsMagnitude > rhsMagnitude }
        default:
            break
        }

        return lhs.id.uuidString < rhs.id.uuidString
    }

    private static func priority(of reason: ExecutionReviewNoteworthyReason) -> Int {
        switch reason {
        case .reopened: 3
        case .postponed: 2
        case .missedFirstPlan: 1
        }
    }
}
