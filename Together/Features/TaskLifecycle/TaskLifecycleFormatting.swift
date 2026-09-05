import Foundation

nonisolated enum TaskLifecycleFormatting {
    static func executionSummary(_ snapshot: ExecutionReviewSnapshot) -> String {
        guard snapshot.completionCount > 0 else {
            return "\(snapshot.range.title)还没有完成任务"
        }
        return "\(snapshot.range.title)完成 \(snapshot.completionCount) 项"
    }

    static func firstScheduleSummary(_ snapshot: ExecutionReviewSnapshot) -> String {
        guard snapshot.firstPlanSampleCount > 0 else {
            return "暂无可判断首次安排的记录"
        }
        return "\(snapshot.firstPlanSampleCount) 项可判断首次安排，其中 \(snapshot.firstPlanOnTimeCount) 项按首次安排完成"
    }

    static func executionComparison(_ trend: ExecutionReviewTrend, range: ExecutionReviewRange) -> String {
        let title = switch trend.metric {
        case .firstPlanOnTimeRate: "按首次安排完成"
        case .postponedProportion: "曾向后调整"
        }
        let previous = range == .week ? "上周同期" : "上月同期"
        return "\(title)：\(range.title) \(trend.currentCount)/\(trend.currentSampleCount)，\(previous) \(trend.previousCount)/\(trend.previousSampleCount)"
    }

    static func duration(_ interval: TimeInterval) -> String {
        let minutes = max(0, Int(interval / 60))
        let days = minutes / 1_440
        let hours = (minutes % 1_440) / 60
        let remainingMinutes = minutes % 60
        if days > 0 { return hours > 0 ? "\(days)天\(hours)小时" : "\(days)天" }
        if hours > 0 { return remainingMinutes > 0 ? "\(hours)小时\(remainingMinutes)分钟" : "\(hours)小时" }
        return "\(remainingMinutes)分钟"
    }

    static func relativeDuration(since date: Date, referenceDate: Date = .now) -> String {
        duration(max(0, referenceDate.timeIntervalSince(date)))
    }

    static func planDelay(
        completedAt: Date,
        schedule: TaskScheduleSnapshot,
        calendar: Calendar = .current
    ) -> String {
        guard let dueAt = schedule.dueAt else { return "—" }
        if schedule.hasExplicitTime {
            let delay = max(0, completedAt.timeIntervalSince(dueAt))
            return delay < 60 ? "不到1分钟" : duration(delay)
        }

        let dueDay = calendar.startOfDay(for: dueAt)
        let completionDay = calendar.startOfDay(for: completedAt)
        let days = max(
            1,
            calendar.dateComponents([.day], from: dueDay, to: completionDay).day ?? 1
        )
        return "\(days)天"
    }

    static func dateTime(_ date: Date) -> String {
        date.formatted(
            Date.FormatStyle(date: .abbreviated, time: .shortened)
                .locale(Locale(identifier: "zh_CN"))
        )
    }

    static func schedule(_ date: Date?, hasExplicitTime: Bool) -> String {
        guard let date else { return "未排期" }
        if hasExplicitTime { return dateTime(date) }
        return date.formatted(
            Date.FormatStyle(date: .abbreviated, time: .omitted)
                .locale(Locale(identifier: "zh_CN"))
        )
    }

    static func eventDetail(_ event: TaskLifecycleEvent) -> String? {
        switch event.kind {
        case .created, .reopened:
            return nil
        case .firstScheduled, .rescheduled:
            return schedule(
                event.newDueAt,
                hasExplicitTime: event.newHasExplicitTime ?? false
            )
        case .postponed, .movedEarlier:
            let old = schedule(event.oldDueAt, hasExplicitTime: event.oldHasExplicitTime ?? false)
            let new = schedule(event.newDueAt, hasExplicitTime: event.newHasExplicitTime ?? false)
            return "\(old) → \(new)"
        case .scheduleCleared:
            return schedule(event.oldDueAt, hasExplicitTime: event.oldHasExplicitTime ?? false)
        case .completed:
            guard let count = event.incompleteSubtaskCount, count > 0 else { return nil }
            return "完成时仍有 \(count) 项子任务未完成"
        }
    }
}
