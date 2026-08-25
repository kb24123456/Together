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

nonisolated enum PlanningReviewRange: String, CaseIterable, Sendable {
    case week
    case month

    var title: String { self == .week ? "本周" : "本月" }

    func interval(containing date: Date, calendar: Calendar) -> DateInterval {
        calendar.dateInterval(of: self == .week ? .weekOfYear : .month, for: date)
            ?? DateInterval(start: calendar.startOfDay(for: date), duration: 86_400)
    }
}

nonisolated enum PlanningRiskKind: String, Sendable {
    case overdue
    case postponedUncompleted

    var title: String {
        switch self {
        case .overdue: "已逾期"
        case .postponedUncompleted: "推迟后未完成"
        }
    }
}

nonisolated struct PlanningRiskItem: Identifiable, Equatable, Sendable {
    let id: UUID
    let title: String
    let kind: PlanningRiskKind
    let dueAt: Date?
    let hasExplicitTime: Bool
}

nonisolated enum PlanningNoteworthyReason: Equatable, Sendable {
    case postponed(count: Int, cumulativeDuration: TimeInterval, coverage: TaskLifecycleHistoryCoverage)
    case reopened(count: Int, coverage: TaskLifecycleHistoryCoverage)
    case completionDuration(TimeInterval)
}

nonisolated struct PlanningNoteworthyItem: Identifiable, Equatable, Sendable {
    let id: UUID
    let title: String
    let reason: PlanningNoteworthyReason
}

nonisolated enum PlanningTrendMetric: Equatable, Sendable {
    case medianCompletionDuration
    case firstPlanOnTimeRate
    case postponedProportion
}

nonisolated struct PlanningTrend: Identifiable, Equatable, Sendable {
    let metric: PlanningTrendMetric
    let delta: Double
    var id: String { String(describing: metric) }
}

nonisolated struct PlanningReviewSnapshot: Equatable, Sendable {
    let range: PlanningReviewRange
    let interval: DateInterval
    let completionCount: Int
    let validDurationSampleCount: Int
    let medianCompletionDuration: TimeInterval?
    let firstPlanSampleCount: Int
    let firstPlanOnTimeRate: Double?
    let finalPlanSampleCount: Int
    let finalPlanOnTimeRate: Double?
    let postponementSampleCount: Int
    let postponedCompletionCount: Int
    let postponedProportion: Double?
    let unscheduledCompletionCount: Int
    let riskItems: [PlanningRiskItem]
    let noteworthyItems: [PlanningNoteworthyItem]
    let trends: [PlanningTrend]

    static func empty(range: PlanningReviewRange, referenceDate: Date, calendar: Calendar = .current) -> Self {
        Self(
            range: range,
            interval: range.interval(containing: referenceDate, calendar: calendar),
            completionCount: 0,
            validDurationSampleCount: 0,
            medianCompletionDuration: nil,
            firstPlanSampleCount: 0,
            firstPlanOnTimeRate: nil,
            finalPlanSampleCount: 0,
            finalPlanOnTimeRate: nil,
            postponementSampleCount: 0,
            postponedCompletionCount: 0,
            postponedProportion: nil,
            unscheduledCompletionCount: 0,
            riskItems: [],
            noteworthyItems: [],
            trends: []
        )
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

    static func median(_ values: [TimeInterval]) -> TimeInterval? {
        guard values.isEmpty == false else { return nil }
        let sorted = values.sorted()
        let middle = sorted.count / 2
        if sorted.count.isMultiple(of: 2) {
            return (sorted[middle - 1] + sorted[middle]) / 2
        }
        return sorted[middle]
    }
}
