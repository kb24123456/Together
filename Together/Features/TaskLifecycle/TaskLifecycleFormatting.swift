import Foundation

nonisolated enum TaskLifecycleFormatting {
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
